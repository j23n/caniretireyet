import Foundation
import Model
import TaxKit
import Tracker

/// The starting portfolio, grouped into buckets by wrapper (PLANNER.md,
/// "Buckets"). Each bucket holds lots: one per asset class, tax category,
/// country and whether the purchase cost is known.
///
/// It stays editable until every wrapper that will receive money is known
/// (a tax system can credit a wrapper no account uses yet, such as TFR);
/// ``finalized()`` then gives the flat arrays the simulation runs on.
struct PortfolioBuilder: Sendable {
    struct Holding: Sendable {
        var assetClass: AssetClass
        var category: TaxCategory
        var country: String?
        var value: Double
        /// `nil` when the purchase cost is unknown and the plan gave no estimate.
        var basis: Double?

        var isCash: Bool { category == .cash }
    }

    struct Bucket: Sendable {
        let wrapper: String
        let name: String
        let category: WrapperCategory
        let rule: WrapperRule?
        var holdings: [Holding]
        var accounts: [AccountID]
        /// The earliest date an account joined the wrapper (or opened).
        var joined: CalendarDate?
        /// The country of the largest account, for new lots.
        var country: String?
        var targetMix: [AssetClass: Double]
        var receivesSavings = false

        var value: Double { holdings.reduce(0) { $0 + $1.value } }
    }

    /// Accounts that hold a pension scheme's record (its `seedWrapper`):
    /// they start the scheme rather than being a bucket.
    struct Seed: Sendable {
        let scheme: String
        let wrapper: String
        var accounts: [AccountID]
        /// Their value on the start date, in the plan's currency.
        var value: Double
    }

    /// Where a lot's purchase cost came from.
    enum BasisSource: String, Sendable {
        /// Its value: cash, and money in a tax-advantaged wrapper.
        case value
        /// The cost basis recorded in the check-in.
        case recorded
        /// Estimated from the plan's `unrealizedGainShare`.
        case estimated
        /// Unknown: no record and no estimate.
        case unknown
    }

    /// How one library account was read, for the plan debugger.
    struct AccountReading: Sendable {
        enum Outcome: Sendable {
            /// In the bucket of this wrapper.
            case included(wrapper: String)
            /// Its value starts this pension scheme instead of being a bucket.
            case seed(scheme: String)
            /// Left out of the plan, and why.
            case leftOut(String)
        }

        /// One part of the account's value (cash, a balance or a position)
        /// and the lots it became.
        struct Part: Sendable {
            let instrument: InstrumentID?
            let isCash: Bool
            /// In the plan's currency; negative for a debt.
            let value: Double
            /// The conversion the tracker used, if any.
            let fx: FXQuote?
            let holdings: [Holding]
            let basis: BasisSource
        }

        let account: AccountID
        var outcome: Outcome
        /// The value the tracker computes, in the plan's currency.
        var value: Double?
        var parts: [Part] = []
    }

    private(set) var buckets: [Bucket]
    /// The pension schemes started from accounts, in the order first met.
    let seeds: [Seed]
    /// Every library account, by ID, and how it was read.
    let readings: [AccountReading]
    /// Debts included in the plan, paid off from liquid money at the start.
    let debtPaidOff: Double
    /// Every asset class a lot can hold, in canonical order.
    let classes: [AssetClass]
    /// The bucket new savings go into.
    let primaryLiquid: Int
    /// The target mix of a new taxable bucket.
    private let liquidMix: [AssetClass: Double]
    /// The value of the included accounts, exactly as the tracker computes it.
    let startAssets: Decimal
    /// The included accounts, sorted.
    let accounts: [AccountID]
    private let registry: TaxRegistry

    // MARK: - Building from the library

