import Foundation
import Model

/// How much you've been saving: the new money into plan assets over the
/// last 12 months, in today's money, with unusual months counted as a usual
/// one (PLANNER.md, "Continue as you have").
///
/// Each account's new money at a check-in (``Valuator/change(from:to:in:)``)
/// is spread evenly over the days since its own record before, and the
/// days are grouped into months that end on the same day of the month as
/// the latest check-in (on the last day of each month when it's a month
/// end). Money moved between two plan assets cancels out.
public struct SavingPace: Hashable, Sendable {
    /// The new money of one month.
    public struct Month: Hashable, Sendable {
        /// The month's last day.
        public let end: CalendarDate
        /// The new money in it.
        public let newMoney: Decimal
        /// Whether it's unusual, and counted as the usual month instead.
        public let isUnusual: Bool

        public init(end: CalendarDate, newMoney: Decimal, isUnusual: Bool) {
            self.end = end
            self.newMoney = newMoney
            self.isUnusual = isUnusual
        }
    }

    /// The latest check-in, the end of the last month.
    public let asOf: CalendarDate
    /// The currency of every amount: the base currency.
    public let currency: CurrencyCode
    /// The months counted, oldest first: the last 12, or every whole month
    /// since the first check-in when there are fewer.
    public let months: [Month]
    /// The usual month: the median of `months`.
    public let usualMonth: Decimal
    /// The pace: the months' new money, an unusual month counted as the
    /// usual one, scaled to a year when there are fewer than 12.
    public let perYear: Decimal
    /// The lowest and highest pace of the 12 months ending at each of the
    /// last 12 month ends; `nil` without 13 months.
    public let range: ClosedRange<Decimal>?
    /// Each account's new money in `months` from outside plan assets,
    /// scaled to a year, unusual months included; an account with none is
    /// left out. Money moved between plan assets at a check-in comes off
    /// each side pro rata.
    public let byAccount: [AccountID: Decimal]
    /// Accounts whose new money in `months` wasn't recorded, so that the
    /// tracker counts what the main plan pays into them
    /// (``AccountChange/isFlowFromPlan``). That new money is left out, at
    /// each check-in where it came from the plan, since a pace that repeats
    /// the plan says nothing about it.
    public let leftOut: [AccountID]
    /// Whether the amounts are in money of `asOf`. Without an inflation
    /// index with values from the start of the first month, they're all in
    /// money of each check-in.
    public let isInTodaysMoney: Bool
    /// Whether every value and new money in `months` was known.
    public let isComplete: Bool

    /// The number of months a pace covers.
    public static let window = 12
    /// The fewest whole months that give a pace.
    public static let minimumMonths = 3

    public init(asOf: CalendarDate, currency: CurrencyCode, months: [Month], usualMonth: Decimal, perYear: Decimal,
                range: ClosedRange<Decimal>?, byAccount: [AccountID: Decimal], leftOut: [AccountID],
                isInTodaysMoney: Bool, isComplete: Bool) {
        self.asOf = asOf
        self.currency = currency
        self.months = months
        self.usualMonth = usualMonth
        self.perYear = perYear
        self.range = range
        self.byAccount = byAccount
        self.leftOut = leftOut
        self.isInTodaysMoney = isInTodaysMoney
        self.isComplete = isComplete
    }

    /// The months counted as the usual one.
    public var unusualMonths: [Month] { months.filter(\.isUnusual) }

    /// Whether it covers fewer than 12 months and was scaled to a year.
    public var isScaled: Bool { months.count < Self.window }

    /// The pace of `amounts`, the new money of consecutive months: their
    /// total, each unusual month counted as the usual one (their median),
    /// scaled to a year.
    ///
    /// When you usually save (the usual month is above zero), a month is
    /// unusual when it's at least twice the usual saving and at least 1% of
    /// `planAssets`, as Progress marks a check-in where you saved more than
    /// usual (PROGRESS.md, "Milestones"), or when it takes out at least 1%
    /// of `planAssets`. When you usually save nothing, no month is: saving
    /// every quarter, or every other month, is how you save.
    public static func pace(of amounts: [Decimal], planAssets: Decimal)
        -> (perYear: Decimal, usual: Decimal, unusual: [Bool]) {
        guard !amounts.isEmpty else { return (0, 0, []) }
        let usual = median(amounts)
        let large = abs(planAssets) / 100
        let unusual = amounts.map { amount in
            usual > 0 && (amount >= 2 * usual && amount >= large || amount <= 0 && -amount >= large)
        }
        let counted = zip(amounts, unusual).reduce(Decimal(0)) { $0 + ($1.1 ? usual : $1.0) }
        return (counted * Decimal(window) / Decimal(amounts.count), usual, unusual)
    }

