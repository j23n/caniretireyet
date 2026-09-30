import Foundation
import Model

/// Where an account stands in a check-in (UI.md, "Check-in").
public enum CheckInRowState: String, Hashable, Sendable, CaseIterable, Codable {
    /// Not looked at yet. Writes nothing unless marked unchanged.
    case notReviewed
    /// A new value was entered.
    case updated
    /// Confirmed the same as last time. Still writes a valuation (flow 0),
    /// so the account isn't stale.
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

    init(instrument: InstrumentID, previous: Position?, quantity: Decimal, enteredCostBasis: Decimal? = nil) {
        self.instrument = instrument
        self.previousQuantity = previous?.quantity ?? 0
        self.previousCostBasis = previous?.costBasis
        self.quantity = quantity
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
    public private(set) var balance: Decimal?
    public private(set) var cash: Decimal?
    public private(set) var positions: [CheckInPosition]
    /// Whether the flow was entered by hand; otherwise it's the default for the account kind.
    public private(set) var isFlowEdited: Bool
    /// The flow entered by hand, in the account's currency; `nil` means unknown.
    public private(set) var enteredFlow: Decimal?
    /// The valuation's note. Editing it doesn't change the row's state.
    public var note: String?
    /// Where the values came from, kept from a valuation already saved on
    /// the date until the row is edited.
    public private(set) var source: DataSource?

    public var id: AccountID { account }

    /// A row pre-filled from `existing` (a valuation already saved on the
    /// check-in date, making the row `updated`) or else from `previous`.
    init(account: Account, previous: Valuation?, existing: Valuation?) {
        self.account = account.id
        self.previous = previous
        let filled = existing ?? previous
        let mode = Self.mode(of: filled) ?? account.valuationMode
        self.mode = mode
        state = existing == nil ? .notReviewed : .updated
        balance = mode == .balance ? filled?.balance : nil
        cash = mode == .holdings ? filled?.cash : nil
        positions = []
        isFlowEdited = existing?.flow != nil
        enteredFlow = existing?.flow
        note = existing?.note
        source = existing?.source
        if mode == .holdings {
            for position in filled?.positions ?? [] {
                positions.append(CheckInPosition(
                    instrument: position.instrument, previous: previous?.position(for: position.instrument),
                    quantity: position.quantity, enteredCostBasis: existing == nil ? nil : position.costBasis))
            }
            for position in previous?.positions ?? [] where self.position(for: position.instrument) == nil {
                positions.append(CheckInPosition(instrument: position.instrument, previous: position, quantity: 0))
            }
        }
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
            positions.append(CheckInPosition(instrument: instrument, previous: previous?.position(for: instrument),
                                             quantity: quantity))
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
    /// new one is dropped.
    public mutating func removePosition(_ instrument: InstrumentID) {
        guard let index = positions.firstIndex(where: { $0.instrument == instrument }) else { return }
        if positions[index].previousQuantity != 0 {
            positions[index].quantity = 0
            positions[index].paid = nil
            positions[index].enteredCostBasis = nil
        } else {
            positions.remove(at: index)
        }
        touch()
    }

    /// Enters the flow by hand, in the account's currency; `nil` means unknown.
    public mutating func setFlow(_ amount: Decimal?) {
        isFlowEdited = true
        enteredFlow = amount
        touch()
    }

    /// Goes back to the default flow for the account's kind.
    public mutating func resetFlow() {
        isFlowEdited = false
        enteredFlow = nil
    }

    /// Confirms the account is the same as in the previous valuation:
    /// restores its values, with flow 0.
    public mutating func markUnchanged() {
        mode = Self.mode(of: previous) ?? mode
        balance = mode == .balance ? previous?.balance : nil
        cash = mode == .holdings ? previous?.cash : nil
        positions = mode == .holdings
            ? (previous?.positions ?? []).map { CheckInPosition(instrument: $0.instrument, previous: $0, quantity: $0.quantity) }
            : []
        isFlowEdited = false
        enteredFlow = nil
        source = nil
        state = .unchanged
    }

    /// Leaves the account out of this check-in.
    public mutating func skip() {
        state = .skipped
    }

    /// Takes over what was entered in `other`, a row for the same account
    /// from a draft for another date.
    mutating func adoptEdits(from other: CheckInRow) {
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
        }
        note = other.note
    }

    private mutating func switchToHoldings() {
        guard mode != .holdings else { return }
        mode = .holdings
        balance = nil
    }

    private mutating func touch() {
        state = .updated
        source = nil
    }

    private static func mode(of valuation: Valuation?) -> ValuationMode? {
        guard let valuation else { return nil }
        if valuation.isBalance { return .balance }
        if valuation.isHoldings { return .holdings }
        return nil
    }
}

/// A check-in in progress (UI.md, "Check-in"): one row per open account,
/// plus the prices and FX rates fetched or typed in for it.
///
/// Pure data with no UI dependencies, and `Codable`, so the app can keep an
/// unfinished check-in on the device. Nothing is written to the library
/// until ``apply(to:)`` (or ``records(in:)``) at save time.
public struct CheckInDraft: Hashable, Sendable, Codable {
    /// The date the new valuations carry.
    public private(set) var date: CalendarDate
    /// One row per account open on the date, grouped (Cash, Investments, …)
    /// and sorted by name.
    public private(set) var rows: [CheckInRow]
    /// Prices for this check-in, written to the library with it.
    public private(set) var prices: [PriceRecord]
    /// FX rates for this check-in, written to the library with it.
    public private(set) var fxRates: [FXRecord]

