import TaxKit

/// How Germany taxes a pension.
enum PensionTreatment: Hashable, Sendable {
    /// The taxable share of the year it started (Besteuerungsanteil), then a
    /// fixed exempt amount: statutory pensions, German and foreign, and Rürup.
    case cohort
    /// In full (§22 Nr. 5): a German occupational pension (bAV).
    case full
    /// A Swiss BVG pension: its mandatory part like a statutory pension, the
    /// rest at the Ertragsanteil.
    case swiss(mandatoryShare: Double)
    /// The Ertragsanteil for the age at the start: private annuities and
    /// foreign occupational pensions.
    case yieldShare
}

/// A pension's year after stage 3, in today's euros.
struct GermanPensionResult: Hashable, Sendable {
    var id: String
    var amount: Double
    var kind: PensionKind
    var country: String?
    var form: VariableYear.PayoutForm
    var startYear: Int
    var treatment: PensionTreatment
    /// Whether Germany taxes it (residence, or a German pension).
    var taxedHere: Bool
    /// The part taxed on the tariff, before the €102 lump sum (or counted for
    /// the progression clause, when the paying country taxes it).
    var taxable: Double
}

extension GermanYearCalculator {
    /// What kind of pension `pension` is, and from where: known schemes
    /// first, then the plan's `kind` (unknown: statutory, with a warning).
    func classify(_ pension: FixedYear.Pension) -> (kind: PensionKind, country: String?, known: Bool) {
        let country = pension.sourceCountry?.uppercased()
        switch pension.scheme {
        case DRVPensionScheme.schemeID: return (.statutory, country ?? "DE", true)
        case "it.inps": return (.statutory, country ?? "IT", true)
        case "ch.ahv": return (.statutory, country ?? "CH", true)
        case "ch.bvg": return (.occupational, country ?? "CH", true)
        default:
            guard let kind = pension.kind else { return (.statutory, country, false) }
            let known: Set<PensionKind> = [.statutory, .occupational, .basicPension, .privateAnnuity]
            return known.contains(kind) ? (kind, country, true) : (.statutory, country, false)
        }
    }

    /// How a pension of `kind` from `country` is taxed.
    func treatment(_ kind: PensionKind, country: String?, mandatoryShare: Double?) -> PensionTreatment {
        switch kind {
        case .occupational:
            if country == "CH" { return .swiss(mandatoryShare: min(1, max(0, mandatoryShare ?? 1))) }
            return country == nil || country == "DE" ? .full : .yieldShare
        case .privateAnnuity:
            return .yieldShare
        default:
            return .cohort
        }
    }

    /// Stage 3: every pension's taxable part, the €102 lump sum, the
    /// progression income of pensions the paying country taxes, and the
    /// treaty checks in a pension's first year.
    mutating func computePensions() {
        for pension in year.pensions where pension.amount > 0 {
            let (kind, country, known) = classify(pension)
            let amount = pension.amount * rate
            let start = pension.startYear ?? year.year
            let taxedHere = pension.taxedIn == .residence || country == "DE"
            let way = treatment(kind, country: country, mandatoryShare: pension.mandatoryShare)
            if state[GermanStateKey.seen(pension.id)] == nil {
                nextState[GermanStateKey.seen(pension.id)] = 1
                if !known {
                    issues.append(.warning(
                        "de.pension.kindUnknown",
                        "The pension \(pension.id) doesn't say what kind it is (statutory, occupational, basicPension or "
                            + "privateAnnuity): Germany taxes it like a statutory pension.", year: year.year))
                }
                checkTreaty(pension, kind: kind, country: country)
            }
            var taxable = 0.0
            let ageAtStart = start - person.birthYear
            switch way {
            case .cohort:
                taxable = cohortTaxable(pension.id, amount: amount, startYear: start, form: pension.form)
            case .full:
                taxable = amount
            case .swiss(let mandatory):
                if pension.form == .lumpSum {
                    taxable = p.taxableShare.share(startedIn: start) * amount
                    if mandatory < 1 {
                        issues.append(.warning(
                            "de.pension.swissLumpSum",
                            "The over-mandatory part of a Swiss pension-fund lump sum is taxed like its mandatory part, "
                                + "at the cohort's share: the law taxes its gain (or nothing, for membership before 2005), "
                                + "which the plan doesn't know.", year: year.year))
                    }
                } else {
                    taxable = cohortTaxable(pension.id, amount: mandatory * amount, startYear: start, form: pension.form)
                        + (1 - mandatory) * amount * p.annuityShare(ageAtStart: ageAtStart)
                }
            case .yieldShare:
                if pension.form == .lumpSum {
                    issues.append(.warning(
                        "de.pension.lumpSumNotTaxed",
                        "A lump sum from a private annuity or a foreign occupational scheme is taxed on its gain, which "
                            + "the plan doesn't know: \(pension.id) isn't taxed.", year: year.year))
                } else {
                    taxable = amount * p.annuityShare(ageAtStart: ageAtStart)
                }
            }
            pensions.append(GermanPensionResult(id: pension.id, amount: amount, kind: kind, country: country,
                                                form: pension.form, startYear: start, treatment: way,
                                                taxedHere: taxedHere, taxable: taxable))
        }
        let taxed = pensions.filter(\.taxedHere).reduce(0) { $0 + $1.taxable }
        let lumpSum = min(p.pensionLumpSum, taxed)
        pensionIncome = taxed - lumpSum
        pensionLumpSumLeft = p.pensionLumpSum - lumpSum
        let exempt = pensions.filter { !$0.taxedHere }.reduce(0) { $0 + $1.taxable }
        let used = min(pensionLumpSumLeft, exempt)
        pensionProgression = exempt - used
        pensionLumpSumLeft -= used
    }

