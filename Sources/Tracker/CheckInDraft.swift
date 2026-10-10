import Foundation
import Model

/// Where an account stands in a check-in (UI.md, "Check-in").
public enum CheckInRowState: String, Hashable, Sendable, Codable {
    /// Not looked at yet. Writes nothing unless marked unchanged.
    case notReviewed
    /// A new value was entered.
    case updated
    /// Confirmed the same as last time. Still writes a valuation (flow 0),
    /// so the account isn't stale.
    ///
    /// For an account that records trades it means as its trades say (see
    /// ``CheckInRow/followsTrades``): the cash they give and the new money
    /// they record. Such a row starts so, since there's nothing to type.
    case unchanged
    /// Left out: no valuation is written, and the account will show as stale.
    case skipped
}

/// One position in a check-in row.
public struct CheckInPosition: Hashable, Sendable, Identifiable {
    public let instrument: InstrumentID
    /// The quantity in the previous valuation; zero for a new position.
    public let previousQuantity: Decimal
    /// The cost basis in the previous valuation, if recorded.
    public let previousCostBasis: Decimal?
    public internal(set) var quantity: Decimal
    /// What was paid for the added quantity, in the account's currency. Used
    /// only when the quantity went up; it becomes new money and is added to
    /// the cost basis.
    public internal(set) var paid: Decimal?
    /// A cost basis entered directly (or kept from a valuation already saved
    /// on the date). It overrides the computed one until the quantity or the
    /// amount paid is edited.
    public internal(set) var enteredCostBasis: Decimal?

    public var id: InstrumentID { instrument }

    /// `quantity − previousQuantity`.
    public var quantityChange: Decimal { quantity - previousQuantity }

    /// Whether the quantity went up, so the "paid" field applies.
    public var isIncrease: Bool { quantity > previousQuantity }

    init(instrument: InstrumentID, previous: Position?, quantity: Decimal, paid: Decimal? = nil,
         enteredCostBasis: Decimal? = nil) {
        self.instrument = instrument
        self.previousQuantity = previous?.quantity ?? 0
        self.previousCostBasis = previous?.costBasis
        self.quantity = quantity
        self.paid = paid
        self.enteredCostBasis = enteredCostBasis
    }
}

/// One account in a check-in: its values as entered, and what they are
/// compared with. Edits go through the mutating methods, which keep the
/// row's state in step.
public struct CheckInRow: Hashable, Sendable, Identifiable {
    public let account: AccountID
    public private(set) var state: CheckInRowState
    /// Whether the new valuation records a balance, or cash and positions.
    public private(set) var mode: ValuationMode
    /// The account's latest valuation before the check-in date: what
    /// "unchanged" restores, and what flows and warnings compare with.
    public let previous: Valuation?
    /// The valuation saved in the library on the check-in date when the row
    /// was filled in or last refreshed, if any: what the row started from.
    public internal(set) var existing: Valuation?
    /// A valuation saved on the check-in date since the row was filled in
    /// (e.g. on another device) that differs from what the row would write.
    /// Until it's settled with ``CheckInDraft/resolveConflict(of:keepingSaved:in:)``
    /// the row writes nothing, so the saved valuation isn't overwritten.
    public internal(set) var conflict: Valuation?
    public private(set) var balance: Decimal?
    public private(set) var cash: Decimal?
    public private(set) var positions: [CheckInPosition]
    /// Whether the flow was entered by hand (or kept as saved on the date);
    /// otherwise it's the default for the account kind.
    public private(set) var isFlowEdited: Bool
    /// The flow entered by hand, in the account's currency; `nil` means unknown.
    public private(set) var enteredFlow: Decimal?
    /// The money that came in since the previous valuation, in the account's
    /// currency, for an account that records it (PROGRESS.md, "Money in and
    /// out"); `nil` means not recorded.
    public private(set) var moneyIn: Decimal?
    /// The money that went out, typed by hand (or kept as saved on the
    /// date); `nil` works it out from ``moneyIn`` and the flow
    /// (``CheckInDraft/defaultMoneyOut(moneyIn:flow:)``).
    public private(set) var enteredMoneyOut: Decimal?
    /// The valuation's note. Editing it doesn't change the row's state.
    public var note: String?
    /// Where the values came from, kept from a valuation already saved on
    /// the date until the row is edited.
    public private(set) var source: DataSource?
    /// Whether a value was entered in the row since it was filled in. A row
    /// pre-filled from a valuation already saved on the date is `updated`
    /// without being edited.
    public private(set) var isEdited: Bool
    /// Whether the flow kept from `existing` goes back to the default once a
    /// value is edited: it was the default for the saved values, so it was
    /// worked out rather than typed.
    var resetsFlowOnEdit: Bool
    /// Whether the account opens after the check-in's date, e.g. one added
    /// in the app today while last year is filled in. Such a row is
    /// optional: it's never counted as missing, *mark rest unchanged* leaves
    /// it alone, and left empty it changes nothing. Saving a value for it
    /// moves the account's opening date back to the check-in's date.
    public private(set) var opensLater: Bool
    /// Whether the account's holdings come from its trades (``Model/ValuationMode/trades``).
    /// Such a row records the account's cash (``mode`` is `.trades`); its
    /// positions, if any are entered, are a reconciliation check against
    /// ``derived`` (e.g. from a broker statement), not its holdings.
    public private(set) var isTrades: Bool
    /// For a trades account: what its trades give on the check-in date,
    /// counting from the previous valuation (the cash rule): the cash, and
    /// the positions with their average cost. `nil` for other accounts, and
    /// for a trades account with nothing recorded before the date.
    public internal(set) var derived: Valuation?
    /// For a trades account: whether it holds cash of its own
    /// (``Valuator/holdsCash(_:)``): a trade settled in its cash, a deposit
    /// or withdrawal, or a valuation that recorded cash. One whose trades
    /// were all paid from outside it (coins or crypto bought from a bank
    /// account) has no cash to show (``showsCash``). `true` for other accounts.
    public internal(set) var holdsCash: Bool

