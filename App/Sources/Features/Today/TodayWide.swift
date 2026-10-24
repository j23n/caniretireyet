import Glance
import Model
import Planner
import SwiftUI
import Tracker

// Today on the Mac and iPad (UI.md, "Today"): the answer's figures beside
// the date, the page's two columns, and *Coming up*.

// MARK: - Columns

/// Today's two columns on the Mac and iPad: the main column takes the width
/// the side column leaves, both aligned at the top. Narrower than the two
/// need, the side column goes under the main one.
///
/// A custom layout rather than an `HStack`, so the main column's width
/// never depends on what the chart in it would like to be (see
/// ``EqualColumns``).
struct TodayColumns: Layout {
    var sideWidth: CGFloat = 300
    var spacing: CGFloat = Metrics.l
    /// The narrowest the main column gets beside the side column.
    var minimumMainWidth: CGFloat = 480
    /// The width when the parent offers none.
    private static let fallbackWidth: CGFloat = 900

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? Self.fallbackWidth
        let height = frames(width: width, subviews: subviews).map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(width: bounds.width, subviews: subviews)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    /// The first subview is the main column, the second the side column;
    /// any others stack under them.
    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        var frames: [CGRect] = []
        var top: CGFloat = 0
        var start = 0
        if subviews.count >= 2, width >= minimumMainWidth + spacing + sideWidth {
            let mainWidth = width - spacing - sideWidth
            let main = subviews[0].sizeThatFits(ProposedViewSize(width: mainWidth, height: nil)).height
            let side = subviews[1].sizeThatFits(ProposedViewSize(width: sideWidth, height: nil)).height
            frames.append(CGRect(x: 0, y: 0, width: mainWidth, height: main))
            frames.append(CGRect(x: mainWidth + spacing, y: 0, width: sideWidth, height: side))
            top = max(main, side) + spacing
            start = 2
        }
        for index in subviews.indices where index >= start {
            let height = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
            frames.append(CGRect(x: 0, y: top, width: width, height: height))
            top += height + spacing
        }
        return frames
    }
}

// MARK: - Figures

/// The four figures beside the date on the Mac and iPad: net worth with
/// its change at the last check-in, the chance at the plan's target age,
/// what you saved this year, and the next milestone. Each opens where it's
/// explained: the accounts, the plan, the Timeline's year.
struct TodayFigures: View {
    let answer: RetirementAnswer
    let plan: PlanDocument
    let results: PlanResults?
    let year: TodayYear?
    let today: CalendarDate

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.baseCurrency) private var currency
    @Environment(\.locale) private var locale

    var body: some View {
        let netWorth = NetWorthGlance(valuator: library.valuator, asOf: today)
        HStack(alignment: .top, spacing: Metrics.l) {
            figure("Net worth", hint: "Shows your accounts", action: { navigation.showAccounts() }) {
                AmountText(netWorth.total, tabular: false, animatesChanges: true)
            } caption: {
                if let change = netWorth.sinceLastCheckIn {
                    HStack(spacing: Metrics.xs) {
                        DeltaText(change.change, showsArrow: false)
                        Text(GlanceText.period(from: change.from, to: change.to, relativeTo: today, locale: locale))
                            .foregroundStyle(Palette.change(change.change > 0 ? 1 : change.change < 0 ? -1 : 0))
                            .privacySensitiveInFeedback()
                    }
                }
            }
            if let target = answer.targetAge, let success = answer.successAtTarget {
                figure("At \(target), as planned", personalTitle: true, hint: "Opens the plan",
                       action: { navigation.showPlan() }) {
                    Text(verbatim: GlanceText.futures(success))
                        .privacySensitiveInFeedback()
                } caption: {
                    Text(verbatim: "futures last to \(plan.effectiveEndAge)")
                        .privacySensitiveInFeedback()
                }
            }
            if let year {
                figure("Saved this year", hint: "Shows this year on the Timeline",
                       action: { navigation.showTimeline(.year) }) {
                    AmountText(year.split.saved, tabular: false)
                } caption: {
                    if let rate = year.savings?.rate {
                        Text(verbatim: "Savings rate \(AmountFormat.percent(rate, digits: 0, locale: locale))")
                            .privacySensitiveInFeedback()
                    }
                }
            }
            if let next = TodayMilestones.of(plan, results: results, library: library, plans: plans).next {
                let text = PlanMilestoneText(currency: currency, locale: locale)
                figure("Next milestone", hint: "Shows this year on the Timeline",
                       action: { navigation.showTimeline(.year) }) {
                    Text(verbatim: AmountFormat.percent(next.progress, digits: 0, locale: locale))
                        .privacySensitiveInFeedback()
                } caption: {
                    AmountSentenceText(text.name(next.milestone))
                }
            }
        }
    }

    /// A figure: its title small and grey, the figure, and a caption, as a
    /// button that opens where it's explained.
    /// `personalTitle` when the title holds the person's data (an age).
    private func figure(_ title: String, personalTitle: Bool = false, hint: String,
                        action: @escaping @MainActor () -> Void, @ViewBuilder value: () -> some View,
                        @ViewBuilder caption: () -> some View) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.todayFigureTitle)
                    .foregroundStyle(Palette.mutedInk)
                    .lineLimit(1)
                    .privacySensitiveInFeedback(personalTitle)
                value()
                    .font(.todayFigure)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                caption()
                    .font(.todayFigureTitle)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(hint)
    }
}

extension Font {
    /// A figure beside the date: 17 pt semibold on the Mac.
    fileprivate static var todayFigure: Font {
        #if os(macOS)
        return .title2.weight(.semibold)
        #else
        return .title3.weight(.semibold)
        #endif
    }

    /// A figure's title and caption: 11 pt on the Mac.
    fileprivate static var todayFigureTitle: Font {
        #if os(macOS)
        return .subheadline
        #else
        return .caption
        #endif
    }
}

// MARK: - Coming up

/// What's ahead, on the Mac and iPad (UI.md, "Today"): the next check-in
/// and the main plan's milestones ahead, a line each with when.
struct TodayComingUpCard: View {
    let plan: PlanDocument?
    let results: PlanResults?
    let today: CalendarDate

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(CheckInStore.self) private var checkIn
    @Environment(\.baseCurrency) private var currency
    @Environment(\.locale) private var locale

    var body: some View {
        let milestones = plan.map { TodayMilestones.of($0, results: results, library: library, plans: plans) }
        let items = TodayComingUp.items(status: checkIn.status, ahead: milestones?.ahead ?? [],
                                        next: milestones?.next, text: PlanMilestoneText(currency: currency,
                                                                                         locale: locale),
                                        today: today, locale: locale)
        if !items.isEmpty {
            Card("Coming up") {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Metrics.m, verticalSpacing: Metrics.s) {
                    ForEach(items) { item in
                        GridRow {
                            Text(item.when)
                                .foregroundStyle(Palette.mutedInk)
                                .lineLimit(1)
                                .fixedSize()
                                .privacySensitiveInFeedback()
                            AmountSentenceText(item.what)
                                .foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Milestones

/// The main plan's milestones as Today shows them: the Plan screen's, with
/// those reached as Progress works them out.
@MainActor
enum TodayMilestones {
    static func of(_ plan: PlanDocument, results: PlanResults?, library: LibraryStore,
                   plans: PlanStore) -> PlanMilestones {
        let progress = plans.planProgress(of: plan.id, document: plan)
        return PlanMilestones(plan: plan, library: library.library, valuator: library.valuator,
                              asOf: library.asOfDate, results: results, reached: progress.reached)
    }
}
