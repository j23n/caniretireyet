import Foundation
import Glance
import Model
import Tracker

// The check-in's presentation logic (UI.md, "Check-in"), kept free of
// SwiftUI so it can be type-checked and tested on Linux: the fields and the
// order they're visited in, the account sections, the words each row shows,
// and the editing rules the screen adds on top of `CheckInDraft`.

// MARK: - Fields

/// A text field in the check-in: what has the keyboard focus, and where
/// ▲ ▼ (iPhone) and Return (Mac) move to.
enum CheckInField: Hashable, Sendable {
    /// An account's balance.
    case balance(AccountID)
    /// The cash held alongside positions.
    case cash(AccountID)
    /// A position's quantity.
    case quantity(AccountID, InstrumentID)
    /// What was paid for a position's added quantity.
    case paid(AccountID, InstrumentID)
    /// The account's new money (the valuation's flow).
    case flow(AccountID)
    /// The money that came into a cash or savings account.
    case moneyIn(AccountID)
    /// The money that went out of it.
    case moneyOut(AccountID)
    /// The valuation's note (the Mac table's Note column).
    case note(AccountID)

    /// The account the field belongs to.
    var account: AccountID {
        switch self {
        case .balance(let account), .cash(let account), .flow(let account), .moneyIn(let account),
             .moneyOut(let account), .note(let account):
            account
        case .quantity(let account, _), .paid(let account, _):
            account
        }
    }
}

extension CheckInField {
    /// A row's first field: its balance, or its first position's quantity,
    /// else its cash. A trades account's is its cash: its positions come
    /// from its trades.
    static func primary(for row: CheckInRow) -> CheckInField {
        if row.isTrades { return .cash(row.account) }
        guard row.mode == .holdings else { return .balance(row.account) }
        if let first = row.positions.first { return .quantity(row.account, first.instrument) }
        return .cash(row.account)
    }

    /// What the field is, for the bar above the keyboard and VoiceOver:
    /// "Conto Fineco", "Directa · VWCE", "Fondo pensione · contributions".
    func name(in library: Library) -> String {
        let account = library.accounts[account]
        let name = account?.name ?? self.account.rawValue
        func label(_ instrument: InstrumentID) -> String {
            CheckInWording.instrumentLabel(instrument, instrument: library.instruments[instrument])
        }
        switch self {
        case .balance: return name
        case .cash: return name + " · cash"
        case .quantity(_, let instrument): return name + " · " + label(instrument)
        case .paid(_, let instrument): return name + " · paid for " + label(instrument)
        case .flow:
            return name + (CheckInWording.isPension(account?.kind) ? " · contributions" : " · new money")
        case .moneyIn: return name + " · money in"
        case .moneyOut: return name + " · money out"
        case .note: return name + " · note"
        }
    }
}

/// How numbers read in the check-in's fields and cells.
enum CheckInFieldFormat {
    /// What a field holds.
    enum Style: Hashable, Sendable {
        /// Money: grouped, two decimals (`4.210,55`).
        case amount
        /// A quantity: ungrouped, up to eight decimals (`412,5`, `0,4215`).
        case quantity
        /// A debt's balance: money, where a typed amount is what's owed
        /// (stored negative) and a leading `+` means in credit (`+20,00`).
        case debt
    }

    /// The text a field shows for `value` while it isn't being edited. It
    /// reads back to the same value with ``value(from:style:locale:)``.
    static func text(for value: Decimal?, style: Style, locale: Locale = .current) -> String {
        guard let value else { return "" }
        switch style {
        case .amount:
            return value.formatted(.number.precision(.fractionLength(2)).locale(locale))
        case .quantity:
            return AmountInput.text(for: value, maxDigits: 8, locale: locale)
        case .debt:
            let text = value.formatted(.number.precision(.fractionLength(2)).locale(locale))
            return value > 0 ? "+" + text : text
        }
    }

    /// The value typed in a field, or `nil` while it can't be read (e.g.
    /// just "-"). A debt's amount is what's owed, unless it starts with `+`.
    static func value(from text: String, style: Style, locale: Locale = .current) -> Decimal? {
        switch style {
        case .amount, .quantity: AmountInput.decimal(from: text, locale: locale)
        case .debt: AmountInput.balance(from: text, isLiability: true, locale: locale)
        }
    }

    /// `text` after the ± key: the minus sign added or removed, or for a
    /// debt, switched between owed and in credit.
    static func toggledSign(_ text: String, style: Style) -> String {
        style == .debt ? AmountInput.toggledCredit(text) : CheckInEditing.toggledSign(text)
    }

    /// An amount without its currency, for table cells and captions:
    /// `4.210,55`, `−310,20`, or `+1.450,00` when `signed`.
    static func plain(_ value: Decimal, signed: Bool = false, locale: Locale = .current) -> String {
        let text: String
        if signed {
            text = value.formatted(
                .number.precision(.fractionLength(2)).sign(strategy: .always(includingZero: false)).locale(locale))
        } else {
            text = value.formatted(.number.precision(.fractionLength(2)).locale(locale))
        }
        return AmountFormat.typographicMinus(text)
    }
}

/// Fields in the order they're visited.
struct CheckInFieldOrder: Hashable, Sendable {
    var fields: [CheckInField]

    /// The field after `field`; the first one when nothing is focused, `nil`
    /// after the last one or for a field that isn't in the order.
    func next(after field: CheckInField?) -> CheckInField? {
        guard let field else { return fields.first }
        guard let index = fields.firstIndex(of: field), index + 1 < fields.count else { return nil }
        return fields[index + 1]
    }

