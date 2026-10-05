import Model

/// An account whose latest valuation is too old (docs/schema/README.md, "How values are computed").
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

    // MARK: - Empty accounts

    /// The day since which `account` has held nothing, as of `date`: what
    /// it holds after its latest record on or before `date` is nothing (a
    /// zero balance, or no cash and no quantity), and so after every record
    /// before it back to that day. A record is a valuation, or for a trades
    /// account also a trade, whose holdings and cash its trades give
    /// (``snapshot(of:on:)``). Needs no prices or rates.
    ///
    /// `nil` when the account holds something on `date`, has no record by
    /// then, or is unknown. An empty account has nothing to check in: the
    /// app suggests closing it rather than marking it stale.
    public func emptySince(of account: AccountID, on date: CalendarDate) -> CalendarDate? {
        guard let found = accounts[account] else { return nil }
        var days = Set(valuations(for: account).map(\.date).filter { $0 <= date })
        if let ledger = ledgers[account] {
            days.formUnion(ledger.entries.map(\.date).filter { $0 <= date })
        }
        var since: CalendarDate?
        for day in days.sorted(by: >) {
            guard let held = carried(found, on: day), held.holdsNothing else { break }
            since = day
        }
        return since
    }
}

extension Valuation {
    /// Whether it holds nothing: a zero balance, or (without a balance) no
    /// cash and no position with a quantity.
    var holdsNothing: Bool {
        if let balance { return balance == 0 }
        return (cash ?? 0) == 0 && positions.allSatisfy { $0.quantity == 0 }
    }
}
