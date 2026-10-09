#if DEBUG
import Foundation
import Model

/// The UI tests' launch (App/UITests): `-uiTestLibrary example` (or
/// `longHistory`) opens a made-up library in memory, with the real planner,
/// no network and settings of its own, and `-uiTestScreen` the screen to
/// start on (`overview`, `plan`, `progress` or `whatIf`), so each
/// screenshot is one launch. The main plan is calculated at once, with
/// fewer runs than it says, so the plan's screens fill in quickly; not with
/// `-uiTestNoRun`. `-uiTestKeepResults <name>` keeps the plans' results as
/// the app does, in a folder of the app's caches for that name, and shows
/// them again at launch, so a test can quit and open the app again. Debug
/// builds only.
struct UITestLaunch {
    enum Screen: String {
        case overview
        case plan
        case progress
        case whatIf
    }

    var library: Library
    /// The library's name in `-uiTestLibrary`.
    var name: String
    var screen: Screen
    /// `-uiTestKeepResults`: the folder's name.
    var keptResults: String?
    /// Whether the main plan is calculated at launch.
    var runsMainPlan: Bool

    /// `nil` without `-uiTestLibrary` and a library it knows.
    init?(arguments: [String]) {
        func value(of name: String) -> String? {
            guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
                return nil
            }
            return arguments[index + 1]
        }
        switch value(of: "-uiTestLibrary") {
        case "example": library = PreviewLibrary.library; name = "example"
        case "longHistory": library = PreviewLibrary.withLongHistory; name = "longHistory"
        default: return nil
        }
        screen = value(of: "-uiTestScreen").flatMap(Screen.init(rawValue:)) ?? .overview
        keptResults = value(of: "-uiTestKeepResults")
        runsMainPlan = !arguments.contains("-uiTestNoRun")
        for id in library.plans.keys {
            library.plans[id]?.simulation.runs = 400
        }
    }

    @MainActor
    func model() -> AppModel {
        let suite = "ui-tests"
        UserDefaults().removePersistentDomain(forName: suite)
        let model = AppModel.preview(library, planEngine: PlannerPlanEngine(), planResults: keptResultsArchive(),
                                     defaults: suite)
        if keptResults != nil {
            model.plans.inMemoryLibrary = URL(fileURLWithPath: "/ui-tests/\(name)", isDirectory: true)
        }
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
        let runsMainPlan = runsMainPlan
        Task {
            // As the root view does once a library is open; a library in
            // memory is open from the start.
            await model.plans.restoreKeptResults()
            if runsMainPlan, let main { _ = await model.plans.run(main) }
        }
        return model
    }

    /// With `-uiTestKeepResults`: `Caches/<bundle id>/UITestPlanResults/<name>`.
    private func keptResultsArchive() -> PlanResultsArchive? {
        guard let keptResults,
              let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return PlanResultsArchive(root: caches
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "CanIRetireYet", isDirectory: true)
            .appendingPathComponent("UITestPlanResults", isDirectory: true)
            .appendingPathComponent(keptResults, isDirectory: true))
    }
}
#endif
