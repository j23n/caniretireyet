import Foundation
import Model
import Tracker

/// The money a plan starts with (PLANNER.md, "Portfolio"): the accounts it
/// counts, valued on the start date in the base currency, grouped by when
/// they can be drawn. Bucket 0 is the money you can draw now; each other
/// bucket holds the accounts available from one later age
/// (`availableFromAge`), and joins bucket 0 when that age is reached.
struct Portfolio: Sendable {
    struct Bucket: Sendable {
        let name: String
        /// The age from which it can be drawn; `nil` for bucket 0.
        let opensAtAge: Int?
        /// Value per class (``Portfolio/classes``).
        var values: [Double]
        /// What was paid for what it holds, in today's money: what a sale
        /// counts as gain is the rest.
        var basis: Double
        let accounts: [AccountID]

        var value: Double { values.reduce(0, +) }
    }

    var buckets: [Bucket]
    /// Every asset class a bucket can hold, in canonical order.
    let classes: [AssetClass]
    /// The value of the included accounts, exactly as the tracker computes it.
    let startAssets: Decimal
    /// The included accounts, sorted.
    let accounts: [AccountID]
    /// Debts the plan counts, paid off from bucket 0 at the start.
    let debtPaidOff: Double

    var totalValue: Double { buckets.reduce(0) { $0 + $1.value } }
    /// What can be drawn on the start date: bucket 0.
    var accessibleValue: Double { buckets[0].value }

    /// The portfolio with `extra` more money you can draw now (less, when
    /// negative), the way the assets-needed search changes it: new money is
    /// invested at `mix` and costs what it's worth; money taken out leaves
    /// the mix and the share of gains as they were.
    func withExtra(_ extra: Double, mix: [Double]) -> Portfolio {
        var result = self
        if extra > 0 {
            for c in classes.indices { result.buckets[0].values[c] += extra * mix[c] }
            result.buckets[0].basis += extra
        } else if extra < 0 {
            let value = buckets[0].value
            let keep = value > 0 ? max(0, 1 + extra / value) : 0
            for c in classes.indices { result.buckets[0].values[c] *= keep }
            result.buckets[0].basis *= keep
        }
        return result
    }

    /// Bucket 0's mix as shares of its value; `nil` when it's empty.
    var accessibleShares: [Double]? {
        let value = buckets[0].value
        guard value > 0 else { return nil }
        return buckets[0].values.map { $0 / value }
    }
}

