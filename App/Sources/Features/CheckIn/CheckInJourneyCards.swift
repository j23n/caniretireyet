import Glance
import Model
import Planner
import SwiftUI
import Tracker

/// The check-in's ending after the answer (UI.md, "After saving"): the age
/// you could retire at over the last 12 check-ins and how it moved in a
/// year; what this month saved, said as time of the life you plan, with
/// the last 12 months' saving and markets as bars, and a word of
/// perspective when markets took 5% or more; then the next milestone.
struct CheckInJourneyCards: View {
    /// The check-in's date: the library's latest.
    let date: CalendarDate

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(\.locale) private var locale
    @Environment(\.baseCurrency) private var currency

    var body: some View {
        let points = agePoints
        if points.count >= 2 {
            Card {
                VStack(alignment: .leading, spacing: Metrics.s) {
                    if let move = yearMove(points) {
                        Text(verbatim: move)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                            .privacySensitiveInFeedback()
                    }
                    AgeStepChart(points: points)
                }
            } header: {
                SectionHeader("The age you could retire at") {
                    Text("last 12 check-ins")
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
        }
        if let split = monthSplit {
            Card {
                VStack(alignment: .leading, spacing: Metrics.m) {
                    SavingAsTimeText(saved: split.newMoney, markets: split.market, yearlySpending: spending)
                    if split.start > 0,
                       let perspective = MarketPerspective.sentence(
                           marketsShare: (split.market / split.start).doubleValue,
                           confidence: plans.mainHeadline?.confidence) {
                        Text(verbatim: perspective)
                            .font(.subheadline)
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    let months = library.valuator.monthlyChanges(last: 12, through: date)
                    if months.count >= 2 {
                        MonthlyMovesChart(months: months, highlighted: date.yearMonth)
                    }
                }
            } header: {
                SectionHeader("This month") {
                    Text("the last 12 months")
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
        }
        if let next = nextMilestone {
            Label {
                AmountSentenceText(next)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "flag")
                    .foregroundStyle(Palette.accent)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: The age

    /// The main plan's answers recorded at the last 12 check-ins through this one.
    private var agePoints: [JourneyPoint] {
        guard let main = library.settings.mainPlan else { return [] }
        return library.library.headlines(for: main)
            .filter { $0.date <= date && $0.earliestAge != nil }
            .suffix(12)
            .map { JourneyPoint(date: $0.date, earliestAge: $0.earliestAge, readiness: $0.readiness?.doubleValue) }
    }

    /// "2 years sooner than a year ago", against the answer a year before,
    /// else the first of `points`: "A year later than in March 2026", "The
    /// same as a year ago".
    private func yearMove(_ points: [JourneyPoint]) -> String? {
        guard let now = points.last?.earliestAge else { return nil }
        let yearAgo = points.last { $0.date <= date.adding(years: -1) }
        guard let reference = yearAgo ?? points.first, let before = reference.earliestAge,
              reference.date < date
        else { return nil }
        let when = yearAgo != nil ? "a year ago" : "in \(GlanceText.monthAndYear(reference.date, locale: locale))"
        guard before != now else { return "The same as \(when)" }
        let years = abs(now - before)
        let span = years == 1 ? "A year" : "\(years) years"
        return "\(span) \(now < before ? "sooner" : "later") than \(when)"
    }

    // MARK: The month

    /// The change since the check-in before, with new money as what was
    /// saved, as the Overview's *What moved* splits it.
    private var monthSplit: ValueChange? {
        let valuator = library.valuator
        guard let previous = valuator.previousCheckIn(before: date) else { return nil }
        return valuator.savedSplit(of: valuator.change(from: previous, to: date))
    }

    /// The main plan's retirement spending a year.
    private var spending: Decimal? {
        library.mainPlan.flatMap { MilestoneLadder(plan: $0, library: library.library, on: date).spending }
    }

    // MARK: The next milestone

    /// "Next: 5 years of spending, 80% there."
    private var nextMilestone: AmountSentence? {
        guard let plan = library.mainPlan else { return nil }
        let milestones = PlanMilestones(plan: plan, library: library.library, valuator: library.valuator,
                                        asOf: library.asOfDate, results: plans.latestResults(of: plan.id))
        guard let next = milestones.next else { return nil }
        let text = PlanMilestoneText(currency: currency, locale: locale)
        return "Next: \(text.name(next.milestone)), \(text.progress(next))."
    }
}
