import Foundation
import TaxKit

extension ThresholdIndexing.Rule {
    /// Amounts the law sets from average wages every year (contribution
    /// ceilings, the minimum base, the bAV limits): in today's euros they
    /// grow with the residence option `realWageGrowth` after the file's year.
    static let wages: ThresholdIndexing.Rule = "wages"
}

/// The factors that turn a parameter file's nominal euros into a simulated
/// year's today's euros, by indexing rule (`"indexed"` in the file).
struct IndexingScales: Hashable, Sendable {
    /// `plan`: the plan's `indexThresholds` decides.
    var plan: Double
    /// `fixed`: nominal by law (or as `plan` with the option `indexFixedAllowances`).
    var fixed: Double
    /// `wages`: grows with real wages.
    var wages: Double

    static let one = IndexingScales(plan: 1, fixed: 1, wages: 1)

    init(plan: Double, fixed: Double, wages: Double) {
        self.plan = plan
        self.fixed = fixed
        self.wages = wages
    }

    /// The factors for `year`, from a file for `parameterYear`.
    init(year: FixedYear, parameterYear: Int, realWageGrowth: Double, indexFixedAllowances: Bool) {
        plan = ThresholdIndexing.scale(for: year, parameterYear: parameterYear, rule: .plan)
        fixed = indexFixedAllowances ? plan : ThresholdIndexing.scale(for: year, parameterYear: parameterYear, rule: .fixed)
        if year.year > parameterYear {
            wages = pow(1 + realWageGrowth, Double(year.year - parameterYear))
        } else {
            wages = ThresholdIndexing.scale(for: year, parameterYear: parameterYear, rule: .fixed)
        }
    }

    func factor(_ rule: ThresholdIndexing.Rule) -> Double {
        switch rule {
        case .law: 1
        case .fixed: fixed
        case .wages: wages
        default: plan
        }
    }
}

/// The §32a tariff: zones of zero, quadratic and linear tax, written the
/// way the law writes them. Not a bracket schedule: the two middle zones are
/// quadratic, so the marginal rate rises smoothly.
///
/// In the file: `{ "zones": [ { "upTo": …, "kind": "zero" }, { "upTo": …,
/// "kind": "quadratic", "from": …, "a": …, "b": …, "c": … }, { "upTo": …,
/// "kind": "linear", "rate": …, "minus": … }, … ] }`. A quadratic zone's tax
/// is `(a × u + b) × u + c` with `u = (x − from) / 10,000`; a linear zone's
/// is `rate × x − minus`. A plan overrides any of them by path, e.g.
/// `de.incomeTax.tariff.zones.4.rate`.
struct ZoneTariff: Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case zero, quadratic, linear
    }

    struct Zone: Hashable, Sendable {
        var upTo: Double?
        var kind: Kind
        var from = 0.0
        var a = 0.0
        var b = 0.0
        var c = 0.0
        var rate = 0.0
        var minus = 0.0

        func tax(_ x: Double) -> Double {
            switch kind {
            case .zero:
                return 0
            case .quadratic:
                let u = (x - from) / 10_000
                return (a * u + b) * u + c
            case .linear:
                return rate * x - minus
            }
        }
    }

    var zones: [Zone]
    /// The tariff in today's euros is `scale × T(x / scale)`, which keeps its shape.
    var scale = 1.0

    init(_ node: ParameterNode) throws {
        zones = try node["zones"].list().map { entry in
            let text = try entry["kind"].string()
            guard let kind = Kind(rawValue: text) else { throw entry["kind"].error("is not zero, quadratic or linear") }
            var zone = Zone(upTo: try entry["upTo"].optionalDouble(), kind: kind)
            switch kind {
            case .zero:
                break
            case .quadratic:
                zone.from = try entry["from"].double()
                zone.a = try entry["a"].double()
                zone.b = try entry["b"].double()
                zone.c = try entry["c"].double(default: 0)
            case .linear:
                zone.rate = try entry["rate"].double()
                zone.minus = try entry["minus"].double(default: 0)
            }
            return zone
        }
        guard !zones.isEmpty else { throw node["zones"].error("is empty") }
        guard zones.dropLast().allSatisfy({ $0.upTo != nil }) else {
            throw node["zones"].error("has an open-ended zone before the last")
        }
    }

    /// The tax on taxable income `income` (0 for none).
    func tax(on income: Double) -> Double {
        guard income > 0 else { return 0 }
        let x = income / scale
        let zone = zones.first { x <= ($0.upTo ?? .infinity) } ?? zones[zones.count - 1]
        return max(0, scale * zone.tax(x))
    }

    /// The zones' upper limits in today's euros.
    var limits: [Double] {
        zones.compactMap(\.upTo).map { $0 * scale }
    }

    /// The basic allowance (Grundfreibetrag): the end of the zero zone, in today's euros.
    var basicAllowance: Double {
        (zones.first { $0.kind == .zero }?.upTo ?? 0) * scale
    }
}

