# HamBands 📡

An iOS and Apple Watch app for amateur radio operators that displays real-time HF band conditions based on live solar data from NOAA.

Built by [KD3CLW](https://www.qrz.com/db/KD3CLW) — Western Pennsylvania.

---

## Features

- **Live solar data** — fetches Solar Flux Index (SFI), K-index, and A-index directly from NOAA
- **Color-coded band ratings** — instant Good / Fair / Poor assessment for 10m, 15m, 20m, 40m, and 80m
- **Apple Watch app** — glanceable band conditions and solar data on your wrist
- **Watch complication** — circular and rectangular styles, refreshes automatically every 30 minutes
- **Pull to refresh** — tap to get the latest conditions before a QSO or POTA activation

---

## Screenshots

<!-- Add screenshots here -->

---

## Use Cases

- Quick band check before a Parks on the Air (POTA) activation
- Field day operating decisions
- Daily shack reference for HF operators
- Wrist-check during a contact to gauge propagation

---

## Requirements

- iOS 17.0+
- watchOS 10.0+
- Xcode 15+
- Swift 5.9+

---

## Installation

### Clone the repo

```bash
git clone https://github.com/kd3clw/HamBands.git
cd HamBands
```

### Open in Xcode

```bash
open HamBands.xcodeproj
```

### Build and run

1. Select your target device or simulator in Xcode
2. Press **⌘R** to build and run
3. For the Watch app, select the **HamBands Watch App** scheme

> **Note:** No API keys required. Solar data is fetched from the publicly available [NOAA Space Weather API](https://services.swpc.noaa.gov/).

---

## How Band Ratings Work

Band conditions are calculated from two key solar indices:

| Index | What it measures |
|-------|-----------------|
| **SFI** (Solar Flux Index) | Overall solar activity — higher is generally better for higher bands |
| **K-index** | Geomagnetic disturbance — lower is better for all bands |

| Band | Good | Fair | Poor |
|------|------|------|------|
| 10m | SFI ≥ 150, K ≤ 2 | SFI ≥ 120, K ≤ 3 | Otherwise |
| 15m | SFI ≥ 120, K ≤ 3 | SFI ≥ 100, K ≤ 4 | Otherwise |
| 20m | SFI ≥ 100, K ≤ 3 | K ≤ 5 | Otherwise |
| 40m | K ≤ 2 | K ≤ 4 | Otherwise |
| 80m | K ≤ 2 | K ≤ 4 | Otherwise |

---

## Project Structure

```
HamBands/
├── HamBands/                   # iOS app target
│   ├── BandConditions.swift    # Data models, band rating logic, NOAA fetch
│   ├── ContentView.swift       # Main iPhone UI
│   └── Assets.xcassets/
├── HamBands Watch App/         # watchOS app target
│   └── ContentView.swift       # Watch UI
└── HamBands Widget/            # WidgetKit extension
    └── HamBandsWidget.swift    # Complication logic
```

---

## Data Source

Solar data is pulled from the **NOAA Space Weather Prediction Center**:

```
https://services.swpc.noaa.gov/products/noaa-planetary-k-index.json
```

No account or API key required. Data is publicly available.

---

## Contributing

Pull requests welcome. If you're a ham and have ideas for improvements — band-specific propagation notes, geomagnetic storm alerts, grey line data — open an issue.

---

## License

MIT License. See [LICENSE](LICENSE) for details.

---

## 73

*Built for the ham radio community. If this helps you make a contact, that's the whole point.*

`KD3CLW — de Western Pennsylvania`
