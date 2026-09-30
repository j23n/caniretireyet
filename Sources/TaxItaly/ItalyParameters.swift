import TaxKit

/// One tax year's Italian parameters, read from `Resources/it/<year>.json`.
/// The code never hard-codes a rate or threshold: everything comes from here.
///
/// Amounts are nominal euros of the file's year; ``scaled(by:)`` converts
/// the ones the plan's `indexThresholds` governs into today's euros. INPS
/// amounts (maximum and minimum bases, assegno sociale, minimum pension) are
/// indexed by law every year, so they keep their value in today's euros and
/// are never scaled.
struct ItalyParameters: Sendable {
    struct Cuneo: Sendable {
        var exemptSumIncomeLimit: Double
        var exemptSum: BandRateSchedule
        var extraDetrazione: LinearTaper
        var countsExemptImpatriatiIncome: Bool
    }

    struct TrattamentoIntegrativo: Sendable {
        var amount: Double
        var incomeLimit: Double
        var detrazioneReduction: Double
    }

    struct INPS: Sendable {
        var employeeRate: Double
        var employeeCreditRate: Double
        var separataRate: Double
        var separataCreditRate: Double
        var separataMinimumBase: Double
        var maximumBase: Double
    }

    struct TFR: Sendable {
        var accrualRate: Double
        var revaluation: WrapperRevaluation
        var revaluationTaxRate: Double
        var payoutFallbackRate: Double
    }

    struct Forfettario: Sendable {
        var rate: Double
        var startupRate: Double
        var startupYears: Int
        var revenueLimit: Double
        var immediateExitLimit: Double
        var employmentIncomeLimit: YearSchedule
    }

    struct Impatriati2024: Sendable {
        var exemptShare: Double
        var minorChildExemptShare: Double
        var incomeCap: Double
        var years: Int
        var firstMoveYear: Int
        var minimumStayYears: Int
        var forfettarioOnArrivalRulesOut: Bool
    }

    struct Impatriati2015: Sendable {
        var exemptShare: Double
        var southExemptShare: Double
        var years: Int
        var lastMoveYear: Int
        var reformFromMoveYear: Int
        var preReformExemptShare: Double
        var minimumStayYears: Int
        var extensionYears: Int
        var extensionExemptShare: Double
        var extensionThreeMinorChildrenExemptShare: Double
        var extensionFromMoveYear: Int
        var forfettarioOnArrivalRulesOut: Bool
    }

    struct PensionFund: Sendable {
        var deductionLimit: Double
        var growthTaxRate: Double
        var minimumMembershipYears: Int
        var payoutRate: Double
        var payoutReductionPerYear: Double
        var payoutReductionAfterYears: Int
        var payoutFloor: Double
        var lumpSumMaxShare: Double
        var lumpSumAnnuityShare: Double
        var smallAnnuityAssegnoSocialeShare: Double
        var ritaYearsBeforeOldAge: Int
        var ritaContributionYears: Double
        var ritaExtendedYearsBeforeOldAge: Int
        var ritaExtendedYearsWithoutWork: Int

        /// The payout tax rate after `years` of membership: the base rate less
        /// a reduction per year beyond the threshold, down to the floor.
        func payoutTaxRate(membershipYears years: Int) -> Double {
            let reduction = Double(max(0, years - payoutReductionAfterYears)) * payoutReductionPerYear
            return max(payoutFloor, payoutRate - reduction)
        }
    }

    struct Investments: Sendable {
        var standardRate: Double
        var governmentBondRate: Double
        var cryptoRate: Double
        var stablecoinRate: Double
        var goldRate: Double
        var goldUndocumentedGainShare: Double
        var realEstateRate: Double

        /// The rate on realised gains in `category`. Cash has no capital
        /// gains (its interest is capital income).
        func gainRate(for category: TaxCategory) -> Double {
            category == .cash ? 0 : rate(for: category)
        }

        /// The rate on gains and income in `category`.
        func rate(for category: TaxCategory) -> Double {
            switch category {
            case .governmentBond: governmentBondRate
            case .crypto: cryptoRate
            case .stablecoin: stablecoinRate
            case .physicalGold: goldRate
            case .realEstate: realEstateRate
            default: standardRate
            }
        }
    }

    struct WealthTax: Sendable {
        var financialRate: Double
        var blacklistRate: Double
        var cryptoRate: Double
        var currentAccountAmount: Double
        var currentAccountThreshold: Double
        var propertyAbroadRate: Double
        var propertyAbroadMinimum: Double
        var blacklist: Set<String>
    }

