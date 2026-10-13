import Model

/// A problem with the mapping or the file as a whole, as opposed to one cell,
/// or a note about how the file was read (see ``isNote``).
public struct ImportIssue: Hashable, Sendable, CustomStringConvertible {
    public enum Kind: Hashable, Sendable {
        /// A column the profile doesn't know. It isn't imported until it's mapped.
        case unknownColumn
        /// A column of the profile that the file doesn't have.
        case missingColumn
        /// No column holds the dates.
        case noDateColumn
        /// A column's target needs this field, and neither the column, the
        /// profile's constants nor the header give it.
        case missingField(ImportField)
        /// The date pattern isn't one the importer understands.
        case invalidDatePattern(String)
        /// A quote in this row was never closed; it was read as a literal quote.
        case unterminatedQuote(row: Int)
        /// A closed account has values in the file after the day it closed.
        case valuesAfterClosed(AccountID, closed: CalendarDate)
        /// A note: `count` positive balances of a debt account (a loan,
        /// mortgage or credit card) were read as debts and made negative.
        /// The `liabilitySign` format `asWritten` keeps them as written.
        case positiveDebts(AccountID, count: Int)
        /// A note: `count` positive balances of a debt account were kept
        /// positive (in credit), because the column writes debts as negative
        /// amounts.
        case debtsInCredit(AccountID, count: Int)
        /// Trades layout: `count` rows have a type the mapping doesn't know
        /// (`value`); they're left out until it's mapped.
        case unmappedTradeType(String, count: Int)
        /// A note, trades layout: whether an amount column writes signed
        /// amounts (kept as written) or absolute values (signed by the type).
        case tradeAmountSigns(signed: Bool)
        /// A note, trades layout: `count` negative quantities were made
        /// positive; the type says the direction (without a type column, a
        /// negative quantity is a sell).
        case negativeQuantities(count: Int, byType: Bool)
        /// A note, trades layout: `count` deposits and withdrawals were told
        /// apart by their amount's sign.
        case cashDirectionBySign(count: Int)
        /// A note, trades layout: `count` rows of types mapped to `ignore` were left out.
        case ignoredTradeRows(count: Int)
        /// A brokerage, crypto or metals account that doesn't record trades
        /// (its `valuation` says otherwise): its trades are left out. Only
        /// an account of another kind is offered to switch.
        case accountDoesntRecordTrades(AccountID)
        /// A note: the quantities of an account that records trades became
        /// trades: openings where nothing was held, then a buy or a sale per
        /// change (IMPORT.md, "Quantities in a trades account").
        /// `settledOutside`: the account has never held cash, so its buys
        /// and sales are paid from and into another account.
        case quantitiesAsTrades(AccountID, openings: Int, buys: Int, sales: Int, settledOutside: Bool)
        /// A note: `count` buys or sales made from quantities have no price
        /// on or before their date and no purchase cost, so their amounts are unknown.
        case tradesWithoutPrice(AccountID, count: Int)
        /// A note: `count` openings made from quantities have no purchase
        /// cost and no price, so their cost is unknown.
        case openingsWithoutCost(AccountID, count: Int)
        /// Statement layout: the account the profile names isn't in the library.
        case unknownAccount(AccountID)
        /// Statement layout: the account doesn't record money in and out
        /// (only cash and savings accounts that don't record trades do), so
        /// nothing is imported.
        case noMoneyInOut(AccountID)
        /// Statement layout: the file has no balance column, and the library
        /// has no value of the account just before the file, so its balances
        /// are unknown until an opening balance is given
        /// (``ImportSession/statementOpeningBalance``).
        case needsOpeningBalance(AccountID)
        /// A note, statement layout: the file doesn't cover the period from
        /// the account's value before it (`previous`, or none) to its first
        /// value in the file, so money in and out start after `value`.
        case moneyInOutFrom(AccountID, value: CalendarDate, previous: CalendarDate?)
        /// A note, statement layout: `count` lines come after the file's last
        /// value (`after`, or none), so they count toward a later one.
        case linesAfterLastValue(count: Int, after: CalendarDate?)
        /// A note, statement layout: on `count` days, the balance column
        /// doesn't follow from the day before and the day's lines.
        case runningBalanceBreaks(count: Int)
        /// A note, statement layout: the days the file is read as covering
        /// (``ImportSession/statementFrom``, ``ImportSession/statementThrough``).
        case statementPeriod(from: CalendarDate, through: CalendarDate)
        /// Statement layout: `count` lines fall outside the days the file
        /// is said to cover, so nothing is imported.
        case linesOutsidePeriod(count: Int, from: CalendarDate, through: CalendarDate)
        /// Statement layout: the last day the file is said to cover is after
        /// today, so nothing is imported.
        case statementThroughAfterToday(CalendarDate)
        /// A note, statement layout: the account's next value after the file
        /// (`value`) has money in and out since its value before (`since`),
        /// which the file's new values now split, so they count twice until
        /// that value's are corrected.
        case laterMoneyInOut(AccountID, value: CalendarDate, since: CalendarDate?)
        /// Statement layout: the answer of the line on `row` as a purchase
        /// or a sale (``StatementAsset``) is left out, and the line counts
        /// by its class. A purchase must be money out and start a
        /// belongings, property or other account; a sale must be money in,
        /// of an account that ``Model/Account/canBeSoldFromStatement``, in
        /// the statement's currency, with no values after the line, sold
        /// once (`account`). Either needs a value of the file's on or after
        /// the line.
        case statementAssetLeftOut(row: Int, account: AccountID?)
    }

