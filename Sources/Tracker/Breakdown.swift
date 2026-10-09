import Foundation
import Model

/// What a breakdown groups values by (UI.md, "Allocation").
public enum BreakdownDimension: String, Hashable, Sendable, CaseIterable {
    /// Holdings split by their instrument's asset mix, balances by the
    /// account's effective mix, cash held with positions as cash. Debts form
    /// their own group.
    case assetClass
    /// Cash, Investments, Crypto & gold, Pension, Property, Debts, by account kind.
    case accountGroup
    /// The currency each part is held in: an account's currency for balances
    /// and cash, the price's currency for positions.
    case currency
    /// The account's institution.
    case institution
    /// Liquid or locked, by account kind.
    case liquidity
}

/// One group in a breakdown. Keys sort in stacking order: for asset classes
/// cash, bonds, equity, gold, crypto, real estate, other (UI.md, "Colour in
/// charts"), then debts; account groups in display order; currencies and
/// institutions alphabetically, with "no institution" last.
public enum BreakdownKey: Hashable, Sendable, Comparable, CustomStringConvertible {
    case assetClass(AssetClass)
    /// Debt accounts, in the asset-class breakdown.
    case debts
    case accountGroup(AccountGroup)
    case currency(CurrencyCode)
    /// An institution; `nil` for accounts without one.
    case institution(String?)
    case liquidity(Liquidity)

    /// Asset classes in stacking order, bottom first. Classes this version
    /// doesn't know follow them.
    public static let assetClassOrder: [AssetClass] = [.cash, .bonds, .equity, .gold, .crypto, .realEstate, .other]

    public static func < (lhs: BreakdownKey, rhs: BreakdownKey) -> Bool {
        lhs.sortKey < rhs.sortKey
    }

    /// The kind of key, the rank within its kind, then the name.
    private var sortKey: (Int, Int, String) {
        switch self {
        case .assetClass(let assetClass):
            (0, Self.assetClassOrder.firstIndex(of: assetClass) ?? Self.assetClassOrder.count, assetClass.rawValue)
        case .debts: (1, 0, "")
        case .accountGroup(let group): (2, AccountGroup.allCases.firstIndex(of: group)!, "")
        case .currency(let code): (3, 0, code.rawValue)
        case .institution(let name): (4, name == nil ? 1 : 0, name ?? "")
        case .liquidity(let liquidity): (5, Liquidity.allCases.firstIndex(of: liquidity)!, "")
        }
    }

    /// An English label, e.g. "Real estate", "Crypto & gold" or "No institution".
    public var description: String {
        switch self {
        case .assetClass(let assetClass):
            switch assetClass {
            case .equity: "Equity"
            case .bonds: "Bonds"
            case .cash: "Cash"
            case .gold: "Gold"
            case .crypto: "Crypto"
            case .realEstate: "Real estate"
            case .other: "Other"
            default: assetClass.rawValue
            }
        case .debts: "Debts"
        case .accountGroup(let group): group.description
        case .currency(let code): code.rawValue
        case .institution(let name): name ?? "No institution"
        case .liquidity(let liquidity): liquidity.description
        }
    }
}

/// One group's value in a breakdown.
public struct BreakdownSlice: Hashable, Sendable, Identifiable {
    public let key: BreakdownKey
    /// The value in the base currency; negative for debts.
    public let value: Decimal
    /// The value as a fraction of the breakdown's total (net worth). `nil`
    /// when the total is zero.
    public let share: Decimal?
    /// The value as a fraction of the sum of the positive slices (what you
    /// own), the usual basis for an allocation. Debts get a negative share.
    /// `nil` when nothing is positive.
    public let shareOfAssets: Decimal?
    /// The accounts contributing to the slice, sorted.
    public let accounts: [AccountID]

    public var id: BreakdownKey { key }
}

/// Values on one date grouped along one dimension.
public struct Breakdown: Hashable, Sendable {
    public let date: CalendarDate
    public let dimension: BreakdownDimension
    /// Largest value first, so debts come last.
    public let slices: [BreakdownSlice]
    /// The sum of all slices: net worth, or plan assets.
    public let total: Decimal
    /// The sum of the positive slices.
    public let assets: Decimal
    /// Whether every account was valued completely.
    public let isComplete: Bool

    /// The value of one group, or zero if it has none.
    public func value(of key: BreakdownKey) -> Decimal {
        slice(for: key)?.value ?? 0
    }

    /// The slice for `key`, if any account contributes to it.
    public func slice(for key: BreakdownKey) -> BreakdownSlice? {
        slices.first { $0.key == key }
    }
}

/// A breakdown over time, for a stacked chart.
public struct StackedSeries: Hashable, Sendable {
    public let dimension: BreakdownDimension
    /// Every group with a value on some date, in stacking order (bottom first).
    public let keys: [BreakdownKey]
    /// One breakdown per date.
    public let points: [Breakdown]

