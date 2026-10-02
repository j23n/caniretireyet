import TaxKit

extension SwissTaxSystem {
    /// `CH`: Swiss pensions the plan says Switzerland taxes while the person
    /// lives elsewhere (`taxedIn: source`) are this system's, through
    /// ``prepareNonResident(_:state:parameters:)``; and a Swiss pension of
    /// someone living in Switzerland is an ordinary resident's pension.
    public var country: String? { TaxSwitzerland.country }

    /// The source tax Switzerland charges someone living abroad on Swiss
    /// pensions (docs/tax/CH.md, "Pensions paid abroad"): on BVG, 3a and
    /// vested-benefits annuities the federal 1% and the canton's rate, on
    /// lump sums the federal and the canton's tax on capital benefits; none
    /// on AHV pensions. The canton is that of the plan's residence period in
    /// Switzerland (`year.systemOptions`); without one, only the federal tax.
    ///
    /// Under a treaty that gives such pensions to the country of residence
    /// (Italy, Germany: art. 18), annuities are paid without source tax and
    /// the tax on lump sums is refunded, so none of it is final: the year has
    /// no lines, and a warning says the pension's `taxedIn` should be
    /// `residence`. Elsewhere the tax is counted as final, with a warning
    /// that a treaty may give the pension to the country of residence.
    public func prepareNonResident(_ year: FixedYear, state: TaxState, parameters: ParameterSet)
        -> (any PreparedTaxYear)? {
        SwissNonResidentYear.prepare(system: self, year: year, state: state, parameters: parameters)
    }
}

/// A Swiss non-resident year: everything is known in advance, so every
/// path's assessment is the fixed one.
struct SwissNonResidentYear: PreparedTaxYear {
    let fixedAssessment: TaxAssessment

    func assess(_ variable: VariableYear) -> TaxAssessment {
        fixedAssessment
    }

    func grossUp(net: Double, from bucket: BucketSnapshot) -> Double? {
        nil
    }

    static func prepare(system: SwissTaxSystem, year: FixedYear, state: TaxState, parameters: ParameterSet)
        -> SwissNonResidentYear {
        let p: SwissParameters
        do {
            p = try system.parsed.parameters(for: parameters).scaled(for: year)
        } catch {
            let issue = TaxIssue.error("ch.parameters", "The Swiss tax parameters for \(parameters.year) can't be used: "
                                       + "\(error)", year: year.year)
            return SwissNonResidentYear(fixedAssessment: TaxAssessment(issues: [issue], nextState: state))
        }
        var calculator = SwissNonResidentCalculator(system: system, year: year, p: p)
        let lines = calculator.lines()
        return SwissNonResidentYear(fixedAssessment: TaxAssessment(lines: lines, issues: calculator.issues,
                                                                   nextState: state))
    }
}

/// The source tax on one year's Swiss pensions paid abroad, in CHF inside.
struct SwissNonResidentCalculator {
    let system: SwissTaxSystem
    let year: FixedYear
    let p: SwissParameters
    var issues: [TaxIssue] = []

    init(system: SwissTaxSystem, year: FixedYear, p: SwissParameters) {
        self.system = system
        self.year = year
        self.p = p
    }

    /// A warning once per plan (no year), as treaty notes are.
    private mutating func warn(_ code: String, _ message: String) {
        let issue = TaxIssue.warning(code, message)
        if !issues.contains(issue) { issues.append(issue) }
    }

    /// Whether a pension is a state (AHV/IV) pension, which isn't taxed at source.
    static func isStatutory(_ pension: FixedYear.Pension) -> Bool {
        pension.kind == .statutory || (pension.kind == nil && pension.scheme == AHVPensionScheme.schemeID)
    }

    /// The treaty with the country of residence in the year, when the module knows it.
    private var residenceTreaty: SwissParameters.Treaty? {
        guard let residence = year.residenceSystem(in: year.year) else { return nil }
        return p.treaties.values.first { $0.system == residence }
    }

