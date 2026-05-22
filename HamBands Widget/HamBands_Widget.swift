import WidgetKit
import SwiftUI

// MARK: - Entry

struct BandEntry: TimelineEntry {
    let date: Date
    let bestBand: String
    let rating: BandRating
    let sfi: Double
    let kIndex: Double
}

// MARK: - Provider

struct BandProvider: TimelineProvider {
    func placeholder(in context: Context) -> BandEntry {
        BandEntry(date: Date(), bestBand: "20m", rating: .good, sfi: 135, kIndex: 1.5)
    }

    func getSnapshot(in context: Context, completion: @escaping (BandEntry) -> Void) {
        completion(BandEntry(date: Date(), bestBand: "20m", rating: .good, sfi: 135, kIndex: 1.5))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BandEntry>) -> Void) {
        Task {
            let (sfi, kIndex) = await fetchConditions()
            let bands = rateBands(sfi: sfi, kIndex: kIndex)
            let best = bands.first { $0.rating == .good } ?? bands.first { $0.rating == .fair }
            let entry = BandEntry(
                date: Date(),
                bestBand: best?.band ?? "20m",
                rating: best?.rating ?? .fair,
                sfi: sfi,
                kIndex: kIndex
            )
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    private func fetchConditions() async -> (Double, Double) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: config)

        async let kResult: Double = {
            guard let url = URL(string: "https://services.swpc.noaa.gov/products/noaa-planetary-k-index.json"),
                  let (data, _) = try? await session.data(from: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [[Any]],
                  let latest = json.last else { return 2.0 }
            return Double(latest[1] as? String ?? "2.0") ?? 2.0
        }()

        async let sfiResult: Double = {
            guard let url = URL(string: "https://services.swpc.noaa.gov/json/f107_cm_flux.json"),
                  let (data, _) = try? await session.data(from: url) else { return 120.0 }
            struct F107Entry: Codable { let flux: Double? }
            return (try? JSONDecoder().decode([F107Entry].self, from: data))?.last?.flux ?? 120.0
        }()

        return await (sfiResult, kResult)
    }
}

// MARK: - Views

struct HamBandsWidgetEntryView: View {
    var entry: BandEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Circle()
                        .fill(entry.rating.color)
                        .frame(width: 10, height: 10)
                    Text(entry.bestBand)
                        .font(.system(.body, design: .monospaced, weight: .bold))
                        .minimumScaleFactor(0.5)
                }
            }
        default:
            HStack(spacing: 8) {
                Circle()
                    .fill(entry.rating.color)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.bestBand)
                        .font(.system(.title3, design: .monospaced, weight: .bold))
                    Text("SFI \(Int(entry.sfi))  K \(String(format: "%.1f", entry.kIndex))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Widget

struct HamBandsWidget: Widget {
    let kind: String = "HamBandsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BandProvider()) { entry in
            HamBandsWidgetEntryView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("HamBands")
        .description("Best HF band conditions at a glance.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}
