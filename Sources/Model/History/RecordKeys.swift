/// A record in a list that has a stable key for merging and de-duplicating.
///
/// There is at most one record per key in the library. Keys sort by date,
/// then by ID, which is the order records are written in.
public protocol KeyedRecord: Sendable {
    associatedtype Key: Hashable, Comparable, Sendable
    var key: Key { get }
}

/// A valuation's key: account + date.
public struct ValuationKey: Hashable, Comparable, Sendable {
    public var date: CalendarDate
    public var account: AccountID

    public init(account: AccountID, date: CalendarDate) {
        self.account = account
        self.date = date
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.date, lhs.account) < (rhs.date, rhs.account)
    }
}

/// A price's key: instrument + date.
public struct PriceKey: Hashable, Comparable, Sendable {
    public var date: CalendarDate
    public var instrument: InstrumentID

    public init(instrument: InstrumentID, date: CalendarDate) {
        self.instrument = instrument
        self.date = date
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.date, lhs.instrument) < (rhs.date, rhs.instrument)
    }
}

/// An FX rate's key: base + quote + date.
public struct FXKey: Hashable, Comparable, Sendable {
    public var date: CalendarDate
    public var base: CurrencyCode
    public var quote: CurrencyCode

    public init(base: CurrencyCode, quote: CurrencyCode, date: CalendarDate) {
        self.base = base
        self.quote = quote
        self.date = date
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.date, lhs.base, lhs.quote) < (rhs.date, rhs.base, rhs.quote)
    }
}

/// An index value's key: index + date.
public struct IndexKey: Hashable, Comparable, Sendable {
    public var date: CalendarDate
    public var index: IndexID

    public init(index: IndexID, date: CalendarDate) {
        self.index = index
        self.date = date
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.date, lhs.index) < (rhs.date, rhs.index)
    }
}

/// A trade's key: account + date + trade ID.
public struct TradeKey: Hashable, Comparable, Sendable, CustomStringConvertible {
    public var date: CalendarDate
    public var account: AccountID
    public var id: TradeID

    public init(account: AccountID, date: CalendarDate, id: TradeID) {
        self.account = account
        self.date = date
        self.id = id
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.date, lhs.account, lhs.id) < (rhs.date, rhs.account, rhs.id)
    }

    /// `2026-03-12 directa k3q7vz2m`
    public var description: String { "\(date) \(account) \(id)" }
}

extension Sequence where Element: KeyedRecord {
    /// The records sorted by key: by date, then by ID.
    public func sortedByKey() -> [Element] {
        sorted { $0.key < $1.key }
    }
}

extension Array {
    /// For an array sorted by date: the index of the last element dated on
    /// or before `limit`, found by binary search.
    public func lastIndex(onOrBefore limit: CalendarDate, date: (Element) -> CalendarDate) -> Int? {
        var low = 0
        var high = count
        while low < high {
            let mid = (low + high) / 2
            if date(self[mid]) <= limit { low = mid + 1 } else { high = mid }
        }
        return low == 0 ? nil : low - 1
    }
}
