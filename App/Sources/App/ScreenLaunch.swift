#if DEBUG
import Foundation
import Model
import Planner
import SwiftUI

/// A screen of the app with a made-up library, for its screenshots
/// (App/ScreenTests, `make screenshots`) and for opening a screen by hand:
/// `-screenLibrary example` (or `longHistory` or `longAccountName`) opens a
/// made-up library in memory, with the real planner, no network and settings
/// of its own, and `-screen` the screen to start on (`today`, `plan`,
/// `whatIf`; `year`, `decades` or `lookBack`, the Timeline at that zoom;
/// `targetMix`, the Target mix sheet of the first plan with changes with
/// age; `accounts`, the accounts list;
/// `tradesAccount` or `cashAccount`, an account's
/// details; `checkIn`, the October check-in under way, from
/// `CheckInPreviewData`). The main plan is calculated at once, with fewer runs than it
/// says, so the plan's screens fill in quickly; not with `-screenNoRun`.
/// `-screenLibrary empty` opens first launch instead, on the step `-screen`
/// names (``OnboardingStep``: `welcome`, `you`, `money`, `later`,
/// `answer`, `files` or `notes`), with made-up answers
/// (``sampleAnswers``). `-screenLibrary dayOne` opens the library the tour
/// leaves, on its first day. With
/// `-screenHidesAmounts`, amounts are hidden, as with the eye button. The
/// person has Plus, without the App Store; with `-screenWithoutPlus` they
/// don't, and Plus's actions open the paywall (UI.md, "Plus"), with made-up
/// prices and nothing to buy. Debug builds only.
struct ScreenLaunch {
    /// The made-up libraries: ``PreviewLibrary/library``,
    /// ``PreviewLibrary/withLongHistory`` and
    /// ``PreviewLibrary/withLongAccountName``; or none, for first launch.
    enum Sample: String, CaseIterable {
        case example
        case longHistory
        case longAccountName
        /// No library yet: first launch, on ``ScreenLaunch/onboardingStep``.
        case empty
        /// The library the tour leaves (``ScreenLaunch/createdLibrary``),
        /// on its first day.
        case dayOne

        var library: Library {
            switch self {
            case .example: PreviewLibrary.library
            case .longHistory: PreviewLibrary.withLongHistory
            case .longAccountName: PreviewLibrary.withLongAccountName
            case .empty: Library()
            case .dayOne: ScreenLaunch.createdLibrary
            }
        }
    }

    enum Screen: String, CaseIterable {
        case today
        case plan
        /// The Timeline at a year (was Progress).
        case year
        /// The Timeline at decades: the history and the plan's futures.
        case decades
        /// The Timeline looking back (was Trends).
        case lookBack
        case whatIf
        case targetMix
        /// The accounts: on iPhone pushed on Today's stack, on the Mac
        /// *All Accounts*.
        case accounts
        /// Directa's details: a trades account's holdings, trades and statements.
        case tradesAccount
        /// Conto Fineco's details: a current account's values with money in,
        /// money out and what moved.
        case cashAccount
        /// The check-in, under way (``CheckInPreviewData/fill(_:)``).
        case checkIn

        /// The account whose details the screen shows; `nil` for the others.
        var account: AccountID? {
            switch self {
            case .tradesAccount: "directa"
            case .cashAccount: "conto-fineco"
            default: nil
            }
        }
    }

    var library: Library
    var screen: Screen
    /// Whether the main plan is calculated at launch.
    var calculates: Bool
    /// Whether amounts are hidden, as with the eye button.
    var hidesAmounts: Bool
    /// The step of first launch to open on, with ``Sample/empty``; `nil`
    /// with a library.
    var onboardingStep: OnboardingStep?
    /// Whether it's the tour's day, as with ``Sample/dayOne``.
    var isFirstDay = false
    /// Whether the person has Plus; without it, Plus's actions open the
    /// paywall, with made-up prices.
    var hasPlus = true

    /// `sample` on `screen`; ``Sample/empty`` opens first launch's welcome.
    init(_ sample: Sample, screen: Screen, calculates: Bool = true, hidesAmounts: Bool = false) {
        library = sample.library
        self.screen = screen
        self.calculates = calculates
        self.hidesAmounts = hidesAmounts
        onboardingStep = sample == .empty ? .welcome : nil
        isFirstDay = sample == .dayOne
        for id in library.plans.keys {
            library.plans[id]?.simulation.runs = 400
        }
    }

    /// First launch on `step`. Before *See My Answer* there's no library;
    /// from the answer on, the library is the one *See My Answer* leaves
    /// (``createdLibrary``).
    init(firstLaunchAt step: OnboardingStep) {
        library = step.comesAfterCreating ? Self.createdLibrary : Library()
        screen = .today
        calculates = false
        hidesAmounts = false
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
        self.init(sample, screen: value(of: "-screen").flatMap(Screen.init(rawValue:)) ?? .today,
                  calculates: !arguments.contains("-screenNoRun"),
                  hidesAmounts: arguments.contains("-screenHidesAmounts"))
        hasPlus = !arguments.contains("-screenWithoutPlus")
    }

