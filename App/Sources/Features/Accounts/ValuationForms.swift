import Foundation
import Model
import Tracker

// Recording and editing one account's valuations outside a check-in (UI.md,
// "Accounts": *Update value* is a one-account valuation; the valuations
// list is editable). Plain values, so they can be checked on Linux.

/// A new valuation of one account, made the way the check-in makes one: a
/// `CheckInDraft` limited to that account, so flows, "paid" amounts and cost
/// bases follow the same rules.
struct AccountValuationDraft: Hashable, Sendable {
    let account: AccountID
    private(set) var draft: CheckInDraft

    /// Starts from the account's latest valuation before `date`, or from the
    /// one already saved on `date`.
    init(account: AccountID, date: CalendarDate, library: Library) {
        self.account = account
        draft = CheckInDraft(date: date, library: library)
    }

    var date: CalendarDate { draft.date }

    /// The account's row; `nil` when the account closed before the date. For
    /// a date before it opened, the row `opensLater`: saving the value moves
    /// the opening date back (`Library.saveValue(_:replacing:)`).
    var row: CheckInRow? { draft[account] }

    /// Changes the account's row.
    mutating func edit(_ body: (inout CheckInRow) -> Void) {
        guard var row = draft[account] else { return }
        body(&row)
        draft[account] = row
    }

    /// The row valued, with its default flow and positions.
    func review(in library: Library) -> CheckInRowReview? {
        draft.review(in: library).row(for: account)
    }

    /// The valuation to save. A row left as it was is saved as unchanged
    /// (the same values, no new money), so the account is up to date. `nil`
    /// when the account closed before the date, or when it has no earlier
    /// value to keep and none was entered.
    func valuation(in library: Library) -> Valuation? {
        var draft = self.draft
        if var row = draft[account], row.state == .notReviewed || row.state == .skipped {
            guard row.markUnchanged() else { return nil }
            draft[account] = row
        }
        return draft.records(in: library).valuations.first { $0.account == account }
    }

    /// What must be entered before saving, if anything: an account with no
    /// earlier value to keep needs a value (a balance, or positions or cash).
    func missingValue(in library: Library) -> String? {
        guard let row, !row.canMarkUnchanged else { return nil }
        if let valuation = valuation(in: library), valuation.isBalance || valuation.isHoldings { return nil }
        return row.mode == .balance
            ? "Enter the balance: this account has no earlier value to keep."
            : "Enter the positions or the cash: this account has no earlier value to keep."
    }
}

/// What saving one value does besides writing it, in words, for *Update
/// Value* (and *Add Past Value*) and the valuation editor (UI.md, "Adding
/// history").
enum AccountValueNotes {
    /// "Saving moves the opening date from 30 Sep 2026 to 31 Mar 2024.",
    /// when `date` is before the day `account` opened; `nil` otherwise.
    static func openingMove(date: CalendarDate, account: Account, locale: Locale = .current) -> String? {
        guard date < account.opened else { return nil }
        return "Saving moves the opening date from \(AmountFormat.mediumDate(account.opened, locale: locale)) "
            + "to \(AmountFormat.mediumDate(date, locale: locale))."
    }

    /// What saving does to the new money of the account's other values
    /// (`edit` from `Library.previewSavingValue(_:replacing:)`): "Saving
    /// also works out again the new money of the value on 30 Sep 2026."
    /// for automatic amounts, "The new money of the value on 30 Sep 2026
    /// was typed in, so it stays as it is." for typed ones. `nil` when no
    /// other value is concerned.
    static func flowFollowUp(_ edit: ValueEdit, locale: Locale = .current) -> String? {
        flowFollowUp(edit.flows, locale: locale)
    }

    /// The same for the flows any edit worked out again or kept, e.g. a
    /// trade's (`TradeEdit.flows`).
    static func flowFollowUp(_ flows: FlowFollowUp, locale: Locale = .current) -> String? {
        func dates(_ valuations: [Valuation]) -> String {
            Wording.list(valuations.map { AmountFormat.mediumDate($0.date, locale: locale) })
        }
        func values(_ count: Int) -> String { count == 1 ? "value" : "values" }
        var sentences: [String] = []
        let recomputed = flows.recomputed
        if !recomputed.isEmpty {
            sentences.append("Saving also works out again the new money of the \(values(recomputed.count)) on "
                + "\(dates(recomputed)).")
        }
        let kept = flows.kept
        if !kept.isEmpty {
            sentences.append("The new money of the \(values(kept.count)) on \(dates(kept)) was typed in, "
                + "so it stays as it is.")
        }
        if let moneyInOut = moneyInOutCheck(flows, locale: locale) {
            sentences.append(moneyInOut)
        }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }

    /// "Check the money in and out of the value on 30 Sep 2026: they were
    /// for the days since another value.", for the values that record them
    /// whose value before is now on another date (`FlowFollowUp.moneyInOut`),
    /// as after saving or deleting a value; `nil` when there are none.
    static func moneyInOutCheck(_ flows: FlowFollowUp, locale: Locale = .current) -> String? {
        let valuations = flows.moneyInOut
        guard !valuations.isEmpty else { return nil }
        let dates = Wording.list(valuations.map { AmountFormat.mediumDate($0.date, locale: locale) })
        return "Check the money in and out of the \(valuations.count == 1 ? "value" : "values") on \(dates): "
            + "they were for the days since another value."
    }
}

