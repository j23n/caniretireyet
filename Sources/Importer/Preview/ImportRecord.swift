import Foundation
import Model

/// The key of a record the import writes: account + date, instrument + date,
/// or currency pair + date. Sorts by date, then kind, then ID.
public enum ImportRecordKey: Hashable, Comparable, Sendable, CustomStringConvertible {
    case valuation(ValuationKey)
    case price(PriceKey)
    case fx(FXKey)

    public var date: CalendarDate {
        switch self {
        case .valuation(let key): key.date
        case .price(let key): key.date
        case .fx(let key): key.date
        }
    }

    /// The account of a valuation.
    public var account: AccountID? {
        if case .valuation(let key) = self { key.account } else { nil }
    }

    /// The instrument of a price.
    public var instrument: InstrumentID? {
        if case .price(let key) = self { key.instrument } else { nil }
    }

    public var description: String {
        switch self {
        case .valuation(let key): "\(key.account) on \(key.date)"
        case .price(let key): "\(key.instrument) price on \(key.date)"
        case .fx(let key): "\(key.base)/\(key.quote) on \(key.date)"
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.valuation(let a), .valuation(let b)): a < b
        case (.price(let a), .price(let b)): a < b
        case (.fx(let a), .fx(let b)): a < b
        default: (lhs.date, lhs.order) < (rhs.date, rhs.order)
        }
    }

    private var order: Int {
        switch self {
        case .valuation: 0
        case .price: 1
        case .fx: 2
        }
    }
}

/// A record as the library stores it.
public enum LibraryRecord: Hashable, Sendable {
    case valuation(Valuation)
    case price(PriceRecord)
    case fx(FXRecord)

    public var key: ImportRecordKey {
        switch self {
        case .valuation(let record): .valuation(record.key)
        case .price(let record): .price(record.key)
        case .fx(let record): .fx(record.key)
        }
    }
}

/// A position's values from the file. Either can be missing: a file can
/// hold only quantities, or only purchase costs.
public struct ImportedPosition: Hashable, Sendable {
    public var instrument: InstrumentID
    public var quantity: Decimal?
    public var costBasis: Decimal?

    public init(instrument: InstrumentID, quantity: Decimal? = nil, costBasis: Decimal? = nil) {
        self.instrument = instrument
        self.quantity = quantity
        self.costBasis = costBasis
    }
}

/// What the file says about one record: only the fields it provides. Fields
/// the file doesn't mention are left as they are in the library.
public struct ImportedRecord: Hashable, Sendable {
    public var key: ImportRecordKey
    /// Valuations: the balance, cash and positions, as far as the file gives them.
    public var balance: Decimal?
    public var cash: Decimal?
    public var positions: [ImportedPosition]
    /// Prices: the price and its currency.
    public var price: Decimal?
    public var currency: CurrencyCode?
    /// FX rates: 1 base = rate × quote.
    public var rate: Decimal?
    /// Valuations: the money added (+) or taken out (−) since the account's
    /// previous valuation, when the file knows it (a ledger journal does).
    public var flow: Decimal?
    /// Where the values come from, written into new and overwritten
    /// records; `nil` means `import`.
    public var source: DataSource?
    /// Whether `balance` is negative because the file wrote a debt account's
    /// balance as a positive amount (IMPORT.md, "Debts").
    public internal(set) var balanceReadAsDebt = false
    /// Whether `balance` is positive although its account is a debt, because
    /// its column writes debts as negative amounts: the account is in credit
    /// (IMPORT.md, "Debts").
    public internal(set) var balanceKeptAsCredit = false
    /// The balance as the file wrote it, before its sign was set for a debt
    /// account; `nil` for records made outside a preview.
    var writtenBalance: Decimal?
    /// The 1-based column the balance was read from.
    var balanceColumn: Int?
    /// How the balance's column signs debts.
    var liabilitySign: LiabilitySign = .auto