/// The solidarity surcharge (SolZG): nothing up to the exemption limit, then
/// at most `taperRate` of the income tax above it, at most `rate` of all of it.
struct Soli: Hashable, Sendable {
    var rate: Double
    var exemptionLimit: Double
    var taperRate: Double
    /// On the flat tax on capital income, always, with no limit.
    var capitalIncomeRate: Double

    func amount(onIncomeTax tax: Double) -> Double {
        guard tax > exemptionLimit else { return 0 }
        return min(rate * tax, taperRate * (tax - exemptionLimit))
    }
}

/// A contribution rate with the employee's share and a yearly ceiling.
struct Insurance: Hashable, Sendable {
    var rate: Double
    var employeeShare: Double
    var ceiling: Double
}

/// One step of an age table by birth year: born up to `upTo` (or later, for
/// the last), the age in months.
struct AgeStep: Hashable, Sendable {
    var upTo: Int?
    var months: Int

    static func read(_ node: ParameterNode) throws -> [AgeStep] {
        let steps = try node.list().map { entry in
            AgeStep(upTo: try entry["upTo"].exists ? entry["upTo"].int() : nil,
                    months: try entry["years"].int() * 12 + entry["months"].int(default: 0))
        }
        guard !steps.isEmpty else { throw node.error("is empty") }
        return steps
    }

    static func months(_ steps: [AgeStep], bornIn year: Int) -> Int {
        (steps.first { year <= ($0.upTo ?? .max) } ?? steps[steps.count - 1]).months
    }
}

/// One year's German parameters, read from `Resources/de/<year>.json`. The
/// code hard-codes no rate or threshold: everything comes from here.
///
/// Amounts are nominal euros of the file's year; ``scaled(by:)`` turns them
/// into a simulated year's today's euros, each group by the `"indexed"` rule
/// the file gives it (``ThresholdIndexing/Rule``, plus this system's `wages`).
struct GermanParameters: Sendable {
    struct Health: Hashable, Sendable {
        var generalRate: Double
        var reducedRate: Double
        var averageAdditionalRate: Double
        var employeeShare: Double
        var ceiling: Double
        var compulsoryInsuranceLimit: Double
        var voluntaryMinimumBase: Double
        var employerSubsidyMaxMonthly: Double
    }

    struct Care: Hashable, Sendable {
        var rate: Double
        var employeeShare: Double
        var childlessSurcharge: Double
        var childlessFromAge: Int
        var saxonyEmployeeExtra: Double
        var saxonyState: String
        var ceiling: Double
        var discountPerChild: Double
        var discountFromChild: Int
        var discountToChild: Int
        var discountChildUnderAge: Int
    }

    struct KVdR: Hashable, Sendable {
        var qualifyingShare: Double
        var yearsPerChild: Double
        var occupationalAllowanceMonthly: Double
        var occupationalCareThresholdMonthly: Double
        var defaultWorkStartAge: Int
        /// EU, EEA and Swiss country codes: residence years there count as insured.
        var countries: Set<String>
        var statutoryPensionRateShare: Double
        var foreignPensionRateShare: Double
    }

    struct Riester: Hashable, Sendable {
        var maximumWithGrant: Double
        var basicGrant: Double
        var childGrant: Double
        var childGrantBornBefore: Double
        var childGrantFromBirthYear: Int
        var childGrantUntilAge: Int
        var minimumOwnShareOfPriorIncome: Double
        var minimumOwnContribution: Double
        var payoutFromAge: Int
    }

