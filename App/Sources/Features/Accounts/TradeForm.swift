import Foundation
import Model
import Tracker

// The Add/Edit Trade sheet's fields and rules (UI.md, "Add Trade"): which
// fields a type shows, reading what's typed (`AmountInput`), the amount
// worked out live, checks (`Trade.problems`), and what saving will change
// (the `Library.addTrade` / `updateTrade` previews). Plain values, so they
// can be checked on Linux.

/// What the trade editor opens on: a trade to edit, or a new one with
/// what's known already (the check-in's date, a statement's instrument).
struct TradeEditorTarget: Hashable, Sendable, Identifiable {
    var account: AccountID
    /// The trade to edit; `nil` for a new one.
    var trade: TradeKey?
    /// A new trade's date; today when `nil`.
    var date: CalendarDate?
    /// A new trade's type; a buy when `nil`.
    var type: TradeType?
    /// A new trade's instrument.
    var instrument: InstrumentID?

    init(account: AccountID, trade: TradeKey? = nil, date: CalendarDate? = nil, type: TradeType? = nil,
         instrument: InstrumentID? = nil) {
        self.account = account
        self.trade = trade
        self.date = date
        self.type = type
        self.instrument = instrument
    }

    /// Opens `key` in the editor.
    static func editing(_ key: TradeKey) -> TradeEditorTarget {
        TradeEditorTarget(account: key.account, trade: key)
    }

    var id: String {
        if let trade { return "edit \(trade)" }
        return "new \(account) \(date?.description ?? "") \(type?.rawValue ?? "") \(instrument?.rawValue ?? "")"
    }
}

/// A field of the trade editor.
enum TradeFormField: String, Hashable, Sendable, CaseIterable {
    case instrument, quantity, price, currency, fees, tax, amount, cost, ratio

    /// The field's label for `type`: "Price", "Received", "Ratio", …
    func title(for type: TradeType) -> String {
        switch self {
        case .instrument: "Instrument"
        case .quantity: type == .dividend ? "Units" : "Quantity"
        case .price: type == .dividend ? "Per unit" : "Price"
        case .currency: "Currency"
        case .fees: "Fees"
        case .tax: type == .buy ? "Transaction tax" : (type == .tax ? "Tax" : "Tax withheld")
        case .amount: TradeForm.amountTitle(for: type)
        case .cost: "Purchase cost"
        case .ratio: "Ratio"
        }
    }
}

/// Something that stops saving (an error) or is worth a look (a warning),
/// on a field when it concerns one.
struct TradeFormProblem: Hashable, Sendable, Identifiable {
    var field: TradeFormField?
    var message: String
    var isError: Bool

    var id: String { "\(field?.rawValue ?? "-") \(message)" }
}

/// The trade editor's fields while a trade is added or edited.
struct TradeForm: Hashable, Sendable {
    let account: AccountID
    /// The account's currency: amounts, fees, taxes and costs are in it.
    let accountCurrency: CurrencyCode
    /// The trade being edited; `nil` for a new one.
    let original: Trade?
    private(set) var type: TradeType
    var date: CalendarDate
    var instrument: InstrumentID?
    var quantity = ""
    var price = ""
    /// The price's currency when chosen; `nil` follows the instrument's (or the account's).
    var currency: CurrencyCode?
    var fees = ""
    var tax = ""
    /// The amount typed, as a positive amount for the types whose
    /// direction is fixed (a buy's "Paid", a withdrawal's amount); empty
    /// for a buy or sell means worked out from quantity × price.
    var amount = ""
    var cost = ""
    var ratio = ""
    var note = ""
    /// Whether a buy, fee or tax was paid from outside the account, or a
    /// sale's proceeds left it (`"settlement": "external"`, docs/TRADES.md).
    /// Only a type that can be (``Model/TradeType/canSettleExternally``)
    /// writes it. A new trade starts from the account's default
    /// (``Model/Library/defaultSettlement(for:in:)``): on for a metals
    /// account and one that has never held cash.
    var paidOutside = false

    /// A new trade from `target`, or the trade it points to. `nil` when the
    /// account, or the trade to edit, isn't in `library`.
    init?(target: TradeEditorTarget, library: Library, today: CalendarDate = .today(), locale: Locale = .current) {
        guard let account = library.accounts[target.account] else { return nil }
        if let key = target.trade {
            guard let trade = library.trade(key) else { return nil }
            self.init(editing: trade, accountCurrency: account.currency, locale: locale)
            return
        }
        // The instrument asked for, else the one traded last.
        let instrument = target.instrument
            ?? library.trades(for: account.id).last(where: { $0.instrument != nil })?.instrument
        self.init(account: account, type: target.type ?? .buy, date: target.date ?? today, instrument: instrument)
        paidOutside = library.defaultSettlement(for: .buy, in: account.id) == .external
    }

