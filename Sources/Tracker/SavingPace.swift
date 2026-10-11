import Foundation
import Model

/// How much you've been saving: the new money into plan assets over the
/// last 12 months, in today's money, with unusual months counted as a usual
/// one (PLANNER.md, "Continue as you have").
///
/// Each account's new money at a check-in (``Valuator/change(from:to:in:)``)
/// is spread evenly over the days since its own record before, or since it
/// was last paid when it's paid regularly, and the days are
/// grouped into months that end on the same day of the month as the
/// latest check-in (on the last day of each month when it's a month end).
/// Money moved between two plan assets cancels out.
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
    /// since every plan asset is tracked (the first record of each one
    /// opened before it) when there are fewer.
    public let months: [Month]
    /// The usual month: the median of `months`.
    public let usualMonth: Decimal
    /// The pace: the months' new money, an unusual month counted as the
    /// usual one, scaled to a year when there are fewer than 12.
    public let perYear: Decimal
    /// The lowest and highest pace of the 12 months ending at each of the
    /// last month ends, up to 12; `nil` without 13 months, or when the
    /// pace is in today's money and the inflation index doesn't cover
    /// them all. The months
    /// before `months` aren't checked for missing values (`isComplete`) or
    /// left-out accounts (`leftOut`).
    public let range: ClosedRange<Decimal>?
    /// Each account's new money in `months` from outside plan assets,
    /// scaled to a year, unusual months included; an account with none is
    /// left out. Money moved between plan assets at a check-in comes off
    /// each side pro rata.
    public let byAccount: [AccountID: Decimal]
    /// Each account's share of `perYear`: its new money in `months`, scaled
    /// to a year, with an unusual month counted as the usual one. One that
    /// saved more is split between accounts as that month was; one that took
    /// money out is split as the usual months were. The shares add up to
    /// `perYear`. A pace made without them (in tests) takes `byAccount`.
    public let byAccountInPace: [AccountID: Decimal]
    /// Accounts whose new money in `months` wasn't recorded, so that the
    /// tracker counts what the main plan pays into them, nothing without a
    /// contribution
    /// (``AccountChange/isFlowFromPlan``). That new money is left out, at
    /// each check-in where it came from the plan, since a pace that repeats
    /// the plan says nothing about it.
    public let leftOut: [AccountID]
    /// Accounts whose saving at the rate of their latest payment goes on to
    /// `asOf`, for at most as long again: paid regularly and not valued
    /// since, or paid less often than plan assets are valued, or valued
    /// less often and not since, when that reaches the months;
    /// money taken out isn't carried forward.
    public let carriedForward: [AccountID]
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
                range: ClosedRange<Decimal>?, byAccount: [AccountID: Decimal],
                byAccountInPace: [AccountID: Decimal]? = nil, leftOut: [AccountID],
                carriedForward: [AccountID], isInTodaysMoney: Bool, isComplete: Bool) {
        self.asOf = asOf
        self.currency = currency
        self.months = months
        self.usualMonth = usualMonth
        self.perYear = perYear
        self.range = range
        self.byAccount = byAccount
        self.byAccountInPace = byAccountInPace ?? byAccount
        self.leftOut = leftOut
        self.carriedForward = carriedForward
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
            usual > 0 && (amount >= 2 * usual && amount >= large || amount < 0 && -amount >= large)
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
    /// whole months since every plan asset is tracked.
    public func savingPace(asOf date: CalendarDate, inflation: InflationIndex? = nil) -> SavingPace? {
        let checkIns = checkInDates(in: .planAssets, through: date)
        guard let first = checkIns.first, let asOf = checkIns.last else { return nil }
        // The months start once every plan asset open before the first
        // check-in is tracked: before such an account was first valued, its
        // months would count as saving nothing. One opened later is new.
        let tracked = accounts.values.filter { NetWorthScope.planAssets.includes($0) && $0.opened < first }
            .compactMap { account in
                firstRecordDate(of: account.id).flatMap { $0 > account.opened && $0 <= asOf ? $0 : nil }
            }
            .max()
        let start = max(first, tracked ?? first)
        // Months 0 (the latest) to 22, each from the end of the one before,
        // which the pace and its range read; only whole months after the
        // start.
        let longest = 2 * SavingPace.window - 1
        let ends = (0...longest).map { SavingPace.monthEnd($0, before: asOf) }
        let available = (0..<longest).prefix(while: { ends[$0 + 1] >= start }).count
        guard available >= SavingPace.minimumMonths else { return nil }

        // The check-ins in the months, and back to each open plan asset's
        // latest record before them, so an account valued once a year
        // before the months can still go on into them; never further back
        // than 23 months before the latest check-in.
        let before = accounts.values.filter {
            NetWorthScope.planAssets.includes($0) && $0.closed.map { $0 > ends[available] } ?? true
        }.compactMap { latestRecordDate(of: $0.id, onOrBefore: ends[available]) }.min().map { max($0, ends[longest]) }
            ?? ends[available]
        let intervals = zip(checkIns, checkIns.dropFirst()).filter { $0.1 > ends[available] || $0.1 >= before }
        let reports = intervals.map { change(from: $0.0, to: $0.1, in: .planAssets) }
        let window = min(available, SavingPace.window)
        // An account whose new money came from the plan, or would have with
        // a contribution in it: it had a value before, so the money is
        // missing, not what it held when its records start.
        let leftOut = Set(reports.filter { $0.to > ends[window] }.flatMap { report in
            report.accounts.filter { change in
                change.isFlowFromPlan && (change.change.newMoney != 0
                    || firstRecordDate(of: change.account).map { $0 <= report.from } == true)
            }.map(\.account)
        })

        // In today's money only when the index covers every month, so the
        // months never mix money of today and of each check-in; without
        // the range's older months covered too, there's no range.
        let index = inflation.flatMap {
            $0.value(on: ends[window]) != nil && $0.value(on: asOf) != nil ? $0 : nil
        }
        let hasRange = available > SavingPace.window
            && (index == nil || index?.value(on: ends[available]) != nil)
        var isComplete = true
        // Each account's new money at each check-in where it had some,
        // after money moved between plan assets cancels out.
        var paid: [(account: AccountID, from: CalendarDate, to: CalendarDate, amount: Decimal, isMissing: Bool)] = []
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
            // another too low. Only when the two are alike (the smaller at
            // least half the larger): a large withdrawal isn't a transfer.
            let paidIn = included.reduce(Decimal(0)) { $0 + max($1.change.newMoney, 0) }
            let takenOut = included.reduce(Decimal(0)) { $0 - min($1.change.newMoney, 0) }
            let moved = 2 * min(paidIn, takenOut) >= max(paidIn, takenOut) ? min(paidIn, takenOut) : 0
            for account in included {
                var amount = account.change.newMoney
                if moved > 0, amount != 0 {
                    amount -= amount > 0 ? amount * moved / paidIn : amount * moved / takenOut
                }
                if amount == 0 { continue }
                // Spread from the account's own record before, not the
                // check-in before: an account valued quarterly saved over
                // the quarter, not in its last month. A trades account's
                // new money is its deposits and withdrawals since the
                // check-in before, so it's spread from there, and so is an
                // account closed since, whose closing date is known.
                let closed = accounts[account.account]?.closed.map { $0 >= report.from && $0 < report.to } ?? false
                let from = accounts[account.account]?.recordsTrades == true || closed ? report.from
                    : latestRecordDate(of: account.account, onOrBefore: report.from) ?? report.from
                guard from < report.to else { continue }
                if let index { amount = index.convert(amount, from: report.to, to: asOf) ?? amount }
                paid.append((account.account, from, report.to, amount,
                             !account.problems.allSatisfy(\.isNotTrackedYet)))
            }
        }

        var months = [Decimal](repeating: 0, count: available)
        // Each account's part of each of the window's months.
        var parts: [AccountID: [Decimal]] = [:]
        func spread(_ amount: Decimal, of account: AccountID, from: CalendarDate, to: CalendarDate) {
            let days = from.days(to: to)
            guard amount != 0, days > 0 else { return }
            for month in 0..<available {
                let overlap = max(from, ends[month + 1]).days(to: min(to, ends[month]))
                guard overlap > 0 else { continue }
                let part = amount * Decimal(overlap) / Decimal(days)
                months[month] += part
                if month < window { parts[account, default: Array(repeating: 0, count: window)][month] += part }
            }
        }
        // The usual time between check-ins of plan assets.
        let checkInGaps = intervals.map { $0.0.days(to: $0.1) }.sorted()
        let usualCheckIn = checkInGaps.isEmpty ? 0 : checkInGaps[(checkInGaps.count - 1) / 2]
        var carriedForward: [AccountID] = []
        for (account, payments) in Dictionary(grouping: paid, by: { $0.account }).sorted(by: { $0.key < $1.key }) {
            // An account paid regularly, at least three times, with
            // check-ins in between that record nothing (a pension fund marked
            // unchanged between its quarterly statements), saved over the
            // time since it was last paid: each payment is spread from the
            // one before, and the first over as long as the time to the next,
            // but never over more than half as long again as the usual time
            // between payments, so a one-off long after the others stays a
            // one-off. Only a payment like the usual one (above zero, at most
            // twice their median) is spread back: a one-off stays in its
            // check-in. A trades account's deposits are dated, so they stay
            // where they are.
            let firstRecord = firstRecordDate(of: account)
            let gaps = zip(payments, payments.dropFirst()).map { $0.0.to.days(to: $0.1.to) }.sorted()
            let regular = payments.count >= 3 && accounts[account]?.recordsTrades != true
            let usualGap = regular ? gaps[(gaps.count - 1) / 2] : 0
            let furthest = usualGap * 3 / 2
            let usual = regular ? SavingPace.median(payments.map(\.amount)) : 0
            var spans: [(from: CalendarDate, to: CalendarDate, amount: Decimal, isMissing: Bool)] = []
            for (number, payment) in payments.enumerated() {
                guard regular, usual > 0, payment.amount > 0, payment.amount <= 2 * usual else {
                    spans.append((payment.from, payment.to, payment.amount, payment.isMissing))
                    continue
                }
                let before = number > 0 ? payments[number - 1].to
                    : payment.to.adding(days: -payments[0].to.days(to: payments[1].to))
                let earliest = [before, payment.to.adding(days: -furthest), firstRecord ?? before].max() ?? before
                spans.append((min(payment.from, earliest), payment.to, payment.amount, payment.isMissing))
            }
            for span in spans { spread(span.amount, of: account, from: span.from, to: span.to) }
            // An account goes on saving as it did up to its latest payment,
            // to the latest check-in and for at most as long again, when it's
            // paid regularly (and that payment was like the others) and
            // either isn't valued since or is paid less often than plan
            // assets are valued (a pension fund paid each quarter and marked
            // unchanged in between), or when it's valued less often than
            // plan assets and not since: an account valued once a year saved
            // in the months since its statement too. Valued since, it's
            // carried only while its next payment isn't overdue: one that
            // stopped paying in has stopped saving. "Less often" is over
            // half as long again as the usual time between check-ins. A
            // one-off only skipped at a check-in isn't repeated, nor money
            // taken out, nor an amount the inflation index couldn't put in
            // today's money.
            let notValuedSince = spans.last.map { latestRecordDate(of: account, onOrBefore: asOf) == $0.to } ?? false
            guard let last = spans.last, last.amount > 0, last.to < asOf,
                  regular ? last.amount <= 2 * usual
                      && (notValuedSince || usualGap * 2 > usualCheckIn * 3 && last.to.days(to: asOf) <= furthest)
                      : notValuedSince && last.from.days(to: last.to) * 2 > usualCheckIn * 3,
                  accounts[account]?.recordsTrades != true, accounts[account]?.closed.map({ $0 > asOf }) ?? true,
                  index.map({ $0.value(on: last.to) != nil }) ?? true
            else { continue }
            let length = last.from.days(to: last.to)
            let until = min(asOf, last.to.adding(days: length))
            spread(last.amount * Decimal(last.to.days(to: until)) / Decimal(length), of: account,
                   from: last.to, to: until)
            // Listed when it reaches the months the pace reads, carried into
            // them from a check-in that may be before them.
            guard until > ends[window] else { continue }
            carriedForward.append(account)
            if last.isMissing { isComplete = false }
        }

        let planAssets = total(on: asOf, in: .planAssets).total
        let latest = Array(months.prefix(window).reversed())
        let pace = SavingPace.pace(of: latest, planAssets: planAssets)
        var range: ClosedRange<Decimal>?
        if hasRange {
            let paces = (0...(available - SavingPace.window)).prefix(SavingPace.window).map { shift in
                // Each window's unusual months by plan assets at its own end.
                let atEnd = total(on: ends[shift], in: .planAssets).total
                let year = Array(months[shift..<(shift + SavingPace.window)])
                return SavingPace.pace(of: year, planAssets: atEnd).perYear
            }
            if let low = paces.min(), let high = paces.max() { range = low...high }
        }
        let scale = Decimal(SavingPace.window) / Decimal(window)
        // An unusual month counts as the usual month: one that saved more,
        // split as it was; one that took money out, split as the usual
        // months were, so an account paying as usual keeps a share like theirs.
        let isUnusual = (0..<window).map { pace.unusual[window - 1 - $0] }
        let usualParts = parts.mapValues { amounts in
            amounts.indices.reduce(Decimal(0)) { isUnusual[$1] ? $0 : $0 + amounts[$1] }
        }
        let usualTotal = usualParts.values.reduce(0, +)
        let takenOut = Decimal(isUnusual.indices.filter { isUnusual[$0] && months[$0] <= 0 }.count)
        let byAccount = parts.mapValues { $0.reduce(0, +) }.filter { $0.value != 0 }
        let inPace = parts.mapValues { amounts in
            amounts.indices.reduce(Decimal(0)) { total, month in
                guard isUnusual[month] else { return total + amounts[month] }
                if months[month] > 0 { return total + amounts[month] * pace.usual / months[month] }
                return total
            }
        }.merging(usualParts.mapValues { share in
            usualTotal > 0 ? pace.usual * takenOut * share / usualTotal : 0
        }, uniquingKeysWith: +).filter { $0.value != 0 }
        return SavingPace(
            asOf: asOf, currency: baseCurrency,
            months: latest.indices.map { index in
                SavingPace.Month(end: ends[window - 1 - index], newMoney: latest[index],
                                 isUnusual: pace.unusual[index])
            },
            usualMonth: pace.usual, perYear: pace.perYear, range: range,
            byAccount: byAccount.mapValues { $0 * scale }, byAccountInPace: inPace.mapValues { $0 * scale },
            leftOut: leftOut.sorted(), carriedForward: carriedForward.sorted(), isInTodaysMoney: index != nil,
            isComplete: isComplete)
    }
}
