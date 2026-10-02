import TaxKit

/// Germany as the paying country (TaxKit gap G8): the tax Germany charges a
/// non-resident on German pensions that the plan says the paying country
/// taxes (`taxedIn: source`).
///
/// - **Which pensions.** Those whose paying country is Germany (`de.drv`, or
///   a `sourceCountry` of `DE`). The treaty with the country of residence
///   decides: Italy (Art. 19(4)) leaves a social-security pension to
///   Germany for a German national who isn't also Italian, and private and
///   occupational pensions to Italy (Art. 18); Switzerland (Art. 18) leaves
///   pensions to Switzerland, except in the year of a German national's
///   move there and the 5 after (Art. 4 Abs. 4). Without a treaty in the
///   parameters, Germany taxes them (limited tax liability, §49 Abs. 1 Nr. 7).
///   Where the treaty gives a pension to the country of residence, Germany
///   taxes nothing and says so.
/// - **How.** As for a resident (the cohort's share and the fixed exempt
///   amount, the €102 lump sum), but without the basic allowance: the
///   tariff applies to the taxable income plus €12,348 (§50 Abs. 1 Satz 2),
///   and no special expenses. With at least 90% of the year's income German,
///   or the rest under the basic allowance, the person is taxed as a
///   resident (§1 Abs. 3). Soli; no church tax. Health contributions abroad
///   aren't modelled.
enum GermanNonResident {
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
        let residence = year.residenceSystem(in: year.year).map { $0.uppercased() }
        var issues: [TaxIssue] = []
        var taxed: [FixedYear.Pension] = []
        for pension in year.pensions where pension.amount > 0 {
            let (kind, country, _) = GermanYearCalculator.classify(pension)
            guard country == "DE" else { continue }
            switch germanyTaxes(kind: kind, residence: residence, year: year, p: unscaled) {
            case .germany(let note):
                if let issue = note(pension.id) { issues.append(issue) }
                var mine = pension
                mine.taxedIn = .residence
                taxed.append(mine)
            case .residence(let country):
                issues.append(.warning(
                    "de.nonResident.residenceTaxes",
                    "Under the treaty with \(country), \(country) taxes \(pension.id), not Germany: set its taxedIn to "
                        + "residence.", year: year.year))
            }
        }
        guard !taxed.isEmpty else {
            return issues.isEmpty ? nil : GermanNonResidentYear(fixedAssessment: TaxAssessment(issues: issues,
                                                                                               nextState: state))
        }

        var german = year
        german.systemOptions = [:]
        german.work = []
        german.windfalls = []
        german.wrapperContributions = []
        german.pensions = taxed
        let options = OptionValues().withDefaults(from: system.options)
        let scales = IndexingScales(year: german, parameterYear: parameters.year, realWageGrowth: 0.01,
                                    indexFixedAllowances: false)
        var calculator = GermanYearCalculator(system: system, year: german, state: state,
                                              parameters: unscaled.scaled(by: scales), options: options)
        calculator.computePensions()
        let p = calculator.p
        let rate = calculator.rate

        // §1 Abs. 3: taxed as a resident when the year's income is at least
        // 90% German, or the rest is under the basic allowance.
        let germanIncome = taxed.reduce(0) { $0 + $1.amount } * rate
        let world = (year.pensions.reduce(0) { $0 + max(0, $1.amount) }
            + year.work.reduce(0) { $0 + max(0, $1.gross - $1.costs) }) * rate
        let asResident = germanIncome >= 0.9 * world || world - germanIncome <= p.tariff.basicAllowance
        var inputs = TariffInputs()
        inputs.income = calculator.pensionIncome
        inputs.positiveIncome = calculator.pensionIncome
        inputs.addedToTaxable = asResident ? 0 : p.tariff.basicAllowance
        let tax = IncomeTaxCalculator(tariff: p.tariff, soli: p.soli, churchRate: 0, specialExpensesLumpSum: 0,
                                      oneFifthDivisor: p.oneFifthDivisor).compute(inputs)

        // Each pension's share of the tax, by its taxable part.
        let parts = calculator.pensions.filter(\.taxedHere)
        let total = parts.reduce(0) { $0 + $1.taxable }
        var lines: [TaxLine] = []
        for part in parts where total > 0 {
            let share = part.taxable / total
            let label = asResident ? "German income tax" : "German income tax (non-resident)"
            if tax.incomeTax * share > 1e-9 {
                lines.append(TaxLine(id: GermanLine.incomeTax, label: label, amount: tax.incomeTax * share / rate,
                                     base: tax.taxableIncome * share / rate, subject: part.id))
            }
            if tax.soli * share > 1e-9 {
                lines.append(TaxLine(id: GermanLine.soli, label: "German solidarity surcharge",
                                     amount: tax.soli * share / rate, subject: part.id))
            }
        }
        return GermanNonResidentYear(fixedAssessment: TaxAssessment(
            lines: lines, issues: issues + calculator.issues, nextState: calculator.nextState))
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
                             + "here.", year: year.year)
            }
        }
        guard kind == .statutory, nationals else { return .residence(residence) }
        guard !year.citizenships.isEmpty else {
            return .germany { id in
                .warning("de.treaty.citizenshipUnknown",
                         "Whether Germany or \(residence) taxes \(id) depends on your citizenship; without citizenships "
                             + "in the library, Germany taxes it as the plan says.", year: year.year)
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
    /// Germany: the paying country of `de.drv` pensions and of pensions with
    /// `sourceCountry` `DE`, for systems that tax a pension in its paying
    /// country (TaxKit gap G8).
    public var country: String? { "DE" }

    /// What Germany charges a non-resident on the German pensions in `year`
    /// that the plan says the paying country taxes: see ``GermanNonResident``.
    /// `nil` when there are none. Lines name the pension in `subject`;
    /// amounts are in the plan's currency.
    public func prepareNonResident(_ year: FixedYear, state: TaxState, parameters: ParameterSet)
        -> (any PreparedTaxYear)? {
        GermanNonResident.prepare(system: self, year: year, state: state, parameters: parameters)
    }
}
