import Foundation
import Model

/// What came in, was saved and was spent, and the savings rate, over one
/// month or calendar year
/// (PROGRESS.md, "Trends"): over the values dated in it, even when one
/// covers more (after a skipped check-in), as
/// ``Valuator/savingsRate(from:through:)`` counts them. In the base
/// currency.
public struct MoneyInOutPeriod: Hashable, Sendable {
    /// The first day of the month or year.
    public let from: CalendarDate
    /// The last day counted: the month's or year's last day, or the end of
    /// the series when that comes first.
    public let through: CalendarDate
    /// The savings rate over the values dated in the period, with the money
    /// in and out it's worked out from; `nil` when none was counted.
    public let savings: SavingsRate?
    /// With months, the savings rate over the 12 months that end on
    /// ``through``, from the twelfth month of the series; `nil` before it
    /// and with years.
    public let lastTwelveMonths: SavingsRate?

    public init(from: CalendarDate, through: CalendarDate, savings: SavingsRate?,
                lastTwelveMonths: SavingsRate? = nil) {
        self.from = from
        self.through = through
        self.savings = savings
        self.lastTwelveMonths = lastTwelveMonths
    }

    /// Whether no money in and out was counted in the period.
    public var isEmpty: Bool { savings == nil }

    /// Money in: what arrived in cash and savings accounts from outside them.
    public var moneyIn: Decimal { savings?.moneyInOut.moneyIn ?? 0 }

    /// What was paid into pension funds and TFR over the days the pay covers.
    public var pensionContributions: Decimal { savings?.pensionContributions ?? 0 }

    /// What came in: money in plus the pension contributions
    /// (``SavingsRate/income``).
    public var cameIn: Decimal { savings?.income ?? 0 }

    /// What was saved: every account's new money (``SavingsRate/saved``).
    public var saved: Decimal { savings?.saved ?? 0 }

    /// What was spent: what came in less what was saved
    /// (``SavingsRate/spent``).
    public var spent: Decimal { savings?.spent ?? 0 }

    /// The savings rate; `nil` when nothing came in.
    public var rate: Decimal? { savings?.rate }

    /// The days the pay counted in the period covers: from the day after
    /// the valuation the values of the account the most came into are
    /// measured from (``SavingsRate/from``, the days the savings rate counts
    /// pension contributions over) through the latest value's date. So a
    /// savings account checked quarterly, or an account first valued
    /// mid-month, doesn't stretch it. `nil` when nothing was counted.
    public var covers: ClosedRange<CalendarDate>? {
        guard let savings, let end = savings.moneyInOut.lastCounted, savings.from < end else { return nil }
        return savings.from.adding(days: 1)...end
    }

    /// Whether the period's pay (``covers``) covers more than one and a half
    /// months (or years), so it holds more than its own money: a value counts in
    /// the period of its date, so after a skipped check-in its month holds
    /// two months' money.
    public func coversMore(_ grain: PeriodGrain) -> Bool {
        guard let covers else { return false }
        let days = covers.lowerBound.days(to: covers.upperBound) + 1
        switch grain {
        case .months: return Double(days) > 1.5 * 365.25 / 12
        case .years: return Double(days) > 1.5 * 365.25
        }
    }
}

/// Trends' money in and out by period (PROGRESS.md, "Trends"): each month
/// or calendar year from the first with money in and out counted.
public struct MoneyInOutSeries: Hashable, Sendable {
    /// The base currency.
    public let currency: CurrencyCode
    public let grain: PeriodGrain
    /// Oldest first, a period for each month or year from the first with a
    /// value counted through the end, those without one too; empty without
    /// money in and out.
    public let periods: [MoneyInOutPeriod]
    /// Every value counted through the end: where money in and out starts
    /// (``MoneyInOutSummary/measuredFrom``) and the months it was recorded.
    public let recorded: MoneyInOutSummary

    public init(currency: CurrencyCode, grain: PeriodGrain, periods: [MoneyInOutPeriod],
                recorded: MoneyInOutSummary) {
        self.currency = currency
        self.grain = grain
        self.periods = periods
        self.recorded = recorded
    }

    /// Whether no money in and out was counted.
    public var isEmpty: Bool { recorded.isEmpty }
}

extension Valuator {
    /// Money in and out and the savings rate for each month or calendar year
    /// of `grain` from the first with a value counted through `end`
    /// (PROGRESS.md, "Trends"), each over the values dated in it
    /// (``savingsRate(from:through:)``), the last through `end`. With
    /// months, also the savings rate over the 12 months that end at each
    /// month (``savingsRate(overYearEndingOn:)``), from the twelfth month
    /// on, since a single month's rate is noisy.
    public func moneyInOutSeries(_ grain: PeriodGrain, through end: CalendarDate) -> MoneyInOutSeries {
        let firstValue = accounts.values.filter(\.kind.recordsMoneyInOut)
            .compactMap { valuations(for: $0.id).first?.date }.min()
        let recorded = moneyInOut(from: min(firstValue ?? end, end), through: end)
        guard let firstMonth = recorded.months.first else {
            return MoneyInOutSeries(currency: baseCurrency, grain: grain, periods: [], recorded: recorded)
        }
        let start = switch grain {
        case .months: firstMonth.firstDay
        case .years: CalendarDate.firstDay(ofYear: firstMonth.year)
        }
        let periods = grain.periodEnds(from: start, through: end).enumerated().map { index, through in
            let from = switch grain {
            case .months: through.startOfMonth
            case .years: CalendarDate.firstDay(ofYear: through.year)
            }
            return MoneyInOutPeriod(
                from: from, through: through, savings: savingsRate(from: from, through: through),
                lastTwelveMonths: grain == .months && index >= 11 ? savingsRate(overYearEndingOn: through) : nil)
        }
        return MoneyInOutSeries(currency: baseCurrency, grain: grain, periods: periods, recorded: recorded)
    }
}