    /// Values the included accounts on `date`, in `currency`, and groups
    /// them into buckets. Accounts whose wrapper is in `seedWrappers` (a
    /// wrapper → the scheme it seeds) become ``seeds`` instead.
    init(library: Library, date: CalendarDate, plan: PlanDocument, registry: TaxRegistry,
         residence: (any TaxSystem)?, currency: CurrencyCode? = nil, seedWrappers: [String: String] = [:],
         issues: inout [PlanIssue]) {
        self.registry = registry
        let valuator = Self.valuator(library: library, currency: currency ?? library.settings.baseCurrency)
        let excluded = Set(plan.portfolio.exclude)
        let gainShare = plan.portfolio.unrealizedGainShare.map { min(1, max(0, $0.double)) }
        let planMix = plan.portfolio.targetMix.flatMap { Self.normalized($0, section: .portfolio, issues: &issues) }

        for id in plan.portfolio.exclude where library.accounts[id] == nil {
            issues.append(.warning("planner.unknownAccount", "Excluded account \(id) doesn't exist.",
                                   section: .portfolio, account: id))
        }

        var buckets: [Bucket] = []
        var seeds: [Seed] = []
        var debt = 0.0
        var undocumented: [AccountID] = []
        var included: [AccountID] = []
        var total: Decimal = 0

        var readings: [AccountID: AccountReading] = [:]
        for account in library.accounts.values {
            let reason: String? = if excluded.contains(account.id) {
                "excluded by the plan (portfolio.exclude)"
            } else if !account.includedInPlan {
                "left out of plans (includeIn.plan is false)"
            } else if let closed = account.closed, closed < date {
                "closed on \(closed)"
            } else if account.opened > date {
                "opened after the start date, on \(account.opened)"
            } else {
                nil
            }
            readings[account.id] = AccountReading(account: account.id, outcome: .leftOut(reason ?? "not valued"))
        }

        let candidates = library.accounts.values
            .filter { $0.includedInPlan && !excluded.contains($0.id) && $0.isOpen(on: date) }
            .sorted { $0.id < $1.id }
        for account in candidates {
            guard let value = valuator.value(of: account.id, on: date) else { continue }
            if value.status == .noValuation {
                issues.append(.warning("planner.noValuation",
                                       "\(account.name) has no value on or before \(date); the plan leaves it out.",
                                       section: .portfolio, account: account.id))
                readings[account.id]?.outcome = .leftOut("no value on or before \(date)")
                continue
            }
            readings[account.id]?.value = value.knownValue.double
            for problem in value.problems {
                issues.append(.warning("planner.incompleteValue",
                                       "\(problem.description); the plan counts only what could be valued.",
                                       section: .portfolio, account: account.id))
            }
            if let wrapper = account.wrapper?.rawValue, let scheme = seedWrappers[wrapper] {
                let amount = value.knownValue.double
                if let index = seeds.firstIndex(where: { $0.scheme == scheme }) {
                    seeds[index].accounts.append(account.id)
                    seeds[index].value += amount
                } else {
                    seeds.append(Seed(scheme: scheme, wrapper: wrapper, accounts: [account.id], value: amount))
                }
                readings[account.id]?.outcome = .seed(scheme: scheme)
                continue
            }
            if let wrapper = account.wrapper?.rawValue,
               let scheme = registry.systems.lazy.flatMap(\.pensionSchemes).first(where: { $0.seedWrapper == wrapper }) {
                issues.append(.warning("planner.seedWithoutPension",
                                       "\(account.name) holds a \(scheme.name) record, but the plan has no \(scheme.name) "
                                           + "pension; the plan treats it as an account.",
                                       section: .pensions, account: account.id))
            }
            included.append(account.id)
            total += value.knownValue

            let (wrapper, category, rule) = Self.wrapper(for: account, registry: registry, issues: &issues)
            readings[account.id]?.outcome = .included(wrapper: wrapper)
            var holdings: [Holding] = []
            for component in value.components {
                guard let amount = component.value?.double else { continue }
                var instrument: InstrumentID?
                if case .position(let id) = component.kind { instrument = id }
                if amount < 0 {
                    debt -= amount
                    readings[account.id]?.parts.append(AccountReading.Part(
                        instrument: instrument, isCash: component.kind == .cash, value: amount, fx: component.fx,
                        holdings: [], basis: .value))
                    continue
                }
                let (part, basis) = Self.holdings(of: component, value: amount, account: account,
                                                  valuation: value.valuation, library: library, valuator: valuator,
                                                  date: date, taxable: category == .taxable, gainShare: gainShare,
                                                  undocumented: &undocumented, issues: &issues)
                holdings += part
                readings[account.id]?.parts.append(AccountReading.Part(
                    instrument: instrument, isCash: component.kind == .cash, value: amount, fx: component.fx,
                    holdings: part, basis: basis))
            }

            let index: Int
            if let existing = buckets.firstIndex(where: { $0.wrapper == wrapper }) {
                index = existing
            } else {
                buckets.append(Bucket(wrapper: wrapper, name: rule?.name ?? wrapper, category: category, rule: rule,
                                      holdings: [], accounts: [], joined: nil, country: nil, targetMix: [:]))
                index = buckets.count - 1
            }
            let joined = account.tax?.joined ?? account.opened
            buckets[index].joined = min(buckets[index].joined ?? joined, joined)
            if buckets[index].country == nil || holdings.reduce(0, { $0 + $1.value }) > buckets[index].value {
                buckets[index].country = account.country?.rawValue ?? buckets[index].country
            }
            buckets[index].holdings += holdings
            buckets[index].accounts.append(account.id)
        }

        if !undocumented.isEmpty {
            let names = Set(undocumented).sorted().map(\.rawValue).joined(separator: ", ")
            issues.append(.warning("planner.unknownCostBasis",
                                   "Some positions have no purchase cost (\(names)). Record it, or set "
                                       + "portfolio.unrealizedGainShare; until then the tax system treats the purchase cost as unknown.",
                                   section: .portfolio, option: "unrealizedGainShare"))
        }

        // Merge lots and set target mixes.
        var overall: [AssetClass: Double] = [:]
        for index in buckets.indices {
            buckets[index].holdings = Self.merged(buckets[index].holdings)
            for holding in buckets[index].holdings { overall[holding.assetClass, default: 0] += holding.value }
        }
        let overallMix = Self.shares(overall)
        let liquidMix = planMix ?? overallMix ?? [.cash: 1]

        // New savings go into the largest taxable bucket, or a new one.
        var primary = buckets.indices.filter { buckets[$0].category == .taxable }
            .max { buckets[$0].value < buckets[$1].value }
        if primary == nil {
            let id = residence?.wrappers.first { $0.category == .taxable }?.id ?? WrapperID.taxable.rawValue
            let rule = registry.wrapper(id)
            buckets.append(Bucket(wrapper: id, name: rule?.name ?? id, category: .taxable, rule: rule, holdings: [],
                                  accounts: [], joined: date, country: nil, targetMix: liquidMix))
            primary = buckets.count - 1
        }
        buckets[primary!].receivesSavings = true
        for index in buckets.indices {
            let own = Self.shares(buckets[index].holdings.reduce(into: [:]) { $0[$1.assetClass, default: 0] += $1.value })
            if buckets[index].category == .taxable {
                buckets[index].targetMix = planMix ?? own ?? liquidMix
            } else {
                buckets[index].targetMix = own ?? [.cash: 1]
            }
        }

        // Debts included in the plan are paid off from liquid money at the start.
        if debt > 0 {
            issues.append(.warning("planner.debtIncluded",
                                   "The plan includes debts of \(Int(debt.rounded())); it pays them off from liquid "
                                       + "money at the start. Leave debts out of the plan if their payments are in your spending.",
                                   section: .portfolio))
            Self.payOff(debt, from: &buckets, primary: primary!)
        }

        var classes = Set(liquidMix.keys).union([.cash])
        for bucket in buckets {
            classes.formUnion(bucket.targetMix.keys)
            classes.formUnion(bucket.holdings.map(\.assetClass))
        }
        self.classes = AssetClass.knownValues.filter(classes.contains)
            + classes.subtracting(AssetClass.knownValues).sorted()
        self.buckets = buckets
        self.seeds = seeds
        self.readings = readings.keys.sorted().map { readings[$0]! }
        self.debtPaidOff = debt
        self.primaryLiquid = primary!
        self.liquidMix = liquidMix
        self.startAssets = total
        self.accounts = included
    }