extension Portfolio {
    /// Values the included accounts on `date` and groups them by when they
    /// can be drawn at `currentAge`. `extraClasses` (e.g. the target mixes')
    /// are added to the classes held.
    static func build(library: Library, date: CalendarDate, plan: PlanDocument, currentAge: Int,
                      extraClasses: Set<AssetClass>, issues: inout [PlanIssue]) -> Portfolio {
        let valuator = Valuator(library: library)
        let excluded = Set(plan.portfolio.exclude)
        let gainShare = plan.portfolio.unrealizedGainShare.map { min(1, max(0, $0.double)) }
        for id in plan.portfolio.exclude where library.accounts[id] == nil {
            issues.append(.warning("planner.unknownAccount", "Excluded account \(id) doesn't exist.",
                                   section: .portfolio, account: id))
        }

        struct Group {
            var name: [String] = []
            var values: [AssetClass: Double] = [:]
            var basis = 0.0
            var accounts: [AccountID] = []
        }
        var groups: [Int?: Group] = [nil: Group()]
        var debt = 0.0
        var undocumented: [String] = []
        var included: [AccountID] = []
        var total: Decimal = 0

        let candidates = library.accounts.values
            .filter { $0.includedInPlan && !excluded.contains($0.id) && $0.isOpen(on: date) }
            .sorted { $0.id < $1.id }
        for account in candidates {
            guard let value = valuator.value(of: account.id, on: date) else { continue }
            if value.status == .noValuation {
                issues.append(.warning("planner.noValuation",
                                       "\(account.name) has no value on or before \(date); the plan leaves it out.",
                                       section: .portfolio, account: account.id))
                continue
            }
            for problem in value.problems {
                issues.append(.warning("planner.incompleteValue",
                                       "\(problem.description); the plan counts only what could be valued.",
                                       section: .portfolio, account: account.id))
            }
            included.append(account.id)
            total += value.knownValue
            let opensAt = account.availableFromAge.flatMap { $0 > currentAge ? $0 : nil }
            let locked = opensAt != nil
            var group = groups[opensAt] ?? Group()
            // The holdings and what was paid for them; `nil` when nobody knows.
            var parts: [(assetClass: AssetClass, value: Double, basis: Double?)] = []
            func add(_ assetClass: AssetClass, _ amount: Double, basis: Double?) {
                parts.append((assetClass, amount, basis))
            }

            for component in value.components {
                guard let amount = component.value?.double else { continue }
                if amount < 0 {
                    debt -= amount
                    continue
                }
                switch component.kind {
                case .cash:
                    add(.cash, amount, basis: amount)
                case .balance:
                    guard let mix = account.effectiveAssetClasses.flatMap(shares) else {
                        issues.append(.warning("planner.noAssetMix",
                                               "\(account.name) has no asset mix (assetClasses); the plan treats it "
                                                   + "as cash.", section: .portfolio, account: account.id))
                        add(.cash, amount, basis: amount)
                        continue
                    }
                    for (assetClass, share) in mix.sorted(by: { $0.key < $1.key }) {
                        let part = amount * share
                        add(assetClass, part, basis: assetClass == .cash || locked ? part : nil)
                    }
                case .position(let instrumentID):
                    let mix = library.instruments[instrumentID].flatMap { shares($0.assetClasses) } ?? [.other: 1]
                    var basis: Double?
                    if locked {
                        basis = amount
                    } else if let recorded = value.valuation?.position(for: instrumentID)?.costBasis {
                        if account.currency == valuator.baseCurrency {
                            basis = recorded.double
                        } else if let quote = valuator.fx.quote(from: account.currency, to: valuator.baseCurrency,
                                                                 on: date) {
                            basis = quote.convert(recorded).double
                        }
                    }
                    for (assetClass, share) in mix.sorted(by: { $0.key < $1.key }) {
                        add(assetClass, amount * share, basis: basis.map { $0 * share })
                    }
                }
            }
            for part in parts {
                group.values[part.assetClass, default: 0] += part.value
                group.basis += part.basis ?? gainShare.map { part.value * (1 - $0) } ?? 0
            }
            if gainShare == nil, parts.contains(where: { $0.basis == nil && $0.value > 0 }) {
                undocumented.append(account.name)
            }
            group.name.append(account.name)
            group.accounts.append(account.id)
            groups[opensAt] = group
        }

        if !undocumented.isEmpty {
            let names = Self.list(undocumented)
            issues.append(.warning(
                "planner.unknownCostBasis",
                "\(names) \(undocumented.count == 1 ? "has" : "have") holdings without a recorded purchase cost, "
                    + "so the plan taxes selling them as if their whole value were gain, which makes the results "
                    + "more pessimistic. Record their purchase cost, or set an estimate of the unrealised gains in "
                    + "the plan (portfolio.unrealizedGainShare).",
                section: .portfolio, option: "unrealizedGainShare"))
        }

        // With nothing held yet, savings go into cash.
        var held = Set(groups.values.flatMap { $0.values.filter { $0.value > 0 }.keys }).union(extraClasses)
        if held.isEmpty { held = [.cash] }
        let classes = AssetClass.knownValues.filter(held.contains) + held.subtracting(AssetClass.knownValues).sorted()
        let order = groups.keys.sorted { ($0 ?? .min) < ($1 ?? .min) }
        var buckets = order.map { key -> Bucket in
            let group = groups[key]!
            return Bucket(name: key == nil ? "Money you can draw" : group.name.joined(separator: ", "),
                          opensAtAge: key, values: classes.map { max(0, group.values[$0] ?? 0) },
                          basis: max(0, group.basis), accounts: group.accounts)
        }

        // Debts are paid off from the money you can draw: cash first, then the rest proportionally.
        if debt > 0 {
            issues.append(.warning("planner.debtIncluded",
                                   "The plan includes debts of \(Int(debt.rounded())); it pays them off from the "
                                       + "money you can draw at the start. Leave debts out of the plan if their "
                                       + "payments are in your spending.", section: .portfolio))
            var rest = debt
            if let cash = classes.firstIndex(of: .cash) {
                let take = min(rest, buckets[0].values[cash])
                buckets[0].values[cash] -= take
                buckets[0].basis = max(0, buckets[0].basis - take)
                rest -= take
            }
            let value = buckets[0].value
            if rest > 0, value > 0 {
                let keep = max(0, 1 - rest / value)
                for c in classes.indices { buckets[0].values[c] *= keep }
                buckets[0].basis *= keep
            }
        }
        return Portfolio(buckets: buckets, classes: classes, startAssets: total, accounts: included.sorted(),
                         debtPaidOff: debt)
    }

    /// A mix as `Double` shares summing to 1, or `nil` if it's empty.
    static func shares(_ mix: AssetMix) -> [AssetClass: Double]? {
        let positive = mix.shares.mapValues(\.double).filter { $0.value > 0 }
        let total = positive.values.reduce(0, +)
        guard total > 0 else { return nil }
        return positive.mapValues { $0 / total }
    }

    /// "A", "A and B", "A, B and C".
    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: ""
        case 1: names[0]
        default: names.dropLast().joined(separator: ", ") + " and " + names.last!
        }
    }
}
