import TaxKit

/// Germany as the paying country (TaxKit's G8): the tax Germany charges a
/// non-resident on German pensions that the plan says the paying country
/// taxes (`taxedIn: source`).
///
/// - **What it's given.** The planner calls it for each year the person
///   lives elsewhere with only those pensions: the ones whose
///   `sourceCountry` is `DE` (a `de.drv` pension's is, unless the plan says
///   otherwise). No work, no other pensions, no investment income: Germany
///   can't see what's taxed in the country of residence. Besides, the
///   citizenships, the residence timeline, the euro rate, the options of the
///   plan's latest `de` residence period (of which only `realWageGrowth` and
///   `indexFixedAllowances`, how amounts follow prices, are used) and the
///   running tax state.
/// - **Which pensions.** The treaty with the country of residence decides:
///   Italy (Art. 19(4)) leaves a social-security pension to Germany for a
///   German national who isn't also Italian, and private and occupational
///   pensions to Italy (Art. 18); Switzerland (Art. 18) leaves pensions to
///   Switzerland, except in the year of a German national's move there and
///   the 5 after (Art. 4 Abs. 4). Without a treaty in the parameters,
///   Germany taxes them (limited tax liability, §49 Abs. 1 Nr. 7). Where the
///   treaty gives a pension to the country of residence, Germany taxes
///   nothing on it and says so.
/// - **How.** As for a resident (the cohort's share and the fixed exempt
///   amount, kept in the tax state whichever country the person lives in;
///   the €102 lump sum), but without the basic allowance: the tariff applies
///   to the taxable income plus €12,348 (§50 Abs. 1 Satz 2), and no special
///   expenses. Taxed instead as a resident, on application, when at least
///   90% of the year's income is taxed in Germany or the rest is under the
///   basic allowance (§1 Abs. 3): with the allowance and the €36 lump sum,
///   the rest raising the rate (§32b Abs. 1 Nr. 5). The rest Germany sees is
///   only the German pensions the treaty leaves to the country of residence,
///   so with nothing else it applies §1 Abs. 3, and warns that more income
///   abroad would undo it. Soli; no church tax. Each line's `subject` is its
///   pension, so the planner's `taxByPension` gives each its own tax. Health
///   contributions abroad aren't modelled.
enum GermanNonResident {
    /// The residence options that say how amounts follow prices, not where
    /// or how the person lives: the only ones used abroad.
    static let modellingOptions: Set<String> = ["realWageGrowth", "indexFixedAllowances"]

    static func prepare(system: GermanTaxSystem, year: FixedYear, state: TaxState, parameters: ParameterSet)
        -> (any PreparedTaxYear)? {
        let unscaled: GermanParameters
        do {
            unscaled = try system.parsed.parameters(for: parameters)
        } catch {
            let issue = TaxIssue.error("de.parameters", "The German tax parameters for \(parameters.year) can't be "
                                       + "used: \(error)", year: year.year)
            return GermanNonResidentYear(fixedAssessment: TaxAssessment(issues: [issue], nextState: state))
        }
        let residence = residenceCountry(of: year)
        var issues: [TaxIssue] = []
        var german: [FixedYear.Pension] = []
        var exempt: Set<String> = []
        for pension in year.pensions where pension.amount > 0 {
            let (kind, country, _) = GermanYearCalculator.classify(pension)
            // The planner passes only pensions paid from Germany.
            guard country == "DE" else { continue }
            switch germanyTaxes(kind: kind, residence: residence, year: year, p: unscaled) {
            case .germany(let note):
                if let issue = note(pension.id) { issues.append(issue) }
            case .residence(let country):
                exempt.insert(pension.id)
                issues.append(.warning(
                    "de.nonResident.residenceTaxes",
                    "Under the treaty with \(country), \(country) taxes \(pension.id), not Germany: set its taxedIn to "
                        + "residence."))
            }
            german.append(pension)
        }
        guard !german.isEmpty else { return nil }

        // The German pensions alone, each computed as for a resident, so the
        // exempt amount is fixed (and kept in the state) also for one the
        // treaty leaves to the country of residence.
        var only = year
        only.systemOptions = OptionValues(year.systemOptions.values.filter { modellingOptions.contains($0.key) })
        only.overlays = []
        only.work = []
        only.windfalls = []
        only.wrapperContributions = []
        only.pensions = german
        let options = only.systemOptions.withDefaults(from: system.options)
        let scales = IndexingScales(year: only, parameterYear: parameters.year,
                                    realWageGrowth: options.double("realWageGrowth", default: 0.01),
                                    indexFixedAllowances: options.bool("indexFixedAllowances", default: false))
        var calculator = GermanYearCalculator(system: system, year: only, state: state,
                                              parameters: unscaled.scaled(by: scales), options: options)
        calculator.treatyExempt = exempt
        calculator.computePensions()
        let p = calculator.p
        let rate = calculator.rate

        // §1 Abs. 3 on what Germany sees: the income it taxes, and the German
        // pensions the treaty leaves to the country of residence, as German
        // law counts them. Other income abroad isn't passed, so it counts none.
        let germanIncome = calculator.pensionIncome
        let otherIncome = calculator.pensionProgression
        let asResident = germanIncome >= p.residentTreatmentShare * (germanIncome + otherIncome)
            || otherIncome <= p.tariff.basicAllowance
        var inputs = TariffInputs()
        inputs.income = germanIncome
        inputs.positiveIncome = germanIncome
        if asResident {
            inputs.progression = otherIncome
        } else {
            inputs.addedToTaxable = p.tariff.basicAllowance
        }
        let tax = IncomeTaxCalculator(tariff: p.tariff, soli: p.soli, churchRate: 0,
                                      specialExpensesLumpSum: asResident ? p.specialExpensesLumpSum : 0,
                                      oneFifthDivisor: p.oneFifthDivisor).compute(inputs)
        if asResident && tax.incomeTax > 1e-9 {
            issues.append(.warning(
                "de.nonResident.taxedAsResident",
                "Germany taxes your German pensions with the basic allowance, as a resident's (§1 Abs. 3 EStG). That "
                    + "needs an application, and at least \(percent(p.residentTreatmentShare)) of your income taxed in "
                    + "Germany or the rest under the allowance. The plan tells Germany only about the pensions it "
                    + "taxes, so it counts no other income: with more income abroad, Germany taxes them without the "
                    + "allowance, which costs more."))
        }

        // Each pension's share of the tax, by its taxable part.
        let parts = calculator.pensions.filter(\.taxedHere)
        let total = parts.reduce(0) { $0 + $1.taxable }
        var lines: [TaxLine] = []
        for part in parts where total > 0 {
            let share = part.taxable / total
            if tax.incomeTax * share > 1e-9 {
                lines.append(TaxLine(id: GermanLine.nonResidentIncomeTax, label: "Income tax (non-resident)",
                                     amount: tax.incomeTax * share / rate, base: tax.taxableIncome * share / rate,
                                     subject: part.id))
            }
            if tax.soli * share > 1e-9 {
                lines.append(TaxLine(id: GermanLine.nonResidentSoli, label: "Solidarity surcharge",
                                     amount: tax.soli * share / rate, base: tax.incomeTax * share / rate,
                                     subject: part.id))
            }
        }
        return GermanNonResidentYear(fixedAssessment: TaxAssessment(
            lines: lines, issues: issues + calculator.issues, nextState: calculator.nextState))
    }

