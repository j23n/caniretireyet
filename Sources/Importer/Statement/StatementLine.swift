import Foundation
import Model

/// One line of a bank statement as the preview reads it: what it says, the
/// class it gets, and why (docs/IMPORT.md, "Bank statements").
public struct StatementLine: Hashable, Sendable, Identifiable {
    /// Why a line has its class, from the surest to the least sure.
    public enum Source: Hashable, Sendable {
        /// Chosen for this line alone (``ImportSession/setStatementClass(_:forRow:)``).
        case chosen
        /// The profile's rule with this phrase.
        case rule(String)
        /// The library's trade moving the same amount into or out of another
        /// account within a few days: a deposit, a withdrawal, or a buy or
        /// sale paid from outside that account.
        case trade(TradeKey)
        /// A line of another account's statement imported with this one
        /// (``StatementBatch``) moves the same amount the other way within
        /// a few days: a transfer.
        case paired(AccountID)
        /// The description names another account of the library (or its
        /// institution): a transfer, or a payment of a debt (spending).
        case account(AccountID)
        /// The usual words for pay, refunds, tax, transfers between your
        /// own accounts and interest (``StatementWords``).
        case words
        /// Money in from a sender the file has paid within the 90 days
        /// before: paid back, so spending.
        case paidBefore
        /// Money in from a sender who pays similar amounts in at least 3 of
        /// the file's months: income, those amounts and smaller ones.
        case recurring
        /// Money in and out of the same amount within a few days, at least
        /// one of them large enough to need an answer: money that passed
        /// through the account. Both are transfers; `row` is the other line's.
        case passThrough(row: Int)
        /// Nothing else said: spending, which money in lowers.
        case sign
    }

    /// Why the import leaves out the line's answer as money moved, a
    /// purchase or a sale (``ImportIssue/Kind/statementMoveLeftOut(row:account:)``,
    /// ``ImportIssue/Kind/statementAssetLeftOut(row:account:)``).
    public enum AssetLeftOut: Hashable, Sendable {
        /// The account can't take money moved from this statement
        /// (``Library/canMoveFromStatement(_:of:on:)``).
        case accountCantTakeMoves
        /// The move is to a tax pot, and the line counts in no value whose
        /// money in and out the file covers.
        case notCovered
        /// The purchase or the sale doesn't fit the line.
        case doesntFit
    }

    /// The 1-based row in the file.
    public var row: Int
    public var date: CalendarDate
    /// Signed: + in, − out.
    public var amount: Decimal
    /// The description and counterparty columns, joined.
    public var text: String
    /// Who paid or was paid, as words of the text a rule can match: the
    /// counterparty, else the description's first words that name someone
    /// (``StatementWords/sender(of:)``); empty when nothing does.
    public var sender: String
    /// The account's balance after the line, when the file has it.
    public var balance: Decimal?
    public var statementClass: StatementClass
    public var source: Source
    /// The date of the value whose money in and out the line counts in;
    /// `nil` when it counts in none: a period the file doesn't cover from
    /// the account's previous value, or after the file's last value.
    public var period: CalendarDate?
    /// Whether the line is too large to count by its sign without asking,
    /// and nothing classified it. Money in: more than a typical month's
    /// spending in the file, or more than a sender who pays every month
    /// usually pays, whatever its size. Money out: more than a typical
    /// month's spending, without the line. Income, spending, a one-off,
    /// tax, or moved to or from an account? Until it's answered it counts
    /// as spending.
    public var needsAnswer = false
    /// Whether the line needs an answer, or would without the class or
    /// the answer chosen for it alone: a question that stays a question
    /// once it's answered.
    public var wasAsked = false
    /// The line's answer as money moved to or from an account, a purchase
    /// you keep or a sale (``ImportSession/setStatementAsset(_:forRow:)``,
    /// or a rule with an account), when the import takes it: the line is
    /// then a transfer.
    public var asset: StatementAsset?
    /// The account the answer moves money to or from: the account named, a
    /// purchase's new account (``ImportPreview/newAccounts``), or the
    /// account sold.
    public var assetAccount: AccountID?
    /// Why the line's answer is left out; `nil` when it's taken or there
    /// is none.
    public var assetLeftOut: AssetLeftOut?
    /// Its ID among the account's lines kept in the library (docs/IMPORT.md,
    /// "Lines"): made from its account, date, amount and text, so importing
    /// the file again finds it.
    public var lineID: BankLineID = ""
    /// Whether the library's line was removed, such as one listed twice: it
    /// counts in nothing, and isn't in the balance.
    public var isRemoved = false
    /// The note of the library's line.
    public var note: String?

