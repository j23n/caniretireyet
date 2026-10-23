import Foundation
import Model
import Tracker

/// The money a plan starts with (PLANNER.md, "The portfolio"): the accounts it
/// counts, valued on the start date in the base currency, grouped by when
/// they can be drawn and how what's taken from them is taxed. Bucket 0 is
/// the taxable money you can draw now; each other bucket holds the accounts
/// available from one later age (`availableFromAge`), or pre-tax accounts
/// with one withdrawal tax rate (`withdrawalTaxRate`), or both. A taxable
/// bucket joins bucket 0 when its age is reached; a pre-tax bucket stays a
/// group of its own, drawn alongside bucket 0 from that age (now, without one).
struct Portfolio: Sendable {
    struct Bucket: Sendable {
        let name: String
        /// The age from which it can be drawn; `nil` when it can be drawn now.
        let opensAtAge: Int?
        /// The share of every amount sold from it that goes to tax, in place
        /// of the plan's rate on investments; `nil` for taxable money.
        var withdrawalRate: Double? = nil
        /// Value per class (``Portfolio/classes``).
        var values: [Double]
        /// What was paid for what it holds, in today's money: what a sale
        /// counts as gain is the rest. Pre-tax money's is its value: its
        /// gains aren't taxed.
        var basis: Double
        let accounts: [AccountID]

        var value: Double { values.reduce(0, +) }
        /// Whether it's pre-tax money (``withdrawalRate``).
        var isPreTax: Bool { withdrawalRate != nil }
    }

    var buckets: [Bucket]
    /// Every asset class a bucket can hold, in canonical order.
    let classes: [AssetClass]
    /// The value of the included accounts, exactly as the tracker computes it,
    /// less the tax on what paying off the debts took from pre-tax buckets
    /// (``debtWithdrawalTax``) and without the debts left unpaid
    /// (``debtUnpaid``), each to the cent: what the buckets hold, which the
    /// readiness and the assets-needed search are measured against.
    let startAssets: Decimal
    /// The value of the included accounts, exactly as the tracker computes
    /// it: where a baseline and the fan start.
    let trackedAssets: Decimal
    /// The included accounts, sorted.
    let accounts: [AccountID]
    /// Debts the plan counts, paid off at the start from the money you can
    /// draw: bucket 0 first, then the open pre-tax buckets.
    let debtPaidOff: Double
    /// The tax on withdrawals paid on what paying off the debts took from
    /// pre-tax buckets: part of the first year's tax on withdrawals, and
    /// taken off ``startAssets``.
    var debtWithdrawalTax = 0.0
    /// The part of the debts the money you can draw couldn't pay off, which
    /// the plan leaves out, of ``startAssets`` too.
    var debtUnpaid = 0.0

    var totalValue: Double { buckets.reduce(0) { $0 + $1.value } }
    /// What can be drawn on the start date: bucket 0 and the pre-tax buckets
    /// open from the start, the money the assets-needed search takes from.
    var accessibleValue: Double { drawableNow.reduce(0) { $0 + buckets[$1].value } }

    /// The buckets you can draw on the start date: bucket 0 and the pre-tax
    /// buckets open from the start.
    var drawableNow: [Int] { buckets.indices.filter { $0 == 0 || buckets[$0].opensAtAge == nil } }

    /// The portfolio with `extra` more money you can draw now (less, when
    /// negative), the way the assets-needed search changes it: new money goes
    /// into the taxable money (bucket 0), invested at `mix`, and costs what
    /// it's worth; money taken out comes from every bucket you can draw now
    /// in proportion, leaving their mixes and shares of gains as they were.
    func withExtra(_ extra: Double, mix: [Double]) -> Portfolio {
        var result = self
        if extra > 0 {
            for c in classes.indices { result.buckets[0].values[c] += extra * mix[c] }
            result.buckets[0].basis += extra
        } else if extra < 0 {
            let value = accessibleValue
            let keep = value > 0 ? max(0, 1 + extra / value) : 0
            for b in drawableNow {
                for c in classes.indices { result.buckets[b].values[c] *= keep }
                result.buckets[b].basis *= keep
            }
        }
        return result
    }

    /// The mix of the money you can draw now (bucket 0 and the pre-tax
    /// buckets open from the start) as shares of its value; `nil` when it's
    /// empty.
    var accessibleShares: [Double]? {
        var values = buckets[0].values
        for bucket in buckets.dropFirst() where bucket.opensAtAge == nil {
            for c in values.indices { values[c] += bucket.values[c] }
        }
        let value = values.reduce(0, +)
        guard value > 0 else { return nil }
        return values.map { $0 / value }
    }
}

