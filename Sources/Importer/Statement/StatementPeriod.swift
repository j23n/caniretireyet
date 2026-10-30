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

/// Where a statement's values go before the library's first check-in
/// (IMPORT.md, "Values"): at every month end, at every quarter end, or
/// never. Month ends from the first check-in on always get one, as do
/// every value the account has and the file's last month end.
public struct StatementCheckIns: Hashable, Sendable {
    /// Which month ends before the first check-in get a value.
    public enum Ends: String, Hashable, Sendable, CaseIterable {
        case months
        case quarters
        /// None: the lines count as one stretch, up to the account's next
        /// value or the file's last month end.
        case never
    }

    public var ends: Ends
    /// The library's first check-in; `nil` when it has none, and every
    /// month end follows ``ends``.
    public var firstCheckIn: CalendarDate?

    public init(ends: Ends, firstCheckIn: CalendarDate?) {
        self.ends = ends
        self.firstCheckIn = firstCheckIn
    }

    /// `ends` before the first check-in of `library`.
    public init(ends: Ends, before library: Library) {
        self.init(ends: ends, firstCheckIn: library.checkInDates.first)
    }

    /// Whether the end of `month` gets a value.
    public func includes(_ month: YearMonth) -> Bool {
        if let firstCheckIn, month.lastDay >= firstCheckIn { return true }
        switch ends {
        case .months: return true
        case .quarters: return month.month % 3 == 0
        case .never: return false
        }
    }
}
