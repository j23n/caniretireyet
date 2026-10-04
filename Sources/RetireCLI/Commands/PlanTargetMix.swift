import ArgumentParser
import Foundation
import Model
import Planner
import TaxKit

/// The plan's target mix in the CLI's words (`retire plan show` and
/// `retire plan set --target-mix`): reading mixes typed as
/// `equity=70%,bonds=30%`, the steps of a mix that changes with age
/// (`55:equity=60%,bonds=40%`, `retirement:…`), and the "Asset mix" table
/// with today's mix next to the target.
enum PlanTargetMix {
    // MARK: Reading

    /// `equity=70%,bonds=30%` (or `equity=0.7,bonds=0.3`) as a mix that adds
    /// up to 100%; classes at 0 are left out.
    static func mix(_ text: String, option: String) throws -> AssetMix {
        try mix(entries: text.split(separator: ",").map(String.init), option: option)
    }

    /// One `class=share` per entry, as a mix that adds up to 100%.
    static func mix(entries: [String], option: String) throws -> AssetMix {
        var shares: [AssetClass: Decimal] = [:]
        for entry in entries where !entry.trimmingCharacters(in: .whitespaces).isEmpty {
            let (assetClass, share) = try PlanSetCommand.share(entry, option: option, allowsDefault: false)
            guard let share, share >= 0 else { throw ValidationError("\(option): a share can't be negative.") }
            guard shares[assetClass] == nil else {
                throw ValidationError("\(option): \(assetClass) is given twice.")
            }
            shares[assetClass] = share
        }
        let total = shares.values.reduce(0, +)
        guard total == 1 else {
            throw ValidationError("\(option): the mix adds up to \(Format.exact(total * 100))%; it must add up to 100%.")
        }
        return AssetMix(shares.filter { $0.value != 0 })
    }

    /// `55:equity=60%,bonds=40%` or `retirement:…` as a step of the target mix.
    static func step(_ text: String, option: String) throws -> TargetMixStep {
        let parts = text.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else {
            throw ValidationError("\(option) takes age:mix, e.g. 55:equity=60%,bonds=40% or "
                + "retirement:equity=60%,bonds=40%, not “\(text)”.")
        }
        let start: MixStepStart
        if parts[0].lowercased() == "retirement" {
            start = .retirement
        } else if let age = Int(parts[0]), age >= 0 {
            start = .age(age)
        } else {
            throw ValidationError("\(option): “\(parts[0])” isn't an age or retirement.")
        }
        return TargetMixStep(fromAge: start, mix: try mix(parts[1], option: option))
    }

    /// The steps of `--target-mix-from`, in order; `none` alone for no steps.
    static func steps(_ texts: [String], option: String) throws -> [TargetMixStep] {
        if texts.count == 1, texts[0].lowercased() == "none" { return [] }
        let steps = try texts.map { text -> TargetMixStep in
            guard text.lowercased() != "none" else { throw ValidationError("\(option) none can't be given with steps.") }
            return try step(text, option: option)
        }
        var previous: Int?
        for step in steps {
            guard let age = step.fromAge.age else { continue }
            if let previous, age <= previous {
                throw ValidationError("\(option): the ages must go up: \(age) comes after \(previous).")
            }
            previous = age
        }
        return steps
    }

    // MARK: Words

    /// "equity 70%, bonds 30%": a mix's classes from the largest share.
    static func describe(_ mix: AssetMix) -> String {
        mix.shares.filter { $0.value != 0 }.sorted { ($1.value, $0.key) < ($0.value, $1.key) }
            .map { "\($0.key) \(Format.exact($0.value * 100))%" }.joined(separator: ", ")
    }

    /// "55", "retirement".
    static func describe(_ start: MixStepStart) -> String {
        switch start {
        case .age(let age): "\(age)"
        case .retirement: "retirement"
        }
    }

    // MARK: The table