    public var id: AccountID { account }

    /// A row pre-filled from `existing` (a valuation already saved on the
    /// check-in date, making the row `updated`) or else from `previous`.
    /// `date` is the check-in's, and `valuator` tells whether the saved
    /// flow was the default one.
    ///
    /// A trades account's row needs nothing typed: its value is its trades
    /// at the check-in's prices. So, open on the date and with something
    /// recorded before it (``derived``), it starts as its trades say
    /// (``followsTrades``), as if marked unchanged.
    init(account: Account, date: CalendarDate, previous: Valuation?, existing: Valuation?,
         valuator: inout LazyValuator) {
        self.account = account.id
        self.previous = previous
        opensLater = account.opened > date
        self.existing = existing
        conflict = nil
        isTrades = account.recordsTrades
        let derived = isTrades ? valuator.valuator.derivedSnapshot(of: account, on: date, previous: previous) : nil
        self.derived = derived
        holdsCash = isTrades ? valuator.valuator.holdsCash(account.id) : true
        isFlowEdited = existing?.flow != nil
        enteredFlow = existing?.flow
        moneyIn = existing?.moneyIn
        enteredMoneyOut = existing?.moneyOut
        note = existing?.note
        source = existing?.source
        isEdited = false
        resetsFlowOnEdit = false
        if isTrades {
            // The cash typed on the date, else what the trades give; positions only as entered.
            mode = .trades
            if existing != nil {
                state = .updated
            } else {
                state = derived != nil && !opensLater ? .unchanged : .notReviewed
            }
            balance = nil
            cash = existing?.cash ?? derived?.cash
            positions = (existing?.positions ?? []).map { position in
                CheckInPosition(instrument: position.instrument, previous: derived?.position(for: position.instrument),
                                quantity: position.quantity, enteredCostBasis: position.costBasis)
            }
        } else {
            let filled = existing ?? previous
            let mode = Self.mode(of: filled) ?? account.valuationMode
            self.mode = mode
            state = existing == nil ? .notReviewed : .updated
            balance = mode == .balance ? filled?.balance : nil
            cash = mode == .holdings ? filled?.cash : nil
            positions = []
            if mode == .holdings {
                for position in filled?.positions ?? [] {
                    let before = previous?.position(for: position.instrument)
                    positions.append(CheckInPosition(
                        instrument: position.instrument, previous: before, quantity: position.quantity,
                        paid: existing == nil ? nil : Self.paid(for: position, previous: before),
                        enteredCostBasis: existing == nil ? nil : position.costBasis))
                }
                for position in previous?.positions ?? [] where self.position(for: position.instrument) == nil {
                    positions.append(CheckInPosition(instrument: position.instrument, previous: position, quantity: 0))
                }
            }
        }
        // A trades row's positions have nothing paid, and its default flow doesn't use it.
        if let existing, let flow = existing.flow {
            resetsFlowOnEdit = valuator.valuator.defaultFlow(for: existing, previous: previous, paid: paid) == flow
        }
    }

