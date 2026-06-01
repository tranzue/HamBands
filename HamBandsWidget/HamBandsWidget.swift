import WidgetKit
import SwiftUI

// MARK: - Shared Timeline Entry

struct BandEntry: TimelineEntry {
    let date: Date
    let sfi: Double
    let kIndex: Double
    let aIndex: Double
    let bands: [BandCondition]

    var bestBand: BandCondition? {
        bands.first { $0.rating == .good } ?? bands.first { $0.rating == .fair }
    }

    var overallRating: BandRating {
        let goodCount = bands.filter { $0.rating == .good }.count
        let fairCount = bands.filter { $0.rating == .fair }.count
        if goodCount >= 2 { return .good }
        if goodCount >= 1 || fairCount >= 2 { return .fair }
        return .poor
    }

    static var placeholder: BandEntry {
        BandEntry(
            date: Date(),
            sfi: 145,
            kIndex: 2.0,
            aIndex: 8,
            bands: rateBands(sfi: 145, kIndex: 2.0)
        )
    }
}

// MARK: - Shared Timeline Provider

struct BandProvider: TimelineProvider {

    func placeholder(in context: Context) -> BandEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (BandEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        Task {
            completion(await fetchEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BandEntry>) -> Void) {
        Task {
            let entry = await fetchEntry()
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    private func fetchEntry() async -> BandEntry {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: config)

        async let k = fetchK(session: session)
        async let sfi = fetchSFI(session: session)
        async let a = fetchA(session: session)

        let (kVal, sfiVal, aVal) = await (k, sfi, a)
        return BandEntry(
            date: Date(),
            sfi: sfiVal,
            kIndex: kVal,
            aIndex: aVal,
            bands: rateBands(sfi: sfiVal, kIndex: kVal)
        )
    }

    private func fetchK(session: URLSession) async -> Double {
        guard let url = URL(string: "https://services.swpc.noaa.gov/products/noaa-planetary-k-index.json"),
              let (data, _) = try? await session.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[Any]],
              let latest = json.last else { return 2.0 }
        return Double(latest[1] as? String ?? "2.0") ?? 2.0
    }

    private func fetchSFI(session: URLSession) async -> Double {
        guard let url = URL(string: "https://services.swpc.noaa.gov/json/f107_cm_flux.json"),
              let (data, _) = try? await session.data(from: url) else { return 120.0 }
        struct F107Entry: Codable { let flux: Double? }
        return (try? JSONDecoder().decode([F107Entry].self, from: data))?.last?.flux ?? 120.0
    }

    private func fetchA(session: URLSession) async -> Double {
        guard let url = URL(string: "https://services.swpc.noaa.gov/json/solar-cycle/observed-solar-indices.json"),
              let (data, _) = try? await session.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[Any]],
              let last = json.last, last.count >= 6 else { return 8 }
        return (last[5] as? Double) ?? (last[5] as? Int).map(Double.init) ?? 8
    }
}

// MARK: - Threshold helpers

private func sfiColor(_ sfi: Double) -> Color {
    if sfi >= 150 { return .green }
    if sfi >= 100 { return .yellow }
    return .red
}

private func sfiLabel(_ sfi: Double) -> String {
    if sfi >= 150 { return "High" }
    if sfi >= 100 { return "Moderate" }
    return "Low"
}

private func kColor(_ k: Double) -> Color {
    if k <= 2 { return .green }
    if k <= 4 { return .yellow }
    return .red
}

private func kLabel(_ k: Double) -> String {
    if k <= 2 { return "Quiet" }
    if k <= 4 { return "Unsettled" }
    return "Stormy"
}

private func aColor(_ a: Double) -> Color {
    if a <= 7 { return .green }
    if a <= 29 { return .yellow }
    return .red
}

private func aLabel(_ a: Double) -> String {
    if a <= 7 { return "Quiet" }
    if a <= 29 { return "Active" }
    return "Storm"
}

// MARK: - Bands Widget Views

struct BandsSmallView: View {
    let entry: BandEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(entry.overallRating.color)
                Text("Bands")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if let best = entry.bestBand {
                Text(best.band)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(best.rating.color)
                Text(best.rating.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(best.rating.color.opacity(0.85))
            } else {
                Text("Poor")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 0)

            HStack {
                Text("SFI \(Int(entry.sfi))")
                Spacer()
                Text("K \(String(format: "%.1f", entry.kIndex))")
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
        }
    }
}

