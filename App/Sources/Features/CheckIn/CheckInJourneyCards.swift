import Glance
import Model
import Planner
import SwiftUI
import Tracker

/// The check-in's ending after the date (UI.md, "After saving"): what
/// moved it, what you saved and what markets did, said as time of the life
/// you plan, and a word of perspective when markets took 5% or more; then
/// the next milestone.
struct CheckInJourneyCards: View {
    /// The check-in's date: the library's latest.
    let date: CalendarDate

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(\.locale) private var locale
    @Environment(\.baseCurrency) private var currency

    var body: some View {
        if let split = monthSplit {
            Card {
                VStack(alignment: .leading, spacing: Metrics.m) {
                    SavingAsTimeText(saved: split.saved, markets: split.market, yearlySpending: spending)
                    if split.start > 0,
                       let perspective = MarketPerspective.sentence(
                           marketsShare: (split.market / split.start).doubleValue,
                           confidence: plans.mainHeadline?.confidence) {
                        Text(verbatim: perspective)
                            .font(.subheadline)
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                SectionHeader("What moved it")
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

    // MARK: The month

    /// The change since the check-in before, with new money as what was
    /// saved, as Today's *What changed* splits it.
    private var monthSplit: ValueChange? {
        let valuator = library.valuator
        guard let previous = valuator.previousCheckIn(before: date) else { return nil }
        return valuator.savedSplit(of: valuator.change(from: previous, to: date))
    }

    /// The main plan's retirement spending a year.
    private var spending: Decimal? {
        library.mainPlan.flatMap(MilestoneLadder.spending(of:))
    }

    // MARK: The next milestone

    /// "Next: 5 years of spending, 80% there."
    private var nextMilestone: AmountSentence? {
        guard let plan = library.mainPlan else { return nil }
        let milestones = PlanMilestones(plan: plan, library: library.library, valuator: library.valuator,
                                        asOf: library.asOfDate, results: plans.latestResults(of: plan.id),
                                        reached: plans.planProgress(of: plan.id, document: plan).reached)
        guard let next = milestones.next else { return nil }
        let text = PlanMilestoneText(currency: currency, locale: locale)
        return "Next: \(text.name(next.milestone)), \(text.progress(next))."
    }
}
