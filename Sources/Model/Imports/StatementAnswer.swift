import Foundation

/// Statement layout: a class chosen for one line, remembered in the profile
/// so a later statement with the same line asks nothing again: an export
/// of the last 90 days that covers last month too, or the same file
/// imported again. A line has it when its date and amount are the same and
/// its text has the same words, ignoring case, accents and punctuation.
public struct StatementAnswer: Hashable, Sendable, KnownKeysProviding {
    public var date: CalendarDate
    /// The line's amount: money in positive, money out negative.
    public var amount: Decimal
    /// The line's text, as the file writes it.
    public var match: String
    public var statementClass: StatementClass

    public init(date: CalendarDate, amount: Decimal, match: String, statementClass: StatementClass) {
        self.date = date
        self.amount = amount
        self.match = match
        self.statementClass = statementClass
    }
}

extension StatementAnswer: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case date, amount, match
        case statementClass = "class"
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(CalendarDate.self, forKey: .date)
        amount = try c.decodeDecimal(forKey: .amount)
        match = try c.decode(String.self, forKey: .match)
        statementClass = try c.decode(StatementClass.self, forKey: .statementClass)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(date, forKey: .date)
        try c.encodeDecimal(amount, forKey: .amount)
        try c.encode(match, forKey: .match)
        try c.encode(statementClass, forKey: .statementClass)
    }
}