    /// The median of `values`, which aren't empty: the middle one, or the
    /// mean of the two in the middle.
    static func median(_ values: [Decimal]) -> Decimal {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// The end of the month `back` months before the one ending on `asOf`:
    /// the same day of the month, or the month's last day when `asOf` is
    /// one or the month is shorter.
    public static func monthEnd(_ back: Int, before asOf: CalendarDate) -> CalendarDate {
        let month = asOf.yearMonth.adding(months: -back)
        if asOf == asOf.yearMonth.lastDay || asOf.day >= month.numberOfDays { return month.lastDay }
        return month.firstDay.adding(days: asOf.day - 1)
    }
}

extension Valuator {
    /// How much you've been saving into plan assets through the latest
    /// check-in on or before `date` (``SavingPace``), in its money with
    /// `inflation`; `nil` with fewer than ``SavingPace/minimumMonths``
    /// whole months since the first check-in.
    public func savingPace(asOf date: CalendarDate, inflation: InflationIndex? = nil) -> SavingPace? {
        let checkIns = checkInDates(in: .planAssets, through: date)
        guard let first = checkIns.first, let asOf = checkIns.last else { return nil }
        // Months 0 (the latest) to 23, each from the end of the one before;
        // only whole months after the first check-in.
        let longest = 2 * SavingPace.window
        let ends = (0...longest).map { SavingPace.monthEnd($0, before: asOf) }
        let available = (0..<longest).prefix(while: { ends[$0 + 1] >= first }).count
        guard available >= SavingPace.minimumMonths else { return nil }

        let intervals = zip(checkIns, checkIns.dropFirst()).filter { $0.1 > ends[available] }
        let reports = intervals.map { change(from: $0.0, to: $0.1, in: .planAssets) }
        let window = min(available, SavingPace.window)
        let leftOut = Set(reports.filter { $0.to > ends[window] }
            .flatMap { $0.accounts.filter { $0.isFlowFromPlan && $0.change.newMoney != 0 }.map(\.account) })

        var months = [Decimal](repeating: 0, count: available)
        var byAccount: [AccountID: Decimal] = [:]
        // In today's money only when the index covers every month, so the
        // months never mix money of today and of each check-in.
        let index = inflation.flatMap {
            $0.value(on: ends[available]) != nil && $0.value(on: asOf) != nil ? $0 : nil
        }
        var isComplete = true
        for report in reports {
            // What holdings held when their records start, without a
            // flow, isn't money saved (a balance's counts as other).
            let included = report.accounts.filter { change in
                guard !change.isFlowFromPlan else { return false }
                guard change.flow == nil, change.change.start == 0, accounts[change.account]?.recordsTrades != true,
                      let first = firstRecordDate(of: change.account)
                else { return true }
                return !(first > report.from && first <= report.to)
            }
            if report.to > ends[window], included.contains(where: { !$0.problems.allSatisfy(\.isNotTrackedYet) }) {
                isComplete = false
            }
            // Money moved between plan assets at this check-in cancels out
            // before it's spread: what went in and came out up to the
            // smaller of the two comes off each side pro rata, so two legs
            // spread over different days don't leave a month too high and
            // another too low.
            let paidIn = included.reduce(Decimal(0)) { $0 + max($1.change.newMoney, 0) }
            let takenOut = included.reduce(Decimal(0)) { $0 - min($1.change.newMoney, 0) }
            let moved = min(paidIn, takenOut)
            for account in included {
                var amount = account.change.newMoney
                if amount == 0 { continue }
                if moved > 0 { amount -= amount > 0 ? amount * moved / paidIn : amount * moved / takenOut }
                if amount == 0 { continue }
                // Spread from the account's own record before, not the
                // check-in before: an account valued quarterly saved over
                // the quarter, not in its last month. A trades account's
                // new money is its deposits and withdrawals since the
                // check-in before, so it's spread from there.
                let from = accounts[account.account]?.recordsTrades == true ? report.from
                    : latestRecordDate(of: account.account, onOrBefore: report.from) ?? report.from
                let days = from.days(to: report.to)
                guard days > 0 else { continue }
                if let index { amount = index.convert(amount, from: report.to, to: asOf) ?? amount }
                for month in 0..<available {
                    let start = max(from, ends[month + 1])
                    let end = min(report.to, ends[month])
                    let overlap = start.days(to: end)
                    guard overlap > 0 else { continue }
                    let part = amount * Decimal(overlap) / Decimal(days)
                    months[month] += part
                    if month < window { byAccount[account.account, default: 0] += part }
                }
            }
        }

        let planAssets = total(on: asOf, in: .planAssets).total
        let latest = Array(months.prefix(window).reversed())
        let pace = SavingPace.pace(of: latest, planAssets: planAssets)
        var range: ClosedRange<Decimal>?
        if available > SavingPace.window {
            let paces = (0...(available - SavingPace.window)).prefix(SavingPace.window).map { shift in
                SavingPace.pace(of: Array(months[shift..<(shift + SavingPace.window)]), planAssets: planAssets).perYear
            }
            if let low = paces.min(), let high = paces.max() { range = low...high }
        }
        let scale = Decimal(SavingPace.window) / Decimal(window)
        return SavingPace(
            asOf: asOf, currency: baseCurrency,
            months: latest.indices.map { index in
                SavingPace.Month(end: ends[window - 1 - index], newMoney: latest[index],
                                 isUnusual: pace.unusual[index])
            },
            usualMonth: pace.usual, perYear: pace.perYear, range: range,
            byAccount: byAccount.filter { $0.value != 0 }.mapValues { $0 * scale },
            leftOut: leftOut.sorted(), isInTodaysMoney: index != nil, isComplete: isComplete)
    }
}
