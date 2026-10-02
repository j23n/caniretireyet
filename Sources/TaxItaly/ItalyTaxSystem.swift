import Foundation
import TaxKit

/// The Italian tax system (`it`), as described in docs/tax/IT.md: IRPEF with
/// the employment, pension and self-employment detrazioni and the cuneo
/// relief; the regimes `it.employee`, `it.professional` and `it.forfettario`;
/// the overlays `it.impatriati-2024` and `it.impatriati-2015`; INPS
/// contributions and the `it.inps` pension; the wrappers `it.ordinary`,
/// `it.pensionFund` and `it.tfr`; taxes on investments and wealth; and
/// inheritance tax.
///
/// Every rate and threshold comes from the bundled parameter files
/// (`Resources/it/<year>.json`). Register it with the others:
///
///     let registry = TaxRegistry([ItalyTaxSystem(), GenericTaxSystem()])
///
/// Inheritances: a windfall of kind `inheritance` is taxed as one from a
/// parent (the file's default relationship); `inheritance.spouse`,
/// `inheritance.lineal`, `inheritance.sibling`, `inheritance.relative` and
/// `inheritance.other` choose the relationship.
public struct ItalyTaxSystem: TaxSystem {
    public let id = "it"
    public let name = "Italy"
    /// Italy computes in euros: a plan in another currency is converted at
    /// the planner's rate on the way in, and every line, accrual and claim
    /// option back on the way out (rate 1 for a plan in euros).
    public let currency: String? = "EUR"
    public let parameters: any ParameterStore
    public let options: [OptionField]
    public let regimes: [RegimeDescriptor]
    public let wrappers: [WrapperRule]
    /// Parameter sets already parsed: a plan prepares thousands of years
    /// from a few sets.
    let parsed = ItalyParameterCache()

    /// The Italian system with its bundled parameter files. If they can't be
    /// read (which the tests rule out), `parameters` throws and `validate`
    /// reports it.
    public init() {
        self.init(parameters: Self.bundledParameters)
    }

    /// The Italian system with other parameters, e.g. a newer file or test values.
    public init(parameters: any ParameterStore) {
        self.parameters = parameters
        let latest = parameters.years.last.flatMap { try? parameters.parameters(for: $0) }
            .flatMap { try? ItalyParameters($0) }
        options = Self.systemOptions()
        regimes = Self.regimeDescriptors(parameters: latest)
        wrappers = Self.wrapperRules(parameters: latest)
    }

    /// The bundled parameter files, loaded once.
    public static var bundledParameters: any ParameterStore {
        switch bundled {
        case .success(let store): store
        case .failure: UnavailableParameters()
        }
    }

    private static let bundled: Result<JSONParameterStore, any Error> = Result {
        guard let root = Bundle.module.resourceURL else { throw ParameterError.noParameters(system: "it") }
        var files: [Int: Data] = [:]
        // `.process` flattens Resources/it into the bundle's root; `.copy` would keep the folder.
        for directory in [root, root.appendingPathComponent("it")] {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { continue }
            for name in names where name.hasSuffix(".json") {
                let stem = name.dropLast(".json".count)
                if stem.count == 4, let year = Int(stem) {
                    files[year] = try Data(contentsOf: directory.appendingPathComponent(name))
                }
            }
        }
        return try JSONParameterStore(system: "it", files: files)
    }

    /// `it.inps` and the shared `fixed` scheme.
    public var pensionSchemes: [any PensionScheme] {
        [INPSPensionScheme(), FixedPensionScheme()]
    }

    /// `it.employee` for employees, `it.professional` for the self-employed.
    public func defaultRegime(for kind: EarnedIncomeKind) -> String? {
        switch kind {
        case .employee: ItalyRegime.employee
        case .selfEmployed: ItalyRegime.professional
        default: nil
        }
    }

    /// Unknown IDs, regime scope and years, options, impatriati's years and
    /// exclusions, and forfettario's start-up period. Forfettario's revenue
    /// limits need the amounts: see `validate(_:years:parameters:)`.
    public func validate(_ plan: TaxPlan, parameters: any ParameterStore) -> [TaxIssue] {
        ItalyValidator(system: self, plan: plan, parameters: parameters).issues()
    }

    /// Stages 1–7 and 10 of the year (see docs/tax/IT.md); the prepared year
    /// assesses gains, payouts and wealth per path, and grosses up exactly.
    public func prepare(_ year: FixedYear, state: TaxState, parameters: ParameterSet) -> any PreparedTaxYear {
        ItalyYearCalculator.prepare(system: self, year: year, state: state, parameters: parameters)
    }
}

/// The parameter sets a system has parsed, most recent last. A planner
/// passes the same set for many years, so the lookup is usually an identity
/// check; other sets are compared in full.
final class ItalyParameterCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(set: ParameterSet, parameters: ItalyParameters)] = []
    private static let capacity = 16

    func parameters(for set: ParameterSet) throws -> ItalyParameters {
        lock.lock()
        if let hit = entries.last(where: { $0.set.year == set.year && $0.set == set }) {
            lock.unlock()
            return hit.parameters
        }
        lock.unlock()
        let parsed = try ItalyParameters(set)
        lock.lock()
        entries.append((set, parsed))
        if entries.count > Self.capacity { entries.removeFirst() }
        lock.unlock()
        return parsed
    }
}

/// Stands in for the bundled parameters if they can't be read.
struct UnavailableParameters: ParameterStore {
    let system = "it"
    var years: [Int] { [] }

    func parameters(for year: Int) throws -> ParameterSet {
        throw ParameterError.noParameters(system: system)
    }
}
