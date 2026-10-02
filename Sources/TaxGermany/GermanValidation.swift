import TaxKit

/// Checks a plan against the German rules that don't need its amounts: the
/// shared checks, `childBirthYears` (a list, which no `OptionField` kind
/// describes), the PKV premium, pensions without a kind, and what the
/// residence timeline shows: the exit tax and the Swiss treaty's years after
/// a move. Checks that need amounts (PKV for an employee below the limit,
/// Riester eligibility, contribution limits, the KVdR test, treaties against
/// each pension's `taxedIn`) run year by year in `prepare`.
struct GermanValidator {
    let system: GermanTaxSystem
    let plan: TaxPlan
    let parameters: any ParameterStore

    func issues() -> [TaxIssue] {
        var issues = system.commonIssues(for: plan).filter {
            !($0.code == "\(system.id).options.unknownKey" && $0.option == "childBirthYears")
        }
        let periods = system.residencePeriods(in: plan)
        guard let first = periods.first?.lowerBound else { return issues }
        let p: GermanParameters
        do {
            p = try system.parsed.parameters(for: try parameters.parameters(for: first))
        } catch {
            issues.append(.error("de.parameters", "The German tax parameters can't be used: \(error)", year: first))
            return issues
        }
        for entry in plan.residence where entry.system == system.id {
            issues += optionIssues(entry)
        }
        issues += pensionIssues()
        issues += movingIssues(p)
        return issues
    }

    private func optionIssues(_ entry: TaxPlan.Residence) -> [TaxIssue] {
        var issues: [TaxIssue] = []
        if let value = entry.options["childBirthYears"] {
            let valid = value.listValue?.allSatisfy { year in
                year.intValue.map { (1900...2200).contains($0) } ?? false
            } ?? false
            if !valid {
                issues.append(.error("de.options.wrongType", "Children's birth years must be a list of years, e.g. "
                                     + "[2015, 2018].", year: entry.from, option: "childBirthYears"))
            }
        }
        let options = entry.options.withDefaults(from: system.options)
        let privateCover = options.string("healthInsurance") == "pkv"
            || options.string("retirementHealthInsurance") == "pkv"
        if privateCover && (options.double("pkvPremium") ?? 0) <= 0 {
            issues.append(.error("de.pkv.premiumMissing", "Private health insurance needs its monthly premium "
                                 + "(pkvPremium).", year: entry.from, option: "pkvPremium"))
        }
        if options.string("retirementHealthInsurance") == "kvdr" && options.string("healthInsurance") == "pkv" {
            issues.append(.warning("de.kvdr.afterPKV", "The pensioners' insurance (KVdR) needs 9/10 of the second "
                                   + "half of the working life in statutory insurance, which years in PKV don't count "
                                   + "toward.", year: entry.from, option: "retirementHealthInsurance"))
        }
        return issues
    }

    /// `fixed` pensions while resident in Germany need a kind to be taxed right.
    private func pensionIssues() -> [TaxIssue] {
        plan.pensions.compactMap { pension in
            guard pension.scheme == FixedPensionScheme.schemeID, pension.kind == nil else { return nil }
            return .warning("de.pension.kindUnknown", "The pension \(pension.id) doesn't say what kind it is (statutory, "
                            + "occupational, basicPension or privateAnnuity): Germany taxes it like a statutory pension.",
                            regime: pension.scheme)
        }
    }

    /// Leaving Germany: the exit tax on large fund and company holdings after
    /// 7 of the last 12 years of residence, and the Swiss treaty's 5 years of
    /// German taxation for a German national (not Swiss) moving to Switzerland.
    private func movingIssues(_ p: GermanParameters) -> [TaxIssue] {
        var issues: [TaxIssue] = []
        let entries = plan.residence.sorted { $0.from < $1.from }
        for (index, entry) in entries.enumerated() where index > 0 && entry.system != system.id {
            guard entries[index - 1].system == system.id else { continue }
            let move = entry.from
            let resident = (move - p.exitTaxLookbackYears..<move).filter { plan.residence(in: $0)?.system == system.id }
            if resident.count >= p.exitTaxResidenceYears {
                issues.append(.warning(
                    "de.exitTax", "Leaving Germany in \(move) after \(resident.count) of the last "
                        + "\(p.exitTaxLookbackYears) years there: holdings of at least 1% of a company or a fund, or of "
                        + "a fund that cost \(euros(p.exitTaxFundCost)) or more, are taxed as if sold (§6 AStG, §19 "
                        + "Abs. 3 InvStG). The plan doesn't compute this.", year: move))
            }
            let citizens = Set(plan.citizenships.map { $0.uppercased() })
            if entry.system == "ch", citizens.contains("DE"), !citizens.contains("CH"),
               resident.count >= p.moveToSwitzerlandPriorYears {
                issues.append(.warning(
                    "de.treaty.CH.extendedTaxation", "A German national moving to Switzerland stays taxable in Germany "
                        + "on German income (a DRV pension included) in \(move) and the \(p.moveToSwitzerlandYears) years "
                        + "after, with the Swiss tax credited (Art. 4 Abs. 4 of the treaty). The plan doesn't compute "
                        + "this.", year: move))
            }
        }
        return issues
    }
}

extension GermanTaxSystem {
    /// The points where German law makes a tax or contribution jump as income
    /// rises, from the parameters for `year` (in that file's nominal euros).
    /// The tariff, the Soli (with its taper), church tax, trade tax, the
    /// one-fifth rule and inheritance tax (with the hardship relief) are
    /// continuous; the tariff's quadratic and linear zones meet within 6
    /// cents at €69,878.
    public func cliffs(in year: Int) -> [LegalCliff] {
        guard let set = try? parameters.parameters(for: year), let p = try? GermanParameters(set) else { return [] }
        return [
            LegalCliff(id: "de.kvdr.occupationalCare", measure: GermanCliffMeasure.occupationalPensionMonthly,
                       at: p.kvdr.occupationalCareThresholdMonthly, direction: .taxRises,
                       note: "Care contributions on an occupational pension are due on all of it once it's above this "
                           + "a month."),
            LegalCliff(id: "de.pkv.compulsoryInsuranceLimit", measure: GermanCliffMeasure.salary,
                       at: p.health.compulsoryInsuranceLimit, direction: .taxFalls,
                       note: "With healthInsurance pkv, an employee earning more than this pays the PKV premium instead "
                           + "of statutory contributions."),
        ].sorted { ($0.at, $0.id) < ($1.at, $1.id) }
    }
}

/// What the German cliffs are measured on (`LegalCliff.measure`).
public enum GermanCliffMeasure {
    /// German occupational pensions per month.
    public static let occupationalPensionMonthly = "occupational pension per month"
    /// An employee's yearly salary.
    public static let salary = "salary"
}
