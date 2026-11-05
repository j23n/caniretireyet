import Foundation
import Model

/// What came in, was saved and was spent, and the savings rate, over one
/// month or calendar year
/// (PROGRESS.md, "Trends"): over the values dated in it, even when one
/// covers more (after a skipped check-in), as
/// ``Valuator/savingsRate(from:through:)`` counts them, with what was saved
/// over the days their pay covers. Each period's days start where the
/// one before's ended, when it counted anything, and otherwise no earlier
/// than where the latest that did ended, so the periods add up to the
/// days they cover together, even when the pay account changes. In the
/// base currency.
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

    /// What came in after tax: money in plus the pension contributions,
    /// less the tax (``SavingsRate/income``).
    public var cameIn: Decimal { savings?.income ?? 0 }

    /// What came in before tax: money in plus the pension contributions.
    public var beforeTax: Decimal { moneyIn + pensionContributions }

    /// The tax paid in the period (``SavingsRate/tax``).
    public var tax: Decimal { savings?.tax ?? 0 }

    /// One-offs: saved, but neither came in nor spent (``SavingsRate/oneOffs``).
    public var oneOffs: Decimal { savings?.oneOffs ?? 0 }

    /// What came in, the tax, what was spent, the one-offs and what was
    /// saved (``SavingsRate/pay``); `nil` when none was counted.
    public var pay: WhatMoved.Pay? { savings?.pay }

    /// The period's money in and out as two bars (``MoneyInOutBars``);
    /// `nil` when none was counted.
    public var bars: MoneyInOutBars? { pay.map(MoneyInOutBars.init) }

    /// What was saved: what every account saved, the one-offs with it
    /// (``SavingsRate/saved``).
    public var saved: Decimal { savings?.saved ?? 0 }

    /// What was spent: what came in less what the pay saved
    /// (``SavingsRate/spent``).
    public var spent: Decimal { savings?.spent ?? 0 }

    /// The savings rate; `nil` when nothing came in after tax.
    public var rate: Decimal? { savings?.rate }

    /// Why a period with money in and out has no savings rate
    /// (``SavingsRate/noRate``); `nil` when it has one or none was counted.
    public var noRate: SavingsRate.NoRate? { savings?.noRate }

    /// The days the pay counted in the period covers, the days the savings
    /// rate counts what was saved over: from the day after
    /// ``SavingsRate/from`` through ``SavingsRate/payThrough``: from where
    /// the period before's ended through the pay account's latest value in
    /// it. So a savings account checked quarterly, another account's later
    /// statement, or an account first valued mid-month, doesn't stretch it,
    /// unless the period before's pay covered no days.
    /// `nil` when nothing was counted, or the pay covers no days (the pay
    /// account has no value in the period).
    public var covers: ClosedRange<CalendarDate>? {
        guard let savings, savings.from < savings.payThrough else { return nil }
        return savings.from.adding(days: 1)...savings.payThrough
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
    /// Every value of ``Valuator/cameInAccounts`` counted through the end:
    /// where money in and out starts (``MoneyInOutSummary/measuredFrom``)
    /// and the months it was recorded.
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
        let firstValue = cameInAccounts.compactMap { valuations(for: $0).first?.date }.min()
        let recorded = moneyInOut(from: min(firstValue ?? end, end), through: end, accounts: cameInAccounts)
        guard let firstMonth = recorded.months.first else {
            return MoneyInOutSeries(currency: baseCurrency, grain: grain, periods: [], recorded: recorded)
        }
        let start = switch grain {
        case .months: firstMonth.firstDay
        case .years: CalendarDate.firstDay(ofYear: firstMonth.year)
        }
        // Each period's pay starts where the one before's ended, so the periods count every day once;
        // after a period with nothing counted, it covers its own days, but none counted before.
        var payAfter: CalendarDate?
        var countedThrough: CalendarDate?
        let periods = grain.periodEnds(from: start, through: end).enumerated().map { index, through in
            let from = switch grain {
            case .months: through.startOfMonth
            case .years: CalendarDate.firstDay(ofYear: through.year)
            }
            let savings = savingsRate(from: from, through: through, payAfter: payAfter, notBefore: countedThrough)
            payAfter = savings?.payThrough
            countedThrough = savings?.payThrough ?? countedThrough
            return MoneyInOutPeriod(
                from: from, through: through, savings: savings,
                lastTwelveMonths: grain == .months && index >= 11 ? savingsRate(overYearEndingOn: through) : nil)
        }
        return MoneyInOutSeries(currency: baseCurrency, grain: grain, periods: periods, recorded: recorded)
    }
}
