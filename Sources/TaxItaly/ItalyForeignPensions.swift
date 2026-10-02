import TaxKit

/// How Italy taxes one pension paid to a resident in a year, by where it
/// comes from (docs/tax/IT.md, "Pensions from abroad"):
///
/// - **Switzerland.** AHV and BVG benefits (statutory and occupational, or
///   of unknown kind; annuities and lump sums) pay the 5% substitute tax,
///   outside IRPEF. Pillar 3a (a private pension or annuity): annuities in
///   IRPEF, lump sums taxed separately. Italy taxes them all (treaty art.
///   18), whatever the plan's `taxedIn` says.
/// - **Germany.** A statutory (DRV) pension, or one of unknown kind, is
///   Germany's alone for a German citizen who isn't Italian (treaty art.
///   19(4)); otherwise Italy's, which taxes only the part Germany would
///   (protocol no. 14 e). Occupational and private pensions are Italy's
///   (art. 18), in IRPEF in full. Without citizenships, Italy taxes it and
///   warns.
/// - **Elsewhere, and Italy.** In IRPEF, unless the plan says the paying
///   country taxes it.
///
/// Where the treaty gives Italy the right, Italy taxes the pension even when
/// its `taxedIn` is `source`, and credits the tax the paying country
/// charged (`sourceTax`). Where it gives the other country the right and the
/// plan says `residence`, Italy follows the plan and warns. Italy has no
/// progression clause: what it exempts counts nowhere.
struct ItalyPensionTreatment: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// In IRPEF: `taxable` counts toward total income.
        case irpef
        /// The 5% substitute tax on Swiss AHV and BVG benefits.
        case swissFlatTax
        /// Taxed separately at the TFR's average rate (a pillar 3a lump sum).
        case separate
        /// Not taxed in Italy.
        case exempt
    }

    var pension: FixedYear.Pension
    var kind: Kind
    /// The amount taxed: all of the pension, or for a German statutory
    /// pension the part Germany would tax.
    var taxable: Double
    /// Whether Italy taxes it although the plan says the paying country
    /// does: the tax charged there is credited.
    var creditsSourceTax = false
}

extension ItalyPensionTreatment {
    /// The country a pension comes from, in capitals: its `sourceCountry`,
    /// else its scheme's prefix when that's a country code (`ch.bvg` is
    /// Swiss, `it.inps` Italian); `nil` when unknown (a `fixed` pension
    /// without one).
    static func country(of pension: FixedYear.Pension) -> String? {
        if let country = pension.sourceCountry, !country.isEmpty { return country.uppercased() }
        let parts = pension.scheme.split(separator: ".", maxSplits: 1)
        guard parts.count == 2, parts[0].count == 2, parts[0].allSatisfy(\.isLetter) else { return nil }
        return parts[0].uppercased()
    }
}

extension ItalyYearCalculator {
    /// Each pension's treatment, recording the German exemptions to fix and
    /// the treaty warnings.
    mutating func treatPensions() {
        pensionTreatments = year.pensions.map { treatment(of: $0) }
    }

    private mutating func treatment(of pension: FixedYear.Pension) -> ItalyPensionTreatment {
        let amount = max(0, pension.amount)
        let atSource = pension.taxedIn == .source
        let followPlan = ItalyPensionTreatment(pension: pension, kind: atSource ? .exempt : .irpef,
                                               taxable: atSource ? 0 : amount)
        switch ItalyPensionTreatment.country(of: pension) {
        case "CH":
            let kind: ItalyPensionTreatment.Kind
            switch pension.kind {
            case nil, .statutory?, .occupational?:
                kind = .swissFlatTax
            case .privateAnnuity?, .basicPension?:
                kind = pension.form == .lumpSum ? .separate : .irpef
            default:
                return followPlan
            }
            if atSource {
                treatyWarning("it.treaty.taxedIn", "\(pension.id) is a Swiss pension, which Italy taxes while its "
                              + "recipient lives there (Italy–Switzerland treaty art. 18): it's taxed in Italy "
                              + "although its taxedIn is source, and any Swiss tax on it is credited.")
            }
            return ItalyPensionTreatment(pension: pension, kind: kind, taxable: amount, creditsSourceTax: atSource)
        case "DE":
            let statutory = pension.kind == nil || pension.kind == .statutory
            var italys = true
            if statutory {
                if year.citizenships.isEmpty {
                    treatyWarning("it.treaty.citizenship", "Who taxes the German state pension \(pension.id) depends "
                                  + "on citizenship (Italy–Germany treaty art. 19(4)), which the library doesn't "
                                  + "record: Italy taxes it.")
                } else if year.isCitizen(of: "DE") && !year.isCitizen(of: "IT") {
                    italys = false
                }
            }
            if !italys {
                if atSource {
                    return ItalyPensionTreatment(pension: pension, kind: .exempt, taxable: 0)
                }
                treatyWarning("it.treaty.taxedIn", "\(pension.id) is the German state pension of a German citizen "
                              + "who isn't Italian, which only Germany taxes (Italy–Germany treaty art. 19(4)): its "
                              + "taxedIn should be source. Italy taxes it, as the plan says.")
            } else if atSource {
                let rule = statutory ? "art. 19(4), for an Italian citizen" : "art. 18"
                treatyWarning("it.treaty.taxedIn", "\(pension.id) is a German pension that Italy taxes "
                              + "(Italy–Germany treaty \(rule)): it's taxed in Italy although its taxedIn is "
                              + "source, and any German tax on it is credited.")
            }
            let taxable = statutory ? germanTaxablePart(of: pension) : amount
            return ItalyPensionTreatment(pension: pension, kind: .irpef, taxable: taxable,
                                         creditsSourceTax: atSource && italys)
        default:
            return followPlan
        }
    }