    struct BAV: Hashable, Sendable {
        var taxFreeShare: Double
        var contributionFreeShare: Double
        var employerTopUp: Double
        var payoutFromAge: Int
    }

    struct AltersvorsorgeDepot: Hashable, Sendable {
        var from: Int
        var grant: BracketSchedule
        var maximumOwnContribution: Double
        var payoutFromAge: Int
    }

    struct Relationship: Hashable, Sendable {
        var taxClass: Int
        var allowance: Double
    }

    struct Inheritance: Hashable, Sendable {
        var relationships: [String: Relationship]
        var giftRelationships: [String: Relationship]
        var defaultRelationship: String
        var limits: [Double]
        var rates: [Int: [Double]]
        var reliefShareUpTo30Percent: Double
        var reliefShareAbove30Percent: Double
    }

    struct TradeTax: Hashable, Sendable {
        var allowance: Double
        var baseRate: Double
        var minimumMultiplier: Double
        var creditFactor: Double
    }

    struct CohortShare: Hashable, Sendable {
        struct Segment: Hashable, Sendable {
            var from: Int
            var value: Double
            var step: Double
            var until: Int
        }

        var segments: [Segment]
        var before: Double
        var after: Double

        /// The taxable share for a pension that started in `year`: the
        /// segment's value plus its step for each year since it began.
        func share(startedIn year: Int) -> Double {
            if let segment = segments.first(where: { year >= $0.from && year <= $0.until }) {
                return min(1, segment.value + segment.step * Double(year - segment.from))
            }
            return year < (segments.map(\.from).min() ?? year) ? before : after
        }
    }

    var year: Int
    // Income tax.
    var tariff: ZoneTariff
    var oneFifthDivisor: Double
    var oneFifthKinds: Set<String>
    var soli: Soli
    var churchRates: [String: Double]
    var churchDefaultRate: Double
    // Allowances and lump sums.
    var employeeLumpSum: Double
    var pensionLumpSum: Double
    var specialExpensesLumpSum: Double
    var saverAllowance: Double
    // Special expenses.
    var retirementMaximum: Double
    var otherMaximumEmployee: Double
    var otherMaximumSelfPaid: Double
    var sickPayReduction: Double
    // Social insurance.
    var pension: Insurance
    var unemployment: Insurance
    var health: Health
    var care: Care
    var referenceValue: Double
    var drvVoluntaryMinimum: Double
    var drvVoluntaryMaximum: Double
    var drvStandardContribution: Double
    var aktivrenteMonthly: Double
    var standardAge: [AgeStep]
    // Pensions.
    var taxableShare: CohortShare
    var annuityShares: [(upToAge: Int?, value: Double)]
    var kvdr: KVdR
    var voluntaryStatutoryPensionRateShare: Double
    var pkvSubsidyRateShare: Double
    var pkvSubsidyMaxShare: Double
    // Investments.
    var flatRate: Double
    /// The share of the proceeds taxed when a sale's cost isn't known.
    var undocumentedGainShare: Double
    var partialExemption: [TaxCategory: Double]
    var basiszins: Double
    var basisShare: Double
    var privateSaleCategories: Set<TaxCategory>
    // Wrappers.
    var riester: Riester
    var ruerupPayoutFromAge: Int
    var bav: BAV
    var altersvorsorgedepot: AltersvorsorgeDepot
    var payoutYears: [String: Int]
    var foreignHalfGainAfterYears: Int
    var foreignHalfGainFromAge: Int
    // Other.
    var inheritance: Inheritance
    var tradeTax: TradeTax
    var exitTaxResidenceYears: Int
    var exitTaxLookbackYears: Int
    var exitTaxFundCost: Double
    var payingStateTaxesItsNationals: [String: Bool]
    var moveToSwitzerlandYears: Int
    var moveToSwitzerlandPriorYears: Int
    /// The share of a non-resident's income that must be taxed in Germany
    /// for them to be taxed as a resident (§1 Abs. 3): 90%.
    var residentTreatmentShare: Double

    /// How each group of amounts follows prices, from the file.
    var rules: [String: ThresholdIndexing.Rule]