    /// Starts a check-in for `date`, pre-filling each open account from its
    /// latest valuation before the date: balance, or cash and positions. An
    /// account that already has a valuation on the date starts from that one,
    /// as `updated`.
    public init(date: CalendarDate, library: Library) {
        self.date = date
        prices = []
        fxRates = []
        rows = library.accounts.values
            .filter { $0.isOpen(on: date) }
            .sorted { ($0.group, $0.name.lowercased(), $0.id) < ($1.group, $1.name.lowercased(), $1.id) }
            .map { account in
                let valuations = library.valuations(for: account.id)
                return CheckInRow(account: account, previous: valuations.last { $0.date < date },
                                  existing: valuations.last { $0.date == date })
            }
    }

    /// The date to suggest for a new check-in on `today`: the end of the
    /// previous month during the first `firstDays` days of a month, unless
    /// that month end already has a check-in; otherwise today.
    public static func suggestedDate(today: CalendarDate, lastCheckIn: CalendarDate? = nil,
                                     firstDays: Int = 7) -> CalendarDate {
        let monthEnd = today.startOfMonth.adding(days: -1)
        guard today.day <= firstDays, lastCheckIn.map({ $0 < monthEnd }) ?? true else { return today }
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

    /// Marks every row not reviewed yet as unchanged.
    public mutating func markRestUnchanged() {
        for index in rows.indices where rows[index].state == .notReviewed {
            rows[index].markUnchanged()
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
        Set(rows.filter { $0.mode == .holdings }.flatMap { $0.positions.map(\.instrument) }).sorted()
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

    /// The number of rows in `state`.
    public func count(_ state: CheckInRowState) -> Int {
        rows.count { $0.state == state }
    }

    /// Rows updated, unchanged or skipped ("7 of 9 reviewed").
    public var reviewedCount: Int {
        rows.count - count(.notReviewed)
    }

    /// The accounts not reviewed yet, in row order.
    public var notReviewed: [AccountID] {
        rows.filter { $0.state == .notReviewed }.map(\.account)
    }

    /// Whether every row has been reviewed, so the check-in can be saved
    /// without asking about the rest.
    public var isReadyToSave: Bool {
        !rows.contains { $0.state == .notReviewed }
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
        case account, state, mode, previous, balance, cash, positions, isFlowEdited, enteredFlow, note, source
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        account = try c.decode(AccountID.self, forKey: .account)
        state = try c.decode(CheckInRowState.self, forKey: .state)
        mode = try c.decode(ValuationMode.self, forKey: .mode)
        previous = try c.decodeIfPresent(Valuation.self, forKey: .previous)
        balance = try c.decodeDecimalIfPresent(forKey: .balance)
        cash = try c.decodeDecimalIfPresent(forKey: .cash)
        positions = try c.decodeIfPresent([CheckInPosition].self, forKey: .positions) ?? []
        isFlowEdited = try c.decodeIfPresent(Bool.self, forKey: .isFlowEdited) ?? false
        enteredFlow = try c.decodeDecimalIfPresent(forKey: .enteredFlow)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        source = try c.decodeIfPresent(DataSource.self, forKey: .source)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(account, forKey: .account)
        try c.encode(state, forKey: .state)
        try c.encode(mode, forKey: .mode)
        try c.encodeIfPresent(previous, forKey: .previous)
        try c.encodeDecimalIfPresent(balance, forKey: .balance)
        try c.encodeDecimalIfPresent(cash, forKey: .cash)
        try c.encode(positions, forKey: .positions)
        try c.encode(isFlowEdited, forKey: .isFlowEdited)
        try c.encodeDecimalIfPresent(enteredFlow, forKey: .enteredFlow)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encodeIfPresent(source, forKey: .source)
    }
}
