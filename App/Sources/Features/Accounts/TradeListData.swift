import Foundation
import Glance
import Model
import Tracker

// An account that records its trades (docs/TRADES.md; UI.md, "Account
// detail" for trades accounts): its trades by month, its holdings with
// average cost and share, its income and gains by year, and what's wrong
// with its trades in plain words. Plain values, so they can be checked on
// Linux.

// MARK: - Trade types

/// How a trade type reads and looks.
enum TradeTypeDisplay {
    /// The types the Add Trade sheet's segmented control offers.
    static let primary: [TradeType] = [.buy, .sell, .dividend]

    /// The types under *More*, in the order they're listed.
    static let more: [TradeType] = [
        .interest, .fee, .tax, .deposit, .withdrawal, .transferIn, .transferOut, .split, .opening,
    ]

    /// "Buy", "Transfer in", …; the raw value for a type this version doesn't know.
    static func name(_ type: TradeType) -> String {
        switch type {
        case .buy: "Buy"
        case .sell: "Sell"
        case .dividend: "Dividend"
        case .interest: "Interest"
        case .fee: "Fee"
        case .tax: "Tax"
        case .deposit: "Deposit"
        case .withdrawal: "Withdrawal"
        case .transferIn: "Transfer in"
        case .transferOut: "Transfer out"
        case .split: "Split"
        case .opening: "Opening"
        default: type.rawValue
        }
    }

    /// The SF Symbol of the type.
    static func systemImage(_ type: TradeType) -> String {
        switch type {
        case .buy: "plus.circle"
        case .sell: "minus.circle"
        case .dividend: "banknote"
        case .interest: "percent"
        case .fee: "creditcard"
        case .tax: "building.columns"
        case .deposit: "arrow.down.circle"
        case .withdrawal: "arrow.up.circle"
        case .transferIn: "arrow.right.circle"
        case .transferOut: "arrow.left.circle"
        case .split: "arrow.triangle.branch"
        case .opening: "flag"
        default: "questionmark.circle"
        }
    }

    /// What the type does, in one line, for the *More* menu and the sheet.
    static func explanation(_ type: TradeType) -> String {
        switch type {
        case .buy: "Units bought with the account's cash, or paid from outside it."
        case .sell: "Units sold for cash, kept in the account or paid out."
        case .dividend: "A dividend or distribution paid in cash."
        case .interest: "Interest paid on the account's cash."
        case .fee: "A fee charged on its own, e.g. a custody fee."
        case .tax: "A tax charged on its own, e.g. imposta di bollo."
        case .deposit: "Money paid into the account."
        case .withdrawal: "Money taken out of the account."
        case .transferIn: "Units moved in from another account or broker, with what they cost."
        case .transferOut: "Units moved out to another account or broker."
        case .split: "A split or reverse split: the quantity is multiplied by the ratio."
        case .opening: "A holding on the day the account's history starts, with what it cost."
        default: "A type this version of the app doesn't know: only its amount counts."
        }
    }
}

// MARK: - Words for trades

/// The words a trade reads as: in lists, issues and the editor.
enum TradeWording {
    /// The short name of an instrument: its ticker, a crypto's unit, else its name.
    static func instrumentLabel(_ id: InstrumentID, in library: Library) -> String {
        CheckInWording.instrumentLabel(id, instrument: library.instruments[id])
    }

    /// What a trade was, without its price: "Buy 0,10383916 BTC", "Sell 8,5
    /// VWCE", "Dividend VWCE", "Deposit", "Split VWCE × 2", "Opening 338
    /// VWCE". Quantities read as everywhere (``QuantityFormat``).
    static func title(of trade: Trade, in library: Library, locale: Locale = .current) -> String {
        var parts = [TradeTypeDisplay.name(trade.type)]
        let label = trade.instrument.map { instrumentLabel($0, in: library) }
        if trade.type == .split {
            if let label {
                parts.append(label + (trade.ratio.map { " × " + AmountFormat.number($0, maxDigits: 6, locale: locale) } ?? ""))
            }
            return parts.joined(separator: " ")
        }
        if let quantity = trade.quantity { parts.append(QuantityFormat.quantity(quantity, locale: locale)) }
        if let label { parts.append(label) }
        return parts.joined(separator: " ")
    }

