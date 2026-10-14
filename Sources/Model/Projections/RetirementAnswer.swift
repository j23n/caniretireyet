import Foundation

/// The answer to "can I retire yet?" for one plan (UI.md, "Headline"): from
/// a plan's latest results, or recorded at a check-in (a ``Headline``).
/// The Overview, the Plan screens, Progress and the widgets all show this
/// one value; the Planner picks which one is the latest (`LatestAnswer`).
public struct RetirementAnswer: Hashable, Sendable {
    /// The confidence level required: 0.9 is "in 9 of 10 simulated futures".
    public var confidence: Double
    /// The earliest retirement age reaching the confidence level; `nil` if none does.
    public var earliestAge: Int?
    /// When that is: the birthday that age is reached on, e.g. 12 April 2042.
    public var earliestDate: CalendarDate?
    /// The plan's target retirement age, if it names one; `nil` in a recorded answer.
    public var targetAge: Int?
    /// The chance of success at the target age.
    public var successAtTarget: Double?
    /// The chance of success when retiring today; `nil` in a recorded answer.
    public var successToday: Double?
    /// The most you could spend a year retiring at the target age, in today's
    /// money; `nil` in a recorded answer.
    public var sustainableSpending: Decimal?
    /// Plan assets as a fraction of what retiring today with the plan's
    /// confidence needs (PLANNER.md, "Assets needed to retire today"): 1 or
    /// more exactly when retiring today works. `nil` in older records and
    /// when the search found no amount.
    public var readiness: Double?
    /// ``readiness`` is a lower bound ("…% or more"): even with the money
    /// that can be drawn now taken out, retiring today works.
    public var readinessIsLowerBound: Bool
    /// Retiring today would need more than the planner searched, so there's
    /// no ``readiness``.
    public var needsMoreThanSearched: Bool
    /// Whether retiring today reaches the confidence level ("Yes.").
    public var canRetireNow: Bool
    /// For an answer recorded at a check-in: the check-in's date.
    public var recordedOn: CalendarDate?

    public init(confidence: Double, earliestAge: Int? = nil, earliestDate: CalendarDate? = nil, targetAge: Int? = nil,
                successAtTarget: Double? = nil, successToday: Double? = nil, sustainableSpending: Decimal? = nil,
                readiness: Double? = nil, readinessIsLowerBound: Bool = false, needsMoreThanSearched: Bool = false,
                canRetireNow: Bool = false, recordedOn: CalendarDate? = nil) {
        self.confidence = confidence
        self.earliestAge = earliestAge
        self.earliestDate = earliestDate
        self.targetAge = targetAge
        self.successAtTarget = successAtTarget
        self.successToday = successToday
        self.sustainableSpending = sustainableSpending
        self.readiness = readiness
        self.readinessIsLowerBound = readinessIsLowerBound
        self.needsMoreThanSearched = needsMoreThanSearched
        self.canRetireNow = canRetireNow
        self.recordedOn = recordedOn
    }

    /// The answer recorded at a check-in. A record has no date for the
    /// earliest age, so it's the birthday that age is reached on (never
    /// before the check-in, as the planner has it), and no spending.
    /// Retiring today works when the recorded readiness, which is rounded
    /// down (``Readiness/rounded(_:)``), is 1 or more.
    public init(recorded headline: Headline, birthDate: CalendarDate?, defaultConfidence: Double = 0.9) {
        self.init(confidence: headline.confidence?.doubleValue ?? defaultConfidence,
                  earliestAge: headline.earliestAge,
                  successAtTarget: headline.successAtTarget?.doubleValue,
                  readiness: headline.readiness?.doubleValue, recordedOn: headline.date)
        if let age = headline.earliestAge, let birthDate {
            earliestDate = Self.earliestDate(age: age, recordedOn: headline.date, birthDate: birthDate)
        }
        canRetireNow = (readiness ?? 0) >= 1
    }