    /// The field before `field`; the last one when nothing is focused, `nil`
    /// before the first one or for a field that isn't in the order.
    func previous(before field: CheckInField?) -> CheckInField? {
        guard let field else { return fields.last }
        guard let index = fields.firstIndex(of: field), index > 0 else { return nil }
        return fields[index - 1]
    }

    /// The iPhone list's fields, top to bottom: each balance; the positions
    /// (quantity, then "paid" when it went up) and cash of the holdings rows
    /// that are expanded; a trades account's statement quantities entered
    /// to compare (expanded) and its cash when it has a field
    /// (``CheckInRowDisplay/showsCashField(_:isEditing:)``, `editingCash`);
    /// and each new-money field that's shown; money in and out after the
    /// balance of the accounts in `moneyInOut`.
    static func list(rows: [CheckInRow], review: CheckInReview, expanded: Set<AccountID>,
                     editingFlows: Set<AccountID>, editingCash: Set<AccountID> = [],
                     moneyInOut: Set<AccountID> = []) -> CheckInFieldOrder {
        var fields: [CheckInField] = []
        for row in rows {
            let isOpen = row.mode == .balance || expanded.contains(row.account)
            if row.isTrades {
                if expanded.contains(row.account) {
                    fields += row.positions.map { .quantity(row.account, $0.instrument) }
                }
                if CheckInRowDisplay.showsCashField(row, isEditing: editingCash.contains(row.account)) {
                    fields.append(.cash(row.account))
                }
            } else if row.mode == .holdings {
                guard isOpen else { continue }
                for position in row.positions {
                    fields.append(.quantity(row.account, position.instrument))
                    if position.isIncrease { fields.append(.paid(row.account, position.instrument)) }
                }
                fields.append(.cash(row.account))
            } else {
                fields.append(.balance(row.account))
                if moneyInOut.contains(row.account) {
                    fields += [.moneyIn(row.account), .moneyOut(row.account)]
                }
            }
            let rule = review.row(for: row.account)?.flowRule ?? .ask
            if CheckInRowDisplay.showsFlowField(row, rule: rule, isEditing: editingFlows.contains(row.account)) {
                fields.append(.flow(row.account))
            }
        }
        return CheckInFieldOrder(fields: fields)
    }

    /// The Mac table's "Now" column, top to bottom: each balance, and each
    /// position's quantity and the cash of holdings rows; a trades
    /// account's statement quantities (if any were entered) and its cash
    /// when it has a field (`editingCash`); money in and out after the
    /// balance of the accounts in `moneyInOut`. Return moves down this
    /// column.
    static func nowColumn(rows: [CheckInRow], editingCash: Set<AccountID> = [],
                          moneyInOut: Set<AccountID> = []) -> CheckInFieldOrder {
        var fields: [CheckInField] = []
        for row in rows {
            if row.isTrades {
                fields += row.positions.map { .quantity(row.account, $0.instrument) }
                if CheckInRowDisplay.showsCashField(row, isEditing: editingCash.contains(row.account)) {
                    fields.append(.cash(row.account))
                }
            } else if row.mode == .holdings {
                for position in row.positions {
                    fields.append(.quantity(row.account, position.instrument))
                }
                fields.append(.cash(row.account))
            } else {
                fields.append(.balance(row.account))
                if moneyInOut.contains(row.account) {
                    fields += [.moneyIn(row.account), .moneyOut(row.account)]
                }
            }
        }
        return CheckInFieldOrder(fields: fields)
    }

    /// Where Return goes from `field` in the Mac table: down the "Now"
    /// column. From a cell in another column (new money, paid, note) it goes
    /// to the "Now" cell below that row.
    func returnTarget(after field: CheckInField) -> CheckInField? {
        if fields.contains(field) { return next(after: field) }
        let anchor: CheckInField? = switch field {
        case .paid(let account, let instrument): .quantity(account, instrument)
        default: fields.last { $0.account == field.account }
        }
        guard let anchor else { return nil }
        return next(after: anchor)
    }
}

// MARK: - Sections

/// The accounts of one group in the check-in (Cash, Investments, …), in the
/// draft's order; or, at the end of a past check-in, the accounts that open
/// after its date ("Opened later").
struct CheckInSection: Identifiable, Hashable, Sendable {
    enum ID: Hashable, Sendable {
        case group(AccountGroup)
        case openedLater
    }

    /// The accounts' group; `nil` for the "Opened later" section.
    var group: AccountGroup?
    var rows: [CheckInRow]

    var id: ID { group.map(ID.group) ?? .openedLater }

    /// Whether this is the section of accounts that open after the date.
    var isOpenedLater: Bool { group == nil }

    /// "Cash", "Investments", …, "Opened later".
    var title: String { group?.description ?? "Opened later" }

    /// The draft's rows by account group, in display order. An account no
    /// longer in the library goes under "Other". Accounts that open after
    /// the date (``CheckInRow/opensLater``) come last, in their own section.
    static func sections(of draft: CheckInDraft, in library: Library) -> [CheckInSection] {
        var rowsByGroup: [AccountGroup: [CheckInRow]] = [:]
        for row in draft.rows where !row.opensLater {
            let group = library.accounts[row.account]?.group ?? .other
            rowsByGroup[group, default: []].append(row)
        }
        var sections = AccountGroup.allCases.compactMap { group in
            rowsByGroup[group].map { CheckInSection(group: group, rows: $0) }
        }
        let later = draft.rowsOpeningLater
        if !later.isEmpty { sections.append(CheckInSection(group: nil, rows: later)) }
        return sections
    }