    var year: Int
    var irpef: BracketSchedule
    var employmentDetrazione: LinearTaper
    var pensionDetrazione: LinearTaper
    var selfEmploymentDetrazione: LinearTaper
    var cuneo: Cuneo
    var trattamentoIntegrativo: TrattamentoIntegrativo
    var addizionaliOnlyWhenIrpefIsDue: Bool
    var inps: INPS
    var tfr: TFR
    var forfettario: Forfettario
    var impatriati2024: Impatriati2024
    var impatriati2015: Impatriati2015
    var pensionFund: PensionFund
    var investments: Investments
    var wealthTax: WealthTax
    var inheritance: [String: FlatRate]
    var defaultRelationship: String
    var pension: INPSPensionParameters

    init(_ set: ParameterSet) throws {
        let root = ParameterNode(set)
        year = set.year
        irpef = try BracketSchedule(root["irpef"])
        employmentDetrazione = try LinearTaper(root["detrazioni"]["employment"])
        pensionDetrazione = try LinearTaper(root["detrazioni"]["pension"])
        selfEmploymentDetrazione = try LinearTaper(root["detrazioni"]["selfEmployment"])

        let cuneo = root["cuneo"]
        self.cuneo = Cuneo(
            exemptSumIncomeLimit: try cuneo["exemptSum"]["incomeLimit"].double(),
            exemptSum: try BandRateSchedule(cuneo["exemptSum"]),
            extraDetrazione: try LinearTaper(cuneo["extraDetrazione"]),
            countsExemptImpatriatiIncome: try cuneo["countsExemptImpatriatiIncome"]["value"].bool())

        let ti = root["trattamentoIntegrativo"]
        trattamentoIntegrativo = TrattamentoIntegrativo(
            amount: try ti["amount"].double(), incomeLimit: try ti["incomeLimit"].double(),
            detrazioneReduction: try ti["detrazioneReduction"].double())
        addizionaliOnlyWhenIrpefIsDue = try root["addizionali"]["onlyWhenIrpefIsDue"].bool()

        let inps = root["inps"]
        self.inps = INPS(
            employeeRate: try inps["employee"]["rate"].double(),
            employeeCreditRate: try inps["employee"]["pensionCreditRate"].double(),
            separataRate: try inps["gestioneSeparata"]["rate"].double(),
            separataCreditRate: try inps["gestioneSeparata"]["pensionCreditRate"].double(),
            separataMinimumBase: try inps["gestioneSeparata"]["minimumBase"].double(),
            maximumBase: try inps["maximumBase"]["value"].double())

        let tfr = root["tfr"]
        self.tfr = TFR(
            accrualRate: try tfr["accrualRate"].double(),
            revaluation: WrapperRevaluation(fixedRate: try tfr["revaluation"]["fixedRate"].double(),
                                            inflationShare: try tfr["revaluation"]["inflationShare"].double()),
            revaluationTaxRate: try tfr["revaluationTaxRate"].double(),
            payoutFallbackRate: try tfr["payoutFallbackRate"].double())

        let forfettario = root["forfettario"]
        self.forfettario = Forfettario(
            rate: try forfettario["rate"].double(), startupRate: try forfettario["startupRate"].double(),
            startupYears: try forfettario["startupYears"].int(), revenueLimit: try forfettario["revenueLimit"].double(),
            immediateExitLimit: try forfettario["immediateExitLimit"].double(),
            employmentIncomeLimit: try YearSchedule(forfettario["employmentIncomeLimit"]))

        let new = root["impatriati2024"]
        impatriati2024 = Impatriati2024(
            exemptShare: try new["exemptShare"].double(),
            minorChildExemptShare: try new["minorChildExemptShare"].double(),
            incomeCap: try new["incomeCap"].double(), years: try new["years"].int(),
            firstMoveYear: try new["firstMoveYear"].int(), minimumStayYears: try new["minimumStayYears"].int(),
            forfettarioOnArrivalRulesOut: try new["forfettarioOnArrival"]["rulesOutImpatriati"].bool())

        let old = root["impatriati2015"]
        impatriati2015 = Impatriati2015(
            exemptShare: try old["exemptShare"].double(), southExemptShare: try old["southExemptShare"].double(),
            years: try old["years"].int(), lastMoveYear: try old["lastMoveYear"].int(),
            reformFromMoveYear: try old["reformFromMoveYear"].int(),
            preReformExemptShare: try old["preReformExemptShare"].double(),
            minimumStayYears: try old["minimumStayYears"].int(),
            extensionYears: try old["extension"]["years"].int(),
            extensionExemptShare: try old["extension"]["exemptShare"].double(),
            extensionThreeMinorChildrenExemptShare: try old["extension"]["threeMinorChildrenExemptShare"].double(),
            extensionFromMoveYear: try old["extension"]["fromMoveYear"].int(),
            forfettarioOnArrivalRulesOut: try old["forfettarioOnArrival"]["rulesOutImpatriati"].bool())

        let fund = root["pensionFund"]
        pensionFund = PensionFund(
            deductionLimit: try fund["deductionLimit"].double(), growthTaxRate: try fund["growthTaxRate"].double(),
            minimumMembershipYears: try fund["minimumMembershipYears"].int(),
            payoutRate: try fund["payoutTax"]["rate"].double(),
            payoutReductionPerYear: try fund["payoutTax"]["reductionPerYear"].double(),
            payoutReductionAfterYears: try fund["payoutTax"]["reductionAfterYears"].int(),
            payoutFloor: try fund["payoutTax"]["floor"].double(),
            lumpSumMaxShare: try fund["lumpSum"]["maxShare"].double(),
            lumpSumAnnuityShare: try fund["lumpSum"]["annuityShare"].double(),
            smallAnnuityAssegnoSocialeShare: try fund["lumpSum"]["smallAnnuityAssegnoSocialeShare"].double(),
            ritaYearsBeforeOldAge: try fund["rita"]["yearsBeforeOldAge"].int(),
            ritaContributionYears: try fund["rita"]["contributionYears"].double(),
            ritaExtendedYearsBeforeOldAge: try fund["rita"]["extendedYearsBeforeOldAge"].int(),
            ritaExtendedYearsWithoutWork: try fund["rita"]["extendedYearsWithoutWork"].int())

        let investments = root["investments"]
        self.investments = Investments(
            standardRate: try investments["standard"]["rate"].double(),
            governmentBondRate: try investments["governmentBonds"]["rate"].double(),
            cryptoRate: try investments["crypto"]["rate"].double(),
            stablecoinRate: try investments["crypto"]["stablecoinRate"].double(),
            goldRate: try investments["physicalGold"]["rate"].double(),
            goldUndocumentedGainShare: try investments["physicalGold"]["undocumentedCostGainShare"].double(),
            realEstateRate: try investments["realEstate"]["rate"].double())

        let wealth = root["wealthTax"]
        wealthTax = WealthTax(
            financialRate: try wealth["financial"]["rate"].double(),
            blacklistRate: try wealth["financial"]["blacklistRate"].double(),
            cryptoRate: try wealth["crypto"]["rate"].double(),
            currentAccountAmount: try wealth["currentAccount"]["amount"].double(),
            currentAccountThreshold: try wealth["currentAccount"]["averageBalanceAbove"].double(),
            propertyAbroadRate: try wealth["propertyAbroad"]["rate"].double(),
            propertyAbroadMinimum: try wealth["propertyAbroad"]["minimumDue"].double(),
            blacklist: Set(try wealth["blacklist"]["countries"].strings().map { $0.uppercased() }))

        inheritance = try root["inheritance"]["relationships"].members().mapValues(FlatRate.init)
        defaultRelationship = try root["inheritance"]["defaultRelationship"].string()
        guard inheritance[defaultRelationship] != nil else {
            throw root["inheritance"]["defaultRelationship"].error("names no relationship")
        }
        pension = try INPSPensionParameters(root["inpsPension"])
    }

