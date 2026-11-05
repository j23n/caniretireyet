import Foundation
import Model

/// A rule the library's numbers keep wherever they're right (``AuditChecks``).
/// A violation points at a record to look at, or at a bug.
public enum AuditRule: String, CaseIterable, Hashable, Sendable {
    /// Net worth's change between two check-ins has a part nothing explains
    /// (``WhatMoved/unexplained``) of more than rounding
    /// (``AuditChecks/tolerance``), though every price and rate is known and
    /// so is what every value saved, an account's first value aside (what it
    /// started with).
    case unexplainedChange = "unexplained-change"
    /// An account's bank lines between two of its values don't lead from
    /// one balance to the next (``LineStretch/addsUp``): a line missing, one
    /// twice, or a balance typed wrong.
    case linesDontAddUp = "lines-dont-add-up"
    /// A valuation of a trades account lists a quantity other than its
    /// trades give (``Valuator/reconciliation(of:)``).
    case positionMismatch = "position-mismatch"
    /// The check-in's *What moved it* and its bars disagree on what was
    /// saved, by more than rounding: ``WhatMoved/saved`` against
    /// ``Valuator/savedSplit(of:)``'s.
    case savedDisagrees = "saved-disagrees"
    /// A month's savings rate, as the Months screen counts it, is outside
    /// ``AuditChecks/plausibleMonthlyRates``.
    case monthlyRateOutOfRange = "monthly-rate-out-of-range"
    /// An account whose records start at a check-in held (or owed) more
    /// than the month's money in, counted as what it started with rather
    /// than saved (``SavedStretch/startedWith``).
    case startedWithAboveMoneyIn = "started-with-above-money-in"

    /// The rule in words.
    public var summary: String {
        switch self {
        case .unexplainedChange: "net worth's change has a part nothing explains, though every saved amount is known"
        case .linesDontAddUp: "the bank lines don't add up to the balance"
        case .positionMismatch: "the listed quantity differs from what the trades give"
        case .savedDisagrees: "What moved it and the check-in's bars disagree on what was saved"
        case .monthlyRateOutOfRange: "the month's savings rate is below -50% or above 100%"
        case .startedWithAboveMoneyIn: "the account started with more than the month's money in"
        }
    }

    /// Its place in ``allCases``, to sort violations by.
    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// Where the library breaks a rule (``AuditRule``).
public struct AuditViolation: Hashable, Sendable {
    /// One number behind a violation, by name, e.g. `difference`.
    public struct Amount: Hashable, Sendable {
        public var name: String
        public var value: Decimal

        public init(_ name: String, _ value: Decimal) {
            self.name = name
            self.value = value
        }
    }

    public var rule: AuditRule
    /// The check-in, or the value, it's about.
    public var date: CalendarDate
    /// The account it's about; `nil` for net worth as a whole.
    public var account: AccountID?
    /// The instrument, for a position mismatch.
    public var instrument: InstrumentID?
    /// The numbers behind it, in the order they read best: amounts in the
    /// base currency, an account's own for its lines, quantities for a
    /// position, and a rate as a fraction.
    public var amounts: [Amount]

    public init(rule: AuditRule, date: CalendarDate, account: AccountID? = nil, instrument: InstrumentID? = nil,
                amounts: [Amount] = []) {
        self.rule = rule
        self.date = date
        self.account = account
        self.instrument = instrument
        self.amounts = amounts
    }
}

/// Checks that the library's numbers agree with each other (``AuditRule``),
/// for `retire audit --check` and, later, the app: the residuals vanish where
/// everything is known, the screens agree on one check-in, the bank lines
/// and the trades match their statements, and a month's numbers are
/// plausible. Each check-in is compared with the one before it, a date with
/// a value of any account, as Today compares them.
public struct AuditChecks: Sendable {
    public let library: Library
    public let valuator: Valuator

    /// The savings rates a month can plausibly have: from −50% to 100%.
    public static let plausibleMonthlyRates: ClosedRange<Decimal> = Decimal(-1) / 2...1

    /// How far apart two amounts worked out in different ways may be: half
    /// a cent. Values priced in another currency, or at prices with many
    /// digits, carry decimals down to the last of `Decimal`'s 38 digits, so
    /// adding them up in another order can leave a remainder around
    /// 10⁻³⁰, which is rounding, not money.
    public static let tolerance = Decimal(5) / 1000

    /// Whether `amount` is more than rounding (``tolerance``).
    static func isMoney(_ amount: Decimal) -> Bool {
        abs(amount) > tolerance
    }

    /// `valuator` is the library's; `nil` makes one.
    public init(library: Library, valuator: Valuator? = nil) {
        self.library = library
        self.valuator = valuator ?? Valuator(library: library)
    }

    /// Every violation on or before `date` (every one when `nil`), by date,
    /// then account (net worth first), then rule.
    public func violations(through date: CalendarDate? = nil) -> [AuditViolation] {
        let steps = checkInSteps(through: date)
        let all = unexplainedChanges(steps) + lineStretches(through: date) + positionMismatches(through: date)
            + savedDisagreements(steps) + monthlyRates(through: date) + startedWith(steps)
        return all.sorted {
            ($0.date, $0.account?.rawValue ?? "", $0.rule.order, $0.instrument?.rawValue ?? "")
                < ($1.date, $1.account?.rawValue ?? "", $1.rule.order, $1.instrument?.rawValue ?? "")
        }
    }

    /// One check-in and the one before it: net worth's change between them
    /// and what moved it.
    struct Step {
        var report: ChangeReport
        var moved: WhatMoved
    }

    /// Each check-in on or before `date` after the first, with the one before.
    func checkInSteps(through date: CalendarDate?) -> [Step] {
        let dates = valuator.checkInDates(through: date)
        return zip(dates, dates.dropFirst()).map { from, to in
            let report = valuator.change(from: from, to: to)
            return Step(report: report, moved: valuator.whatMoved(report))
        }
    }