    /// The bucket for a wrapper, if there is one.
    func bucketIndex(wrapper: String) -> Int? {
        buckets.firstIndex { $0.wrapper == wrapper }
    }

    /// Adds an empty bucket for a wrapper that receives money but that no
    /// included account uses. Returns a warning to show, unless the caller
    /// expects the money there (a scheme's lump sum moving into it).
    mutating func addBucket(wrapper: String) -> PlanIssue? {
        guard bucketIndex(wrapper: wrapper) == nil else { return nil }
        let rule = registry.wrapper(wrapper)
        let category = rule?.category ?? WrapperCategory(rawValue: wrapper) ?? .taxable
        let mix = category == .taxable ? liquidMix : [.cash: 1]
        buckets.append(Bucket(wrapper: wrapper, name: rule?.name ?? wrapper, category: category, rule: rule,
                              holdings: [], accounts: [], joined: nil, country: nil, targetMix: mix))
        guard category != .taxable else { return nil }
        return .warning("planner.newWrapper",
                        "Money goes into \(rule?.name ?? wrapper), which none of the plan's accounts use; "
                            + "the plan invests it as cash.",
                        section: .portfolio)
    }

    // MARK: - Finalizing

    /// The flat arrays the simulation runs on.
    func finalized() -> Portfolio {
        let classCount = classes.count
        let classIndex = Dictionary(uniqueKeysWithValues: classes.enumerated().map { ($1, $0) })
        var lots: [Portfolio.Lot] = []
        var infos: [Portfolio.BucketInfo] = []
        var targetShares = [Double](repeating: 0, count: buckets.count * classCount)
        var depositLot = [Int](repeating: -1, count: buckets.count * classCount)

        for (b, bucket) in buckets.enumerated() {
            let first = lots.count
            // Lots in a fixed order (by class, then as the holdings came), so
            // sums over them are the same in every process.
            let sorted = bucket.holdings.enumerated().sorted {
                (classIndex[$0.element.assetClass]!, $0.offset) < (classIndex[$1.element.assetClass]!, $1.offset)
            }.map(\.element)
            for holding in sorted {
                lots.append(Portfolio.Lot(bucket: b, classIndex: classIndex[holding.assetClass]!,
                                          category: holding.category, country: holding.country,
                                          documented: holding.basis != nil, value: holding.value,
                                          basis: holding.basis ?? 0))
            }
            for (assetClass, share) in bucket.targetMix.sorted(by: { classIndex[$0.key]! < classIndex[$1.key]! })
                where share > 0 {
                let c = classIndex[assetClass]!
                targetShares[b * classCount + c] = share
                let inClass = (first..<lots.count).filter { lots[$0].classIndex == c }
                let wantsCash = assetClass == .cash
                let candidate = inClass.filter { lots[$0].documented && (!wantsCash || lots[$0].isCash) }
                    .max { lots[$0].value < lots[$1].value }
                if let candidate {
                    depositLot[b * classCount + c] = candidate
                } else {
                    let largest = inClass.max { lots[$0].value < lots[$1].value }
                    let category = wantsCash ? .cash
                        : largest.map { lots[$0].category } ?? Self.defaultCategory(for: assetClass)
                    lots.append(Portfolio.Lot(bucket: b, classIndex: c, category: category, country: bucket.country,
                                              documented: true, value: 0, basis: 0))
                    depositLot[b * classCount + c] = lots.count - 1
                }
            }
            infos.append(Portfolio.BucketInfo(
                wrapper: bucket.wrapper, name: bucket.name, category: bucket.category, rule: bucket.rule,
                growthTaxRate: bucket.rule?.growthTaxRate ?? 0, lots: first..<lots.count, joined: bucket.joined,
                accounts: bucket.accounts, receivesSavings: bucket.receivesSavings,
                targetMix: bucket.targetMix))
        }
        return Portfolio(buckets: infos, lots: lots, classes: classes, primaryLiquid: primaryLiquid,
                         targetShares: targetShares, depositLot: depositLot)
    }

