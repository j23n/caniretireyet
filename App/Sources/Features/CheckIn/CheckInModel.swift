import Foundation
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
    /// The valuation's note (the Mac table's Note column).
    case note(AccountID)

    /// The account the field belongs to.
    var account: AccountID {
        switch self {
        case .balance(let account), .cash(let account), .flow(let account), .note(let account):
            account
        case .quantity(let account, _), .paid(let account, _):
            account
        }
    }
}

extension CheckInField {
    /// A row's first field: its balance, or its first position's quantity,
    /// else its cash.
    static func primary(for row: CheckInRow) -> CheckInField {
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
            let isPension = account?.kind == .pensionFund || account?.kind == .tfr
            return name + (isPension ? " · contributions" : " · new money")
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
    }

    /// The text a field shows for `value` while it isn't being edited. It
    /// reads back to the same value with `AmountInput.decimal(from:locale:)`.
    static func text(for value: Decimal?, style: Style, locale: Locale = .current) -> String {
        guard let value else { return "" }
        switch style {
        case .amount:
            return value.formatted(.number.precision(.fractionLength(2)).locale(locale))
        case .quantity:
            return AmountInput.text(for: value, maxDigits: 8, locale: locale)
        }
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
    /// that are expanded; and each new-money field that's shown.
    static func list(rows: [CheckInRow], library: Library, expanded: Set<AccountID>,
                     editingFlows: Set<AccountID>) -> CheckInFieldOrder {
        var fields: [CheckInField] = []
        for row in rows {
            let isOpen = row.mode == .balance || expanded.contains(row.account)
            if row.mode == .holdings {
                guard isOpen else { continue }
                for position in row.positions {
                    fields.append(.quantity(row.account, position.instrument))
                    if position.isIncrease { fields.append(.paid(row.account, position.instrument)) }
                }
                fields.append(.cash(row.account))
            } else {
                fields.append(.balance(row.account))
            }
            let rule = CheckInRowDisplay.flowRule(of: row.account, in: library)
            if CheckInRowDisplay.showsFlowField(row, rule: rule, isEditing: editingFlows.contains(row.account)) {
                fields.append(.flow(row.account))
            }
        }
        return CheckInFieldOrder(fields: fields)
    }

    /// The Mac table's "Now" column, top to bottom: each balance, and each
    /// position's quantity and the cash of holdings rows. Return moves down
    /// this column.
    static func nowColumn(rows: [CheckInRow]) -> CheckInFieldOrder {
        var fields: [CheckInField] = []
        for row in rows {
            if row.mode == .holdings {
                for position in row.positions {
                    fields.append(.quantity(row.account, position.instrument))
                }
                fields.append(.cash(row.account))
            } else {
                fields.append(.balance(row.account))
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
/// draft's order.
struct CheckInSection: Identifiable, Hashable, Sendable {
    var group: AccountGroup
    var rows: [CheckInRow]

    var id: AccountGroup { group }

    /// The draft's rows by account group, in display order. An account no
    /// longer in the library goes under "Other".
    static func sections(of draft: CheckInDraft, in library: Library) -> [CheckInSection] {
        var rowsByGroup: [AccountGroup: [CheckInRow]] = [:]
        for row in draft.rows {
            let group = library.accounts[row.account]?.group ?? .other
            rowsByGroup[group, default: []].append(row)
        }
        return AccountGroup.allCases.compactMap { group in
            rowsByGroup[group].map { CheckInSection(group: group, rows: $0) }
        }
    }
}

// MARK: - Rows

/// What a row shows, beyond its values.
enum CheckInRowDisplay {
    /// How the account's kind fills in new money; `.ask` for an account no
    /// longer in the library.
    static func flowRule(of account: AccountID, in library: Library) -> FlowDefault {
        library.accounts[account]?.kind.defaultFlow ?? .ask
    }

    /// Whether the row shows a field for new money: when the account's kind
    /// asks for it (a pension fund's "contributions since …") and the row
    /// isn't unchanged or skipped, or when the automatic amount is being
    /// edited.
    static func showsFlowField(_ row: CheckInRow, rule: FlowDefault, isEditing: Bool) -> Bool {
        if isEditing { return true }
        guard rule == .ask else { return false }
        return row.state == .notReviewed || row.state == .updated
    }

    /// Whether "unchanged" means something for the row: there's a previous
    /// value to keep. A new account has none, so it can only be entered or
    /// skipped.
    static func canMarkUnchanged(_ row: CheckInRow) -> Bool {
        row.previous != nil
    }

    /// Whether the row's previous value is older than the previous
    /// check-in, so the row says when it's from ("Last value 31 May").
    static func isPreviousOld(_ row: CheckInRow, previousCheckIn: CalendarDate?) -> Bool {
        guard let date = row.previous?.date, let previousCheckIn else { return false }
        return date < previousCheckIn
    }
}

// MARK: - Editing rules

/// Rules the screen applies on top of `CheckInDraft`'s own editing.
enum CheckInEditing {
    /// Marks every row not reviewed yet as unchanged. Accounts without a
    /// previous value (new ones) have nothing to keep, so they're skipped
    /// instead of getting an empty valuation.
    static func markRestUnchanged(_ draft: inout CheckInDraft) {
        for account in draft.notReviewed {
            guard var row = draft[account] else { continue }
            if CheckInRowDisplay.canMarkUnchanged(row) {
                row.markUnchanged()
            } else {
                row.skip()
            }
            draft[account] = row
        }
    }

    /// Skips every row not reviewed yet: nothing is written for them, and
    /// they'll show as stale.
    static func skipRest(_ draft: inout CheckInDraft) {
        for account in draft.notReviewed {
            guard var row = draft[account] else { continue }
            row.skip()
            draft[account] = row
        }
    }

    /// The balance to record for an amount typed into a debt's field: debts
    /// are negative balances, so a positive amount is read as a debt (as the
    /// importer does). Other accounts record what was typed.
    static func balance(_ typed: Decimal, isLiability: Bool) -> Decimal {
        isLiability && typed > 0 ? -typed : typed
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

    /// Whether the draft holds anything the user entered: a reviewed row, a
    /// note, or a price or rate typed in. Cancel asks before throwing such a
    /// draft away.
    static func hasEdits(_ draft: CheckInDraft) -> Bool {
        draft.reviewedCount > 0
            || draft.rows.contains { !($0.note ?? "").isEmpty }
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

    /// "7 of 9 reviewed".
    static func reviewed(_ draft: CheckInDraft) -> String {
        "\(draft.reviewedCount) of \(draft.rows.count) reviewed"
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
        let count = "\(accounts) account\(accounts == 1 ? "" : "s")"
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

    /// What the new-money field is called: "Contributions since June" for
    /// pension funds and TFR, "New money since 31 Aug" for other accounts
    /// whose flow is asked for, "New money" otherwise.
    static func flowTitle(kind: AccountKind?, rule: FlowDefault, previous: Valuation?,
                          locale: Locale = .current) -> String {
        guard rule == .ask else { return "New money" }
        let isPension = kind == .pensionFund || kind == .tfr
        guard let previous else { return isPension ? "Contributions" : "New money" }
        if isPension {
            return "Contributions since " + AmountFormat.monthName(previous.date.adding(days: 1), locale: locale)
        }
        return "New money since " + AmountFormat.shortDate(previous.date, locale: locale)
    }

    /// The line under a row that isn't updated: "Pre-filled from 31 Aug",
    /// "Unchanged", "Skipped · no value this time", or for a new account
    /// "New account · enter its value". `nil` for an updated row, whose line
    /// shows the amounts.
    static func caption(for row: CheckInRow, locale: Locale = .current) -> String? {
        switch row.state {
        case .updated:
            return nil
        case .unchanged:
            return "Unchanged"
        case .skipped:
            return "Skipped · no value this time"
        case .notReviewed:
            guard let previous = row.previous else { return "New account · enter its value" }
            return "Pre-filled from " + AmountFormat.shortDate(previous.date, locale: locale)
        }
    }

    /// "Last value 31 May", when the previous value is older than the
    /// previous check-in.
    static func lastValueNote(for row: CheckInRow, previousCheckIn: CalendarDate?,
                              locale: Locale = .current) -> String? {
        guard CheckInRowDisplay.isPreviousOld(row, previousCheckIn: previousCheckIn),
              let date = row.previous?.date
        else { return nil }
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
            let quantity = self.quantity(position.quantity, of: position.instrument,
                                         instrument: instruments[position.instrument], locale: locale)
            return position.quantityChange == 0 ? quantity : quantity + " · changed"
        }
        let changed = held.count { $0.quantityChange != 0 }
        let count = "\(held.count) positions"
        return changed == 0 ? count + " · quantities unchanged" : count + " · \(changed) changed"
    }

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
        guard let unit = instrument?.unit else { return "" }
        return unit == .share ? "sh" : unit.rawValue
    }

    /// A quantity with its unit: "412,5 sh", "0,4215 BTC", "62,2 g".
    static func quantity(_ quantity: Decimal, of id: InstrumentID, instrument: Instrument?,
                         locale: Locale = .current) -> String {
        let unit = self.unit(of: instrument)
        let number = AmountFormat.number(quantity, maxDigits: 8, locale: locale)
        return unit.isEmpty ? number : number + " " + unit
    }

    /// A change in quantity with its sign: "+10,5", "−5".
    static func quantityChange(_ change: Decimal, locale: Locale = .current) -> String {
        let number = AmountFormat.number(abs(change), maxDigits: 8, locale: locale)
        if change > 0 { return "+" + number }
        if change < 0 { return AmountFormat.minus + number }
        return number
    }

    /// The first word of the check-in's review: "5 updated · 3 unchanged · 1 skipped".
    static func stateCounts(_ draft: CheckInDraft) -> String {
        let parts: [(CheckInRowState, String)] = [
            (.updated, "updated"), (.unchanged, "unchanged"), (.skipped, "skipped"), (.notReviewed, "not reviewed"),
        ]
        return parts.compactMap { state, word in
            let count = draft.count(state)
            return count == 0 ? nil : "\(count) \(word)"
        }.joined(separator: " · ")
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
                message: "\(AmountFormat.number(from, maxDigits: 8, locale: locale)) → "
                    + "\(AmountFormat.number(to, maxDigits: 8, locale: locale))\(suffix). Did you sell some? "
                    + "If so, the sale counts as money taken out, unless it stayed in the account as cash.",
                action: .showRow(account), actionTitle: "Check")
        case .largeChange(let account, let from, let to):
            let share = from == 0 ? 0 : ((to - from) / abs(from)).doubleValue
            return CheckInWarningText(
                title: "\(name(account)) changed by \(AmountFormat.percent(share, digits: 0, signed: true, locale: locale))",
                message: "That's more than usual. Worth a second look in case of a typo.",
                action: .showRow(account), actionTitle: "Check")
        case .unknownFlow(let account):
            let kind = library.accounts[account]?.kind
            let isPension = kind == .pensionFund || kind == .tfr
            return CheckInWarningText(
                title: "\(name(account)): \(isPension ? "contributions" : "new money") unknown",
                message: "Its change counts as \u{201C}other\u{201D} until you enter it, so the waterfall can't "
                    + "separate saving from growth.",
                action: .enterFlow(account), actionTitle: isPension ? "Enter contributions" : "Enter new money")
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
                lead: "Yes: retiring now works in ", emphasis: confidenceWords(headline.confidence),
                trail: " simulated futures.")
        }
        guard let age = headline.earliestAge else {
            return CheckInAnswer(
                lead: "Not yet: no retirement age in the plan works in \(confidenceWords(headline.confidence)) "
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
        let span = "\(years) year\(years == 1 ? "" : "s")"
        return age < before ? ", \(span) earlier than in \(month)." : ", \(span) later than in \(month)."
    }

    /// A confidence level in words: 0.9 is "9 of 10", 0.95 "19 of 20".
    static func confidenceWords(_ confidence: Double) -> String {
        for scale in [10, 20, 100] {
            let count = confidence * Double(scale)
            if abs(count - count.rounded()) < 0.001 { return "\(Int(count.rounded())) of \(scale)" }
        }
        return "\(Int((confidence * 100).rounded())) of 100"
    }

    /// The answer recorded at the check-in before `date` for the main plan.
    static func previousHeadline(before date: CalendarDate, in library: Library) -> Headline? {
        guard let main = library.settings.mainPlan else { return nil }
        return library.headlines(for: main).last { $0.date < date }
    }
}