    public var kind: Kind
    /// The 1-based column, when the issue is about one.
    public var column: Int?
    public var header: String?

    public init(kind: Kind, column: Int? = nil, header: String? = nil) {
        self.kind = kind
        self.column = column
        self.header = header
    }

    /// Whether this only says how the file was read, rather than something
    /// to fix: nothing is left out because of it.
    public var isNote: Bool {
        switch kind {
        case .positiveDebts, .debtsInCredit, .tradeAmountSigns, .negativeQuantities, .cashDirectionBySign,
             .ignoredTradeRows, .quantitiesAsTrades, .tradesWithoutPrice, .openingsWithoutCost, .moneyInOutFrom,
             .linesAfterLastValue, .runningBalanceBreaks, .statementPeriod,
             .laterMoneyInOut: true
        default: false
        }
    }

    /// `1 row was`, `3 rows were`.
    private static func rows(_ count: Int) -> String {
        count == 1 ? "1 row was" : "\(count) rows were"
    }

    public var description: String {
        let place = header.map { "“\($0)”" } ?? column.map { "Column \($0)" } ?? "The file"
        switch kind {
        case .unknownColumn:
            return "\(place) isn't in the profile, so it isn't imported until you map it."
        case .missingColumn:
            return "\(place) from the profile isn't in the file."
        case .noDateColumn:
            return "No column holds the dates."
        case .missingField(let field):
            return "\(place) needs \(field == .account || field == .instrument ? "an" : "a") \(field.rawValue)."
        case .invalidDatePattern(let pattern):
            return "“\(pattern)” isn't a date pattern the importer understands."
        case .unterminatedQuote(let row):
            return "Row \(row) has a quote that never closes."
        case .valuesAfterClosed(let account, let closed):
            return "\(account) closed on \(closed), but the file has later values."
        case .positiveDebts(let account, let count):
            let name = header.map { "“\($0)”" } ?? account.rawValue
            return "\(name): positive amounts were read as debts (\(count) \(count == 1 ? "value" : "values"))."
        case .debtsInCredit(let account, let count):
            let name = header.map { "“\($0)”" } ?? account.rawValue
            return "\(name): the column writes debts as negative amounts, so positive amounts were kept "
                + "as credit (\(count) \(count == 1 ? "value" : "values"))."
        case .unmappedTradeType(let value, let count):
            return "“\(value)” isn't mapped to a trade type, so \(Self.rows(count)) left out until it is."
        case .tradeAmountSigns(let signed):
            return signed
                ? "\(place): amounts are signed, so their signs were kept (negative for buys, fees, taxes and "
                    + "withdrawals)."
                : "\(place): amounts are written without signs, so each one's sign comes from its type (negative for "
                    + "buys, fees, taxes and withdrawals)."
        case .negativeQuantities(let count, let byType):
            return "\(place): \(count) negative \(count == 1 ? "quantity was" : "quantities were") made positive; "
                + (byType ? "the type says whether units come in or go out." : "without a type, a negative quantity "
                    + "is a sell and a positive one a buy.")
        case .cashDirectionBySign(let count):
            return "\(count) \(count == 1 ? "deposit or withdrawal was" : "deposits and withdrawals were") told "
                + "apart by the amount's sign."
        case .ignoredTradeRows(let count):
            return count == 1 ? "1 row was left out: its type is mapped to ignore."
                : "\(count) rows were left out: their types are mapped to ignore."
        case .accountDoesntRecordTrades(let account):
            return "\(account) is a brokerage, crypto or metals account that doesn't record trades, so its trades are "
                + "left out. Remove its \"valuation\" so it records trades, as its kind does, then import again."
        case .quantitiesAsTrades(let account, let openings, let buys, let sales, let settledOutside):
            let trades = [(openings, "opening"), (buys, "buy"), (sales, "sale")].filter { $0.0 > 0 }
                .map { Wording.count($0.0, $0.1) }
            return "\(account) records trades, so its quantities became \(Wording.list(trades)): one per change in "
                + "what it holds, at the date's price unless the file gives the purchase cost."
                + (settledOutside && buys + sales > 0
                    ? " It has never held cash, so its buys and sales are paid from and into another account." : "")
        case .tradesWithoutPrice(let account, let count):
            return "\(account): \(count == 1 ? "1 buy or sale has" : "\(count) buys or sales have") no price on or "
                + "before \(count == 1 ? "its" : "their") date and no purchase cost: import the prices too, or add "
                + "\(count == 1 ? "its amount" : "their amounts")."
        case .openingsWithoutCost(let account, let count):
            return "\(account): \(count == 1 ? "1 opening has" : "\(count) openings have") no purchase cost and no "
                + "price, so \(count == 1 ? "its cost is" : "their costs are") unknown."
        case .unknownAccount(let account):
            return "There's no account \(account) in the library."
        case .noMoneyInOut(let account):
            return "\(account) doesn't record money in and out: only cash and savings accounts do, so the statement "
                + "isn't imported."
        case .needsOpeningBalance(let account):
            return "The file has no balance column, and the library has no value of \(account) just before it: give "
                + "the balance before the file's first line."
        case .moneyInOutFrom(let account, let value, let previous):
            let before = previous.map { "\(account)'s value before the file is on \($0), before the file starts" }
                ?? "\(account) has no value before the file"
            return "\(before), so money in and out start after \(value)."
        case .linesAfterLastValue(let count, let after):
            let lines = count == 1 ? "1 line comes" : "\(count) lines come"
            return after.map { "\(lines) after \($0), so \(count == 1 ? "it counts" : "they count") toward the next value." }
                ?? "\(lines) after the file's last whole month, so no value is made from \(count == 1 ? "it" : "them") yet."
        case .runningBalanceBreaks(let count):
            return "\(place): on \(Wording.count(count, "day")), the balance doesn't follow from the day before and "
                + "the day's lines."
        case .statementPeriod(let from, let through):
            return "The file is read as covering \(from) to \(through): every line from those days, and no others."
        case .linesOutsidePeriod(let count, let from, let through):
            return "\(count == 1 ? "1 line is" : "\(count) lines are") outside \(from) to \(through), the days the "
                + "file covers."
        case .statementThroughAfterToday(let through):
            return "The file can't cover days after today, such as \(through)."
        case .laterMoneyInOut(let account, let value, let since):
            let start = since.map { "since \($0)" } ?? "since it opened"
            return "\(account)'s value on \(value) has money in and out \(start), which the file's values now split: "
                + "until its money in and out are only those after the file's last value, they count twice."
        case .statementAssetLeftOut(let row, let account?):
            return "Row \(row) can't sell \(account): it needs to be an open account of the library valued by its "
                + "balance in the statement's currency, not a cash or savings account or a debt, with no values after "
                + "the line, sold once. The line counts by its class."
        case .statementAssetLeftOut(let row, nil):
            return "Row \(row) can't be a purchase or a sale: a purchase is money out that starts a belongings, "
                + "property or other account, and a sale is money in, each before the file's last value. The line "
                + "counts by its class."
        }
    }
}
