import Model

/// What a check-in shows before it's saved (UI.md, "Check-in"): net worth on
/// its date at the prices and rates fetched for it, the change since the
/// previous check-in, and which open accounts this month's imports or typed
/// values updated. Read-only: it changes nothing in the library.
public struct CheckInSummary: Hashable, Sendable {
    public let date: CalendarDate
    /// Net worth on the date, with the check-in's prices and rates.
    public let netWorth: NetWorth
    /// The change since the previous check-in (the latest date before
    /// ``date`` with a value); `nil` for the first check-in.
    public let change: ChangeReport?
    /// The accounts open on the date with a value in the date's month, on
    /// or before the date, or for a trades account a trade; by group, then
    /// name.
    public let updated: [AccountID]
    /// The other accounts open on the date: no file imported this month
    /// covered them, so they carry their last values forward. An account
    /// that holds nothing (``Valuator/emptySince(of:on:)``) isn't listed:
    /// it has nothing to update. In the same order.
    public let notUpdated: [AccountID]

    /// The summary of a check-in on `date` in `library`, with `prices` and
    /// `fxRates` fetched for it on top.
    public init(date: CalendarDate, library: Library, prices: [PriceRecord] = [], fxRates: [FXRecord] = []) {
        var priced = library
        for price in prices { priced.upsert(price) }
        for rate in fxRates { priced.upsert(rate) }
        let valuator = Valuator(library: priced)
        self.date = date
        netWorth = valuator.netWorth(on: date)
        change = valuator.previousCheckIn(before: date).map { valuator.change(from: $0, to: date) }
        let monthStart = date.startOfMonth
        let accounts = priced.accounts.values
            .filter { $0.isOpen(on: date) }
            .sorted { ($0.group, $0.name.lowercased(), $0.id) < ($1.group, $1.name.lowercased(), $1.id) }
        var updated: [AccountID] = []
        var notUpdated: [AccountID] = []
        for account in accounts {
            if let last = valuator.latestRecordDate(of: account.id, onOrBefore: date), last >= monthStart {
                updated.append(account.id)
            } else if valuator.emptySince(of: account.id, on: date) == nil {
                notUpdated.append(account.id)
            }
        }
        self.updated = updated
        self.notUpdated = notUpdated
    }
}