/// What was typed in the *Update value* sheet. Only fields that were
/// edited are kept, so the others keep following the account's previous
/// values (also after the date changes). The labelled subscripts give a
/// field's text with its pre-filled value, for `$input[balance: …]`
/// bindings; ``flowText`` is the new money's, which has none.
struct AccountValuationInput: Hashable, Sendable {
    var balance: String?
    var cash: String?
    var quantities: [InstrumentID: String] = [:]
    var paid: [InstrumentID: String] = [:]
    /// `nil` or empty: the default for the account's kind.
    var flow: String?
    var note: String?
    /// Positions added to a holdings account, in order.
    var added: [InstrumentID] = []

    init() {}

    subscript(balance prefilled: String) -> String {
        get { balance ?? prefilled }
        set { balance = newValue }
    }

    subscript(cash prefilled: String) -> String {
        get { cash ?? prefilled }
        set { cash = newValue }
    }

    subscript(quantity instrument: InstrumentID, prefilled prefilled: String) -> String {
        get { quantities[instrument] ?? prefilled }
        set { quantities[instrument] = newValue }
    }

    subscript(paid instrument: InstrumentID) -> String {
        get { paid[instrument] ?? "" }
        set { paid[instrument] = newValue }
    }

    var flowText: String {
        get { flow ?? "" }
        set { flow = newValue }
    }

    subscript(note prefilled: String) -> String {
        get { note ?? prefilled }
        set { note = newValue }
    }

    /// What stops Save: typed amounts that can't be read, and a balance or
    /// quantity field that was cleared (an empty field isn't zero).
    func problems(locale: Locale = .current) -> [String] {
        var problems: [String] = []
        func check(_ text: String?, _ what: String, required: String? = nil) {
            guard let text else { return }
            switch AmountInput.parse(text, locale: locale) {
            case .empty: if let required, !problems.contains(required) { problems.append(required) }
            case .unreadable: problems.append("The \(what) can't be read.")
            case .value: break
            }
        }
        check(balance, "balance", required: "Enter the balance. To record nothing owed or held, type 0.")
        check(cash, "cash")
        for (_, text) in quantities.sorted(by: { $0.key < $1.key }) {
            check(text, "quantity", required: "Enter each position's quantity, or 0 if it was sold.")
        }
        for (_, text) in paid.sorted(by: { $0.key < $1.key }) { check(text, "amount paid") }
        check(flow, "new money")
        return problems
    }

    /// `base` with what was typed. A balance typed for a debt
    /// (`isLiability`) is what's owed and is recorded as negative, unless
    /// it starts with "+" (in credit). An empty balance or quantity isn't
    /// entered: ``problems(locale:)`` asks for it.
    func applied(to base: AccountValuationDraft, isLiability: Bool,
                 locale: Locale = .current) -> AccountValuationDraft {
        var draft = base
        draft.edit { row in
            for instrument in added where row.position(for: instrument) == nil {
                row.setQuantity(0, of: instrument)
            }
            if let balance, let amount = AmountInput.balance(from: balance, isLiability: isLiability, locale: locale) {
                row.setBalance(amount)
            }
            if let cash { row.setCash(AmountInput.decimal(from: cash, locale: locale)) }
            for (instrument, text) in quantities.sorted(by: { $0.key < $1.key }) {
                if let quantity = AmountInput.decimal(from: text, locale: locale) {
                    row.setQuantity(quantity, of: instrument)
                }
            }
            for (instrument, text) in paid.sorted(by: { $0.key < $1.key }) {
                row.setPaid(AmountInput.decimal(from: text, locale: locale), for: instrument)
            }
            if let flow {
                switch AmountInput.parse(flow, locale: locale) {
                case .empty: row.resetFlow()
                case .value(let amount): row.setFlow(amount)
                case .unreadable: break
                }
            }
            if let note {
                let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                row.note = trimmed.isEmpty ? nil : trimmed
            }
        }
        return draft
    }
}

/// The fields of a valuation already saved, while it's edited: date,
/// balance (or cash and positions), new money and note.
struct AccountValuationForm: Hashable, Sendable {
    struct PositionField: Hashable, Sendable, Identifiable {
        var instrument: InstrumentID
        var quantity: String
        /// The cost basis; empty for unknown.
        var cost: String

        var id: InstrumentID { instrument }
    }

    let original: Valuation
    var date: CalendarDate
    /// Whether it records a balance (or cash and positions).
    let isBalance: Bool
    /// Whether the account is a debt: its balance is typed as what's owed
    /// and recorded negative (``AmountInput/balance(from:isLiability:locale:)``).
    let isLiability: Bool
    var balance: String
    var cash: String
    var positions: [PositionField]
    /// Empty means unknown.
    var flow: String
    /// Whether the account's kind records money in and out (cash and
    /// savings). For other kinds the editor hides the fields, and saving
    /// keeps what the file has.
    let recordsMoneyInOut: Bool
    /// Money in and out of a cash or savings account; empty means not recorded.
    var moneyIn: String
    var moneyOut: String
    var note: String

