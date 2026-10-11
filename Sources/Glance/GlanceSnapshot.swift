import Foundation
import Model

/// What the widgets show: net worth today and how it changed at the latest
/// check-in, the asset mix, the main plan's answer and when the next
/// check-in is due (UI.md, "Widgets").
///
/// The app writes it whenever the library or the answer changes; the widget
/// extension reads it and never opens the library. Amounts are in
/// ``currency``, the library's base currency. Whatever depends on the day a
/// widget is drawn (the countdown to retirement, the days to the check-in)
/// is worked out then, from the dates here.
public struct GlanceSnapshot: Hashable, Sendable, Codable {
    /// The currency of every amount: the library's base currency.
    public var currency: CurrencyCode
    /// Net worth today, as the Overview has it; `nil` before the first
    /// check-in.
    public var netWorth: NetWorthGlance?
    /// Net worth today by asset class, in stacking order (cash, bonds,
    /// equity, gold, crypto, real estate, other), then debts. Empty before
    /// the first check-in.
    public var allocation: [AllocationSlice]
    /// The main plan's answer; `nil` without a main plan, or before it has one.
    public var retirement: RetirementGlance?
    /// When the next check-in is due.
    public var checkIn: CheckInGlance
    /// The main plan's next milestone (PROGRESS.md, "Milestones"); `nil`
    /// without one.
    public var milestone: MilestoneGlance?

    public init(currency: CurrencyCode, netWorth: NetWorthGlance?, allocation: [AllocationSlice],
                retirement: RetirementGlance?, checkIn: CheckInGlance, milestone: MilestoneGlance? = nil) {
        self.currency = currency
        self.netWorth = netWorth
        self.allocation = allocation
        self.retirement = retirement
        self.checkIn = checkIn
        self.milestone = milestone
    }
}

// MARK: - The next milestone

/// The main plan's next milestone (PROGRESS.md, "Milestones"): what it is,
/// how far there, and when the plan's median future typically reaches it.
public struct MilestoneGlance: Hashable, Sendable {
    /// What a milestone is, as written in the snapshot.
    public struct Kind: OpenEnum {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        /// A round amount of plan assets.
        public static let roundAmount: Kind = "roundAmount"
        /// Enough for ``MilestoneGlance/years`` years of retirement spending.
        public static let yearsOfSpending: Kind = "yearsOfSpending"
        /// ``MilestoneGlance/share`` of what retiring today needs.
        public static let shareOfNeeded: Kind = "shareOfNeeded"
        /// Where a typical year's growth matches a year's saving.
        public static let crossover: Kind = "crossover"

        public static let knownValues: [Kind] = [.roundAmount, .yearsOfSpending, .shareOfNeeded, .crossover]
    }

    public var kind: Kind
    /// The plan assets that reach it, in ``GlanceSnapshot/currency``.
    public var amount: Decimal
    /// For years of spending, how many.
    public var years: Int?
    /// For a share of what retiring today needs: 0.5 is half.
    public var share: Decimal?
    /// How far there, from 0 to 1.
    public var progress: Double
    /// When the median future typically reaches it; `nil` without results.
    public var typically: CalendarDate?

    public init(kind: Kind, amount: Decimal, years: Int? = nil, share: Decimal? = nil, progress: Double,
                typically: CalendarDate? = nil) {
        self.kind = kind
        self.amount = amount
        self.years = years
        self.share = share
        self.progress = progress
        self.typically = typically
    }
}

// MARK: - Net worth

/// Net worth today, as the Overview has it, the change at the latest
/// check-in, and a year of history.
public struct NetWorthGlance: Hashable, Sendable {
    /// The date net worth is reported on: the day the app wrote the snapshot.
    public var date: CalendarDate
    /// The sum of what could be valued.
    public var total: Decimal
    /// Whether every account could be valued; when not, ``total`` misses some.
    public var isComplete: Bool
    /// The change between the last two check-ins on or before ``date``;
    /// `nil` before the second check-in.
    public var sinceLastCheckIn: NetWorthChange?
    /// The change since 31 December of last year, as a fraction of the value
    /// then; `nil` without a value then, or when it was zero.
    public var thisYear: Double?
    /// Net worth at each month end of the year up to ``date``, and on
    /// ``date`` itself, oldest first. Empty for the Overview's hero, which
    /// draws no line.
    public var history: [GlancePoint]

    public init(date: CalendarDate, total: Decimal, isComplete: Bool, sinceLastCheckIn: NetWorthChange?,
                thisYear: Double?, history: [GlancePoint]) {
        self.date = date
        self.total = total
        self.isComplete = isComplete
        self.sinceLastCheckIn = sinceLastCheckIn
        self.thisYear = thisYear
        self.history = history
    }
}

