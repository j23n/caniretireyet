import Foundation
import TaxKit

/// The German tax system (`de`), as described in docs/tax/DE.md: income tax
/// on the §32a tariff with the Soli and church tax; social contributions for
/// employees, freelancers and traders, and health insurance in retirement
/// (KVdR, voluntary GKV or PKV); the regimes `de.employee`, `de.freelancer`
/// and `de.trader` (with trade tax); the `de.drv` statutory pension; the
/// taxation of pensions by cohort, kind and treaty; the wrappers
/// `de.ordinary`, `de.riester`, `de.ruerup`, `de.bav` and
/// `de.altersvorsorgedepot`; the flat tax on investment income with the
/// partial exemption, the Vorabpauschale and the Günstigerprüfung; and
/// inheritance and gift tax.
///
/// It computes in euros (`currency` is `EUR`): a plan in another currency is
/// converted with the year's `currencyRate`. Every rate and threshold comes
/// from the bundled parameter files (`Resources/de/<year>.json`). Register it
/// with the others:
///
///     let registry = TaxRegistry([ItalyTaxSystem(), GermanTaxSystem(), GenericTaxSystem()])
///
/// Inheritances and gifts: a windfall of kind `inheritance` or `gift` is
/// taxed as one from a parent (the file's default relationship);
/// `.spouse`, `.lineal`, `.grandparent`, `.parent`, `.sibling`, `.relative`
/// and `.other` choose the relationship. A windfall of kind `severance` is
/// taxed with the one-fifth rule.
public struct GermanTaxSystem: TaxSystem {
    public let id = TaxGermany.systemID
    public let name = "Germany"
    public let currency: String? = TaxGermany.currency
    public let parameters: any ParameterStore
    public let options: [OptionField]
    public let regimes: [RegimeDescriptor]
    public let wrappers: [WrapperRule]
    /// Parameter sets already parsed: a plan prepares thousands of years from a few sets.
    let parsed = GermanParameterCache()

    /// The German system with its bundled parameter files. If they can't be
    /// read (which the tests rule out), `parameters` throws and `validate`
    /// reports it.
    public init() {
        self.init(parameters: Self.bundledParameters)
    }

    /// The German system with other parameters, e.g. a newer file or test values.
    public init(parameters: any ParameterStore) {
        self.parameters = parameters
        let latest = parameters.years.last.flatMap { try? parameters.parameters(for: $0) }
            .flatMap { try? GermanParameters($0) }
        options = Self.systemOptions(parameters: latest)
        regimes = Self.regimeDescriptors(parameters: latest)
        wrappers = Self.wrapperRules(parameters: latest)
    }

    /// The bundled parameter files, loaded once.
    public static var bundledParameters: any ParameterStore {
        switch TaxGermany.bundled {
        case .success(let store): store
        case .failure: UnavailableGermanParameters()
        }
    }

    /// `de.drv` and the shared `fixed` scheme.
    public var pensionSchemes: [any PensionScheme] {
        [DRVPensionScheme(), FixedPensionScheme()]
    }

    /// `de.employee` for employees, `de.freelancer` for the self-employed.
    public func defaultRegime(for kind: EarnedIncomeKind) -> String? {
        switch kind {
        case .employee: GermanRegime.employee
        case .selfEmployed: GermanRegime.freelancer
        default: nil
        }
    }

    /// The shared checks, the options only Germany reads (`childBirthYears`,
    /// the PKV premium), pensions without a kind, and warnings from the
    /// residence timeline (exit tax, the Swiss treaty's years after a move).
    /// Checks that need the plan's amounts run in `prepare`; see
    /// `validate(_:years:parameters:)`.
    public func validate(_ plan: TaxPlan, parameters: any ParameterStore) -> [TaxIssue] {
        GermanValidator(system: self, plan: plan, parameters: parameters).issues()
    }

