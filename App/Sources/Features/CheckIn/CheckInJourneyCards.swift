import Glance
import Model
import Planner
import SwiftUI
import Tracker

/// The check-in's ending after the date (UI.md, "After saving"): *What
/// moved it*, net worth with its change, what you saved and what markets
/// did as bars, said as time of the life you plan, and a word of
/// perspective when markets took 5% or more; then the next milestone on a
/// card of its own (not after a past check-in).
struct CheckInJourneyCards: View {
    let result: CheckInSaveResult

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(\.locale) private var locale
    @Environment(\.baseCurrency) private var currency

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Metrics.m) {
                netWorth
                if let split = monthSplit {
                    CheckInMovedBars(saved: split.saved, markets: split.market)
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
            }
        } header: {
            SectionHeader("What moved it")
        }
        if !result.isPast, let next = nextMilestone {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.m) {
                Image(systemName: "flag")
                    .font(.title3)
                    .foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
                AmountSentenceText(next)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Metrics.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    /// "Net worth   312.480 € ▲ +4.210 €", on one line.
    private var netWorth: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Text("Net worth")
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
            Spacer(minLength: Metrics.s)
            AmountText(result.netWorth)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .fixedSize()
            if let change = result.change {
                DeltaText(change.change)
                    .font(.subheadline)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: The month

    /// The change since the check-in before, with new money as what was
    /// saved, as Today's *What changed* splits it.
    private var monthSplit: ValueChange? {
        let valuator = library.valuator
        guard let previous = valuator.previousCheckIn(before: result.date) else { return nil }
        return valuator.savedSplit(of: valuator.change(from: previous, to: result.date))
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

/// What you saved and what markets did this month, a bar each against the
/// larger of the two, with the amount on the right: "You saved ▬▬▬ +1.420 €".
struct CheckInMovedBars: View {
    let saved: Decimal
    let markets: Decimal

    private struct Part: Identifiable {
        var title: String
        var amount: Decimal
        var color: Color
        var id: String { title }
    }

    var body: some View {
        let parts = [Part(title: "You saved", amount: saved, color: Palette.accent),
                     Part(title: "Markets", amount: markets, color: Palette.accent.opacity(0.45))]
        let largest = max(abs(saved.doubleValue), abs(markets.doubleValue))
        Grid(alignment: .leading, horizontalSpacing: Metrics.m, verticalSpacing: Metrics.s) {
            ForEach(parts) { part in
                GridRow {
                    Text(part.title)
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                    GeometryReader { proxy in
                        Capsule()
                            .fill(part.color)
                            .frame(width: max(6, proxy.size.width * CGFloat(largest > 0
                                    ? abs(part.amount.doubleValue) / largest : 0)))
                    }
                    .frame(height: 8)
                    .frame(minWidth: 40, maxWidth: .infinity)
                    .accessibilityHidden(true)
                    AmountText(part.amount, signed: true)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .fixedSize()
                        .gridColumnAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .privacySensitiveInFeedback()
    }
}
