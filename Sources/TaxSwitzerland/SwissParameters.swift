import TaxKit

/// One tax year's Swiss parameters, read from `Resources/ch/<year>.json`.
/// The code hard-codes no rate or threshold: everything comes from here.
///
/// Amounts are nominal CHF of the file's year. ``scaled(for:)`` turns them
/// into today's francs for a simulated year, following each object's
/// `indexed` rule: most Swiss amounts are indexed by law (`law`, so they keep
/// their value), a few are fixed in nominal terms (`fixed`), and the rest
/// follow the plan's `indexThresholds`.
struct SwissParameters: Sendable {
    /// A flat professional-expense deduction: a share of net salary between
    /// a minimum and a maximum, or a flat amount.
    struct ProfessionalExpenses: Sendable {
        var rate: Double
        var minimum: Double
        var maximum: Double
        var flat: Double?

        init(_ node: ParameterNode) throws {
            flat = try node["flat"].optionalDouble()
            rate = try node["rate"].double(default: 0)
            minimum = try node["minimum"].double(default: 0)
            maximum = try node["maximum"].double(default: flat ?? 0)
        }

        /// The deduction for `netSalary` earned over `employedShare` of a year:
        /// the limits and the flat amount are pro rata.
        func amount(netSalary: Double, employedShare: Double) -> Double {
            guard netSalary > 0, employedShare > 0 else { return 0 }
            if let flat { return min(netSalary, flat * employedShare) }
            let raw = rate * netSalary
            return min(netSalary, min(maximum * employedShare, max(minimum * employedShare, raw)))
        }

        func scaled(by factor: Double) -> ProfessionalExpenses {
            var result = self
            result.minimum *= factor
            result.maximum *= factor
            result.flat = flat.map { $0 * factor }
            return result
        }
    }

    /// The insurance-premium deduction, with and without 2nd-pillar or 3a contributions.
    struct Insurance: Sendable {
        var withPensionContributions: Double
        var withoutPensionContributions: Double

        init(_ node: ParameterNode) throws {
            withPensionContributions = try node["withPensionContributions"].double()
            withoutPensionContributions = try node["withoutPensionContributions"].double()
        }

        func amount(withPensionContributions: Bool) -> Double {
            withPensionContributions ? self.withPensionContributions : withoutPensionContributions
        }
    }

    struct Federal: Sendable {
        var tariff: BracketSchedule
        var maximumAverageRate: Double
        var minimumTax: Double
        var professionalExpenses: ProfessionalExpenses
        var insurance: Insurance
        var capitalBenefitShare: Double
        var lumpSumMinimumBase: Double
        var lumpSumRentMultiple: Double

        /// The tax on `taxable` at the rate of `rateBase` (at least
        /// `taxable`; more when income exempt by a treaty counts for the
        /// rate), at most 11.5% of the base; amounts under the minimum aren't levied.
        func incomeTax(on taxable: Double, rateBase: Double) -> Double {
            guard taxable > 0 else { return 0 }
            let base = max(taxable, rateBase)
            let tax = min(tariff.tax(on: base), maximumAverageRate * base) * taxable / base
            return tax < minimumTax ? 0 : tax
        }

        /// The separate tax on a year's capital benefits: a share of the tariff.
        func capitalBenefitTax(on amount: Double) -> Double {
            guard amount > 0 else { return 0 }
            return min(tariff.tax(on: amount), maximumAverageRate * amount) * capitalBenefitShare
        }
    }

    struct EmployeeContributions: Sendable {
        var ahvRate: Double
        var ahvEmployerRate: Double
        var alvRate: Double
        var alvEmployerRate: Double
        var alvCap: Double
        var alvSolidarityRate: Double
        var retireeAllowance: Double
    }

    struct SelfEmployedContributions: Sendable {
        var fullRate: Double
        var fullRateFrom: Double
        var lowestRate: Double
        var slidingScaleFrom: Double
        var minimum: Double

