import Foundation
import Model

// JSON for the snapshot file. Decimals are strings in their shortest exact
// form, as in the library's files, never through `Double`; lists that are
// absent decode as empty, so a field added later doesn't break an older file.

extension GlanceSnapshot: Codable {
    enum CodingKeys: String, CodingKey {
        case version, currency, netWorth, allocation, retirement, checkIn, milestone
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        currency = try c.decode(CurrencyCode.self, forKey: .currency)
        netWorth = try c.decodeIfPresent(NetWorthGlance.self, forKey: .netWorth)
        allocation = try c.decodeIfPresent([AllocationSlice].self, forKey: .allocation) ?? []
        retirement = try c.decodeIfPresent(RetirementGlance.self, forKey: .retirement)
        checkIn = try c.decode(CheckInGlance.self, forKey: .checkIn)
        milestone = try c.decodeIfPresent(MilestoneGlance.self, forKey: .milestone)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(currency, forKey: .currency)
        try c.encodeIfPresent(netWorth, forKey: .netWorth)
        try c.encode(allocation, forKey: .allocation)
        try c.encodeIfPresent(retirement, forKey: .retirement)
        try c.encode(checkIn, forKey: .checkIn)
        try c.encodeIfPresent(milestone, forKey: .milestone)
    }
}

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
        isComplete = try c.decodeIfPresent(Bool.self, forKey: .isComplete) ?? true
        sinceLastCheckIn = try c.decodeIfPresent(NetWorthChange.self, forKey: .sinceLastCheckIn)
        thisYear = try c.decodeIfPresent(Double.self, forKey: .thisYear)
        history = try c.decodeIfPresent([GlancePoint].self, forKey: .history) ?? []
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
        to = try c.decodeIfPresent(CalendarDate.self, forKey: .to)
        start = try c.decodeDecimal(forKey: .start)
        markets = try c.decodeDecimal(forKey: .markets)
        newMoney = try c.decodeDecimal(forKey: .newMoney)
        other = try c.decodeDecimal(forKey: .other)
        end = try c.decodeDecimal(forKey: .end)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(from, forKey: .from)
        try c.encodeIfPresent(to, forKey: .to)
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

extension RetirementGlance: Codable {
    enum CodingKeys: String, CodingKey {
        case answer, history
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        answer = try c.decode(RetirementAnswer.self, forKey: .answer)
        history = try c.decodeIfPresent([AnswerPoint].self, forKey: .history) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(answer, forKey: .answer)
        try c.encode(history, forKey: .history)
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
        readinessIsLowerBound = try c.decodeIfPresent(Bool.self, forKey: .readinessIsLowerBound) ?? false
        needsMoreThanSearched = try c.decodeIfPresent(Bool.self, forKey: .needsMoreThanSearched) ?? false
        canRetireNow = try c.decodeIfPresent(Bool.self, forKey: .canRetireNow) ?? false
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

extension AnswerPoint: Codable {
    enum CodingKeys: String, CodingKey {
        case date, earliestAge
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(CalendarDate.self, forKey: .date)
        earliestAge = try c.decodeIfPresent(Int.self, forKey: .earliestAge)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(date, forKey: .date)
        try c.encodeIfPresent(earliestAge, forKey: .earliestAge)
    }
}

extension CheckInGlance: Codable {
    enum CodingKeys: String, CodingKey {
        case last, next
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        last = try c.decodeIfPresent(CalendarDate.self, forKey: .last)
        next = try c.decode(CalendarDate.self, forKey: .next)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(last, forKey: .last)
        try c.encode(next, forKey: .next)
    }
}
