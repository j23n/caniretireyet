#if DEBUG
import Foundation
import Model

/// The UI tests' launch (App/UITests): `-uiTestLibrary example` (or
/// `longHistory`) opens a made-up library in memory, with the real planner,
/// no network and settings of its own, and `-uiTestScreen` the screen to
/// start on (`overview`, `plan`, `progress` or `whatIf`), so each
/// screenshot is one launch. The main plan is calculated at once, with
/// fewer runs than it says, so the plan's screens fill in quickly. Debug
/// builds only.
struct UITestLaunch {
    enum Screen: String {
        case overview
        case plan
        case progress
        case whatIf
    }

    var library: Library
    var screen: Screen

    /// `nil` without `-uiTestLibrary` and a library it knows.
    init?(arguments: [String]) {
        func value(of name: String) -> String? {
            guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
                return nil
            }
            return arguments[index + 1]
        }
        switch value(of: "-uiTestLibrary") {
        case "example": library = PreviewLibrary.library
        case "longHistory": library = PreviewLibrary.withLongHistory
        default: return nil
        }
        screen = value(of: "-uiTestScreen").flatMap(Screen.init(rawValue:)) ?? .overview
        for id in library.plans.keys {
            library.plans[id]?.simulation.runs = 400
        }
    }

    @MainActor
    func model() -> AppModel {
        let suite = "ui-tests"
        UserDefaults().removePersistentDomain(forName: suite)
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        let model = AppModel(
            preferences: AppPreferences(defaults: defaults), privacy: PrivacySettings(defaults: defaults),
            library: .inMemory(library), prices: PriceStore(service: nil), planEngine: PlannerPlanEngine(),
            draftURL: nil)
        let navigation = model.navigation
        // The main plan by its ID: the sidebar turns "the main plan" into its
        // row, a new Plan screen, after the first one took the requests.
        let main = library.settings.mainPlan
        switch screen {
        case .overview:
            navigation.showOverview()
        case .plan:
            navigation.showPlan(main)
        case .progress:
            navigation.showPlan(main)
            navigation.requestedPlanPart = .progress
        case .whatIf:
            navigation.showPlan(main)
            navigation.requestsWhatIf = true
        }
        if let main {
            Task { _ = await model.plans.run(main) }
        }
        return model
    }
}
#endif
