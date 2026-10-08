import Foundation
import Model

// Values of accounts whose holdings come from their trades (docs/TRADES.md):
// the cash rule, snapshots, and what's wrong with the trades.

extension Valuator {
    /// The ledger of an account that records trades (``Model/Account/recordsTrades``);
    /// `nil` for other accounts.
    public func ledger(for account: AccountID) -> TradeLedger? {
        ledgers[account]
    }

    // MARK: - Cash

    /// The cash of a trades account at the end of `date` (docs/TRADES.md,
    /// "Cash"): the `cash` of its latest valuation on or before the date
    /// that records cash, plus the cash effect of every trade after that
    /// valuation through the date. Without such a valuation it starts from
    /// zero. `nil` for an account that doesn't record trades.
    public func tradeCash(of account: AccountID, on date: CalendarDate) -> Decimal? {
        guard let ledger = ledgers[account] else { return nil }
        let anchor = cashAnchor(for: account, onOrBefore: date)
        return (anchor?.cash ?? 0) + ledger.cashEffect(after: anchor?.date, through: date)
    }

    /// The cash a trades account's trades give at the end of `date`
    /// counting from `anchor` (a valuation with cash, or nothing: zero
    /// before the first trade), whatever valuations come after it.
    func derivedCash(of account: AccountID, on date: CalendarDate, from anchor: Valuation?) -> Decimal {
        (anchor?.cash ?? 0) + (ledgers[account]?.cashEffect(after: anchor?.date, through: date) ?? 0)
    }

    /// The latest valuation of `account` on or before `date` that records cash.
    func cashAnchor(for account: AccountID, onOrBefore date: CalendarDate) -> Valuation? {
        let valuations = valuations(for: account)
        guard var index = valuations.lastIndex(onOrBefore: date, date: \.date) else { return nil }
        while valuations[index].cash == nil {
            guard index > 0 else { return nil }
            index -= 1
        }
        return valuations[index]
    }

    // MARK: - Snapshots

    /// What `account` holds at the end of `date`, as a valuation.
    ///
    /// - A balance or holdings account: its latest valuation on or before the date.
    /// - A trades account: its cash by the cash rule (``tradeCash(of:on:)``)
    ///   and the positions its trades leave, with their purchase cost, dated
    ///   the day of its latest valuation or trade on or before the date.
    ///
    /// `nil` when there's nothing on or before the date.
    public func snapshot(of account: AccountID, on date: CalendarDate) -> Valuation? {
        guard let found = accounts[account] else { return nil }
        return carried(found, on: date)
    }

    /// A trades account's snapshot at the end of `date`; `nil` before its
    /// first valuation and first trade.
    func tradeSnapshot(of account: Account, on date: CalendarDate) -> Valuation? {
        let ledger = ledgers[account.id]
        let lastValuation = latestValuation(for: account.id, onOrBefore: date)?.date
        let lastTrade = ledger?.entries.lastIndex(onOrBefore: date, date: \.date).map { ledger!.entries[$0].date }
        guard let last = [lastValuation, lastTrade].compactMap({ $0 }).max() else { return nil }
        return Valuation(account: account.id, date: last, cash: tradeCash(of: account.id, on: date),
                         positions: ledger?.positions(on: date) ?? [])
    }

    /// What a trades account's trades give at the end of `date`, counting
    /// its cash from `previous` (its valuation before the date), whatever
    /// is saved on the date itself: what a check-in on the date starts
    /// from. `nil` without a previous valuation or a trade on or before the date.
    func derivedSnapshot(of account: Account, on date: CalendarDate, previous: Valuation?) -> Valuation? {
        guard let ledger = ledgers[account.id] else { return nil }
        guard previous != nil || (ledger.firstDate.map { $0 <= date } ?? false) else { return nil }
        let anchor = previous?.cash != nil
            ? previous : previous.flatMap { cashAnchor(for: account.id, onOrBefore: $0.date) }
        return Valuation(account: account.id, date: date, cash: derivedCash(of: account.id, on: date, from: anchor),
                         positions: ledger.positions(on: date))
    }

