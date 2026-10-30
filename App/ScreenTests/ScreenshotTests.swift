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

    /// Ahead: your last Monday with the plan's chart, the tiles, and your
    /// life ahead with when you stop on it.
    @Test func ahead() async throws {
        try await keep("ahead", .example, .ahead)
    }

    /// Before it's calculated: the chapters without their money.
    @Test func aheadBeforeCalculating() async throws {
        try await keep("ahead-uncalculated", .example, .ahead, calculates: false)
    }

    /// What if with the age lever two years sooner: on iPhone its sheet,
    /// with *With these levers*; on the Mac the levers beside your date.
    @Test func whatIf() async throws {
        try await keep("what-if", .example, .whatIf)
    }

    /// A new event's sheet: its form, then *With this change*. On iPhone;
    /// on the Mac a sheet is a window of its own.
    @Test func newEvent() async throws {
        try await keep("new-event", .example, .newEvent)
    }

    /// The Target mix sheet of a plan with a mix of its own and changes
    /// with age. On iPhone; on the Mac a sheet is a window of its own,
    /// which the picture of the main window leaves out.
    @Test func targetMix() async throws {
        try await keep("target-mix", .example, .targetMix)
    }

    /// So far: this year against January's plan, the savings rate and money
    /// in and out by month, and year by year.
    @Test func soFar() async throws {
        try await keep("so-far", .example, .soFar)
    }

    /// A savings plan since 2018 and check-ins from October 2025: the years
    /// before are valued from prices.
    @Test func soFarWithALongHistory() async throws {
        try await keep("so-far-long", .longHistory, .soFar)
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
    /// the accounts list; on the Mac *All Accounts*.
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

    @Test func aheadWithAmountsHidden() async throws {
        try await keep("ahead-hidden", .example, .ahead, hidesAmounts: true)
    }

    @Test func soFarWithAmountsHidden() async throws {
        try await keep("so-far-hidden", .example, .soFar, hidesAmounts: true)
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
