import Glance
import Model
import Planner
import SwiftUI
import Tracker

/// The monthly moment (UI.md, "After saving"): the check-in ends on your
/// date, moved.
///
/// > October saved · Net worth 312.480 € (▲ 4.210)
/// > Your last Monday at work: ~~3 April 2051~~ 27 March 2051 · A year sooner
///
/// Then what moved it, said as time of the life you plan, and the next
/// milestone (``CheckInJourneyCards``).
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
                    Text(verbatim: "\(AmountFormat.monthName(result.date, locale: locale)) saved")
                        .font(.title2.bold())
                        .privacySensitiveInFeedback()
                    Text(verbatim: AmountFormat.longDate(result.date, locale: locale))
                        .foregroundStyle(Palette.secondaryInk)
                        .privacySensitiveInFeedback()
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
                    Card("Your last Monday at work") {
                        answer
                    }
                    CheckInJourneyCards(date: result.date)
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
                            .privacySensitiveInFeedback()
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
        return PlanMilestones.reached(by: plan, library: library.library, valuator: library.valuator,
                                      since: previous, through: result.date)
    }

    /// "Passed 300.000 €."
    private func milestones(_ reached: [ReachedMilestone]) -> some View {
        let text = PlanMilestoneText(currency: library.baseCurrency, locale: locale)
        return Card {
            ForEach(reached) { milestone in
                Label {
                    AmountSentenceText(text.reached(milestone.milestone))
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
                .privacySensitiveInFeedback()
        } icon: {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(Palette.accent)
        }
    }

    @ViewBuilder
    private var answer: some View {
        if let headline = answerRun?.headline {
            VStack(alignment: .leading, spacing: Metrics.s) {
                movedDate(headline)
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
                Text("Create a plan to see your last Monday at work. Every check-in will then end with it, moved.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Create a plan") { openPlan() }
                    .buttonStyle(.borderless)
            }
        } else {
            VStack(alignment: .leading, spacing: Metrics.s) {
                if let last = previousHeadline {
                    Text(verbatim: lastAnswer(last))
                        .fixedSize(horizontal: false, vertical: true)
                        .privacySensitiveInFeedback()
                }
                Text(verbatim: unavailableReason)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .privacySensitiveInFeedback()
            }
        }
    }

    /// The date before, struck through, the date now, how it moved, and
    /// how sure: "Still at 63, in 9 of 10 futures."
    @ViewBuilder
    private func movedDate(_ headline: RetirementAnswer) -> some View {
        let now = LastMonday(headline)
        let before = previousHeadline.flatMap { previous in
            LastMonday(RetirementAnswer(recorded: previous, birthDate: library.settings.person?.birthDate))
        }
        VStack(alignment: .leading, spacing: Metrics.xs) {
            if let before, let now, before.date != now.date {
                Text(verbatim: GlanceText.lastMonday(before.date, locale: locale))
                    .font(.subheadline)
                    .strikethrough()
                    .foregroundStyle(Palette.secondaryInk)
            }
            Text(verbatim: now.map { GlanceText.lastMonday($0.date, locale: locale) }
                 ?? (headline.canRetireNow ? "You could stop today" : "Not yet"))
                .font(.largeTitle.bold())
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let previous = previousHeadline,
               let move = LastMondayMove(answer: headline,
                                         history: [AnswerPoint(date: previous.date, earliestAge: previous.earliestAge)],
                                         latestCheckIn: result.date) {
                TodayMoveChip(move: move, words: CheckInAnswer.move(move))
            }
            Text(verbatim: CheckInAnswer.line(headline, previousAge: previousHeadline?.earliestAge))
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .privacySensitiveInFeedback()
        .accessibilityElement(children: .combine)
    }

    /// "Last time (31 Aug): 27 March 2051."
    private func lastAnswer(_ headline: Headline) -> String {
        let date = AmountFormat.shortDate(headline.date, locale: locale)
        let answer = RetirementAnswer(recorded: headline, birthDate: library.settings.person?.birthDate)
        guard let lastMonday = LastMonday(answer) else { return "Last time (\(date)): not yet." }
        return "Last time (\(date)): \(GlanceText.lastMonday(lastMonday.date, locale: locale))."
    }

    /// Why there's no answer this month, without alarm.
    private var unavailableReason: String {
        if let error = answerRun?.error ?? library.settings.mainPlan.flatMap({ plans.errors[$0] }) {
            return "The plan couldn't run this time: \(error)"
        }
        return "This month's date isn't ready yet. The plan works it out when you open it."
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
        navigation.finishCheckIn { $0.showPlan() }
    }
}

#Preview("Saved") {
    let model = AppModel.preview()
    CheckInConfirmationView(result: CheckInPreviewData.saved) {}
        .appEnvironment(model)
        .task { model.plans.recordCheckInAnswer(on: CheckInPreviewData.saved.date) }
}

#Preview("Saved, working out the answer") {
    let model = AppModel.preview(planEngine: PreviewPlanEngine(delay: .milliseconds(400)))
    CheckInConfirmationView(result: CheckInPreviewData.saved) {}
        .appEnvironment(model)
        .task { model.plans.recordCheckInAnswer(on: CheckInPreviewData.saved.date) }
}

#Preview("Saved, no answer yet") {
    CheckInConfirmationView(result: CheckInPreviewData.saved) {}
        .previewEnvironment()
}

#Preview("Saved, a past check-in") {
    CheckInConfirmationView(result: CheckInPreviewData.savedInThePast) {}
        .previewEnvironment()
}