        /// The AHV/IV/EO contribution on a year's net income from
        /// self-employment: the minimum below the sliding scale, or, past the
        /// reference age (`applyingMinimum` false), the scale's lowest rate.
        func contribution(onYearlyIncome income: Double, applyingMinimum: Bool = true) -> Double {
            guard income > 0 else { return 0 }
            if income < slidingScaleFrom { return applyingMinimum ? minimum : lowestRate * income }
            if income >= fullRateFrom { return fullRate * income }
            let share = (income - slidingScaleFrom) / (fullRateFrom - slidingScaleFrom)
            return (lowestRate + (fullRate - lowestRate) * share) * income
        }
    }

    struct NonEmployed: Sendable {
        struct Step: Sendable {
            var from: Double
            var contribution: Double
            var perStep: Double
        }

        var minimum: Double
        var maximum: Double
        var pensionIncomeMultiple: Double
        var fromAge: Int
        /// Months of work in a year that count as permanent full-time work.
        var fullTimeMonths: Int
        var steps: [Step]
        var stepWidth: Double
        var adminCostMaximumRate: Double
        var ahvShare: Double
        var divisorRate: Double

        /// The yearly contribution on a base of net wealth plus 20 × pension income.
        func contribution(onBase base: Double) -> Double {
            guard let step = steps.last(where: { base >= $0.from }) else { return minimum }
            let completed = stepWidth > 0 ? ((base - step.from) / stepWidth).rounded(.down) : 0
            return min(maximum, step.contribution + step.perStep * completed)
        }

        /// The income a contribution is credited as for the AHV average.
        func creditedIncome(forContribution contribution: Double) -> Double {
            divisorRate > 0 ? contribution * ahvShare / divisorRate : 0
        }

        func scaled(by factor: Double) -> NonEmployed {
            var result = self
            result.minimum *= factor
            result.maximum *= factor
            result.steps = steps.map { Step(from: $0.from * factor, contribution: $0.contribution * factor,
                                            perStep: $0.perStep * factor) }
            result.stepWidth *= factor
            return result
        }
    }

    struct BVG: Sendable {
        var entryThreshold: Double
        var coordinationDeduction: Double
        var upperLimit: Double
        var minimumCoordinatedSalary: Double
        var ageCredits: [(fromAge: Int, rate: Double)]
        var minimumEmployerShare: Double
        var earliestAge: Int
        var latestAgeIfWorking: Int
        var lockYears: Int
        var arrivalShareOfInsuredSalary: Double
        var arrivalYears: Int
        var minimumLumpSumShare: Double

        /// The legal age-credit rate at `age` (0 below the first band).
        func creditRate(age: Int) -> Double {
            ageCredits.last { age >= $0.fromAge }?.rate ?? 0
        }
    }

    struct BVGDefaults: Sendable {
        var conversionRateAt65: Double
        var conversionRateStepPerYear: Double
        var realInterest: Double
        var inflation: Double
    }

    struct Pillar3a: Sendable {
        var maximumWithPensionFund: Double
        var shareWithoutPensionFund: Double
        var maximumWithoutPensionFund: Double
        var earliestYearsBeforeReferenceAge: Int
        var latestYearsAfterReferenceAgeIfWorking: Int
    }

    struct VestedBenefits: Sendable {
        var earliestYearsBeforeReferenceAge: Int
        var latestYearsAfterReferenceAgeIfWorking: Int
        var maxAccounts: Int
    }

    /// The AHV old-age pension rules (scale 44).
    struct AHVPension: Sendable {
        var minimumMonthly: Double
        var maximumMonthly: Double
        var paymentsPerYear: Double
        var thirteenthPaymentFrom: Int
        var fullScaleYears: Double
        var referenceAge: Int
        var minimumContributionYears: Double
        var lowerBandMultiple: Double
        var lowerFixedShare: Double
        var lowerVariableShare: Double
        var upperFixedShare: Double
        var upperVariableShare: Double
        var earlyMaxYears: Int
        var earlyReductionPerYear: Double
        var deferralSupplements: [Double]