    /// Whether the iPhone list shows the "Opened later" section's rows: when
    /// it's expanded, or when it's the only section (every account opens
    /// after the date), so the list is never just a collapsed header.
    static func showsOpenedLater(in sections: [CheckInSection], expanded: Bool) -> Bool {
        expanded || sections.allSatisfy(\.isOpenedLater)
    }

    /// The rows the iPhone list shows: every section's, except the "Opened
    /// later" section's while it's collapsed.
    static func visibleRows(of sections: [CheckInSection], showsOpenedLater: Bool) -> [CheckInRow] {
        let shows = Self.showsOpenedLater(in: sections, expanded: showsOpenedLater)
        return sections.filter { !$0.isOpenedLater || shows }.flatMap(\.rows)
    }
}

// MARK: - Rows

/// What a row shows, beyond its values.
enum CheckInRowDisplay {
    /// Whether the row shows a field for new money: when the account's kind
    /// asks for it (a pension fund's "contributions since …") and the row
    /// isn't unchanged or skipped, or when the automatic amount is being
    /// edited. A trades account's new money comes from its trades, whatever
    /// its kind.
    static func showsFlowField(_ row: CheckInRow, rule: FlowDefault, isEditing: Bool) -> Bool {
        if isEditing { return true }
        guard rule == .ask, !row.isTrades else { return false }
        return row.state == .notReviewed || row.state == .updated
    }

    /// Whether a balance row shows money in and out: its account asks for
    /// them (``Model/Account/tracksMoneyInOut``), or they were recorded on
    /// the date already; never for a row marked unchanged or skipped.
    static func showsMoneyInOut(_ row: CheckInRow, in library: Library) -> Bool {
        guard row.mode == .balance, !row.isTrades, row.state != .unchanged, row.state != .skipped else {
            return false
        }
        return library.accounts[row.account]?.tracksMoneyInOut == true || row.moneyIn != nil
            || row.enteredMoneyOut != nil
    }

    /// The style of a row's balance field: a debt's reads amounts as owed.
    static func balanceStyle(of account: AccountID, in library: Library) -> CheckInFieldFormat.Style {
        library.accounts[account]?.kind.isLiability == true ? .debt : .amount
    }

    // MARK: Trades accounts

    /// Whether the row has a field for its cash. A holdings row always
    /// does. A trades row needs nothing typed: its cash is read-only, from
    /// its trades, unless a cash from a statement is being entered
    /// (`isEditing`, *Enter From Statement*) or was (``CheckInRow/hasStatementCash``),
    /// or nothing is recorded yet to work it out from. One that holds no
    /// cash (``CheckInRow/showsCash``) has neither.
    static func showsCashField(_ row: CheckInRow, isEditing: Bool) -> Bool {
        guard row.isTrades else { return row.mode == .holdings }
        guard row.showsCash, row.state != .skipped else { return false }
        return isEditing || row.hasStatementCash || row.derived == nil
    }

    /// Whether a trades row shows its cash read-only, "Cash 1.234,56 · from
    /// trades": when it holds cash and has no field for it.
    static func showsTradeCash(_ row: CheckInRow, isEditing: Bool) -> Bool {
        row.isTrades && row.showsCash && row.state != .skipped && !showsCashField(row, isEditing: isEditing)
    }

    /// Whether a trades row's new money can be edited: only once a cash
    /// from a statement makes part of it a guess (the residual), or when it
    /// was typed already. Otherwise it's what the trades record, read-only.
    static func canEditTradeFlow(_ row: CheckInRow) -> Bool {
        row.isTrades && (row.hasStatementCash || row.isFlowEdited)
    }
}

// MARK: - Review

/// What the review screen lists (UI.md, "Review screen").
enum CheckInReviewDisplay {
    /// The "Changed accounts": rows updated that write a value (rows in
    /// conflict are in their own card), and trades accounts as their trades
    /// say whose value or new money changed, marked "from trades".
    static func changedRows(_ review: CheckInReview, draft: CheckInDraft) -> [CheckInRowReview] {
        review.rows.filter { reviewed in
            guard reviewed.valuation != nil else { return false }
            if reviewed.state == .updated { return true }
            guard draft[reviewed.account]?.followsTrades == true else { return false }
            let changed = (reviewed.value?.knownValue).map { $0 != reviewed.previousValue } ?? false
            return changed || (reviewed.flow ?? 0) != 0
        }
    }

    /// A changed account's line under its name: "New money +1.200 €",
    /// "Contributions +1.325 €", "New money unknown", and for a trades
    /// account as its trades say "New money +1.450 € · from trades". In the
    /// account's currency.
    static func flowLine(_ reviewed: CheckInRowReview, kind: AccountKind?, currency: CurrencyCode,
                         followsTrades: Bool, hidesAmounts: Bool = false, locale: Locale = .current) -> String {
        let title = CheckInWording.isPension(kind) ? "Contributions" : "New money"
        let amount = reviewed.flow.map { flow in
            hidesAmounts ? AmountFormat.hidden
                : AmountFormat.signedAmount(flow, currency: currency, precision: .automatic, locale: locale)
        } ?? "unknown"
        let line = QuantityFormat.labelled(title, amount)
        return followsTrades ? line + " · from trades" : line
    }
}

// MARK: - Editing rules

/// Rules the screen applies on top of `CheckInDraft`'s own editing.
enum CheckInEditing {
    /// Skips every row not reviewed yet: nothing is written for them, and
    /// they'll show as stale.
    static func skipRest(_ draft: inout CheckInDraft) {
        for account in draft.notReviewed {
            guard var row = draft[account] else { continue }
            row.skip()
            draft[account] = row
        }
    }