    /// A trade's unit price in its own currency, with the currency's symbol
    /// (``QuantityFormat/unitPrice(_:currency:locale:)``): "101.437,76 €",
    /// "165,00 $". `nil` without a quantity and a price.
    static func price(of trade: Trade, in library: Library, locale: Locale = .current) -> String? {
        guard let price = trade.price, trade.quantity != nil, trade.type != .split else { return nil }
        return QuantityFormat.unitPrice(price, currency: priceCurrency(of: trade, in: library), locale: locale)
    }

    /// The whole trade on one line: "Buy 10 VWCE at 134,75 €", "Deposit".
    static func summary(of trade: Trade, in library: Library, locale: Locale = .current) -> String {
        let title = title(of: trade, in: library, locale: locale)
        return price(of: trade, in: library, locale: locale).map { title + " at " + $0 } ?? title
    }

    /// The line under a trade's title in the list: "at 101.437,76 € · 1 Oct
    /// 2025 · note"; the date and note alone without a price.
    static func subtitle(of trade: Trade, in library: Library, locale: Locale = .current) -> String {
        [price(of: trade, in: library, locale: locale).map { "at " + $0 },
         AmountFormat.mediumDate(trade.date, locale: locale), trade.note]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// The currency of a trade's price: as written, else the instrument's, else the account's.
    static func priceCurrency(of trade: Trade, in library: Library) -> CurrencyCode {
        trade.priceCurrency(instruments: library.instruments,
                            accountCurrency: library.accounts[trade.account]?.currency ?? library.settings.baseCurrency)
    }

    /// "paid from outside" for a buy, fee or tax paid from another account,
    /// "proceeds paid out" for a sale whose proceeds left it; `nil` for
    /// other trades.
    static func settlementLabel(of trade: Trade) -> String? {
        guard trade.isSettledExternally else { return nil }
        return trade.type == .sell ? "proceeds paid out" : "paid from outside"
    }

    /// "the buy of VWCE on 12 Mar 2026", for sentences.
    static func phrase(_ trade: Trade, in library: Library, locale: Locale = .current) -> String {
        let what = trade.instrument.map { " of " + instrumentLabel($0, in: library) } ?? ""
        return "the \(TradeTypeDisplay.name(trade.type).lowercased())\(what) on "
            + AmountFormat.mediumDate(trade.date, locale: locale)
    }
}

// MARK: - The list of trades

/// One trade in the account's list.
struct TradeListItem: Hashable, Sendable, Identifiable {
    var trade: Trade
    /// "Buy 10 VWCE" (``TradeWording/title(of:in:locale:)``).
    var title: String
    /// "at 102,30 € · 12 Mar 2026 · note" (``TradeWording/subtitle(of:in:locale:)``).
    var subtitle: String
    /// The unit price in its currency, "102,30 €"; `nil` without one (the
    /// Mac table's Price column).
    var priceText: String?
    /// The instrument's short name, if the trade has one.
    var instrumentLabel: String?
    /// What the trade paid or brought in, in the account's currency, as
    /// the ledger applied it: the amount written, or worked out. It's what
    /// the account's cash changed by, unless it was paid from or into
    /// another account (``settlementLabel``). `nil` when it can't be worked out.
    var amount: Decimal?
    /// "paid from outside", "proceeds paid out": a trade that didn't change
    /// the account's cash (``TradeWording/settlementLabel(of:)``).
    var settlementLabel: String?
    /// For a sale: its realised gain, when known.
    var realizedGain: Decimal?
    /// Whether a check found something wrong with it.
    var hasIssue: Bool