    // MARK: - Helpers

    /// A valuator that values in `currency`: the library's own when it's the
    /// base currency, else one converting at the library's FX rates.
    private static func valuator(library: Library, currency: CurrencyCode) -> Valuator {
        guard currency != library.settings.baseCurrency else { return Valuator(library: library) }
        return Valuator(baseCurrency: currency, accounts: Array(library.accounts.values),
                        valuations: library.months.values.flatMap(\.valuations), prices: PriceTable(library: library),
                        fx: FXTable(library: library), instruments: Array(library.instruments.values),
                        trades: library.months.values.flatMap(\.trades))
    }

    /// The wrapper an account belongs to, its category and its rule.
    private static func wrapper(for account: Account, registry: TaxRegistry, issues: inout [PlanIssue])
        -> (String, WrapperCategory, WrapperRule?) {
        let lockedKind = account.kind == .pensionFund || account.kind == .tfr
        guard let id = account.wrapper?.rawValue else {
            return lockedKind ? (WrapperID.taxDeferred.rawValue, .taxDeferred, registry.wrapper("taxDeferred"))
                              : (WrapperID.taxable.rawValue, .taxable, registry.wrapper("taxable"))
        }
        if let rule = registry.wrapper(id) { return (id, rule.category, rule) }
        if let generic = WrapperCategory(rawValue: id) { return (id, generic, nil) }
        let category: WrapperCategory = lockedKind ? .taxDeferred : .taxable
        issues.append(.warning("planner.unknownWrapper",
                               "No tax system defines the wrapper \(id) of \(account.name); the plan treats it as "
                                   + "\(category.rawValue), with no access limits.",
                               section: .portfolio, account: account.id))
        return (id, category, nil)
    }