    /// Records the new money typed in a row's field. Emptied, it's unknown
    /// when the account's kind asks for it (`rule`), else the automatic
    /// amount again.
    static func enterFlow(_ amount: Decimal?, rule: FlowDefault, in row: inout CheckInRow) {
        if let amount {
            row.setFlow(amount)
        } else if rule == .ask {
            row.setFlow(nil)
        } else {
            row.resetFlow()
        }
    }

    /// `text` with its minus sign added or removed (the ± key above the
    /// iPhone's decimal keypad, which has no minus).
    static func toggledSign(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let first = trimmed.first, first == "-" || first == "\u{2212}" {
            return String(trimmed.dropFirst())
        }
        return "-" + trimmed
    }

    /// Whether the draft holds anything the user entered: a value, a row
    /// marked unchanged or skipped, a note, or a price or rate typed in.
    /// Rows only pre-filled from values already saved on the date (e.g. by
    /// the other device) don't count. Cancel asks before throwing such a
    /// draft away.
    static func hasEdits(_ draft: CheckInDraft) -> Bool {
        draft.rows.contains { $0.hasUserInput || ($0.note ?? "") != ($0.existing?.note ?? "") }
            || draft.prices.contains { $0.source == .manual }
            || draft.fxRates.contains { $0.source == .manual }
    }
}

// MARK: - Words

/// The words the check-in shows, formatted for the locale.
enum CheckInWording {
    /// "Updated", "Unchanged", "Not reviewed yet", "Skipped".
    static func stateName(_ state: CheckInRowState) -> String {
        switch state {
        case .updated: "Updated"
        case .unchanged: "Unchanged"
        case .notReviewed: "Not reviewed yet"
        case .skipped: "Skipped"
        }
    }

    /// A row's state in words: ``stateName(_:)``, or "From trades" for a
    /// trades account as its trades say (``CheckInRow/followsTrades``).
    static func stateName(for row: CheckInRow) -> String {
        row.followsTrades ? "From trades" : stateName(row.state)
    }

    /// The swipe action that marks a row unchanged: "Unchanged", or for a
    /// trades account "From Trades" (back to what its trades say).
    static func markUnchangedSwipeTitle(for row: CheckInRow) -> String {
        row.isTrades ? "From Trades" : "Unchanged"
    }

    /// The menu command that marks a row unchanged: "Mark Unchanged", or for
    /// a trades account "Use the Trades' Values".
    static func markUnchangedTitle(for row: CheckInRow) -> String {
        row.isTrades ? "Use the Trades' Values" : "Mark Unchanged"
    }

    /// "7 of 9 reviewed". Accounts that open later count once something was
    /// entered for them.
    static func reviewed(_ draft: CheckInDraft) -> String {
        "\(draft.reviewedCount) of \(draft.progressTotal) reviewed"
    }

    /// The number of accounts a check-in's date line counts: those open on
    /// its date.
    static func accountCount(_ draft: CheckInDraft) -> Int {
        draft.rows.count { !$0.opensLater }
    }

    /// "1 account not reviewed", "2 accounts not reviewed".
    static func notReviewedTitle(count: Int) -> String {
        Wording.count(count, "account") + " not reviewed"
    }

    /// "Not reviewed: Fondo pensione, Mutuo" (at most three names, then "and 2 more").
    static func notReviewed(_ names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        let shown = names.prefix(3).joined(separator: ", ")
        let more = names.count - 3
        return "Not reviewed: " + shown + (more > 0 ? " and \(more) more" : "")
    }

    /// "Last check-in 31 August · 9 accounts" under the date; "First
    /// check-in · 9 accounts" before there's one.
    static func dateLine(previousCheckIn: CalendarDate?, accounts: Int, locale: Locale = .current) -> String {
        let count = Wording.count(accounts, "account")
        guard let previousCheckIn else { return "First check-in · " + count }
        let day = previousCheckIn.dateValue.formatted(.dateTime.day().month(.wide).locale(locale))
        return "Last check-in \(day) · " + count
    }

    /// "Values from 30 September are already saved; saving updates them.",
    /// when the library has a check-in on the draft's date.
    static func existingCheckInNote(on date: CalendarDate, in library: Library,
                                    locale: Locale = .current) -> String? {
        let hasValues = library.months[date.yearMonth]?.valuations.contains { $0.date == date } ?? false
        guard hasValues else { return nil }
        let day = date.dateValue.formatted(.dateTime.day().month(.wide).locale(locale))
        return "There's already a check-in on \(day). Its values are filled in, and saving updates it."
    }

    /// "Conto Fineco got a value for 31 October on another device while this
    /// check-in was open. …", when rows are in conflict with values saved on
    /// the date since the check-in started; `nil` otherwise.
    static func conflictNote(_ draft: CheckInDraft, in library: Library, locale: Locale = .current) -> String? {
        let names = draft.conflicts.map { library.accounts[$0.account]?.name ?? $0.account.rawValue }
        guard !names.isEmpty else { return nil }
        let day = draft.date.dateValue.formatted(.dateTime.day().month(.wide).locale(locale))
        let one = names.count == 1
        return "\(Wording.list(names)) got \(one ? "a value" : "values") for \(day) on another device "
            + "while this check-in was open. "
            + "Until you choose, \(one ? "the saved value is" : "the saved values are") kept and yours "
            + "\(one ? "isn't" : "aren't") written."
    }

    /// Whether an account's new money is called its contributions: a
    /// pension fund's and TFR's.
    static func isPension(_ kind: AccountKind?) -> Bool {
        kind == .pensionFund || kind == .tfr
    }

