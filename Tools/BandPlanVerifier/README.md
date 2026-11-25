# Band plan verifier

Checks the band privileges in `HamBands/BandPrivileges.swift` against the FCC's own
rules (47 CFR Part 97 on [eCFR](https://www.ecfr.gov/current/title-47/part-97)).

```bash
Tools/BandPlanVerifier/verify_band_plan.sh
```

**Run it:**
- after any edit to `BandPrivileges.swift`, and
- whenever the app's Privileges tab says **"FCC rules have changed."**

It downloads §97.301, §97.303 and §97.305, parses their tables itself, and compares them
with the data the app actually ships, for every license class:

- every frequency each class may use (anything extra or missing fails),
- the allowed modes in every slice of every segment, including Technician CW-only/SSB-only limits,
- the 60 m channels,
- that segments are ordered, non-overlapping and inside their band,
- that location- and use-restricted segments (2200 m, 630 m, 219–220 MHz, 420–430 MHz Line A,
  33 cm) carry a restriction warning,
- that `BandPlan.rulesCurrentThrough` equals eCFR's latest amendment date.

Exit code 0 means everything matches. Any mismatch is listed and exits 1.

When the FCC changes the rules: update the bands in `BandPrivileges.swift`, set
`rulesCurrentThrough` to the new amendment date, and rerun until it passes.
