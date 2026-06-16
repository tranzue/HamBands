import SwiftUI
import Charts
import Combine

// MARK: - Data Models

struct TrendDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let type: TrendType
}

enum TrendType: String, CaseIterable {
    case kIndex = "K-Index"
    case sfi = "SFI"
}

// MARK: - ViewModel

@MainActor
class TrendViewModel: ObservableObject {
    @Published var kIndexPoints: [TrendDataPoint] = []
    @Published var sfiPoints: [TrendDataPoint] = []
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    @Published var selectedMetric: TrendType = .kIndex

    func fetch() async {
        isLoading = true
        errorMessage = nil

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        let session = URLSession(configuration: config)

        async let kTask = fetchKIndexHistory(session: session)
        async let sfiTask = fetchSFIHistory(session: session)

        let kPoints = await kTask
        let sfiPoints = await sfiTask

        self.kIndexPoints = kPoints
        self.sfiPoints = sfiPoints
        isLoading = false
    }

    private func parseKVal(_ raw: Any) -> Double? {
        if let s = raw as? String { return Double(s) }
        if let d = raw as? Double { return d }
        if let n = raw as? NSNumber { return n.doubleValue }
        return nil
    }

    private func parseNOAADate(_ raw: String) -> Date? {
        // Format 1: ISO8601 with T separator e.g. "2026-05-21T00:00:00"
        let iso = ISO8601DateFormatter()
        iso.timeZone = TimeZone(identifier: "UTC")
        iso.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        if let d = iso.date(from: raw) { return d }

        // Format 2: space separator with milliseconds e.g. "2026-05-21 00:00:00.000"
        let df1 = DateFormatter()
        df1.locale = Locale(identifier: "en_US_POSIX")
        df1.timeZone = TimeZone(identifier: "UTC")
        df1.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        if let d = df1.date(from: raw) { return d }

        // Format 3: space separator no millis e.g. "2026-05-21 00:00:00"
        let df2 = DateFormatter()
        df2.locale = Locale(identifier: "en_US_POSIX")
        df2.timeZone = TimeZone(identifier: "UTC")
        df2.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df2.date(from: raw)
    }

    private func fetchKIndexHistory(session: URLSession) async -> [TrendDataPoint] {
        guard let url = URL(string: "https://services.swpc.noaa.gov/products/noaa-planetary-k-index.json") else { return [] }
        do {
            let (data, _) = try await session.data(from: url)

            struct KEntry: Decodable {
                let time_tag: String
                let Kp: Double
            }

            let entries = try JSONDecoder().decode([KEntry].self, from: data)
            let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()

            return entries.compactMap { entry -> TrendDataPoint? in
                guard let date = parseNOAADate(entry.time_tag),
                      date >= cutoff
                else { return nil }
                return TrendDataPoint(date: date, value: entry.Kp, type: .kIndex)
            }.sorted { $0.date < $1.date }

        } catch {
            print("K-INDEX fetch error: \(error)")
            return []
        }
    }

    private func fetchSFIHistory(session: URLSession) async -> [TrendDataPoint] {
        guard let url = URL(string: "https://services.swpc.noaa.gov/json/f107_cm_flux.json") else { return [] }
        do {
            let (data, _) = try await session.data(from: url)

            struct F107Entry: Decodable {
                let time_tag: String
                let flux: Double?
            }

            let entries = try JSONDecoder().decode([F107Entry].self, from: data)
            let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()

            return entries.compactMap { entry -> TrendDataPoint? in
                guard let flux = entry.flux,
                      let date = parseNOAADate(entry.time_tag),
                      date >= cutoff
                else { return nil }
                return TrendDataPoint(date: date, value: flux, type: .sfi)
            }.sorted { $0.date < $1.date }

        } catch {
            print("SFI fetch error: \(error)")
            return []
        }
    }

    var kIndexDomain: ClosedRange<Double> { 0...9 }
    var sfiDomain: ClosedRange<Double> {
        let values = sfiPoints.map { $0.value }
        let min = (values.min() ?? 70) - 10
        let max = (values.max() ?? 200) + 10
        return min...max
    }