    /// A new, empty trade.
    init(account: Account, type: TradeType, date: CalendarDate, instrument: InstrumentID?) {
        self.account = account.id
        accountCurrency = account.currency
        original = nil
        self.type = type
        self.date = date
        self.instrument = instrument
    }

    /// The fields of `trade`.
    init(editing trade: Trade, accountCurrency: CurrencyCode, locale: Locale = .current) {
        account = trade.account
        self.accountCurrency = accountCurrency
        original = trade
        type = trade.type
        date = trade.date
        instrument = trade.instrument
        func text(_ value: Decimal?, digits: Int = 8) -> String {
            value.map { AmountInput.text(for: $0, maxDigits: digits, locale: locale) } ?? ""
        }
        quantity = text(trade.quantity)
        price = text(trade.price)
        currency = trade.currency
        fees = text(trade.fees, digits: 2)
        tax = text(trade.tax, digits: 2)
        let shown = trade.amount.map { Self.amountSign(for: trade.type) == .asTyped ? $0 : abs($0) }
        amount = text(shown, digits: 2)
        cost = text(trade.cost, digits: 2)
        ratio = text(trade.ratio)
        note = trade.note ?? ""
        paidOutside = trade.settlement == .external
    }

    var isNew: Bool { original == nil }

    /// The type; setting it keeps the fields the new type shares.
    var chosenType: TradeType {
        get { type }
        set { type = newValue }
    }

    /// The date as a `Date` (noon, this device's time zone), for a date picker.
    var dateValue: Date {
        get { date.dateValue }
        set { date = CalendarDate(newValue, in: .current) }
    }

    // MARK: Fields

    /// The fields a type shows, in order.
    static func baseFields(for type: TradeType) -> [TradeFormField] {
        switch type {
        case .buy, .sell: [.instrument, .quantity, .price, .currency, .fees, .tax, .amount]
        case .dividend: [.instrument, .amount, .tax, .fees]
        case .interest: [.amount, .tax]
        case .fee, .tax, .deposit, .withdrawal: [.amount]
        case .transferIn: [.instrument, .quantity, .cost, .fees]
        case .opening: [.instrument, .quantity, .cost]
        case .transferOut: [.instrument, .quantity, .fees]
        case .split: [.instrument, .ratio]
        default: [.instrument, .quantity, .price, .currency, .amount]
        }
    }

    /// The fields shown: the type's, and any other the trade being edited
    /// has (e.g. an imported dividend's units and rate per unit), so editing
    /// never drops what's there.
    var fields: [TradeFormField] {
        var fields = Self.baseFields(for: type)
        guard let original, original.type == type else { return fields }
        var present: [TradeFormField] = []
        if original.instrument != nil { present.append(.instrument) }
        if original.quantity != nil { present.append(.quantity) }
        if original.price != nil { present += [.price, .currency] }
        if original.currency != nil { present.append(.currency) }
        if original.fees != nil { present.append(.fees) }
        if original.tax != nil { present.append(.tax) }
        if original.amount != nil { present.append(.amount) }
        if original.cost != nil { present.append(.cost) }
        if original.ratio != nil { present.append(.ratio) }
        for field in TradeFormField.allCases where present.contains(field) && !fields.contains(field) {
            fields.append(field)
        }
        return fields
    }

    func shows(_ field: TradeFormField) -> Bool { fields.contains(field) }

    // MARK: Paid from outside

    /// Whether the type offers "Paid from outside this account" (a buy, fee
    /// or tax) or "Proceeds leave this account" (a sale).
    var showsSettlement: Bool { type.canSettleExternally }

    /// Whether the trade as typed is paid from or into another account.
    var isSettledOutside: Bool { paidOutside && showsSettlement }

    /// The switch's label: "Paid from outside this account", or for a
    /// sale "Proceeds leave this account".
    var settlementTitle: String {
        type == .sell ? "Proceeds leave this account" : "Paid from outside this account"
    }

    /// What the switch means, when it's on.
    var settlementExplanation: String? {
        guard isSettledOutside else { return nil }
        return type == .sell
            ? "The proceeds went to another account, e.g. your bank: this account's cash doesn't change, and they "
                + "count as money taken out."
            : "Paid from another account, e.g. your bank: this account's cash doesn't change, and what it cost "
                + "counts as money added."
    }

