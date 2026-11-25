#!/usr/bin/env python3
"""
Independently checks HamBands' band privilege data against the FCC rules on eCFR.

It downloads 47 CFR §97.301 (frequency privileges by class), §97.305 (emission types)
and §97.303 (60 m channels) for the latest eCFR date, parses the tables itself, and
compares them, frequency by frequency and class by class, with the JSON the app's
own Swift code exports. It shares no data with the app: if either side is wrong,
the check fails.

Usage: run verify_band_plan.sh (it builds the export and runs this script).
Exit code 0 = everything matches, 1 = a mismatch was found.
"""
import html
import json
import re
import subprocess
import sys
from html.parser import HTMLParser

API = "https://www.ecfr.gov/api/versioner/v1"
CLASSES = ["technician", "general", "advanced", "extra"]
RANK = {c: i for i, c in enumerate(CLASSES)}
# §97.301 paragraph -> which classes that table grants (Region 2 column).
PARAGRAPH_CLASSES = {
    "a": set(CLASSES),
    "b": {"extra"},
    "c": {"advanced"},
    "d": {"general"},
    "e": {"technician"},
}
UNIT_KHZ = {"kHz": 1, "MHz": 1_000, "GHz": 1_000_000}
EPS = 1e-6

failures = []


def fail(msg):
    failures.append(msg)


def fetch(url):
    # The system curl uses macOS's certificate store (python.org builds often have none).
    result = subprocess.run(["curl", "-sSf", "--compressed", "--max-time", "60", url],
                            capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"Could not download {url}: {result.stderr.strip()}")
    return result.stdout


# ---------------------------------------------------------------- table parsing

class Tables(HTMLParser):
    """Collects (preceding paragraph text, rows) for every table in an eCFR section."""

    def __init__(self):
        super().__init__()
        self.tables, self.last_p, self._p = [], "", None
        self._rows = self._row = self._cell = None

    def handle_starttag(self, tag, attrs):
        if tag == "p" and self._rows is None:
            self._p = ""
        elif tag == "table":
            self._rows = []
        elif tag == "tr" and self._rows is not None:
            self._row = []
        elif tag in ("td", "th") and self._row is not None:
            self._cell = ""

    def handle_endtag(self, tag):
        if tag == "p" and self._p is not None:
            self.last_p, self._p = self._p.strip(), None
        elif tag == "table":
            self.tables.append((self.last_p, self._rows))
            self._rows = None
        elif tag == "tr" and self._row is not None:
            self._rows.append(self._row)
            self._row = None
        elif tag in ("td", "th") and self._cell is not None:
            self._row.append(re.sub(r"\s+", " ", html.unescape(self._cell)).strip())
            self._cell = None

    def handle_data(self, data):
        if self._cell is not None:
            self._cell += data
        elif self._p is not None:
            self._p += data


def parse_tables(xml):
    p = Tables()
    p.feed(xml)
    return p.tables


def parse_range(text, unit):
    text = text.replace("–", "-").strip().rstrip(".")
    m = re.fullmatch(r"([\d.]+)\s*-\s*([\d.]+)(?:\s*(kHz|MHz|GHz))?", text)
    if not m:
        return None
    mult = UNIT_KHZ[m.group(3) or unit]
    return (round(float(m.group(1)) * mult, 4), round(float(m.group(2)) * mult, 4))


# ---------------------------------------------------------------- interval helpers

def merge(intervals):
    out = []
    for lo, hi in sorted(intervals):
        if out and lo <= out[-1][1] + EPS:
            out[-1] = (out[-1][0], max(out[-1][1], hi))
        else:
            out.append((lo, hi))
    return out


def fmt(iv):
    return ", ".join(f"{lo:g}-{hi:g} kHz" for lo, hi in iv) or "(none)"


def diff(a, b):
    """Parts of interval list a not covered by b."""
    out = []
    for lo, hi in a:
        cur = lo
        for blo, bhi in b:
            if bhi <= cur + EPS or blo >= hi - EPS:
                continue
            if blo > cur + EPS:
                out.append((cur, blo))
            cur = max(cur, bhi)
        if cur < hi - EPS:
            out.append((cur, hi))
    return out


# ---------------------------------------------------------------- §97.301

def fcc_privileges(xml):
    """class -> merged Region 2 intervals in kHz, plus whether 'Above 275 GHz' is granted to all."""
    grants = {c: [] for c in CLASSES}
    above_275 = False
    tables = parse_tables(xml)
    if len(tables) < 5:
        fail(f"§97.301: expected at least 5 tables, parsed {len(tables)} - eCFR format may have changed")
    for para, rows in tables:
        m = re.match(r"\(([a-e])\)", para)
        if not m:
            fail(f"§97.301: table not preceded by a recognised paragraph: {para[:60]!r}")
            continue
        classes = PARAGRAPH_CLASSES[m.group(1)]
        unit = None
        for row in rows:
            if len(row) < 3:
                continue
            if row[1] in UNIT_KHZ:
                unit = row[1]
                continue
            if row[0].lower().startswith("wavelength"):
                continue
            region2 = row[2]
            if not region2:
                continue
            if region2.lower().startswith("above 275"):
                if classes == set(CLASSES):
                    above_275 = True
                continue
            rng = parse_range(region2, unit)
            if rng is None:
                fail(f"§97.301({m.group(1)}): could not parse Region 2 value {region2!r} in row {row}")
                continue
            for c in classes:
                grants[c].append(rng)
    return {c: merge(v) for c, v in grants.items()}, above_275


