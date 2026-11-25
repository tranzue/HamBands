import Foundation
import SwiftUI

// MARK: - US amateur band privileges (FCC Part 97)
//
// Source: 47 CFR Part 97 as published on eCFR (ecfr.gov), for a station in the
// continental US (ITU Region 2):
//   §97.301  Authorized frequency bands (who can transmit where)
//   §97.303  Frequency sharing requirements (60 m channels, 2200/630 m, 219 MHz)
//   §97.305  Authorized emission types (which modes go where)
//   §97.307  Emission standards (Technician CW-only / SSB-only limits)
//   §97.313  Transmitter power standards
//
// When the FCC amends any of those sections, `BandPlan.rulesCurrentThrough` must be
// updated after re-checking the data below. `FCCRuleWatcher` compares that date to
// eCFR's change history so the app can warn when this chart falls behind.

enum LicenseClass: String, CaseIterable, Identifiable, Comparable {
    case technician, general, advanced, extra

    var id: String { rawValue }

    var name: String {
        switch self {
        case .technician: "Technician"
        case .general: "General"
        case .advanced: "Advanced"
        case .extra: "Extra"
        }
    }

    var shortName: String {
        switch self {
        case .technician: "Tech"
        case .general: "General"
        case .advanced: "Adv"
        case .extra: "Extra"
        }
    }

    private var rank: Int {
        switch self {
        case .technician: 0
        case .general: 1
        case .advanced: 2
        case .extra: 3
        }
    }

    static func < (lhs: LicenseClass, rhs: LicenseClass) -> Bool { lhs.rank < rhs.rank }

    static let storageKey = "licenseClass"
}

/// Which emissions are allowed in a segment (§97.305 / §97.307).
enum ModeGroup: String, CaseIterable, Identifiable {
    case cwOnly
    case cwSSB
    case data
    case phone
    case mixed
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cwOnly: "CW only"
        case .cwSSB: "CW · SSB"
        case .data: "CW · RTTY · Data"
        case .phone: "CW · Phone · Image"
        case .mixed: "CW · Phone · Data"
        case .all: "All modes"
        }
    }

    var color: Color {
        switch self {
        case .cwOnly: .blue
        case .cwSSB: .indigo
        case .data: .purple
        case .phone: .orange
        case .mixed: .teal
        case .all: .green
        }
    }
}

/// A slice of a band with one set of rules. Privileges are nested
/// (Technician ⊂ General ⊂ Advanced ⊂ Extra), so each segment records the
/// lowest class allowed to transmit in it.
struct BandSegment: Identifiable, Hashable {
    let lowKHz: Double
    let highKHz: Double
    let minimumClass: LicenseClass
    let mode: ModeGroup
    /// Technicians sometimes get fewer modes than higher classes in the same segment.
    var technicianMode: ModeGroup? = nil
    /// Set when the segment is legally open to the class but only under special
    /// conditions (prior notification, specific use). Shown as a warning, never as plain access.
    var restriction: String? = nil

    var id: String { "\(lowKHz)-\(highKHz)" }

    func isAllowed(for license: LicenseClass) -> Bool { license >= minimumClass }

    func mode(for license: LicenseClass) -> ModeGroup {
        license == .technician ? (technicianMode ?? mode) : mode
    }
}

enum BandGroup: String, CaseIterable, Identifiable {
    case lfmf = "LF / MF"
    case hf = "HF"
    case vhf = "VHF"
    case uhf = "UHF"
    case microwave = "Microwave"

    var id: String { rawValue }
}

struct Band: Identifiable, Hashable {
    let name: String
    let group: BandGroup
    /// The span drawn on the chart. Gaps between segments are not amateur spectrum.
    let lowKHz: Double
    let highKHz: Double
    let segments: [BandSegment]
    /// Single-frequency channels (60 m), as center frequencies in kHz.
    var channelsKHz: [Double] = []
    var channelMinimumClass: LicenseClass = .general
    var notes: [String] = []

