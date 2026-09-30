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
    public let parameters: any ParameterStore
    public let options: [OptionField]
    public let regimes: [RegimeDescriptor]
    public let wrappers: [WrapperRule]

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

    public var pensionSchemes: [any PensionScheme] {
        [INPSPensionScheme(), FixedPensionScheme()]
    }

    public func defaultRegime(for kind: EarnedIncomeKind) -> String? {
        switch kind {
        case .employee: ItalyRegime.employee
        case .selfEmployed: ItalyRegime.professional
        default: nil
        }
    }

    public func validate(_ plan: TaxPlan, parameters: any ParameterStore) -> [TaxIssue] {
        ItalyValidator(system: self, plan: plan, parameters: parameters).issues()
    }

    public func prepare(_ year: FixedYear, state: TaxState, parameters: ParameterSet) -> any PreparedTaxYear {
        ItalyYearCalculator.prepare(system: self, year: year, state: state, parameters: parameters)
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