# ---------------------------------------------------------------- §97.303 (60 m channels)

def fcc_60m_channels(xml):
    centers = []
    for para, rows in parse_tables(xml):
        for row in rows:
            nums = [c for c in row if re.fullmatch(r"5[34]\d\d\.\d", c)]
            if len(nums) == 2:
                centers.append(float(nums[1]))
    return sorted(centers)


# ---------------------------------------------------------------- §97.305 (modes)

def fcc_emission_rows(xml):
    """List of (low_kHz, high_kHz or None for 'entire band', band, emissions set, standards set)."""
    out = []
    band_names = {}
    for para, rows in parse_tables(xml):
        for row in rows:
            if len(row) < 4 or row[0].lower().startswith("wavelength"):
                continue
            band = re.sub(r"^\([ivx]+\)\s*", "", row[0]).replace(" ", "")
            freqs, emissions, standards = row[1], row[2], row[3]
            if not band or not emissions:
                continue
            ems = {e.strip().lower() for e in re.split(r"[,\s]+", emissions) if e.strip()}
            stds = set(re.findall(r"\((\d+)\)", standards))
            if freqs.lower().startswith("entire band"):
                out.append((None, None, band, ems, stds))
            elif freqs.lower().startswith("above 275"):
                continue  # not drawn; the app must mention it in a note (check 4)
            elif band == "60m":
                out.append(("60m", None, band, ems, stds))
            else:
                rng = parse_range(freqs, "MHz")
                if rng is None:
                    rng = parse_range(re.sub(r"\s*MHz$", "", freqs), "MHz")
                if rng is None:
                    fail(f"§97.305: could not parse frequencies {freqs!r} for {band}")
                    continue
                out.append((rng[0], rng[1], band, ems, stds))
    return out


def mode_group(ems, extras):
    phone = bool(ems & {"phone", "image"})
    data = bool(ems & {"rtty", "data"})
    if extras:
        return "all"
    if phone and data:
        return "mixed"
    if phone:
        return "phone"
    if data:
        return "data"
    return "cwOnly"


def expected_mode(freq, band_name, band_range, rows, license):
    """What §97.305/§97.307 allow at freq (continental US) for this class."""
    ems, stds, extras = set(), set(), False
    name = band_name.replace(" ", "")
    for lo, hi, rband, rems, rstds in rows:
        covers = False
        if lo is None:
            # §97.301 defines "80 m" as 3.500-3.600 MHz and "75 m" as 3.600-4.000 MHz;
            # the app draws both as one 80m band.
            if rband == "80m":
                covers = name == "80m" and freq < 3600
            elif rband == "75m":
                covers = name == "80m" and freq >= 3600
            else:
                covers = rband == name
        elif lo == "60m":
            covers = name == "60m"
        else:
            covers = lo - EPS <= freq < hi - EPS
        if not covers:
            continue
        if "11" in rstds and rstds >= {"11"} and "phone" in rems and lo is not None and lo != "60m" \
                and hi - lo <= 25.0 + EPS and 7075 <= lo < 7100:
            # 7.075-7.100 MHz phone: only west of 130° W / south of 20° N. Not continental US.
            continue
        ems |= rems
        stds |= rstds
        extras |= bool(rems & {"mcw", "ss", "test", "pulse"})
    if license == "technician":
        if "9" in stds:
            return "cwOnly"
        if "10" in stds:
            return "cwSSB"
    return mode_group(ems, extras)


# ---------------------------------------------------------------- main