    var id: String { name }

    func isAvailable(to license: LicenseClass) -> Bool {
        segments.contains { $0.isAllowed(for: license) }
            || (!channelsKHz.isEmpty && license >= channelMinimumClass)
    }

    /// The segments this license can use, with neighbors that share a mode merged.
    /// Restricted segments are never merged with unrestricted ones, so a warning
    /// can't be hidden inside a wider "open" range.
    func allowedRanges(for license: LicenseClass) -> [AllowedRange] {
        var result: [AllowedRange] = []
        for segment in segments where segment.isAllowed(for: license) {
            let mode = segment.mode(for: license)
            if let last = result.last, last.high == segment.lowKHz, last.mode == mode,
               last.restriction == nil, segment.restriction == nil {
                result[result.count - 1].high = segment.highKHz
            } else {
                result.append(AllowedRange(low: segment.lowKHz, high: segment.highKHz,
                                           mode: mode, restriction: segment.restriction))
            }
        }
        return result
    }

    /// True when any part of the band this license can use comes with special conditions.
    func hasRestrictions(for license: LicenseClass) -> Bool {
        segments.contains { $0.isAllowed(for: license) && $0.restriction != nil }
    }
}

struct AllowedRange {
    var low: Double
    var high: Double
    let mode: ModeGroup
    let restriction: String?
}

// MARK: - Frequency formatting

enum Frequency {
    /// Formats a kHz value in the unit hams use for that part of the spectrum.
    static func format(_ kHz: Double, unitHint: Double? = nil) -> String {
        let reference = unitHint ?? kHz
        if reference < 1000 {
            return trimmed(kHz, maxDecimals: 1) + " kHz"
        } else if reference < 1_000_000 {
            // Always three decimals, the way band plans are written (3.600 MHz).
            return (kHz / 1000).formatted(.number.precision(.fractionLength(3...4)).grouping(.never)) + " MHz"
        } else {
            return trimmed(kHz / 1_000_000, maxDecimals: 3) + " GHz"
        }
    }

    static func range(_ low: Double, _ high: Double) -> String {
        let lowText = format(low, unitHint: high).split(separator: " ").first.map(String.init) ?? ""
        return "\(lowText)–\(format(high, unitHint: high))"
    }

    /// eCFR dates are calendar days, stored as midnight UTC; show them as that same day
    /// regardless of the device's time zone.
    static func ruleDate(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        style.timeZone = .gmt
        return date.formatted(style)
    }

    private static func trimmed(_ value: Double, maxDecimals: Int) -> String {
        value.formatted(.number.precision(.fractionLength(0...maxDecimals)).grouping(.never))
    }
}

// MARK: - The band plan

enum BandPlan {
    /// The most recent substantive eCFR amendment to §§97.301, .303, .305, .307 and .313
    /// that this data reflects. Update after re-checking the bands against eCFR.
    static let rulesCurrentThrough = DateComponents(calendar: .init(identifier: .gregorian),
                                                    timeZone: .gmt, year: 2026, month: 2, day: 13).date!

    static let watchedSections = ["97.301", "97.303", "97.305", "97.307", "97.313"]

    static let generalNotes = [
        "Maximum power is 1.5 kW PEP unless a band says otherwise (§97.313). Use the minimum power needed.",
        "Spread spectrum is limited to 10 W PEP on the bands where it is allowed.",
        "Privileges shown are for the US mainland, Alaska, Hawaii, Puerto Rico and the US Virgin Islands (ITU Region 2). Guam, the Northern Mariana Islands and American Samoa are in Region 3 and have different band edges.",
        "Your whole signal must stay inside your privileges, not just the dial frequency. LSB on 3.800 MHz or USB on 14.350 MHz puts part of your signal outside the band.",
        "CW is allowed anywhere you have privileges.",
    ]