    /// The lots one part of an account's value becomes, and where their
    /// purchase cost came from.
    private static func holdings(of component: ValueComponent, value: Double, account: Account,
                                 valuation: Valuation?, library: Library, valuator: Valuator, date: CalendarDate,
                                 taxable: Bool, gainShare: Double?, undocumented: inout [AccountID],
                                 issues: inout [PlanIssue]) -> ([Holding], BasisSource) {
        let country = account.country?.rawValue
        let estimate: BasisSource = gainShare == nil ? .unknown : .estimated
        func estimatedBasis(_ value: Double) -> Double? {
            if let gainShare { return value * (1 - gainShare) }
            undocumented.append(account.id)
            return nil
        }

        switch component.kind {
        case .cash:
            return ([Holding(assetClass: .cash, category: .cash, country: country, value: value, basis: value)], .value)

        case .balance:
            guard let mix = account.effectiveAssetClasses.flatMap({ Self.shares($0) }) else {
                issues.append(.warning("planner.noAssetMix",
                                       "\(account.name) has no asset mix (assetClasses); the plan treats it as cash.",
                                       section: .portfolio, account: account.id))
                return ([Holding(assetClass: .cash, category: .cash, country: country, value: value, basis: value)],
                        .value)
            }
            var source = BasisSource.value
            let holdings = mix.sorted(by: { $0.key < $1.key }).map { assetClass, share in
                let part = value * share
                let category = balanceCategory(kind: account.kind, assetClass: assetClass)
                let isValue = category == .cash || !taxable
                if !isValue { source = estimate }
                let basis = isValue ? part : estimatedBasis(part)
                return Holding(assetClass: assetClass, category: category, country: country, value: part, basis: basis)
            }
            return (holdings, source)

        case .position(let instrumentID):
            let instrument = library.instruments[instrumentID]
            let mix = instrument.flatMap { Self.shares($0.assetClasses) } ?? [.other: 1]
            let category = instrument.map(Self.category(of:)) ?? .other
            var basis: Double?
            var source = BasisSource.recorded
            if let recorded = valuation?.position(for: instrumentID)?.costBasis {
                if account.currency == valuator.baseCurrency {
                    basis = recorded.double
                } else if let quote = valuator.fx.quote(from: account.currency, to: valuator.baseCurrency, on: date) {
                    basis = quote.convert(recorded).double
                }
            }
            if !taxable {
                basis = value
                source = .value
            } else if basis == nil {
                basis = estimatedBasis(value)
                source = estimate
            }
            let govShare = instrument?.tax?.govBondShare.map { min(1, max(0, $0.double)) } ?? 0
            var result: [Holding] = []
            for (assetClass, share) in mix.sorted(by: { $0.key < $1.key }) {
                var part = share
                if assetClass == .bonds, govShare > 0 {
                    let gov = min(govShare, share)
                    result.append(Holding(assetClass: .bonds, category: .governmentBond, country: country,
                                          value: value * gov, basis: basis.map { $0 * gov }))
                    part -= gov
                }
                guard part > 0 else { continue }
                result.append(Holding(assetClass: assetClass, category: category, country: country,
                                      value: value * part, basis: basis.map { $0 * part }))
            }
            return (result, source)
        }
    }

    /// Holdings with the same class, category, country and cost knowledge, summed.
    private static func merged(_ holdings: [Holding]) -> [Holding] {
        var result: [Holding] = []
        for holding in holdings where holding.value > 0 {
            if let index = result.firstIndex(where: {
                $0.assetClass == holding.assetClass && $0.category == holding.category
                    && $0.country == holding.country && ($0.basis == nil) == (holding.basis == nil)
            }) {
                result[index].value += holding.value
                if let basis = holding.basis { result[index].basis = (result[index].basis ?? 0) + basis }
            } else {
                result.append(holding)
            }
        }
        return result
    }