        init(_ node: ParameterNode) throws {
            minimumMonthly = try node["minimumMonthly"].double()
            maximumMonthly = try node["maximumMonthly"].double()
            paymentsPerYear = try node["paymentsPerYear"].double()
            thirteenthPaymentFrom = try node["thirteenthPayment"]["from"].int()
            fullScaleYears = try node["fullScaleYears"].double()
            referenceAge = try node["referenceAge"].int()
            minimumContributionYears = try node["minimumContributionYears"].double(default: 1)
            let formula = node["formula"]
            lowerBandMultiple = try formula["lowerBand"]["upToMinimumPensionMultiple"].double()
            lowerFixedShare = try formula["lowerBand"]["fixedShareOfMinimum"].double()
            lowerVariableShare = try formula["lowerBand"]["variableShareOfIncome"].double()
            upperFixedShare = try formula["upperBand"]["fixedShareOfMinimum"].double()
            upperVariableShare = try formula["upperBand"]["variableShareOfIncome"].double()
            earlyMaxYears = try node["earlyWithdrawal"]["maxYears"].int()
            earlyReductionPerYear = try node["earlyWithdrawal"]["reductionPerYear"].double()
            deferralSupplements = try node["deferral"]["supplements"].doubles()
        }

        var earliestAge: Int { referenceAge - earlyMaxYears }
        var latestAge: Int { referenceAge + deferralSupplements.count }

        /// The monthly pension with a full record for an average yearly
        /// income, between the minimum and the maximum pension.
        func fullMonthlyPension(averageIncome income: Double) -> Double {
            let amount = income <= lowerBandMultiple * minimumMonthly
                ? lowerFixedShare * minimumMonthly + lowerVariableShare * income
                : upperFixedShare * minimumMonthly + upperVariableShare * income
            return min(maximumMonthly, max(minimumMonthly, amount))
        }

        /// The factor for claiming at `age`: a reduction for each year early,
        /// the deferral supplement for each year late.
        func adjustment(claimAge age: Int) -> Double {
            if age < referenceAge { return 1 - earlyReductionPerYear * Double(referenceAge - age) }
            if age == referenceAge { return 1 }
            let years = min(age - referenceAge, deferralSupplements.count)
            return 1 + (years > 0 ? deferralSupplements[years - 1] : 0)
        }

        /// Payments a year (13 from the year of the 13th payment, else 12).
        func payments(in year: Int) -> Double {
            year >= thirteenthPaymentFrom ? paymentsPerYear : 12
        }
    }

    /// How the system treats another system's wrapper.
    enum ForeignWrapper: String, Sendable {
        /// Like `ch.ordinary`.
        case taxable
        /// No wealth tax or tax inside; payouts taxed as capital benefits.
        case taxDeferred
        /// Payouts taxed only by the paying country.
        case taxedAtSource
    }

    var year: Int
    var federal: Federal
    var employee: EmployeeContributions
    var selfEmployed: SelfEmployedContributions
    var nonEmployed: NonEmployed
    var ahv: AHVPension
    var bvg: BVG
    var bvgDefaults: BVGDefaults
    var pillar3a: Pillar3a
    var vestedBenefits: VestedBenefits
    var imputedRentLastYear: Int
    var mortgageInterestCap: Double
    var expatriateYears: Int
    var expatriateFlatPerMonth: Double
    var traderGainsShare: Double
    var ordinaryAssessmentFromSalary: Double
    var cantons: [String: SwissCanton]
    var foreignWrappers: [String: ForeignWrapper]
    /// The indexing rule of each scaled object, by path.
    var rules: [String: ThresholdIndexing.Rule]