    /// What a saved valuation paid for a position's added quantity, from its
    /// cost basis and the previous one (what the check-in recorded as
    /// "paid"). `nil` unless the quantity went up and the costs are known.
    static func paid(for position: Position, previous: Position?) -> Decimal? {
        let before = previous?.quantity ?? 0
        guard position.quantity > before, let cost = position.costBasis else { return nil }
        if before <= 0 { return cost }
        return previous?.costBasis.map { cost - $0 }
    }

    /// What a saved `valuation` paid, by instrument, for the positions whose
    /// quantity went up since `previous` (see ``paid(for:previous:)``).
    static func paid(in valuation: Valuation, since previous: Valuation?) -> [InstrumentID: Decimal] {
        var paid: [InstrumentID: Decimal] = [:]
        for position in valuation.positions {
            if let amount = Self.paid(for: position, previous: previous?.position(for: position.instrument)) {
                paid[position.instrument] = amount
            }
        }
        return paid
    }

    /// Whether the row holds something decided in this check-in: a value
    /// entered, or the choice to mark it unchanged or skip it. A row that is
    /// only pre-filled (not reviewed yet, or from a valuation already saved
    /// on the date) has none.
    public var hasUserInput: Bool {
        switch state {
        case .notReviewed: false
        case .updated: isEdited
        // A trades account's row starts as its trades say: nothing was decided.
        case .unchanged: !followsTrades
        case .skipped: true
        }
    }

    /// For a trades account: whether the row is as its trades say (it's
    /// ``CheckInRowState/unchanged``, which it starts as): it writes the
    /// cash they give and the new money they record (docs/TRADES.md,
    /// "Check-ins"). The check-in counts it as done, "from trades".
    public var followsTrades: Bool {
        isTrades && state == .unchanged
    }

    /// For a trades account: whether a cash other than the trades' was
    /// entered, e.g. from a broker statement to compare. It anchors the
    /// cash, and the difference counts as money added or taken out that no
    /// trade records (a residual, docs/TRADES.md "Flows").
    public var hasStatementCash: Bool {
        isTrades && mode == .trades && cash != nil && cash != derived?.cash
    }

    /// Whether the row shows the account's cash: a holdings row always; a
    /// trades row when the account holds cash (``holdsCash``), when a cash
    /// from a statement was entered (``hasStatementCash``), or when nothing
    /// is recorded yet to work it out from (``derived`` is `nil`). An
    /// account whose trades were all paid from outside it shows none.
    public var showsCash: Bool {
        guard isTrades else { return mode == .holdings }
        return holdsCash || hasStatementCash || derived == nil
    }

    /// Whether the row counts in the check-in's progress ("7 of 9
    /// reviewed"): every account open on the date, and an account that
    /// opens later once something was decided for it.
    public var countsInProgress: Bool {
        !opensLater || state != .notReviewed
    }

    /// Whether "unchanged" means something for the row: there's a previous
    /// value to keep. A new account has none, so it can only be entered or
    /// skipped.
    public var canMarkUnchanged: Bool {
        isTrades ? derived != nil : Self.mode(of: previous) != nil
    }

    /// Whether the note was typed in this check-in, rather than kept from
    /// the valuation saved on the date.
    var hasTypedNote: Bool {
        note != existing?.note
    }

    /// The row's position in `instrument`, if any.
    public func position(for instrument: InstrumentID) -> CheckInPosition? {
        positions.first { $0.instrument == instrument }
    }

    /// What was paid, by instrument, for positions whose quantity went up.
    public var paid: [InstrumentID: Decimal] {
        Dictionary(positions.compactMap { position in position.paid.flatMap { position.isIncrease ? (position.instrument, $0) : nil } },
                   uniquingKeysWith: { _, last in last })
    }