    init(_ set: ParameterSet) throws {
        let root = ParameterNode(set)
        year = set.year
        var rules: [String: ThresholdIndexing.Rule] = [:]
        func rule(_ path: String) -> ThresholdIndexing.Rule {
            let found = set.indexingRule(at: path)
            rules[path] = found
            return found
        }

        let income = root["incomeTax"]
        tariff = try ZoneTariff(income["tariff"])
        _ = rule("incomeTax.tariff")
        oneFifthDivisor = try income["oneFifthRule"]["divisor"].double()
        oneFifthKinds = Set(try income["oneFifthRule"]["windfallKinds"].strings())
        let soli = root["soli"]
        self.soli = Soli(rate: try soli["rate"].double(), exemptionLimit: try soli["exemptionLimit"].double(),
                         taperRate: try soli["taperRate"].double(), capitalIncomeRate: try soli["capitalIncomeRate"].double())
        _ = rule("soli")
        var church = try root["churchTax"]["rates"].members().mapValues { try $0.double() }
        churchDefaultRate = try church.removeValue(forKey: "default") ?? root["churchTax"]["rates"]["default"].double()
        churchRates = Dictionary(uniqueKeysWithValues: church.map { ($0.key.uppercased(), $0.value) })

        let allowances = root["allowances"]
        employeeLumpSum = try allowances["employeeLumpSum"]["value"].double()
        pensionLumpSum = try allowances["pensionIncomeLumpSum"]["value"].double()
        specialExpensesLumpSum = try allowances["specialExpensesLumpSum"]["value"].double()
        saverAllowance = try allowances["saverAllowance"]["value"].double()
        for key in ["employeeLumpSum", "pensionIncomeLumpSum", "specialExpensesLumpSum", "saverAllowance"] {
            _ = rule("allowances.\(key)")
        }

        let provisions = root["provisions"]
        retirementMaximum = try provisions["retirementMaximum"]["value"].double()
        otherMaximumEmployee = try provisions["otherMaximumEmployee"]["value"].double()
        otherMaximumSelfPaid = try provisions["otherMaximumSelfPaid"]["value"].double()
        sickPayReduction = try provisions["sickPayReduction"]["value"].double()
        for key in ["retirementMaximum", "otherMaximumEmployee", "otherMaximumSelfPaid"] { _ = rule("provisions.\(key)") }

        let social = root["socialInsurance"]
        func insurance(_ node: ParameterNode) throws -> Insurance {
            Insurance(rate: try node["rate"].double(), employeeShare: try node["employeeShare"].double(),
                      ceiling: try node["ceiling"].double())
        }
        pension = try insurance(social["pension"])
        unemployment = try insurance(social["unemployment"])
        let health = social["health"]
        self.health = Health(
            generalRate: try health["generalRate"].double(), reducedRate: try health["reducedRate"].double(),
            averageAdditionalRate: try health["averageAdditionalRate"].double(),
            employeeShare: try health["employeeShare"].double(), ceiling: try health["ceiling"].double(),
            compulsoryInsuranceLimit: try health["compulsoryInsuranceLimit"].double(),
            voluntaryMinimumBase: try health["voluntaryMinimumBase"].double(),
            employerSubsidyMaxMonthly: try health["employerSubsidyMaxMonthly"].double())
        let care = social["care"]
        let discount = care["childDiscount"]
        self.care = Care(
            rate: try care["rate"].double(), employeeShare: try care["employeeShare"].double(),
            childlessSurcharge: try care["childlessSurcharge"].double(), childlessFromAge: try care["childlessFromAge"].int(),
            saxonyEmployeeExtra: try care["saxonyEmployeeExtra"].double(),
            saxonyState: try care["saxonyState"].string().uppercased(), ceiling: try care["ceiling"].double(),
            discountPerChild: try discount["perChild"].double(), discountFromChild: try discount["fromChild"].int(),
            discountToChild: try discount["toChild"].int(), discountChildUnderAge: try discount["childUnderAge"].int())
        referenceValue = try social["referenceValue"]["value"].double()
        for key in ["pension", "unemployment", "health", "care", "referenceValue"] { _ = rule("socialInsurance.\(key)") }

        let voluntary = root["freelancer"]["drvVoluntary"]
        drvVoluntaryMinimum = try voluntary["minimumMonthly"].double() * 12
        drvVoluntaryMaximum = try voluntary["maximumMonthly"].double() * 12
        drvStandardContribution = try voluntary["standardMonthly"].double() * 12
        _ = rule("freelancer.drvVoluntary")
        aktivrenteMonthly = try root["aktivrente"]["monthlyExemption"].double()
        _ = rule("aktivrente")
        standardAge = try AgeStep.read(root["drv"]["standardAge"]["byBirthYear"])

        let taxation = root["pensionTaxation"]
        let share = taxation["taxableShare"]
        taxableShare = CohortShare(
            segments: try share["segments"].list().map { segment in
                CohortShare.Segment(from: try segment["from"].int(), value: try segment["value"].double(),
                                    step: try segment["stepPerYear"].double(), until: try segment["until"].int())
            },
            before: try share["beforeFirstYear"].double(), after: try share["afterLastYear"].double())
        annuityShares = try taxation["annuityIncomeShare"]["byAgeAtStart"].list().map { entry in
            let upTo: Int? = try entry["upToAge"].exists ? entry["upToAge"].int() : nil
            return (upToAge: upTo, value: try entry["value"].double())
        }
        guard !annuityShares.isEmpty else { throw taxation["annuityIncomeShare"]["byAgeAtStart"].error("is empty") }

        let phi = root["pensionHealthInsurance"]
        let kvdr = phi["kvdr"]
        self.kvdr = KVdR(
            qualifyingShare: try kvdr["qualifyingShare"].double(), yearsPerChild: try kvdr["yearsPerChild"].double(),
            occupationalAllowanceMonthly: try kvdr["occupationalHealthAllowanceMonthly"].double(),
            occupationalCareThresholdMonthly: try kvdr["occupationalCareThresholdMonthly"].double(),
            defaultWorkStartAge: try kvdr["defaultWorkStartAge"].int(),
            countries: Set(try phi["periodsAbroadForKvdr"]["countries"].strings().map { $0.uppercased() }),
            statutoryPensionRateShare: try kvdr["pensionRateShare"].double(),
            foreignPensionRateShare: try kvdr["foreignPensionRateShare"].double())
        _ = rule("pensionHealthInsurance.kvdr")
        voluntaryStatutoryPensionRateShare = try phi["voluntary"]["drvSubsidyShare"].double()
        pkvSubsidyRateShare = try phi["pkvSubsidy"]["rateShare"].double()
        pkvSubsidyMaxShare = try phi["pkvSubsidy"]["maxShareOfPremium"].double()

        let investments = root["investments"]
        flatRate = try investments["flatRate"]["rate"].double()
        undocumentedGainShare = try investments["undocumentedCost"]["substituteGainShare"].double()
        partialExemption = Dictionary(uniqueKeysWithValues: try investments["partialExemption"]["rates"].members()
            .map { (TaxCategory(rawValue: $0.key), try $0.value.double()) })
        basiszins = try investments["vorabpauschale"]["basiszins"].double()
        basisShare = try investments["vorabpauschale"]["basisShare"].double()
        privateSaleCategories = Set(try investments["privateSales"]["categories"].strings().map { TaxCategory(rawValue: $0) })
        _ = rule("investments.privateSales")

        let wrappers = root["wrappers"]
        let riester = wrappers["riester"]
        self.riester = Riester(
            maximumWithGrant: try riester["maximumWithGrant"].double(), basicGrant: try riester["basicGrant"].double(),
            childGrant: try riester["childGrant"].double(),
            childGrantBornBefore: try riester["childGrantBornBefore2008"].double(),
            childGrantFromBirthYear: try riester["childGrantFromBirthYear"].int(),
            childGrantUntilAge: try riester["childGrantUntilAge"].int(),
            minimumOwnShareOfPriorIncome: try riester["minimumOwnShareOfPriorIncome"].double(),
            minimumOwnContribution: try riester["minimumOwnContribution"].double(),
            payoutFromAge: try riester["payoutFromAge"].int())
        ruerupPayoutFromAge = try wrappers["ruerup"]["payoutFromAge"].int()
        let bav = wrappers["bav"]
        self.bav = BAV(taxFreeShare: try bav["taxFreeShareOfPensionCeiling"].double(),
                       contributionFreeShare: try bav["contributionFreeShareOfPensionCeiling"].double(),
                       employerTopUp: try bav["employerTopUp"].double(), payoutFromAge: try bav["payoutFromAge"].int())
        let depot = wrappers["altersvorsorgedepot"]
        altersvorsorgedepot = AltersvorsorgeDepot(
            from: try depot["from"].int(),
            grant: BracketSchedule(try depot["grant"]["bands"].list().map {
                BracketSchedule.Bracket(upTo: try $0["upTo"].optionalDouble(), rate: try $0["rate"].double())
            }),
            maximumOwnContribution: try depot["maximumOwnContribution"].double(),
            payoutFromAge: try depot["payoutFromAge"].int())
        for key in ["riester", "bav", "altersvorsorgedepot"] { _ = rule("wrappers.\(key)") }
        payoutYears = try wrappers["payoutPlan"].members().compactMapValues { $0.value?.intValue }
        foreignHalfGainAfterYears = try wrappers["foreign"]["halfGainAfterYears"].int()
        foreignHalfGainFromAge = try wrappers["foreign"]["halfGainFromAge"].int()

        let inheritance = root["inheritance"]
        func relationships(_ node: ParameterNode) throws -> [String: Relationship] {
            try node.members().mapValues {
                Relationship(taxClass: try $0["class"].int(), allowance: try $0["allowance"].double())
            }
        }
        let classRates = inheritance["classRates"]
        var rates: [Int: [Double]] = [:]
        for (key, value) in try classRates.members() where key != "limits" {
            guard let taxClass = Int(key) else { continue }
            rates[taxClass] = try value.doubles()
        }
        let limits = try classRates["limits"].doubles()
        for (taxClass, list) in rates where list.count != limits.count + 1 {
            throw classRates["\(taxClass)"].error("needs one rate more than there are limits")
        }
        self.inheritance = Inheritance(
            relationships: try relationships(inheritance["relationships"]),
            giftRelationships: try inheritance["giftRelationships"].exists
                ? relationships(inheritance["giftRelationships"]) : [:],
            defaultRelationship: try inheritance["defaultRelationship"].string(), limits: limits, rates: rates,
            reliefShareUpTo30Percent: try inheritance["hardshipRelief"]["shareUpTo30Percent"].double(),
            reliefShareAbove30Percent: try inheritance["hardshipRelief"]["shareAbove30Percent"].double())
        guard self.inheritance.relationships[self.inheritance.defaultRelationship] != nil else {
            throw inheritance["defaultRelationship"].error("names no relationship")
        }
        _ = rule("inheritance")

        let trade = root["tradeTax"]
        tradeTax = TradeTax(allowance: try trade["allowance"].double(), baseRate: try trade["baseRate"].double(),
                            minimumMultiplier: try trade["minimumMultiplier"].double(),
                            creditFactor: try trade["incomeTaxCreditFactor"].double())
        _ = rule("tradeTax")
        let exit = root["exitTax"]
        exitTaxResidenceYears = try exit["residenceYears"].int()
        exitTaxLookbackYears = try exit["lookbackYears"].int()
        exitTaxFundCost = try exit["fundCostThreshold"].double()

        var nationals: [String: Bool] = [:]
        for (country, treaty) in try root["treaties"].members() {
            if let rule = treaty["socialSecurityPensions"]["payingStateTaxesItsNationals"].value?.boolValue {
                nationals[country.uppercased()] = rule
            }
        }
        payingStateTaxesItsNationals = nationals
        let move = root["treaties"]["CH"]["extendedTaxationAfterMove"]
        moveToSwitzerlandYears = try move["years"].int()
        moveToSwitzerlandPriorYears = try move["minimumPriorGermanYears"].int()
        residentTreatmentShare = try root["nonResident"]["residentTreatmentShare"].double()
        self.rules = rules
    }