    /// These parameters with every amount the plan's `indexThresholds`
    /// governs multiplied by `factor` (see `ThresholdIndexing`).
    func scaled(by factor: Double) -> ItalyParameters {
        guard factor != 1 else { return self }
        var result = self
        result.irpef = irpef.scaled(by: factor)
        result.employmentDetrazione = employmentDetrazione.scaled(by: factor)
        result.pensionDetrazione = pensionDetrazione.scaled(by: factor)
        result.selfEmploymentDetrazione = selfEmploymentDetrazione.scaled(by: factor)
        result.cuneo.exemptSumIncomeLimit *= factor
        result.cuneo.exemptSum = cuneo.exemptSum.scaled(by: factor)
        result.cuneo.extraDetrazione = cuneo.extraDetrazione.scaled(by: factor)
        result.trattamentoIntegrativo.amount *= factor
        result.trattamentoIntegrativo.incomeLimit *= factor
        result.trattamentoIntegrativo.detrazioneReduction *= factor
        result.forfettario.revenueLimit *= factor
        result.forfettario.immediateExitLimit *= factor
        result.forfettario.employmentIncomeLimit.initial *= factor
        result.forfettario.employmentIncomeLimit.changes = forfettario.employmentIncomeLimit.changes.map {
            YearSchedule.Change(from: $0.from, value: $0.value * factor)
        }
        result.impatriati2024.incomeCap *= factor
        result.pensionFund.deductionLimit *= factor
        result.wealthTax.currentAccountAmount *= factor
        result.wealthTax.currentAccountThreshold *= factor
        result.wealthTax.propertyAbroadMinimum *= factor
        result.inheritance = inheritance.mapValues { $0.scaled(by: factor) }
        return result
    }
}