    /// A statutory-type pension's taxable part: the cohort's share in the
    /// year it starts (and for a lump sum); from the next year, all of it
    /// above the exempt amount fixed then, in nominal euros, which inflation
    /// erodes in today's euros.
    private mutating func cohortTaxable(_ id: String, amount: Double, startYear: Int,
                                        form: VariableYear.PayoutForm) -> Double {
        let share = p.taxableShare.share(startedIn: startYear)
        guard form == .annuity, year.year > startYear else { return share * amount }
        let key = GermanStateKey.exemptAmount(id)
        let factor = year.inflationFactor > 0 ? year.inflationFactor : 1
        if let nominal = state[key] {
            nextState[key] = nominal
            return max(0, amount - nominal / factor)
        }
        let exempt = (1 - share) * amount
        nextState[key] = exempt * factor
        return amount - exempt
    }

    /// Whether the plan's `taxedIn` matches the treaty with the paying
    /// country: Germany–Italy taxes a social-security pension in the paying
    /// state for its nationals who aren't German too (Art. 19(4)); Germany–
    /// Switzerland always in the state of residence (Art. 18). The module
    /// never overrides `taxedIn`; it warns.
    private mutating func checkTreaty(_ pension: FixedYear.Pension, kind: PensionKind, country: String?) {
        guard let country, country != "DE", kind == .statutory || country == "CH",
              let nationals = p.payingStateTaxesItsNationals[country] else { return }
        let payingState: Bool
        if nationals {
            guard !year.citizenships.isEmpty else {
                issues.append(.warning(
                    "de.treaty.citizenshipUnknown",
                    "Whether Germany or \(country) taxes \(pension.id) depends on your citizenship (the treaty taxes a "
                        + "social-security pension in the paying country for its own nationals). Without citizenships "
                        + "in the library, the plan's taxedIn (\(pension.taxedIn.rawValue)) stands.", year: year.year))
                return
            }
            payingState = year.isCitizen(of: country) && !year.isCitizen(of: "DE")
        } else {
            payingState = false
        }
        if payingState && pension.taxedIn == .residence {
            issues.append(.warning(
                "de.treaty.taxedInSource",
                "Under the treaty with \(country), \(country) taxes \(pension.id) (a social-security pension paid to its "
                    + "national): set its taxedIn to source.", year: year.year))
        } else if !payingState && pension.taxedIn == .source {
            issues.append(.warning(
                "de.treaty.taxedInResidence",
                "Under the treaty with \(country), Germany taxes \(pension.id) while you live here: set its taxedIn to "
                    + "residence.", year: year.year))
        }
    }

    /// Health items for the pensions, for the part of the year not covered
    /// as an employee: under KVdR, statutory and comparable foreign pensions
    /// (half the rate) and German occupational pensions (the full rate,
    /// above an allowance); as a voluntary member, every pension.
    func pensionHealthItems(_ status: HealthStatus) -> [HealthItem] {
        var items: [HealthItem] = []
        for pension in pensions {
            let statutoryLike = pension.kind == .statutory || pension.country == "CH" && pension.kind == .occupational
            if statutoryLike {
                let rate = pension.country == "DE" ? rates.statutoryPension : rates.foreignPension
                items.append(HealthItem(kind: .statutoryPension, healthBase: pension.amount, careBase: pension.amount,
                                        rate: rate, deductible: pension.taxedHere))
            } else if pension.treatment == .full {
                continue // German occupational pensions: see occupationalHealthItem.
            } else if status == .voluntary {
                items.append(HealthItem(kind: .other, healthBase: pension.amount, careBase: pension.amount,
                                        rate: rates.reduced, deductible: pension.taxedHere))
            }
        }
        return items
    }

    /// German occupational pensions paid as annuities and as lump sums.
    var occupationalPensions: (annuity: Double, lumpSum: Double) {
        pensions.filter { $0.treatment == .full }.reduce((0, 0)) { total, pension in
            pension.form == .lumpSum ? (total.0, total.1 + pension.amount) : (total.0 + pension.amount, total.1)
        }
    }
}

/// The health item for German occupational pensions (Versorgungsbezüge):
/// under KVdR the full rate on the part above the monthly allowance (a
/// lump sum counts as 1/120 a month for 10 years, all charged in its year),
/// and care on all of it once above the threshold; as a voluntary member,
/// all of it at the full rate.
func occupationalHealthItem(annuity: Double, lumpSum: Double, status: HealthStatus, rates: HealthRates,
                            p: GermanParameters) -> HealthItem? {
    guard annuity + lumpSum > 0 else { return nil }
    switch status {
    case .kvdr:
        let allowance = p.kvdr.occupationalAllowanceMonthly
        let monthly = annuity / 12 + lumpSum / 120
        let left = max(0, allowance - annuity / 12)
        let health = max(0, annuity / 12 - allowance) * 12 + max(0, lumpSum / 120 - left) * 120
        let care = monthly > p.kvdr.occupationalCareThresholdMonthly ? annuity + lumpSum : 0
        return HealthItem(kind: .occupationalPension, healthBase: health, careBase: care, rate: rates.general)
    case .voluntary:
        return HealthItem(kind: .occupationalPension, healthBase: annuity + lumpSum, careBase: annuity + lumpSum,
                          rate: rates.general)
    case .pkv:
        return nil
    }
}
