import TaxKit

/// Runs the market-independent stages of one Swiss tax year (docs/tax/CH.md,
/// "How the module is built"), in CHF:
///
/// 1. work income by regime; 2. overlays (expatriate deductions, lump-sum
/// taxation); 3. social contributions, AHV and BVG credits; 4. net income;
/// 5. deductions; 6. federal, cantonal, communal and church income tax and
/// the personal tax; 7. capital benefits known in advance (pension lump
/// sums); 10. the state carried into next year.
///
/// Investment income, wealth tax, AHV contributions without work and
/// wrapper payouts depend on the markets and run in
/// ``SwissPreparedYear/assess(_:)``.
struct SwissYearCalculator {
    let system: SwissTaxSystem
    let year: FixedYear
    let state: TaxState
    /// The year's parameters, in today's francs.
    let p: SwissParameters
    /// The residence options, with defaults.
    let options: OptionValues
    let tariffs: SwissTariffs
    let labels: SwissLabels

    var work: [SwissWorkResult] = []
    var issues: [TaxIssue] = []

    /// An amount in the plan's currency, in CHF.
    func chf(_ amount: Double) -> Double { year.inSystemCurrency(amount) }

    /// An amount in CHF, in the plan's currency.
    func inPlanCurrency(_ amount: Double) -> Double { year.inPlanCurrency(amount) }

    /// Runs the stages and returns the prepared year.
    static func prepare(system: SwissTaxSystem, year: FixedYear, state: TaxState, parameters: ParameterSet)
        -> SwissPreparedYear {
        let unscaled: SwissParameters
        do {
            unscaled = try system.parsed.parameters(for: parameters)
        } catch {
            let issue = TaxIssue.error("ch.parameters", "The Swiss tax parameters for \(parameters.year) can't be used: "
                                       + "\(error)", year: year.year)
            return SwissPreparedYear(failed: TaxAssessment(issues: [issue], nextState: state))
        }
        let p = unscaled.scaled(for: year)
        let options = year.systemOptions.withDefaults(from: system.options)
        let place: SwissPlace
        switch SwissPlace.resolve(options, parameters: p) {
        case .success(let resolved):
            place = resolved
        case .failure(let problem):
            let issue = problem.issue(supported: Array(p.cantons.values), year: year.year)
            return SwissPreparedYear(failed: TaxAssessment(issues: [issue], nextState: state))
        }
        var calculator = SwissYearCalculator(
            system: system, year: year, state: state, p: p, options: options,
            tariffs: SwissTariffs(p: p, place: place, year: year.year), labels: SwissLabels(place: place))
        calculator.computeWork()
        return calculator.preparedYear()
    }

    private var place: SwissPlace { tariffs.place }