    /// Stages 1–7 and 11 of the year (see docs/tax/DE.md); the prepared year
    /// assesses investment income, payouts and health contributions on them
    /// per path.
    public func prepare(_ year: FixedYear, state: TaxState, parameters: ParameterSet) -> any PreparedTaxYear {
        GermanYearCalculator.prepare(system: self, year: year, state: state, parameters: parameters)
    }
}

/// The parameter sets a system has parsed, most recent last.
final class GermanParameterCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(set: ParameterSet, parameters: GermanParameters)] = []
    private static let capacity = 16

    func parameters(for set: ParameterSet) throws -> GermanParameters {
        lock.lock()
        if let hit = entries.last(where: { $0.set.year == set.year && $0.set == set }) {
            lock.unlock()
            return hit.parameters
        }
        lock.unlock()
        let parsed = try GermanParameters(set)
        lock.lock()
        entries.append((set, parsed))
        if entries.count > Self.capacity { entries.removeFirst() }
        lock.unlock()
        return parsed
    }
}

/// Stands in for the bundled parameters if they can't be read.
struct UnavailableGermanParameters: ParameterStore {
    let system = TaxGermany.systemID
    var years: [Int] { [] }

    func parameters(for year: Int) throws -> ParameterSet {
        throw ParameterError.noParameters(system: system)
    }
}

extension GermanTaxSystem {
    /// The wrapper rules, with the ages and payout plans of `parameters`
    /// (the latest year). Payout taxes are computed in `assess`.
    static func wrapperRules(parameters p: GermanParameters?) -> [WrapperRule] {
        /// Accessible for the whole year once `months` of age are reached by
        /// 1 January (with a birth date), else from the year of that birthday.
        @Sendable func from(_ months: Int, _ context: WrapperAccessContext) -> Bool {
            if let age = context.ageInMonthsAtStartOfYear { return age >= months }
            return context.age >= months / 12
        }
        @Sendable func access(_ months: Int, _ name: String, _ context: WrapperAccessContext) -> WrapperAccess {
            from(months, context) ? .accessible(route: nil)
                : .locked(reason: "\(name) pays out from \(months / 12)\(months % 12 > 0 ? " and \(months % 12) months" : "").")
        }
        let riester = (p?.riester.payoutFromAge ?? 62) * 12
        let ruerup = (p?.ruerupPayoutFromAge ?? 62) * 12
        let bav = (p?.bav.payoutFromAge ?? 62) * 12
        let depot = (p?.altersvorsorgedepot.payoutFromAge ?? 65) * 12
        let standard = p?.standardAge.last?.months ?? 67 * 12
        let years = p?.payoutYears ?? [:]
        return [
            WrapperRule(id: GermanWrapper.ordinary, name: "Ordinary account (Depot)", category: .taxable) { _ in
                .accessible(route: nil)
            },
            WrapperRule(id: GermanWrapper.riester, name: "Riester", category: .taxDeferred,
                        preferredPayoutYears: years["riester"]) { context in
                access(riester, "A Riester contract", context)
            },
            WrapperRule(id: GermanWrapper.ruerup, name: "Basisrente (Rürup)", category: .taxDeferred,
                        preferredPayoutYears: years["ruerup"]) { context in
                access(ruerup, "A Basisrente", context)
            },
            // A bAV pays from the contract's age, at least 62: the standard
            // retirement age, unless the planner's old-age pension age is earlier.
            WrapperRule(id: GermanWrapper.bav, name: "Occupational pension (bAV)", category: .taxDeferred,
                        preferredPayoutYears: years["bav"]) { context in
                let age = max(bav, context.oldAgePensionAgeInMonths ?? context.oldAgePensionAge.map { $0 * 12 } ?? standard)
                return access(age, "An occupational pension", context)
            },
            WrapperRule(id: GermanWrapper.altersvorsorgedepot, name: "Altersvorsorgedepot", category: .taxDeferred,
                        preferredPayoutYears: years["altersvorsorgedepot"]) { context in
                access(depot, "The Altersvorsorgedepot", context)
            },
        ]
    }
}