struct BandsMediumView: View {
    let entry: BandEntry

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(entry.overallRating.color)
                    Text("Bands")
                        .font(.system(size: 12, weight: .semibold))
                }
                if let best = entry.bestBand {
                    Text(best.band)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(best.rating.color)
                    Text("Best now")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("SFI \(Int(entry.sfi))  K \(String(format: "%.1f", entry.kIndex))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(entry.bands) { band in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(band.rating.color)
                            .frame(width: 8, height: 8)
                        Text(band.band)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .frame(width: 30, alignment: .leading)
                        Text(band.rating.rawValue)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct BandsLargeView: View {
    let entry: BandEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(entry.overallRating.color)
                    Text("HamBand")
                        .font(.system(size: 15, weight: .bold))
                }
                Spacer()
                Text(entry.date, style: .time)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                SolarTile(label: "SFI", value: "\(Int(entry.sfi))", subtitle: sfiLabel(entry.sfi), color: sfiColor(entry.sfi))
                SolarTile(label: "K", value: String(format: "%.1f", entry.kIndex), subtitle: kLabel(entry.kIndex), color: kColor(entry.kIndex))
                SolarTile(label: "A", value: "\(Int(entry.aIndex))", subtitle: aLabel(entry.aIndex), color: aColor(entry.aIndex))
            }

            Spacer(minLength: 10)

            VStack(spacing: 0) {
                ForEach(Array(entry.bands.enumerated()), id: \.element.id) { index, band in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(band.rating.color)
                            .frame(width: 10, height: 10)
                        Text(band.band)
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .frame(width: 40, alignment: .leading)
                        Text(band.rating.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(band.rating.color)
                        Spacer()
                        Text(band.note)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxHeight: .infinity)

                    if index < entry.bands.count - 1 {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Solar Flux Widget Views

struct SolarSmallView: View {
    let entry: BandEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
                Text("Solar Flux")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text("\(Int(entry.sfi))")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(sfiColor(entry.sfi))
            Text(sfiLabel(entry.sfi))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(sfiColor(entry.sfi).opacity(0.85))

            Spacer(minLength: 0)

            HStack {
                Text("K \(String(format: "%.1f", entry.kIndex))")
                Spacer()
                Text("A \(Int(entry.aIndex))")
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
        }
    }
}

struct SolarMediumView: View {
    let entry: BandEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
                Text("Solar Indices")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(entry.date, style: .time)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                SolarTile(label: "SFI", value: "\(Int(entry.sfi))", subtitle: sfiLabel(entry.sfi), color: sfiColor(entry.sfi))
                SolarTile(label: "K", value: String(format: "%.1f", entry.kIndex), subtitle: kLabel(entry.kIndex), color: kColor(entry.kIndex))
                SolarTile(label: "A", value: "\(Int(entry.aIndex))", subtitle: aLabel(entry.aIndex), color: aColor(entry.aIndex))
            }

            Spacer(minLength: 0)
        }
    }
}

struct SolarLargeView: View {
    let entry: BandEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text("Solar Indices")
                        .font(.system(size: 15, weight: .bold))
                }
                Spacer()
                Text(entry.date, style: .time)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                BigSolarTile(label: "SFI", value: "\(Int(entry.sfi))", subtitle: sfiLabel(entry.sfi), color: sfiColor(entry.sfi))
                BigSolarTile(label: "K", value: String(format: "%.1f", entry.kIndex), subtitle: kLabel(entry.kIndex), color: kColor(entry.kIndex))
                BigSolarTile(label: "A", value: "\(Int(entry.aIndex))", subtitle: aLabel(entry.aIndex), color: aColor(entry.aIndex))
            }
            .frame(maxHeight: .infinity)

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 0) {
                IndexExplainer(symbol: "antenna.radiowaves.left.and.right", title: "SFI", text: sfiExplain(entry.sfi))
                    .frame(maxHeight: .infinity)
                Divider().opacity(0.4)
                IndexExplainer(symbol: "waveform.path", title: "K-Index", text: kExplain(entry.kIndex))
                    .frame(maxHeight: .infinity)
                Divider().opacity(0.4)
                IndexExplainer(symbol: "bolt.horizontal", title: "A-Index", text: aExplain(entry.aIndex))
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func sfiExplain(_ s: Double) -> String {
        if s >= 150 { return "High flux — 10m & 15m open for DX." }
        if s >= 100 { return "Moderate flux — 20m & 15m usable." }
        return "Low flux — higher bands mostly closed."
    }
    private func kExplain(_ k: Double) -> String {
        if k <= 2 { return "Quiet geomagnetic field." }
        if k <= 4 { return "Unsettled — minor degradation." }
        return "Storm — bands may be disrupted."
    }
    private func aExplain(_ a: Double) -> String {
        if a <= 7 { return "Calm daily average." }
        if a <= 29 { return "Active daily average." }
        return "Storm-level daily activity."
    }
}

// MARK: - Reusable Tiles

struct SolarTile: View {
    let label: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(color.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct BigSolarTile: View {
    let label: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium)) 
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
            Text(subtitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color.opacity(0.85))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct IndexExplainer: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text(text)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

// MARK: - Widgets

struct HamBandsWidget: Widget {
    let kind: String = "HamBandsBandsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BandProvider()) { entry in
            BandsEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("HF Bands")
        .description("Best HF band right now and the full band table.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct BandsEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: BandEntry

    var body: some View {
        switch family {
        case .systemSmall: BandsSmallView(entry: entry)
        case .systemMedium: BandsMediumView(entry: entry)
        case .systemLarge: BandsLargeView(entry: entry)
        default: BandsSmallView(entry: entry)
        }
    }
}

struct SolarFluxWidget: Widget {
    let kind: String = "HamBandsSolarFluxWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BandProvider()) { entry in
            SolarEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Solar Indices")
        .description("Live solar flux, K-index, and A-index.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct SolarEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: BandEntry

    var body: some View {
        switch family {
        case .systemSmall: SolarSmallView(entry: entry)
        case .systemMedium: SolarMediumView(entry: entry)
        case .systemLarge: SolarLargeView(entry: entry)
        default: SolarSmallView(entry: entry)
        }
    }
}

// MARK: - Previews

#Preview("Bands Small", as: .systemSmall) {
    HamBandsWidget()
} timeline: { BandEntry.placeholder }

#Preview("Bands Medium", as: .systemMedium) {
    HamBandsWidget()
} timeline: { BandEntry.placeholder }

#Preview("Bands Large", as: .systemLarge) {
    HamBandsWidget()
} timeline: { BandEntry.placeholder }

#Preview("Solar Small", as: .systemSmall) {
    SolarFluxWidget()
} timeline: { BandEntry.placeholder }

#Preview("Solar Medium", as: .systemMedium) {
    SolarFluxWidget()
} timeline: { BandEntry.placeholder }

#Preview("Solar Large", as: .systemLarge) {
    SolarFluxWidget()
} timeline: { BandEntry.placeholder }