    /// The rule for a group, `plan` when the file gives none.
    func rule(_ path: String) -> ThresholdIndexing.Rule {
        rules[path] ?? .plan
    }

    /// The Ertragsanteil for an annuity that started at `age`.
    func annuityShare(ageAtStart age: Int) -> Double {
        (annuityShares.first { age <= ($0.upToAge ?? .max) } ?? annuityShares[annuityShares.count - 1]).value
    }

    /// The church-tax rate in a federal state (`nil`: the rate of most states).
    func churchRate(in state: String?) -> Double {
        state.flatMap { churchRates[$0.uppercased()] } ?? churchDefaultRate
    }

    /// The standard retirement age (Regelaltersgrenze) in months, by birth year.
    func standardAgeMonths(bornIn year: Int) -> Int {
        AgeStep.months(standardAge, bornIn: year)
    }

    /// The partial exemption (Teilfreistellung) of a category: 30% for an
    /// equity fund, 15% mixed, 60% or 80% real estate, 0% for other funds and
    /// everything else.
    func partialExemption(_ category: TaxCategory) -> Double {
        partialExemption[category] ?? 0
    }

    /// Whether `category` is a fund, which pays the Vorabpauschale.
    static func isFund(_ category: TaxCategory) -> Bool {
        category == .fund || category.broader == .fund
    }