    var activePoints: [TrendDataPoint] {
        selectedMetric == .kIndex ? kIndexPoints : sfiPoints
    }

    var activeDomain: ClosedRange<Double> {
        selectedMetric == .kIndex ? kIndexDomain : sfiDomain
    }
}

// MARK: - View

struct TrendView: View {
    @StateObject private var vm = TrendViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                Picker("Metric", selection: $vm.selectedMetric) {
                    ForEach(TrendType.allCases, id: \.self) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)

                if vm.isLoading {
                    Spacer()
                    ProgressView("Loading trend data...")
                        .foregroundStyle(.secondary)
                    Spacer()

                } else if let error = vm.errorMessage {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") { Task { await vm.fetch() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    Spacer()

                } else {
                    chartSection
                    legendSection
                }
            }
            .navigationTitle("7-Day Trend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await vm.fetch() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                await vm.fetch()
            }
        }
    }

    @ViewBuilder
    var chartSection: some View {
        Chart(vm.activePoints) { point in
            LineMark(
                x: .value("Time", point.date),
                y: .value(vm.selectedMetric.rawValue, point.value)
            )
            .foregroundStyle(lineColor)
            .interpolationMethod(.catmullRom)

            AreaMark(
                x: .value("Time", point.date),
                yStart: .value("Min", vm.activeDomain.lowerBound),
                yEnd: .value(vm.selectedMetric.rawValue, point.value)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [lineColor.opacity(0.25), lineColor.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)

            if vm.selectedMetric == .kIndex {
                RuleMark(y: .value("Storm threshold", 5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.red.opacity(0.6))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Storm K≥5")
                            .font(.caption2)
                            .foregroundStyle(.red.opacity(0.7))
                    }
            }
        }
        .chartYScale(domain: vm.activeDomain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 1)) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .frame(height: 260)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    var lineColor: Color {
        vm.selectedMetric == .kIndex ? .blue : .orange
    }

    @ViewBuilder
    var legendSection: some View {
        VStack(spacing: 12) {
            Divider()

            if vm.selectedMetric == .kIndex {
                kIndexLegend
            } else {
                sfiLegend
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    var kIndexLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("K-Index Reference")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 16) {
                legendItem(color: .green, label: "K 0–2", sublabel: "Quiet")
                legendItem(color: .yellow, label: "K 3–4", sublabel: "Unsettled")
                legendItem(color: .orange, label: "K 5–6", sublabel: "Storm")
                legendItem(color: .red, label: "K 7–9", sublabel: "Severe")
            }

            if let latest = vm.kIndexPoints.last {
                summaryRow(label: "Current K-Index", value: String(format: "%.1f", latest.value), color: kIndexColor(latest.value))
            }
        }
    }

    var sfiLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Solar Flux Index Reference")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 16) {
                legendItem(color: .red, label: "< 100", sublabel: "Low")
                legendItem(color: .yellow, label: "100–149", sublabel: "Moderate")
                legendItem(color: .green, label: "≥ 150", sublabel: "High")
            }

            if let latest = vm.sfiPoints.last {
                summaryRow(label: "Current SFI", value: String(format: "%.0f", latest.value), color: sfiColor(latest.value))
            }
        }
    }

    func legendItem(color: Color, label: String, sublabel: String) -> some View {
        VStack(spacing: 2) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.caption2)
                .fontWeight(.semibold)
            Text(sublabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    func summaryRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
        .padding(.top, 4)
    }

    func kIndexColor(_ k: Double) -> Color {
        switch k {
        case ..<3: return .green
        case 3..<5: return .yellow
        case 5..<7: return .orange
        default: return .red
        }
    }

    func sfiColor(_ sfi: Double) -> Color {
        switch sfi {
        case ..<100: return .red
        case 100..<150: return .yellow
        default: return .green
        }
    }
}

#Preview {
    TrendView()
}
