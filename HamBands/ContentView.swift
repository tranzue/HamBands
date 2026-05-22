import SwiftUI

struct ContentView: View {
    @StateObject private var vm = BandViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    ProgressView("Fetching space weather…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = vm.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text(error)
                            .foregroundStyle(.secondary)
                        Button("Retry") { Task { await vm.fetch() } }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Solar data header
                            if let solar = vm.solarData {
                                SolarHeaderView(solar: solar)
                            }

                            // Band list
                            VStack(spacing: 10) {
                                ForEach(vm.bands) { band in
                                    BandRowView(band: band)
                                }
                            }
                            .padding(.horizontal)

                            Text("Updated \(vm.solarData?.fetchedAt.formatted(.relative(presentation: .named)) ?? "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.bottom)
                        }
                        .padding(.top)
                    }
                    .refreshable { await vm.fetch() }
                }
            }
            .navigationTitle("HamBands")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await vm.fetch() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .task { await vm.fetch() }
    }
}

struct SolarHeaderView: View {
    let solar: SolarData

    var body: some View {
        HStack(spacing: 0) {
            StatTile(label: "SFI", value: String(format: "%.0f", solar.solarFluxIndex), color: solar.solarFluxIndex >= 150 ? .green : solar.solarFluxIndex >= 120 ? .yellow : .red)
            Divider().frame(height: 40)
            StatTile(label: "K-index", value: String(format: "%.1f", solar.kIndex), color: solar.kIndex <= 2 ? .green : solar.kIndex <= 4 ? .yellow : .red)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
    }
}

struct StatTile: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }
}

struct BandRowView: View {
    let band: BandCondition

    var body: some View {
        HStack {
            Circle()
                .fill(band.rating.color)
                .frame(width: 12, height: 12)
            Text(band.band)
                .font(.system(.title3, design: .monospaced, weight: .semibold))
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(band.rating.rawValue)
                    .font(.subheadline.weight(.medium))
                Text(band.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    ContentView()
}
