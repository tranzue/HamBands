import Foundation
import SwiftUI
import Combine

// MARK: - Data Models

struct SolarData {
    let solarFluxIndex: Double
    let kIndex: Double
    let aIndex: Double
    let fetchedAt: Date
}

enum BandRating: String {
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"

    var color: Color {
        switch self {
        case .good: return .green
        case .fair: return .yellow
        case .poor: return .red
        }
    }

    var emoji: String {
        switch self {
        case .good: return "🟢"
        case .fair: return "🟡"
        case .poor: return "🔴"
        }
    }
}

struct BandCondition: Identifiable {
    let id = UUID()
    let band: String
    let rating: BandRating
    let note: String
}

// MARK: - Band Rating Logic

func rateBands(sfi: Double, kIndex: Double) -> [BandCondition] {
    return [
        BandCondition(
            band: "10m",
            rating: sfi >= 150 && kIndex <= 2 ? .good : sfi >= 120 && kIndex <= 3 ? .fair : .poor,
            note: sfi >= 150 ? "High solar flux" : sfi >= 120 ? "Moderate flux" : "Low flux"
        ),
        BandCondition(
            band: "15m",
            rating: sfi >= 120 && kIndex <= 3 ? .good : sfi >= 100 && kIndex <= 4 ? .fair : .poor,
            note: kIndex <= 3 ? "Quiet geomagnetic" : kIndex <= 4 ? "Minor disturbance" : "Active/stormy"
        ),
        BandCondition(
            band: "20m",
            rating: sfi >= 100 && kIndex <= 3 ? .good : kIndex <= 5 ? .fair : .poor,
            note: "Reliable workhorse band"
        ),
        BandCondition(
            band: "40m",
            rating: kIndex <= 2 ? .good : kIndex <= 4 ? .fair : .poor,
            note: kIndex <= 2 ? "Good DX potential" : "Some noise expected"
        ),
        BandCondition(
            band: "80m",
            rating: kIndex <= 2 ? .good : kIndex <= 4 ? .fair : .poor,
            note: "Best after local sunset"
        )
    ]
}

// MARK: - NOAA Fetch

@MainActor
class BandViewModel: ObservableObject {
    @Published var bands: [BandCondition] = []
    @Published var solarData: SolarData? = nil
    @Published var isLoading = false
    @Published var errorMessage: String? = nil

    func fetch() async {
        isLoading = true
        errorMessage = nil

        // Use a 10 second timeout
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        let session = URLSession(configuration: config)

        // Fetch K-index and SFI in parallel
        async let kResult = fetchKIndex(session: session)
        async let sfiResult = fetchSFI(session: session)

        let kIndex = await kResult
        let sfi = await sfiResult

        let solar = SolarData(
            solarFluxIndex: sfi,
            kIndex: kIndex,
            aIndex: 0,
            fetchedAt: Date()
        )
        self.solarData = solar
        self.bands = rateBands(sfi: sfi, kIndex: kIndex)
        isLoading = false
    }

    private func fetchKIndex(session: URLSession) async -> Double {
        guard let url = URL(string: "https://services.swpc.noaa.gov/products/noaa-planetary-k-index.json") else { return 2.0 }
        do {
            let (data, _) = try await session.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [[Any]], json.count > 1 else { return 2.0 }
            // First row is a header; sort remaining rows by time_tag (col 0) and take the latest with a valid Kp (col 1).
            let rows = json.dropFirst().sorted { (a, b) in
                let aT = (a.first as? String) ?? ""
                let bT = (b.first as? String) ?? ""
                return aT < bT
            }
            for row in rows.reversed() where row.count > 1 {
                if let kp = doubleValue(row[1]) { return kp }
            }
        } catch { }
        return 2.0
    }

    private func fetchSFI(session: URLSession) async -> Double {
        // This endpoint is much lighter/faster than the solar cycle one
        guard let url = URL(string: "https://services.swpc.noaa.gov/json/f107_cm_flux.json") else { return 120.0 }
        do {
            let (data, _) = try await session.data(from: url)
            struct F107Entry: Codable {
                let time_tag: String?
                let flux: Double?
            }
            let entries = try JSONDecoder().decode([F107Entry].self, from: data)
            // Skip null-flux entries (future / not-yet-observed days) and pick the most recent by time_tag.
            let valid = entries.compactMap { e -> (String, Double)? in
                guard let t = e.time_tag, let f = e.flux else { return nil }
                return (t, f)
            }.sorted { $0.0 < $1.0 }
            return valid.last?.1 ?? 120.0
        } catch { }
        return 120.0
    }

    private func doubleValue(_ raw: Any) -> Double? {
        if let s = raw as? String { return Double(s) }
        if let d = raw as? Double { return d }
        if let i = raw as? Int { return Double(i) }
        if let n = raw as? NSNumber { return n.doubleValue }
        return nil
    }

    var bestBand: BandCondition? {
        bands.first { $0.rating == .good } ?? bands.first { $0.rating == .fair }
    }
}