    /// `valuation` of a trades account as a snapshot on its own date: its
    /// cash (by the cash rule when it has none), and the positions the
    /// account's trades leave on its date in place of any it lists (those
    /// are a reconciliation check, ``reconciliation(of:)``). A balance isn't used.
    func tradeSnapshot(for valuation: Valuation, in account: Account) -> Valuation {
        var snapshot = valuation
        snapshot.balance = nil
        if snapshot.cash == nil { snapshot.cash = tradeCash(of: account.id, on: valuation.date) }
        snapshot.positions = ledgers[account.id]?.positions(on: valuation.date) ?? []
        return snapshot
    }

    /// The FX rates missing for the cash of a trades account in
    /// `valuation`: trades counted in its cash whose cash effect needs a
    /// rate that isn't there. None when the valuation records its own cash.
    func tradeCashProblems(of account: Account, for valuation: Valuation, derived: Bool) -> [ValuationProblem] {
        guard derived, let ledger = ledgers[account.id] else { return [] }
        let anchor = cashAnchor(for: account.id, onOrBefore: valuation.date)
        guard ledger.unknownCashEffects(after: anchor?.date, through: valuation.date) > 0 else { return [] }
        var problems: [ValuationProblem] = []
        for issue in ledger.issues where issue.kind == .missingFX {
            guard let key = issue.trade, anchor.map({ key.date > $0.date }) ?? true, key.date <= valuation.date,
                  let entry = ledger.entries.first(where: { $0.trade.key == key })
            else { continue }
            let from = entry.trade.priceCurrency(instruments: instruments, accountCurrency: account.currency)
            let problem = ValuationProblem.missingFX(account: account.id, from: from, to: account.currency)
            if !problems.contains(problem) { problems.append(problem) }
        }
        return problems
    }

    // MARK: - Checks

