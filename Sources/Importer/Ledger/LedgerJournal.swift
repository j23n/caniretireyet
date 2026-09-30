import Foundation
import Model

/// A line of a journal file: the file as shown to the user (relative to
/// the folder of the files given) and a 1-based line number.
public struct LedgerLocation: Hashable, Sendable, Comparable, CustomStringConvertible {
    public var file: String
    public var line: Int

    public init(file: String, line: Int) {
        self.file = file
        self.line = line
    }

    /// E.g. `2024.journal:12`.
    public var description: String { "\(file):\(line)" }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.file, lhs.line) < (rhs.file, rhs.line)
    }
}

/// Something found while reading a journal or turning it into records: an
/// error (the transaction or directive was skipped), a warning (it was
/// read, but check it), or a note on something left out.
public struct LedgerDiagnostic: Hashable, Sendable, CustomStringConvertible {
    public enum Severity: String, Hashable, Sendable {
        case error, warning, note
    }

    public var severity: Severity
    public var location: LedgerLocation?
    public var message: String

    public init(_ severity: Severity, _ message: String, at location: LedgerLocation? = nil) {
        self.severity = severity
        self.message = message
        self.location = location
    }

    /// E.g. `2024.journal:12: the transaction doesn't balance: off by 0.10 EUR`.
    public var description: String {
        location.map { "\($0): \(message)" } ?? message
    }
}

/// A quantity of a commodity, e.g. `-5.00 EUR` or `10 "VWCE.MI"`.
public struct LedgerAmount: Hashable, Sendable, CustomStringConvertible {
    public var quantity: Decimal
    /// The commodity as written, without quotes; empty when the amount has none.
    public var commodity: String

    public init(_ quantity: Decimal, _ commodity: String) {
        self.quantity = quantity
        self.commodity = commodity
    }

    public var description: String {
        guard !commodity.isEmpty else { return quantity.description }
        let plain = commodity.allSatisfy { $0.isLetter || "€$£¥₹₩₺_".contains($0) }
        return "\(quantity.description) \(plain ? commodity : "\"\(commodity)\"")"
    }
}

/// One posting of a transaction, after the transaction was balanced: every
/// posting has an amount.
public struct LedgerPosting: Hashable, Sendable {
    /// `(Account)` postings are virtual and don't have to balance;
    /// `[Account]` ones are virtual but balance among themselves.
    public enum Kind: String, Hashable, Sendable {
        case real
        case balancedVirtual
        case unbalancedVirtual
    }

    /// The full account name, after `apply account` and aliases.
    public var account: String
    public var kind: Kind
    public var amount: LedgerAmount
    /// What the posting cost in total, in another commodity, with the
    /// amount's sign: from a `{lot price}`, `@ unit price` or `@@ total
    /// price`, or inferred when a transaction exchanges two commodities.
    /// It's what the posting balances with.
    public var cost: LedgerAmount?
    /// The price per unit written with `@` or `@@`: a market price on the
    /// transaction's date.
    public var unitPrice: LedgerAmount?
    /// Whether the amount was left out and inferred, or set by a balance assignment.
    public var isInferred: Bool
    public var location: LedgerLocation

    public init(account: String, kind: Kind = .real, amount: LedgerAmount, cost: LedgerAmount? = nil,
                unitPrice: LedgerAmount? = nil, isInferred: Bool = false, location: LedgerLocation) {
        self.account = account
        self.kind = kind
        self.amount = amount
        self.cost = cost
        self.unitPrice = unitPrice
        self.isInferred = isInferred
        self.location = location
    }
}

/// A dated transaction with its postings.
public struct LedgerTransaction: Hashable, Sendable {
    /// `*` cleared or `!` pending.
    public enum Status: String, Hashable, Sendable {
        case cleared = "*"
        case pending = "!"
    }

    public var date: CalendarDate
    public var status: Status?
    public var code: String?
    public var description: String
    public var postings: [LedgerPosting]
    public var location: LedgerLocation

    public init(date: CalendarDate, status: Status? = nil, code: String? = nil, description: String,
                postings: [LedgerPosting], location: LedgerLocation) {
        self.date = date
        self.status = status
        self.code = code
        self.description = description
        self.postings = postings
        self.location = location
    }
}

