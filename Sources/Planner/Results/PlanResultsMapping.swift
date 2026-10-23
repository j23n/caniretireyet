import Foundation
import Model
import Tracker

// From the Planner's `PlanResult` to `PlanResults`: plain values that feed
// the chart components and the Plan screens directly.

/// The pieces of ``PlanResults/init(result:mode:birthDate:computedAt:)``.
public enum PlanResultsMapping {
    /// The categories retirement income is stacked by, bottom first (UI.md,
    /// "Retirement income"). Each has its own colour slot, in the same order,
    /// so neighbours in the stack are neighbours in the validated palette.
    public enum IncomeCategory: Hashable, Sendable {
        case withdrawals
        case work
        case pensions
        case windfalls
        case other

        /// The stacking order, bottom first, and the colour slot.
        public var sortKey: Int {
            switch self {
            case .withdrawals: 0
            case .work: 1
            case .pensions: 2
            case .windfalls: 5
            case .other: 7
            }
        }

        /// One-off amounts, which may run off the top of the chart.
        public var isOneOff: Bool {
            self == .windfalls
        }
    }

    /// The label of the taxes on top of retirement income.
    public static let taxesLabel = "Taxes"

    /// The fan in today's money: the start value, then each year-end.
    public static func fan(_ result: PlanResult) -> [FanPoint] {
        let start = result.start.planAssets.doubleValue
        var points = [FanPoint(date: result.start.date.dateValue, p10: start, p25: start, p50: start, p75: start,
                               p90: start)]
        for year in result.fan {
            guard let end = YearMonth(year: year.year, month: 12)?.lastDay, end > result.start.date else { continue }
            points.append(FanPoint(date: end.dateValue, p10: year.p10, p25: year.p25, p50: year.p50, p75: year.p75,
                                   p90: year.p90))
        }
        return points
    }

    /// The date of something that happens in `year` at `age`: that year's
    /// birthday, or `exact` when it's known.
    public static func date(year: Int, birthDate: CalendarDate, exact: CalendarDate? = nil) -> CalendarDate {
        if let exact, exact.year == year { return exact }
        return CalendarDate(year: year, month: birthDate.month, day: min(birthDate.day, 28))
            ?? YearMonth(year: year, month: 6)?.lastDay ?? birthDate
    }

    /// A name without the explanation in brackets: "State pension (estimate)"
    /// → "State pension".
    public static func shortName(_ name: String) -> String {
        guard let bracket = name.range(of: " (") else { return name }
        let short = name[..<bracket.lowerBound].trimmingCharacters(in: .whitespaces)
        return short.isEmpty ? name : short
    }

    /// The planner's markers on the time axis: "Retire at 55", "State pension 67",
    /// "Pension fund 67", "Inheritance 62", "New car 2031", each with its
    /// icon and kind, on its birthday (retirement on `retirementDate`).
    public static func markers(_ markers: [TimelineMarker], birthDate: CalendarDate,
                        retirementDate: CalendarDate?) -> [ChartMarker] {
        markers.map { marker in
            let when = date(year: marker.year, birthDate: birthDate,
                            exact: marker.kind == .retirement ? retirementDate : nil)
            let label: String
            let symbol: String
            let kind: ChartMarker.Kind?
            switch marker.kind {
            case .retirement:
                label = "Retire at \(marker.age)"
                symbol = "figure.walk"
                kind = .retirement
            case .pensionStart:
                label = "\(shortName(marker.label)) \(marker.age)"
                symbol = "building.columns"
                kind = .pension
            case .accessible:
                label = "\(shortName(marker.label)) \(marker.age)"
                symbol = "lock.open"
                kind = .accessible
            case .windfall:
                label = "\(marker.label) \(marker.age)"
                symbol = "gift"
                kind = .windfall
            case .expense:
                label = "\(marker.label) \(marker.year)"
                symbol = "cart"
                kind = .expense
            default:
                label = marker.label
                symbol = "star"
                kind = nil
            }
            return ChartMarker(date: when.dateValue, label: label, systemImage: symbol, kind: kind)
        }
    }

    /// A year's amount for a whole year: the first year may be only the
    /// part after the check-in.
    public static func whole(_ amount: Double, _ year: YearDetail) -> Double {
        year.fraction > 0.01 ? amount / year.fraction : amount
    }

    public static func category(of item: IncomeItem) -> IncomeCategory {
        switch item.kind {
        case .withdrawal: .withdrawals
        case .pension: .pensions
        case .windfall: .windfalls
        case .work: .work
        default: .other
        }
    }