    /// The country the person lives in during `year`, from the residence
    /// timeline: a system's ID is its country's code in lower case (`it`,
    /// `ch`); `nil` for a system of no one country, such as `generic`.
    static func residenceCountry(of year: FixedYear) -> String? {
        guard let system = year.residenceSystem(in: year.year), system.count == 2,
              system.allSatisfy(\.isLetter) else { return nil }
        return system.uppercased()
    }

    enum Decision {
        /// Germany taxes it, with a note to show.
        case germany((String) -> TaxIssue?)
        /// The treaty gives it to the country of residence.
        case residence(String)
    }

    /// Who taxes a German pension of `kind` paid to a resident of `residence`.
    static func germanyTaxes(kind: PensionKind, residence: String?, year: FixedYear, p: GermanParameters) -> Decision {
        guard let residence, let nationals = p.payingStateTaxesItsNationals[residence] else {
            return .germany { _ in nil }
        }
        if residence == "CH", let move = movedToSwitzerland(year, p: p) {
            return .germany { id in
                .warning("de.treaty.CH.extendedTaxation",
                         "A German national who moved to Switzerland in \(move) stays taxable in Germany on \(id) "
                             + "until \(move + p.moveToSwitzerlandYears) (Art. 4 Abs. 4); the Swiss tax isn't credited "
                             + "here.")
            }
        }
        guard kind == .statutory, nationals else { return .residence(residence) }
        guard !year.citizenships.isEmpty else {
            return .germany { id in
                .warning("de.treaty.citizenshipUnknown",
                         "Whether Germany or \(residence) taxes \(id) depends on your citizenship; without citizenships "
                             + "in the library, Germany taxes it as the plan says.")
            }
        }
        return year.isCitizen(of: "DE") && !year.isCitizen(of: residence) ? .germany { _ in nil } : .residence(residence)
    }

    /// The year a German national (not Swiss) moved from Germany to
    /// Switzerland after at least 5 years there, when `year` is within the
    /// years Germany keeps taxing.
    static func movedToSwitzerland(_ year: FixedYear, p: GermanParameters) -> Int? {
        guard year.isCitizen(of: "DE"), !year.isCitizen(of: "CH"),
              let entry = year.residence.last(where: { $0.from <= year.year }), entry.system == "ch",
              let before = year.residence.last(where: { $0.from < entry.from }), before.system == "de" else {
            return nil
        }
        let move = entry.from
        let german = (move - 50..<move).filter { year.residenceSystem(in: $0) == "de" }.count
        return german >= p.moveToSwitzerlandPriorYears && year.year <= move + p.moveToSwitzerlandYears ? move : nil
    }
}

/// A year of tax Germany charges a non-resident: fixed, nothing from the markets.
struct GermanNonResidentYear: PreparedTaxYear {
    let fixedAssessment: TaxAssessment

    func assess(_ variable: VariableYear) -> TaxAssessment {
        fixedAssessment
    }

    func grossUp(net: Double, from bucket: BucketSnapshot) -> Double? {
        nil
    }
}

extension GermanTaxSystem {
    /// `DE`: the paying country of `de.drv` pensions and of pensions with
    /// `sourceCountry` `DE`, which the planner gives this system to tax
    /// while the person lives elsewhere (``prepareNonResident(_:state:parameters:)``).
    public var country: String? { "DE" }

    /// What Germany charges a non-resident on the German pensions in `year`
    /// that the plan says the paying country taxes: see ``GermanNonResident``.
    /// `nil` when there are none. Each line names its pension in `subject`;
    /// amounts are in the plan's currency. The state carries each pension's
    /// fixed exempt amount, so it's the same as while living in Germany.
    public func prepareNonResident(_ year: FixedYear, state: TaxState, parameters: ParameterSet)
        -> (any PreparedTaxYear)? {
        GermanNonResident.prepare(system: self, year: year, state: state, parameters: parameters)
    }
}
