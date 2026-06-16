import SwiftUI
import MapKit
import Combine

// MARK: - Solar geometry

private struct SolarPosition {
    let declination: Double      // degrees, latitude of subsolar point
    let subsolarLongitude: Double // degrees, longitude where sun is overhead

    static func current(at date: Date = Date()) -> SolarPosition {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = cal.dateComponents([.hour, .minute, .second, .dayOfYear], from: date)
        let h = Double(comps.hour ?? 0)
        let m = Double(comps.minute ?? 0)
        let s = Double(comps.second ?? 0)
        let utcHours = h + m / 60 + s / 3600
        let n = Double(comps.dayOfYear ?? 1)

        // Declination — simple approximation good to ~½°.
        let dec = -23.44 * cos((2 * .pi / 365.0) * (n + 10))

        // Subsolar longitude — sun moves 15° west per UTC hour, over 0° at noon UTC.
        let lon = normalizeLongitude((12.0 - utcHours) * 15.0)

        return SolarPosition(declination: dec, subsolarLongitude: lon)
    }
}

private func normalizeLongitude(_ lon: Double) -> Double {
    var l = lon.truncatingRemainder(dividingBy: 360)
    if l > 180 { l -= 360 }
    if l < -180 { l += 360 }
    return l
}

// Points on the great circle 90° away from the subsolar point.
private func terminatorCoordinates(_ position: SolarPosition, steps: Int = 360) -> [CLLocationCoordinate2D] {
    let dec = position.declination * .pi / 180
    let sub = position.subsolarLongitude * .pi / 180

    // Unit basis for the terminator plane (perpendicular to subsolar vector).
    let ux = -sin(sub),                uy = cos(sub),                 uz = 0.0
    let vx = -sin(dec) * cos(sub),     vy = -sin(dec) * sin(sub),     vz = cos(dec)

    var coords: [CLLocationCoordinate2D] = []
    coords.reserveCapacity(steps + 1)
    for i in 0...steps {
        let t = Double(i) / Double(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = ux * c + vx * s
        let y = uy * c + vy * s
        let z = uz * c + vz * s
        let lat = asin(max(-1.0, min(1.0, z))) * 180 / .pi
        let lon = atan2(y, x) * 180 / .pi
        coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
    }
    return coords
}

// Splits a polyline at antimeridian crossings so MapKit doesn't draw a line across the world.
private func splitAtAntimeridian(_ coords: [CLLocationCoordinate2D]) -> [[CLLocationCoordinate2D]] {
    var segments: [[CLLocationCoordinate2D]] = []
    var current: [CLLocationCoordinate2D] = []
    for c in coords {
        if let prev = current.last, abs(prev.longitude - c.longitude) > 180 {
            segments.append(current)
            current = []
        }
        current.append(c)
    }
    if !current.isEmpty { segments.append(current) }
    return segments
}

// MARK: - View

struct GreylineView: View {
    @State private var solar: SolarPosition = .current()
    @State private var now: Date = Date()
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                mapView
                infoPanel
            }
            .navigationTitle("Greyline")
            .navigationBarTitleDisplayMode(.inline)
            .onReceive(timer) { newNow in
                now = newNow
                solar = SolarPosition.current(at: newNow)
            }
        }
    }

    // MARK: Map

    private var mapView: some View {
        let segments = splitAtAntimeridian(terminatorCoordinates(solar))
        let subsolar = CLLocationCoordinate2D(latitude: solar.declination, longitude: solar.subsolarLongitude)
        let antisolar = CLLocationCoordinate2D(
            latitude: -solar.declination,
            longitude: normalizeLongitude(solar.subsolarLongitude + 180)
        )

        return Map(initialPosition: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 140, longitudeDelta: 360)
        ))) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                MapPolyline(coordinates: seg)
                    .stroke(.orange, lineWidth: 3)
            }
            Marker("Sun", systemImage: "sun.max.fill", coordinate: subsolar)
                .tint(.yellow)
            Marker("Midnight", systemImage: "moon.fill", coordinate: antisolar)
                .tint(.indigo)
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted))
    }

    // MARK: Info panel

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .foregroundStyle(.tint)
                Text("Greyline Tracker")
                    .font(.headline)
                Spacer()
                Text(utcText)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                infoItem(label: "Sun Lat", value: formatDeg(solar.declination))
                infoItem(label: "Sun Lon", value: formatDeg(solar.subsolarLongitude))
                infoItem(label: "Season", value: seasonHint)
            }

            Text("The greyline is the band of twilight between day and night. Low bands (160m, 80m, 40m) work DX best when your QTH sits on or near this line — the ionospheric D-layer collapses at sunset and forms at sunrise, briefly opening propagation paths that are otherwise absorbed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private func infoItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var utcText: String {
        let df = DateFormatter()
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "HH:mm 'UTC'"
        return df.string(from: now)
    }

    private func formatDeg(_ v: Double) -> String {
        String(format: "%+.1f°", v)
    }

    private var seasonHint: String {
        if solar.declination > 10 { return "N tilt" }
        if solar.declination < -10 { return "S tilt" }
        return "Equinox"
    }
}

#Preview {
    GreylineView()
}
