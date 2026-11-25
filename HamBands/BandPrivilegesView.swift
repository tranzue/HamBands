import SwiftUI

// MARK: - Privileges tab

struct BandPrivilegesView: View {
    @AppStorage(LicenseClass.storageKey) private var license: LicenseClass = .technician
    @AppStorage("privileges.onlyMyBands") private var onlyMyBands = false
    @State private var watcher = FCCRuleWatcher()
    @State private var selectedBand: Band?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var columns: [GridItem] {
        let count = horizontalSizeClass == .regular ? 2 : 1
        return Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("License class", selection: $license) {
                        ForEach(LicenseClass.allCases) { Text($0.shortName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    RuleStatusCard(watcher: watcher)
                        .padding(.horizontal)

                    ModeLegend()
                        .padding(.horizontal)

                    Toggle("Only bands I can use", isOn: $onlyMyBands)
                        .font(.subheadline)
                        .padding(.horizontal)

                    ForEach(BandGroup.allCases) { group in
                        let bands = BandPlan.bands.filter {
                            $0.group == group && (!onlyMyBands || $0.isAvailable(to: license))
                        }
                        if !bands.isEmpty {
                            Text(group.rawValue)
                                .font(.headline)
                                .padding(.horizontal)
                                .padding(.top, 4)
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(bands) { band in
                                    Button { selectedBand = band } label: {
                                        BandPrivilegeRow(band: band, license: license)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(BandPlan.generalNotes, id: \.self) { note in
                            Label(note, systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("Always check the current FCC rules before transmitting. This chart is a reference, not legal advice.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
                .padding(.top)
            }
            .refreshable { await watcher.check(force: true) }
            .themedScreenBackground()
            .navigationTitle("Privileges")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedBand) { band in
                BandDetailView(band: band, license: license)
            }
        }
        .task { await watcher.check() }
    }
}

// MARK: - FCC rule status

private struct RuleStatusCard: View {
    let watcher: FCCRuleWatcher

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                if case .outdated(let sections, _) = watcher.status {
                    ForEach(sections, id: \.self) { section in
                        Link("Read §\(section) on eCFR", destination: FCCRuleWatcher.sectionURL(section))
                            .font(.caption.weight(.medium))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .themedCard(cornerRadius: 12)
    }

    @ViewBuilder private var icon: some View {
        switch watcher.status {
        case .checking, .unknown:
            ProgressView().frame(width: 22)
        case .current:
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).font(.title3)
        case .outdated:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.title3)
        case .failed:
            Image(systemName: "wifi.exclamationmark").foregroundStyle(.secondary).font(.title3)
        }
    }

    private var title: String {
        switch watcher.status {
        case .unknown, .checking: "Checking FCC rules…"
        case .current: "Matches current FCC rules"
        case .outdated: "FCC rules have changed"
        case .failed: "Couldn't reach eCFR"
        }
    }

    private var detail: String {
        let reflected = Frequency.ruleDate(BandPlan.rulesCurrentThrough)
        switch watcher.status {
        case .unknown, .checking:
            return "Comparing this chart with 47 CFR Part 97 on eCFR."
        case .current(let latest):
            let checked = watcher.lastChecked.map { " Checked \($0.formatted(.relative(presentation: .named)))." } ?? ""
            return "Part 97 band rules last amended \(Frequency.ruleDate(latest)).\(checked)"
        case .outdated(_, let latest):
            return "Part 97 was amended \(Frequency.ruleDate(latest)). This chart reflects rules through \(reflected) and may be out of date."
        case .failed:
            return "Chart reflects FCC rules through \(reflected). Pull to retry."
        }
    }
}

// MARK: - Legend

private struct ModeLegend: View {
    var body: some View {
        let items: [ModeGroup] = [.cwOnly, .cwSSB, .data, .phone, .mixed, .all]
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(items) { mode in
                legendItem(color: mode.color, text: mode.label)
            }
            legendItem(color: .secondary.opacity(0.25), text: "Higher class only")
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(ModeGroup.all.color)
                    .overlay(RestrictedHatch())
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .frame(width: 14, height: 10)
                Text("Restricted, tap for rules").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 14, height: 10)
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Band row

struct BandPrivilegeRow: View {
    let band: Band
    let license: LicenseClass

    private var available: Bool { band.isAvailable(to: license) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(band.name)
                    .font(.system(.headline, design: .monospaced))
                Spacer()
                Text(Frequency.range(band.lowKHz, band.highKHz))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            BandBar(band: band, license: license)
                .frame(height: 22)

            if available {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(band.allowedRanges(for: license), id: \.low) { range in
                        HStack(spacing: 6) {
                            Circle().fill(range.mode.color).frame(width: 7, height: 7)
                            Text(Frequency.range(range.low, range.high))
                                .monospacedDigit()
                            Text(range.mode.label)
                                .foregroundStyle(.secondary)
                            if range.restriction != nil {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    if !band.channelsKHz.isEmpty, license >= band.channelMinimumClass {
                        HStack(spacing: 6) {
                            Circle().fill(ModeGroup.mixed.color).frame(width: 7, height: 7)
                            Text("+ \(band.channelsKHz.count) channels")
                        }
                    }
                    if band.hasRestrictions(for: license) {
                        Label("Restrictions apply. Tap before transmitting.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .fontWeight(.semibold)
                            .padding(.top, 2)
                    }
                }
                .font(.caption)
            } else {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .themedCard(cornerRadius: 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(band.name), \(Frequency.range(band.lowKHz, band.highKHz)). \(summary)")
        .accessibilityHint("Shows privileges for every license class")
    }

    private var summary: String {
        guard available else {
            let needed = (band.segments.map(\.minimumClass) + (band.channelsKHz.isEmpty ? [] : [band.channelMinimumClass])).min()
            return "Not available to \(license.name) licensees" + (needed.map { ". Requires \($0.name) or higher." } ?? ".")
        }
        var parts = band.allowedRanges(for: license).map {
            "\(Frequency.range($0.low, $0.high)) \($0.mode.label)" + ($0.restriction != nil ? ", restricted" : "")
        }
        if !band.channelsKHz.isEmpty, license >= band.channelMinimumClass {
            parts.append("\(band.channelsKHz.count) channels")
        }
        if band.hasRestrictions(for: license) {
            parts.append("Restrictions apply, open for details")
        }
        return parts.joined(separator: "; ")
    }
}

/// Draws a band to scale: colored where the license can transmit (by mode),
/// grey where only higher classes can, and empty where it isn't amateur spectrum.
struct BandBar: View {
    let band: Band
    let license: LicenseClass

    var body: some View {
        GeometryReader { geo in
            let x = { (kHz: Double) -> CGFloat in
                CGFloat((kHz - band.lowKHz) / (band.highKHz - band.lowKHz)) * geo.size.width
            }

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.secondary.opacity(0.3), lineWidth: 1)

                ForEach(band.segments) { segment in
                    let allowed = segment.isAllowed(for: license)
                    Rectangle()
                        .fill(allowed ? segment.mode(for: license).color : Color.secondary.opacity(0.25))
                        .overlay { if allowed && segment.restriction != nil { RestrictedHatch() } }
                        .clipped()
                        .frame(width: max(x(segment.highKHz) - x(segment.lowKHz) - 1, 2))
                        .offset(x: x(segment.lowKHz))
                }

                ForEach(band.channelsKHz, id: \.self) { channel in
                    let allowed = license >= band.channelMinimumClass
                    Rectangle()
                        .fill(allowed ? ModeGroup.mixed.color : Color.secondary.opacity(0.25))
                        .frame(width: 4)
                        .offset(x: x(channel) - 2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

/// Diagonal stripes marking a segment that is open to the class only under conditions.
struct RestrictedHatch: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 6
            }
            context.stroke(path, with: .color(.black.opacity(0.45)), lineWidth: 2)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Band detail

struct BandDetailView: View {
    let band: Band
    let license: LicenseClass
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    BandBar(band: band, license: license)
                        .frame(height: 30)
                        .listRowBackground(Color.clear)
                }

                Section("Segments") {
                    ForEach(band.segments) { segment in
                        SegmentRow(segment: segment, license: license)
                    }
                }

                if !band.channelsKHz.isEmpty {
                    Section("Channels (center frequency)") {
                        ForEach(band.channelsKHz, id: \.self) { channel in
                            HStack {
                                Text(Frequency.format(channel, unitHint: 1000)).monospacedDigit()
                                Spacer()
                                Text("\(band.channelMinimumClass.name)+").foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                    }
                }

                if !band.notes.isEmpty {
                    Section("Notes") {
                        ForEach(band.notes, id: \.self) { Text($0).font(.subheadline) }
                    }
                }

                Section {
                    Link("Read §97.301 on eCFR", destination: FCCRuleWatcher.sectionURL("97.301"))
                    Link("Read §97.305 (modes) on eCFR", destination: FCCRuleWatcher.sectionURL("97.305"))
                }
            }
            .navigationTitle(band.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct SegmentRow: View {
    let segment: BandSegment
    let license: LicenseClass

    private var allowed: Bool { segment.isAllowed(for: license) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(allowed ? segment.mode(for: license).color : Color.secondary.opacity(0.3))
                .frame(width: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(Frequency.range(segment.lowKHz, segment.highKHz))
                    .font(.subheadline.monospacedDigit().weight(.medium))
                Text(segment.mode.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let techMode = segment.technicianMode {
                    Text("Technician: \(techMode.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let restriction = segment.restriction {
                    Label(restriction, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                        .padding(.top, 2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(segment.minimumClass == .extra ? "Extra" : "\(segment.minimumClass.name)+")
                    .font(.caption.weight(.semibold))
                Image(systemName: !allowed ? "lock.fill"
                      : segment.restriction != nil ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(!allowed ? Color.secondary : segment.restriction != nil ? Color.orange : Color.green)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    BandPrivilegesView()
}
