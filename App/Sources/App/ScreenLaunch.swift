#if DEBUG
import Foundation
import Model

/// A screen of the app with a made-up library, for its screenshots
/// (App/ScreenTests, `make screenshots`) and for opening a screen by hand:
/// `-screenLibrary example` (or `longHistory`) opens a made-up library in
/// memory, with the real planner, no network and settings of its own, and
/// `-screen` the screen to start on (`overview`, `plan`, `progress` or
/// `whatIf`; `targetMix`, the Target mix sheet of the first plan with
/// changes with age). The main plan is calculated at once, with fewer runs than it
/// says, so the plan's screens fill in quickly; not with `-screenNoRun`.
/// `-screenLibrary empty` opens first launch instead, on the step `-screen`
/// names (``OnboardingStep``: `welcome`, `location`, `you`, `money`,
/// `accounts` or `disclaimer`). Debug builds only.
struct ScreenLaunch {
    /// The made-up libraries: ``PreviewLibrary/library`` and
    /// ``PreviewLibrary/withLongHistory``; or none, for first launch.
    enum Sample: String, CaseIterable {
        case example
        case longHistory
        /// No library yet: first launch, on ``ScreenLaunch/onboardingStep``.
        case empty

        var library: Library {
            switch self {
            case .example: PreviewLibrary.library
            case .longHistory: PreviewLibrary.withLongHistory
            case .empty: Library()
            }
        }
    }

    enum Screen: String, CaseIterable {
        case overview
        case plan
        case progress
        case whatIf
        case targetMix
    }

    var library: Library
    var screen: Screen
    /// Whether the main plan is calculated at launch.
    var calculates: Bool
    /// The step of first launch to open on, with ``Sample/empty``; `nil`
    /// with a library.
    var onboardingStep: OnboardingStep?

    /// `sample` on `screen`; ``Sample/empty`` opens first launch's welcome.
    init(_ sample: Sample, screen: Screen, calculates: Bool = true) {
        library = sample.library
        self.screen = screen
        self.calculates = calculates
        onboardingStep = sample == .empty ? .welcome : nil
        for id in library.plans.keys {
            library.plans[id]?.simulation.runs = 400
        }
    }

    /// First launch on `step`. Before *Create library* there's no library;
    /// from the accounts step on, the library is the one *Create library*
    /// leaves (``createdLibrary``).
    init(firstLaunchAt step: OnboardingStep) {
        library = step.comesAfterCreating ? Self.createdLibrary : Library()
        screen = .overview
        calculates = false
        onboardingStep = step
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
        if sample == .empty {
            self.init(firstLaunchAt: value(of: "-screen").flatMap(OnboardingStep.init(rawValue:)) ?? .welcome)
            return
        }
        self.init(sample, screen: value(of: "-screen").flatMap(Screen.init(rawValue:)) ?? .overview,
                  calculates: !arguments.contains("-screenNoRun"))
    }

    /// What *Create library* leaves, for first launch's last steps: the
    /// example library's settings, the starter plan "Base case" spending
    /// 2.500 a month and retiring at 60, and no accounts yet.
    static var createdLibrary: Library {
        var settings = PreviewLibrary.library.settings
        settings.mainPlan = nil
        var library = Library(settings: settings)
        if let plan = PlanEditing.starterPlan(
            id: "base-case", name: PlanEditing.starterPlanName, library: library,
            asOf: PreviewLibrary.latestCheckIn, payPerMonth: nil, spendingPerMonth: 2_500, retirementAge: 60) {
            library.plans[plan.id] = plan
            library.settings.mainPlan = plan.id
        }
        return library
    }

    @MainActor
    func model() -> AppModel {
        let suite = "screen-launch"
        UserDefaults().removePersistentDomain(forName: suite)
        if let onboardingStep {
            return firstLaunchModel(on: onboardingStep, defaults: suite)
        }
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
        case .targetMix:
            let plans = library.plans.values.sorted { $0.id.rawValue < $1.id.rawValue }
            navigation.showPlan(plans.first { !$0.portfolio.targetMixByAge.isEmpty }?.id ?? main)
            navigation.requestsTargetMix = true
        }
        if calculates, let main {
            // As the root view does once a library is open; a library in
            // memory is open from the start.
            Task { _ = await model.plans.run(main) }
        }
        return model
    }

    /// First launch on `step`. Before *Create library*, a store without a
    /// library, which would create one in a new temporary folder; from the
    /// accounts step on, ``library`` in memory, with onboarding still
    /// showing as *Create library* leaves it.
    @MainActor
    private func firstLaunchModel(on step: OnboardingStep, defaults suite: String) -> AppModel {
        let model: AppModel
        if step.comesAfterCreating {
            model = AppModel.preview(library, planEngine: PlannerPlanEngine(), defaults: suite)
            model.navigation.finishesOnboarding = true
        } else {
            let preferences = AppPreferences(defaults: UserDefaults(suiteName: suite) ?? .standard)
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("screen-launch-\(UUID().uuidString)", isDirectory: true)
            model = AppModel(preferences: preferences, library: .needingSetup(in: folder, preferences: preferences),
                             prices: PriceStore(service: nil), planEngine: PlannerPlanEngine(), draftURL: nil)
        }
        model.navigation.requestedOnboardingStep = step
        return model
    }
}
#endif
