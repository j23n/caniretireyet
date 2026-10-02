import Foundation
import TaxKit

/// The Swiss tax system (`ch`), as described in docs/tax/CH.md: the federal
/// direct tax, the cantonal and communal income and wealth taxes of the
/// cantons in the parameter file (Zurich and Ticino), church and personal
/// tax; the regimes `ch.employee` and `ch.selfEmployed` and AHV
/// contributions without work; the overlays `ch.expatriate` and
/// `ch.lumpSum`; the `ch.ahv` and `ch.bvg` pensions; the wrappers
/// `ch.ordinary`, `ch.pillar3a`, `ch.vestedBenefits` and `ch.bvg`; and the
/// separate tax on capital benefits.
///
/// It computes in Swiss francs (`currency` is `CHF`): amounts arrive in the
/// plan's currency and are converted with `FixedYear.currencyRate`, and the
/// lines, accruals and claim options it returns are converted back. Every
/// rate and threshold comes from the bundled parameter files
/// (`Resources/ch/<year>.json`). Register it with the others:
///
///     let registry = TaxRegistry([ItalyTaxSystem(), SwissTaxSystem(), GenericTaxSystem()])
public struct SwissTaxSystem: TaxSystem {
    public let id = TaxSwitzerland.systemID
    public let name = "Switzerland"
    public let parameters: any ParameterStore
    public let options: [OptionField]
    public let regimes: [RegimeDescriptor]
    public let wrappers: [WrapperRule]
    public let pensionSchemes: [any PensionScheme]
    /// Parameter sets already parsed.
    let parsed = SwissParameterCache()

    public var currency: String? { TaxSwitzerland.currency }

    /// The Swiss system with its bundled parameter files. If they can't be
    /// read (which the tests rule out), `parameters` throws and `validate`
    /// reports it.
    public init() {
        self.init(parameters: Self.bundledParameters)
    }

    /// The Swiss system with other parameters, e.g. a newer file or test
    /// values. How many years pillar 3a and vested-benefits payouts are
    /// spread over is the plan's choice (the residence options
    /// `pillar3aPayoutYears` and `vestedBenefitsPayoutYears`,
    /// ``preferredPayoutYears(for:options:)``).
    public init(parameters: any ParameterStore) {
        self.parameters = parameters
        let latest = parameters.years.last.flatMap { try? parameters.parameters(for: $0) }
            .flatMap { try? SwissParameters($0) }
        options = Self.systemOptions(parameters: latest)
        regimes = Self.regimeDescriptors(parameters: latest)
        wrappers = Self.wrapperRules(parameters: latest)
        pensionSchemes = [AHVPensionScheme(), BVGPensionScheme(defaults: latest?.bvgDefaults), FixedPensionScheme()]
    }

    /// The bundled parameter files, loaded once.
    public static var bundledParameters: any ParameterStore {
        switch bundled {
        case .success(let store): store
        case .failure: UnavailableParameters()
        }
    }

    private static let bundled: Result<JSONParameterStore, any Error> = Result {
        try TaxSwitzerland.bundledParameters()
    }

    /// `ch.employee` for employees, `ch.selfEmployed` for the self-employed.
    public func defaultRegime(for kind: EarnedIncomeKind) -> String? {
        switch kind {
        case .employee: SwissRegime.employee
        case .selfEmployed: SwissRegime.selfEmployed
        default: nil
        }
    }

    /// Unknown IDs, options, the canton and commune, the tariff, the permit,
    /// and the overlays' conditions. Checks that need the amounts (3a limits,
    /// buy-ins) run in `prepare`; `validate(_:years:parameters:)` collects them.
    public func validate(_ plan: TaxPlan, parameters: any ParameterStore) -> [TaxIssue] {
        SwissValidator(system: self, plan: plan, parameters: parameters).issues()
    }

    /// The years pillar 3a and vested-benefits accounts pay out over, from
    /// the year they open: the residence options `pillar3aPayoutYears`
    /// (default: the years from first access to the reference age, 5) and
    /// `vestedBenefitsPayoutYears` (default: the accounts one may hold, 2),
    /// standing for that many accounts closed one a year; 1 pays everything
    /// in the first year, 0 draws only what's needed until it must be paid
    /// out (`nil`). Other wrappers as their rules say.
    public func preferredPayoutYears(for wrapper: String, options: OptionValues) -> Int? {
        let key: String
        switch wrapper {
        case SwissWrapper.pillar3a: key = SwissOption.pillar3aPayoutYears
        case SwissWrapper.vestedBenefits: key = SwissOption.vestedBenefitsPayoutYears
        default: return self.wrapper(wrapper)?.preferredPayoutYears
        }
        let years = options.withDefaults(from: self.options).int(key) ?? self.wrapper(wrapper)?.preferredPayoutYears ?? 0
        return years > 0 ? years : nil
    }

    /// Stages 1–7 and 10 of the year (docs/tax/CH.md); the prepared year
    /// assesses investment income, wealth, AHV without work and wrapper
    /// payouts per path.
    public func prepare(_ year: FixedYear, state: TaxState, parameters: ParameterSet) -> any PreparedTaxYear {
        SwissYearCalculator.prepare(system: self, year: year, state: state, parameters: parameters)
    }
}

/// The parameter sets a system has parsed, most recent last. A planner
/// passes the same set for many years, so the lookup is usually quick.
final class SwissParameterCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(set: ParameterSet, parameters: SwissParameters)] = []
    private static let capacity = 16

    func parameters(for set: ParameterSet) throws -> SwissParameters {
        lock.lock()
        if let hit = entries.last(where: { $0.set.year == set.year && $0.set == set }) {
            lock.unlock()
            return hit.parameters
        }
        lock.unlock()
        let parsed = try SwissParameters(set)
        lock.lock()
        entries.append((set, parsed))
        if entries.count > Self.capacity { entries.removeFirst() }
        lock.unlock()
        return parsed
    }
}

/// Stands in for the bundled parameters if they can't be read.
struct UnavailableParameters: ParameterStore {
    let system = TaxSwitzerland.systemID
    var years: [Int] { [] }

    func parameters(for year: Int) throws -> ParameterSet {
        throw ParameterError.noParameters(system: system)
    }
}

/// An amount in francs for messages, e.g. "CHF 7,258".
func francs(_ amount: Double) -> String {
    let rounded = Int(amount.rounded())
    let digits = String(abs(rounded))
    var grouped = ""
    for (index, digit) in digits.enumerated() {
        if index > 0 && (digits.count - index) % 3 == 0 { grouped.append(",") }
        grouped.append(digit)
    }
    return (rounded < 0 ? "CHF -" : "CHF ") + grouped
}

/// A rate for labels, e.g. "95%" or "12.5%".
func percent(_ rate: Double) -> String {
    let value = (rate * 1000).rounded() / 10
    return value == value.rounded() ? "\(Int(value))%" : "\(value)%"
}
