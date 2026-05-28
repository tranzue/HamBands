import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            BandConditionsTab()
                .tabItem {
                    Label("Bands", systemImage: "antenna.radiowaves.left.and.right")
                }

            TrendView()
                .tabItem {
                    Label("Trend", systemImage: "chart.line.uptrend.xyaxis")
                }
        }
    }
}

// MARK: - Bands Tab

struct BandConditionsTab: View {
    @StateObject private var vm = BandViewModel()
    @State private var titleTapCount = 0
    @State private var showEasterEgg = false
    @State private var showPerfectConditions = false
    @State private var titleTapTimer: Timer? = nil

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
                            if let solar = vm.solarData {
                                // Perfect K=0 banner
                                if solar.kIndex == 0 {
                                    PerfectConditionsBanner()
                                }
                                SolarHeaderView(solar: solar)
                            }

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
            .navigationTitle("HamBand")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("HamBand")
                        .font(.headline)
                        .onTapGesture(count: 1) {
                            titleTapCount += 1
                            titleTapTimer?.invalidate()
                            titleTapTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
                                titleTapCount = 0
                            }
                            if titleTapCount >= 5 {
                                titleTapCount = 0
                                titleTapTimer?.invalidate()
                                showEasterEgg = true
                            }
                        }
                }
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
        .alert("73 de KD3CLW", isPresented: $showEasterEgg) {
            Button("73!", role: .cancel) {}
        } message: {
            Text("You found the secret frequency.\n\nHamBand was built by Taylor, KD3CLW, from Ford City, PA.\n\nGood DX & clear skies. 73.")
        }
    }
}

// MARK: - Perfect Conditions Banner

struct PerfectConditionsBanner: View {
    @State private var visible = false

    var body: some View {
        HStack(spacing: 10) {
            Text("🏆")
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Perfect Conditions")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Text("K-Index is 0 — as quiet as it gets")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [Color.green.opacity(0.85), Color.teal.opacity(0.75)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .padding(.horizontal)
        .scaleEffect(visible ? 1.0 : 0.92)
        .opacity(visible ? 1.0 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                visible = true
            }
        }
    }
}

// MARK: - Solar Header

struct SolarHeaderView: View {
    let solar: SolarData
    @State private var showSFIInfo = false
    @State private var showKInfo = false

    var body: some View {
        HStack(spacing: 0) {
            Button {
                showSFIInfo = true
            } label: {
                StatTile(
                    label: "SFI",
                    value: String(format: "%.0f", solar.solarFluxIndex),
                    color: solar.solarFluxIndex >= 150 ? .green : solar.solarFluxIndex >= 120 ? .yellow : .red
                )
            }
            .buttonStyle(.plain)
            .alert("Solar Flux Index (SFI)", isPresented: $showSFIInfo) {
                Button("Got it", role: .cancel) {}
            } message: {
                Text("The Solar Flux Index measures the radio energy output of the sun at 10.7cm wavelength. Higher values mean more ionization of the ionosphere, which opens up higher HF bands.\n\n• < 100 — Low, higher bands mostly closed\n• 100–149 — Moderate, 20m–15m usable\n• 150+ — High, 10m often open for DX")
            }

            Divider().frame(height: 40)

            Button {
                showKInfo = true
            } label: {
                StatTile(
                    label: "K-Index",
                    value: String(format: "%.1f", solar.kIndex),
                    color: solar.kIndex <= 2 ? .green : solar.kIndex <= 4 ? .yellow : .red
                )
            }
            .buttonStyle(.plain)
            .alert("K-Index", isPresented: $showKInfo) {
                Button("Got it", role: .cancel) {}
            } message: {
                Text("The K-Index measures geomagnetic disturbance on a scale of 0–9. Lower is better for HF propagation. High K values (geomagnetic storms) can absorb or disrupt radio signals, especially on lower bands.\n\n• 0–2 — Quiet, excellent conditions\n• 3–4 — Unsettled, minor degradation\n• 5–6 — Storm, significant disruption\n• 7–9 — Severe storm, bands may go dark")
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
    }
}

// MARK: - Subviews

struct StatTile: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
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