    /// The amount section's footer.
    var amountFooter: String {
        switch type {
        case .buy:
            isSettledOutside
                ? "What was paid, fees and tax included." : "What the account's cash went down by, fees and tax included."
        case .sell:
            isSettledOutside
                ? "What was received, after fees and tax." : "What the account's cash went up by, after fees and tax."
        case .dividend, .interest: "What was paid into the account, after tax withheld and fees."
        case .withdrawal: "What was taken out of the account."
        case .deposit: "What was paid into the account."
        default: isSettledOutside ? "What was paid." : "What the account's cash changed by."
        }
    }

    /// "Cash would go to −1.200,00 €. Paid from outside this account?":
    /// for a buy, fee or tax paid from the account's cash that leaves it
    /// below zero on the trade's day (`preview`), with a switch to turn it
    /// into one paid from outside. `nil` otherwise.
    func negativeCashHint(_ preview: TradeFormPreview?, locale: Locale = .current) -> String? {
        guard showsSettlement, type != .sell, !paidOutside, let preview, let effect = preview.cashEffect, effect < 0,
              let cash = preview.cashAfter, cash < 0
        else { return nil }
        return "Cash would go to " + AmountFormat.amount(cash, currency: accountCurrency, precision: .cents,
                                                         locale: locale)
            + ". Paid from outside this account?"
    }

    // MARK: The amount

    /// How the amount typed becomes the signed cash effect.
    enum AmountSign: Hashable, Sendable {
        /// Money out: recorded negative (a buy, a fee, a tax, a withdrawal).
        case negative
        /// Money in: recorded positive (a sale, a deposit).
        case positive
        /// As typed: positive is received (dividends, interest charged is negative).
        case asTyped
    }

    static func amountSign(for type: TradeType) -> AmountSign {
        switch type {
        case .buy, .fee, .tax, .withdrawal: .negative
        case .sell, .deposit: .positive
        default: .asTyped
        }
    }

    /// "Paid", "Received", "Charged", "Amount".
    static func amountTitle(for type: TradeType) -> String {
        switch type {
        case .buy: "Paid"
        case .sell: "Received"
        case .dividend, .interest: "Received"
        case .fee, .tax: "Charged"
        default: "Amount"
        }
    }

    /// Whether the amount is worked out from the other fields when left empty.
    var amountIsComputed: Bool {
        type == .buy || type == .sell || ((type == .dividend || type == .interest) && shows(.quantity))
    }

    /// The price's currency: chosen, else the instrument's, else the account's.
    func priceCurrency(in library: Library) -> CurrencyCode {
        currency ?? defaultPriceCurrency(in: library)
    }

    /// The currency a price is in when none is chosen: the instrument's, else the account's.
    func defaultPriceCurrency(in library: Library) -> CurrencyCode {
        instrument.flatMap { library.instruments[$0]?.currency } ?? accountCurrency
    }

    /// The rate that converts the price into the account's currency on the
    /// date; `nil` when none is needed, or none is known.
    func fxQuote(in library: Library, valuator: Valuator) -> FXQuote? {
        let from = priceCurrency(in: library)
        guard from != accountCurrency else { return nil }
        return valuator.fx.quote(from: from, to: accountCurrency, on: date)
    }

    /// Whether the price needs a rate that isn't known on or before the date.
    func isMissingRate(in library: Library, valuator: Valuator) -> Bool {
        priceCurrency(in: library) != accountCurrency && fxQuote(in: library, valuator: valuator) == nil
    }

    /// The cash effect worked out from quantity × price (converted at the
    /// date's rate), fees and tax, as the ledger does (docs/TRADES.md,
    /// "Types"): −(gross + fees + tax) for a buy, gross − fees − tax for a
    /// sale or income. `nil` when it can't be.
    func computedAmount(in library: Library, valuator: Valuator, locale: Locale = .current) -> Decimal? {
        let fees = Self.parse(fees, locale: locale).value ?? 0
        let tax = Self.parse(tax, locale: locale).value ?? 0
        switch type {
        case .buy, .sell, .dividend, .interest:
            guard shows(.quantity), let quantity = Self.parse(quantity, locale: locale).value,
                  let price = Self.parse(price, locale: locale).value
            else { return nil }
            var gross = quantity * price
            if priceCurrency(in: library) != accountCurrency {
                guard let quote = fxQuote(in: library, valuator: valuator) else { return nil }
                gross = quote.convert(gross)
            }
            // To cents, as the ledger rounds.
            gross = gross.rounded(scale: 2)
            return type == .buy ? -(gross + fees + tax) : gross - fees - tax
        default:
            return nil
        }
    }

