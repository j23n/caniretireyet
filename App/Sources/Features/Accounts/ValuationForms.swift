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

    /// The account's row; `nil` when the account isn't open on the date.
    var row: CheckInRow? { draft[account] }

    /// Changes the account's row.
    mutating func edit(_ body: (inout CheckInRow) -> Void) {
        guard var row = draft[account] else { return }
        body(&row)
        draft[account] = row
    }

    /// Moves the valuation to another date, keeping what was entered.
    mutating func changeDate(to date: CalendarDate, library: Library) {
        draft.changeDate(to: date, library: library)
    }

    /// The row valued, with its default flow and positions.
    func review(in library: Library) -> CheckInRowReview? {
        draft.review(in: library).row(for: account)
    }

    /// The valuation to save. A row left as it was is saved as unchanged
    /// (the same values, no new money), so the account is up to date.
    func valuation(in library: Library) -> Valuation? {
        var draft = self.draft
        if var row = draft[account], row.state == .notReviewed || row.state == .skipped {
            row.markUnchanged()
            draft[account] = row
        }
        return draft.records(in: library).valuations.first { $0.account == account }
    }
}

/// What was typed in the *Update value* sheet. Only fields that were
/// edited are kept, so the others keep following the account's previous
/// values (also after the date changes). The labelled subscripts give a
/// field's text with its pre-filled value, for `$input[balance: …]`
/// bindings.
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

    subscript(flow prefilled: String) -> String {
        get { flow ?? prefilled }
        set { flow = newValue }
    }

    subscript(note prefilled: String) -> String {
        get { note ?? prefilled }
        set { note = newValue }
    }

    /// Whether anything was typed.
    var isEdited: Bool {
        balance != nil || cash != nil || !quantities.isEmpty || !paid.isEmpty || flow != nil || note != nil
            || !added.isEmpty
    }

    /// Typed amounts that can't be read.
    func problems(locale: Locale = .current) -> [String] {
        var problems: [String] = []
        func check(_ text: String?, _ what: String) {
            guard let trimmed = text?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else { return }
            if AmountInput.decimal(from: trimmed, locale: locale) == nil { problems.append("The \(what) can't be read.") }
        }
        check(balance, "balance")
        check(cash, "cash")
        for text in quantities.values { check(text, "quantity") }
        for text in paid.values { check(text, "amount paid") }
        check(flow, "new money")
        return problems
    }

    /// `base` with what was typed. A positive balance typed for a debt
    /// (`isLiability`) is recorded as negative.
    func applied(to base: AccountValuationDraft, isLiability: Bool,
                 locale: Locale = .current) -> AccountValuationDraft {
        func number(_ text: String) -> Decimal? {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : AmountInput.decimal(from: trimmed, locale: locale)
        }
        var draft = base
        draft.edit { row in
            for instrument in added where row.position(for: instrument) == nil {
                row.setQuantity(0, of: instrument)
            }
            if let balance {
                var amount = number(balance)
                if isLiability, let value = amount, value > 0 { amount = -value }
                row.setBalance(amount)
            }
            if let cash { row.setCash(number(cash)) }
            for (instrument, text) in quantities.sorted(by: { $0.key < $1.key }) {
                if let quantity = number(text) { row.setQuantity(quantity, of: instrument) }
            }
            for (instrument, text) in paid.sorted(by: { $0.key < $1.key }) {
                row.setPaid(number(text), for: instrument)
            }
            if let flow {
                if flow.trimmingCharacters(in: .whitespaces).isEmpty {
                    row.resetFlow()
                } else if let amount = number(flow) {
                    row.setFlow(amount)
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
struct ValuationForm: Hashable, Sendable {
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
    var balance: String
    var cash: String
    var positions: [PositionField]
    /// Empty means unknown.
    var flow: String
    var note: String

    init(_ valuation: Valuation, holdsPositions: Bool, locale: Locale = .current) {
        original = valuation
        date = valuation.date
        isBalance = valuation.isBalance || (!valuation.isHoldings && !holdsPositions)
        balance = valuation.balance.map { AmountInput.text(for: $0, locale: locale) } ?? ""
        cash = valuation.cash.map { AmountInput.text(for: $0, locale: locale) } ?? ""
        positions = valuation.positions.map { position in
            PositionField(instrument: position.instrument,
                          quantity: AmountInput.text(for: position.quantity, locale: locale),
                          cost: position.costBasis.map { AmountInput.text(for: $0, locale: locale) } ?? "")
        }
        flow = valuation.flow.map { AmountInput.text(for: $0, locale: locale) } ?? ""
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

    /// Removes the position in `instrument`.
    mutating func removePosition(_ instrument: InstrumentID) {
        positions.removeAll { $0.instrument == instrument }
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
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if required { problems.append("Enter the \(what).") }
            } else if AmountInput.decimal(from: trimmed, locale: locale) == nil {
                problems.append("The \(what) can't be read.")
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
        return problems
    }

    /// The edited valuation, or `nil` while something can't be read. Its
    /// source becomes `manual` when a value or the date changed.
    func valuation(locale: Locale = .current) -> Valuation? {
        guard problems(locale: locale).isEmpty else { return nil }
        func number(_ text: String) -> Decimal? {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : AmountInput.decimal(from: trimmed, locale: locale)
        }
        var valuation = Valuation(account: original.account, date: date)
        if isBalance {
            valuation.balance = number(balance)
        } else {
            valuation.cash = number(cash)
            valuation.positions = positions.compactMap { field in
                guard let quantity = number(field.quantity), quantity != 0 else { return nil }
                return Position(instrument: field.instrument, quantity: quantity, costBasis: number(field.cost))
            }
        }
        valuation.flow = number(flow)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        valuation.note = trimmedNote.isEmpty ? nil : trimmedNote
        var unchanged = original
        unchanged.note = valuation.note
        unchanged.source = nil
        valuation.source = valuation == unchanged ? original.source : .manual
        return valuation
    }
}
