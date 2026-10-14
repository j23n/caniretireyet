import Foundation
import Model
import Tracker

// Recording and editing one account's valuations outside a check-in (UI.md,
// "Accounts": *Update value* is a one-account valuation; the valuations
// list is editable). Plain values, so they can be checked on Linux.

/// A new valuation of one account, made the way the check-in makes one: a
/// `CheckInDraft` limited to that account, so flows and money in and out
/// follow the same rules.
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
    /// earlier value to keep needs a value (a balance, or a trades
    /// account's cash).
    func missingValue(in library: Library) -> String? {
        guard let row, !row.canMarkUnchanged else { return nil }
        if let valuation = valuation(in: library), valuation.isBalance || valuation.isHoldings { return nil }
        return row.mode == .balance
            ? "Enter the balance: this account has no earlier value to keep."
            : "Enter the cash: this account has no earlier value to keep."
    }

    /// The fields *Update Value* shows for the account on this date.
    var fields: AccountValuationFields? {
        row.map { AccountValuationFields(kind: $0.kind, recordsTrades: $0.isTrades, isFirst: $0.previous == nil) }
    }
}

/// Which fields *Update Value* and *Edit Value* ask for: the same as the
/// check-in, by the account's kind (docs/ACCOUNTS.md, "What each kind asks
/// for").
struct AccountValuationFields: Hashable, Sendable {
    /// A balance; otherwise a trades account's cash.
    var balance: Bool
    /// Money in and out: a cash or savings account's, at every value after
    /// its first, unless it records trades.
    var moneyInOut: Bool
    /// The interest a savings account earned, with its money in and out.
    var interest: Bool
    /// New money, typed: only where the kind asks for it (a pension fund's
    /// "paid in since …", property), and a trades account's, which its
    /// trades fill in. Cash, savings and debts work it out from what's typed.
    var flow: Bool