    /// The part of a German statutory pension Germany would tax, which is
    /// all Italy taxes (protocol no. 14 e): in the year it starts, the
    /// share for that year; from the next, the pension less a fixed amount
    /// in nominal euros, (1 − share) × the first full year's pension, kept
    /// in the state (in today's euros it shrinks with inflation). A pension
    /// first seen later, e.g. one already paid when the plan starts, fixes
    /// the amount on that year's pension.
    private mutating func germanTaxablePart(of pension: FixedYear.Pension) -> Double {
        let amount = max(0, pension.amount)
        let start = pension.startYear ?? year.year
        let share = p.foreignPensions.germanStatutoryShare(startYear: start)
        guard pension.form == .annuity else { return share * amount }
        let key = ItalyStateKey.germanExemption(pension.id)
        let prices = year.inflationFactor > 0 ? year.inflationFactor : 1
        if let nominal = germanExemptions[key] ?? state[key] {
            return max(0, amount - nominal / prices)
        }
        guard start < year.year else { return share * amount }
        let exempt = (1 - share) * amount
        germanExemptions[key] = exempt * prices
        return amount - exempt
    }

    /// A treaty warning, once per plan (no year).
    private mutating func treatyWarning(_ code: String, _ message: String) {
        let issue = TaxIssue.warning(code, message)
        if !issues.contains(issue) { issues.append(issue) }
    }

    /// The rate of separate taxation (TFR, pillar 3a lump sums): the average
    /// IRPEF rate of the plan's employee years, or the file's fallback.
    var separateTaxationRate: Double {
        let income = state[ItalyStateKey.tfrTaxableIncome] ?? 0
        return income > 0 ? (state[ItalyStateKey.tfrIrpef] ?? 0) / income : p.tfr.payoutFallbackRate
    }

    /// The lines of pensions taxed outside IRPEF (the Swiss 5%, separate
    /// taxation), and the credits for tax paid abroad, in euros.
    func foreignPensionLines() -> [TaxLine] {
        var lines: [TaxLine] = []
        let flatRate = p.foreignPensions.swissFlatRate
        let separateRate = separateTaxationRate
        for treatment in pensionTreatments {
            let id = treatment.pension.id
            var italianTax = 0.0
            switch treatment.kind {
            case .swissFlatTax:
                italianTax = flatRate * treatment.taxable
                lines.append(TaxLine(id: "it.swissPensionTax", label: ItalyMarketLabels.swissPensionLabel(rate: flatRate),
                                     amount: italianTax, base: treatment.taxable, subject: id))
            case .separate:
                italianTax = separateRate * treatment.taxable
                lines.append(TaxLine(id: "it.separateTaxation",
                                     label: ItalyMarketLabels.pillar3aLabel(rate: separateRate),
                                     amount: italianTax, base: treatment.taxable, subject: id))
            case .irpef:
                if irpef.totalIncome > 0 {
                    italianTax = irpef.netIrpef * treatment.taxable / irpef.totalIncome
                }
            case .exempt:
                break
            }
            if treatment.creditsSourceTax, let paid = treatment.pension.sourceTax, paid > 0, italianTax > 0 {
                lines.append(TaxLine(id: "it.foreignTaxCredit", label: "Credit for tax paid abroad",
                                     amount: -min(paid, italianTax), base: paid, subject: id))
            }
        }
        return lines.filter { abs($0.amount) > 1e-9 }
    }
}

extension ItalyStateKey {
    /// The fixed exempt amount of a German statutory pension, in nominal
    /// euros of the plan's first year's prices (protocol no. 14 e).
    static func germanExemption(_ pension: String) -> String {
        "it.de.exempt.\(pension)"
    }
}
