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
    @Test func overview() async throws {
        try await keep("overview", .example, .overview)
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

    @Test func progress() async throws {
        try await keep("progress", .example, .progress)
    }

    /// A savings plan since 2018 and check-ins from October 2025: the years
    /// before are valued from prices.
    @Test func progressWithALongHistory() async throws {
        try await keep("progress-long", .longHistory, .progress)
    }

    /// First launch, with no library: each step up to the disclaimer, as
    /// ``ScreenLaunch`` opens it. It's ready once onboarding has taken the
    /// step. The accounts step and the disclaimer show the library *Create
    /// library* leaves, with its starter plan.
    @Test(arguments: OnboardingStep.allCases)
    func firstLaunch(_ step: OnboardingStep) async throws {
        let model = ScreenLaunch(firstLaunchAt: step).model()
        try await ScreenCapture.keep(root(model), named: "first-launch-\(step.rawValue)") {
            model.navigation.requestedOnboardingStep == nil
        }
    }

    // With the eye on (UI.md, "Privacy"): amounts are placeholders, words
    // stay, and charts keep their shape with a relative value axis.

    @Test func overviewWithAmountsHidden() async throws {
        try await keep("overview-hidden", .example, .overview, hidesAmounts: true)
    }

    @Test func planWithAmountsHidden() async throws {
        try await keep("plan-hidden", .example, .plan, hidesAmounts: true)
    }

    @Test func progressWithAmountsHidden() async throws {
        try await keep("progress-hidden", .example, .progress, hidesAmounts: true)
    }

    private func keep(_ name: String, _ sample: ScreenLaunch.Sample, _ screen: ScreenLaunch.Screen,
                      calculates: Bool = true, hidesAmounts: Bool = false) async throws {
        let launch = ScreenLaunch(sample, screen: screen, calculates: calculates, hidesAmounts: hidesAmounts)
        let main = try #require(launch.library.settings.mainPlan)
        let model = launch.model()
        try await ScreenCapture.keep(root(model), named: name) {
            !calculates || model.plans.results[main] != nil || model.plans.errors[main] != nil
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