    /// Stages 2 and 4–7, and the assessment of the year without market activity.
    private mutating func preparedYear() -> SwissPreparedYear {
        let thisYear = year.year

        // Stage 4: pensions. Annuities taxed here are income; those a treaty
        // leaves to the paying country count for the rate. Lump sums are
        // capital benefits.
        var pensionIncome = 0.0
        var exemptForRate = 0.0
        var annuities = 0.0
        var capitalBenefits: [SwissCapitalBenefit] = []
        var bvgLumpSum = false
        for pension in year.pensions where pension.amount > 0 {
            let amount = chf(pension.amount)
            if pension.form == .lumpSum {
                if pension.taxedIn == .residence {
                    capitalBenefits.append(SwissCapitalBenefit(subject: pension.id, amount: amount))
                }
                if pension.scheme == BVGPensionScheme.schemeID { bvgLumpSum = true }
            } else {
                annuities += amount
                if pension.taxedIn == .residence { pensionIncome += amount } else { exemptForRate += amount }
            }
        }

        // Stage 5: pillar 3a and BVG buy-ins.
        var accruals: [Accrual] = []
        let inPensionFund = work.contains { $0.inPensionFund }
        let earned = work.reduce(0) { $0 + $1.earnedIncomeFor3a }
        var pillar3aPaid = 0.0
        var buyIns = 0.0
        for contribution in year.wrapperContributions where contribution.amount > 0 {
            switch contribution.wrapper {
            case SwissWrapper.pillar3a:
                pillar3aPaid += chf(contribution.amount)
            case BVGPensionScheme.schemeID:
                buyIns += chf(contribution.amount)
                accruals.append(Accrual(target: .pensionScheme(BVGPensionScheme.schemeID), amount: contribution.amount,
                                        source: contribution.source))
            default:
                break
            }
        }
        let pillar3aDeduction = pillar3aRelief(paid: pillar3aPaid, earned: earned, inPensionFund: inPensionFund)
        checkBuyIns(buyIns, inPensionFund: inPensionFund)
        var lockedBuyIns = buyIns
        for back in 1...max(1, p.bvg.lockYears) { lockedBuyIns += state[SwissStateKey.buyIn(thisYear - back)] ?? 0 }
        var reversal = 0.0
        if bvgLumpSum && lockedBuyIns > 0 {
            reversal = lockedBuyIns
            issues.append(buyInLockIssue(lockedBuyIns))
        }

        // Stage 2: overlays.
        let lumpSum = lumpSumTaxation()
        let expatriate = expatriateDeduction()

        // A home: its value is wealth; until 2028 the imputed rent is income
        // and mortgage interest a deduction.
        let home = chf(options.double("homeTaxValue") ?? 0) - chf(options.double("mortgage") ?? 0)
        let propertyYear = thisYear <= p.imputedRentLastYear
        let imputedRent = propertyYear ? chf(max(0, options.double("imputedRentalValue") ?? 0)) : 0
        let mortgageInterest = propertyYear ? chf(max(0, options.double("mortgageInterest") ?? 0)) : 0

        // Stages 4–5: net income and deductions.
        let netSalary = work.reduce(0) { $0 + $1.netSalary }
        let employedShare = min(1, work.filter(\.isEmployee).reduce(0) { $0 + $1.fractionOfYear })
        let pensionContributions = inPensionFund || pillar3aDeduction > 0 || buyIns > 0
        let common = pillar3aDeduction + buyIns + expatriate + chf(max(0, options.double("otherDeductions") ?? 0))
        let canton = place.canton
        let base = SwissIncomeBase(
            income: netSalary + work.reduce(0) { $0 + $1.selfEmployedIncome } + pensionIncome + imputedRent + reversal,
            federalDeductions: p.federal.professionalExpenses.amount(netSalary: netSalary, employedShare: employedShare)
                + p.federal.insurance.amount(withPensionContributions: pensionContributions) + common,
            cantonalDeductions: canton.professionalExpenses.amount(netSalary: netSalary, employedShare: employedShare)
                + canton.insurance.amount(withPensionContributions: pensionContributions) + common,
            mortgageInterest: mortgageInterest, imputedRent: imputedRent, exemptForRate: exemptForRate)

        // Stages 6–7.
        let incomeTaxes = lumpSum == nil ? tariffs.incomeTaxes(base) : nil
        var builder = SwissLineBuilder(tariffs: tariffs, labels: labels)
        if let lumpSum {
            builder.addIncome(federal: lumpSum.federal, federalBase: lumpSum.base, simple: lumpSum.simple,
                              cantonalBase: lumpSum.base)
        } else if let incomeTaxes {
            builder.addIncome(federal: incomeTaxes.federal, federalBase: incomeTaxes.federalTaxable,
                              simple: incomeTaxes.simple, cantonalBase: incomeTaxes.cantonalTaxable)
        }
        builder.addPersonalTax(canton.personalTax)
        builder.addCapitalBenefits(capitalBenefits)
        if let lumpSum {
            builder.addWealth(simple: lumpSum.wealthSimple, netWealth: lumpSum.deemedWealth, fraction: 1)
        }

        // Stage 3: pension credits. A year resident in Switzerland between
        // 21 and the reference age is a full AHV year: from work, or as a
        // year without work (credited here with the minimum contribution's
        // income; the contribution itself depends on wealth, in assess).
        for result in work {
            if result.ahvCredit > 0 {
                accruals.append(Accrual(target: .pensionScheme(AHVPensionScheme.schemeID),
                                        amount: inPlanCurrency(result.ahvCredit), contributionMonths: result.ahvMonths,
                                        source: result.phaseID))
            }
            if result.bvgCredit > 0 {
                accruals.append(Accrual(target: .pensionScheme(BVGPensionScheme.schemeID),
                                        amount: inPlanCurrency(result.bvgCredit), source: result.phaseID))
            }
        }
        let referenceAge = p.ahv.referenceAge
        if year.age >= p.nonEmployed.fromAge && year.age < referenceAge {
            let months = 12 - min(12, work.reduce(0) { $0 + $1.ahvMonths })
            if months > 0 {
                let income = p.nonEmployed.creditedIncome(forContribution: p.nonEmployed.minimum) * Double(months) / 12
                accruals.append(Accrual(target: .pensionScheme(AHVPensionScheme.schemeID),
                                        amount: inPlanCurrency(income), contributionMonths: months))
            }
        }
        // Due unless working full time (here: work for most of the year).
        var nonEmployedShare = 0.0
        let workMonths = work.reduce(0) { $0 + $1.ahvMonths }
        if year.age >= p.nonEmployed.fromAge && workMonths < p.nonEmployed.fullTimeMonths {
            if year.age < referenceAge {
                nonEmployedShare = 1
            } else if year.age == referenceAge, let birth = year.birthDate {
                nonEmployedShare = Double(min(12, max(0, birth.month))) / 12
            }
        }

        // Stage 10.
        var next = state
        for key in state.values.keys where SwissStateKey.isBuyIn(key) {
            if let buyInYear = SwissStateKey.buyInYear(key), buyInYear <= thisYear - p.bvg.lockYears {
                next[key] = nil
            }
        }
        if buyIns > 0 { next[SwissStateKey.buyIn(thisYear)] = buyIns }

        let rate = year.currencyRate
        let contributions = work.flatMap(\.contributions).map {
            TaxLine(id: $0.id, label: $0.label, amount: inPlanCurrency($0.amount), base: $0.base.map(inPlanCurrency),
                    subject: $0.subject)
        }
        let fixed = TaxAssessment(lines: builder.converted(rate: rate), contributions: contributions,
                                  accruals: accruals, issues: issues, nextState: next)
        let context = SwissPreparedYear.Context(
            year: thisYear, rate: rate, tariffs: tariffs, labels: labels, base: lumpSum == nil ? base : nil,
            incomeTaxes: incomeTaxes, lumpSum: lumpSum, capitalBenefits: capitalBenefits,
            lockedBuyIns: lockedBuyIns, reversedInPrepare: reversal > 0,
            workAHV: work.reduce(0) { $0 + $1.ahvOnEarnings }, annuities: annuities, home: home,
            nonEmployedShare: nonEmployedShare,
            adminRate: max(0, options.double("nonEmployedAdminRate") ?? p.nonEmployed.adminCostMaximumRate),
            personalTax: canton.personalTax, fixedContributions: contributions)
        return SwissPreparedYear(fixed: fixed, context: context)
    }