    // MARK: - The checks

    /// ``AuditRule/unexplainedChange`` at each check-in on or before `date`.
    public func unexplainedChanges(through date: CalendarDate? = nil) -> [AuditViolation] {
        unexplainedChanges(checkInSteps(through: date))
    }

    func unexplainedChanges(_ steps: [Step]) -> [AuditViolation] {
        steps.compactMap { step in
            let report = step.report
            let known = report.accounts.allSatisfy { change in
                change.isSavedKnown || startsIn(change.account, after: report.from, through: report.to)
            }
            guard known, step.moved.isPriced, Self.isMoney(step.moved.unexplained) else { return nil }
            return AuditViolation(rule: .unexplainedChange, date: report.to,
                                  amounts: [.init("unexplained", step.moved.unexplained),
                                            .init("change", step.moved.change)])
        }
    }

    /// ``AuditRule/linesDontAddUp``: each stretch of an account's bank lines
    /// that ends on a value on or before `date` and doesn't lead from the
    /// balance before to that value's.
    public func lineStretches(through date: CalendarDate? = nil) -> [AuditViolation] {
        library.accounts.keys.sorted().flatMap { account in
            library.lineStretches(of: account).compactMap { stretch -> AuditViolation? in
                guard let through = stretch.through, date.map({ through <= $0 }) ?? true,
                      let difference = stretch.difference, difference != 0
                else { return nil }
                return AuditViolation(rule: .linesDontAddUp, date: through, account: account,
                                      amounts: [.init("difference", difference),
                                                .init("opening", stretch.opening ?? 0),
                                                .init("lines", stretch.total),
                                                .init("closing", stretch.closing ?? 0)])
            }
        }
    }

    /// ``AuditRule/positionMismatch``: each position a trades account's
    /// valuation on or before `date` lists with a quantity its trades don't give.
    public func positionMismatches(through date: CalendarDate? = nil) -> [AuditViolation] {
        library.accounts.keys.sorted().flatMap { account in
            valuator.reconciliation(of: account)
                .filter { mismatch in date.map { mismatch.date <= $0 } ?? true }
                .map { mismatch in
                    AuditViolation(rule: .positionMismatch, date: mismatch.date, account: account,
                                   instrument: mismatch.instrument,
                                   amounts: [.init("listed", mismatch.listed), .init("derived", mismatch.derived)])
                }
        }
    }

    /// ``AuditRule/savedDisagrees`` at each check-in on or before `date`.
    public func savedDisagreements(through date: CalendarDate? = nil) -> [AuditViolation] {
        savedDisagreements(checkInSteps(through: date))
    }

    func savedDisagreements(_ steps: [Step]) -> [AuditViolation] {
        steps.compactMap { step in
            let split = valuator.savedSplit(of: step.report)
            guard Self.isMoney(split.saved - step.moved.saved) else { return nil }
            return AuditViolation(rule: .savedDisagrees, date: step.report.to,
                                  amounts: [.init("whatMoved", step.moved.saved), .init("savedSplit", split.saved)])
        }
    }

    /// ``AuditRule/monthlyRateOutOfRange``: each check-in of the accounts
    /// with months (``Model/Library/moneyMonths(next:limit:)``) on or before
    /// `date` whose savings rate since the one before, as the Months screen
    /// counts it, is outside ``plausibleMonthlyRates``.
    public func monthlyRates(through date: CalendarDate? = nil) -> [AuditViolation] {
        library.moneyMonths().reversed().compactMap { month -> AuditViolation? in
            guard month.isCheckedIn, let from = month.from, date.map({ month.through <= $0 }) ?? true,
                  let rate = valuator.savingsRate(from: from.adding(days: 1), through: month.through),
                  let share = rate.rate, !Self.plausibleMonthlyRates.contains(share)
            else { return nil }
            return AuditViolation(rule: .monthlyRateOutOfRange, date: month.through,
                                  amounts: [.init("rate", share), .init("savedFromPay", rate.savedFromPay),
                                            .init("cameIn", rate.income)])
        }
    }

    /// ``AuditRule/startedWithAboveMoneyIn`` at each check-in on or before
    /// `date`: each account whose records start since the check-in before
    /// and that started with more, or owed more, than the money in recorded
    /// over those days (``WhatMoved/Pay/moneyIn``, zero without it).
    public func startedWith(through date: CalendarDate? = nil) -> [AuditViolation] {
        startedWith(checkInSteps(through: date))
    }

    func startedWith(_ steps: [Step]) -> [AuditViolation] {
        steps.flatMap { step -> [AuditViolation] in
            let report = step.report
            let moneyIn = step.moved.pay?.moneyIn ?? 0
            let stretches = valuator.savedStretches(
                between: valuator.savedCuts(after: report.from, through: report.to, in: .netWorth), in: .netWorth)
            var startedWith: [AccountID: Decimal] = [:]
            for stretch in stretches { startedWith.merge(stretch.startedWith, uniquingKeysWith: +) }
            return startedWith.keys.sorted().compactMap { account in
                guard let amount = startedWith[account], amount != 0, abs(amount) > moneyIn else { return nil }
                return AuditViolation(rule: .startedWithAboveMoneyIn, date: report.to, account: account,
                                      amounts: [.init("startedWith", amount), .init("moneyIn", moneyIn)])
            }
        }
    }

    /// Whether the account's first record is after `from` through `through`.
    private func startsIn(_ account: AccountID, after from: CalendarDate, through: CalendarDate) -> Bool {
        valuator.firstRecordDate(of: account).map { $0 > from && $0 <= through } ?? false
    }
}