    /// What the new-money field is called: "Contributions since June" for
    /// pension funds and TFR, "New money since 31 Aug" for other accounts
    /// whose flow is asked for, "New money" otherwise.
    static func flowTitle(kind: AccountKind?, rule: FlowDefault, previous: Valuation?,
                          locale: Locale = .current) -> String {
        guard rule == .ask else { return "New money" }
        let pension = isPension(kind)
        guard let previous else { return pension ? "Contributions" : "New money" }
        if pension {
            return "Contributions since " + AmountFormat.monthName(previous.date.adding(days: 1), locale: locale)
        }
        return "New money since " + AmountFormat.shortDate(previous.date, locale: locale)
    }

    /// The line under a row that isn't updated: "Pre-filled from 31 Aug",
    /// "Unchanged" ("As the trades say" for a trades account), "Skipped ·
    /// no value this time", or for a new account "New account · enter its
    /// value". `nil` for an updated row, whose line
    /// shows the amounts. A row of an account that opens later says so
    /// instead (see ``openingNote(for:opened:date:locale:)``).
    static func caption(for row: CheckInRow, locale: Locale = .current) -> String? {
        switch row.state {
        case .updated:
            return nil
        case .unchanged:
            return row.followsTrades ? "As the trades say" : "Unchanged"
        case .skipped:
            return "Skipped · no value this time"
        case .notReviewed:
            if row.opensLater { return "Optional · leave empty to change nothing" }
            guard let previous = row.previous else { return "New account · enter its value" }
            return "Pre-filled from " + AmountFormat.shortDate(previous.date, locale: locale)
        }
    }

    /// The footnote of a row whose account opens after the check-in's
    /// `date` (on `opened`): "Opened 30 Sep 2026 · a value here moves its
    /// opening date to 31 Mar 2024." until a value is entered, then "Saving
    /// moves its opening date to 31 Mar 2024." `nil` for other rows, and
    /// for a skipped one (it writes nothing).
    static func openingNote(for row: CheckInRow, opened: CalendarDate?, date: CalendarDate,
                            locale: Locale = .current) -> String? {
        guard row.opensLater, row.state != .skipped else { return nil }
        let moved = AmountFormat.mediumDate(date, locale: locale)
        if row.state == .notReviewed {
            let since = opened.map { "Opened " + AmountFormat.mediumDate($0, locale: locale) + " · " } ?? ""
            return since + "a value here moves its opening date to \(moved)."
        }
        return "Saving moves its opening date to \(moved)."
    }

    /// The short form for the Mac table's account column: "opened 30 Sep
    /// 2026 · optional", or once a value is entered "opening date moves to
    /// 31 Mar 2024". `nil` for other rows, and a skipped one.
    static func openingDetail(for row: CheckInRow, opened: CalendarDate?, date: CalendarDate,
                              locale: Locale = .current) -> String? {
        guard row.opensLater, row.state != .skipped else { return nil }
        if row.state == .notReviewed {
            return (opened.map { "opened " + AmountFormat.mediumDate($0, locale: locale) + " · " } ?? "") + "optional"
        }
        return "opening date moves to " + AmountFormat.mediumDate(date, locale: locale)
    }

    /// The review's note on accounts whose opening date saving moves:
    /// "Saving moves the opening date of Fineco and Directa to 31 Mar
    /// 2024." `nil` when there are none.
    static func openingMovesNote(_ accounts: [AccountID], date: CalendarDate, in library: Library,
                                 locale: Locale = .current) -> String? {
        guard !accounts.isEmpty else { return nil }
        let names = Wording.list(accounts.map { library.accounts[$0]?.name ?? $0.rawValue })
        return "Saving moves the opening date of \(names) to \(AmountFormat.mediumDate(date, locale: locale)), "
            + "so \(accounts.count == 1 ? "its history starts" : "their histories start") there."
    }

    /// The banner of a past check-in, one dated before the library's latest
    /// (`latest`): later values stay, and no answer is recorded. `nil` when
    /// the check-in isn't a past one.
    static func pastCheckInNote(on date: CalendarDate, in library: Library, locale: Locale = .current) -> String? {
        guard let latest = CheckInStore.laterCheckIn(than: date, in: library) else { return nil }
        let hasLaterAccounts = library.accounts.values.contains { $0.opened > date && ($0.closed.map { date <= $0 } ?? true) }
        return "Your latest check-in is \(AmountFormat.longDate(latest, locale: locale)). Values saved after this "
            + "date stay as they are, and the answer to \u{201C}Can I retire yet?\u{201D} is only recorded at the "
            + "latest check-in."
            + (hasLaterAccounts ? " Accounts opened after this date are listed at the end, under Opened later." : "")
    }

    /// The confirmation of a past check-in, in place of the answer: "Saved a
    /// past check-in (31 Mar 2024). The answer isn't recorded for past dates."
    static func pastCheckInSaved(on date: CalendarDate, latest: CalendarDate?, locale: Locale = .current) -> String {
        var text = "Saved a past check-in (\(AmountFormat.mediumDate(date, locale: locale))). "
            + "The answer isn't recorded for past dates"
        if let latest {
            text += ": it's worked out at your latest check-in, \(AmountFormat.mediumDate(latest, locale: locale))"
        }
        return text + "."
    }

    /// "Last value 31 May", when the previous value is older than the
    /// previous check-in.
    static func lastValueNote(for row: CheckInRow, previousCheckIn: CalendarDate?,
                              locale: Locale = .current) -> String? {
        guard let date = row.previous?.date, let previousCheckIn, date < previousCheckIn else { return nil }
        return "Last value " + AmountFormat.shortDate(date, locale: locale)
    }