    static let bands: [Band] = [
        // LF / MF
        Band(name: "2200m", group: .lfmf, lowKHz: 135.7, highKHz: 137.8,
             segments: [.init(lowKHz: 135.7, highKHz: 137.8, minimumClass: .general, mode: .mixed,
                              restriction: "Fixed stations only, after notifying UTC and waiting 30 days (§97.303(g)).")],
             notes: ["1 W EIRP maximum.",
                     "Fixed stations only. Notify the Utilities Telecom Council (UTC) 30 days before operating (§97.303(g))."]),
        Band(name: "630m", group: .lfmf, lowKHz: 472, highKHz: 479,
             segments: [.init(lowKHz: 472, highKHz: 479, minimumClass: .general, mode: .mixed,
                              restriction: "Fixed stations only, after notifying UTC and waiting 30 days (§97.303(g)).")],
             notes: ["500 W PEP and 5 W EIRP maximum (1 W EIRP in parts of Alaska).",
                     "Fixed stations only. Notify the Utilities Telecom Council (UTC) 30 days before operating (§97.303(g))."]),
        Band(name: "160m", group: .lfmf, lowKHz: 1800, highKHz: 2000,
             segments: [.init(lowKHz: 1800, highKHz: 2000, minimumClass: .general, mode: .mixed)]),

        // HF
        Band(name: "80m", group: .hf, lowKHz: 3500, highKHz: 4000,
             segments: [
                .init(lowKHz: 3500, highKHz: 3525, minimumClass: .extra, mode: .data),
                .init(lowKHz: 3525, highKHz: 3600, minimumClass: .technician, mode: .data, technicianMode: .cwOnly),
                .init(lowKHz: 3600, highKHz: 3700, minimumClass: .extra, mode: .phone),
                .init(lowKHz: 3700, highKHz: 3800, minimumClass: .advanced, mode: .phone),
                .init(lowKHz: 3800, highKHz: 4000, minimumClass: .general, mode: .phone),
             ],
             notes: ["The phone portion (3.600–4.000 MHz) is often called 75 m.",
                     "Technicians: CW only, 200 W PEP maximum."]),
        Band(name: "60m", group: .hf, lowKHz: 5330.5, highKHz: 5406.4,
             segments: [.init(lowKHz: 5351.5, highKHz: 5366.5, minimumClass: .general, mode: .mixed)],
             channelsKHz: [5332, 5348, 5373, 5405],
             notes: ["Channels 5332, 5348, 5373 and 5405 kHz (center): 100 W ERP maximum. For phone and data, set the carrier 1.5 kHz below center (USB); for CW, transmit on the center frequency.",
                     "5351.5–5366.5 kHz: 9.15 W ERP maximum.",
                     "2.8 kHz maximum bandwidth. Secondary user: don't interfere with government stations."]),
        Band(name: "40m", group: .hf, lowKHz: 7000, highKHz: 7300,
             segments: [
                .init(lowKHz: 7000, highKHz: 7025, minimumClass: .extra, mode: .data),
                .init(lowKHz: 7025, highKHz: 7125, minimumClass: .technician, mode: .data, technicianMode: .cwOnly),
                .init(lowKHz: 7125, highKHz: 7175, minimumClass: .advanced, mode: .phone),
                .init(lowKHz: 7175, highKHz: 7300, minimumClass: .general, mode: .phone),
             ],
             notes: ["Technicians: CW only, 200 W PEP maximum.",
                     "7.075–7.100 MHz phone is allowed only from west of 130° W or south of 20° N (Hawaii, most of Alaska, Puerto Rico, US Virgin Islands). Mainland US: no phone below 7.125 MHz."]),
        Band(name: "30m", group: .hf, lowKHz: 10100, highKHz: 10150,
             segments: [.init(lowKHz: 10100, highKHz: 10150, minimumClass: .general, mode: .data)],
             notes: ["200 W PEP maximum. No phone.", "Secondary user: don't interfere with other services."]),
        Band(name: "20m", group: .hf, lowKHz: 14000, highKHz: 14350,
             segments: [
                .init(lowKHz: 14000, highKHz: 14025, minimumClass: .extra, mode: .data),
                .init(lowKHz: 14025, highKHz: 14150, minimumClass: .general, mode: .data),
                .init(lowKHz: 14150, highKHz: 14175, minimumClass: .extra, mode: .phone),
                .init(lowKHz: 14175, highKHz: 14225, minimumClass: .advanced, mode: .phone),
                .init(lowKHz: 14225, highKHz: 14350, minimumClass: .general, mode: .phone),
             ]),
        Band(name: "17m", group: .hf, lowKHz: 18068, highKHz: 18168,
             segments: [
                .init(lowKHz: 18068, highKHz: 18110, minimumClass: .general, mode: .data),
                .init(lowKHz: 18110, highKHz: 18168, minimumClass: .general, mode: .phone),
             ]),
        Band(name: "15m", group: .hf, lowKHz: 21000, highKHz: 21450,
             segments: [
                .init(lowKHz: 21000, highKHz: 21025, minimumClass: .extra, mode: .data),
                .init(lowKHz: 21025, highKHz: 21200, minimumClass: .technician, mode: .data, technicianMode: .cwOnly),
                .init(lowKHz: 21200, highKHz: 21225, minimumClass: .extra, mode: .phone),
                .init(lowKHz: 21225, highKHz: 21275, minimumClass: .advanced, mode: .phone),
                .init(lowKHz: 21275, highKHz: 21450, minimumClass: .general, mode: .phone),
             ],
             notes: ["Technicians: CW only, 200 W PEP maximum."]),
        Band(name: "12m", group: .hf, lowKHz: 24890, highKHz: 24990,
             segments: [
                .init(lowKHz: 24890, highKHz: 24930, minimumClass: .general, mode: .data),
                .init(lowKHz: 24930, highKHz: 24990, minimumClass: .general, mode: .phone),
             ]),
        Band(name: "10m", group: .hf, lowKHz: 28000, highKHz: 29700,
             segments: [
                .init(lowKHz: 28000, highKHz: 28300, minimumClass: .technician, mode: .data),
                .init(lowKHz: 28300, highKHz: 28500, minimumClass: .technician, mode: .phone, technicianMode: .cwSSB),
                .init(lowKHz: 28500, highKHz: 29700, minimumClass: .general, mode: .phone),
             ],
             notes: ["Technicians: 200 W PEP maximum. SSB phone allowed on 28.300–28.500 MHz.",
                     "By band-plan convention (not FCC rule), FM and repeaters use 29.0–29.7 MHz."]),

        // VHF
        Band(name: "6m", group: .vhf, lowKHz: 50000, highKHz: 54000,
             segments: [
                .init(lowKHz: 50000, highKHz: 50100, minimumClass: .technician, mode: .cwOnly),
                .init(lowKHz: 50100, highKHz: 54000, minimumClass: .technician, mode: .all),
             ]),
        Band(name: "2m", group: .vhf, lowKHz: 144000, highKHz: 148000,
             segments: [
                .init(lowKHz: 144000, highKHz: 144100, minimumClass: .technician, mode: .cwOnly),
                .init(lowKHz: 144100, highKHz: 148000, minimumClass: .technician, mode: .all),
             ]),
        Band(name: "1.25m", group: .vhf, lowKHz: 219000, highKHz: 225000,
             segments: [
                .init(lowKHz: 219000, highKHz: 220000, minimumClass: .technician, mode: .data,
                      restriction: "Fixed point-to-point digital message forwarding only. Written notice to ARRL 30 days before transmitting (§97.303(l))."),
                .init(lowKHz: 222000, highKHz: 225000, minimumClass: .technician, mode: .all),
             ],
             notes: ["219–220 MHz is only for fixed point-to-point digital message forwarding, 50 W PEP maximum (§97.303(l)).",
                     "220–222 MHz is not amateur spectrum."]),

        // UHF
        Band(name: "70cm", group: .uhf, lowKHz: 420_000, highKHz: 450_000,
             segments: [
                .init(lowKHz: 420_000, highKHz: 430_000, minimumClass: .technician, mode: .all,
                      restriction: "Do not transmit here from north of Line A, the strip along the Canadian border (§97.303(m), §97.3(a))."),
                .init(lowKHz: 430_000, highKHz: 450_000, minimumClass: .technician, mode: .all),
             ],
             notes: ["420–430 MHz: no transmitting from north of Line A (a line near the Canadian border; Seattle, Detroit, Cleveland, Erie PA, Buffalo and northern New England are north of it). Near Buffalo, Cleveland and Detroit it is shared with land mobile.",
                     "50 W PEP maximum near certain military bases (§97.313(f))."]),
        Band(name: "33cm", group: .uhf, lowKHz: 902_000, highKHz: 928_000,
             segments: [.init(lowKHz: 902_000, highKHz: 928_000, minimumClass: .technician, mode: .all,
                              restriction: "Banned in some areas: no transmitting from the White Sands region of Texas/New Mexico, and parts of Colorado/Wyoming bar four segments (§97.303(n)).")],
             notes: ["No transmitting at all from the part of Texas and New Mexico between 31°41′–34°30′ N and 104°11′–107°30′ W (White Sands), or from outside the US and its Region 2 areas.",
                     "No transmitting on 902.4–902.6, 904.3–904.7, 925.3–925.7 or 927.3–927.7 MHz from the part of Colorado and Wyoming between 39°–42° N and 103°–108° W.",
                     "50 W PEP maximum within 241 km of the White Sands Missile Range boundary (§97.313(g)).",
                     "Secondary user: shared with government, location-monitoring and ISM devices."]),
        Band(name: "23cm", group: .uhf, lowKHz: 1_240_000, highKHz: 1_300_000,
             segments: [.init(lowKHz: 1_240_000, highKHz: 1_300_000, minimumClass: .technician, mode: .all)]),

        // Microwave
        Band(name: "13cm", group: .microwave, lowKHz: 2_300_000, highKHz: 2_450_000,
             segments: [
                .init(lowKHz: 2_300_000, highKHz: 2_310_000, minimumClass: .technician, mode: .all),
                .init(lowKHz: 2_390_000, highKHz: 2_450_000, minimumClass: .technician, mode: .all),
             ],
             notes: ["2.310–2.390 GHz is not amateur spectrum."]),
        Band(name: "5cm", group: .microwave, lowKHz: 5_650_000, highKHz: 5_925_000,
             segments: [.init(lowKHz: 5_650_000, highKHz: 5_925_000, minimumClass: .technician, mode: .all)]),
        Band(name: "3cm", group: .microwave, lowKHz: 10_000_000, highKHz: 10_500_000,
             segments: [.init(lowKHz: 10_000_000, highKHz: 10_500_000, minimumClass: .technician, mode: .all)]),
        Band(name: "1.2cm", group: .microwave, lowKHz: 24_000_000, highKHz: 24_250_000,
             segments: [.init(lowKHz: 24_000_000, highKHz: 24_250_000, minimumClass: .technician, mode: .all)]),
        Band(name: "6mm", group: .microwave, lowKHz: 47_000_000, highKHz: 47_200_000,
             segments: [.init(lowKHz: 47_000_000, highKHz: 47_200_000, minimumClass: .technician, mode: .all)]),
        Band(name: "4mm", group: .microwave, lowKHz: 76_000_000, highKHz: 81_000_000,
             segments: [.init(lowKHz: 76_000_000, highKHz: 81_000_000, minimumClass: .technician, mode: .all)],
             notes: ["316 W peak EIRP maximum."]),
        Band(name: "2.5mm", group: .microwave, lowKHz: 122_250_000, highKHz: 123_000_000,
             segments: [.init(lowKHz: 122_250_000, highKHz: 123_000_000, minimumClass: .technician, mode: .all)]),
        Band(name: "2mm", group: .microwave, lowKHz: 134_000_000, highKHz: 141_000_000,
             segments: [.init(lowKHz: 134_000_000, highKHz: 141_000_000, minimumClass: .technician, mode: .all)]),
        Band(name: "1mm", group: .microwave, lowKHz: 241_000_000, highKHz: 250_000_000,
             segments: [.init(lowKHz: 241_000_000, highKHz: 250_000_000, minimumClass: .technician, mode: .all)],
             notes: ["All frequencies above 275 GHz are also open to every license class."]),
    ]
}