    /// The amount typed, signed for the type; `nil` when empty or unreadable.
    func typedAmount(locale: Locale = .current) -> Decimal? {
        guard let value = Self.parse(amount, locale: locale).value else { return nil }
        switch Self.amountSign(for: type) {
        case .negative: return -abs(value)
        case .positive: return abs(value)
        case .asTyped: return value
        }
    }

    /// The cash effect the trade will have: the amount typed, else the one worked out.
    func effectiveAmount(in library: Library, valuator: Valuator, locale: Locale = .current) -> Decimal? {
        typedAmount(locale: locale) ?? computedAmount(in: library, valuator: valuator, locale: locale)
            ?? cashOnlyAmount(locale: locale)
    }

    /// The cash effect of a type without an amount that's worked out from
    /// its fees or tax alone (a fee, a tax, a transfer's fees).
    private func cashOnlyAmount(locale: Locale) -> Decimal? {
        let fees = Self.parse(fees, locale: locale).value
        let tax = Self.parse(tax, locale: locale).value
        switch type {
        case .fee, .tax, .transferIn, .transferOut, .opening:
            guard fees != nil || tax != nil else { return type == .fee || type == .tax ? nil : 0 }
            return -((fees ?? 0) + (tax ?? 0))
        case .split:
            return 0
        default:
            return nil
        }
    }

    /// The amount field's placeholder: the amount worked out, as a positive
    /// amount for the fixed directions; "Amount" otherwise.
    func amountPrompt(in library: Library, valuator: Valuator, locale: Locale = .current) -> String {
        guard let computed = computedAmount(in: library, valuator: valuator, locale: locale) else {
            return type == .buy || type == .sell ? "Worked out" : "0"
        }
        let shown = Self.amountSign(for: type) == .asTyped ? computed : abs(computed)
        return AmountInput.text(for: shown, maxDigits: 2, locale: locale)
    }

    /// The line under the amount: "computed from quantity × price, fees and
    /// tax"; with a rate, "at 1,1398 USD per EUR on 30 Sep"; for a typed
    /// amount that differs, what was worked out. `nil` where there's nothing to say.
    func amountHint(in library: Library, valuator: Valuator, locale: Locale = .current) -> String? {
        guard amountIsComputed else { return nil }
        let computed = computedAmount(in: library, valuator: valuator, locale: locale)
        let from = priceCurrency(in: library)
        if typedAmount(locale: locale) != nil {
            guard let computed, computed != typedAmount(locale: locale) else { return "Typed; it matches the computed amount." }
            let shown = Self.amountSign(for: type) == .asTyped ? computed : abs(computed)
            return "Typed; computed would be \(AmountFormat.number(shown, maxDigits: 2, locale: locale)). The typed "
                + "amount wins, e.g. for the broker's rate or rounding."
        }
        if from != accountCurrency {
            guard let quote = fxQuote(in: library, valuator: valuator) else {
                return "There's no \(from.rawValue)→\(accountCurrency.rawValue) rate on or before this date: type "
                    + "the amount the broker charged."
            }
            let rate = AmountFormat.number(quote.rate, maxDigits: 6, locale: locale)
            return "Computed at 1 \(from.rawValue) = \(rate) \(accountCurrency.rawValue); type the broker's amount "
                + "if it differs."
        }
        return computed == nil ? "Computed from quantity × price, fees and tax." : "Computed; type the broker's "
            + "amount if it differs."
    }

    // MARK: The price

    /// The library's price for the instrument on the date, or the latest before it.
    func libraryPrice(valuator: Valuator) -> PriceRecord? {
        guard let instrument else { return nil }
        return valuator.prices.latest(for: instrument, onOrBefore: date)
    }

    /// "The library's price that day: 102,30 €", or "The latest price before
    /// it, 30 Sep 2026: 138,42 €".
    static func priceHint(_ record: PriceRecord, date: CalendarDate, locale: Locale = .current) -> String {
        let price = QuantityFormat.unitPrice(record.price, currency: record.currency, locale: locale)
        if record.date == date { return "The library's price that day: \(price)" }
        return "The latest price before it, \(AmountFormat.mediumDate(record.date, locale: locale)): \(price)"
    }