    var id: TradeKey { trade.key }
    var date: CalendarDate { trade.date }
    var type: TradeType { trade.type }
}

/// The trades of one month, newest first.
struct TradeMonthSection: Hashable, Sendable, Identifiable {
    var month: YearMonth
    var items: [TradeListItem]

    var id: YearMonth { month }

    /// "September 2026".
    func title(locale: Locale = .current) -> String {
        GlanceText.monthAndYear(month.lastDay, locale: locale)
    }
}

/// What the list shows: every trade, or one instrument's, or one type's.
struct TradeListFilter: Hashable, Sendable {
    var instrument: InstrumentID?
    var type: TradeType?

    init(instrument: InstrumentID? = nil, type: TradeType? = nil) {
        self.instrument = instrument
        self.type = type
    }

    var isActive: Bool { instrument != nil || type != nil }

    func includes(_ trade: Trade) -> Bool {
        (instrument.map { trade.instrument == $0 } ?? true) && (type.map { trade.type == $0 } ?? true)
    }
}

/// A choice in the list's filter menu.
struct TradeFilterOption<Value: Hashable & Sendable>: Hashable, Sendable, Identifiable {
    var value: Value
    var name: String
    var id: Value { value }
}

/// An account's trades by month, newest first, filtered (UI.md, "Account
/// detail": the trades list).
struct TradeList: Hashable, Sendable {
    var sections: [TradeMonthSection]
    /// The instruments the account's trades concern, by name.
    var instruments: [TradeFilterOption<InstrumentID>]
    /// The types among the account's trades, in the sheet's order.
    var types: [TradeFilterOption<TradeType>]
    /// How many trades the account has, and how many the filter shows.
    var totalCount: Int
    var shownCount: Int

    /// Every trade shown, newest first (the Mac table's rows).
    var items: [TradeListItem] { sections.flatMap(\.items) }

    var isEmpty: Bool { totalCount == 0 }

    init(account: AccountID, library: Library, valuator: Valuator, filter: TradeListFilter = TradeListFilter(),
         locale: Locale = .current) {
        let entries = valuator.ledger(for: account)?.entries ?? []
        let flagged = Set(valuator.tradeIssues(for: account).filter { $0.severity == .error }.compactMap(\.trade))
        // Newest first: the reverse of the order they apply in.
        let items = entries.reversed().filter { filter.includes($0.trade) }.map { entry in
            TradeListItem(
                trade: entry.trade, title: TradeWording.title(of: entry.trade, in: library, locale: locale),
                subtitle: TradeWording.subtitle(of: entry.trade, in: library, locale: locale),
                priceText: TradeWording.price(of: entry.trade, in: library, locale: locale),
                instrumentLabel: entry.trade.instrument.map { TradeWording.instrumentLabel($0, in: library) },
                amount: entry.amount, settlementLabel: TradeWording.settlementLabel(of: entry.trade),
                realizedGain: entry.realizedGain,
                hasIssue: flagged.contains(entry.trade.key))
        }
        var sections: [TradeMonthSection] = []
        for item in items {
            let month = item.date.yearMonth
            if sections.last?.month == month {
                sections[sections.count - 1].items.append(item)
            } else {
                sections.append(TradeMonthSection(month: month, items: [item]))
            }
        }
        self.sections = sections
        let trades = entries.map(\.trade)
        instruments = Set(trades.compactMap(\.instrument))
            .map { TradeFilterOption(value: $0, name: library.instruments[$0]?.name ?? $0.rawValue) }
            .sorted { ($0.name.lowercased(), $0.value) < ($1.name.lowercased(), $1.value) }
        let present = Set(trades.map(\.type))
        let order = TradeTypeDisplay.primary + TradeTypeDisplay.more
        types = (order.filter(present.contains) + present.filter { !order.contains($0) }.sorted())
            .map { TradeFilterOption(value: $0, name: TradeTypeDisplay.name($0)) }
        totalCount = entries.count
        shownCount = items.count
    }
}

// MARK: - Holdings

/// A trades account's holdings card (UI.md, "Account detail"): per
/// instrument its quantity, average cost, value, unrealised gain and share
/// of the account; then cash; then the total. Amounts in the account's
/// currency.
struct TradeHoldings: Hashable, Sendable {
    var rows: [AccountHoldingRow]
    /// The cash by the cash rule (docs/TRADES.md, "Cash").
    var cash: Decimal?
    /// The positions' values and the cash, in the account's currency (what could be valued).
    var total: Decimal
    /// Whether every position has a price (and rate).
    var isComplete: Bool
    /// The positions' purchase costs; `nil` when one is unknown.
    var totalCost: Decimal?