    public var id: Int { row }

    /// The other account the line moves money to or from, when it's a
    /// transfer and it's known.
    public var otherAccount: AccountID? {
        guard statementClass == .transfer else { return nil }
        if let assetAccount { return assetAccount }
        switch source {
        case .trade(let key): return key.account
        case .paired(let account), .account(let account): return account
        default: return nil
        }
    }

    /// The line as the library keeps it: what it is, confirmed when it
    /// was chosen, and the import's suggestion otherwise. A purchase or a
    /// sale stays a suggestion, so importing the file again asks for it
    /// again and finds the value it made.
    func bankLine(account: AccountID) -> BankLine {
        let isConfirmed = source == .chosen && !isRemoved && !isPurchaseOrSale
        return BankLine(account: account, date: date, id: lineID, amount: amount, text: text,
                        statementClass: statementClass, otherAccount: otherAccount, note: note,
                        removed: isRemoved ? true : nil, confirmed: isConfirmed ? true : nil, source: .import)
    }

    /// Whether the line's answer is a purchase or a sale, also one the
    /// import leaves out because it doesn't fit.
    private var isPurchaseOrSale: Bool {
        switch asset {
        case .purchase?, .sale?: true
        case .moved?, nil: assetLeftOut == .doesntFit
        }
    }

    /// Whether the text has `phrase` as whole words, ignoring case, accents
    /// and punctuation, as a rule matches it.
    public func hasWords(_ phrase: String) -> Bool {
        let words = TextTools.words(phrase)
        return !words.isEmpty && TextTools.contains(TextTools.words(text), anyOf: [words.joined(separator: " ")])
    }

    /// What the line adds to money in, money out, one-offs, tax and
    /// interest (``Model/LineAmounts``).
    func counted(recordsInterest: Bool) -> LineAmounts {
        LineAmounts(statementClass, amount: amount, recordsInterest: recordsInterest)
    }
}

/// The usual words of bank statements, in Italian, German and English,
/// folded (lowercase, no accents), that classify a line no rule and no
/// account does. Pay, interest and refunds count only for money in.
public enum StatementWords {
    /// Pay and pensions: income when the line is money in.
    static let income = ["stipendio", "stipendi", "emolumenti", "retribuzione", "salario", "pensione", "salary",
                         "payroll", "wages", "pension", "gehalt", "lohn", "bezuge", "rente"]
    /// Money paid back: a refund or a reversal, when the line is money in.
    /// It's spending, which it lowers.
    static let paidBack = ["rimborso", "storno", "stornierung", "erstattung", "ruckerstattung", "refund", "reversal",
                           "chargeback"]
    /// Money moved between your own accounts.
    static let transfer = ["giroconto", "girofondi", "giro conto", "trasferimento tra conti", "umbuchung", "ubertrag",
                           "eigenubertrag", "own account transfer", "transfer between accounts", "transfer to savings",
                           "transfer from savings", "internal transfer"]
    /// The tax office, and tax on income: tax paid, or a refund.
    static let tax = ["finanzamt", "agenzia entrate", "agenzia delle entrate", "f24", "einkommensteuer", "hmrc",
                      "income tax", "self assessment"]
    /// Interest earned: interest when the line is money in.
    static let interest = ["interessi", "interessi creditori", "interessi attivi", "competenze creditorie", "zinsen",
                           "habenzinsen", "zinsgutschrift", "interest", "interest paid", "credit interest"]

    /// The class a line's text suggests, if any.
    public static func suggestion(for text: String, amount: Decimal) -> StatementClass? {
        suggestion(for: TextTools.words(text), amount: amount)
    }