    // MARK: Editing

    /// Records a balance (the row becomes a balance valuation).
    public mutating func setBalance(_ amount: Decimal?) {
        mode = .balance
        balance = amount
        cash = nil
        touch()
    }

    /// Records the cash held alongside positions.
    public mutating func setCash(_ amount: Decimal?) {
        switchToHoldings()
        cash = amount
        touch()
    }

    /// Sets a position's quantity, adding the position if it's new. Clears a
    /// cost basis entered by hand, and the amount paid if the quantity no
    /// longer went up.
    public mutating func setQuantity(_ quantity: Decimal, of instrument: InstrumentID) {
        switchToHoldings()
        if let index = positions.firstIndex(where: { $0.instrument == instrument }) {
            positions[index].quantity = quantity
            positions[index].enteredCostBasis = nil
            if !positions[index].isIncrease { positions[index].paid = nil }
        } else {
            let before = (isTrades ? derived : previous)?.position(for: instrument)
            positions.append(CheckInPosition(instrument: instrument, previous: before, quantity: quantity))
        }
        touch()
    }

    /// Records what was paid for the added quantity of a position, in the
    /// account's currency (`nil` clears it). Ignored unless the quantity went up.
    public mutating func setPaid(_ amount: Decimal?, for instrument: InstrumentID) {
        guard let index = positions.firstIndex(where: { $0.instrument == instrument }) else { return }
        positions[index].paid = amount
        positions[index].enteredCostBasis = nil
        touch()
    }

    /// Sets a position's cost basis directly, overriding the computed one
    /// (`nil` goes back to computing it).
    public mutating func setCostBasis(_ amount: Decimal?, for instrument: InstrumentID) {
        guard let index = positions.firstIndex(where: { $0.instrument == instrument }) else { return }
        positions[index].enteredCostBasis = amount
        touch()
    }

    /// Removes a position: a position held before goes to zero (sold), a
    /// new one is dropped. In a trades account's row, where positions are
    /// quantities from a statement to compare with the trades, it's
    /// dropped: the statement no longer lists it.
    public mutating func removePosition(_ instrument: InstrumentID) {
        guard let index = positions.firstIndex(where: { $0.instrument == instrument }) else { return }
        if positions[index].previousQuantity != 0 && !isTrades {
            positions[index].quantity = 0
            positions[index].paid = nil
            positions[index].enteredCostBasis = nil
        } else {
            positions.remove(at: index)
        }
        touch()
    }

    /// For a trades account: enters what its trades hold on the date (``derived``)
    /// as quantities from a statement, to correct where the statement
    /// differs; they're written as a reconciliation check (docs/TRADES.md).
    /// Returns `false`, changing nothing, for another row or when
    /// quantities were entered already.
    @discardableResult
    public mutating func enterStatementQuantities() -> Bool {
        guard isTrades, positions.isEmpty else { return false }
        switchToHoldings()
        positions = (derived?.positions ?? []).filter { $0.quantity != 0 }.map { position in
            CheckInPosition(instrument: position.instrument, previous: position, quantity: position.quantity)
        }
        touch()
        return true
    }

    /// For a trades account: drops the quantities entered from a statement,
    /// so nothing is compared.
    public mutating func removeStatementQuantities() {
        guard isTrades, !positions.isEmpty else { return }
        positions = []
        touch()
    }

    /// Enters the flow by hand, in the account's currency; `nil` means unknown.
    public mutating func setFlow(_ amount: Decimal?) {
        touch()
        isFlowEdited = true
        enteredFlow = amount
    }

    /// Records the money that came in, in the account's currency; `nil`
    /// stops recording money in and out for this valuation.
    public mutating func setMoneyIn(_ amount: Decimal?) {
        touch()
        moneyIn = amount
    }

    /// Records the money that went out, in the account's currency; `nil`
    /// goes back to working it out from the money in and the flow.
    public mutating func setMoneyOut(_ amount: Decimal?) {
        touch()
        enteredMoneyOut = amount
    }

    /// Goes back to the default flow for the account's kind.
    public mutating func resetFlow() {
        isFlowEdited = false
        enteredFlow = nil
        resetsFlowOnEdit = false
        if state == .updated { isEdited = true }
    }

