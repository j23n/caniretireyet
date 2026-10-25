import SwiftUI
import Testing
@testable import CanIRetireYet

/// Each screen of the app with a made-up library, kept as a picture
/// (``ScreenCapture``) for a person or an agent to look at (App/README.md,
/// "Screenshots"). Each screen opens as ``ScreenLaunch`` opens it: the main
/// plan calculated with the real planner and fewer runs. A screen whose
/// plan never calculates is an issue. One at a time: each calculates a plan.
@MainActor
@Suite(.serialized)
struct ScreenshotTests {
    @Test func today() async throws {
        try await keep("today", .example, .today)
    }

    @Test func plan() async throws {
        try await keep("plan", .example, .plan)
    }

    /// Before it's calculated: the chapters without their money, the first
    /// saying "Calculate to see your money".
    @Test func planBeforeCalculating() async throws {
        try await keep("plan-uncalculated", .example, .plan, calculates: false)
    }

    @Test func whatIf() async throws {
        try await keep("what-if", .example, .whatIf)
    }

    /// The Target mix sheet of a plan with a mix of its own and changes
    /// with age. On iPhone; on the Mac a sheet is a window of its own,
    /// which the picture of the main window leaves out.
    @Test func targetMix() async throws {
        try await keep("target-mix", .example, .targetMix)
    }

    /// The Timeline at a year: this year's check-ins against January's plan.
    @Test func timelineYear() async throws {
        try await keep("timeline-year", .example, .year)
    }

    /// A savings plan since 2018 and check-ins from October 2025: the years
    /// before are valued from prices.
    @Test func timelineYearWithALongHistory() async throws {
        try await keep("timeline-year-long", .longHistory, .year)
    }

    /// The Timeline at decades: your records, then the plan's futures.
    @Test func timelineDecades() async throws {
        try await keep("timeline-decades", .example, .decades)
    }

    @Test func timelineLookBack() async throws {
        try await keep("timeline-look-back", .example, .lookBack)
    }

    /// The accounts, with the net worth chart and the allocation.
    @Test func accounts() async throws {
        try await keep("accounts", .example, .accounts)
    }

    /// A trades account's details: its holdings, its trades by month in
    /// place of its values, its income and gains, and its statements.
    @Test func tradesAccount() async throws {
        try await keep("account-trades", .example, .tradesAccount)
    }

    /// A current account's details: its values with money in, money out and
    /// what moved between your own accounts.
    @Test func cashAccount() async throws {
        try await keep("account-cash", .example, .cashAccount)
    }

    /// An account whose name and institution are longer than fit beside
    /// its value: the institution goes under the name and both wrap, and
    /// its value stays on one line in the column of the others'. On iPhone
    /// the accounts list; on the Mac *All Accounts* and the sidebar's
    /// accounts.
    @Test func accountsWithALongName() async throws {
        try await keep("accounts-long-name", .longAccountName, .accounts)
    }

    /// The October check-in under way (`CheckInPreviewData`), after this
    /// month's files were imported: net worth and its change, the accounts
    /// the files updated and those they didn't. On iPhone in a full-screen
    /// cover; on the Mac the sidebar's Check-in page.
    @Test func checkIn() async throws {
        try await keep("check-in", .example, .checkIn)
    }

    /// First launch, with no library: each step of the tour, with made-up
    /// answers, as ``ScreenLaunch`` opens it. It's ready once onboarding has
    /// taken the step. From the answer on, the library is the one *See My
    /// Answer* leaves, and the answer step waits for the answer.
    @Test(arguments: OnboardingStep.allCases)
    func firstLaunch(_ step: OnboardingStep) async throws {
        let model = ScreenLaunch(firstLaunchAt: step).model()
        try await ScreenCapture.keep(root(model), named: "first-launch-\(step.rawValue)") {
            model.navigation.requestedOnboardingStep == nil
                && (step != .answer || model.plans.checkInAnswer?.isRunning == false)
        }
    }

    /// Today on the tour's day: the starting estimates as accounts.
    @Test func todayOnDayOne() async throws {
        try await keep("today-day-one", .dayOne, .today)
    }

    // With the eye on (UI.md, "Privacy"): amounts are placeholders, words
    // stay, and charts keep their shape with a relative value axis.

    @Test func todayWithAmountsHidden() async throws {
        try await keep("today-hidden", .example, .today, hidesAmounts: true)
    }

    @Test func planWithAmountsHidden() async throws {
        try await keep("plan-hidden", .example, .plan, hidesAmounts: true)
    }

    @Test func timelineYearWithAmountsHidden() async throws {
        try await keep("timeline-year-hidden", .example, .year, hidesAmounts: true)
    }

    private func keep(_ name: String, _ sample: ScreenLaunch.Sample, _ screen: ScreenLaunch.Screen,
                      calculates: Bool = true, hidesAmounts: Bool = false) async throws {
        let launch = ScreenLaunch(sample, screen: screen, calculates: calculates, hidesAmounts: hidesAmounts)
        let main = try #require(launch.library.settings.mainPlan)
        let model = launch.model()
        try await ScreenCapture.keep(root(model), named: name) {
            !calculates || model.plans.results(of: main) != nil || model.plans.errors[main] != nil
        }
        #expect(model.plans.errors[main] == nil, "The main plan didn't calculate.")
    }

    /// The window's content, as the app's own window has it.
    @ViewBuilder
    private func root(_ model: AppModel) -> some View {
        #if os(macOS)
        FixedMinimumSize(minWidth: 900, minHeight: 600) {
            RootView()
        }
        .appEnvironment(model)
        .task { await model.start() }
        #else
        RootView()
            .appEnvironment(model)
            .task { await model.start() }
        #endif
    }
}