    /// Fills the price (and its currency) from `record`.
    mutating func usePrice(_ record: PriceRecord, in library: Library, locale: Locale = .current) {
        price = AmountInput.text(for: record.price, maxDigits: 6, locale: locale)
        currency = record.currency == defaultPriceCurrency(in: library) ? nil : record.currency
    }

    // MARK: Checks

    /// Typed numbers that can't be read, on their fields.
    func inputProblems(locale: Locale = .current) -> [TradeFormProblem] {
        let texts: [(TradeFormField, String)] = [
            (.quantity, quantity), (.price, price), (.fees, fees), (.tax, tax), (.amount, amount), (.cost, cost),
            (.ratio, ratio),
        ]
        return texts.compactMap { field, text in
            guard shows(field), Self.parse(text, locale: locale) == .unreadable else { return nil }
            return TradeFormProblem(field: field, message: "The \(field.title(for: type).lowercased()) can't be read.",
                                    isError: true)
        }
    }

    /// What's wrong: numbers that can't be read, then what the trade on its
    /// own is missing or gets wrong (``Model/Trade/problems``), by field.
    func problems(in library: Library, locale: Locale = .current) -> [TradeFormProblem] {
        let input = inputProblems(locale: locale)
        guard input.isEmpty, let trade = trade(in: library, locale: locale) else { return input }
        return trade.problems.map { problem in
            TradeFormProblem(field: problem.field.flatMap(Self.field(named:)), message: problem.message,
                             isError: problem.severity == .error)
        }
    }

    /// Whether the trade can be saved: everything reads, and nothing it
    /// needs is missing.
    func canSave(in library: Library, locale: Locale = .current) -> Bool {
        trade(in: library, locale: locale) != nil && !problems(in: library, locale: locale).contains(where: \.isError)
    }

    /// The problems concerning `field`.
    func problems(for field: TradeFormField, in library: Library, locale: Locale = .current) -> [TradeFormProblem] {
        problems(in: library, locale: locale).filter { $0.field == field }
    }

    // MARK: The trade

    /// The trade as typed; `nil` while a number can't be read. Only the
    /// fields its type shows are written. Its ID stays when it's edited;
    /// its source becomes `manual` when something changed.
    func trade(in library: Library, locale: Locale = .current) -> Trade? {
        guard inputProblems(locale: locale).isEmpty else { return nil }
        func value(_ field: TradeFormField, _ text: String) -> Decimal? {
            shows(field) ? Self.parse(text, locale: locale).value : nil
        }
        var trade = Trade(account: account, date: date, id: original?.id ?? .random(), type: type)
        if shows(.instrument) { trade.instrument = instrument }
        trade.quantity = value(.quantity, quantity)
        trade.price = value(.price, price)
        if trade.price != nil, let currency, currency != defaultPriceCurrency(in: library) || original?.currency == currency {
            trade.currency = currency
        }
        trade.fees = value(.fees, fees)
        trade.tax = value(.tax, tax)
        if shows(.amount) { trade.amount = typedAmount(locale: locale) }
        trade.cost = value(.cost, cost)
        trade.ratio = value(.ratio, ratio)
        if showsSettlement {
            // Paid from outside, else as written (an explicit "account", or a value a newer app wrote).
            trade.settlement = paidOutside ? .external : original?.settlement.flatMap { $0 == .external ? nil : $0 }
        }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        trade.note = trimmedNote.isEmpty ? nil : trimmedNote
        if let original {
            var unchanged = original
            unchanged.note = trade.note
            unchanged.source = nil
            trade.source = trade == unchanged ? original.source : .manual
        } else {
            trade.source = .manual
        }
        return trade
    }

    /// What saving will do (the `Library.addTrade` / `updateTrade`
    /// previews), and what the account holds after it; `nil` while the
    /// trade can't be read.
    func preview(in library: Library, locale: Locale = .current) -> TradeFormPreview? {
        guard let trade = trade(in: library, locale: locale) else { return nil }
        var after = library
        let edit = original.map { after.updateTrade(trade, replacing: $0.key) } ?? after.addTrade(trade)
        let valuator = Valuator(library: after)
        let saved = edit.saved ?? trade
        let entry = valuator.ledger(for: account)?.entries.first { $0.trade.key == saved.key }
        return TradeFormPreview(
            edit: edit, instrument: saved.instrument,
            quantityAfter: saved.type.changesHoldings ? entry?.quantityAfter : nil,
            cashEffect: entry?.cashEffect, isSettledOutside: saved.isSettledExternally,
            newMoney: entry?.externalFlow, realizedGain: entry?.realizedGain,
            cashAfter: valuator.tradeCash(of: account, on: saved.date),
            newIssues: edit.newIssues.filter { $0.kind != .reconciliation }
                .compactMap { TradeIssueNote.note(for: $0, library: after, locale: locale) }
                + Self.newMismatches(edit, library: after, locale: locale))
    }