    /// When an earliest `age` recorded at the check-in on `date` is reached:
    /// the birthday of that age, never before the check-in, as the planner
    /// has it.
    public static func earliestDate(age: Int, recordedOn date: CalendarDate, birthDate: CalendarDate) -> CalendarDate {
        max(date, birthDate.adding(years: age))
    }

    /// ``readiness`` as every screen shows it (``Readiness/shown(_:)``).
    public var shownReadiness: Double? {
        readiness.map(Readiness.shown)
    }
}

extension RetirementAnswer: Codable {
    enum CodingKeys: String, CodingKey {
        case confidence, earliestAge, earliestDate, targetAge, successAtTarget, successToday, sustainableSpending
        case readiness, readinessIsLowerBound, needsMoreThanSearched, canRetireNow, recordedOn
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        confidence = try c.decode(Double.self, forKey: .confidence)
        earliestAge = try c.decodeIfPresent(Int.self, forKey: .earliestAge)
        earliestDate = try c.decodeIfPresent(CalendarDate.self, forKey: .earliestDate)
        targetAge = try c.decodeIfPresent(Int.self, forKey: .targetAge)
        successAtTarget = try c.decodeIfPresent(Double.self, forKey: .successAtTarget)
        successToday = try c.decodeIfPresent(Double.self, forKey: .successToday)
        sustainableSpending = try c.decodeDecimalIfPresent(forKey: .sustainableSpending)
        readiness = try c.decodeIfPresent(Double.self, forKey: .readiness)
        readinessIsLowerBound = try c.decodeIfPresent(Bool.self, forKey: .readinessIsLowerBound) ?? false
        needsMoreThanSearched = try c.decodeIfPresent(Bool.self, forKey: .needsMoreThanSearched) ?? false
        canRetireNow = try c.decodeIfPresent(Bool.self, forKey: .canRetireNow) ?? false
        recordedOn = try c.decodeIfPresent(CalendarDate.self, forKey: .recordedOn)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(confidence, forKey: .confidence)
        try c.encodeIfPresent(earliestAge, forKey: .earliestAge)
        try c.encodeIfPresent(earliestDate, forKey: .earliestDate)
        try c.encodeIfPresent(targetAge, forKey: .targetAge)
        try c.encodeIfPresent(successAtTarget, forKey: .successAtTarget)
        try c.encodeIfPresent(successToday, forKey: .successToday)
        try c.encodeDecimalIfPresent(sustainableSpending, forKey: .sustainableSpending)
        try c.encodeIfPresent(readiness, forKey: .readiness)
        try c.encode(readinessIsLowerBound, forKey: .readinessIsLowerBound)
        try c.encode(needsMoreThanSearched, forKey: .needsMoreThanSearched)
        try c.encode(canRetireNow, forKey: .canRetireNow)
        try c.encodeIfPresent(recordedOn, forKey: .recordedOn)
    }
}

/// How a readiness (plan assets as a fraction of what retiring today needs;
/// 1 is 100%) is rounded: down to a whole percent, allowing for the binary
/// representation (0.58 stays 0.58), and below 1 at most 0.99. So a figure
/// never reads 100% while retiring today falls short, and a recorded 1
/// means retiring today works. Headlines record it this way, and every
/// screen, widget and the command line show it this way.
public enum Readiness {
    /// `readiness` rounded, as an exact decimal: 0 when it isn't a finite
    /// number or is below 0.
    public static func rounded(_ readiness: Double) -> Decimal {
        guard readiness.isFinite, readiness > 0 else { return 0 }
        var percent = (readiness * 100 + 1e-9).rounded(.down)
        if readiness < 1 { percent = min(99, percent) }
        guard let whole = Int64(exactly: percent) else { return Decimal(percent) / 100 }
        return Decimal(whole) / 100
    }

    /// `readiness` rounded, to show: ``rounded(_:)`` as a `Double`.
    public static func shown(_ readiness: Double) -> Double {
        rounded(readiness).doubleValue
    }
}
