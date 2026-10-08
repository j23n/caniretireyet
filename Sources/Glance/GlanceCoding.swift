import Foundation
import Model

// JSON for the snapshot types that carry amounts: decimals are strings in
// their shortest exact form, as in the library's files, never through
// `Double`. The other snapshot types use the synthesized coding.

extension MilestoneGlance: Codable {
    enum CodingKeys: String, CodingKey {
        case kind, amount, years, share, progress, typically
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        amount = try c.decodeDecimal(forKey: .amount)
        years = try c.decodeIfPresent(Int.self, forKey: .years)
        share = try c.decodeDecimalIfPresent(forKey: .share)
        progress = try c.decode(Double.self, forKey: .progress)
        typically = try c.decodeIfPresent(CalendarDate.self, forKey: .typically)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encodeDecimal(amount, forKey: .amount)
        try c.encodeIfPresent(years, forKey: .years)
        try c.encodeDecimalIfPresent(share, forKey: .share)
        try c.encode(progress, forKey: .progress)
        try c.encodeIfPresent(typically, forKey: .typically)
    }
}

extension NetWorthGlance: Codable {
    enum CodingKeys: String, CodingKey {
        case date, total, isComplete, sinceLastCheckIn, thisYear, history
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(CalendarDate.self, forKey: .date)
        total = try c.decodeDecimal(forKey: .total)
        isComplete = try c.decode(Bool.self, forKey: .isComplete)
        sinceLastCheckIn = try c.decodeIfPresent(NetWorthChange.self, forKey: .sinceLastCheckIn)
        thisYear = try c.decodeIfPresent(Double.self, forKey: .thisYear)
        history = try c.decode([GlancePoint].self, forKey: .history)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(date, forKey: .date)
        try c.encodeDecimal(total, forKey: .total)
        try c.encode(isComplete, forKey: .isComplete)
        try c.encodeIfPresent(sinceLastCheckIn, forKey: .sinceLastCheckIn)
        try c.encodeIfPresent(thisYear, forKey: .thisYear)
        try c.encode(history, forKey: .history)
    }
}

extension NetWorthChange: Codable {
    enum CodingKeys: String, CodingKey {
        case from, to, start, markets, newMoney, other, end
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        from = try c.decode(CalendarDate.self, forKey: .from)
        to = try c.decode(CalendarDate.self, forKey: .to)
        start = try c.decodeDecimal(forKey: .start)
        markets = try c.decodeDecimal(forKey: .markets)
        newMoney = try c.decodeDecimal(forKey: .newMoney)
        other = try c.decodeDecimal(forKey: .other)
        end = try c.decodeDecimal(forKey: .end)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(from, forKey: .from)
        try c.encode(to, forKey: .to)
        try c.encodeDecimal(start, forKey: .start)
        try c.encodeDecimal(markets, forKey: .markets)
        try c.encodeDecimal(newMoney, forKey: .newMoney)
        try c.encodeDecimal(other, forKey: .other)
        try c.encodeDecimal(end, forKey: .end)
    }
}

extension GlancePoint: Codable {
    enum CodingKeys: String, CodingKey {
        case date, value
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(CalendarDate.self, forKey: .date)
        value = try c.decodeDecimal(forKey: .value)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(date, forKey: .date)
        try c.encodeDecimal(value, forKey: .value)
    }
}

extension AllocationSlice: Codable {
    enum CodingKeys: String, CodingKey {
        case key, name, value, share
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        name = try c.decode(String.self, forKey: .name)
        value = try c.decodeDecimal(forKey: .value)
        share = try c.decodeIfPresent(Double.self, forKey: .share)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encode(name, forKey: .name)
        try c.encodeDecimal(value, forKey: .value)
        try c.encodeIfPresent(share, forKey: .share)
    }
}

extension RetirementAnswer: Codable {
    enum CodingKeys: String, CodingKey {
        case confidence, earliestAge, earliestDate, targetAge, sustainableSpending, readiness
        case readinessIsLowerBound, needsMoreThanSearched, canRetireNow
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        confidence = try c.decode(Double.self, forKey: .confidence)
        earliestAge = try c.decodeIfPresent(Int.self, forKey: .earliestAge)
        earliestDate = try c.decodeIfPresent(CalendarDate.self, forKey: .earliestDate)
        targetAge = try c.decodeIfPresent(Int.self, forKey: .targetAge)
        sustainableSpending = try c.decodeDecimalIfPresent(forKey: .sustainableSpending)
        readiness = try c.decodeIfPresent(Double.self, forKey: .readiness)
        readinessIsLowerBound = try c.decode(Bool.self, forKey: .readinessIsLowerBound)
        needsMoreThanSearched = try c.decode(Bool.self, forKey: .needsMoreThanSearched)
        canRetireNow = try c.decode(Bool.self, forKey: .canRetireNow)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(confidence, forKey: .confidence)
        try c.encodeIfPresent(earliestAge, forKey: .earliestAge)
        try c.encodeIfPresent(earliestDate, forKey: .earliestDate)
        try c.encodeIfPresent(targetAge, forKey: .targetAge)
        try c.encodeDecimalIfPresent(sustainableSpending, forKey: .sustainableSpending)
        try c.encodeIfPresent(readiness, forKey: .readiness)
        try c.encode(readinessIsLowerBound, forKey: .readinessIsLowerBound)
        try c.encode(needsMoreThanSearched, forKey: .needsMoreThanSearched)
        try c.encode(canRetireNow, forKey: .canRetireNow)
    }
}