    /// Confirms the account is the same as in the previous valuation:
    /// restores its values, with flow 0. Does nothing, and returns `false`,
    /// when there's no previous value to keep (see ``canMarkUnchanged``).
    ///
    /// For a trades account, "unchanged" means as its trades say
    /// (``followsTrades``, which its row starts as): the cash they give
    /// (``derived``), no cash from a statement and no positions entered.
    /// Its flow is still the default, which counts the deposits and
    /// withdrawals recorded since the previous valuation.
    @discardableResult
    public mutating func markUnchanged() -> Bool {
        if isTrades {
            guard let derived else { return false }
            mode = .trades
            balance = nil
            cash = derived.cash
            positions = []
        } else {
            guard let previous, let mode = Self.mode(of: previous) else { return false }
            self.mode = mode
            balance = mode == .balance ? previous.balance : nil
            cash = mode == .holdings ? previous.cash : nil
            positions = mode == .holdings
                ? previous.positions.map { CheckInPosition(instrument: $0.instrument, previous: $0, quantity: $0.quantity) }
                : []
        }
        isFlowEdited = false
        enteredFlow = nil
        resetsFlowOnEdit = false
        moneyIn = nil
        enteredMoneyOut = nil
        source = nil
        state = .unchanged
        return true
    }

    /// Leaves the account out of this check-in. A conflict no longer
    /// matters: nothing is written, so the saved valuation stays.
    public mutating func skip() {
        state = .skipped
        if let conflict {
            existing = conflict
            self.conflict = nil
        }
    }

    /// Takes over what was entered in `other`, a row for the same account
    /// from a draft for another date or from before the library changed. A
    /// row that was only pre-filled has nothing to take over but a typed note.
    mutating func adoptEdits(from other: CheckInRow) {
        guard other.hasUserInput else {
            if other.hasTypedNote { note = other.note }
            return
        }
        switch other.state {
        case .notReviewed: return
        case .skipped: skip()
        case .unchanged: markUnchanged()
        case .updated:
            if other.mode == .balance {
                setBalance(other.balance)
            } else {
                setCash(other.cash)
                for position in other.positions {
                    setQuantity(position.quantity, of: position.instrument)
                    if let paid = position.paid { setPaid(paid, for: position.instrument) }
                    if let cost = position.enteredCostBasis { setCostBasis(cost, for: position.instrument) }
                }
            }
            if other.isFlowEdited { setFlow(other.enteredFlow) }
            if other.moneyIn != nil { setMoneyIn(other.moneyIn) }
            if other.enteredMoneyOut != nil { setMoneyOut(other.enteredMoneyOut) }
        }
        note = other.note
    }

    /// Back from a balance to cash and positions (or, for a trades account, cash).
    private mutating func switchToHoldings() {
        let holdings: ValuationMode = isTrades ? .trades : .holdings
        guard mode != holdings else { return }
        mode = holdings
        balance = nil
    }

    /// A value was entered: the row is updated, and a flow that was only the
    /// saved default follows the new values.
    private mutating func touch() {
        state = .updated
        source = nil
        isEdited = true
        if resetsFlowOnEdit {
            resetsFlowOnEdit = false
            isFlowEdited = false
            enteredFlow = nil
        }
    }

    static func mode(of valuation: Valuation?) -> ValuationMode? {
        guard let valuation else { return nil }
        if valuation.isBalance { return .balance }
        if valuation.isHoldings { return .holdings }
        return nil
    }
}

/// A check-in in progress (UI.md, "Check-in"): one row per account open on
/// its date, plus a row for each account that opens after it (see
/// ``CheckInRow/opensLater``), and the prices and FX rates fetched or typed
/// in for it.
///
/// Pure data with no UI dependencies, and `Codable`, so the app can keep an
/// unfinished check-in on the device. Nothing is written to the library
/// until ``apply(to:)`` (or ``records(in:)``) at save time.
public struct CheckInDraft: Hashable, Sendable, Codable {
    /// The date the new valuations carry.
    public private(set) var date: CalendarDate
    /// One row per account not closed before the date (open on it, or
    /// opening later), grouped (Cash, Investments, …) and sorted by name.
    public internal(set) var rows: [CheckInRow]
    /// Prices for this check-in, written to the library with it.
    public private(set) var prices: [PriceRecord]
    /// FX rates for this check-in, written to the library with it.
    public private(set) var fxRates: [FXRecord]

