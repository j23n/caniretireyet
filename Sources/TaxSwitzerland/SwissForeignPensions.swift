import TaxKit

/// A pension Switzerland taxes although the plan says the paying country
/// does (`taxedIn: source`), because the treaty gives it to Switzerland:
/// the tax that country charged on it (`FixedYear.Pension.sourceTax`) is
/// credited, up to the Swiss tax on it. Amounts in CHF.
struct SwissForeignCredit: Hashable, Sendable {
    /// The pension's ID.
    var subject: String
    /// The pension's amount in the year.
    var amount: Double
    /// The tax the paying country charged on it.
    var paid: Double
    /// Whether it's a lump sum (a capital benefit) rather than an annuity.
    var isLumpSum: Bool
}

/// Where a pension paid to a Swiss resident comes from, for the treaties.
enum SwissForeignPension {
    /// The paying country, in capitals: the pension's `sourceCountry`, else
    /// its scheme's prefix when that's a country code (`it.inps` is
    /// Italian, `ch.bvg` Swiss); `nil` when unknown (a `fixed` pension
    /// without one).
    static func country(of pension: FixedYear.Pension) -> String? {
        if let country = pension.sourceCountry, !country.isEmpty { return country.uppercased() }
        let parts = pension.scheme.split(separator: ".", maxSplits: 1)
        guard parts.count == 2, parts[0].count == 2, parts[0].allSatisfy(\.isLetter) else { return nil }
        return parts[0].uppercased()
    }
}

extension SwissYearCalculator {
    /// Whether Switzerland taxes `pension` (docs/tax/CH.md, "Moving between
    /// countries"). A pension with `taxedIn: residence` is taxed. One with
    /// `taxedIn: source` is taxed when the treaty with the paying country
    /// gives it to Switzerland (art. 18), with a warning, and its source
    /// tax is credited; it's left to the paying country, counting only for
    /// the rate, when it may be a public-service pension of a citizen of
    /// that country (art. 19), or when the module doesn't know the treaty.
    /// A Swiss pension is Switzerland's.
    mutating func taxesInSwitzerland(_ pension: FixedYear.Pension) -> Bool {
        guard pension.taxedIn == .source else { return true }
        guard let country = SwissForeignPension.country(of: pension) else { return false }
        if country == TaxSwitzerland.country { return true }
        guard let treaty = p.treaties[country] else { return false }
        let treatyName = "\(treaty.name)–Switzerland treaty"
        if treaty.mayBePublicService(pension.kind) {
            if year.isCitizen(of: country) { return false }
            if year.citizenships.isEmpty {
                treatyWarning("ch.treaty.citizenship",
                              "Who taxes the pension \(pension.id) from \(treaty.name) depends on whether it's from public "
                                  + "service and on citizenship (\(treatyName) art. 18–19), which the library doesn't "
                                  + "record: Switzerland taxes it, and any tax \(treaty.name) charged on it is credited.")
                return true
            }
        }
        let publicService = treaty.mayBePublicService(pension.kind)
            ? "; art. 19 keeps public-service pensions in \(treaty.name) only for its citizens" : ""
        treatyWarning("ch.treaty.taxedIn",
                      "\(pension.id) is a pension from \(treaty.name), which Switzerland taxes while its recipient lives "
                          + "there (\(treatyName) art. 18\(publicService)): it's taxed in Switzerland although its taxedIn "
                          + "is source, and any tax \(treaty.name) charged on it is credited.")
        return true
    }

    /// A treaty warning, once per plan (no year).
    private mutating func treatyWarning(_ code: String, _ message: String) {
        let issue = TaxIssue.warning(code, message)
        if !issues.contains(issue) { issues.append(issue) }
    }
}

extension SwissLineBuilder {
    /// Credits for the tax the paying countries charged on pensions
    /// Switzerland taxes against the plan's `taxedIn` (``SwissForeignCredit``),
    /// each up to the Swiss tax on its pension: for a lump sum, its
    /// capital-benefit lines; for an annuity, its share by `income` (the
    /// year's income before deductions) of the income taxes. Call it after
    /// the income and capital-benefit lines.
    mutating func addForeignTaxCredits(_ credits: [SwissForeignCredit], income: Double) {
        guard !credits.isEmpty else { return }
        let incomeIDs: Set = [SwissLine.federal, SwissLine.cantonal, SwissLine.communal, SwissLine.church]
        let capitalIDs: Set = [SwissLine.capitalBenefitsFederal, SwissLine.capitalBenefitsCantonal,
                               SwissLine.capitalBenefitsCommunal, SwissLine.capitalBenefitsChurch]
        let incomeTax = lines.filter { incomeIDs.contains($0.id) }.reduce(0) { $0 + $1.amount }
        var credited: [TaxLine] = []
        for credit in credits where credit.paid > 0 {
            let swissTax = credit.isLumpSum
                ? lines.filter { $0.subject == credit.subject && capitalIDs.contains($0.id) }.reduce(0) { $0 + $1.amount }
                : (income > 0 ? incomeTax * min(1, credit.amount / income) : 0)
            let amount = min(credit.paid, max(0, swissTax))
            guard amount > 1e-9 else { continue }
            credited.append(TaxLine(id: SwissLine.foreignTaxCredit, label: labels.foreignTaxCredit, amount: -amount,
                                    base: credit.paid, subject: credit.subject))
        }
        lines += credited
    }
}