    /// Reduces liquid holdings by `debt`: cash in the primary bucket first,
    /// then every liquid holding proportionally.
    private static func payOff(_ debt: Double, from buckets: inout [Bucket], primary: Int) {
        var remaining = debt
        for index in buckets[primary].holdings.indices where buckets[primary].holdings[index].isCash {
            let take = min(remaining, buckets[primary].holdings[index].value)
            buckets[primary].holdings[index].value -= take
            buckets[primary].holdings[index].basis = buckets[primary].holdings[index].value
            remaining -= take
        }
        let liquid = buckets.indices.filter { buckets[$0].category == .taxable }
        let available = liquid.reduce(0) { $0 + buckets[$1].value }
        guard remaining > 0, available > 0 else { return }
        let keep = max(0, 1 - remaining / available)
        for b in liquid {
            for h in buckets[b].holdings.indices {
                buckets[b].holdings[h].value *= keep
                buckets[b].holdings[h].basis = buckets[b].holdings[h].basis.map { $0 * keep }
            }
        }
    }

    /// A mix as `Double` shares summing to 1, or `nil` if it's empty.
    static func shares(_ mix: AssetMix) -> [AssetClass: Double]? {
        shares(mix.shares.mapValues(\.double))
    }

    static func shares(_ amounts: [AssetClass: Double]) -> [AssetClass: Double]? {
        let positive = amounts.filter { $0.value > 0 }
        // Summed in the classes' order: a dictionary's order changes from one process to the next.
        let total = positive.sorted { $0.key < $1.key }.reduce(0) { $0 + $1.value }
        guard total > 0 else { return nil }
        return positive.mapValues { $0 / total }
    }

    /// The plan's target mix, normalised, with a warning when it doesn't sum to 1.
    private static func normalized(_ mix: AssetMix, section: PlanSection,
                                   issues: inout [PlanIssue]) -> [AssetClass: Double]? {
        guard let shares = shares(mix) else { return nil }
        if abs(mix.total.double - 1) > 0.001 {
            issues.append(.warning("planner.targetMixTotal", "The target mix doesn't add up to 100%; the plan scales it.",
                                   section: section, option: "targetMix"))
        }
        return shares
    }

    /// The tax category of an instrument, from its kind: an ETF or fund by
    /// what kind of fund it is (``fundCategory(of:)``), an ETC with a
    /// delivery claim as such.
    static func category(of instrument: Instrument) -> TaxCategory {
        switch instrument.kind {
        case .etf, .fund: fundCategory(of: instrument)
        case .stock: .stock
        case .bond: .bond
        case .etc: instrument.hasDeliveryClaim ? .etcWithDeliveryClaim : .etc
        case .crypto: .crypto
        case .metal: .physicalGold
        default: .other
        }
    }

    /// The category of an ETF or fund, by the kind of fund it is
    /// (`Instrument.effectiveFundType`: its `tax.fundType` when it gives one
    /// this version knows, else from its asset mix). The whole fund gets one
    /// category, so both parts of a 60/40 fund are an equity fund's.
    static func fundCategory(of instrument: Instrument) -> TaxCategory {
        switch instrument.effectiveFundType {
        case .equity?: .equityFund
        case .mixed?: .mixedFund
        case .realEstate?: .realEstateFund
        case .foreignRealEstate?: .foreignRealEstateFund
        default: .fund
        }
    }

    /// The tax category of part of a balance account.
    static func balanceCategory(kind: AccountKind, assetClass: AssetClass) -> TaxCategory {
        if assetClass == .cash { return .cash }
        switch kind {
        case .crypto: return .crypto
        case .metals: return .physicalGold
        case .property: return .realEstate
        default: return defaultCategory(for: assetClass)
        }
    }

    /// The tax category of new money invested in an asset class: equity in
    /// an equity fund, bonds in a (bond) fund.
    static func defaultCategory(for assetClass: AssetClass) -> TaxCategory {
        switch assetClass {
        case .equity: .equityFund
        case .bonds: .fund
        case .cash: .cash
        case .gold: .etc
        case .crypto: .crypto
        case .realEstate: .realEstate
        default: .other
        }
    }
}

/// The finalized portfolio: lots in contiguous ranges per bucket, with the
/// targets and the lot each class's new money goes into.
struct Portfolio: Sendable {
    struct Lot: Sendable {
        let bucket: Int
        let classIndex: Int
        let category: TaxCategory
        let country: String?
        /// Whether the purchase cost is known.
        let documented: Bool
        var value: Double
        var basis: Double

        var isCash: Bool { category == .cash }
    }

