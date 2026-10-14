import Glance
import Model
import Planner
import SwiftUI

/// *Your way there* on the Overview (UI.md, "Your way there"): the
/// milestones from your first record to your last Monday on one line, the
/// next with how far there, the last one reached, and how far you've come
/// since you started. *All Milestones* opens the plan's Progress, *Your
/// Year* the year in review.
struct JourneyCard: View {
    let plan: PlanDocument
    /// The main plan's latest answer, as the header shows it.
    let answer: RetirementAnswer
    /// The results it comes from, for the milestones ahead; `nil` shows
    /// only those reached.
    let results: PlanResults?
    let today: CalendarDate

    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.baseCurrency) private var currency
    @Environment(\.locale) private var locale
    /// The milestones reached, worked out once for each state of the library.
    @State private var cache = PlanProgressCache()

    var body: some View {
        let key = PlanProgressCache.Key(revision: library.revision, plan: plan.id, document: plan,
                                        asOf: library.asOfDate)
        let progress = cache.progress(for: key, library: library.library, valuator: library.valuator)
        let milestones = PlanMilestones(plan: plan, library: library.library, valuator: library.valuator,
                                        asOf: library.asOfDate, results: results, reached: progress.reached)
        let text = PlanMilestoneText(currency: currency, locale: locale)
        if let start = library.valuator.firstValuationDate(in: .planAssets) {
            Card {
                VStack(alignment: .leading, spacing: Metrics.m) {
                    MilestoneTrack(
                        start: start, today: today, retirement: answer.canRetireNow ? nil : answer.earliestDate,
                        reached: milestones.reached, ahead: milestones.ahead,
                        next: milestones.next.flatMap { next in
                            milestones.nextDate.map { date in
                                (id: next.milestone.id, name: text.label(next.milestone), date: date)
                            }
                        })
                    legend
                    if let next = milestones.next {
                        Divider()
                        nextMilestone(next, date: milestones.nextDate, text: text)
                    }
                    if let last = milestones.reached.last {
                        Divider()
                        lastReached(last, text: text)
                    }
                    if let since = SinceYouStarted(history: progress.history, answer: answer,
                                                   reached: milestones.reached.count) {
                        Divider()
                        sinceYouStarted(since)
                    }
                    HStack(spacing: Metrics.l) {
                        Button("All Milestones") { navigation.showPlanProgress() }
                        Button("Your Year") { navigation.showYourYear() }
                    }
                    .buttonStyle(.borderless)
                }
            } header: {
                SectionHeader("Your way there")
            }
        }
    }

    private var legend: some View {
        HStack(spacing: Metrics.m) {
            HStack(spacing: Metrics.xs) {
                Circle().fill(Palette.accent).frame(width: 9, height: 9)
                Text("Reached")
            }
            HStack(spacing: Metrics.xs) {
                Circle().strokeBorder(Palette.accent, lineWidth: 2).frame(width: 9, height: 9)
                Text("Ahead, when typical")
            }
        }
        .font(.caption)
        .foregroundStyle(Palette.secondaryInk)
        .accessibilityHidden(true)
    }

    /// "⚑ Next · 80% there", its name, a bar, and "150.000 € · typically by late 2028".
    private func nextMilestone(_ next: NextMilestone, date: CalendarDate?, text: PlanMilestoneText) -> some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            HStack {
                Label("Next", systemImage: "flag")
                Spacer(minLength: Metrics.s)
                Text(verbatim: text.progress(next))
                    .privacySensitiveInFeedback()
            }
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
            AmountSentenceText(text.name(next.milestone))
                .font(.headline)
                .foregroundStyle(Palette.ink)
            ShareBarTrack(share: next.progress)
            if let caption = text.caption(next, date: date) {
                AmountSentenceText(caption)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "⚑ Last reached · August" over "Halfway to what retiring today needs."
    private func lastReached(_ milestone: ReachedMilestone, text: PlanMilestoneText) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(verbatim: "Last reached · " + GlanceText.month(milestone.date, relativeTo: today, locale: locale))
                    .privacySensitiveInFeedback()
            } icon: {
                Image(systemName: "flag.fill")
            }
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
            AmountSentenceText(text.reached(milestone.milestone))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// "Since you started · October 2021", "You could retire at 54, not 58",
    /// "From 21% to 58% ready, 7 milestones passed".
    private func sinceYouStarted(_ since: SinceYouStarted) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "Since you started · " + GlanceText.monthAndYear(since.date, locale: locale))
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
            Text(verbatim: since.answer)
                .foregroundStyle(Palette.ink)
            if let progress = since.progress {
                Text(verbatim: progress)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .privacySensitiveInFeedback()
        .accessibilityElement(children: .combine)
    }
}

/// How far you've come since the first answer recorded (UI.md, "Your way
/// there").
struct SinceYouStarted: Hashable {
    /// The check-in of the first answer with an age.
    var date: CalendarDate
    /// "You could retire at 54, not 58".
    var answer: String
    /// "From 21% to 58% ready, 7 milestones passed"; `nil` with neither.
    var progress: String?

    /// `nil` before a second answer, or without an age now.
    init?(history: PlanAnswerHistory, answer: RetirementAnswer, reached: Int) {
        guard let first = history.points.first(where: { $0.earliestAge != nil }),
              let latest = history.points.last, first.date < latest.date,
              let then = first.earliestAge, let now = answer.earliestAge, !answer.canRetireNow
        else { return nil }
        date = first.date
        self.answer = then == now ? "You could retire at \(now), as when you started"
            : "You could retire at \(now), not \(then)"
        var parts: [String] = []
        if let from = first.readiness, let to = answer.shownReadiness {
            let fromPercent = Int((from.doubleValue * 100 + 1e-9).rounded(.down))
            let toPercent = Int((to * 100 + 1e-9).rounded(.down))
            parts.append("from \(fromPercent)% to \(toPercent)% ready")
        }
        if reached > 0 {
            parts.append(reached == 1 ? "a milestone passed" : "\(reached) milestones passed")
        }
        progress = parts.isEmpty ? nil : parts.joined(separator: ", ").capitalizedFirst
    }
}