    public init(key: ImportRecordKey, balance: Decimal? = nil, cash: Decimal? = nil,
                positions: [ImportedPosition] = [], price: Decimal? = nil, currency: CurrencyCode? = nil,
                rate: Decimal? = nil) {
        self.key = key
        self.balance = balance
        self.cash = cash
        self.positions = positions
        self.price = price
        self.currency = currency
        self.rate = rate
    }

    /// Whether every value in the record is zero (a closed account's zeros).
    var isZero: Bool {
        (balance ?? 0) == 0 && (cash ?? 0) == 0 && positions.allSatisfy { ($0.quantity ?? 0) == 0 }
    }

    /// Sets the balance's sign for its account. With `auto`, a positive
    /// amount for a debt account is a debt and becomes negative, unless the
    /// column already writes debts as negative amounts
    /// (`columnWritesDebtsNegative`): then the file's signs are kept, and a
    /// positive amount is a debt in credit. `asWritten` always keeps them.
    /// Called again when the account's kind may have changed, e.g. a proposed
    /// account's kind was edited.
    mutating func signBalance(isLiability: Bool, columnWritesDebtsNegative: Bool) {
        guard let written = writtenBalance else { return }
        let decides = isLiability && liabilitySign != .asWritten && written > 0
        balanceReadAsDebt = decides && !columnWritesDebtsNegative
        balanceKeptAsCredit = decides && columnWritesDebtsNegative
        balance = balanceReadAsDebt ? -written : written
    }

    /// The columns that write debts as negative amounts: those where a
    /// balance of a debt account (`isLiability`) is negative in the file.
    /// With `auto`, their signs are kept as written.
    static func columnsWritingDebtsNegative(_ records: some Sequence<ImportedRecord>,
                                            isLiability: (AccountID) -> Bool) -> Set<Int> {
        var columns: Set<Int> = []
        for record in records {
            guard let written = record.writtenBalance, written < 0, let column = record.balanceColumn,
                  let account = record.key.account, isLiability(account)
            else { continue }
            columns.insert(column)
        }
        return columns
    }
}

/// How an imported record compares with the library.
public enum ImportRecordStatus: String, Hashable, Sendable {
    /// Not in the library: it's added.
    case new
    /// In the library without some of the file's values: they're filled in,
    /// and nothing in the library changes.
    case updated
    /// The library already has these values: nothing to do.
    case identical
    /// The library has different values: the conflict policy decides.
    case conflict
}

/// Compares imported records with the library's and merges them.
enum RecordMerge {
    struct Outcome: Hashable {
        var status: ImportRecordStatus
        /// The library record with the file's new values filled in, keeping
        /// every value that differs (what `keep` writes).
        var kept: LibraryRecord
        /// The library record with every value from the file (what `overwrite` writes).
        var overwritten: LibraryRecord
    }

    static func evaluate(_ imported: ImportedRecord, existing: LibraryRecord?) -> Outcome {
        switch (imported.key, existing) {
        case (.valuation, .valuation(let valuation)?):
            let (kept, _) = merge(imported, into: valuation, overwrite: false)
            let (overwritten, conflict) = merge(imported, into: valuation, overwrite: true)
            let status: ImportRecordStatus = conflict ? .conflict : kept == valuation ? .identical : .updated
            return Outcome(status: status, kept: .valuation(kept), overwritten: .valuation(overwritten))
        case (.valuation(let key), _):
            let valuation = Valuation(
                account: key.account, date: key.date, balance: imported.balance, cash: imported.cash,
                positions: imported.positions.compactMap { position in
                    position.quantity.map {
                        Position(instrument: position.instrument, quantity: $0, costBasis: position.costBasis)
                    }
                }.sorted { $0.instrument < $1.instrument },
                flow: imported.flow, source: imported.source ?? .import)
            return Outcome(status: .new, kept: .valuation(valuation), overwritten: .valuation(valuation))
        case (.price(let key), let existing):
            let record = PriceRecord(instrument: key.instrument, date: key.date, price: imported.price ?? 0,
                                     currency: imported.currency ?? .eur, source: imported.source ?? .import)
            guard case .price(let old)? = existing else {
                return Outcome(status: .new, kept: .price(record), overwritten: .price(record))
            }
            let same = old.price == record.price && old.currency == record.currency
            return Outcome(status: same ? .identical : .conflict, kept: .price(old),
                           overwritten: same ? .price(old) : .price(record))
        case (.fx(let key), let existing):
            let record = FXRecord(base: key.base, quote: key.quote, date: key.date, rate: imported.rate ?? 0,
                                  source: imported.source ?? .import)
            guard case .fx(let old)? = existing else {
                return Outcome(status: .new, kept: .fx(record), overwritten: .fx(record))
            }
            let same = old.rate == record.rate
            return Outcome(status: same ? .identical : .conflict, kept: .fx(old),
                           overwritten: same ? .fx(old) : .fx(record))
        }
    }