    /// The fields of `valuation`. A trades account's (`recordsTrades`) is
    /// never a balance: it records cash, and a balance written by hand
    /// isn't used, so saving drops it (docs/TRADES.md). A debt's
    /// (`isLiability`) balance reads as typed in the check-in.
    init(_ valuation: Valuation, holdsPositions: Bool, recordsTrades: Bool = false, isLiability: Bool = false,
         recordsMoneyInOut: Bool, locale: Locale = .current) {
        original = valuation
        date = valuation.date
        isBalance = !recordsTrades && (valuation.isBalance || (!valuation.isHoldings && !holdsPositions))
        self.isLiability = isLiability
        self.recordsMoneyInOut = recordsMoneyInOut
        balance = valuation.balance.map { AmountInput.balanceText(for: $0, isLiability: isLiability, locale: locale) }
            ?? ""
        cash = valuation.cash.map { AmountInput.text(for: $0, locale: locale) } ?? ""
        positions = valuation.positions.map { position in
            PositionField(instrument: position.instrument,
                          quantity: AmountInput.text(for: position.quantity, locale: locale),
                          cost: position.costBasis.map { AmountInput.text(for: $0, locale: locale) } ?? "")
        }
        flow = valuation.flow.map { AmountInput.text(for: $0, locale: locale) } ?? ""
        moneyIn = valuation.moneyIn.map { AmountInput.text(for: $0, locale: locale) } ?? ""
        moneyOut = valuation.moneyOut.map { AmountInput.text(for: $0, locale: locale) } ?? ""
        note = valuation.note ?? ""
    }

    /// The date as a `Date` (noon, this device's time zone), for a date picker.
    var dateValue: Date {
        get { date.dateValue }
        set { date = CalendarDate(newValue, in: .current) }
    }

    /// Adds a position in `instrument`, unless it's already listed.
    mutating func addPosition(_ instrument: InstrumentID) {
        guard !positions.contains(where: { $0.instrument == instrument }) else { return }
        positions.append(PositionField(instrument: instrument, quantity: "", cost: ""))
    }

    /// The position in `instrument`, for bindings that stay valid while rows
    /// are removed (an empty position once it's gone).
    subscript(position instrument: InstrumentID) -> PositionField {
        get {
            positions.first { $0.instrument == instrument }
                ?? PositionField(instrument: instrument, quantity: "", cost: "")
        }
        set {
            guard let index = positions.firstIndex(where: { $0.instrument == instrument }) else { return }
            positions[index] = newValue
        }
    }

    /// What can't be read, in order.
    func problems(locale: Locale = .current) -> [String] {
        var problems: [String] = []
        func check(_ text: String, _ what: String, required: Bool = false) {
            switch AmountInput.parse(text, locale: locale) {
            case .empty: if required { problems.append("Enter the \(what).") }
            case .unreadable: problems.append("The \(what) can't be read.")
            case .value: break
            }
        }
        if isBalance {
            check(balance, "balance", required: true)
        } else {
            check(cash, "cash")
            for position in positions {
                check(position.quantity, "quantity", required: true)
                check(position.cost, "cost")
            }
        }
        check(flow, "new money")
        if recordsMoneyInOut {
            check(moneyIn, "money in")
            check(moneyOut, "money out")
            let moneyAmounts = [moneyIn, moneyOut].map { AmountInput.parse($0, locale: locale) }
            if (moneyAmounts[0] == .empty) != (moneyAmounts[1] == .empty) {
                problems.append("Enter both money in and out, or neither.")
            }
            if moneyAmounts.contains(where: { ($0.value ?? 0) < 0 }) {
                problems.append("Money in and out can't be negative.")
            }
        }
        return problems
    }

    /// The edited valuation, or `nil` while something can't be read. Its
    /// source becomes `manual` when a value or the date changed.
    func valuation(locale: Locale = .current) -> Valuation? {
        guard problems(locale: locale).isEmpty else { return nil }
        func number(_ text: String) -> Decimal? { AmountInput.decimal(from: text, locale: locale) }
        var valuation = Valuation(account: original.account, date: date)
        if isBalance {
            valuation.balance = AmountInput.balance(from: balance, isLiability: isLiability, locale: locale)
        } else {
            valuation.cash = number(cash)
            valuation.positions = positions.compactMap { field in
                guard let quantity = number(field.quantity), quantity != 0 else { return nil }
                return Position(instrument: field.instrument, quantity: quantity, costBasis: number(field.cost))
            }
        }
        valuation.flow = number(flow)
        valuation.moneyIn = recordsMoneyInOut ? number(moneyIn) : original.moneyIn
        valuation.moneyOut = recordsMoneyInOut ? number(moneyOut) : original.moneyOut
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        valuation.note = trimmedNote.isEmpty ? nil : trimmedNote
        var unchanged = original
        unchanged.note = valuation.note
        unchanged.source = nil
        valuation.source = valuation == unchanged ? original.source : .manual
        return valuation
    }
}
