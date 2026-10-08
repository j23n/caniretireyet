import Foundation
import Model

// Get/set views of plan values for the editors' controls, so the views
// bind by key path (`$plan.spending.phases[planSafe: 0, default: …].factor`,
// `$pension.planFromAge`) rather than with `Binding(get:set:)`
// closures. Plain Swift, tested without SwiftUI. Names start with `plan`
// so they can't collide with other extensions of the model types.

extension Array where Element: Hashable {
    /// The element at `index`, or `fallback` once it's gone (a row being
    /// deleted); writing past the end does nothing.
    subscript(planSafe index: Int, default fallback: Element) -> Element {
        get { indices.contains(index) ? self[index] : fallback }
        set { if indices.contains(index) { self[index] = newValue } }
    }
}

extension Dictionary where Value == Bool {
    /// Whether `key` is set, `false` by default: for expanded sections.
    subscript(planFlag key: Key) -> Bool {
        get { self[key] ?? false }
        set { self[key] = newValue }
    }
}

extension CalendarDate {
    /// The date as a `Date` for a `DatePicker` (noon, local time), and back.
    var planDate: Date {
        get { dateValue }
        set { self = CalendarDate(newValue, in: .current) }
    }
}

extension PlanDocument {
    /// "Retire as early as possible" (`retirement.age: earliest`).
    var planRetiresEarliest: Bool {
        get { retirement.age == .earliest }
        set { retirement.age = newValue ? .earliest : .age(retirement.age.age ?? 60) }
    }

    /// The retirement age, when the plan names one (60 until it does).
    var planRetirementAge: Int {
        get { retirement.age.age ?? 60 }
        set { retirement.age = .age(newValue) }
    }

    /// The last age the plan funds.
    var planEndAge: Int {
        get { effectiveEndAge }
        set { endAge = newValue }
    }
}

extension PlanSpending {
    // MARK: Flexible spending (PLANNER.md, "Flexible spending")

    /// Whether flexible spending is on. Turning it on keeps the settings
    /// the plan had (or uses the defaults); turning it off keeps settings
    /// that differ from the defaults (`enabled: false`) and otherwise
    /// removes the rule, so nothing is written.
    var planFlexibleOn: Bool {
        get { flexibleRule != nil }
        set {
            guard newValue != planFlexibleOn else { return }
            var rule = flexible ?? FlexibleSpending()
            rule.enabled = newValue
            flexible = newValue || !rule.usesDefaults ? rule : nil
        }
    }

    /// The cut, as written (`nil`: the default, 10%). A value equal to the
    /// default isn't written.
    var planFlexibleCut: Decimal? {
        get { flexible?.cut }
        set { updateFlexible { $0.cut = newValue == FlexibleSpending.defaultCut ? nil : newValue } }
    }

    /// The floor, as written (`nil`: the default, 80%).
    var planFlexibleFloor: Decimal? {
        get { flexible?.floor }
        set { updateFlexible { $0.floor = newValue == FlexibleSpending.defaultFloor ? nil : newValue } }
    }

    /// The upper guardrail, as written (`nil`: the default, 20%).
    var planFlexibleUpperGuardrail: Decimal? {
        get { flexible?.upperGuardrail }
        set {
            updateFlexible { $0.upperGuardrail = newValue == FlexibleSpending.defaultUpperGuardrail ? nil : newValue }
        }
    }

    /// The lower guardrail, as written (`nil`: the default, 20%).
    var planFlexibleLowerGuardrail: Decimal? {
        get { flexible?.lowerGuardrail }
        set {
            updateFlexible { $0.lowerGuardrail = newValue == FlexibleSpending.defaultLowerGuardrail ? nil : newValue }
        }
    }

    /// The floor in money: the floor share of retirement spending, before phases.
    var planFlexibleFloorAmount: Decimal {
        (flexible ?? FlexibleSpending()).effectiveFloor * retired
    }

    /// Changes the rule's settings; a rule the plan doesn't have is created on.
    private mutating func updateFlexible(_ change: (inout FlexibleSpending) -> Void) {
        var rule = flexible ?? FlexibleSpending()
        change(&rule)
        flexible = rule.isEnabled || !rule.usesDefaults ? rule : nil
    }
}

extension PlanTax {
    /// Whether the plan pays a wealth tax. Turning it off removes the rate
    /// and the allowance; turning it on starts at 0.2%.
    var planHasWealthTax: Bool {
        get { effectiveWealthRate > 0 }
        set {
            guard newValue != planHasWealthTax else { return }
            if newValue {
                wealthRate = Decimal(string: "0.002")!
            } else {
                wealthRate = nil
                wealthAllowance = nil
            }
        }
    }
}

extension PlanAssumptions {
    /// An asset class's expected real return as its mean (the average
    /// year), the plan's or the default; derived from the median when that's
    /// what's given. Setting it gives the return by its mean. What equals
    /// the default isn't written to the plan.
    subscript(planReal assetClass: AssetClass) -> Decimal {
        get { Self.rounded(returnAssumption(for: assetClass)?.real ?? 0) }
        set {
            var assumption = returnAssumption(for: assetClass) ?? ReturnAssumption(real: 0, volatility: 0)
            guard newValue != Self.rounded(assumption.real) || assumption.isGivenByMedian == false else { return }
            assumption.real = newValue
            setReturnAssumption(assumption, for: assetClass)
        }
    }