    /// The positions' unrealised gain: their value minus their cost; `nil`
    /// when a cost or value is unknown.
    var totalGain: Decimal? {
        guard let totalCost, isComplete else { return nil }
        return rows.compactMap(\.amount).reduce(0, +) - totalCost
    }

    /// ``totalGain`` as a fraction of the cost.
    var totalGainFraction: Double? {
        guard let totalGain, let totalCost, totalCost != 0 else { return nil }
        return (totalGain / abs(totalCost)).doubleValue
    }

    /// `rows` (from ``Valuator/holdings(of:on:)``) and `cash`, with each
    /// position's share of the total.
    init(rows: [AccountHoldingRow], cash: Decimal?) {
        let known = rows.compactMap(\.amount).reduce(0, +)
        let total = known + (cash ?? 0)
        self.total = total
        self.cash = cash
        isComplete = rows.allSatisfy { $0.amount != nil }
        totalCost = rows.allSatisfy { $0.costBasis != nil } ? rows.compactMap(\.costBasis).reduce(0, +) : nil
        self.rows = rows.map { row in
            var row = row
            if let amount = row.amount, total != 0 { row.share = (amount / total).doubleValue }
            return row
        }
    }

    /// The cash's share of the total.
    var cashShare: Double? {
        guard let cash, total != 0 else { return nil }
        return (cash / total).doubleValue
    }
}

// MARK: - Income and gains

/// One year of a trades account's income and gains (UI.md, "Account
/// detail": the *Income & gains* card), in the account's currency.
struct TradeIncomeYear: Hashable, Sendable, Identifiable {
    struct Line: Hashable, Sendable, Identifiable {
        var name: String
        var amount: Decimal
        /// Whether the amount is money out (fees, taxes), shown with a minus.
        var isCharge: Bool
        var id: String { name }
    }

    var year: Int
    var summary: TradeYearSummary

    var id: Int { year }

    /// Realised gains, dividends, interest, fees and taxes, leaving out
    /// income lines that are zero (the realised gain always shows).
    var lines: [Line] {
        var lines = [Line(name: "Realised gains", amount: summary.realizedGain, isCharge: false)]
        if summary.dividends != 0 { lines.append(Line(name: "Dividends", amount: summary.dividends, isCharge: false)) }
        if summary.interest != 0 { lines.append(Line(name: "Interest", amount: summary.interest, isCharge: false)) }
        if summary.fees != 0 { lines.append(Line(name: "Fees", amount: -summary.fees, isCharge: true)) }
        if summary.taxes != 0 { lines.append(Line(name: "Taxes", amount: -summary.taxes, isCharge: true)) }
        return lines
    }

    /// Gains and income after fees and taxes.
    var net: Decimal {
        summary.realizedGain + summary.dividends + summary.interest - summary.fees - summary.taxes
    }

    /// "1 sale's gain is unknown: its purchase cost isn't." when there are such sales.
    var unknownGainNote: String? {
        let count = summary.salesWithUnknownGain.count
        guard count > 0 else { return nil }
        return count == 1
            ? "1 sale's gain is unknown, so it's left out: its purchase cost isn't known."
            : "\(count) sales' gains are unknown, so they're left out: their purchase costs aren't known."
    }