def main(app_json_path):
    app = json.load(open(app_json_path))

    versions = json.loads(fetch(f"{API}/versions/title-47.json?part=97"))
    date = versions["meta"]["latest_issue_date"]
    watched = [v for v in versions["content_versions"]
               if v["identifier"] in app["watchedSections"] and v["substantive"]]
    latest = max(v["date"] for v in watched)
    print(f"eCFR Part 97 as of {date}; latest substantive change to watched sections: {latest}")
    print(f"App data reflects rules through: {app['rulesCurrentThrough']}")
    if latest > app["rulesCurrentThrough"]:
        fail(f"eCFR has amendments after the app's rulesCurrentThrough date ({latest}); re-check and update BandPlan")
    elif latest < app["rulesCurrentThrough"]:
        fail(f"App rulesCurrentThrough ({app['rulesCurrentThrough']}) is later than any real amendment ({latest})")

    sec = lambda s: fetch(f"{API}/full/{date}/title-47.xml?part=97&section={s}")
    privileges, above_275 = fcc_privileges(sec("97.301"))
    channels = fcc_60m_channels(sec("97.303"))
    emission_rows = fcc_emission_rows(sec("97.305"))

    # ---- 0. Internal consistency: segments ordered, non-overlapping, inside their band.
    for b in app["bands"]:
        segs = b["segments"]
        for s in segs:
            if not (b["lowKHz"] - EPS <= s["lowKHz"] < s["highKHz"] <= b["highKHz"] + EPS):
                fail(f"{b['name']}: segment {s['lowKHz']:g}-{s['highKHz']:g} kHz is outside the band or empty")
        for s1, s2 in zip(segs, segs[1:]):
            if s2["lowKHz"] < s1["highKHz"] - EPS:
                fail(f"{b['name']}: segments {s1['lowKHz']:g}-{s1['highKHz']:g} and {s2['lowKHz']:g}-{s2['highKHz']:g} overlap or are out of order")
        for ch in b["channelsKHz"]:
            if not b["lowKHz"] <= ch <= b["highKHz"]:
                fail(f"{b['name']}: channel {ch:g} kHz is outside the band")

    # ---- 1. Frequencies each class may use must match exactly.
    for c in CLASSES:
        app_iv = []
        for b in app["bands"]:
            for s in b["segments"]:
                if RANK[c] >= RANK[s["minimumClass"]]:
                    app_iv.append((s["lowKHz"], s["highKHz"]))
        app_iv = merge(app_iv)
        fcc_iv = privileges[c]
        extra = diff(app_iv, fcc_iv)
        missing = diff(fcc_iv, app_iv)
        if extra:
            fail(f"{c.upper()}: app ALLOWS frequencies the FCC does not grant: {fmt(extra)}")
        if missing:
            fail(f"{c}: app is missing frequencies the FCC grants: {fmt(missing)}")
        print(f"  {c:<11} {len(fcc_iv)} FCC ranges, app {'matches' if not extra and not missing else 'DIFFERS'}")

    # ---- 2. 60 m channels.
    for b in app["bands"]:
        if b["channelsKHz"]:
            if sorted(b["channelsKHz"]) != channels:
                fail(f"60 m channels: app {b['channelsKHz']} vs FCC {channels}")
            if b["channelMinimumClass"] != "general":
                fail("60 m channels should be General and above")
            for c in CLASSES:
                fcc_has_60m = any(lo <= 5351.5 + EPS and hi >= 5366.5 - EPS for lo, hi in privileges[c])
                app_has = RANK[c] >= RANK[b["channelMinimumClass"]]
                if fcc_has_60m != app_has:
                    fail(f"60 m channels: {c} access in app ({app_has}) differs from FCC ({fcc_has_60m})")
    print(f"  60 m channels {channels} checked")

    # ---- 3. Modes in every slice of every segment, for every class.
    checked = 0
    for b in app["bands"]:
        bounds = {b["lowKHz"], b["highKHz"]}
        for lo, hi, *_ in emission_rows:
            if isinstance(lo, float):
                bounds |= {lo, hi}
        for s in b["segments"]:
            bounds |= {s["lowKHz"], s["highKHz"]}
            pts = sorted(x for x in bounds if s["lowKHz"] - EPS <= x <= s["highKHz"] + EPS)
            for a, z in zip(pts, pts[1:]):
                mid = (a + z) / 2
                for c in CLASSES:
                    if RANK[c] < RANK[s["minimumClass"]]:
                        continue
                    app_mode = (s.get("technicianMode") or s["mode"]) if c == "technician" else s["mode"]
                    want = expected_mode(mid, b["name"], (b["lowKHz"], b["highKHz"]), emission_rows, c)
                    checked += 1
                    if app_mode != want:
                        fail(f"{b['name']} {a:g}-{z:g} kHz, {c}: app says {app_mode}, FCC rules give {want}")
    print(f"  {checked} mode checks across all segments and classes")

    # ---- 4. Above 275 GHz must be mentioned since it isn't drawn.
    if above_275 and not any("275 GHz" in n for b in app["bands"] for n in b["notes"]):
        fail("FCC grants all frequencies above 275 GHz but the app never mentions it")

    # ---- 5. Restricted segments must carry their restriction.
    must_restrict = {(219000, 220000): "219-220 MHz (§97.303(l))", (135.7, 137.8): "2200 m (§97.303(g))",
                     (472, 479): "630 m (§97.303(g))", (420000, 430000): "420-430 MHz Line A (§97.303(m))",
                     (902000, 928000): "33 cm area bans (§97.303(n))"}
    found = set()
    for b in app["bands"]:
        for s in b["segments"]:
            key = (s["lowKHz"], s["highKHz"])
            if key in must_restrict:
                found.add(key)
            if key in must_restrict and not s.get("restriction"):
                fail(f"{must_restrict[key]} is legally restricted but the app shows it as open access")

    for key in set(must_restrict) - found:
        fail(f"{must_restrict[key]}: no segment with exactly these edges carries the restriction")
    print(f"  {len(found)} location/use restrictions present")

    print()
    if failures:
        print(f"FAILED - {len(failures)} problem(s):")
        for f in failures:
            print("  ✗", f)
        return 1
    print("PASSED - app band plan matches the FCC rules on eCFR for every class.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
