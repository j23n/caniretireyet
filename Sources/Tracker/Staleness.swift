import Model

/// An account whose latest valuation is too old (FILE_FORMAT.md, "Staleness").
public struct StaleAccount: Hashable, Sendable {
    public let account: AccountID
    /// The date of the latest valuation on or before the date checked (or,
    /// for a trades account, of its latest valuation or trade); `nil` if the
    /// account has never been valued.
    public let lastValuation: CalendarDate?
    /// Days from the latest valuation to the date checked; `nil` if never valued.
    public let age: Int?
}

extension Valuator {
    /// How old, in days, an account's latest valuation may be before the
    /// account is stale.
    public static let defaultStalenessThreshold = 45

    /// Whether `account` is stale on `date`: open, and its latest valuation
    /// (or, for a trades account, its latest valuation or trade) is more
    /// than `threshold` days old, or it has none. `nil` if the account is
    /// unknown or not open on the date.
    public func staleness(of account: AccountID, on date: CalendarDate,
                          threshold: Int = defaultStalenessThreshold) -> StaleAccount? {
        guard let found = accounts[account], found.isOpen(on: date) else { return nil }
        let last = latestRecordDate(of: account, onOrBefore: date)
        let age = last.map { $0.days(to: date) }
        guard age.map({ $0 > threshold }) ?? true else { return nil }
        return StaleAccount(account: account, lastValuation: last, age: age)
    }

    /// The accounts open on `date` whose latest valuation is more than
    /// `threshold` days old, or that have none; never-valued first, then
    /// oldest first. Accounts not in `scope` are left out; `nil` covers every
    /// account.
    public func staleAccounts(on date: CalendarDate, threshold: Int = defaultStalenessThreshold,
                              in scope: NetWorthScope? = nil) -> [StaleAccount] {
        accounts.values
            .filter { scope?.includes($0) ?? true }
            .compactMap { staleness(of: $0.id, on: date, threshold: threshold) }
            .sorted { lhs, rhs in
                switch (lhs.lastValuation, rhs.lastValuation) {
                case (nil, nil): lhs.account < rhs.account
                case (nil, _): true
                case (_, nil): false
                case (let left?, let right?): (left, lhs.account) < (right, rhs.account)
                }
            }
    }
}