    /// The years with trades, newest first. From the account's ledger
    /// (``TradeLedger/summary(for:)``), so amounts are in its currency.
    static func years(of account: AccountID, valuator: Valuator) -> [TradeIncomeYear] {
        guard let ledger = valuator.ledger(for: account) else { return [] }
        return ledger.years.reversed().map { TradeIncomeYear(year: $0, summary: ledger.summary(for: $0)) }
    }
}

// MARK: - Issues

/// What a banner about a trades account's issue offers to do.
enum TradeIssueAction: Hashable, Sendable {
    /// Open a trade in the editor.
    case editTrade(TradeKey)
    /// Open the editor on a new trade.
    case addTrade(TradeEditorTarget)
    /// Open a value (a valuation) in the valuation editor.
    case editValuation(ValuationKey)
    /// Open the account's form (its opening and closing dates).
    case editAccount
    /// Convert the account so its trades count.
    case switchToTrades
}

/// Something wrong with an account's trades, in plain words, with the fix
/// (UI.md: calm, and nothing scolds).
struct TradeIssueNote: Hashable, Sendable, Identifiable {
    var id: String
    var isError: Bool
    var title: String
    var message: String
    var actionTitle: String?
    var action: TradeIssueAction?

    /// The notes for `account`: the checks' issues (``Valuator/tradeIssues(for:)``)
    /// and the statements that differ from the trades (``Valuator/reconciliation(of:)``),
    /// by date. Several problems of one trade become one note.
    static func notes(for account: AccountID, library: Library, valuator: Valuator,
                      locale: Locale = .current) -> [TradeIssueNote] {
        var notes: [TradeIssueNote] = []
        var seen: Set<String> = []
        let issues = valuator.tradeIssues(for: account)
        for issue in issues where issue.kind != .reconciliation && issue.kind != .notTradesAccount {
            guard let note = note(for: issue, library: library, locale: locale), !seen.contains(note.id) else {
                continue
            }
            seen.insert(note.id)
            notes.append(note)
        }
        // Left-out trades of an account that doesn't record them: one note for all.
        let ignored = issues.filter { $0.kind == .notTradesAccount }
        if !ignored.isEmpty {
            let count = ignored.count
            notes.append(TradeIssueNote(
                id: "notTradesAccount", isError: false,
                title: count == 1 ? "1 trade is left out" : "\(count) trades are left out",
                message: "This account records monthly snapshots, so its trades don't count. Switch it to trade "
                    + "history to count them.",
                actionTitle: "Switch to Trade History…", action: .switchToTrades))
        }
        for mismatch in valuator.reconciliation(of: account) {
            notes.append(Self.note(for: mismatch, library: library, locale: locale))
        }
        return notes
    }