    init(_ set: ParameterSet) throws {
        let root = ParameterNode(set)
        year = set.year

        let tariff = root["federal"]["tariff"]
        let deductions = root["federal"]["deductions"]
        federal = Federal(
            tariff: try BracketSchedule(tariff["single"]),
            maximumAverageRate: try tariff["single"]["maximumAverageRate"].double(),
            minimumTax: try tariff["minimumTax"]["value"].double(default: 0),
            professionalExpenses: try ProfessionalExpenses(deductions["professionalExpenses"]),
            insurance: try Insurance(deductions["insurancePremiums"]),
            capitalBenefitShare: try root["federal"]["capitalBenefits"]["share"].double(),
            lumpSumMinimumBase: try root["federal"]["lumpSumTaxation"]["minimumBase"].double(),
            lumpSumRentMultiple: try root["federal"]["lumpSumTaxation"]["rentMultiple"].double())

        let social = root["socialSecurity"]
        let employee = social["employee"]
        self.employee = EmployeeContributions(
            ahvRate: try employee["ahvIvEo"]["employeeRate"].double(),
            ahvEmployerRate: try employee["ahvIvEo"]["employerRate"].double(),
            alvRate: try employee["alv"]["employeeRate"].double(),
            alvEmployerRate: try employee["alv"]["employerRate"].double(),
            alvCap: try employee["alv"]["salaryCap"].double(),
            alvSolidarityRate: try employee["alv"]["solidarityRate"].double(default: 0),
            retireeAllowance: try employee["retireeAllowance"].double())
        let selfEmployed = social["selfEmployed"]
        self.selfEmployed = SelfEmployedContributions(
            fullRate: try selfEmployed["fullRate"].double(), fullRateFrom: try selfEmployed["fullRateFrom"].double(),
            lowestRate: try selfEmployed["lowestRate"].double(),
            slidingScaleFrom: try selfEmployed["slidingScaleFrom"].double(),
            minimum: try selfEmployed["minimumContribution"].double())
        let non = social["nonEmployed"]
        nonEmployed = NonEmployed(
            minimum: try non["minimum"].double(), maximum: try non["maximum"].double(),
            pensionIncomeMultiple: try non["pensionIncomeMultiple"].double(), fromAge: try non["fromAge"].int(),
            fullTimeMonths: try non["fullTimeMonths"].int(),
            steps: try non["steps"].list().map {
                NonEmployed.Step(from: try $0["from"].double(), contribution: try $0["contribution"].double(),
                                 perStep: try $0["perStep"].double())
            },
            stepWidth: try non["stepWidth"].double(),
            adminCostMaximumRate: try non["adminCostMaximumRate"].double(),
            ahvShare: try non["incomeCredit"]["ahvShare"].double(),
            divisorRate: try non["incomeCredit"]["divisorRate"].double())

        ahv = try AHVPension(root["ahvPension"])

        let bvg = root["bvg"]
        self.bvg = BVG(
            entryThreshold: try bvg["entryThreshold"].double(),
            coordinationDeduction: try bvg["coordinationDeduction"].double(),
            upperLimit: try bvg["upperLimit"].double(),
            minimumCoordinatedSalary: try bvg["minimumCoordinatedSalary"].double(),
            ageCredits: try bvg["ageCredits"].list().map { (try $0["fromAge"].int(), try $0["rate"].double()) },
            minimumEmployerShare: try bvg["minimumEmployerShare"].double(),
            earliestAge: try bvg["earliestRetirementAge"].int(),
            latestAgeIfWorking: try bvg["latestRetirementAgeIfWorking"].int(),
            lockYears: try bvg["buyIns"]["lumpSumLockYears"].int(),
            arrivalShareOfInsuredSalary:
                try bvg["buyIns"]["arrivalFromAbroad"]["maxShareOfInsuredSalaryPerYear"].double(),
            arrivalYears: try bvg["buyIns"]["arrivalFromAbroad"]["years"].int(),
            minimumLumpSumShare: try bvg["minimumLumpSumShare"].double())
        let defaults = root["bvgSchemeDefaults"]
        bvgDefaults = BVGDefaults(
            conversionRateAt65: try defaults["conversionRateAt65"].double(),
            conversionRateStepPerYear: try defaults["conversionRateStepPerYear"].double(),
            realInterest: try defaults["realInterest"].double(), inflation: try defaults["inflation"].double())

        let p3a = root["pillar3a"]
        pillar3a = Pillar3a(
            maximumWithPensionFund: try p3a["maximumWithPensionFund"].double(),
            shareWithoutPensionFund: try p3a["withoutPensionFund"]["shareOfNetEarnedIncome"].double(),
            maximumWithoutPensionFund: try p3a["withoutPensionFund"]["maximum"].double(),
            earliestYearsBeforeReferenceAge: try p3a["earliestYearsBeforeReferenceAge"].int(),
            latestYearsAfterReferenceAgeIfWorking: try p3a["latestYearsAfterReferenceAgeIfWorking"].int())
        let vested = root["vestedBenefits"]
        vestedBenefits = VestedBenefits(
            earliestYearsBeforeReferenceAge: try vested["earliestYearsBeforeReferenceAge"].int(),
            latestYearsAfterReferenceAgeIfWorking: try vested["latestYearsAfterReferenceAgeIfWorking"].int(),
            maxAccounts: try vested["maxAccounts"].int())

        imputedRentLastYear = try root["property"]["imputedRentalValue"]["lastYear"].int()
        mortgageInterestCap = try root["property"]["mortgageInterest"]["capAboveInvestmentIncome"].double()
        expatriateYears = try root["expatriates"]["maxYears"].int()
        expatriateFlatPerMonth = try root["expatriates"]["flatDeductionPerMonth"].double()
        traderGainsShare = try root["investments"]["professionalTrader"]["maximumGainsShareOfNetIncome"].double()
        ordinaryAssessmentFromSalary = try root["sourceTax"]["mandatoryOrdinaryAssessmentFrom"].double()

        var cantons: [String: SwissCanton] = [:]
        for (code, node) in try root["cantons"].members() {
            cantons[code] = try SwissCanton(code: code, node)
        }
        guard !cantons.isEmpty else { throw root["cantons"].error("lists no canton") }
        self.cantons = cantons

        var foreign: [String: ForeignWrapper] = [:]
        let wrappers = root["foreign"]["wrappers"]
        for treatment in [ForeignWrapper.taxable, .taxDeferred, .taxedAtSource] {
            for id in try wrappers[treatment.rawValue].optionalList() { foreign[try id.string()] = treatment }
        }
        foreignWrappers = foreign

        var paths = ["federal.tariff", "federal.tariff.minimumTax", "federal.deductions", "federal.lumpSumTaxation",
                     "socialSecurity", "bvg", "pillar3a", "property.mortgageInterest", "expatriates"]
        for code in cantons.keys {
            paths += ["income", "wealth", "deductions", "personalTax", "lumpSumTaxation"].map { "cantons.\(code).\($0)" }
        }
        rules = Dictionary(uniqueKeysWithValues: paths.map { ($0, set.indexingRule(at: $0)) })
    }