/// How net worth changed between two check-ins, split into markets, new
/// money and the rest (UI.md, "Since last check-in").
public struct NetWorthChange: Hashable, Sendable {
    /// The check-in before the latest one.
    public var from: CalendarDate
    /// The latest check-in.
    public var to: CalendarDate
    /// Net worth then.
    public var start: Decimal
    /// Price and exchange-rate movements, interest, reinvested dividends.
    public var markets: Decimal
    /// Money added (+) or taken out (−).
    public var newMoney: Decimal
    /// What can't be explained otherwise.
    public var other: Decimal
    /// Net worth on the latest check-in.
    public var end: Decimal

    public init(from: CalendarDate, to: CalendarDate, start: Decimal, markets: Decimal, newMoney: Decimal,
                other: Decimal, end: Decimal) {
        self.from = from
        self.to = to
        self.start = start
        self.markets = markets
        self.newMoney = newMoney
        self.other = other
        self.end = end
    }

    /// `end − start`.
    public var change: Decimal { end - start }

    /// The change as a fraction of ``start``, what a locked widget shows
    /// instead of the amount; `nil` when it started from zero.
    public var fraction: Double? {
        start == 0 ? nil : (change / abs(start)).doubleValue
    }
}

/// One point of a value series.
public struct GlancePoint: Hashable, Sendable {
    public var date: CalendarDate
    /// The sum of what could be valued.
    public var value: Decimal

    public init(date: CalendarDate, value: Decimal) {
        self.date = date
        self.value = value
    }
}

/// One asset class's part of net worth.
public struct AllocationSlice: Hashable, Sendable {
    /// The key debts have: they aren't an asset class.
    public static let debts = "debts"

    /// The asset class (`cash`, `equity`, … as in the files), or ``debts``.
    public var key: String
    /// Its English name: "Real estate", "Debts".
    public var name: String
    /// The value in the base currency; negative for debts.
    public var value: Decimal
    /// The value as a fraction of what you own (the positive slices);
    /// negative for debts, `nil` when nothing is positive.
    public var share: Double?

    public init(key: String, name: String, value: Decimal, share: Double?) {
        self.key = key
        self.name = name
        self.value = value
        self.share = share
    }
}

// MARK: - Retirement

/// The main plan's answer to "can I retire yet?", and how it moved.
public struct RetirementGlance: Hashable, Sendable, Codable {
    /// The latest answer: the plan's latest results, or the last answer
    /// recorded at a check-in.
    public var answer: RetirementAnswer
    /// The earliest age recorded at each check-in of the year up to the
    /// latest one, oldest first.
    public var history: [AnswerPoint]

    public init(answer: RetirementAnswer, history: [AnswerPoint]) {
        self.answer = answer
        self.history = history
    }

    /// The last move of the earliest age in ``history``: "55 → 54 in June".
    /// `nil` when it never moved, or when the answer shown is no longer the
    /// one last recorded (the plan was changed and calculated since), so the
    /// move doesn't sit next to a number it doesn't lead to.
    public var lastMove: AnswerMove? {
        guard let latest = history.last, latest.earliestAge == answer.earliestAge,
              let index = history.indices.last(where: { $0 > 0 && history[$0].earliestAge != history[$0 - 1].earliestAge })
        else { return nil }
        return AnswerMove(from: history[index - 1].earliestAge, to: history[index].earliestAge,
                          date: history[index].date)
    }
}

/// The answer itself, without the history.
public struct RetirementAnswer: Hashable, Sendable {
    /// The confidence level required: 0.9 is "in 9 of 10 simulated futures".
    public var confidence: Double
    /// The earliest retirement age reaching the confidence level; `nil` if none does.
    public var earliestAge: Int?
    /// When that is: the birthday that age is reached on, e.g. 12 April 2042.
    public var earliestDate: CalendarDate?
    /// The plan's target retirement age, if it names one.
    public var targetAge: Int?
    /// The most you could spend a year retiring at the target age, in today's
    /// money; `nil` in a recorded answer.
    public var sustainableSpending: Decimal?
    /// Plan assets as a fraction of what retiring today needs (PLANNER.md,
    /// "Assets needed to retire today"): 1 or more exactly when retiring
    /// today works.
    public var readiness: Double?
    /// ``readiness`` is a lower bound ("…% or more").
    public var readinessIsLowerBound: Bool
    /// Retiring today would need more than 20 times your plan assets, so
    /// there's no ``readiness``.
    public var needsMoreThanSearched: Bool
    /// Whether retiring today reaches the confidence level ("Yes.").
    public var canRetireNow: Bool

    public init(confidence: Double, earliestAge: Int? = nil, earliestDate: CalendarDate? = nil, targetAge: Int? = nil,
                sustainableSpending: Decimal? = nil, readiness: Double? = nil, readinessIsLowerBound: Bool = false,
                needsMoreThanSearched: Bool = false, canRetireNow: Bool = false) {
        self.confidence = confidence
        self.earliestAge = earliestAge
        self.earliestDate = earliestDate
        self.targetAge = targetAge
        self.sustainableSpending = sustainableSpending
        self.readiness = readiness
        self.readinessIsLowerBound = readinessIsLowerBound
        self.needsMoreThanSearched = needsMoreThanSearched
        self.canRetireNow = canRetireNow
    }