    /// The fields of a value of an account of `kind`; `isFirst`: the
    /// account has no value before it, so it asks only for its balance.
    init(kind: AccountKind, recordsTrades: Bool, isFirst: Bool) {
        balance = !recordsTrades
        moneyInOut = kind.recordsMoneyInOut && !recordsTrades && !isFirst
        interest = moneyInOut && kind.recordsInterest
        flow = recordsTrades || kind.defaultFlow == .ask
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
    /// trade's (`TradeEdit.flows`); `action` is what does it ("Saving",
    /// "Deleting it").
    static func flowFollowUp(_ flows: FlowFollowUp, by action: String = "Saving",
                             locale: Locale = .current) -> String? {
        var sentences: [String] = []
        let recomputed = flows.recomputed
        if !recomputed.isEmpty {
            sentences.append("\(action) also works out again the new money of the \(values(recomputed)) on "
                + "\(dates(recomputed, locale: locale)).")
        }
        let kept = flows.kept
        if !kept.isEmpty {
            sentences.append("The new money of the \(values(kept)) on \(dates(kept, locale: locale)) was typed "
                + "in, so it stays as it is.")
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
        return "Check the money in and out of the \(values(valuations)) on \(dates(valuations, locale: locale)): "
            + "they were for the days since another value."
    }

    /// The confirmation for deleting a value, in the valuation editor and
    /// on the account's details (`flows` from
    /// `Library.previewRemovingValue(_:)`): what the values after it keep
    /// or have worked out again, as ``flowFollowUp(_:by:locale:)`` says it.
    static func deleteMessage(_ flows: FlowFollowUp, locale: Locale = .current) -> String {
        let followUp = flowFollowUp(flows, by: "Deleting it", locale: locale).map { " " + $0 } ?? ""
        return "The account's value then carries forward from the value before it." + followUp
    }

    /// The footer of money in and out, in *Update Value* and the valuation
    /// editor (docs/ACCOUNTS.md, "Money in and out"); with `interest`, a
    /// savings account's.
    static func moneyInOutFooter(interest: Bool) -> String {
        "What came in from outside your accounts and what went out since the last value, loan, mortgage and "
            + "credit card payments included. Money moved between your own accounts is in neither: it's what's "
            + "left of the change." + (interest ? " The interest counts as markets, not new money." : "")
    }

    /// "value" or "values", for `valuations`.
    private static func values(_ valuations: [Valuation]) -> String {
        valuations.count == 1 ? "value" : "values"
    }

    /// The dates of `valuations`: "30 Sep 2026 and 31 Oct 2026".
    private static func dates(_ valuations: [Valuation], locale: Locale) -> String {
        Wording.list(valuations.map { AmountFormat.mediumDate($0.date, locale: locale) })
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
    /// `nil` or empty: the default for the account's kind.
    var flow: String?
    /// A cash or savings account's money in and out; empty: money in is 0,
    /// and money out follows as in the check-in (docs/ACCOUNTS.md,
    /// "Pre-filled values").
    var moneyIn: String?
    var moneyOut: String?
    /// A savings account's interest; empty: none.
    var interest: String?
    var note: String?

    init() {}

    subscript(balance prefilled: String) -> String {
        get { balance ?? prefilled }
        set { balance = newValue }
    }

    subscript(cash prefilled: String) -> String {
        get { cash ?? prefilled }
        set { cash = newValue }
    }

    subscript(moneyIn prefilled: String) -> String {
        get { moneyIn ?? prefilled }
        set { moneyIn = newValue }
    }

    subscript(moneyOut prefilled: String) -> String {
        get { moneyOut ?? prefilled }
        set { moneyOut = newValue }
    }

    subscript(interest prefilled: String) -> String {
        get { interest ?? prefilled }
        set { interest = newValue }
    }

    var flowText: String {
        get { flow ?? "" }
        set { flow = newValue }
    }

    subscript(note prefilled: String) -> String {
        get { note ?? prefilled }
        set { note = newValue }
    }

    /// What stops Save: typed amounts that can't be read, a balance field
    /// that was cleared (an empty field isn't zero), and money in or out
    /// typed with a minus.
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
        check(flow, "new money")
        check(moneyIn, "money in")
        check(moneyOut, "money out")
        check(interest, "interest")
        let money = [moneyIn, moneyOut].compactMap { $0.flatMap { AmountInput.parse($0, locale: locale).value } }
        if money.contains(where: { $0 < 0 }) { problems.append("Money in and out can't be negative.") }
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
            if let balance, let amount = AmountInput.balance(from: balance, isLiability: isLiability, locale: locale) {
                row.setBalance(amount)
            }
            if let cash { row.setCash(AmountInput.decimal(from: cash, locale: locale)) }
            if row.asksMoneyInOut {
                // Emptied, money in is 0 and money out follows again.
                if let amount = Self.entered(moneyIn, locale: locale) { row.setMoneyIn(amount) }
                if let amount = Self.entered(moneyOut, locale: locale) { row.setMoneyOut(amount) }
            }
            if let amount = Self.entered(interest, locale: locale) { row.setInterest(amount) }
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

extension AccountValuationInput {
    /// The amount typed in a field that was edited: `nil` when it wasn't,
    /// or can't be read; `.some(nil)` when it was emptied.
    fileprivate static func entered(_ text: String?, locale: Locale) -> Decimal?? {
        guard let text else { return nil }
        switch AmountInput.parse(text, locale: locale) {
        case .empty: return .some(nil)
        case .value(let amount): return .some(amount)
        case .unreadable: return nil
        }
    }
}

/// The fields of a valuation already saved, while it's edited: date,
/// balance (or cash and a statement's positions), money in and out and a
/// savings account's interest, new money where the kind asks for it, and
/// note (``AccountValuationFields``). Read with the library it's saved in
/// (``fields(in:)``, ``valuation(in:locale:)``): whether it's the
/// account's first value depends on its date, and a cash, savings or debt
/// account's new money is worked out from the value before it.
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
    /// The account's kind, which says what the value asks for.
    let kind: AccountKind
    /// Whether the account records trades: the value is its cash.
    let recordsTrades: Bool
    /// Whether it records a balance (or cash and positions).
    let isBalance: Bool
    /// Whether the account is a debt: its balance is typed as what's owed
    /// and recorded negative (``AmountInput/balance(from:isLiability:locale:)``).
    var isLiability: Bool { kind.isLiability }
    var balance: String
    var cash: String
    var positions: [PositionField]
    /// Empty means unknown. Typed only where ``AccountValuationFields/flow``.
    var flow: String
    /// Money in and out of a cash or savings account. Empty, money in is 0
    /// and money out is suggested, as in *Update Value*; saving records
    /// both, on an older value without them too.
    var moneyIn: String
    var moneyOut: String
    /// A savings account's interest; empty means none.
    var interest: String
    var note: String

    /// The fields of `valuation`, a value of an account of `kind`. A trades
    /// account's (`recordsTrades`) is never a balance: it records cash, and
    /// a balance written by hand isn't used, so saving drops it
    /// (docs/TRADES.md). A debt's balance reads as typed in the check-in.
    init(_ valuation: Valuation, kind: AccountKind, holdsPositions: Bool, recordsTrades: Bool = false,
         locale: Locale = .current) {
        original = valuation
        date = valuation.date
        self.kind = kind
        self.recordsTrades = recordsTrades
        isBalance = !recordsTrades && (valuation.isBalance || (!valuation.isHoldings && !holdsPositions))
        balance = valuation.balance.map {
            AmountInput.balanceText(for: $0, isLiability: kind.isLiability, locale: locale)
        } ?? ""
        cash = valuation.cash.map { AmountInput.text(for: $0, locale: locale) } ?? ""
        positions = valuation.positions.map { position in
            PositionField(instrument: position.instrument,
                          quantity: AmountInput.text(for: position.quantity, locale: locale),
                          cost: position.costBasis.map { AmountInput.text(for: $0, locale: locale) } ?? "")
        }
        flow = valuation.flow.map { AmountInput.text(for: $0, locale: locale) } ?? ""
        moneyIn = valuation.moneyIn.map { AmountInput.text(for: $0, locale: locale) } ?? ""
        moneyOut = valuation.moneyOut.map { AmountInput.text(for: $0, locale: locale) } ?? ""
        interest = valuation.interest.map { AmountInput.text(for: $0, locale: locale) } ?? ""
        note = valuation.note ?? ""
    }

    /// The money out suggested when its field is empty: 0 for savings;
    /// for cash, what money in and the new money suggest
    /// (``Tracker/CheckInDraft/defaultMoneyOut(moneyIn:flow:)``).
    /// `nil` while the value can't be read.
    func suggestedMoneyOut(in library: Library, locale: Locale = .current) -> Decimal? {
        guard let valuation = valuation(in: library, locale: locale, suggestingMoneyOut: false) else { return nil }
        return Self.suggestedMoneyOut(for: valuation, kind: kind)
    }

    private static func suggestedMoneyOut(for valuation: Valuation, kind: AccountKind) -> Decimal {
        kind == .savings ? 0 : CheckInDraft.defaultMoneyOut(moneyIn: valuation.moneyIn ?? 0, flow: valuation.flow) ?? 0
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

    /// `library` without the value being edited, which the form replaces.
    private func others(in library: Library) -> Library {
        var others = library
        others.removeValuation(original.key)
        return others
    }

    /// The account's value before the form's date, the original left out.
    func previous(in library: Library) -> Valuation? {
        others(in: library).valuations(for: original.account).last { $0.date < date }
    }

    /// The fields to show on the form's date: an account's first value
    /// asks only for its balance.
    func fields(in library: Library) -> AccountValuationFields {
        AccountValuationFields(kind: kind, recordsTrades: recordsTrades, isFirst: previous(in: library) == nil)
    }

    /// What can't be read, in order. Fields that aren't shown aren't checked.
    func problems(in library: Library, locale: Locale = .current) -> [String] {
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
        let fields = fields(in: library)
        if fields.flow { check(flow, "new money") }
        if fields.moneyInOut {
            check(moneyIn, "money in")
            check(moneyOut, "money out")
            let moneyAmounts = [moneyIn, moneyOut].map { AmountInput.parse($0, locale: locale) }
            if moneyAmounts.contains(where: { ($0.value ?? 0) < 0 }) {
                problems.append("Money in and out can't be negative.")
            }
        }
        if fields.interest { check(interest, "interest") }
        return problems
    }

    /// The edited valuation, or `nil` while something can't be read. Its
    /// source becomes `manual` when a value or the date changed.
    ///
    /// Fields the form doesn't show keep what the file has, except new
    /// money: a cash, savings or debt account's is worked out from the
    /// value before it in `library` (docs/ACCOUNTS.md, "New money") when
    /// the date, the value or the interest changed.
    func valuation(in library: Library, locale: Locale = .current) -> Valuation? {
        valuation(in: library, locale: locale, suggestingMoneyOut: true)
    }

    private func valuation(in library: Library, locale: Locale, suggestingMoneyOut: Bool) -> Valuation? {
        guard problems(in: library, locale: locale).isEmpty else { return nil }
        func number(_ text: String) -> Decimal? { AmountInput.decimal(from: text, locale: locale) }
        let fields = fields(in: library)
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
        valuation.moneyIn = fields.moneyInOut ? number(moneyIn) ?? 0 : original.moneyIn
        valuation.moneyOut = fields.moneyInOut ? number(moneyOut) : original.moneyOut
        valuation.interest = fields.interest ? number(interest) : original.interest
        // The form doesn't show a one-off or tax: it keeps the file's.
        valuation.oneOff = original.oneOff
        valuation.tax = original.tax
        if fields.flow {
            valuation.flow = number(flow)
        } else if valuation.date == original.date, valuation.balance == original.balance,
                  valuation.cash == original.cash, valuation.positions == original.positions,
                  valuation.interest == original.interest {
            // Nothing the new money is worked out from changed (a note, say), so it stays as it was.
            valuation.flow = original.flow
        } else {
            let others = others(in: library)
            let previous = others.valuations(for: original.account).last { $0.date < date }
            valuation.flow = Valuator(library: others).defaultFlow(for: valuation, previous: previous)
        }
        if fields.moneyInOut, suggestingMoneyOut, valuation.moneyOut == nil {
            valuation.moneyOut = Self.suggestedMoneyOut(for: valuation, kind: kind)
        }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        valuation.note = trimmedNote.isEmpty ? nil : trimmedNote
        var unchanged = original
        unchanged.note = valuation.note
        unchanged.source = nil
        valuation.source = valuation == unchanged ? original.source : .manual
        return valuation
    }
}
