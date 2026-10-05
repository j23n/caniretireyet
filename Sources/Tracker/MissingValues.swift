import Model

/// What a series of values couldn't value: each missing price or FX rate,
/// and each open account without a value yet, with the accounts it leaves
/// incomplete and the dates it's missing on. Missing data is reported,
/// never counted as zero (docs/schema/README.md, "How values are computed"), so a
/// chart can leave those points out or mark them, and say what's missing
/// under it.
public struct MissingValues: Hashable, Sendable {
    /// What's missing.
    public enum Item: Hashable, Sendable, Comparable {
        /// No FX rate from `from` to `to` on or before the date.
        case rate(from: CurrencyCode, to: CurrencyCode)
        /// No price for the instrument on or before the date.
        case price(InstrumentID)
        /// The account is open but has no valuation on or before the date.
        case noValuation(AccountID)

        /// Rates first, then prices, then accounts without a value.
        public static func < (lhs: Item, rhs: Item) -> Bool {
            switch (lhs, rhs) {
            case (.rate(let a, let b), .rate(let c, let d)): (a, b) < (c, d)
            case (.price(let a), .price(let b)): a < b
            case (.noValuation(let a), .noValuation(let b)): a < b
            default: lhs.rank < rhs.rank
            }
        }

        private var rank: Int {
            switch self {
            case .rate: 0
            case .price: 1
            case .noValuation: 2
            }
        }

        /// Whether it's a price or a rate, which *Fill In Past Prices* can fetch.
        public var isPriceOrRate: Bool {
            if case .noValuation = self { false } else { true }
        }
    }

    /// One missing price or rate.
    public struct Gap: Hashable, Sendable {
        public let item: Item
        /// The accounts it leaves incomplete, sorted.
        public let accounts: [AccountID]
        /// The dates it's missing on, sorted.
        public let dates: [CalendarDate]

        public init(item: Item, accounts: [AccountID], dates: [CalendarDate]) {
            self.item = item
            self.accounts = accounts.sorted()
            self.dates = dates.sorted()
        }
    }

    /// Rates first, then prices.
    public let gaps: [Gap]

    /// The gaps as given, sorted by item; `nil` when there are none.
    public init?(gaps: [Gap]) {
        guard !gaps.isEmpty else { return nil }
        self.gaps = gaps.sorted { $0.item < $1.item }
    }

    /// What `values` are missing: their missing prices and FX rates, and
    /// open accounts without a valuation; `nil` when there's nothing.
    public init?(_ values: [AccountValue]) {
        var accounts: [Item: Set<AccountID>] = [:]
        var dates: [Item: Set<CalendarDate>] = [:]
        for value in values {
            for problem in value.problems {
                let item: Item = switch problem {
                case .missingFX(_, let from, let to): .rate(from: from, to: to)
                case .missingPrice(_, let instrument): .price(instrument)
                case .noValuation(let account): .noValuation(account)
                }
                accounts[item, default: []].insert(problem.account)
                dates[item, default: []].insert(value.date)
            }
        }
        self.init(gaps: dates.map { item, days in
            Gap(item: item, accounts: Array(accounts[item] ?? []), dates: Array(days))
        })
    }

    /// Every date with something missing, sorted.
    public var dates: [CalendarDate] {
        Set(gaps.flatMap(\.dates)).sorted()
    }

    /// The gaps `isIncluded` keeps; `nil` when none is left.
    public func filter(_ isIncluded: (Gap) -> Bool) -> MissingValues? {
        MissingValues(gaps: gaps.filter(isIncluded))
    }
}

extension Valuator {
    /// What `account`'s values on `dates` in `currency` are missing; `nil`
    /// when they're complete, or the account is unknown.
    public func missingValues(of account: AccountID, on dates: [CalendarDate],
                              in currency: ValueCurrency = .base) -> MissingValues? {
        MissingValues(dates.compactMap { value(of: account, on: $0, in: currency) })
    }

    /// What the totals of the accounts in `scope` on `dates` are missing;
    /// `nil` when they're complete.
    public func missingValues(in scope: NetWorthScope, on dates: [CalendarDate]) -> MissingValues? {
        MissingValues(dates.flatMap { total(on: $0, in: scope).accounts })
    }
}