    /// These parameters in today's francs for `year`: every amount scaled by
    /// the factor its object's indexing rule gives (1 for amounts indexed by law).
    func scaled(for year: FixedYear) -> SwissParameters {
        func factor(_ path: String) -> Double {
            ThresholdIndexing.scale(for: year, parameterYear: self.year, rule: rules[path] ?? .plan)
        }
        var result = self
        let tariff = factor("federal.tariff")
        if tariff != 1 { result.federal.tariff = federal.tariff.scaled(by: tariff) }
        result.federal.minimumTax *= factor("federal.tariff.minimumTax")
        let deductions = factor("federal.deductions")
        result.federal.professionalExpenses = federal.professionalExpenses.scaled(by: deductions)
        result.federal.insurance.withPensionContributions *= deductions
        result.federal.insurance.withoutPensionContributions *= deductions
        result.federal.lumpSumMinimumBase *= factor("federal.lumpSumTaxation")

        let social = factor("socialSecurity")
        if social != 1 {
            result.employee.alvCap *= social
            result.employee.retireeAllowance *= social
            result.selfEmployed.fullRateFrom *= social
            result.selfEmployed.slidingScaleFrom *= social
            result.selfEmployed.minimum *= social
            result.nonEmployed = nonEmployed.scaled(by: social)
        }
        let bvg = factor("bvg")
        if bvg != 1 {
            result.bvg.entryThreshold *= bvg
            result.bvg.coordinationDeduction *= bvg
            result.bvg.upperLimit *= bvg
            result.bvg.minimumCoordinatedSalary *= bvg
        }
        let p3a = factor("pillar3a")
        result.pillar3a.maximumWithPensionFund *= p3a
        result.pillar3a.maximumWithoutPensionFund *= p3a
        result.mortgageInterestCap *= factor("property.mortgageInterest")
        result.expatriateFlatPerMonth *= factor("expatriates")
        for (code, canton) in cantons {
            result.cantons[code] = canton.scaled(
                income: factor("cantons.\(code).income"), wealth: factor("cantons.\(code).wealth"),
                deductions: factor("cantons.\(code).deductions"), personalTax: factor("cantons.\(code).personalTax"),
                lumpSum: factor("cantons.\(code).lumpSumTaxation"))
        }
        return result
    }
}