    /// Breakdowns along `dimension`, one per date, with their groups in stacking order.
    public init(dimension: BreakdownDimension, breakdowns: [Breakdown]) {
        self.dimension = dimension
        keys = Set(breakdowns.flatMap { $0.slices.map(\.key) }).sorted()
        points = breakdowns
    }

    /// The values of one group over time; zero on dates where it has none.
    public func series(for key: BreakdownKey) -> [SeriesPoint] {
        points.map { SeriesPoint(date: $0.date, value: $0.value(of: key), isComplete: $0.isComplete) }
    }
}

// MARK: - Computing breakdowns

extension Valuator {
    /// The accounts in `scope` on `date`, grouped along `dimension`.
    public func breakdown(by dimension: BreakdownDimension, on date: CalendarDate,
                          in scope: NetWorthScope = .netWorth) -> Breakdown {
        breakdown(of: total(on: date, in: scope), by: dimension)
    }

    /// A total already computed, grouped along `dimension`.
    public func breakdown(of total: NetWorth, by dimension: BreakdownDimension) -> Breakdown {
        var values: [BreakdownKey: Decimal] = [:]
        var contributors: [BreakdownKey: Set<AccountID>] = [:]
        for value in total.accounts {
            guard let account = accounts[value.account] else { continue }
            for (key, amount) in parts(of: value, account: account, by: dimension) {
                values[key, default: 0] += amount
                contributors[key, default: []].insert(account.id)
            }
        }
        let net = values.values.reduce(0, +)
        let assets = values.values.filter { $0 > 0 }.reduce(0, +)
        let slices = values.map { key, value in
            BreakdownSlice(key: key, value: value, share: net == 0 ? nil : value / net,
                           shareOfAssets: assets == 0 ? nil : value / assets,
                           accounts: contributors[key, default: []].sorted())
        }.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
        return Breakdown(date: total.date, dimension: dimension, slices: slices, total: net, assets: assets,
                         isComplete: total.isComplete)
    }

    /// The breakdown on every date of a series, with its groups in stacking order.
    public func breakdownSeries(by dimension: BreakdownDimension = .assetClass, in scope: NetWorthScope = .netWorth,
                                grid: SeriesGrid = .monthEnds, through end: CalendarDate) -> StackedSeries {
        let points = dates(grid, in: scope, through: end).map { breakdown(by: dimension, on: $0, in: scope) }
        return StackedSeries(dimension: dimension, breakdowns: points)
    }

    /// One account's value split along `dimension`. Parts that couldn't be valued are left out.
    func parts(of value: AccountValue, account: Account,
               by dimension: BreakdownDimension) -> [(BreakdownKey, Decimal)] {
        switch dimension {
        case .assetClass:
            if account.kind.isLiability { return [(.debts, value.knownValue)] }
            return value.components.flatMap { component -> [(BreakdownKey, Decimal)] in
                guard let amount = component.value else { return [] }
                return split(amount, by: assetMix(of: component.kind, in: account)).map { (.assetClass($0), $1) }
            }
        case .accountGroup:
            return [(.accountGroup(account.group), value.knownValue)]
        case .currency:
            return value.components.compactMap { component in
                guard let amount = component.value, let currency = component.currency else { return nil }
                return (.currency(currency), amount)
            }
        case .institution:
            let name = account.institution.flatMap { $0.isEmpty ? nil : $0 }
            return [(.institution(name), value.knownValue)]
        case .liquidity:
            return [(.liquidity(account.liquidity), value.knownValue)]
        }
    }

    /// The asset mix of one part of an account, as shares that sum to 1:
    /// cash held with positions is cash, a position follows its instrument,
    /// and a balance follows the account's effective mix. Anything without a
    /// usable mix is `other`.
    func assetMix(of kind: ValueComponent.Kind, in account: Account) -> [(AssetClass, Decimal)] {
        let mix: AssetMix? = switch kind {
        case .cash: .single(.cash)
        case .balance: account.effectiveAssetClasses
        case .position(let instrument): instruments[instrument]?.assetClasses
        }
        guard let mix, mix.total > 0 else { return [(.other, 1)] }
        let total = mix.total
        return mix.assetClasses.compactMap { assetClass in
            let share = mix[assetClass]
            guard share != 0 else { return nil }
            return (assetClass, total == 1 ? share : share / total)
        }
    }

    /// Splits `amount` by `shares` so the parts add up to `amount` exactly:
    /// the last part takes the remainder.
    func split<Key>(_ amount: Decimal, by shares: [(Key, Decimal)]) -> [(Key, Decimal)] {
        guard shares.count > 1 else { return shares.map { ($0.0, amount) } }
        var parts: [(Key, Decimal)] = []
        var remaining = amount
        for (index, (key, share)) in shares.enumerated() {
            let part = index == shares.count - 1 ? remaining : amount * share
            parts.append((key, part))
            remaining -= part
        }
        return parts
    }
}
