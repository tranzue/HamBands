import AppIntents
import WidgetKit

struct RefreshHamBandsIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh HamBands"
    static let isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