    /// The 3a deduction: what was paid, up to the year's maximum (with a
    /// pension fund, or 20% of net earned income without one), and only with
    /// earned income.
    private mutating func pillar3aRelief(paid: Double, earned: Double, inPensionFund: Bool) -> Double {
        guard paid > 0 else { return 0 }
        guard earned > 0 else {
            issues.append(.warning(
                "ch.pillar3a.noEarnedIncome",
                "Pillar 3a contributions need earned income in Switzerland; the \(francs(paid)) paid in \(year.year) "
                    + "isn't deductible (and a 3a account wouldn't take it).", year: year.year))
            return 0
        }
        let limit = inPensionFund
            ? p.pillar3a.maximumWithPensionFund
            : min(p.pillar3a.maximumWithoutPensionFund, p.pillar3a.shareWithoutPensionFund * earned)
        if paid > limit + 0.5 {
            let rule = inPensionFund ? "with a pension fund" : "without a pension fund (20% of net earned income)"
            issues.append(.warning(
                "ch.pillar3a.limit",
                "Pillar 3a contributions of \(francs(paid)) in \(year.year) are above the maximum of \(francs(limit)) "
                    + "\(rule); only the maximum is deductible.", year: year.year))
        }
        return min(paid, limit)
    }

    /// Buy-ins need a pension fund, and in the first years after arriving
    /// from abroad are limited to a share of the insured salary.
    private mutating func checkBuyIns(_ amount: Double, inPensionFund: Bool) {
        guard amount > 0 else { return }
        if !inPensionFund {
            issues.append(.warning(
                "ch.bvg.buyInNotInsured",
                "A BVG buy-in in \(year.year) needs membership of a pension fund, which this year's work doesn't give; "
                    + "it's deducted and credited anyway.", year: year.year))
        }
        let timeline = year.residence.sorted { $0.from < $1.from }
        if let index = timeline.lastIndex(where: { $0.from <= year.year && $0.system == system.id }), index > 0,
           timeline[index - 1].system != system.id, year.year < timeline[index].from + p.bvg.arrivalYears {
            let insured = work.reduce(0) { $0 + $1.insuredSalary }
            let limit = p.bvg.arrivalShareOfInsuredSalary * insured
            if amount > limit + 0.5 {
                issues.append(.warning(
                    "ch.bvg.buyInArrival",
                    "In the first \(p.bvg.arrivalYears) years after arriving from abroad, a BVG buy-in is limited to "
                        + "\(percent(p.bvg.arrivalShareOfInsuredSalary)) of the insured salary (\(francs(limit)) in "
                        + "\(year.year)), unless you were in a Swiss pension fund before.", year: year.year))
            }
        }
    }