    /// An asset class's expected real return as its median (the typical
    /// year, which a rebalanced portfolio grows at), the plan's or the
    /// default; derived from the mean when that's what's given. Setting it
    /// gives the return by its median, so the mean follows the volatility.
    subscript(planMedianReal assetClass: AssetClass) -> Decimal {
        get { Self.rounded(returnAssumption(for: assetClass)?.impliedMedianReal ?? 0) }
        set {
            var assumption = returnAssumption(for: assetClass) ?? ReturnAssumption(real: 0, volatility: 0)
            guard newValue != Self.rounded(assumption.impliedMedianReal) || assumption.isGivenByMedian else { return }
            assumption.medianReal = newValue
            setReturnAssumption(assumption, for: assetClass)
        }
    }

    /// An asset class's volatility, the plan's or the default. Setting it
    /// keeps whichever of the mean and the median is given.
    subscript(planVolatility assetClass: AssetClass) -> Decimal {
        get { returnAssumption(for: assetClass)?.volatility ?? 0 }
        set {
            var assumption = returnAssumption(for: assetClass) ?? ReturnAssumption(real: 0, volatility: 0)
            assumption.volatility = newValue
            setReturnAssumption(assumption, for: assetClass)
        }
    }

    /// A return to show and edit, to a hundredth of a percent: a mean
    /// derived from a median (or the other way round) has many decimals.
    static func rounded(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 4, .plain)
        return result
    }
}

extension PlanPortfolio {
    /// Whether the plan counts `account` (it isn't in `exclude`).
    subscript(planIncludes account: AccountID) -> Bool {
        get { !exclude.contains(account) }
        set {
            exclude.removeAll { $0 == account }
            if !newValue { exclude.append(account) }
        }
    }

    // MARK: Target mix (PlanTargetMixModel)

    /// Whether the plan chooses its target mix ("A mix I choose") rather
    /// than keeping each account's mix today. Choosing starts from
    /// `suggestion`; keeping today's mix removes the mix and its changes
    /// with age, so nothing is written.
    subscript(planChoosesMix suggestion: AssetMix) -> Bool {
        get { choosesTargetMix }
        set {
            guard newValue != choosesTargetMix else { return }
            if newValue {
                targetMix = suggestion
            } else {
                targetMix = nil
                targetMixByAge = []
            }
        }
    }

    /// A class's share of the target mix (0.8 is 80%); `nil`, an empty
    /// field, when it has none. Clearing it, or 0, leaves the class out.
    subscript(planTargetShare assetClass: AssetClass) -> Decimal? {
        get { targetMix?.shares[assetClass] }
        set {
            var mix = targetMix ?? AssetMix()
            mix.shares[assetClass] = newValue == 0 ? nil : newValue
            targetMix = mix
        }
    }

    /// A class's share of change `index`'s mix; `nil` when it has none.
    subscript(planStepShare index: Int, assetClass: AssetClass) -> Decimal? {
        get { targetMixByAge.indices.contains(index) ? targetMixByAge[index].mix.shares[assetClass] : nil }
        set {
            guard targetMixByAge.indices.contains(index) else { return }
            targetMixByAge[index].mix.shares[assetClass] = newValue == 0 ? nil : newValue
        }
    }

    /// Change `index`'s age; `fallback` for one that starts at retirement.
    subscript(planStepAge index: Int, fallback fallback: Int) -> Int {
        get { targetMixByAge.indices.contains(index) ? targetMixByAge[index].fromAge.age ?? fallback : fallback }
        set {
            guard targetMixByAge.indices.contains(index) else { return }
            targetMixByAge[index].fromAge = .age(newValue)
        }
    }

    /// Whether change `index` starts at retirement; turned off, it starts at `fallbackAge`.
    subscript(planStepAtRetirement index: Int, fallbackAge fallbackAge: Int) -> Bool {
        get { targetMixByAge.indices.contains(index) && targetMixByAge[index].fromAge == .retirement }
        set {
            guard targetMixByAge.indices.contains(index) else { return }
            targetMixByAge[index].fromAge = newValue ? .retirement : .age(fallbackAge)
        }
    }
}

extension PlanSimulation {
    var planRuns: Int {
        get { effectiveRuns }
        set { runs = newValue }
    }

    var planConfidence: Decimal {
        get { effectiveConfidence }
        set { confidence = newValue }
    }

    var planSeed: Decimal {
        get { Decimal(effectiveSeed) }
        set { if let value = UInt64(newValue.fileString) { seed = value } }
    }
}

extension PlanContribution {
    /// Contributions stop at retirement (the default), or on a date.
    var planUntilRetirement: Bool {
        get { effectiveUntil == .retirement }
        set { until = newValue ? nil : .date(until?.date ?? CalendarDate.today().adding(years: 10)) }
    }

