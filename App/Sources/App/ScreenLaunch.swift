#if DEBUG
import Foundation
import Model

/// A screen of the app with a made-up library, for its screenshots
/// (App/ScreenTests, `make screenshots`) and for opening a screen by hand:
/// `-screenLibrary example` (or `longHistory`) opens a made-up library in
/// memory, with the real planner, no network and settings of its own, and
/// `-screen` the screen to start on (`overview`, `plan`, `progress` or
/// `whatIf`). The main plan is calculated at once, with fewer runs than it
/// says, so the plan's screens fill in quickly; not with `-screenNoRun`.
/// Debug builds only.
struct ScreenLaunch {
    /// The made-up libraries: ``PreviewLibrary/library`` and ``PreviewLibrary/withLongHistory``.
    enum Sample: String, CaseIterable {
        case example
        case longHistory

        var library: Library {
            switch self {
            case .example: PreviewLibrary.library
            case .longHistory: PreviewLibrary.withLongHistory
            }
        }
    }

    enum Screen: String, CaseIterable {
        case overview
        case plan
        case progress
        case whatIf
    }

    var library: Library
    var screen: Screen
    /// Whether the main plan is calculated at launch.
    var calculates: Bool

    init(_ sample: Sample, screen: Screen, calculates: Bool = true) {
        library = sample.library
        self.screen = screen
        self.calculates = calculates
        for id in library.plans.keys {
            library.plans[id]?.simulation.runs = 400
        }
    }

    /// `nil` without `-screenLibrary` and a library it knows.
    init?(arguments: [String]) {
        func value(of name: String) -> String? {
            guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
                return nil
            }
            return arguments[index + 1]
        }
        guard let sample = value(of: "-screenLibrary").flatMap(Sample.init(rawValue:)) else { return nil }
        self.init(sample, screen: value(of: "-screen").flatMap(Screen.init(rawValue:)) ?? .overview,
                  calculates: !arguments.contains("-screenNoRun"))
    }

    @MainActor
    func model() -> AppModel {
        let suite = "screen-launch"
        UserDefaults().removePersistentDomain(forName: suite)
        let model = AppModel.preview(library, planEngine: PlannerPlanEngine(), defaults: suite)
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
        if calculates, let main {
            // As the root view does once a library is open; a library in
            // memory is open from the start.
            Task { _ = await model.plans.run(main) }
        }
        return model
    }
}
#endif