/// One canton's parameters: tariffs, deductions, multipliers, the
/// capital-benefit method, and lump-sum taxation.
struct SwissCanton: Sendable {
    /// How the canton taxes capital benefits (`capitalBenefits.method`).
    enum CapitalBenefitMethod: Sendable {
        /// The rate of the tariff on a fraction of the amount, at least a minimum (Zurich).
        case rateOfFraction(fraction: Double, minimumRate: Double)
        /// The tariff's average rate on the life annuity the capital buys,
        /// between a minimum and (from a year) a maximum (Ticino).
        case annuityRate(minimumRate: Double, maximumRate: Double, maximumFrom: Int, roundedDownTo: Double,
                         maleFactor: Double, femaleFactor: Double)
        /// A share of the ordinary tariff.
        case fractionOfTariff(share: Double)
    }

    /// Ticino's deduction for single people, phased out with income.
    struct SinglePersonDeduction: Sendable {
        var amount: Double
        var fullUpToNetIncome: Double
        var reductionPerStep: Double
        var step: Double

        /// The deduction at `netIncome`: the full amount up to the limit,
        /// less one reduction per completed step above it.
        func amount(netIncome: Double) -> Double {
            guard netIncome > fullUpToNetIncome, step > 0 else { return amount }
            let steps = ((netIncome - fullUpToNetIncome) / step).rounded(.down)
            return max(0, amount - reductionPerStep * steps)
        }
    }

    /// Ticino's wealth-tax brake (art. 49a LT).
    struct Brake: Sendable {
        var maximumShareOfIncome: Double
        var minimumYieldOnWealth: Double
    }

    var code: String
    var name: String
    var capital: String
    var income: BracketSchedule
    var maximumCategoryRate: YearSchedule?
    var wealth: BracketSchedule
    var wealthTaxFreeBelow: Double
    var brake: Brake?
    var cantonMultiplier: Double
    var communes: [String: Double]
    var personalTax: Double
    var professionalExpenses: SwissParameters.ProfessionalExpenses
    var insurance: SwissParameters.Insurance
    var singlePerson: SinglePersonDeduction?
    var capitalBenefits: CapitalBenefitMethod
    var lumpSumAvailable: Bool
    var lumpSumMinimumBase: Double
    var deemedWealthMultiple: Double

    init(code: String, _ node: ParameterNode) throws {
        self.code = code
        let description = node["description"].value?.stringValue ?? code
        name = description.split(separator: ";").first.map { String($0) } ?? code
        income = try BracketSchedule(node["income"]["single"])
        maximumCategoryRate = node["income"]["maximumCategoryRate"].exists
            ? try YearSchedule(node["income"]["maximumCategoryRate"]) : nil
        wealth = try BracketSchedule(node["wealth"]["single"])
        wealthTaxFreeBelow = try node["wealth"]["single"]["taxFreeBelow"].double(default: 0)
        let brake = node["wealth"]["brake"]
        self.brake = brake.exists
            ? Brake(maximumShareOfIncome: try brake["maximumShareOfIncome"].double(),
                    minimumYieldOnWealth: try brake["minimumYieldOnWealth"].double())
            : nil
        let multipliers = node["multipliers"]
        cantonMultiplier = try multipliers["canton"].double()
        capital = try multipliers["capital"].string()
        communes = try multipliers["communes"].members().mapValues { try $0.double() }
        guard communes[capital] != nil else { throw multipliers["capital"].error("isn't one of the communes") }
        personalTax = try node["personalTax"]["amount"].double()
        let deductions = node["deductions"]
        professionalExpenses = try SwissParameters.ProfessionalExpenses(deductions["professionalExpenses"])
        insurance = try SwissParameters.Insurance(deductions["insurancePremiums"])
        let single = deductions["singlePersonDeduction"]
        singlePerson = single.exists
            ? SinglePersonDeduction(amount: try single["amount"].double(),
                                    fullUpToNetIncome: try single["fullUpToNetIncome"].double(),
                                    reductionPerStep: try single["reductionPerStep"].double(),
                                    step: try single["step"].double())
            : nil
        let capitalNode = node["capitalBenefits"]
        switch try capitalNode["method"].string() {
        case "rateOfFraction":
            capitalBenefits = .rateOfFraction(fraction: try capitalNode["fraction"].double(),
                                              minimumRate: try capitalNode["minimumSimpleRate"].double())
        case "annuityRate":
            let table = capitalNode["conversionTable"]["factorAt65"]
            capitalBenefits = .annuityRate(
                minimumRate: try capitalNode["minimumSimpleRate"].double(),
                maximumRate: try capitalNode["maximumSimpleRate"].double(),
                maximumFrom: try capitalNode["maximumFrom"].int(default: Int.min),
                roundedDownTo: try capitalNode["annuityRoundedDownTo"].double(default: 0),
                maleFactor: try table["male"].double(), femaleFactor: try table["female"].double())
        case "fractionOfTariff":
            capitalBenefits = .fractionOfTariff(share: try capitalNode["share"].double())
        case let other:
            throw capitalNode["method"].error("names an unknown method \"\(other)\"")
        }
        let lumpSum = node["lumpSumTaxation"]
        lumpSumAvailable = try lumpSum["available"].bool(default: false)
        lumpSumMinimumBase = try lumpSum["minimumBase"].double(default: 0)
        deemedWealthMultiple = try lumpSum["deemedWealthMultipleOfBase"].double(default: 0)
    }

