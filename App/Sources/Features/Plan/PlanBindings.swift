import Foundation
import Model
import TaxKit

// Get/set views of plan values for the editors' controls, so the views
// bind by key path (`$plan.spending.phases[planSafe: 0, default: …].factor`,
// `$pension.planClaimsEarliest`) rather than with `Binding(get:set:)`
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

extension PlanTax {
    /// Whether thresholds rise with inflation (default on).
    var planIndexThresholds: Bool {
        get { effectiveIndexThresholds }
        set { indexThresholds = newValue }
    }
}

extension PlanAssumptions {
    /// An asset class's expected real return, the plan's or the default.
    subscript(planReal assetClass: AssetClass) -> Decimal {
        get { returnAssumption(for: assetClass)?.real ?? 0 }
        set {
            var assumption = returnAssumption(for: assetClass) ?? ReturnAssumption(real: 0, volatility: 0)
            assumption.real = newValue
            returns[assetClass] = assumption
        }
    }

    /// An asset class's volatility, the plan's or the default.
    subscript(planVolatility assetClass: AssetClass) -> Decimal {
        get { returnAssumption(for: assetClass)?.volatility ?? 0 }
        set {
            var assumption = returnAssumption(for: assetClass) ?? ReturnAssumption(real: 0, volatility: 0)
            assumption.volatility = newValue
            returns[assetClass] = assumption
        }
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
}

extension WorkPhase {
    /// The kind of work; changing it clears a regime that no longer fits
    /// and fills in the amount the new kind needs.
    var planKind: WorkKind {
        get { kind }
        set { self = PlanEditing.changing(self, to: newValue, registry: AppTaxRegistry.standard) }
    }

    /// The regime's ID, "" for the system's default; changing it keeps only
    /// the options the new regime knows.
    var planRegime: String {
        get { regime?.rawValue ?? "" }
        set { self = PlanEditing.choosing(newValue.isEmpty ? nil : newValue, for: self, registry: AppTaxRegistry.standard) }
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
    /// The scheme's ID; changing it keeps the name and claim and the
    /// options the new scheme knows.
    var planScheme: String {
        get { scheme.rawValue }
        set { self = PlanEditing.changing(self, toScheme: newValue, registry: AppTaxRegistry.standard) }
    }

    /// The display name, "" for the scheme's.
    var planName: String {
        get { name ?? "" }
        set { name = newValue.isEmpty ? nil : newValue }
    }

    /// Claimed as early as the scheme allows (the default), or at an age.
    var planClaimsEarliest: Bool {
        get { effectiveClaim == .earliest }
        set { claim = newValue ? .earliest : .age(claim?.age ?? 67) }
    }

    var planClaimAge: Int {
        get { claim?.age ?? 67 }
        set { claim = .age(newValue) }
    }

    /// A fixed pension's start age.
    var planFromAge: Int {
        get { fromAge ?? 67 }
        set { fromAge = newValue }
    }

    /// Who taxes it; the default (residence) is left out of the file.
    var planTaxedIn: TaxedIn {
        get { effectiveTaxedIn }
        set { taxedIn = newValue == .residence ? nil : newValue }
    }
}

/// What a one-off event is, for the editor: money in, an inheritance, or an expense.
enum PlanEventType: String, CaseIterable, Hashable, Sendable {
    case windfall
    case inheritance
    case expense

    var title: String {
        switch self {
        case .windfall: "Windfall"
        case .inheritance: "Inheritance"
        case .expense: "Expense"
        }
    }
}

extension PlanEvent {
    /// Windfall, inheritance or expense: sets the amount's sign and the kind.
    var planType: PlanEventType {
        get {
            if amount < 0 { return .expense }
            return kind == .inheritance ? .inheritance : .windfall
        }
        set {
            let size = amount < 0 ? -amount : amount
            switch newValue {
            case .expense:
                amount = -size
                kind = nil
                probability = nil
            case .windfall:
                amount = size
                kind = nil
            case .inheritance:
                amount = size
                kind = .inheritance
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

extension PlanResidence {
    /// The tax system's ID; changing it keeps only the options it knows.
    var planSystem: String {
        get { system.rawValue }
        set {
            system = TaxSystemID(newValue)
            options = PlanOptionForm.carryOver(options, to: PlanTaxChoices.systemFields(system,
                                                                                        registry: AppTaxRegistry.standard))
        }
    }
}

extension PlanOverlay {
    /// The regime's ID; changing it keeps only the options it knows.
    var planRegime: String {
        get { regime.rawValue }
        set {
            regime = RegimeID(newValue)
            options = PlanOptionForm.carryOver(options, to: PlanTaxChoices.regimeFields(newValue,
                                                                                         registry: AppTaxRegistry.standard))
        }
    }
}

extension Dictionary where Key == String, Value == JSONValue {
    /// A switch option: the plan's value, else the field's default.
    subscript(planBool field: OptionField) -> Bool {
        get { PlanOptionForm.bool(field, in: self) }
        set { self = PlanOptionForm.setting(field.key, to: .bool(newValue), in: self) }
    }

    /// A choice option: the plan's value, else the default, else "".
    subscript(planChoice field: OptionField) -> String {
        get { PlanOptionForm.choice(field, in: self) ?? "" }
        set { self = PlanOptionForm.setting(field.key, to: newValue.isEmpty ? nil : .string(newValue), in: self) }
    }
}