    /// Starts a check-in for `date`, pre-filling each open account from its
    /// latest valuation before the date: balance, or cash and positions. An
    /// account that already has a valuation on the date starts from that one,
    /// as `updated`.
    ///
    /// Accounts that open after the date get a row too, marked
    /// ``CheckInRow/opensLater``: an account added in the app opens on the
    /// day it's added, and a past check-in is one way to fill in its history.
    public init(date: CalendarDate, library: Library) {
        self.date = date
        prices = []
        fxRates = []
        var valuator = LazyValuator(library: library)
        rows = Self.accounts(for: date, in: library).map { account in
            let valuations = library.valuations(for: account.id)
            return CheckInRow(account: account, date: date, previous: valuations.last { $0.date < date },
                              existing: valuations.last { $0.date == date }, valuator: &valuator)
        }
    }

    /// The accounts a check-in on `date` lists, in row order (by group, then
    /// by name): every account not closed before the date, i.e. open on it
    /// or opening later.
    static func accounts(for date: CalendarDate, in library: Library) -> [Account] {
        library.accounts.values
            .filter { account in account.closed.map { date <= $0 } ?? true }
            .sorted { ($0.group, $0.name.lowercased(), $0.id) < ($1.group, $1.name.lowercased(), $1.id) }
    }

    /// The date to suggest for a new check-in on `today`: the end of the
    /// previous month during the first 7 days of a month, unless that month
    /// end already has a check-in; otherwise today.
    public static func suggestedDate(today: CalendarDate, lastCheckIn: CalendarDate? = nil) -> CalendarDate {
        let monthEnd = today.startOfMonth.adding(days: -1)
        guard today.day <= 7, lastCheckIn.map({ $0 < monthEnd }) ?? true else { return today }
        return monthEnd
    }

    /// The row for `account`. Setting it replaces the row with the same
    /// account; rows can't be added or removed this way.
    public subscript(account: AccountID) -> CheckInRow? {
        get { rows.first { $0.account == account } }
        set {
            guard let newValue, newValue.account == account,
                  let index = rows.firstIndex(where: { $0.account == account })
            else { return }
            rows[index] = newValue
        }
    }

    /// Marks every row not reviewed yet as unchanged. Rows with nothing to
    /// keep (a new account without an earlier value) are skipped instead of
    /// getting an empty valuation. Rows of accounts that open later are
    /// passed over: they write nothing unless a value is entered.
    public mutating func markRestUnchanged() {
        for index in rows.indices where rows[index].state == .notReviewed && !rows[index].opensLater {
            if !rows[index].markUnchanged() { rows[index].skip() }
        }
    }

    /// Moves the check-in to another date: rows are pre-filled again for that
    /// date and keep what was entered. Prices and FX rates are dropped, since
    /// they were for the old date.
    public mutating func changeDate(to newDate: CalendarDate, library: Library) {
        guard newDate != date else { return }
        var moved = CheckInDraft(date: newDate, library: library)
        for index in moved.rows.indices {
            if let old = self[moved.rows[index].account] { moved.rows[index].adoptEdits(from: old) }
        }
        self = moved
    }

    /// The money out to suggest when only the money in was typed: what came
    /// in minus the flow (for a current account, the change in balance),
    /// as if nothing moved between your own accounts; never negative.
    /// `nil` without money in or a flow.
    public static func defaultMoneyOut(moneyIn: Decimal?, flow: Decimal?) -> Decimal? {
        guard let moneyIn, let flow else { return nil }
        return max(0, moneyIn - flow)
    }

    // MARK: Prices and FX rates

    /// Adds a price for this check-in, replacing one for the same instrument and date.
    public mutating func setPrice(_ price: PriceRecord) {
        prices.removeAll { $0.key == price.key }
        prices.append(price)
        prices = prices.sortedByKey()
    }

    /// Removes this check-in's prices for `instrument`.
    public mutating func removePrice(for instrument: InstrumentID) {
        prices.removeAll { $0.instrument == instrument }
    }

    /// Adds an FX rate for this check-in, replacing one for the same pair and date.
    public mutating func setFXRate(_ rate: FXRecord) {
        fxRates.removeAll { $0.key == rate.key }
        fxRates.append(rate)
        fxRates = fxRates.sortedByKey()
    }