extension Portfolio {
    /// Values the included accounts on `date` and groups them by when they
    /// can be drawn at `currentAge`. `extraClasses` (e.g. the target mixes')
    /// are added to the classes held. `valuator` is the library's, when the
    /// caller has one; without it, one is built.
    static func build(library: Library, valuator: Valuator? = nil, date: CalendarDate, plan: PlanDocument,
                      currentAge: Int, extraClasses: Set<AssetClass>, issues: inout [PlanIssue]) -> Portfolio {
        let valuator = valuator ?? Valuator(library: library)
        let excluded = Set(plan.portfolio.exclude)
        let gainShare = plan.portfolio.unrealizedGainShare.map { min(1, max(0, $0.doubleValue)) }
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
        /// When a group can be drawn and how it's taxed.
        struct Key: Hashable {
            var opensAt: Int?
            var withdrawalRate: Double?
        }
        let drawable = Key(opensAt: nil, withdrawalRate: nil)
        var groups: [Key: Group] = [drawable: Group()]
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
            let withdrawalRate = account.withdrawalTaxRate.map { min(1, max(0, $0.doubleValue)) }
            // Locked money's gains aren't taxed until it opens, pre-tax money's never.
            let locked = opensAt != nil || withdrawalRate != nil
            let key = Key(opensAt: opensAt, withdrawalRate: withdrawalRate)
            var group = groups[key] ?? Group()
            // The holdings and what was paid for them; `nil` when nobody knows.
            var parts: [(assetClass: AssetClass, value: Double, basis: Double?)] = []
            func add(_ assetClass: AssetClass, _ amount: Double, basis: Double?) {
                parts.append((assetClass, amount, basis))
            }

            for component in value.components {
                guard let amount = component.value?.doubleValue else { continue }
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
                            basis = recorded.doubleValue
                        } else if let quote = valuator.fx.quote(from: account.currency, to: valuator.baseCurrency,
                                                                 on: date) {
                            basis = quote.convert(recorded).doubleValue
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
            groups[key] = group
        }

        if !undocumented.isEmpty {
            let names = Wording.list(undocumented)
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
        // The money you can draw first, then by age and by rate; taxable money first at an age.
        let order = groups.keys.sorted {
            ($0.opensAt ?? .min, $0.withdrawalRate ?? -1) < ($1.opensAt ?? .min, $1.withdrawalRate ?? -1)
        }
        var buckets = order.map { key -> Bucket in
            let group = groups[key]!
            return Bucket(name: key == drawable ? "Money you can draw" : group.name.joined(separator: ", "),
                          opensAtAge: key.opensAt, withdrawalRate: key.withdrawalRate,
                          values: classes.map { max(0, group.values[$0] ?? 0) },
                          basis: max(0, group.basis), accounts: group.accounts)
        }

        // Debts are paid off from the money you can draw: the taxable money's
        // cash first, then the rest of it proportionally, then the open
        // pre-tax money, the same share of each group, after its tax.
        var debtTax = 0.0
        var rest = debt
        if debt > 0 {
            if let cash = classes.firstIndex(of: .cash) {
                let take = min(rest, buckets[0].values[cash])
                buckets[0].values[cash] -= take
                buckets[0].basis = max(0, buckets[0].basis - take)
                rest -= take
            }
            let value = buckets[0].value
            if rest > 0, value > 0 {
                let take = min(rest, value)
                let keep = max(0, 1 - take / value)
                for c in classes.indices { buckets[0].values[c] *= keep }
                buckets[0].basis *= keep
                rest -= take
            }
            let preTax = buckets.indices.filter { $0 > 0 && buckets[$0].opensAtAge == nil }
            let net = preTax.reduce(0) { $0 + buckets[$1].value * (1 - (buckets[$1].withdrawalRate ?? 0)) }
            if rest > 0, net > 0 {
                let share = min(1, rest / net)
                for b in preTax {
                    debtTax += share * buckets[b].value * (buckets[b].withdrawalRate ?? 0)
                    for c in classes.indices { buckets[b].values[c] *= 1 - share }
                    buckets[b].basis *= 1 - share
                }
                rest = max(0, rest - share * net)
            }
            var message = "The plan includes debts of \(Int(debt.rounded())); it pays them off from the money you "
                + "can draw at the start"
            if debtTax > 0 {
                message += ", and the \(Int(debtTax.rounded())) of tax on what it takes from pre-tax accounts, "
                    + "counted in the first year's taxes and taken off the plan assets"
            }
            if rest > 0.5 {
                message += ". The money you can draw covers \(Int((debt - rest).rounded())) of them; the plan leaves "
                    + "the rest out, of the plan assets too"
            }
            message += ". Leave debts out of the plan if their payments are in your spending."
            issues.append(.warning("planner.debtIncluded", message, section: .portfolio))
        }
        // What the buckets hold: the debts left unpaid are left out.
        let startAssets = total - Decimal.rounded(debtTax, scale: 2) + Decimal.rounded(rest, scale: 2)
        return Portfolio(buckets: buckets, classes: classes, startAssets: startAssets, trackedAssets: total,
                         accounts: included.sorted(), debtPaidOff: debt, debtWithdrawalTax: debtTax, debtUnpaid: rest)
    }

    /// A mix as `Double` shares summing to 1, or `nil` if it's empty.
    static func shares(_ mix: AssetMix) -> [AssetClass: Double]? {
        let positive = mix.shares.mapValues(\.doubleValue).filter { $0.value > 0 }
        let total = positive.values.reduce(0, +)
        guard total > 0 else { return nil }
        return positive.mapValues { $0 / total }
    }
}