/// The INPS pension rules for one tax year: conversion coefficients, the
/// claim routes, age steps, and the reference amounts.
struct INPSPensionParameters: Sendable {
    struct Route: Sendable {
        var age: Int
        var contributionYears: Double
        var assegnoSocialeMultiple: Double
        var windowMonths: Int
    }

    /// Coefficient by whole age.
    var coefficients: [Int: Double]
    /// The last year the coefficient table applies to.
    var coefficientsLastYear: Int
    var instalments: Double
    var anticipata: Route
    var motherMultiples: [Double]
    var anticipataCapMinimumPensionMultiple: Double
    var vecchiaia: Route
    var contributiva: Route
    var ageIncreaseMonths: YearSchedule
    var anticipataContributionIncreaseMonths: YearSchedule
    /// Monthly amounts.
    var assegnoSociale: Double
    var minimumPension: Double
    /// The share of inflation passed on, by tier in multiples of the minimum pension.
    var indexation: BracketSchedule

    init(_ node: ParameterNode) throws {
        var coefficients: [Int: Double] = [:]
        for (age, value) in try node["coefficients"]["ages"].members() {
            guard let whole = Int(age) else { throw value.error("is not under a whole age") }
            coefficients[whole] = try value.double()
        }
        guard !coefficients.isEmpty else { throw node["coefficients"]["ages"].error("is empty") }
        self.coefficients = coefficients
        coefficientsLastYear = try node["coefficients"]["lastYear"].int()
        instalments = try node["instalments"]["value"].double()
        func route(_ name: String) throws -> Route {
            let route = node["routes"][name]
            return Route(age: try route["age"].int(), contributionYears: try route["contributionYears"].double(),
                         assegnoSocialeMultiple: try route["assegnoSocialeMultiple"].double(default: 0),
                         windowMonths: try route["windowMonths"].int(default: 0))
        }
        anticipata = try route("anticipata")
        motherMultiples = try node["routes"]["anticipata"]["motherMultiples"].doubles()
        anticipataCapMinimumPensionMultiple = try node["routes"]["anticipata"]["capMinimumPensionMultiple"].double()
        vecchiaia = try route("vecchiaia")
        contributiva = try route("contributiva")
        ageIncreaseMonths = try YearSchedule(node["ageIncreaseMonths"])
        anticipataContributionIncreaseMonths = try YearSchedule(node["anticipataContributionIncreaseMonths"])
        assegnoSociale = try node["assegnoSociale"]["monthly"].double()
        minimumPension = try node["minimumPension"]["monthly"].double()
        indexation = try BracketSchedule(node["indexation"])
    }
}

extension INPSPensionParameters {
    /// The conversion coefficient for an age in months: the table's value for
    /// whole ages, plus a twelfth of the difference to the next age per extra
    /// month; the youngest age's below the table and the oldest's above it.
    func coefficient(ageInMonths months: Int) -> Double {
        let ages = coefficients.keys.sorted()
        guard let youngest = ages.first, let oldest = ages.last else { return 0 }
        let whole = months / 12
        if whole < youngest { return coefficients[youngest] ?? 0 }
        if whole >= oldest { return coefficients[oldest] ?? 0 }
        let lower = coefficients[whole] ?? 0
        let upper = coefficients[whole + 1] ?? lower
        return lower + (upper - lower) * Double(months - whole * 12) / 12
    }
}