    /// Removes this check-in's FX rates between `base` and `quote`, in either direction.
    public mutating func removeFXRate(base: CurrencyCode, quote: CurrencyCode) {
        fxRates.removeAll { ($0.base, $0.quote) == (base, quote) || ($0.base, $0.quote) == (quote, base) }
    }

    /// The instruments held in the rows (or held before), whose prices the
    /// check-in needs, sorted.
    public var instruments: [InstrumentID] {
        var held = Set(rows.filter { $0.mode == .holdings }.flatMap { $0.positions.map(\.instrument) })
        // A trades account holds what its trades give.
        for row in rows where row.isTrades && row.mode != .balance {
            held.formUnion((row.derived?.positions ?? []).filter { $0.quantity != 0 }.map(\.instrument))
        }
        return held.sorted()
    }

    /// The currencies other than the base currency that the check-in needs
    /// FX rates for: the rows' account currencies and the instruments' price
    /// currencies, sorted.
    public func currencies(in library: Library) -> [CurrencyCode] {
        var codes = Set(rows.compactMap { library.accounts[$0.account]?.currency })
        codes.formUnion(instruments.compactMap { library.instruments[$0]?.currency })
        codes.remove(library.settings.baseCurrency)
        return codes.sorted()
    }

    // MARK: Progress

    /// The number of rows in `state`, leaving out accounts that open later
    /// with nothing entered (see ``CheckInRow/countsInProgress``).
    public func count(_ state: CheckInRowState) -> Int {
        rows.count { $0.state == state && $0.countsInProgress }
    }

    /// The rows the progress counts ("7 of **9** reviewed"): every account
    /// open on the date, and accounts that open later once something was
    /// entered for them.
    public var progressTotal: Int {
        rows.count(where: \.countsInProgress)
    }

    /// Rows updated, unchanged or skipped ("**7** of 9 reviewed").
    public var reviewedCount: Int {
        progressTotal - count(.notReviewed)
    }

    /// The accounts not reviewed yet, in row order. Accounts that open
    /// later are never missing, so they aren't listed.
    public var notReviewed: [AccountID] {
        rows.filter { $0.state == .notReviewed && !$0.opensLater }.map(\.account)
    }

    /// Whether every row has been reviewed, so the check-in can be saved
    /// without asking about the rest. Rows of accounts that open later
    /// needn't be.
    public var isReadyToSave: Bool {
        !rows.contains { $0.state == .notReviewed && !$0.opensLater }
    }

    /// The rows of accounts that open after the date, in row order.
    public var rowsOpeningLater: [CheckInRow] {
        rows.filter(\.opensLater)
    }

    /// Rows whose account got a different valuation on the date since the
    /// draft started (see ``CheckInRow/conflict``), in row order. They write
    /// nothing until they're settled.
    public var conflicts: [CheckInRow] {
        rows.filter { $0.conflict != nil }
    }
}

// MARK: - Codable

extension CheckInPosition: Codable {
    enum CodingKeys: String, CodingKey {
        case instrument, previousQuantity, previousCostBasis, quantity, paid, enteredCostBasis
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        instrument = try c.decode(InstrumentID.self, forKey: .instrument)
        previousQuantity = try c.decodeDecimal(forKey: .previousQuantity)
        previousCostBasis = try c.decodeDecimalIfPresent(forKey: .previousCostBasis)
        quantity = try c.decodeDecimal(forKey: .quantity)
        paid = try c.decodeDecimalIfPresent(forKey: .paid)
        enteredCostBasis = try c.decodeDecimalIfPresent(forKey: .enteredCostBasis)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(instrument, forKey: .instrument)
        try c.encodeDecimal(previousQuantity, forKey: .previousQuantity)
        try c.encodeDecimalIfPresent(previousCostBasis, forKey: .previousCostBasis)
        try c.encodeDecimal(quantity, forKey: .quantity)
        try c.encodeDecimalIfPresent(paid, forKey: .paid)
        try c.encodeDecimalIfPresent(enteredCostBasis, forKey: .enteredCostBasis)
    }
}

