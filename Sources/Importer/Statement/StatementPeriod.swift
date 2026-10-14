import Model

/// The days a bank statement is read as covering, first and last
/// included (``ImportPreview/statementPeriod``).
public struct StatementPeriod: Hashable, Sendable {
    public var from: CalendarDate
    public var through: CalendarDate

    public init(from: CalendarDate, through: CalendarDate) {
        self.from = from
        self.through = through
    }

    /// Whether the period covers `date`.
    public func contains(_ date: CalendarDate) -> Bool {
        date >= from && date <= through
    }
}
