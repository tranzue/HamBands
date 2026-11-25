#!/bin/bash
# Checks HamBands' band privilege data against the current FCC rules on eCFR.
# Run this after any edit to HamBands/BandPrivileges.swift, and whenever the app
# reports that the FCC rules have changed.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

xcrun swiftc -parse-as-library -default-isolation MainActor \
    "$repo/HamBands/BandPrivileges.swift" "$here/ExportBandPlan.swift" \
    -o "$work/export-band-plan" 2> "$work/build.log" || { cat "$work/build.log"; exit 1; }
"$work/export-band-plan" > "$work/band-plan.json"
python3 -I "$here/verify_band_plan.py" "$work/band-plan.json"