    /// The answer recorded at a check-in. A record has no date for the
    /// earliest age, so it's the birthday that age is reached on (never
    /// before the check-in, as the planner has it), and no spending. Retiring
    /// today works when the recorded readiness, rounded down, is 1.
    public init(recorded headline: Headline, birthDate: CalendarDate?, defaultConfidence: Double = 0.9) {
        confidence = headline.confidence?.doubleValue ?? defaultConfidence
        earliestAge = headline.earliestAge
        if let age = headline.earliestAge, let birthDate {
            earliestDate = Self.earliestDate(age: age, recordedOn: headline.date, birthDate: birthDate)
        }
        readiness = headline.readiness?.doubleValue
        readinessIsLowerBound = false
        needsMoreThanSearched = false
        canRetireNow = (readiness ?? 0) >= 1
    }

    /// When an earliest `age` recorded at the check-in on `date` is reached:
    /// the birthday of that age, never before the check-in, as the planner
    /// has it.
    public static func earliestDate(age: Int, recordedOn date: CalendarDate, birthDate: CalendarDate) -> CalendarDate {
        max(date, birthDate.adding(years: age))
    }

    /// ``readiness`` as the app shows it: below 1 rounded down to a whole
    /// percent, as headlines record it (allowing for the binary
    /// representation: 0.58 stays 0.58), so it never reads 100% while
    /// retiring today falls short; from 1 on, as it is.
    public var shownReadiness: Double? {
        guard let readiness else { return nil }
        guard readiness < 1 else { return readiness }
        return min(0.99, max(0, (readiness * 100 + 1e-9).rounded(.down) / 100))
    }
}

/// The earliest age recorded at one check-in.
public struct AnswerPoint: Hashable, Sendable, Codable {
    public var date: CalendarDate
    /// `nil` when no age worked out.
    public var earliestAge: Int?

    public init(date: CalendarDate, earliestAge: Int?) {
        self.date = date
        self.earliestAge = earliestAge
    }
}

/// A change of the earliest age between two check-ins.
public struct AnswerMove: Hashable, Sendable {
    public var from: Int?
    public var to: Int?
    /// The check-in that recorded the new age.
    public var date: CalendarDate

    public init(from: Int?, to: Int?, date: CalendarDate) {
        self.from = from
        self.to = to
        self.date = date
    }

    /// Whether retirement moved sooner: a lower age, or one where there was none.
    public var isSooner: Bool {
        switch (from, to) {
        case let (from?, to?): to < from
        case (nil, _?): true
        default: false
        }
    }
}

// MARK: - Check-in

/// When the next check-in is due (UI.md, "Navigation": once a month, at the
/// month's end), for the app's check-in accessory and the widgets alike.
public struct CheckInGlance: Hashable, Sendable, Codable {
    /// How many days before ``next`` a check-in counts as due.
    public static let dueWindow = 3
    /// A check-in this many days or more before its month's end still
    /// leaves that month end due.
    public static let earlyCheckInDays = 7

    /// The latest check-in; `nil` before the first.
    public var last: CalendarDate?
    /// The month end the next check-in is for.
    public var next: CalendarDate

    public init(last: CalendarDate?, next: CalendarDate) {
        self.last = last
        self.next = next
    }

    /// The next check-in after one on `last`: the following month's end, or
    /// that month's own if the check-in was early in the month
    /// (``earlyCheckInDays``). Before the first check-in, `today`.
    public init(last: CalendarDate?, today: CalendarDate) {
        let next = last.map { last in
            last.days(to: last.endOfMonth) >= Self.earlyCheckInDays ? last.endOfMonth : last.yearMonth.next.lastDay
        }
        self.init(last: last, next: next ?? today)
    }

    /// Days from `today` to ``next``; negative once it has passed.
    public func daysUntilDue(on today: CalendarDate) -> Int {
        today.days(to: next)
    }

    /// Whether it's time to check in on `today`: within ``dueWindow`` days of
    /// ``next``, or after it, or there hasn't been one.
    public func isDue(on today: CalendarDate) -> Bool {
        last == nil || daysUntilDue(on: today) <= Self.dueWindow
    }

    /// How much of the time from the last check-in to the next has passed
    /// on `today`, from 0 to 1.
    public func elapsed(on today: CalendarDate) -> Double {
        guard let last else { return 1 }
        let length = last.days(to: next)
        guard length > 0 else { return 1 }
        return min(max(Double(last.days(to: today)) / Double(length), 0), 1)
    }
}