    /// The year's source-tax lines, in the plan's currency, each with its pension as subject.
    mutating func lines() -> [TaxLine] {
        let treaty = residenceTreaty
        let options = year.systemOptions.withDefaults(from: system.options)
        let place = try? SwissPlace.resolve(options, parameters: p).get()
        let cantonalLabel = place.map { "Source tax (cantonal and communal, \($0.canton.name))" }
        var lines: [TaxLine] = []
        func add(_ id: String, _ label: String, _ amount: Double, base: Double, subject: String) {
            guard amount > 1e-9 else { return }
            lines.append(TaxLine(id: id, label: label, amount: year.inPlanCurrency(amount),
                                 base: year.inPlanCurrency(base), subject: subject))
        }

        var lumpSums: [SwissCapitalBenefit] = []
        var taxed = false
        for pension in year.pensions where pension.amount > 0 {
            if Self.isStatutory(pension) {
                warn("ch.nonResident.ahv",
                     "Switzerland doesn't tax the AHV pension \(pension.id) of someone living abroad (there's no source "
                         + "tax on it): the country of residence does, so its taxedIn should be residence.")
                continue
            }
            if let treaty {
                warn("ch.nonResident.treaty",
                     "\(pension.id) is a Swiss pension of someone living in \(treaty.name), which \(treaty.name) taxes "
                         + "(\(treaty.name)–Switzerland treaty art. 18): Switzerland pays an annuity without source tax "
                         + "and refunds the source tax on a lump sum, so none is counted. Its taxedIn should be residence.")
                continue
            }
            if pension.kind == nil {
                warn("ch.nonResident.kind",
                     "\(pension.id) has no kind: Switzerland's source tax is charged as on an occupational pension. An AHV "
                         + "pension (kind statutory) isn't taxed at source.")
            }
            taxed = true
            let amount = year.inSystemCurrency(pension.amount)
            if pension.form == .lumpSum {
                lumpSums.append(SwissCapitalBenefit(subject: pension.id, amount: amount))
                continue
            }
            add(SwissLine.nonResidentFederal, "Source tax (federal)", amount * p.nonResidentFederalAnnuityRate,
                base: amount, subject: pension.id)
            if let place, let cantonalLabel, let rate = place.canton.nonResidentAnnuityRate {
                add(SwissLine.nonResidentCantonal, cantonalLabel, amount * rate, base: amount, subject: pension.id)
            }
        }

        // Lump sums: the tax on capital benefits, on all of the year's together, split in proportion.
        let total = lumpSums.reduce(0) { $0 + $1.amount }
        if total > 0 {
            let federal = p.federal.capitalBenefitTax(on: total)
            var cantonal = 0.0
            if let place {
                let canton = place.canton
                cantonal = canton.capitalBenefitSimpleTax(on: total, schedule: canton.incomeSchedule(in: year.year),
                                                          year: year.year, conversionFactor: place.conversionFactor)
                    * (canton.cantonMultiplier + place.communeMultiplier)
            }
            for lumpSum in lumpSums {
                let share = lumpSum.amount / total
                add(SwissLine.nonResidentFederal, "Source tax (federal)", federal * share, base: lumpSum.amount,
                    subject: lumpSum.subject)
                if let cantonalLabel {
                    add(SwissLine.nonResidentCantonal, cantonalLabel, cantonal * share, base: lumpSum.amount,
                        subject: lumpSum.subject)
                }
            }
        }

        if taxed {
            warn("ch.nonResident.noTreaty",
                 "Switzerland's source tax on pensions paid abroad is counted as final: the module doesn't know a treaty "
                     + "with the country of residence. Under most treaties that country taxes Swiss occupational and 3a "
                     + "pensions, and Switzerland refunds the tax; then their taxedIn should be residence.")
            if place == nil {
                warn("ch.nonResident.canton",
                     "The cantonal source tax on Swiss pensions paid abroad depends on the canton of the paying "
                         + "institution, which the module takes from the plan's residence in Switzerland: the plan has "
                         + "none with a supported canton, so only the federal source tax is counted.")
            }
        }
        return lines
    }
}