// MARK: - FCC rule change detection (eCFR)

/// Checks eCFR's change history for Part 97 and reports whether any of the sections
/// behind `BandPlan` were amended after the date the bundled data reflects.
@Observable
final class FCCRuleWatcher {
    enum Status: Equatable {
        case unknown
        case checking
        /// No amendments newer than the bundled data.
        case current(latestAmendment: Date)
        /// eCFR shows amendments the bundled data may not include.
        case outdated(sections: [String], latestAmendment: Date)
        case failed
    }

    private(set) var status: Status = .unknown
    private(set) var lastChecked: Date? = UserDefaults.standard.object(forKey: Keys.lastChecked) as? Date

    private enum Keys {
        static let lastChecked = "fccRules.lastChecked"
        static let latestAmendment = "fccRules.latestAmendment"
        static let changedSections = "fccRules.changedSections"
    }

    private static let versionsURL = URL(string: "https://www.ecfr.gov/api/versioner/v1/versions/title-47.json?part=97")!

    static func sectionURL(_ section: String) -> URL {
        URL(string: "https://www.ecfr.gov/current/title-47/part-97/section-\(section)")!
    }

    init() {
        // Show the last known result immediately, before any network check.
        if let latest = UserDefaults.standard.object(forKey: Keys.latestAmendment) as? Date {
            status = Self.status(latest: latest,
                                 changed: UserDefaults.standard.stringArray(forKey: Keys.changedSections) ?? [])
        }
    }