    /// The simple income tax schedule in `year`: every category's rate
    /// capped at the year's maximum category rate, where the canton has one.
    func incomeSchedule(in year: Int) -> BracketSchedule {
        guard let maximumCategoryRate else { return income }
        let cap = maximumCategoryRate.value(in: year)
        return BracketSchedule(income.brackets.map { .init(upTo: $0.upTo, rate: min($0.rate, cap)) })
    }

    /// The simple wealth tax on net wealth (nothing below the threshold, if any).
    func wealthSimpleTax(on netWealth: Double) -> Double {
        guard netWealth > 0, netWealth >= wealthTaxFreeBelow else { return 0 }
        return wealth.tax(on: netWealth)
    }

    /// The simple tax on a year's capital benefits, with `schedule` (the
    /// year's income schedule) and, for the annuity method, the conversion
    /// factor from capital to annuity.
    func capitalBenefitSimpleTax(on amount: Double, schedule: BracketSchedule, year: Int,
                                 conversionFactor: Double) -> Double {
        guard amount > 0 else { return 0 }
        switch capitalBenefits {
        case .rateOfFraction(let fraction, let minimumRate):
            return max(minimumRate, schedule.averageRate(at: amount * fraction)) * amount
        case .annuityRate(let minimumRate, let maximumRate, let maximumFrom, let roundedDownTo, _, _):
            let raw = amount * conversionFactor
            let annuity = roundedDownTo > 0 ? (raw / roundedDownTo).rounded(.down) * roundedDownTo : raw
            var rate = max(minimumRate, schedule.averageRate(at: annuity))
            if year >= maximumFrom { rate = min(rate, maximumRate) }
            return rate * amount
        case .fractionOfTariff(let share):
            return schedule.tax(on: amount) * share
        }
    }

    /// The capital-to-annuity factor for the table `table` (`male`,
    /// `female`, or anything else for their average); 0 when the canton
    /// doesn't use one.
    func conversionFactor(table: String) -> Double {
        guard case .annuityRate(_, _, _, _, let male, let female) = capitalBenefits else { return 0 }
        switch table {
        case "male": return male
        case "female": return female
        default: return (male + female) / 2
        }
    }

    func scaled(income: Double, wealth: Double, deductions: Double, personalTax: Double, lumpSum: Double)
        -> SwissCanton {
        var result = self
        if income != 1 { result.income = self.income.scaled(by: income) }
        if wealth != 1 {
            result.wealth = self.wealth.scaled(by: wealth)
            result.wealthTaxFreeBelow *= wealth
        }
        if deductions != 1 {
            result.professionalExpenses = professionalExpenses.scaled(by: deductions)
            result.insurance.withPensionContributions *= deductions
            result.insurance.withoutPensionContributions *= deductions
            result.singlePerson = singlePerson.map {
                SinglePersonDeduction(amount: $0.amount * deductions,
                                      fullUpToNetIncome: $0.fullUpToNetIncome * deductions,
                                      reductionPerStep: $0.reductionPerStep * deductions, step: $0.step * deductions)
            }
        }
        result.personalTax *= personalTax
        result.lumpSumMinimumBase *= lumpSum
        return result
    }
}