    /// Merges the file's values into a valuation. Without `overwrite`, only
    /// values the valuation lacks are filled in. Returns whether any value differed.
    static func merge(_ imported: ImportedRecord, into existing: Valuation,
                      overwrite: Bool) -> (Valuation, conflict: Bool) {
        var valuation = existing
        var conflict = false
        if let balance = imported.balance {
            if let old = valuation.balance {
                if old != balance {
                    conflict = true
                    if overwrite { valuation.balance = balance }
                }
            } else if valuation.isHoldings {
                conflict = true
                if overwrite {
                    valuation.balance = balance
                    valuation.cash = nil
                    valuation.positions = []
                }
            } else {
                valuation.balance = balance
            }
        } else if imported.cash != nil || !imported.positions.isEmpty, valuation.balance != nil {
            // Holdings for a valuation recorded as a balance: switching modes is a conflict.
            guard overwrite else { return (existing, true) }
            conflict = true
            valuation.balance = nil
        }
        if let cash = imported.cash, imported.balance == nil || valuation.balance == nil {
            if let old = valuation.cash, old != cash {
                conflict = true
                if overwrite { valuation.cash = cash }
            } else if valuation.cash == nil {
                valuation.cash = cash
            }
        }
        if imported.balance == nil || valuation.balance == nil {
            for position in imported.positions {
                if let index = valuation.positions.firstIndex(where: { $0.instrument == position.instrument }) {
                    if let quantity = position.quantity, valuation.positions[index].quantity != quantity {
                        conflict = true
                        if overwrite { valuation.positions[index].quantity = quantity }
                    }
                    if let cost = position.costBasis {
                        if let old = valuation.positions[index].costBasis, old != cost {
                            conflict = true
                            if overwrite { valuation.positions[index].costBasis = cost }
                        } else if valuation.positions[index].costBasis == nil {
                            valuation.positions[index].costBasis = cost
                        }
                    }
                } else if let quantity = position.quantity {
                    let new = Position(instrument: position.instrument, quantity: quantity,
                                       costBasis: position.costBasis)
                    let index = valuation.positions.firstIndex { new.instrument < $0.instrument }
                        ?? valuation.positions.endIndex
                    valuation.positions.insert(new, at: index)
                }
            }
        }
        if let flow = imported.flow {
            if let old = valuation.flow, old != flow {
                conflict = true
                if overwrite { valuation.flow = flow }
            } else if valuation.flow == nil {
                valuation.flow = flow
            }
        }
        if overwrite, conflict { valuation.source = imported.source ?? .import }
        return (valuation, conflict)
    }
}

extension Library {
    /// The record with this key, if the library has one.
    func record(for key: ImportRecordKey) -> LibraryRecord? {
        guard let month = months[key.date.yearMonth] else { return nil }
        switch key {
        case .valuation(let key): return month.valuations.first { $0.key == key }.map(LibraryRecord.valuation)
        case .price(let key): return month.prices.first { $0.key == key }.map(LibraryRecord.price)
        case .fx(let key): return month.fx.first { $0.key == key }.map(LibraryRecord.fx)
        }
    }

    /// Adds or replaces a record.
    mutating func upsert(_ record: LibraryRecord) {
        switch record {
        case .valuation(let valuation): upsert(valuation)
        case .price(let price): upsert(price)
        case .fx(let rate): upsert(rate)
        }
    }
}