    /// Checks eCFR at most once every 24 hours unless `force` is set.
    func check(force: Bool = false) async {
        if !force, let lastChecked, Date().timeIntervalSince(lastChecked) < 24 * 60 * 60, status != .unknown {
            return
        }
        let previous = status
        status = .checking
        do {
            var request = URLRequest(url: Self.versionsURL)
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let decoded = try JSONDecoder().decode(VersionsResponse.self, from: data)

            let watched = decoded.contentVersions.filter {
                $0.substantive && BandPlan.watchedSections.contains($0.identifier)
            }
            guard let latest = watched.compactMap({ Self.parse($0.date) }).max() else {
                throw URLError(.cannotParseResponse)
            }
            let changed = Set(watched.filter { (Self.parse($0.date) ?? .distantPast) > BandPlan.rulesCurrentThrough }
                .map(\.identifier)).sorted()

            let now = Date()
            lastChecked = now
            UserDefaults.standard.set(now, forKey: Keys.lastChecked)
            UserDefaults.standard.set(latest, forKey: Keys.latestAmendment)
            UserDefaults.standard.set(changed, forKey: Keys.changedSections)
            status = Self.status(latest: latest, changed: changed)
        } catch {
            // Keep showing the last good result if we have one.
            if case .current = previous { status = previous }
            else if case .outdated = previous { status = previous }
            else { status = .failed }
        }
    }

    private static func status(latest: Date, changed: [String]) -> Status {
        changed.isEmpty ? .current(latestAmendment: latest) : .outdated(sections: changed, latestAmendment: latest)
    }

    private static func parse(_ text: String) -> Date? {
        try? Date(text, strategy: Date.ISO8601FormatStyle().year().month().day())
    }

    private struct VersionsResponse: Decodable {
        let contentVersions: [Version]
        enum CodingKeys: String, CodingKey { case contentVersions = "content_versions" }
    }

    private struct Version: Decodable {
        let date: String
        let identifier: String
        let substantive: Bool
    }
}