    /// A collapsed holdings row's summary: "0,4215 BTC" for one position,
    /// "3 positions · quantities unchanged", "3 positions · 1 changed".
    static func holdingsSummary(_ row: CheckInRow, instruments: [InstrumentID: Instrument],
                                locale: Locale = .current) -> String {
        let held = row.positions.filter { $0.quantity != 0 || $0.previousQuantity != 0 }
        if held.isEmpty {
            return row.cash.map { _ in "Cash only" } ?? "No positions"
        }
        if held.count == 1, let position = held.first {
            let quantity = self.quantity(position.quantity, instrument: instruments[position.instrument],
                                         locale: locale)
            return position.quantityChange == 0 ? quantity : quantity + " · changed"
        }
        let changed = held.count { $0.quantityChange != 0 }
        let count = "\(held.count) positions"
        return changed == 0 ? count + " · quantities unchanged" : count + " · \(changed) changed"
    }

    /// A trades account's summary: "423 VWCE · from trades", "93,3 g · from
    /// trades", "3 positions · from trades", "Cash only · from trades", or
    /// "No trades yet" when nothing is recorded before the date.
    static func tradesSummary(_ row: CheckInRow, instruments: [InstrumentID: Instrument],
                              locale: Locale = .current) -> String {
        guard let derived = row.derived else { return "No trades yet" }
        let held = derived.positions.filter { $0.quantity != 0 }
        let what: String
        if held.isEmpty {
            what = row.showsCash ? "Cash only" : "Nothing held"
        } else if held.count == 1, let position = held.first {
            // Shares by their ticker ("423 VWCE"), anything else by its unit ("93,3 g", "0,4215 BTC").
            let instrument = instruments[position.instrument]
            let unit = QuantityFormat.unit(of: instrument)
            let label = unit == nil || unit == "sh" ? instrumentLabel(position.instrument, instrument: instrument) : unit
            what = QuantityFormat.quantity(position.quantity, unit: label, locale: locale)
        } else {
            what = "\(held.count) positions"
        }
        return what + " · from trades"
    }

    /// What *Add Trade…* asks in a trades account's row: "Bought or sold
    /// since 30 Sep?" (its previous value), else "Bought or sold anything?".
    static func addTradePrompt(for row: CheckInRow, locale: Locale = .current) -> String {
        guard let previous = row.previous else { return "Bought or sold anything?" }
        return "Bought or sold since " + AmountFormat.shortDate(previous.date, locale: locale) + "?"
    }

    /// What VoiceOver reads for *Add Trade…*: "Add a trade to Directa, dated
    /// 31 October".
    static func addTradeLabel(account name: String, date: CalendarDate, locale: Locale = .current) -> String {
        let day = date.dateValue.formatted(.dateTime.day().month(.wide).locale(locale))
        return "Add a trade to \(name), dated \(day)"
    }

    /// A trades account's cash, read-only: "Cash 1.234,56 · from trades".
    /// `nil` when the account holds no cash (``CheckInRow/showsCash``).
    static func tradeCash(_ row: CheckInRow, hidesAmounts: Bool = false, locale: Locale = .current) -> String? {
        guard row.isTrades, row.showsCash else { return nil }
        let cash = row.cash ?? row.derived?.cash ?? 0
        let amount = hidesAmounts ? AmountFormat.hidden : CheckInFieldFormat.plain(cash, locale: locale)
        let source = row.hasStatementCash ? "from a statement" : "from trades"
        return QuantityFormat.labelled("Cash", amount) + " · " + source
    }

    /// Under a cash from a statement: "From a statement · the trades give
    /// 312,30". `nil` for other rows, and when nothing is recorded yet.
    static func statementCashNote(_ row: CheckInRow, hidesAmounts: Bool = false,
                                  locale: Locale = .current) -> String? {
        guard row.isTrades, let derived = row.derived?.cash else { return nil }
        let amount = hidesAmounts ? AmountFormat.hidden : CheckInFieldFormat.plain(derived, locale: locale)
        return "From a statement · the trades give " + amount
    }

    /// A trades account's new money, read-only: "New money +1.200,00 · paid
    /// from outside", or with several parts "New money +1.400,60 · deposits
    /// +200,60 · paid from outside +1.200,00". `total` is the new money the
    /// row writes. `nil` when it's zero with nothing to split.
    static func tradeNewMoney(_ flow: CheckInTradeFlow, total: Decimal?, hidesAmounts: Bool = false,
                              locale: Locale = .current) -> String? {
        let parts = tradeFlowParts(flow, hidesAmounts: hidesAmounts, locale: locale)
        guard let total else {
            return (["New money unknown"] + parts.map(\.text)).joined(separator: " · ")
        }
        guard total != 0 || !parts.isEmpty else { return nil }
        let amount = hidesAmounts ? AmountFormat.hidden : CheckInFieldFormat.plain(total, signed: true, locale: locale)
        let lead = QuantityFormat.labelled("New money", amount)
        if parts.count == 1, let part = parts.first, part.amount == total {
            return lead + " · " + part.name
        }
        return ([lead] + parts.map(\.text)).joined(separator: " · ")
    }

    /// The parts of a trades account's new money: "deposits +200,60 · paid
    /// from outside +1.200,00 · cash difference +11,30". `nil` when all are
    /// zero or unknown.
    static func tradeFlowDetail(_ flow: CheckInTradeFlow, hidesAmounts: Bool = false,
                                locale: Locale = .current) -> String? {
        let parts = tradeFlowParts(flow, hidesAmounts: hidesAmounts, locale: locale)
        return parts.isEmpty ? nil : parts.map(\.text).joined(separator: " · ")
    }

    /// One part of a trades account's new money: "deposits" and its amount.
    private struct TradeFlowPart {
        var name: String
        var amount: Decimal?
        var text: String
    }