    /// Made-up answers to the tour's questions: some cash, investments
    /// and a pension pot, a home with a mortgage, pay and spending, a state
    /// pension from 67.
    static let sampleAnswers = StarterAnswers(
        cash: 18_000, investments: 42_000, pension: 25_000, pensionFromAge: 67, home: 320_000, mortgage: 190_000,
        payPerMonth: 3_800, spendingPerMonth: 2_600, statePensionPerMonth: 1_100, statePensionFromAge: 67,
        retirementAge: nil, investmentTax: Decimal(string: "0.26"))

    /// What *See My Answer* leaves, for first launch's last steps: the
    /// example library's settings, ``sampleAnswers``'s starting estimates
    /// on ``PreviewLibrary/latestCheckIn``, and the starter plan "Base
    /// case" completed with them, as the main plan.
    static var createdLibrary: Library {
        var settings = PreviewLibrary.library.settings
        settings.mainPlan = nil
        var library = Library(settings: settings)
        let date = PreviewLibrary.latestCheckIn
        let answers = sampleAnswers
        StarterSetup.addEstimates(answers, to: &library, on: date, taken: [])
        if var plan = PlanEditing.starterPlan(
            id: "base-case", name: PlanEditing.starterPlanName, library: library, asOf: date,
            payPerMonth: answers.payPerMonth, spendingPerMonth: answers.spendingPerMonth,
            retirementAge: answers.retirementAge) {
            StarterSetup.complete(&plan, with: answers, asOf: date)
            plan.simulation.runs = 400
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
        let model = AppModel.preview(library, planEngine: PlannerPlanEngine(), defaults: suite,
                                     plus: hasPlus ? .lifetime : .free)
        model.preferences.hidesAmounts = hidesAmounts
        let navigation = model.navigation
        let main = library.settings.mainPlan
        switch screen {
        case .today:
            navigation.showToday()
        case .plan:
            navigation.showPlan(main)
        case .year:
            navigation.showTimeline(.year)
        case .decades:
            navigation.showTimeline(.decades)
        case .lookBack:
            navigation.showTimeline(.lookBack)
        case .whatIf:
            navigation.showPlan(main)
        case .targetMix:
            let plans = library.plans.values.sorted { $0.id.rawValue < $1.id.rawValue }
            navigation.showPlan(plans.first { !$0.portfolio.targetMixByAge.isEmpty }?.id ?? main,
                                at: PlanRoute(opensTargetMix: true))
        case .accounts:
            // Both layouts', since the root view sets the layout once it appears.
            navigation.tab = .today
            navigation.todayPath.append(TodayPage.accounts)
            navigation.sidebarSelection = .accounts
        case .tradesAccount, .cashAccount:
            // Both layouts', as above.
            if let account = screen.account {
                navigation.tab = .today
                navigation.todayPath.append(TodayPage.accounts)
                navigation.todayPath.append(account)
                navigation.sidebarSelection = .account(account)
            }
        case .checkIn:
            CheckInPreviewData.fill(model)
            // Both layouts', as above.
            navigation.isCheckInPresented = true
            navigation.sidebarSelection = .checkIn
        }
        if calculates, let main {
            // As the root view does once a library is open; a library in
            // memory is open from the start. What if then moves the age
            // lever two years sooner and runs it, as letting go of it does.
            let movesLever = screen == .whatIf
            Task {
                guard let results = await model.plans.run(main), movesLever,
                      let age = results.headline.earliestAge else { return }
                model.plans.setWhatIf(PlanWhatIf(retirementAge: age - 2), for: main)
                _ = await model.plans.run(main, .whatIf)
            }
        }
        return model
    }

    /// First launch on `step`, with ``sampleAnswers`` given. Before *See My
    /// Answer*, a store without a library, which would create one in a new
    /// temporary folder; from the answer on, ``library`` in memory, with
    /// onboarding still showing as *See My Answer* leaves it, and the
    /// answer being recorded.
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
                             prices: PriceStore(service: nil), planEngine: PlannerPlanEngine(),
                             plus: PlusStore(access: .lifetime))
        }
        let onboarding = model.onboarding
        onboarding.age = (library.settings.person?.birthDate ?? PreviewLibrary.library.settings.person?.birthDate)
            .map { $0.wholeYears(to: .today()) }
        onboarding.choose(country: PreviewLibrary.library.settings.taxResidence)
        onboarding.currency = PreviewLibrary.library.settings.baseCurrency
        onboarding.answers = Self.sampleAnswers
        if step.comesAfterCreating {
            onboarding.startAnswer(library: model.library, plans: model.plans)
        }
        model.navigation.requestedOnboardingStep = step
        return model
    }
}
#endif
