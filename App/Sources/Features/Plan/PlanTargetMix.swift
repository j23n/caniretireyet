import Foundation
import Model
import Planner

/// The Target mix card (UI.md, "Target mix"): what the money you can draw
/// holds today next to the mix the plan rebalances it to, the
/// running total each mix needs, how each mix grows, and the changes with
/// age. Plain Swift: the view binds to `PlanPortfolio`'s `plan…`
/// subscripts (PlanBindings.swift), and nothing here writes a default:
/// "Today's mix" is no `targetMix` at all, and classes at 0 aren't written.
struct PlanTargetMixModel {
    /// One asset class's row.
    struct Row: Hashable, Identifiable {
        let assetClass: AssetClass
        var id: String { assetClass.rawValue }
        /// "Equity", "Real estate".
        let name: String
        /// Its share of the money you can draw today; `nil` without any.
        let ordinaryShare: Double?
        /// Its share of every account the plan counts today; `nil` without any.
        let allShare: Double?
        /// Its median real return a year under the plan's assumptions (`nil` without one).
        let median: Decimal?
    }

    let plan: PlanDocument
    /// What the plan starts with by class.
    let start: StartingMix
    /// Age on the start date; `nil` without a birth date.
    let currentAge: Int?
    /// One per class offered (``classes(plan:start:)``).
    let rows: [Row]

    init(plan: PlanDocument, library: Library, today: CalendarDate = .today()) {
        self.init(plan: plan, start: Planner.startingMix(plan: plan, library: library, today: today),
                  birthDate: library.settings.person?.birthDate)
    }

    init(plan: PlanDocument, start: StartingMix, birthDate: CalendarDate?) {
        self.plan = plan
        self.start = start
        currentAge = birthDate.map { $0.wholeYears(to: start.date) }
        let ordinary = start.accessibleShares
        let all = start.allShares
        rows = Self.classes(plan: plan, start: start).map { assetClass in
            Row(assetClass: assetClass, name: PlanIssueText.assetClassName(assetClass.rawValue),
                ordinaryShare: ordinary.isEmpty ? nil : ordinary[assetClass] ?? 0,
                allShare: all.isEmpty ? nil : all[assetClass] ?? 0,
                median: plan.assumptions.returnAssumption(for: assetClass)?.impliedMedianReal)
        }
    }

    // MARK: Classes and words

    /// The classes always offered, in the assumptions' order.
    static let standardClasses: [AssetClass] = [.equity, .bonds, .cash, .gold, .crypto, .realEstate]

    /// The standard classes, then any other the plan holds today or a mix names.
    static func classes(plan: PlanDocument, start: StartingMix) -> [AssetClass] {
        var others = Set(start.classes)
        for mix in [plan.portfolio.targetMix].compactMap({ $0 }) + plan.portfolio.targetMixByAge.map(\.mix) {
            others.formUnion(mix.shares.filter { $0.value != 0 }.keys)
        }
        others.subtract(standardClasses)
        return standardClasses + AssetClass.knownValues.filter(others.contains)
            + others.subtracting(AssetClass.knownValues).sorted()
    }

    /// The line at the top of the card.
    static let explanation = "Each year the plan rebalances the money you can draw back to this mix: new money "
        + "goes in at it, withdrawals sell every class alike, and rebalancing isn't taxed."

    /// Under "Today's mix".
    static let todaysMixExplanation = "The money you can draw is rebalanced back to its mix today, whatever it "
        + "holds, crypto included. Choose a mix to decide it yourself."

    /// The note under the card.
    static let wrappersNote = "Accounts available only from a later age, such as a pension fund, keep their own mix "
        + "until then."

    /// Under the table: what "Today" counts.
    static let todayNote = "Today: the share of the money you can draw, then of all plan assets."

    // MARK: Totals

    /// The mix "A mix I choose" starts from: today's mix of the money you
    /// can draw in whole percentages adding up to 100, else all equity.
    var suggestion: AssetMix {
        let shares = start.accessibleShares
        return shares.isEmpty ? .single(.equity) : Self.wholePercentages(shares)
    }

    /// Shares as whole percentages adding up to 100, by largest remainder
    /// (ties to the larger share, then the class's name); classes rounding
    /// to 0 are left out.
    static func wholePercentages(_ shares: [AssetClass: Double]) -> AssetMix {
        let total = shares.values.filter { $0 > 0 }.reduce(0, +)
        guard total > 0 else { return AssetMix() }
        let exact = shares.filter { $0.value > 0 }.map { ($0.key, $0.value / total * 100) }
        var percents = Dictionary(uniqueKeysWithValues: exact.map { ($0.0, Int($0.1.rounded(.down))) })
        let missing = 100 - percents.values.reduce(0, +)
        let order = exact.sorted {
            let (a, b) = ($0.1 - $0.1.rounded(.down), $1.1 - $1.1.rounded(.down))
            return a != b ? a > b : $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0
        }
        for (assetClass, _) in order.prefix(missing) { percents[assetClass, default: 0] += 1 }
        return AssetMix(percents.filter { $0.value > 0 }.mapValues { Decimal($0) / 100 })
    }

    /// What a mix's total needs, or `nil` when it's 100%: "Adds up to 95%:
    /// add 5%.", "Adds up to 110%: take off 10%."
    static func problem(_ mix: AssetMix?, locale: Locale = .current) -> String? {
        let total = mix?.total ?? 0
        guard total != 1 else { return nil }
        let percent = { (share: Decimal) in AmountFormat.number(share * 100, maxDigits: 2, locale: locale) + "%" }
        return total < 1 ? "Adds up to \(percent(total)): add \(percent(1 - total)) to reach 100%."
            : "Adds up to \(percent(total)): take off \(percent(total - 1)) to reach 100%."
    }