    /// A category's label. Pensions take the name of their one source when
    /// they have one ("State pension"), else a name for all of them.
    public static func label(of category: IncomeCategory, sources: Set<String> = []) -> String {
        switch category {
        case .withdrawals: "Withdrawals"
        case .pensions: sources.count == 1 ? sources.first ?? "Pensions" : "Pensions"
        case .windfalls: "Windfalls"
        case .work: "Work"
        case .other: "Other income"
        }
    }

    /// Each category's colour slot: its place in the stack, so the stack runs
    /// through the palette in its validated order (withdrawals blue, work
    /// orange, pensions aqua, windfalls green, other red). The taxes on top
    /// are a neutral grey (``ChartColor/taxes``): they're not a source.
    public static func color(of category: IncomeCategory) -> ChartColor {
        .series(category.sortKey)
    }

    /// Retirement income per year by source, bottom first, with the taxes
    /// it pays on top (UI.md, "Retirement income").
    ///
    /// A withdrawal is what's sold, before the tax on its gain, and the
    /// year's income also pays the wealth tax and last year's tax on
    /// investment income. So a year's income reaches spending plus taxes.
    /// To read right against the spending line, each source is
    /// shown after its share of the year's taxes (`totalTax`, shared in
    /// proportion to the amounts), and the taxes are a segment of their own
    /// on top: the sources add up to spending, expenses and what's saved,
    /// and the stack to that plus taxes. The tax on what paying off debts
    /// took from pre-tax accounts (``YearDetail/debtWithdrawalTax``) was paid
    /// at the start, not from the year's income, so it's left out here.
    public static func income(_ years: [YearDetail]) -> [IncomeSegment] {
        func category(_ item: IncomeItem) -> IncomeCategory { self.category(of: item) }
        // The names behind each category over all the years, so a category
        // keeps one label (its single source's, else a general one).
        var sources: [IncomeCategory: Set<String>] = [:]
        for year in years {
            for item in year.income where item.amount > 0.5 {
                sources[category(item), default: []].insert(shortName(item.label))
            }
        }
        var segments: [IncomeSegment] = []
        for year in years {
            var gross: [IncomeCategory: Double] = [:]
            for item in year.income where item.amount > 0.5 {
                gross[category(item), default: 0] += whole(item.amount, year)
            }
            let total = gross.values.reduce(0, +)
            guard total > 0.5 else { continue }
            let taxes = min(total, whole(max(0, year.totalTax - year.debtWithdrawalTax), year))
            let share = (total - taxes) / total
            for category in gross.keys.sorted(by: { $0.sortKey < $1.sortKey }) {
                guard let amount = gross[category], amount * share > 0.5 else { continue }
                segments.append(IncomeSegment(
                    year: year.year, source: label(of: category, sources: sources[category] ?? []),
                    amount: amount * share, color: color(of: category), isOneOff: category.isOneOff))
            }
            if taxes > 0.5 {
                segments.append(IncomeSegment(year: year.year, source: taxesLabel, amount: taxes, color: .taxes))
            }
        }
        return segments
    }

    /// Taxes per year by tax: on investments, on wealth and on withdrawals
    /// from pre-tax accounts. The largest over all the years takes the first
    /// colour slot.
    public static func taxes(_ years: [YearDetail]) -> [IncomeSegment] {
        let taxes: [(label: String, amount: KeyPath<YearDetail, Double>)] = [
            ("Tax on investments", \.investmentTax), ("Wealth tax", \.wealthTax),
            ("Tax on withdrawals", \.withdrawalTax),
        ]
        let totals: [Double] = taxes.map { tax in
            years.reduce(0.0) { total, year in
                let amount = year[keyPath: tax.amount]
                return amount > 0.5 ? total + whole(amount, year) : total
            }
        }
        let ranked = taxes.indices.filter { totals[$0] > 0 }.sorted { (totals[$0], $1) > (totals[$1], $0) }
        var segments: [IncomeSegment] = []
        for year in years {
            for (slot, index) in ranked.enumerated() {
                let amount = year[keyPath: taxes[index].amount]
                guard amount > 0.5, whole(amount, year) > 0.5 else { continue }
                segments.append(IncomeSegment(year: year.year, source: taxes[index].label,
                                              amount: whole(amount, year), color: .series(slot)))
            }
        }
        return segments
    }

    /// Saving per month in the first working year (a whole one if there is one).
    public static func monthlySaving(_ years: [YearDetail]) -> Decimal? {
        let working = years.filter { $0.workingShare > 0 }
        guard let year = working.first(where: { $0.workingShare > 0.999 && $0.fraction > 0.999 }) ?? working.first
        else { return nil }
        let share = year.fraction * year.workingShare
        guard share > 0.01 else { return nil }
        return Decimal(wholeNumber: year.savings / share / 12)
    }
}
