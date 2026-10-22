import Glance
import Model
import Planner
import SwiftUI

/// *Your way to retirement* on the Overview (UI.md, "Your way to
/// retirement"): the milestones from your first record to your last Monday
/// on one line, the next with how far there, the milestones reached, newest
/// first, one at a time, and how far you've come since you started.
struct JourneyCard: View {
    let plan: PlanDocument
    /// The main plan's latest answer, as the header shows it.
    let answer: RetirementAnswer
    /// The results it comes from, for the milestones ahead; `nil` shows
    /// only those reached.
    let results: PlanResults?
    let today: CalendarDate

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(\.baseCurrency) private var currency
    @Environment(\.locale) private var locale
    @Environment(\.pageLayout) private var layout

    /// The milestone reached that's shown; `nil` shows the newest.
    @State private var shownReached: String?
    /// The last step's direction, so the milestone shown slides in from
    /// that side: older from the leading edge.
    @State private var steppedOlder = true

    var body: some View {
        let progress = plans.planProgress(of: plan.id, document: plan)
        let milestones = PlanMilestones(plan: plan, library: library.library, valuator: library.valuator,
                                        asOf: library.asOfDate, results: results, reached: progress.reached)
        let text = PlanMilestoneText(currency: currency, locale: locale)
        let next = milestones.next
        let pager = ReachedMilestonePager(reached: milestones.reached, shownID: shownReached)
        if let start = library.valuator.firstValuationDate(in: .planAssets) {
            let track = MilestoneTrack(
                start: start, today: today, retirement: answer.canRetireNow ? nil : answer.earliestDate,
                reached: milestones.reached, ahead: milestones.ahead,
                next: next.flatMap { next in
                    milestones.nextDate.map { date in
                        (id: next.milestone.id, name: text.label(next.milestone), date: date)
                    }
                },
                shown: pager.shown?.id)
            Card {
                VStack(alignment: .leading, spacing: Metrics.m) {
                    track
                    legend(reached: !track.reached.isEmpty, ahead: !track.drawnAhead.isEmpty)
                    if let next {
                        Divider()
                        nextMilestone(next, date: milestones.nextDate, text: text)
                    }
                    if let shown = pager.shown {
                        Divider()
                        reachedMilestone(shown, pager: pager, text: text)
                    }
                    if let since = SinceYouStarted(history: progress.history, answer: answer,
                                                   reached: milestones.reached.count) {
                        Divider()
                        sinceYouStarted(since)
                    }
                }
            } header: {
                SectionHeader("Your way to retirement")
            }
        }
    }

    /// What the dots and rings mean, each only when the line has some.
    @ViewBuilder
    private func legend(reached: Bool, ahead: Bool) -> some View {
        if reached || ahead {
            HStack(spacing: Metrics.m) {
                if reached {
                    HStack(spacing: Metrics.xs) {
                        Circle().fill(Palette.accent).frame(width: 9, height: 9)
                        Text("Reached")
                    }
                }
                if ahead {
                    HStack(spacing: Metrics.xs) {
                        Circle().strokeBorder(Palette.accent, lineWidth: 2).frame(width: 9, height: 9)
                        Text("Ahead, when typical")
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(Palette.secondaryInk)
            .accessibilityHidden(true)
        }
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

    /// "⚑ Last reached · August" over "Halfway to what retiring today
    /// needs.", or "⚑ Reached · March 2025" for an older one: a swipe, ‹ ›
    /// on the Mac and iPad, or VoiceOver's adjustable action steps to an
    /// older or a newer one.
    private func reachedMilestone(_ milestone: ReachedMilestone, pager: ReachedMilestonePager,
                                  text: PlanMilestoneText) -> some View {
        HStack(alignment: .top, spacing: Metrics.s) {
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Label {
                        Text(verbatim: pager.label(relativeTo: today, locale: locale) ?? "")
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
                .id(milestone.id)
                .transition(.push(from: steppedOlder ? .leading : .trailing))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .contentShape(Rectangle())
            // A swipe to the right shows an older one, to the left a newer one.
            .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { drag in
                let across = drag.translation.width
                guard abs(across) > 44, abs(across) > 2 * abs(drag.translation.height) else { return }
                step(pager, by: across > 0 ? -1 : 1)
            })
            .accessibilityElement(children: .combine)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: step(pager, by: 1)
                case .decrement: step(pager, by: -1)
                @unknown default: break
                }
            }
            if layout.isWide, let index = pager.index, pager.reached.count > 1 {
                PlanStepButtons(index: index, count: pager.reached.count, hasShortcuts: false) { chosen in
                    step(pager, by: chosen - index)
                }
                .controlSize(.small)
            }
        }
    }

    /// Shows the milestone reached `offset` steps newer than the one shown
    /// (older when negative), sliding it in from that side.
    private func step(_ pager: ReachedMilestonePager, by offset: Int) {
        var stepped = pager
        stepped.step(by: offset)
        guard stepped.index != pager.index else { return }
        steppedOlder = offset < 0
        withAnimation(.snappy) { shownReached = stepped.shownID }
    }

    /// "Since you started · October 2021", "Your retirement moved 4 years
    /// sooner, to 54",
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
/// to retirement").
struct SinceYouStarted: Hashable {
    /// The check-in of the first answer with an age.
    var date: CalendarDate
    /// "Your retirement moved 4 years sooner, to 54", "Your retirement
    /// slipped a year, to 59".
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
        let years = abs(now - then)
        let count = years == 1 ? "a year" : "\(years) years"
        self.answer = then == now ? "You could retire at \(now), as when you started"
            : now < then ? "Your retirement moved \(count) sooner, to \(now)"
            : "Your retirement slipped \(count), to \(now)"
        var parts: [String] = []
        if let from = first.readiness, let to = answer.readiness.map(Readiness.shown) {
            let fromPercent = Int((Readiness.shown(from.doubleValue) * 100).rounded())
            let toPercent = Int((to * 100).rounded())
            parts.append("from \(fromPercent)% to \(toPercent)% ready")
        }
        if reached > 0 {
            parts.append(reached == 1 ? "a milestone passed" : "\(reached) milestones passed")
        }
        progress = parts.isEmpty ? nil : parts.joined(separator: ", ").capitalizedFirst
    }
}