    /// "Total 100%", "Total 95%".
    static func totalText(_ mix: AssetMix?, locale: Locale = .current) -> String {
        "Total " + AmountFormat.number((mix?.total ?? 0) * 100, maxDigits: 2, locale: locale) + "%"
    }

    /// The median yearly growth of a mix rebalanced every year under the plan's assumptions.
    func growth(of mix: AssetMix) -> Double {
        Planner.growth(of: mix.shares.mapValues(\.doubleValue), assumptions: plan.assumptions)
    }

    /// The median yearly growth of the money you can draw's mix today, rebalanced every year;
    /// `nil` without any.
    var todaysGrowth: Double? {
        let shares = start.accessibleShares
        return shares.isEmpty ? nil : Planner.growth(of: shares, assumptions: plan.assumptions)
    }

    /// "Grows at a median of 2.9% a year, rebalanced every year (today's mix: 1.9%)."
    func growthText(of mix: AssetMix?, comparedWithToday: Bool = false, locale: Locale = .current) -> String? {
        guard let mix, mix.total > 0 else { return nil }
        var text = "Grows at a median of " + AmountFormat.percent(growth(of: mix), locale: locale)
            + " a year, rebalanced every year"
        if comparedWithToday, let today = todaysGrowth {
            text += " (today's mix: \(AmountFormat.percent(today, locale: locale)))"
        }
        return text + "."
    }

    // MARK: Changes with age

    /// The age a step gets when it stops starting at retirement, and the
    /// one "From retirement" stands for in words: the plan's retirement age,
    /// else ten years from today (60 without a birth date).
    var retirementAge: Int {
        plan.retirement.age.age ?? currentAge.map { $0 + 10 } ?? 60
    }

    /// A change after the plan's last one: from retirement when the plan
    /// has none yet, else ten years after the last age (or after
    /// retirement), before the plan's end. Its mix is the one in force
    /// before it, to edit from (all equity without one).
    static func newStep(in plan: PlanDocument, currentAge: Int?) -> TargetMixStep {
        let steps = plan.portfolio.targetMixByAge
        let mix = steps.last?.mix ?? plan.portfolio.targetMix ?? .single(.equity)
        guard steps.contains(where: { $0.fromAge == .retirement }) else {
            return TargetMixStep(fromAge: .retirement, mix: mix)
        }
        let last = steps.compactMap(\.fromAge.age).max() ?? plan.retirement.age.age ?? currentAge.map { $0 + 10 } ?? 60
        return TargetMixStep(fromAge: .age(min(plan.effectiveEndAge, max(last + 10, (currentAge ?? 0) + 1))), mix: mix)
    }

    /// The ages step `index` can start at: after today's age and the
    /// numbered step before it, before the numbered step after it, and no
    /// later than the plan's end.
    func ageRange(forStep index: Int) -> ClosedRange<Int> {
        let steps = plan.portfolio.targetMixByAge
        let before = steps.prefix(max(0, index)).compactMap(\.fromAge.age).max()
        let after = steps.dropFirst(index + 1).compactMap(\.fromAge.age).min()
        let low = max((before ?? 0) + 1, (currentAge ?? 0) + 1)
        let high = max(low, min((after ?? .max) - 1, plan.effectiveEndAge))
        return low...high
    }

    /// Whether step `index` is in force from the start whatever the
    /// retirement age: its age is at most today's.
    func hasStarted(step index: Int) -> Bool {
        let steps = plan.portfolio.targetMixByAge
        guard steps.indices.contains(index), let age = steps[index].fromAge.age, let currentAge else { return false }
        return age <= currentAge
    }

    /// "From 55", "From retirement".
    static func title(of start: AgeOrRetirement) -> String {
        switch start {
        case .age(let age): "From \(age)"
        case .retirement: "From retirement"
        }
    }

    /// Under a step already in force: "You're 56: this already applies from the start."
    func startedNote(step index: Int) -> String? {
        guard hasStarted(step: index), let currentAge else { return nil }
        return "You're \(currentAge): this already applies from the start."
    }

    // MARK: Summary

    /// The card's one line: "Today's mix", "Equity 80% · bonds 20% ·
    /// changes at retirement and 75".
    static func summary(_ portfolio: PlanPortfolio, locale: Locale = .current) -> String {
        var parts = [mixSummary(portfolio.targetMix, locale: locale)]
        let steps = portfolio.targetMixByAge.map { step -> String in
            switch step.fromAge {
            case .age(let age): "\(age)"
            case .retirement: "retirement"
            }
        }
        if !steps.isEmpty { parts.append("changes at " + PlanResultsText.list(steps)) }
        return parts.joined(separator: " · ")
    }

    /// One mix in words, largest share first: "Equity 80% · bonds 20%";
    /// "Today's mix" without one (the plan keeps what you hold).
    static func mixSummary(_ mix: AssetMix?, locale: Locale = .current) -> String {
        guard let mix, mix.total > 0 else { return "Today's mix" }
        let classes = mix.shares.filter { $0.value != 0 }.sorted { ($1.value, $0.key) < ($0.value, $1.key) }
        return classes.enumerated().map { index, entry in
            let name = PlanIssueText.assetClassName(entry.key.rawValue)
            return "\(index == 0 ? name : name.lowercased()) "
                + AmountFormat.number(entry.value * 100, maxDigits: 1, locale: locale) + "%"
        }.joined(separator: " · ")
    }
}