/// A `P` directive: the price of one unit of a commodity on a date.
public struct LedgerMarketPrice: Hashable, Sendable {
    public var date: CalendarDate
    public var commodity: String
    public var price: LedgerAmount
    public var location: LedgerLocation

    public init(date: CalendarDate, commodity: String, price: LedgerAmount, location: LedgerLocation) {
        self.date = date
        self.commodity = commodity
        self.price = price
        self.location = location
    }
}

/// The type an `account` directive declares (hledger's `type:` tag).
public enum LedgerAccountType: String, Hashable, Sendable {
    case asset, liability, equity, revenue, expense, cash, conversion

    /// Whether accounts of this type count toward net worth.
    public var isNetWorth: Bool { self == .asset || self == .liability || self == .cash }
}

/// A file that was read.
public struct LedgerSourceFile: Hashable, Sendable {
    public var url: URL
    /// The file as shown: relative to the folder of the files given.
    public var name: String
    /// The `include` that brought it in; `nil` for a file given.
    public var includedFrom: LedgerLocation?
    /// Transactions read from it (including ones skipped because of an error).
    public var transactions: Int

    public init(url: URL, name: String, includedFrom: LedgerLocation?, transactions: Int = 0) {
        self.url = url
        self.name = name
        self.includedFrom = includedFrom
        self.transactions = transactions
    }
}

/// An `include` that couldn't be read, e.g. because the app may only read
/// the files you chose, not others in their folder.
public struct LedgerMissingInclude: Hashable, Sendable {
    /// The path as written after `include`.
    public var path: String
    /// Where it points.
    public var url: URL
    public var location: LedgerLocation
    public var reason: String

    public init(path: String, url: URL, location: LedgerLocation, reason: String) {
        self.path = path
        self.url = url
        self.location = location
        self.reason = reason
    }
}

/// One or more journal files read as one journal, with everything they
/// include. Transactions are balanced (every posting has an amount) and
/// sorted by date, keeping the files' order within a day.
public struct LedgerJournal: Hashable, Sendable {
    /// The files read, in the order they were read.
    public var files: [LedgerSourceFile]
    public var transactions: [LedgerTransaction]
    /// `P` directives, sorted by date.
    public var prices: [LedgerMarketPrice]
    /// Accounts declared with `account`, in the order declared.
    public var declaredAccounts: [String]
    /// Types given to accounts by `account` directives (`; type: A`).
    public var accountTypes: [String: LedgerAccountType]
    /// Errors, warnings and notes, in file order.
    public var diagnostics: [LedgerDiagnostic]
    /// Includes that couldn't be read.
    public var missingIncludes: [LedgerMissingInclude]

    public init(files: [LedgerSourceFile] = [], transactions: [LedgerTransaction] = [],
                prices: [LedgerMarketPrice] = [], declaredAccounts: [String] = [],
                accountTypes: [String: LedgerAccountType] = [:], diagnostics: [LedgerDiagnostic] = [],
                missingIncludes: [LedgerMissingInclude] = []) {
        self.files = files
        self.transactions = transactions
        self.prices = prices
        self.declaredAccounts = declaredAccounts
        self.accountTypes = accountTypes
        self.diagnostics = diagnostics
        self.missingIncludes = missingIncludes
    }

    /// The first and last transaction dates.
    public var firstDate: CalendarDate? { transactions.first?.date }
    public var lastDate: CalendarDate? { transactions.last?.date }

    /// Every account posted to or declared, sorted.
    public var accounts: [String] {
        Set(transactions.flatMap { $0.postings.map(\.account) } + declaredAccounts).sorted()
    }

    /// Every commodity in postings, costs and prices, sorted.
    public var commodities: [String] {
        var symbols = Set<String>()
        for transaction in transactions {
            for posting in transaction.postings {
                symbols.insert(posting.amount.commodity)
                if let cost = posting.cost { symbols.insert(cost.commodity) }
            }
        }
        for price in prices {
            symbols.insert(price.commodity)
            symbols.insert(price.price.commodity)
        }
        return symbols.sorted()
    }

    public var errors: [LedgerDiagnostic] { diagnostics.filter { $0.severity == .error } }
    public var warnings: [LedgerDiagnostic] { diagnostics.filter { $0.severity == .warning } }
}
