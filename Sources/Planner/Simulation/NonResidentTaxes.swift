import Foundation
import TaxKit

/// What the paying countries charge in one year on the pensions they tax
/// while the person lives elsewhere: pensions with `taxedIn` `.source`
/// whose `sourceCountry` has a registered system
/// (``TaxKit/TaxSystem/prepareNonResident(_:state:parameters:)``, G8).
///
/// In a year the paying country is the residence's, such a pension is the
/// residence system's to tax, so it gets `taxedIn` `.residence`.
struct NonResidentTaxes: Sendable {
    /// A pension whose paying country's system doesn't tax non-residents.
    struct Untaxed: Sendable {
        let pension: String
        let system: String
    }

    /// A key of the tax state the paying systems set, or removed (`nil`).
    struct StateChange: Sendable {
        let key: String
        let value: Double?
    }

    /// The year's pensions as the residence system sees them: each taxed in
    /// the paying country with its `sourceTax`, and those paid by the
    /// residence country with `taxedIn` `.residence`.
    private(set) var pensions: [FixedYear.Pension]
    /// The paying systems' tax lines, labelled with the system's name.
    private(set) var lines: [TaxLine] = []
    /// Their contributions, labelled likewise.
    private(set) var contributions: [TaxLine] = []
    /// Their issues.
    private(set) var issues: [TaxIssue] = []
    /// What they changed in the tax state, applied on top of the residence
    /// system's next state.
    private(set) var stateChanges: [StateChange] = []
    /// Pensions left untaxed because their paying country's system doesn't
    /// tax non-residents (or has no parameters for the year).
    private(set) var untaxed: [Untaxed] = []

    /// Whether the residence system's year needs anything added.
    var isEmpty: Bool {
        lines.isEmpty && contributions.isEmpty && stateChanges.isEmpty
    }

    /// The taxes and contributions the paying countries charge.
    var total: Double {
        lines.reduce(0) { $0 + $1.amount } + contributions.reduce(0) { $0 + $1.amount }
    }

    init(model: PlanModel, frame: YearFrame, pensions: [FixedYear.Pension], state: TaxState) {
        let residence = model.systems[frame.system].system
        let residenceCountry = residence.country?.uppercased()
        var pensions = pensions
        for index in pensions.indices where pensions[index].taxedIn == .source {
            if let country = pensions[index].sourceCountry, country == residenceCountry {
                pensions[index].taxedIn = .residence
            }
        }
        self.pensions = pensions
        for payer in model.nonResidentSystems where payer.system.id != residence.id {
            let indices = pensions.indices.filter {
                pensions[$0].taxedIn == .source && pensions[$0].sourceCountry == payer.country
            }
            guard !indices.isEmpty else { continue }
            let taxed = indices.map { pensions[$0] }
            let year = FixedYear(
                year: frame.year, age: frame.age,
                systemOptions: Self.options(of: payer.system.id, in: frame.year, residence: model.residence),
                pensions: taxed, inflationFactor: frame.inflationFactor, indexThresholds: model.indexThresholds,
                currencyRate: payer.currencyRate, citizenships: model.citizenships,
                birthDate: model.birthDate.birthDate, residence: model.residence)
            guard let parameters = try? payer.parameters.parameters(for: frame.year),
                  let prepared = payer.system.prepareNonResident(year, state: state, parameters: parameters) else {
                untaxed += taxed.map { Untaxed(pension: $0.id, system: payer.system.name) }
                continue
            }
            let assessment = prepared.fixedAssessment
            let name = payer.system.name
            lines += assessment.lines.map { Self.labelled($0, by: name) }
            contributions += assessment.contributions.map { Self.labelled($0, by: name) }
            issues += assessment.issues
            for key in assessment.nextState.values.keys.sorted() where assessment.nextState[key] != state[key] {
                stateChanges.append(StateChange(key: key, value: assessment.nextState[key]))
            }
            for key in state.values.keys.sorted() where assessment.nextState[key] == nil {
                stateChanges.append(StateChange(key: key, value: nil))
            }
            let byPension = assessment.taxByPension(taxed)
            for index in indices {
                pensions[index].sourceTax = byPension[pensions[index].id]
            }
        }
        self.pensions = pensions
    }

    /// `assessment` with these taxes and contributions added, and the state
    /// changes applied to its next state.
    func adding(to assessment: TaxAssessment) -> TaxAssessment {
        var assessment = assessment
        assessment.lines += lines
        assessment.contributions += contributions
        for change in stateChanges {
            assessment.nextState[change.key] = change.value
        }
        return assessment
    }

    /// The options of the plan's latest residence period in `system` at or
    /// before `year`, else of its first one after it, else none.
    static func options(of system: String, in year: Int, residence: [TaxPlan.Residence]) -> OptionValues {
        let periods = residence.filter { $0.system == system }
        return (periods.last { $0.from <= year } ?? periods.first)?.options ?? [:]
    }

    /// A line with the paying system's name in front of its label: "Italy: IRPEF".
    private static func labelled(_ line: TaxLine, by system: String) -> TaxLine {
        var line = line
        line.label = "\(system): \(line.label)"
        return line
    }
}

/// The residence system's prepared year with the paying countries' taxes
/// on top: in the fixed assessment and in every path's, so the year's cash,
/// its reported taxes and the market-dependent part all include them.
struct WithNonResidentTaxes: PreparedTaxYear {
    let base: any PreparedTaxYear
    let foreign: NonResidentTaxes
    let fixedAssessment: TaxAssessment

    init(base: any PreparedTaxYear, foreign: NonResidentTaxes) {
        self.base = base
        self.foreign = foreign
        fixedAssessment = foreign.adding(to: base.fixedAssessment)
    }

    func assess(_ variable: VariableYear) -> TaxAssessment {
        foreign.adding(to: base.assess(variable))
    }

    func grossUp(net: Double, from bucket: BucketSnapshot) -> Double? {
        base.grossUp(net: net, from: bucket)
    }
}