    /// The class a text's words (``TextTools/words(_:)``) suggest, if any.
    static func suggestion(for words: [String], amount: Decimal) -> StatementClass? {
        guard !words.isEmpty else { return nil }
        if TextTools.contains(words, anyOf: transfer) { return .transfer }
        if TextTools.contains(words, anyOf: tax) { return .tax }
        guard amount > 0 else { return nil }
        if TextTools.contains(words, anyOf: interest) { return .interest }
        if TextTools.contains(words, anyOf: income) { return .income }
        if TextTools.contains(words, anyOf: paidBack) { return .spending }
        return nil
    }

    /// Words every bank puts in its texts, which say nothing about who paid:
    /// the kind of payment, its references, articles and prepositions, a
    /// company's legal form, months and currencies.
    static let noise: Set<String> = [
        "a", "al", "alla", "da", "dal", "dalla", "de", "del", "della", "di", "e", "il", "la", "per", "su", "un", "una",
        "von", "vom", "zu", "zur", "der", "die", "das", "und", "fur", "mit", "an", "auf", "aus",
        "the", "of", "to", "from", "for", "and", "on", "at", "by", "in",
        "bonifico", "bonif", "vostro", "vs", "nostro", "ns", "disposto", "ordine", "sepa", "sct", "sdd", "ordinante", "beneficiario", "favore", "pagamento", "pagam", "pos",
        "carta", "card", "karte", "addebito", "accredito", "disposizione", "operazione", "causale", "rif", "ref", "cro",
        "trn", "id", "iban", "bic", "swift", "eur", "euro", "usd", "chf", "gbp", "istantaneo", "instant",
        "uberweisung", "ueberweisung", "gutschrift", "lastschrift", "dauerauftrag", "kartenzahlung", "zahlung",
        "buchung", "verwendungszweck", "auftraggeber", "empfanger", "kundenreferenz", "mandatsreferenz", "end",
        "transfer", "payment", "receipt", "credit", "debit", "direct", "purchase", "received", "sent", "faster",
        "srl", "spa", "sas", "snc", "gmbh", "ag", "kg", "ltd", "llc", "inc", "plc", "co",
        "gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio", "agosto", "settembre", "ottobre",
        "novembre", "dicembre", "januar", "februar", "marz", "mai", "juni", "juli", "august", "oktober", "dezember",
        "january", "february", "march", "april", "may", "june", "july", "september", "october", "november",
        "december",
    ]

    /// Card and payment processors that write the merchant after a `*`, as
    /// in `PayPal Europe *Kleinanzeigen Fahrrad`.
    static let processors: Set<String> = ["paypal", "sumup", "zettle", "izettle", "klarna", "stripe", "sq"]

    /// A sender's or a search's words as the importer matches them
    /// (lowercase, no accents, no punctuation), joined by spaces: lines
    /// whose senders have the same key are one sender's.
    public static func key(_ text: String) -> String {
        TextTools.words(text).joined(separator: " ")
    }

    /// Who paid or was paid, from a counterparty or a description: its
    /// first run of up to 4 words that aren't ``noise`` or numbers, as the
    /// text writes them, so a rule with them matches the line. A
    /// processor's line (``processors``) is its merchant's: the word after
    /// the `*`. Empty when no word names anyone.
    public static func sender(of text: String) -> String {
        if let star = text.firstIndex(of: "*"),
           TextTools.words(String(text[..<star])).contains(where: processors.contains),
           let merchant = text[text.index(after: star)...]
               .split(whereSeparator: { !($0.isLetter || $0.isNumber) }).first,
           merchant.contains(where: \.isLetter) {
            return String(merchant)
        }
        let folded = TextTools.words(text)
        let written = text.split { !($0.isLetter || $0.isNumber) }.map(String.init)
        let shown = written.count == folded.count ? written : folded
        let names = { (index: Int) in
            let word = folded[index]
            return word.count > 1 && !noise.contains(word) && !word.contains { $0.isNumber }
        }
        guard let start = folded.indices.first(where: names) else { return "" }
        let run = folded.indices[start...].prefix { names($0) }.prefix(4)
        return run.map { shown[$0] }.joined(separator: " ")
    }
}
