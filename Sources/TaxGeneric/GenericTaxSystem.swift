import Foundation
import TaxKit

/// The `generic` tax system: flat effective rates, chosen in the plan's
/// residence options, on work income, pensions, gains, interest and
/// dividends, and wealth, plus a social-contribution rate on work income.
///
/// Good for rough "what if I moved" plans, and used by the planner's own
/// tests so they don't break when a country's law changes. Register it with
/// the others:
///
///     let registry = TaxRegistry([ItalyTaxSystem(), GenericTaxSystem()])
///
/// - Work (`generic.employee`, `generic.selfEmployed`): contributions are
///   `socialContributionRate` × (gross − costs), and income tax is
///   `incomeTaxRate` × (gross − costs − contributions to `taxDeferred`).
/// - Pensions taxed in the residence country: `pensionTaxRate` × amount.
/// - Wrappers: `taxable` (gains, interest, dividends and wealth taxed),
///   `taxDeferred` (payouts taxed at `pensionTaxRate`), `taxFree` (nothing
///   taxed). Wrappers of other systems are treated as `taxable`, or as
///   `taxDeferred` for payouts, with a warning.
/// - Pensions: the shared `fixed` scheme.
/// - Gross-up is exact.
public struct GenericTaxSystem: TaxSystem {
    public let id = "generic"
    public let name = "Generic (flat rates)"
    public let parameters: any ParameterStore

    /// The generic system. It has no yearly parameters: every rate is a plan option.
    public init() {
        let file = #"{ "year": 2026, "note": "The generic system has no parameters: every rate is a residence option." }"#
        // A fixed, valid JSON object: this can't fail.
        parameters = (try? JSONParameterStore(system: "generic", files: [2026: Data(file.utf8)]))
            ?? EmptyParameterStore(system: "generic")
    }

    /// The flat rates, all residence options.
    public var options: [OptionField] {
        [
            .percent("incomeTaxRate", "Income tax rate", default: 0,
                     help: "Effective rate on work income, after costs."),
            .percent("pensionTaxRate", "Pension tax rate",
                     help: "Effective rate on pensions and tax-deferred payouts. Defaults to the income tax rate."),
            .percent("capitalGainsRate", "Capital gains tax rate", default: 0),
            .percent("interestDividendRate", "Interest and dividend tax rate",
                     help: "Defaults to the capital gains tax rate."),
            .percent("wealthTaxRate", "Wealth tax rate", default: 0, range: 0...0.1,
                     help: "Yearly, on the value of taxable accounts."),
            .percent("socialContributionRate", "Social contribution rate", default: 0,
                     help: "On work income, after costs."),
        ]
    }

    /// `generic.employee` and `generic.selfEmployed`.
    public var regimes: [RegimeDescriptor] {
        [
            RegimeDescriptor(id: "generic.employee", name: "Employee (flat rate)", scope: .earnedIncome([.employee]),
                             summary: "Gross salary taxed at the flat income tax rate."),
            RegimeDescriptor(id: "generic.selfEmployed", name: "Self-employed (flat rate)",
                             scope: .earnedIncome([.selfEmployed]),
                             summary: "Revenue minus costs taxed at the flat income tax rate."),
        ]
    }

    /// `taxable`, `taxDeferred` (from the public pension age, or 60) and `taxFree`.
    public var wrappers: [WrapperRule] {
        [
            WrapperRule(id: GenericWrapper.taxable, name: "Taxable", category: .taxable) { _ in .accessible(route: nil) },
            WrapperRule(id: GenericWrapper.taxDeferred, name: "Tax-deferred", category: .taxDeferred) { context in
                let age = context.oldAgePensionAge ?? GenericWrapper.defaultAccessAge
                return context.age >= age
                    ? .accessible(route: nil)
                    : .locked(reason: "A tax-deferred account can be drawn from age \(age).")
            },
            WrapperRule(id: GenericWrapper.taxFree, name: "Tax-free", category: .taxFree) { _ in
                .accessible(route: nil)
            },
        ]
    }

    /// The shared `fixed` scheme.
    public var pensionSchemes: [any PensionScheme] {
        [FixedPensionScheme()]
    }

    public func defaultRegime(for kind: EarnedIncomeKind) -> String? {
        switch kind {
        case .employee: "generic.employee"
        case .selfEmployed: "generic.selfEmployed"
        default: nil
        }
    }

    /// The shared checks, plus a warning when every rate of a residence period is 0.
    public func validate(_ plan: TaxPlan, parameters: any ParameterStore) -> [TaxIssue] {
        var issues = commonIssues(for: plan)
        for entry in plan.residence where entry.system == id {
            let rates = GenericRates(entry.options.withDefaults(from: options))
            if rates.allZero {
                issues.append(.warning("generic.noRates", "Every generic tax rate is 0 from \(entry.from).",
                                       year: entry.from))
            }
        }
        return issues
    }

    /// Taxes work and pensions at the year's flat rates; the state passes through unchanged.
    public func prepare(_ year: FixedYear, state: TaxState, parameters: ParameterSet) -> any PreparedTaxYear {
        GenericPreparedYear(year: year, state: state, rates: GenericRates(year.systemOptions.withDefaults(from: options)))
    }
}

/// The IDs of the generic wrappers.
public enum GenericWrapper {
    public static let taxable = "taxable"
    public static let taxDeferred = "taxDeferred"
    public static let taxFree = "taxFree"

    /// The age a `taxDeferred` account opens when the planner doesn't know
    /// the public pension age.
    public static let defaultAccessAge = 60
}

/// A residence period's rates, with the computed defaults filled in.
struct GenericRates: Hashable, Sendable {
    var income: Double
    var pension: Double
    var capitalGains: Double
    var interestDividend: Double
    var wealth: Double
    var social: Double

    init(_ options: OptionValues) {
        income = options.double("incomeTaxRate", default: 0)
        pension = options.double("pensionTaxRate") ?? income
        capitalGains = options.double("capitalGainsRate", default: 0)
        interestDividend = options.double("interestDividendRate") ?? capitalGains
        wealth = options.double("wealthTaxRate", default: 0)
        social = options.double("socialContributionRate", default: 0)
    }

    var allZero: Bool {
        [income, pension, capitalGains, interestDividend, wealth, social].allSatisfy { $0 == 0 }
    }
}

/// A store with no years, used only if the generic system's inline
/// parameters could not be read.
struct EmptyParameterStore: ParameterStore {
    let system: String
    var years: [Int] { [] }

    func parameters(for year: Int) throws -> ParameterSet {
        throw ParameterError.noParameters(system: system)
    }
}
