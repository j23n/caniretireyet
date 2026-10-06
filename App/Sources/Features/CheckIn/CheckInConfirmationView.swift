import Model
import Planner
import SwiftUI
import Tracker

/// The monthly moment (UI.md, "After saving"): what the check-in did to net
/// worth, and this month's answer.
///
/// > Saved · Net worth 312.480 € (▲ 4.210)
/// > Can I retire yet? Not yet: earliest at **54**, unchanged since August.
///
/// It shows as soon as the check-in is written. The main plan then runs to
/// record the month's answer (`PlanStore.checkInAnswer`): its progress shows
/// in place of the answer, the same as on the Plan screen, until the answer
/// is there. Done closes it meanwhile; the run goes on and records the answer.
///
/// Without an answer it says why, calmly: there's no main plan yet, plans
/// can't run in this version (the last recorded answer is shown), or the
/// plan couldn't run. A past check-in (one before the library's latest)
/// records no answer, and says so instead:
///
/// > Saved a past check-in (31 Mar 2024). The answer isn't recorded for past dates.
struct CheckInConfirmationView: View {
    let result: CheckInSaveResult
    let done: () -> Void

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale

    init(result: CheckInSaveResult, done: @escaping () -> Void) {
        self.result = result
        self.done = done
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Metrics.xl) {
                VStack(spacing: Metrics.s) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 44))
                        .foregroundStyle(Palette.good)
                        .accessibilityHidden(true)
                    Text("Saved")
                        .font(.title2.bold())
                    Text(verbatim: AmountFormat.longDate(result.date, locale: locale))
                        .foregroundStyle(Palette.secondaryInk)
                }
                netWorth
                let reached = result.isPast ? [] : reachedMilestones
                if !reached.isEmpty {
                    milestones(reached)
                }
                if result.isPast {
                    Card {
                        pastCheckIn
                    }
                } else {
                    Card("Can I retire yet?") {
                        answer
                    }
                }
                LibraryStatusBanners()
                Button {
                    done()
                } label: {
                    Text("Done")
                        .fontWeight(.semibold)
                        .frame(maxWidth: 280)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(Metrics.xl)
            .frame(maxWidth: Metrics.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.page)
    }

    /// "Net worth 312.480 € ▲ +4.210 € since 31 Aug".
    private var netWorth: some View {
        VStack(spacing: Metrics.xs) {
            Text("Net worth")
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
            AmountText(result.netWorth, tabular: false)
                .font(.largeTitle.bold())
            if let change = result.change {
                HStack(spacing: Metrics.xs) {
                    DeltaText(change.change)
                    if let previous = previousCheckIn {
                        Text(verbatim: "since " + AmountFormat.shortDate(previous, locale: locale))
                            .foregroundStyle(Palette.secondaryInk)
                    }
                }
                .font(.subheadline)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Milestones

    /// The main plan's milestones this check-in reached (UI.md,
    /// "Milestones"): the amounts passed since the check-in before, on its
    /// day or at a month end between them. The shares of what retiring
    /// today needs come with the answer, and show on Progress.
    private var reachedMilestones: [ReachedMilestone] {
        guard let plan = library.mainPlan else { return [] }
        let previous = library.valuator.previousCheckIn(before: result.date, in: .planAssets)
        return PlanMilestones(plan: plan, library: library.library, valuator: library.valuator, asOf: result.date,
                              results: nil).reached(since: previous, through: result.date)
    }

    /// "Passed 300.000 €."
    private func milestones(_ reached: [ReachedMilestone]) -> some View {
        let text = PlanMilestoneText(currency: library.baseCurrency, hidesAmounts: hidesAmounts, locale: locale)
        return Card {
            ForEach(reached) { milestone in
                Label {
                    Text(text.reached(milestone.milestone))
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(Palette.accent)
                }
            }
        } header: {
            SectionHeader(reached.count == 1 ? "A milestone" : "Milestones")
        }
    }

    // MARK: The answer

    /// A past check-in: saved, with no answer recorded for its date.
    private var pastCheckIn: some View {
        Label {
            Text(verbatim: CheckInWording.pastCheckInSaved(on: result.date, latest: result.laterCheckIn,
                                                           locale: locale))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(Palette.accent)
        }
    }

    @ViewBuilder
    private var answer: some View {
        if let headline = result.headline ?? answerRun?.headline {
            let parts = CheckInAnswer.make(headline, previous: previousHeadline, locale: locale)
            VStack(alignment: .leading, spacing: Metrics.s) {
                answerText(parts)
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
                if let readiness = PlanResultsText.readiness(headline, locale: locale) {
                    Text(verbatim: readiness)
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                }
                Button("Open the plan") { openPlan() }
                    .buttonStyle(.borderless)
            }
        } else if let run = answerRun, run.isRunning {
            VStack(alignment: .leading, spacing: Metrics.s) {
                PlanRunProgressView(progress: plans.progress(of: run.plan, .checkIn) ?? .starting(.full),
                                    isCheckIn: true)
                Text("You can close this now: the answer is recorded when it's ready.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if library.mainPlan == nil {
            VStack(alignment: .leading, spacing: Metrics.s) {
                Text("Create a plan to see when you could retire. Every check-in will then end with this month's answer.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Create a plan") { openPlan() }
                    .buttonStyle(.borderless)
            }
        } else {
            VStack(alignment: .leading, spacing: Metrics.s) {
                if let last = previousHeadline {
                    Text(verbatim: lastAnswer(last))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(verbatim: unavailableReason)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The sentence with the age in bold.
    private func answerText(_ parts: CheckInAnswer) -> Text {
        if let emphasis = parts.emphasis {
            return Text("\(parts.lead)\(Text(verbatim: emphasis).bold())\(parts.trail)")
        }
        return Text(verbatim: parts.text)
    }

    /// "Last answer (31 Aug): not yet, earliest at 54."
    private func lastAnswer(_ headline: Headline) -> String {
        let date = AmountFormat.shortDate(headline.date, locale: locale)
        guard let age = headline.earliestAge else { return "Last answer (\(date)): not yet." }
        return "Last answer (\(date)): not yet, earliest at \(age)."
    }

    /// Why there's no answer this month, without alarm.
    private var unavailableReason: String {
        if !plans.isAvailable {
            return "This month's answer comes once plans can run in this version of the app."
        }
        if let error = answerRun?.error ?? library.settings.mainPlan.flatMap({ plans.errors[$0] }) {
            return "The plan couldn't run this time: \(error)"
        }
        return "This month's answer isn't ready yet. Open the plan to calculate it."
    }

    // MARK: Helpers

    /// The main plan's run for this check-in's answer: its progress, then
    /// the headline it recorded.
    private var answerRun: CheckInAnswerRun? {
        guard let run = plans.checkInAnswer, run.date == result.date else { return nil }
        return run
    }

    /// The answer recorded at the check-in before this one.
    private var previousHeadline: Headline? {
        CheckInAnswer.previousHeadline(before: result.date, in: library.library)
    }

    /// The check-in before this one, where the change starts.
    private var previousCheckIn: CalendarDate? {
        library.valuator.previousCheckIn(before: result.date)
    }

    /// Closes the check-in, then shows the main plan.
    private func openPlan() {
        let navigation = self.navigation
        done()
        Task { @MainActor in
            // On iPhone the check-in is a full-screen cover: let it close first.
            try? await Task.sleep(for: .milliseconds(350))
            navigation.showPlan()
        }
    }
}

#Preview("Saved") {
    CheckInConfirmationView(result: CheckInPreviewData.saved) {}
        .previewEnvironment()
}

#Preview("Saved, working out the answer") {
    let model = AppModel.preview(planEngine: PlanPreviewEngine(delay: .milliseconds(400)))
    CheckInConfirmationView(result: CheckInPreviewData.savedWithoutAnswer) {}
        .previewEnvironment(model: model)
        .task { model.plans.recordCheckInAnswer(on: CheckInPreviewData.savedWithoutAnswer.date) }
}

#Preview("Saved, no planner") {
    CheckInConfirmationView(result: CheckInPreviewData.savedWithoutAnswer) {}
        .previewEnvironment()
}

#Preview("Saved, a past check-in") {
    CheckInConfirmationView(result: CheckInPreviewData.savedInThePast) {}
        .previewEnvironment()
}