    /// Statements that differ from the trades since the edit, and didn't before.
    private static func newMismatches(_ edit: TradeEdit, library: Library, locale: Locale) -> [TradeIssueNote] {
        let issues = edit.newIssues.filter { $0.kind == .reconciliation }
        guard let account = issues.first?.account else { return [] }
        let mismatches = Valuator(library: library).reconciliation(of: account)
        return issues.compactMap { issue in
            mismatches.first { $0.date == issue.date && $0.instrument == issue.instrument }
                .map { TradeIssueNote.note(for: $0, library: library, locale: locale) }
        }
    }

    // MARK: Internals

    /// A number typed in a field.
    enum Parsed: Hashable, Sendable {
        case empty
        case value(Decimal)
        case unreadable

        var value: Decimal? {
            if case .value(let value) = self { value } else { nil }
        }
    }

    static func parse(_ text: String, locale: Locale = .current) -> Parsed {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .empty }
        return AmountInput.decimal(from: trimmed, locale: locale).map(Parsed.value) ?? .unreadable
    }

    /// The form field of a ``Model/TradeProblem``'s field name.
    static func field(named name: String) -> TradeFormField? {
        TradeFormField(rawValue: name)
    }
}

/// What saving a trade will do, for the editor to show before saving.
struct TradeFormPreview: Hashable, Sendable {
    var edit: TradeEdit
    var instrument: InstrumentID?
    /// The quantity of the instrument held after the trade's day; `nil` for
    /// trades that don't change holdings.
    var quantityAfter: Decimal?
    /// What the account's cash changes by; `nil` when it can't be worked out.
    var cashEffect: Decimal?
    /// Whether the trade is paid from or into another account: the cash
    /// doesn't change, and ``newMoney`` is what it adds or takes out.
    var isSettledOutside = false
    /// For a trade paid from outside the account: the money it adds (a
    /// buy's cost) or takes out (a sale's proceeds); `nil` otherwise.
    var newMoney: Decimal?
    /// A sale's realised gain, when known.
    var realizedGain: Decimal?
    /// The account's cash at the end of the trade's date, after the edit.
    var cashAfter: Decimal?
    /// Problems the edit brings in, e.g. a later sale now taking away more than is held.
    var newIssues: [TradeIssueNote]

    /// The follow-on effects in words: the opening date moving, and the new
    /// money of later values worked out again or kept.
    func notes(account: Account?, locale: Locale = .current) -> [String] {
        TradeEditNotes.sentences(edit, account: account, locale: locale)
    }
}

/// What a trade edit does besides writing the trade, in words.
enum TradeEditNotes {
    /// "Saving moves the account's opening date from 1 Mar 2021 to 15 Feb
    /// 2021.", then what happens to the new money of later values.
    static func sentences(_ edit: TradeEdit, account: Account?, locale: Locale = .current) -> [String] {
        var sentences: [String] = []
        if let from = edit.movedOpeningFrom, let to = edit.saved?.date {
            sentences.append("Saving moves the account's opening date from \(AmountFormat.mediumDate(from, locale: locale)) "
                + "to \(AmountFormat.mediumDate(to, locale: locale)).")
        }
        if let flows = AccountValueNotes.flowFollowUp(edit.flows, locale: locale) {
            sentences.append(flows)
        }
        return sentences
    }

    /// What deleting `key` does: the new money of later values, and the
    /// problems it brings in (e.g. a later sale now taking away more than
    /// is held). Empty when nothing else changes.
    static func removal(of key: TradeKey, in library: Library, locale: Locale = .current) -> [String] {
        var after = library
        let edit = after.removeTrade(key)
        var sentences: [String] = []
        if let flows = AccountValueNotes.flowFollowUp(edit.flows, locale: locale) {
            sentences.append(flows.replacingOccurrences(of: "Saving also", with: "Deleting it also"))
        }
        for issue in edit.newIssues where issue.kind != .reconciliation {
            if let note = TradeIssueNote.note(for: issue, library: after, locale: locale) {
                sentences.append(note.message)
            }
        }
        return sentences
    }
}