extension CheckInRow: Codable {
    enum CodingKeys: String, CodingKey {
        case account, state, mode, previous, existing, conflict, balance, cash, positions, isFlowEdited, enteredFlow,
             moneyIn, enteredMoneyOut, note, source, isEdited, resetsFlowOnEdit, opensLater, isTrades, derived, holdsCash
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        account = try c.decode(AccountID.self, forKey: .account)
        state = try c.decode(CheckInRowState.self, forKey: .state)
        mode = try c.decode(ValuationMode.self, forKey: .mode)
        previous = try c.decodeIfPresent(Valuation.self, forKey: .previous)
        existing = try c.decodeIfPresent(Valuation.self, forKey: .existing)
        conflict = try c.decodeIfPresent(Valuation.self, forKey: .conflict)
        balance = try c.decodeDecimalIfPresent(forKey: .balance)
        cash = try c.decodeDecimalIfPresent(forKey: .cash)
        positions = try c.decodeIfPresent([CheckInPosition].self, forKey: .positions) ?? []
        isFlowEdited = try c.decodeIfPresent(Bool.self, forKey: .isFlowEdited) ?? false
        enteredFlow = try c.decodeDecimalIfPresent(forKey: .enteredFlow)
        moneyIn = try c.decodeDecimalIfPresent(forKey: .moneyIn)
        enteredMoneyOut = try c.decodeDecimalIfPresent(forKey: .enteredMoneyOut)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        source = try c.decodeIfPresent(DataSource.self, forKey: .source)
        // A draft kept before rows recorded this: an updated row counts as edited.
        isEdited = try c.decodeIfPresent(Bool.self, forKey: .isEdited) ?? (state == .updated)
        resetsFlowOnEdit = try c.decodeIfPresent(Bool.self, forKey: .resetsFlowOnEdit) ?? false
        opensLater = try c.decodeIfPresent(Bool.self, forKey: .opensLater) ?? false
        isTrades = try c.decodeIfPresent(Bool.self, forKey: .isTrades) ?? false
        derived = try c.decodeIfPresent(Valuation.self, forKey: .derived)
        // A draft kept before rows recorded this shows the cash, as it did; rebasing finds out.
        holdsCash = try c.decodeIfPresent(Bool.self, forKey: .holdsCash) ?? true
        // A draft kept before a trades row started as its trades say: one not reviewed yet does now.
        if isTrades, state == .notReviewed, derived != nil, !opensLater, existing == nil, conflict == nil,
           positions.isEmpty, cash == derived?.cash {
            state = .unchanged
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(account, forKey: .account)
        try c.encode(state, forKey: .state)
        try c.encode(mode, forKey: .mode)
        try c.encodeIfPresent(previous, forKey: .previous)
        try c.encodeIfPresent(existing, forKey: .existing)
        try c.encodeIfPresent(conflict, forKey: .conflict)
        try c.encodeDecimalIfPresent(balance, forKey: .balance)
        try c.encodeDecimalIfPresent(cash, forKey: .cash)
        try c.encode(positions, forKey: .positions)
        try c.encode(isFlowEdited, forKey: .isFlowEdited)
        try c.encodeDecimalIfPresent(enteredFlow, forKey: .enteredFlow)
        try c.encodeDecimalIfPresent(moneyIn, forKey: .moneyIn)
        try c.encodeDecimalIfPresent(enteredMoneyOut, forKey: .enteredMoneyOut)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encodeIfPresent(source, forKey: .source)
        try c.encode(isEdited, forKey: .isEdited)
        try c.encode(resetsFlowOnEdit, forKey: .resetsFlowOnEdit)
        if opensLater { try c.encode(opensLater, forKey: .opensLater) }
        if isTrades { try c.encode(isTrades, forKey: .isTrades) }
        try c.encodeIfPresent(derived, forKey: .derived)
        if !holdsCash { try c.encode(holdsCash, forKey: .holdsCash) }
    }
}

// MARK: - A valuator built when needed

/// A `Valuator` over a library, built the first time it's needed: most rows
/// are filled in without one.
struct LazyValuator {
    let library: Library
    private var built: Valuator?

    init(library: Library) {
        self.library = library
    }

    var valuator: Valuator {
        mutating get {
            if let built { return built }
            let valuator = Valuator(library: library)
            built = valuator
            return valuator
        }
    }
}