    private static func tradeFlowParts(_ flow: CheckInTradeFlow, hidesAmounts: Bool,
                                       locale: Locale) -> [TradeFlowPart] {
        func part(_ name: String, _ amount: Decimal) -> TradeFlowPart {
            let shown = hidesAmounts ? AmountFormat.hidden : CheckInFieldFormat.plain(amount, signed: true, locale: locale)
            return TradeFlowPart(name: name, amount: amount, text: QuantityFormat.labelled(name, shown))
        }
        var parts: [TradeFlowPart] = []
        let paidOutside = flow.trades.paidOutside
        if let recorded = flow.trades.recorded.map({ $0 - paidOutside }), recorded != 0 {
            parts.append(part("deposits", recorded))
        } else if flow.trades.recorded == nil {
            parts.append(TradeFlowPart(name: "transfers not valued", amount: nil, text: "transfers not valued"))
        }
        if paidOutside != 0 { parts.append(part("paid from outside", paidOutside)) }
        if let residual = flow.residual, residual != 0 { parts.append(part("cash difference", residual)) }
        return parts
    }

    /// What a trades account's new money is, for help text and VoiceOver.
    static let tradeFlowExplanation = "New money is the deposits, withdrawals and transfers recorded as trades since "
        + "the last value, and what was bought or sold paid from outside the account, plus any difference between "
        + "a cash entered from a statement and the cash the trades give, which counts as money added or taken out "
        + "that no trade records."

    /// The short name of an instrument: its ticker, a crypto's unit (BTC),
    /// else its name, else its ID.
    static func instrumentLabel(_ id: InstrumentID, instrument: Instrument?) -> String {
        guard let instrument else { return id.rawValue }
        if let ticker = instrument.ticker, !ticker.isEmpty { return ticker }
        if instrument.kind == .crypto { return instrument.unit.rawValue }
        return instrument.name
    }

    /// The unit quantities are counted in: "sh" for shares, else the unit
    /// itself ("g", "ozt", "BTC").
    static func unit(of instrument: Instrument?) -> String {
        QuantityFormat.unit(of: instrument) ?? ""
    }

    /// A quantity with its unit: "412,5 sh", "0,4215 BTC", "62,2 g"
    /// (``QuantityFormat``).
    static func quantity(_ quantity: Decimal, instrument: Instrument?, locale: Locale = .current) -> String {
        QuantityFormat.quantity(quantity, unit: QuantityFormat.unit(of: instrument), locale: locale)
    }

    /// A position's price in the check-in: "× 138,42 €", in the price's own
    /// currency (``QuantityFormat/unitPrice(_:currency:locale:)``), after
    /// `unit` when given ("sh × 138,42 €"); "no price" without one.
    static func priceText(unit: String, price: PriceRecord?, locale: Locale = .current) -> String {
        guard let price else { return unit.isEmpty ? "no price" : "\(unit) · no price" }
        let text = "× " + QuantityFormat.unitPrice(price.price, currency: price.currency, locale: locale)
        return unit.isEmpty ? text : unit + " " + text
    }

    /// The first word of the check-in's review: "5 updated · 3 unchanged ·
    /// 2 from trades · 1 skipped". Trades accounts as their trades say
    /// count as "from trades", not unchanged.
    static func stateCounts(_ draft: CheckInDraft) -> String {
        let fromTrades = draft.rows.count { $0.followsTrades && $0.countsInProgress }
        let parts: [(String, Int)] = [
            ("updated", draft.count(.updated)), ("unchanged", draft.count(.unchanged) - fromTrades),
            ("from trades", fromTrades), ("skipped", draft.count(.skipped)),
            ("not reviewed", draft.count(.notReviewed)),
        ]
        return parts.compactMap { word, count in count == 0 ? nil : "\(count) \(word)" }.joined(separator: " · ")
    }
}

// MARK: - Trades accounts

/// A trades account's new money in a check-in (docs/TRADES.md, "Flows"):
/// the deposits, withdrawals, transfers and openings recorded as trades
/// since the previous value, plus the residual, the cash typed minus the
/// cash the trades give.
struct CheckInTradeFlow: Hashable, Sendable {
    /// What the trades record, and the part of it paid from or into
    /// another account.
    var trades: TradeFlowParts
    /// The cash typed minus the cash the trades give on the date; `nil`
    /// when the row records no cash.
    var residual: Decimal?

    /// The split of `row`'s new money on `date`, with the library's trades
    /// (`valuator`), for a trades account's row that writes a value
    /// (updated, or as its trades say); `nil` for any other row. The
    /// trades count from where the saved new money counts them
    /// (`Valuator.tradeFlowParts(of:on:previous:)`): the row's previous
    /// value, or at the account's first check-in the library's previous one.
    static func make(for row: CheckInRow, date: CalendarDate, valuator: Valuator) -> CheckInTradeFlow? {
        guard row.isTrades, row.state == .updated || row.state == .unchanged else { return nil }
        return CheckInTradeFlow(trades: valuator.tradeFlowParts(of: row.account, on: date, previous: row.previous),
                                residual: row.cash.map { $0 - (row.derived?.cash ?? 0) })
    }
}

// MARK: - Warnings

/// A review warning in words, with what the screen can offer to fix it.
struct CheckInWarningText: Hashable, Sendable {
    /// What a warning's button does.
    enum Action: Hashable, Sendable {
        /// Go back to the row and focus its new-money field.
        case enterFlow(AccountID)
        /// Go back to the row.
        case showRow(AccountID)
        /// Open the price list.
        case openPrices
        /// Open the trade editor on a new trade for the account, on the check-in's date.
        case addTrade(AccountID, InstrumentID?)
    }