    private func buyInLockIssue(_ amount: Double) -> TaxIssue {
        .warning("ch.bvg.buyInLock",
                 "A lump sum from the 2nd pillar in \(year.year) comes within \(p.bvg.lockYears) years of BVG buy-ins "
                     + "(\(francs(amount))): their deduction is reversed, and the fund may refuse the lump sum.",
                 year: year.year, regime: BVGPensionScheme.schemeID)
    }

    /// Lump-sum taxation, when the overlay covers the year and can apply.
    private mutating func lumpSumTaxation() -> SwissLumpSumYear? {
        guard let overlay = year.overlays.first(where: { $0.regime == SwissRegime.lumpSum }),
              let first = overlay.options.int("firstYear"), year.year >= first else { return nil }
        let canton = place.canton
        guard canton.lumpSumAvailable else {
            issues.append(.warning("ch.lumpSum.canton",
                                   "\(canton.name) doesn't offer lump-sum taxation; \(year.year) is taxed ordinarily.",
                                   year: year.year, regime: SwissRegime.lumpSum))
            return nil
        }
        guard work.isEmpty else {
            issues.append(.warning("ch.lumpSum.earnedIncome",
                                   "Lump-sum taxation excludes work in Switzerland; \(year.year) is taxed ordinarily.",
                                   year: year.year, regime: SwissRegime.lumpSum))
            return nil
        }
        let rent = chf(max(0, overlay.options.double("annualRent") ?? 0))
        let living = chf(max(0, overlay.options.double("livingExpenses") ?? 0))
        let base = max(p.federal.lumpSumMinimumBase, canton.lumpSumMinimumBase, p.federal.lumpSumRentMultiple * rent,
                       living)
        let deemed = canton.deemedWealthMultiple * base
        return SwissLumpSumYear(
            base: base, federal: p.federal.incomeTax(on: base, rateBase: base),
            simple: tariffs.simpleIncomeTax(on: base, rateBase: base), deemedWealth: deemed,
            wealthSimple: canton.wealthSimpleTax(on: deemed))
    }

    /// The expatriate deduction for employees, for the overlay's years.
    private func expatriateDeduction() -> Double {
        guard let overlay = year.overlays.first(where: { $0.regime == SwissRegime.expatriate }),
              let start = overlay.options.int("assignmentStart"),
              year.year >= start, year.year < start + p.expatriateYears else { return 0 }
        let employed = min(1, work.filter(\.isEmployee).reduce(0) { $0 + $1.fractionOfYear })
        guard employed > 0 else { return 0 }
        if overlay.options.string("deduction") == "actual" {
            return chf(max(0, overlay.options.double("actualAmount") ?? 0))
        }
        return p.expatriateFlatPerMonth * 12 * employed
    }
}

/// Lump-sum taxation in one year: the base and the taxes on it. In CHF.
struct SwissLumpSumYear: Hashable, Sendable {
    var base: Double
    var federal: Double
    var simple: Double
    var deemedWealth: Double
    var wealthSimple: Double
}