    struct BucketInfo: Sendable {
        let wrapper: String
        let name: String
        let category: WrapperCategory
        let rule: WrapperRule?
        let growthTaxRate: Double
        let lots: Range<Int>
        let joined: CalendarDate?
        let accounts: [AccountID]
        let receivesSavings: Bool
        let targetMix: [AssetClass: Double]

        var isLiquid: Bool { category == .taxable }
    }

    let buckets: [BucketInfo]
    let lots: [Lot]
    let classes: [AssetClass]
    let primaryLiquid: Int
    /// Target share per bucket and class, indexed `bucket * classes.count + class`.
    let targetShares: [Double]
    /// The lot new money goes into per bucket and class (`-1` for none).
    let depositLot: [Int]

    var classCount: Int { classes.count }

    /// The value of every lot at the start.
    var totalValue: Double { lots.reduce(0) { $0 + $1.value } }

    func bucketIndex(wrapper: String) -> Int? {
        buckets.firstIndex { $0.wrapper == wrapper }
    }

    /// The value of the liquid (taxable) buckets at the start: the money
    /// that can be drawn at any age, which ``withExtra(_:)`` adds to or
    /// takes from.
    var accessibleValue: Double {
        lots.reduce(0) { $0 + (buckets[$1.bucket].isLiquid ? $1.value : 0) }
    }

    /// The same portfolio with `extra` more money in the buckets that can be
    /// drawn at any age, the liquid ones (PLANNER.md, "Assets needed to
    /// retire today"); tax-advantaged buckets stay as they are. More money
    /// is split between the liquid buckets by their value (all of it into
    /// the one that receives savings when they're empty), and within each by
    /// its target mix, into the lots new money goes to, at a purchase cost
    /// equal to the amount: new money carries no unrealised gain. Less money
    /// (`extra` < 0) comes out of every liquid lot in proportion, value and
    /// purchase cost alike, never below zero. For "assets needed to retire
    /// today" (``Engine/assetsNeeded(age:startAssets:successToday:progress:)``).
    func withExtra(_ extra: Double) -> Portfolio {
        guard extra != 0, extra.isFinite else { return self }
        var changed = lots
        let liquid = buckets.indices.filter { buckets[$0].isLiquid }
        let values = liquid.map { b in buckets[b].lots.reduce(0) { $0 + lots[$1].value } }
        let available = values.reduce(0, +)
        if extra < 0 {
            guard available > 0 else { return self }
            let keep = max(0, 1 + extra / available)
            for b in liquid {
                for index in buckets[b].lots {
                    changed[index].value *= keep
                    changed[index].basis *= keep
                }
            }
        } else {
            func targets(_ b: Int) -> [Double] {
                (0..<classCount).map { depositLot[b * classCount + $0] >= 0 ? targetShares[b * classCount + $0] : 0 }
            }
            var shares = zip(liquid, values).map { ($0, available > 0 ? $1 / available : 0) }
            if available <= 0 { shares = [(primaryLiquid, 1)] }
            for (b, share) in shares where share > 0 {
                // A bucket without a target (never the one receiving savings) adds to that one.
                let bucket = targets(b).reduce(0, +) > 0 ? b : primaryLiquid
                let weights = targets(bucket)
                let total = weights.reduce(0, +)
                guard total > 0 else { continue }
                for c in 0..<classCount where weights[c] > 0 {
                    let lot = depositLot[bucket * classCount + c]
                    let amount = extra * share * weights[c] / total
                    changed[lot].value += amount
                    changed[lot].basis += amount
                }
            }
        }
        return Portfolio(buckets: buckets, lots: changed, classes: classes, primaryLiquid: primaryLiquid,
                         targetShares: targetShares, depositLot: depositLot)
    }

    /// The same portfolio with every lot's value and purchase cost
    /// multiplied by `factor`: every bucket and class grows in proportion,
    /// and each lot keeps its share of unrealised gain. The plan debugger
    /// starts its runs from it when asked for a multiple of today's assets.
    func scaled(by factor: Double) -> Portfolio {
        guard factor != 1 else { return self }
        var scaled = lots
        for index in scaled.indices {
            scaled[index].value *= factor
            scaled[index].basis *= factor
        }
        return Portfolio(buckets: buckets, lots: scaled, classes: classes, primaryLiquid: primaryLiquid,
                         targetShares: targetShares, depositLot: depositLot)
    }
}