    /// A statement quantity entered for a trades account that differs from
    /// what its trades give: "The statement on 31 Oct shows 12 VWCE; your
    /// trades give 10. Add the missing trade." (UI.md, "Check-in").
    static func mismatch(_ mismatch: PositionMismatch, library: Library, locale: Locale = .current) -> CheckInWarningText {
        let note = TradeIssueNote.note(for: mismatch, library: library, locale: locale)
        let name = library.accounts[mismatch.account]?.name ?? mismatch.account.rawValue
        return CheckInWarningText(
            title: "\(name): \(note.title)",
            message: note.message + " Or correct the quantity entered.",
            action: .addTrade(mismatch.account, mismatch.instrument), actionTitle: "Add Trade…")
    }

    var title: String
    var message: String
    var action: Action?
    var actionTitle: String?

    /// The warning in calm words (UI.md: nothing scolds). Amounts aren't
    /// named, so the text can show while amounts are hidden.
    static func make(_ warning: CheckInWarning, library: Library, locale: Locale = .current) -> CheckInWarningText {
        func name(_ account: AccountID) -> String { library.accounts[account]?.name ?? account.rawValue }
        func label(_ instrument: InstrumentID) -> String {
            CheckInWording.instrumentLabel(instrument, instrument: library.instruments[instrument])
        }
        switch warning {
        case .quantityDecreased(let account, let instrument, let from, let to):
            let unit = CheckInWording.unit(of: library.instruments[instrument])
            let suffix = unit.isEmpty ? "" : " " + unit
            return CheckInWarningText(
                title: "\(name(account)): fewer \(label(instrument))",
                message: "\(QuantityFormat.quantity(from, locale: locale)) → "
                    + "\(QuantityFormat.quantity(to, locale: locale))\(suffix). Did you sell some? "
                    + "If so, the sale counts as money taken out, unless it stayed in the account as cash.",
                action: .showRow(account), actionTitle: "Check")
        case .largeChange(let account, let from, let to):
            let share = from == 0 ? 0 : ((to - from) / abs(from)).doubleValue
            return CheckInWarningText(
                title: "\(name(account)) changed by \(AmountFormat.percent(share, digits: 0, signed: true, locale: locale))",
                message: "That's more than usual. Worth a second look in case of a typo.",
                action: .showRow(account), actionTitle: "Check")
        case .unknownFlow(let account):
            let pension = CheckInWording.isPension(library.accounts[account]?.kind)
            return CheckInWarningText(
                title: "\(name(account)): \(pension ? "contributions" : "new money") unknown",
                message: "Its change counts as \u{201C}other\u{201D} until you enter it, so the waterfall can't "
                    + "separate saving from growth.",
                action: .enterFlow(account), actionTitle: pension ? "Enter contributions" : "Enter new money")
        case .valuation(let problem):
            switch problem {
            case .missingPrice(let account, let instrument):
                return CheckInWarningText(
                    title: "No price for \(label(instrument))",
                    message: "\(name(account)) is missing part of its value. Type the price in the price list.",
                    action: .openPrices, actionTitle: "Price list")
            case .missingFX(let account, let from, let to):
                return CheckInWarningText(
                    title: "No \(from.rawValue)→\(to.rawValue) rate",
                    message: "\(name(account)) is missing part of its value. Type the rate in the price list.",
                    action: .openPrices, actionTitle: "Price list")
            case .noValuation(let account):
                return CheckInWarningText(
                    title: "\(name(account)) has no value",
                    message: "Enter a value, or skip the account for this check-in.",
                    action: .showRow(account), actionTitle: "Enter")
            }
        }
    }
}

// MARK: - The answer

/// This month's answer after saving (UI.md, "After saving"):
/// "Not yet: earliest at **54**, unchanged since August."
struct CheckInAnswer: Hashable, Sendable {
    /// The words before the emphasised part.
    var lead: String
    /// The emphasised part, e.g. the earliest age.
    var emphasis: String?
    /// The words after it.
    var trail: String

    /// The whole sentence.
    var text: String { lead + (emphasis ?? "") + trail }

    /// The answer for `headline`, compared with the answer recorded at the
    /// check-in before (`previous`), if any.
    static func make(_ headline: PlanHeadline, previous: Headline?, locale: Locale = .current) -> CheckInAnswer {
        if headline.canRetireNow {
            return CheckInAnswer(
                lead: "Yes: retiring now works in ", emphasis: GlanceText.futures(headline.confidence),
                trail: " simulated futures.")
        }
        guard let age = headline.earliestAge else {
            return CheckInAnswer(
                lead: "Not yet: no retirement age in the plan works in \(GlanceText.futures(headline.confidence)) "
                    + "simulated futures yet.", emphasis: nil, trail: "")
        }
        return CheckInAnswer(lead: "Not yet: earliest at ", emphasis: "\(age)",
                             trail: comparison(age: age, previous: previous, locale: locale))
    }

    /// ", unchanged since August.", ", 1 year earlier than in August.", or ".".
    static func comparison(age: Int, previous: Headline?, locale: Locale = .current) -> String {
        guard let previous, let before = previous.earliestAge else { return "." }
        let month = AmountFormat.monthName(previous.date, locale: locale)
        if before == age { return ", unchanged since \(month)." }
        let years = abs(age - before)
        let span = Wording.count(years, "year")
        return age < before ? ", \(span) earlier than in \(month)." : ", \(span) later than in \(month)."
    }

    /// The answer recorded at the check-in before `date` for the main plan.
    static func previousHeadline(before date: CalendarDate, in library: Library) -> Headline? {
        guard let main = library.settings.mainPlan else { return nil }
        return library.headlines(for: main).last { $0.date < date }
    }
}