    var planUntilDate: CalendarDate {
        get { until?.date ?? CalendarDate.today().adding(years: 10) }
        set { until = .date(newValue) }
    }

    /// Paid once (`amount` in `year`) rather than every year (`perYear`
    /// until `until`). Switching carries the amount over.
    var planIsOneOff: Bool {
        get { isOneOff }
        set {
            guard newValue != isOneOff else { return }
            if newValue {
                amount = perYear > 0 ? perYear : 10_000
                year = year ?? CalendarDate.today().year + 1
                perYear = 0
                until = nil
            } else {
                perYear = amount.map { $0 > 0 ? $0 : 1_000 } ?? 1_000
                amount = nil
                year = nil
            }
        }
    }

    /// A one-off amount.
    var planAmount: Decimal {
        get { amount ?? 0 }
        set { amount = newValue }
    }

    /// The year of a one-off amount.
    var planYear: Int {
        get { year ?? CalendarDate.today().year + 1 }
        set { year = newValue }
    }
}

extension WorkPhase {
    /// The display name, "" for none.
    var planName: String {
        get { name ?? "" }
        set { name = newValue.isEmpty ? nil : newValue }
    }

    /// The phase lasts until retirement, or to a date.
    var planUntilRetirement: Bool {
        get { until == .retirement }
        set { until = newValue ? .retirement : .date(until.date ?? from.adding(years: 3).adding(days: -1)) }
    }

    var planUntilDate: CalendarDate {
        get { until.date ?? from.adding(years: 3).adding(days: -1) }
        set { until = .date(newValue) }
    }
}

extension PlanPension {
    /// The display name, "" for none.
    var planName: String {
        get { name ?? "" }
        set { name = newValue.isEmpty ? nil : newValue }
    }

    /// The age it starts at (67 until set).
    var planFromAge: Int {
        get { fromAge ?? 67 }
        set { fromAge = newValue }
    }
}

extension PlanIncome {
    /// The display name, "" for none.
    var planName: String {
        get { name ?? "" }
        set { name = newValue.isEmpty ? nil : newValue }
    }

    /// It starts when work stops, or at an age.
    var planFromRetirement: Bool {
        get { from == .retirement }
        set { from = newValue ? .retirement : .age(from?.age ?? 60) }
    }

    /// The age it starts at (60 until set).
    var planFromAge: Int {
        get { from?.age ?? 60 }
        set { from = .age(newValue) }
    }

    /// It stops at an age, or runs to the plan's end.
    var planHasEnd: Bool {
        get { untilAge != nil }
        set { untilAge = newValue ? planUntilAge : nil }
    }

    /// The age it stops at (five years after its start until set).
    var planUntilAge: Int {
        get { untilAge ?? (from?.age ?? 60) + 5 }
        set { untilAge = newValue }
    }
}

extension PlanAssumptions {
    /// An asset class's income yield (the part of its return paid as
    /// income each year), `nil` for none.
    subscript(planIncomeYield assetClass: AssetClass) -> Decimal? {
        get { returnAssumption(for: assetClass)?.incomeYield }
        set {
            var assumption = returnAssumption(for: assetClass) ?? ReturnAssumption(real: 0, volatility: 0)
            assumption.incomeYield = newValue
            setReturnAssumption(assumption, for: assetClass)
        }
    }
}

/// What a one-off event is, for the editor: money in (a windfall or an
/// inheritance), or an expense.
enum PlanEventType: String, CaseIterable, Hashable, Sendable {
    case windfall
    case expense

    var title: String {
        switch self {
        case .windfall: "Money in"
        case .expense: "Expense"
        }
    }
}

extension PlanEvent {
    /// Money in or an expense: sets the amount's sign. An expense is certain.
    var planType: PlanEventType {
        get { amount < 0 ? .expense : .windfall }
        set {
            let size = amount < 0 ? -amount : amount
            switch newValue {
            case .expense:
                amount = -size
                probability = nil
            case .windfall:
                amount = size
            }
        }
    }

    /// The amount without its sign.
    var planSize: Decimal {
        get { amount < 0 ? -amount : amount }
        set {
            let size = newValue < 0 ? -newValue : newValue
            amount = planType == .expense ? -size : size
        }
    }

    /// Whether the event is set by age (else by calendar year).
    var planByAge: Bool {
        get { if case .age = timing { true } else { false } }
        set {
            guard newValue != planByAge else { return }
            timing = newValue ? .age(60) : .year(CalendarDate.today().year + 5)
        }
    }

    /// The age or the year.
    var planWhen: Int {
        get {
            switch timing {
            case .age(let age): age
            case .year(let year): year
            }
        }
        set { timing = planByAge ? .age(newValue) : .year(newValue) }
    }

    /// The chance it happens, as a fraction; 1 (certain) is left out of the file.
    var planProbability: Decimal {
        get { effectiveProbability }
        set { probability = newValue >= 1 ? nil : max(0, newValue) }
    }
}
