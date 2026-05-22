import SwiftUI

struct ContentView: View {
    @StateObject private var vm = BandViewModel()

    var body: some View {
        Group {
            if vm.isLoading {
                ProgressView()
            } else {
                VStack(spacing: 6) {
                    if let best = vm.bestBand {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(best.rating.color)
                                .frame(width: 10, height: 10)
                            Text(best.band)
                                .font(.system(.title2, design: .monospaced, weight: .bold))
                        }
                        Text("Best band now")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if let solar = vm.solarData {
                        Divider()
                        HStack(spacing: 12) {
                            Label(String(format: "%.0f", solar.solarFluxIndex), systemImage: "sun.max")
                                .font(.caption2)
                            Label(String(format: "%.1f", solar.kIndex), systemImage: "waveform.path")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
        }
        .task { await vm.fetch() }
    }
}

#Preview {
    ContentView()
}