    /// These parameters in a simulated year's today's euros.
    func scaled(by scales: IndexingScales) -> GermanParameters {
        guard scales != .one else { return self }
        var p = self
        func f(_ path: String) -> Double { scales.factor(rule(path)) }
        p.tariff.scale = tariff.scale * f("incomeTax.tariff")
        p.soli.exemptionLimit *= f("soli")
        p.employeeLumpSum *= f("allowances.employeeLumpSum")
        p.pensionLumpSum *= f("allowances.pensionIncomeLumpSum")
        p.specialExpensesLumpSum *= f("allowances.specialExpensesLumpSum")
        p.saverAllowance *= f("allowances.saverAllowance")
        p.retirementMaximum *= f("provisions.retirementMaximum")
        p.otherMaximumEmployee *= f("provisions.otherMaximumEmployee")
        p.otherMaximumSelfPaid *= f("provisions.otherMaximumSelfPaid")
        p.pension.ceiling *= f("socialInsurance.pension")
        p.unemployment.ceiling *= f("socialInsurance.unemployment")
        let health = f("socialInsurance.health")
        p.health.ceiling *= health
        p.health.compulsoryInsuranceLimit *= health
        p.health.voluntaryMinimumBase *= health
        p.health.employerSubsidyMaxMonthly *= health
        p.care.ceiling *= f("socialInsurance.care")
        p.referenceValue *= f("socialInsurance.referenceValue")
        let voluntary = f("freelancer.drvVoluntary")
        p.drvVoluntaryMinimum *= voluntary
        p.drvVoluntaryMaximum *= voluntary
        p.drvStandardContribution *= voluntary
        p.aktivrenteMonthly *= f("aktivrente")
        let kvdr = f("pensionHealthInsurance.kvdr")
        p.kvdr.occupationalAllowanceMonthly *= kvdr
        p.kvdr.occupationalCareThresholdMonthly *= kvdr
        let riester = f("wrappers.riester")
        p.riester.maximumWithGrant *= riester
        p.riester.basicGrant *= riester
        p.riester.childGrant *= riester
        p.riester.childGrantBornBefore *= riester
        p.riester.minimumOwnContribution *= riester
        let depot = f("wrappers.altersvorsorgedepot")
        p.altersvorsorgedepot.grant = altersvorsorgedepot.grant.scaled(by: depot)
        p.altersvorsorgedepot.maximumOwnContribution *= depot
        let inheritance = f("inheritance")
        p.inheritance.relationships = self.inheritance.relationships.mapValues {
            Relationship(taxClass: $0.taxClass, allowance: $0.allowance * inheritance)
        }
        p.inheritance.giftRelationships = self.inheritance.giftRelationships.mapValues {
            Relationship(taxClass: $0.taxClass, allowance: $0.allowance * inheritance)
        }
        p.inheritance.limits = self.inheritance.limits.map { $0 * inheritance }
        p.tradeTax.allowance *= f("tradeTax")
        return p
    }
}