    /// The "Asset mix" section of `retire plan show`: per class, its share of
    /// the ordinary (taxable) accounts and of all plan assets today, the
    /// target and each step, and its median return; then what the target does.
    static func lines(plan: PlanDocument, library: Library, registry: TaxRegistry, today: CalendarDate) -> [String] {
        let start = Planner.startingMix(plan: plan, library: library, registry: registry, today: today)
        let portfolio = plan.portfolio
        let currency = start.currency
        var lines = ["Asset mix"]
        let steps = portfolio.targetMixByAge
        let mixes = [portfolio.targetMix].compactMap { $0 } + steps.map(\.mix)
        var held = Set(start.classes)
        for mix in mixes { held.formUnion(mix.shares.filter { $0.value != 0 }.keys) }
        let classes = AssetClass.knownValues.filter(held.contains) + held.subtracting(AssetClass.knownValues).sorted()
        guard !classes.isEmpty else {
            lines.append("  Nothing to invest yet" + (portfolio.choosesTargetMix ? "; the target is set below." : "."))
            return lines + targetLines(plan: plan)
        }

        var columns: [TextTable.Column] = [.left("Class"), .right("Ordinary today"), .right("All today")]
        if portfolio.targetMix != nil || !steps.isEmpty { columns.append(.right("Target")) }
        columns += steps.map { .right("From \(describe($0.fromAge))") }
        columns.append(.right("Median"))
        var table = TextTable(columns)
        let ordinary = start.taxableShares
        let all = start.allShares
        func share(_ value: Double?) -> String {
            value.map { Format.percent(Decimal($0), places: 0) } ?? "–"
        }
        func target(_ mix: AssetMix?, _ assetClass: AssetClass) -> String {
            guard let mix else { return "own" }
            return mix[assetClass] == 0 ? "–" : "\(Format.exact(mix[assetClass] * 100))%"
        }
        for assetClass in classes {
            var row = [assetClass.rawValue, ordinary.isEmpty ? "–" : share(ordinary[assetClass] ?? 0),
                       all.isEmpty ? "–" : share(all[assetClass] ?? 0)]
            if portfolio.targetMix != nil || !steps.isEmpty { row.append(target(portfolio.targetMix, assetClass)) }
            row += steps.map { target($0.mix, assetClass) }
            row.append(Format.percent(plan.assumptions.returnAssumption(for: assetClass)?.impliedMedianReal))
            table.add(row)
        }
        lines += table.lines()
        lines.append("Today (\(start.date)): \(Format.amount(Decimal(start.taxableTotal), places: 0)) \(currency) in the "
            + "ordinary (taxable) accounts, \(Format.amount(Decimal(start.allTotal), places: 0)) \(currency) in all plan "
            + "assets. Median: each class's typical real return a year.")
        return lines + targetLines(plan: plan)
    }

    /// What the target does, and how its mixes grow.
    private static func targetLines(plan: PlanDocument) -> [String] {
        let portfolio = plan.portfolio
        var lines: [String] = []
        if portfolio.choosesTargetMix {
            lines.append("Each year the plan rebalances the ordinary accounts back to the target: new money buys what's "
                + "below it, withdrawals sell what's above, and the rest is sold and bought, with tax on gains. "
                + "Pension funds and other tax-advantaged accounts keep their own mix.")
            var growth: [String] = []
            if let mix = portfolio.targetMix { growth.append("the target \(median(of: mix, plan: plan))") }
            else { growth.append("until the first step, each ordinary account keeps its own mix") }
            for step in portfolio.targetMixByAge {
                growth.append("from \(describe(step.fromAge)) \(median(of: step.mix, plan: plan))")
            }
            lines.append("Median growth, rebalanced every year: " + growth.joined(separator: "; ") + ".")
        } else {
            lines.append("Target: today's mix. Each year the plan rebalances every ordinary account back to its own "
                + "mix today; set a target with --target-mix.")
        }
        return lines
    }

    /// "3.0%": a mix's median growth when rebalanced every year.
    private static func median(of mix: AssetMix, plan: PlanDocument) -> String {
        let growth = Planner.growth(of: mix.shares.mapValues { NSDecimalNumber(decimal: $0).doubleValue },
                                    assumptions: plan.assumptions)
        return Format.percent(Decimal(growth.medianReturn))
    }

    // MARK: JSON

    /// The target mix, its steps and today's mix, for `retire plan show --json`.
    struct JSON: Encodable {
        struct Step: Encodable {
            /// An age or `retirement`.
            var fromAge: String
            var mix: [String: String]
        }

        struct Today: Encodable {
            var date: CalendarDate
            /// Values, in the plan's currency.
            var ordinaryValue: String
            var allValue: String
            /// Shares by class, to 4 decimals.
            var ordinary: [String: String]
            var all: [String: String]
        }

        /// As written; absent: each ordinary account keeps its mix today.
        var targetMix: [String: String]?
        var targetMixByAge: [Step]
        var today: Today
    }

    static func json(plan: PlanDocument, library: Library, registry: TaxRegistry, today: CalendarDate) -> JSON {
        let start = Planner.startingMix(plan: plan, library: library, registry: registry, today: today)
        func strings(_ mix: AssetMix) -> [String: String] {
            Dictionary(uniqueKeysWithValues: mix.shares.map { ($0.key.rawValue, $0.value.fileString) })
        }
        func shares(_ shares: [AssetClass: Double]) -> [String: String] {
            Dictionary(uniqueKeysWithValues: shares.map { ($0.key.rawValue, Format.json(Decimal($0.value), places: 4)) })
        }
        return JSON(
            targetMix: plan.portfolio.targetMix.map(strings),
            targetMixByAge: plan.portfolio.targetMixByAge.map {
                JSON.Step(fromAge: describe($0.fromAge), mix: strings($0.mix))
            },
            today: JSON.Today(date: start.date, ordinaryValue: Format.json(Decimal(start.taxableTotal)),
                              allValue: Format.json(Decimal(start.allTotal)), ordinary: shares(start.taxableShares),
                              all: shares(start.allShares)))
    }
}
