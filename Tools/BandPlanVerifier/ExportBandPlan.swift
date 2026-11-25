// Prints the app's band plan (HamBands/BandPrivileges.swift) as JSON so
// verify_band_plan.py can compare it with the FCC rules on eCFR.
// Built and run by verify_band_plan.sh; not part of the app target.

import Foundation

struct ExportSegment: Encodable {
    let lowKHz: Double
    let highKHz: Double
    let minimumClass: String
    let mode: String
    let technicianMode: String?
    let restriction: String?
}

struct ExportBand: Encodable {
    let name: String
    let lowKHz: Double
    let highKHz: Double
    let segments: [ExportSegment]
    let channelsKHz: [Double]
    let channelMinimumClass: String
    let notes: [String]
}

struct Export: Encodable {
    let rulesCurrentThrough: String
    let watchedSections: [String]
    let bands: [ExportBand]
}

@main
struct ExportBandPlan {
    static func main() throws {
        let export = Export(
            rulesCurrentThrough: BandPlan.rulesCurrentThrough.formatted(.iso8601.year().month().day()),
            watchedSections: BandPlan.watchedSections,
            bands: BandPlan.bands.map { band in
                ExportBand(
                    name: band.name,
                    lowKHz: band.lowKHz,
                    highKHz: band.highKHz,
                    segments: band.segments.map {
                        ExportSegment(lowKHz: $0.lowKHz, highKHz: $0.highKHz,
                                      minimumClass: $0.minimumClass.rawValue, mode: $0.mode.rawValue,
                                      technicianMode: $0.technicianMode?.rawValue, restriction: $0.restriction)
                    },
                    channelsKHz: band.channelsKHz,
                    channelMinimumClass: band.channelMinimumClass.rawValue,
                    notes: band.notes)
            })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(export))
    }
}