    /// What's wrong with the trades of `account` (every account when
    /// `nil`), sorted by date (docs/TRADES.md, "Checks"):
    ///
    /// - the ledger's issues: records missing something, more sold than
    ///   held, unknown costs, missing FX rates, splits of what isn't held;
    /// - trades of accounts that don't record trades, which are left out;
    /// - trades dated outside the account's opened and closed dates;
    /// - valuations of trades accounts with a balance, which isn't used;
    /// - valuations listing positions that differ from the trades'
    ///   (``reconciliation(of:)``).
    public func tradeIssues(for account: AccountID? = nil) -> [TradeIssue] {
        var issues: [TradeIssue] = []
        let ids = account.map { [$0] } ?? accounts.keys.sorted()
        for id in ids {
            if let ledger = ledgers[id], let details = accounts[id] {
                issues += ledger.issues
                for entry in ledger.entries {
                    let trade = entry.trade
                    let outside = trade.date < details.opened ? "before the account opened (\(details.opened))"
                        : details.closed.flatMap { trade.date > $0 ? "after the account closed (\($0))" : nil }
                    guard let outside else { continue }
                    issues.append(TradeIssue(.outsideAccountDates, .warning, account: id, trade: trade.key,
                                             instrument: trade.instrument, date: trade.date,
                                             message: "\(TradeLedger.describe(trade)) is dated \(outside); it "
                                                 + "counts only from the day the account opens."))
                }
                for valuation in valuations(for: id) where valuation.balance != nil {
                    issues.append(TradeIssue(.balanceIgnored, .warning, account: id, date: valuation.date,
                                             message: "The valuation on \(valuation.date) has a balance, but the "
                                                 + "account's holdings come from its trades: record its cash "
                                                 + "instead. The balance isn't used."))
                }
                for mismatch in reconciliation(of: id) {
                    issues.append(TradeIssue(.reconciliation, .warning, account: id, instrument: mismatch.instrument,
                                             date: mismatch.date, message: mismatch.description))
                }
            }
            for trade in ignoredTrades where trade.account == id {
                let reason = accounts[id].map { "\(id) records \($0.valuationMode.rawValue), not trades" }
                    ?? "there's no account \(id)"
                issues.append(TradeIssue(.notTradesAccount, .warning, account: id, trade: trade.key,
                                         instrument: trade.instrument, date: trade.date,
                                         message: "\(TradeLedger.describe(trade)) is left out: \(reason)."))
            }
        }
        return issues.enumerated().sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }.map(\.element)
    }

    // MARK: - Reconciliation

    /// Where the valuations of a trades account that list positions (from
    /// a broker statement, say) disagree with the quantities its trades
    /// give on the same date, sorted by date, then instrument. An
    /// instrument held by the trades but not listed counts as listed at
    /// zero. Empty for other accounts.
    public func reconciliation(of account: AccountID) -> [PositionMismatch] {
        guard ledgers[account] != nil else { return [] }
        return valuations(for: account).filter { !$0.positions.isEmpty }.flatMap { reconcile($0) }
    }

    /// Where the positions `valuation` lists disagree with the quantities
    /// its account's trades give on its date, by instrument; empty when
    /// it lists none, or its account doesn't record trades.
    public func reconcile(_ valuation: Valuation) -> [PositionMismatch] {
        guard let ledger = ledgers[valuation.account], !valuation.positions.isEmpty else { return [] }
        let derived = ledger.positions(on: valuation.date)
        var listed: [InstrumentID: Decimal] = [:]
        for position in valuation.positions { listed[position.instrument] = position.quantity }
        let instruments = Set(listed.keys).union(derived.map(\.instrument)).sorted()
        return instruments.compactMap { instrument in
            let expected = derived.first { $0.instrument == instrument }?.quantity ?? 0
            let written = listed[instrument] ?? 0
            guard expected != written else { return nil }
            return PositionMismatch(account: valuation.account, date: valuation.date, instrument: instrument,
                                    listed: written, derived: expected)
        }
    }

    // MARK: - Years

    /// The trades of the accounts selected by `include` (every trades
    /// account by default) in `year`, summed in the base currency, each
    /// amount converted at the latest FX rate on or before its trade date.
    /// Amounts that can't be converted are left out and listed.
    public func tradeSummary(for year: Int, including include: (Account) -> Bool = { _ in true }) -> TradeYearSummary {
        var summary = TradeYearSummary(year: year, currency: baseCurrency)
        for (id, ledger) in ledgers.sorted(by: { $0.key < $1.key }) {
            guard let account = accounts[id], include(account) else { continue }
            for entry in ledger.entries where entry.date.year == year {
                summary.add(entry) { amount in
                    account.currency == baseCurrency
                        ? amount : fx.convert(amount, from: account.currency, to: baseCurrency, on: entry.date)
                }
            }
        }
        return summary
    }
}

/// A position a valuation of a trades account lists with a quantity other
/// than its trades give (``Valuator/reconciliation(of:)``).
public struct PositionMismatch: Hashable, Sendable, CustomStringConvertible {
    public let account: AccountID
    /// The valuation's date.
    public let date: CalendarDate
    public let instrument: InstrumentID
    /// The quantity the valuation lists (zero when it doesn't list it).
    public let listed: Decimal
    /// The quantity the trades give.
    public let derived: Decimal

    public init(account: AccountID, date: CalendarDate, instrument: InstrumentID, listed: Decimal, derived: Decimal) {
        self.account = account
        self.date = date
        self.instrument = instrument
        self.listed = listed
        self.derived = derived
    }

    /// `listed − derived`: positive when the statement shows more.
    public var difference: Decimal { listed - derived }

    public var description: String {
        "The valuation on \(date) lists \(listed.fileString) \(instrument), but the trades give "
            + "\(derived.fileString). Is a trade missing or wrong?"
    }
}