    /// The note for one issue; `nil` for a trade that no longer exists.
    static func note(for issue: TradeIssue, library: Library, locale: Locale = .current) -> TradeIssueNote? {
        let trade = issue.trade.flatMap { library.trade($0) }
        let id = "\(issue.kind.rawValue).\(issue.trade?.description ?? issue.date.description)"
        let what = trade.map { TradeWording.phrase($0, in: library, locale: locale) } ?? "a trade"
        let day = AmountFormat.mediumDate(issue.date, locale: locale)
        let edit: TradeIssueAction? = issue.trade.map(TradeIssueAction.editTrade)
        let isError = issue.severity == .error
        switch issue.kind {
        case .invalidTrade:
            guard let trade else { return nil }
            let problems = trade.problems.map(\.message)
            let message = problems.isEmpty ? "Its amount can't be worked out." : problems.joined(separator: " ")
            return TradeIssueNote(id: "invalidTrade.\(trade.key)", isError: isError,
                                  title: what.capitalizedFirst + " needs a look", message: message,
                                  actionTitle: "Edit Trade…", action: edit)
        case .oversold:
            return TradeIssueNote(
                id: id, isError: isError, title: "More sold than held",
                message: what.capitalizedFirst + " takes away more than the account held then. Is a buy or "
                    + "an opening missing, or is the date wrong?",
                actionTitle: "Edit Trade…", action: edit)
        case .unknownCost:
            return TradeIssueNote(
                id: id, isError: isError, title: "Purchase cost unknown",
                message: what.capitalizedFirst + " has no cost, so the purchase cost and gains of "
                    + (trade?.instrument.map { TradeWording.instrumentLabel($0, in: library) } ?? "the instrument")
                    + " aren't known. Add its cost (valore di carico) from the statement.",
                actionTitle: "Edit Trade…", action: edit)
        case .missingFX:
            let from = trade.map { TradeWording.priceCurrency(of: $0, in: library).rawValue } ?? "the price's"
            let to = library.accounts[issue.account]?.currency.rawValue ?? "the account's"
            return TradeIssueNote(
                id: id, isError: isError, title: "No \(from)→\(to) rate",
                message: "There's no rate on or before \(day) to convert the price of \(what), so the cash it moved "
                    + "is unknown. Type the amount the broker charged, or add the rate at a check-in.",
                actionTitle: "Edit Trade…", action: edit)
        case .splitNotHeld:
            return TradeIssueNote(
                id: id, isError: isError, title: "A split of what isn't held",
                message: what.capitalizedFirst + " changes nothing: the account doesn't hold it then. Is "
                    + "the date right?",
                actionTitle: "Edit Trade…", action: edit)
        case .outsideAccountDates:
            return TradeIssueNote(
                id: id, isError: isError, title: "Outside the account's dates",
                message: what.capitalizedFirst + " is dated outside the days the account is open, so it "
                    + "counts only from its opening date. Change the trade's date, or the account's dates.",
                actionTitle: "Edit Trade…", action: edit)
        case .balanceIgnored:
            return TradeIssueNote(
                id: id, isError: isError, title: "A balance that isn't used",
                message: "The value on \(day) records a balance, but this account's holdings come from its trades. "
                    + "Record its cash instead; the balance isn't counted.",
                actionTitle: "Edit Value…",
                action: .editValuation(ValuationKey(account: issue.account, date: issue.date)))
        default:
            return TradeIssueNote(id: id, isError: isError, title: "Something to check", message: issue.message,
                                  actionTitle: issue.trade == nil ? nil : "Edit Trade…", action: edit)
        }
    }

    /// "The statement on 30 Jun shows 12 VWCE; your trades give 10. Add the
    /// missing trade." with *Add Trade…* on the statement's date.
    static func note(for mismatch: PositionMismatch, library: Library, locale: Locale = .current) -> TradeIssueNote {
        let label = TradeWording.instrumentLabel(mismatch.instrument, in: library)
        let listed = QuantityFormat.quantity(mismatch.listed, locale: locale)
        let derived = QuantityFormat.quantity(mismatch.derived, locale: locale)
        let fix = mismatch.difference > 0
            ? "Add the missing trade, e.g. a buy or a transfer in."
            : "Add the missing sale or transfer out, or check the statement."
        let target = TradeEditorTarget(account: mismatch.account, date: mismatch.date,
                                       type: mismatch.difference > 0 ? .buy : .sell, instrument: mismatch.instrument)
        return TradeIssueNote(
            id: "reconciliation.\(mismatch.date).\(mismatch.instrument)", isError: false,
            title: "\(label) differs from the statement",
            message: "The statement on \(AmountFormat.shortDate(mismatch.date, locale: locale)) shows \(listed) "
                + "\(label); your trades give \(derived). \(fix)",
            actionTitle: "Add Trade…", action: .addTrade(target))
    }
}
