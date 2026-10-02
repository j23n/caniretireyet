import TaxKit

extension ItalyTaxSystem {
    /// `IT`: pensions from Italy taxed at source (an INPS pension of someone
    /// living abroad) are this system's, through ``prepareNonResident(_:state:parameters:)``.
    public var country: String? { "IT" }

    /// IRPEF on Italian pensions paid to someone living abroad, when the plan
    /// says Italy taxes them (`taxedIn: source`): the brackets on their total,
    /// less the pension detrazione on that income alone (non-residents keep
    /// the art. 13 detrazioni, TUIR art. 24 c. 3), and the addizionali of
    /// Lazio and Rome, where INPS has its seat, when IRPEF is due. See
    /// docs/tax/IT.md, "Pensions paid abroad".
    ///
    /// It checks the plan against the treaties with Germany and Switzerland
    /// (by `FixedYear.residence` and the citizenships) and warns when they
    /// give the other country the right; it still taxes what the plan says.
    public func prepareNonResident(_ year: FixedYear, state: TaxState, parameters: ParameterSet)
        -> (any PreparedTaxYear)? {
        ItalyNonResidentYear.prepare(system: self, year: year, state: state, parameters: parameters)
    }
}

/// An Italian non-resident year: everything is known in advance, so every
/// path's assessment is the fixed one.
struct ItalyNonResidentYear: PreparedTaxYear {
    let fixedAssessment: TaxAssessment

    func assess(_ variable: VariableYear) -> TaxAssessment {
        fixedAssessment
    }

    func grossUp(net: Double, from bucket: BucketSnapshot) -> Double? {
        nil
    }

    static func prepare(system: ItalyTaxSystem, year: FixedYear, state: TaxState, parameters: ParameterSet)
        -> ItalyNonResidentYear {
        let p: ItalyParameters
        do {
            p = try system.parsed.parameters(for: parameters)
                .scaled(by: ThresholdIndexing.scale(for: year, parameterYear: parameters.year))
        } catch {
            let issue = TaxIssue.error("it.parameters", "The Italian tax parameters for \(parameters.year) can't be "
                                       + "used: \(error)", year: year.year)
            return ItalyNonResidentYear(fixedAssessment: TaxAssessment(issues: [issue], nextState: state))
        }
        let rate = year.euroRate
        let euros = year.inEuros()
        let pensions = euros.pensions.filter { $0.amount > 0 }
        let income = pensions.reduce(0) { $0 + $1.amount }
        let gross = p.irpef.tax(on: income)
        let detrazione = income > 0 ? p.pensionDetrazione.value(at: income) : 0
        let net = max(0, gross - detrazione)
        let due = net > 0 || !p.addizionaliOnlyWhenIrpefIsDue
        let regional = due ? p.nonResident.regionalSurcharge.tax(on: income) : 0
        let municipal = due ? p.nonResident.municipalRate * income : 0

        var lines: [TaxLine] = []
        for pension in pensions {
            let share = pension.amount / income
            for (id, label, amount) in [
                ("it.nonResident.irpef", "IRPEF (non-resident)", net),
                ("it.nonResident.addizionaleRegionale", "Addizionale regionale (Lazio)", regional),
                ("it.nonResident.addizionaleComunale", "Addizionale comunale (Rome)", municipal),
            ] where amount * share > 1e-9 {
                lines.append(TaxLine(id: id, label: label, amount: amount * share, base: pension.amount,
                                     subject: pension.id).fromEuros(rate))
            }
        }
        return ItalyNonResidentYear(fixedAssessment: TaxAssessment(
            lines: lines, issues: treatyIssues(year, pensions: pensions), nextState: state))
    }

    /// Warnings where a treaty gives the country of residence the pension:
    /// Germany, for a statutory pension unless the person is an Italian
    /// citizen who isn't German (art. 19(4)), and for other pensions (art.
    /// 18); Switzerland, for pensions from private-sector work (art. 18).
    static func treatyIssues(_ year: FixedYear, pensions: [FixedYear.Pension]) -> [TaxIssue] {
        var issues: [TaxIssue] = []
        func warn(_ message: String) {
            let issue = TaxIssue.warning("it.nonResident.treaty", message)
            if !issues.contains(issue) { issues.append(issue) }
        }
        switch year.residenceSystem(in: year.year) {
        case "de":
            for pension in pensions {
                let statutory = pension.kind == nil || pension.kind == .statutory
                if !statutory {
                    warn("\(pension.id) is an Italian occupational or private pension of someone living in Germany, "
                         + "which Germany taxes (Italy–Germany treaty art. 18): its taxedIn should be residence. "
                         + "Italy taxes it, as the plan says.")
                } else if year.citizenships.isEmpty {
                    warn("Who taxes the Italian state pension \(pension.id) of someone living in Germany depends on "
                         + "citizenship (Italy–Germany treaty art. 19(4)), which the library doesn't record. Italy "
                         + "taxes it, as the plan says.")
                } else if !(year.isCitizen(of: "IT") && !year.isCitizen(of: "DE")) {
                    warn("\(pension.id) is an Italian state pension of someone living in Germany who isn't only an "
                         + "Italian citizen, which Germany taxes (Italy–Germany treaty art. 19(4)): its taxedIn "
                         + "should be residence. Italy taxes it, as the plan says.")
                }
            }
        case "ch":
            if !pensions.isEmpty {
                warn("Switzerland taxes Italian pensions from private-sector work paid to its residents (Italy–"
                     + "Switzerland treaty art. 18); Italy keeps only public-service pensions of Italian citizens "
                     + "(art. 19). Italy taxes them, as the plan says.")
            }
        default:
            break
        }
        return issues
    }
}
