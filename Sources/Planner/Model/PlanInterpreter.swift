import Foundation
import Model

/// Turns a plan and the library into a ``PlanModel``, checking every input.
/// Errors stop a run; warnings travel with the results.
enum PlanInterpreter {
    /// The model, or `nil` when the plan has errors, and every issue found.
    static func interpret(plan: PlanDocument, library: Library, options: PlannerOptions)
        -> (PlanModel?, [PlanIssue]) {
        var issues: [PlanIssue] = []
        func error(_ code: String, _ message: String, _ section: PlanSection, index: Int? = nil,
                   option: String? = nil, account: AccountID? = nil) {
            issues.append(.error(code, message, section: section, index: index, option: option, account: account))
        }
        func warning(_ code: String, _ message: String, _ section: PlanSection, index: Int? = nil,
                     option: String? = nil) {
            issues.append(.warning(code, message, section: section, index: index, option: option))
        }

        // The person and the start.
        guard let birthDate = library.settings.person?.birthDate else {
            error("planner.noBirthDate", "Add your birth date (Settings): the plan needs your age.", .person)
            return (nil, issues)
        }
        let today = options.today ?? .today()
        let startDate: CalendarDate
        switch plan.portfolio.effectiveStart {
        case .date(let date):
            startDate = date
        case .latestCheckIn:
            if let latest = library.latestCheckInDate {
                startDate = latest
            } else {
                startDate = today
                warning("planner.noCheckIn", "There is no check-in yet, so the plan starts today with nothing saved.",
                        .portfolio)
            }
        }
        let currentAge = birthDate.wholeYears(to: startDate)
        let endAge = plan.effectiveEndAge
        if endAge > 120 {
            error("planner.endAge", "The plan's end age is \(endAge); it can be at most 120.", .retirement,
                  option: "endAge")
        } else if endAge <= currentAge {
            error("planner.endAge", "The plan's end age (\(endAge)) has to be above your age (\(currentAge)).",
                  .retirement, option: "endAge")
        }
        var planAge: Int?
        if case .age(let age) = plan.retirement.age {
            if age > endAge {
                error("planner.retirementAge", "The retirement age (\(age)) is after the plan's end age (\(endAge)).",
                      .retirement, option: "age")
            }
            planAge = max(age, currentAge)
        }

        // The years.
        let inflation = plan.assumptions.effectiveInflation.doubleValue
        if !(inflation >= -0.5 && inflation <= 0.5) {
            error("planner.inflation", "Inflation is \(percent(inflation)) a year; it has to be between −50% and 50%.",
                  .assumptions, option: "inflation")
        }
        var frames: [YearFrame] = []
        if endAge > currentAge, endAge <= 120 {
            for year in startDate.year...(birthDate.year + endAge) {
                let first = year == startDate.year ? startDate.adding(days: 1) : .firstDay(ofYear: year)
                let last = CalendarDate.lastDay(ofYear: year)
                guard first <= last else { continue }
                let days = CalendarDate.inclusiveDays(from: .firstDay(ofYear: year), to: last)
                let fraction = Double(CalendarDate.inclusiveDays(from: first, to: last)) / Double(days)
                frames.append(YearFrame(index: frames.count, year: year, age: year - birthDate.year,
                                        daysInYear: days, simulatedFrom: first, fraction: fraction,
                                        inflationStep: pow(1 + inflation, fraction)))
            }
        }

        // Taxes.
        var investmentRate = 0.0
        if let rate = plan.tax.investmentRate?.doubleValue {
            if rate >= 0, rate <= 0.9 {
                investmentRate = rate
            } else {
                error("planner.investmentRate", "The tax rate on investments has to be between 0% and 90%.", .tax,
                      option: "investmentRate")
            }
        } else {
            error("planner.investmentRate",
                  "Set the tax rate on investment income and gains: the plan taxes sales and income from your "
                      + "investments with it (26% in Italy, for example; 0% if they aren't taxed).",
                  .tax, option: "investmentRate")
        }
        let wealthRate = plan.tax.effectiveWealthRate.doubleValue
        if !(wealthRate >= 0 && wealthRate <= 0.1) {
            error("planner.wealthRate", "The wealth tax rate has to be between 0% and 10%.", .tax, option: "wealthRate")
        }
        let wealthAllowance = plan.tax.effectiveWealthAllowance.doubleValue
        if wealthAllowance < 0 {
            error("planner.wealthAllowance", "The wealth left untaxed can't be negative.", .tax,
                  option: "wealthAllowance")
        }

        // Work.
        var work: [WorkSpec] = []
        for (index, phase) in plan.work.enumerated() {
            let label = phase.name ?? (plan.work.count == 1 ? "Work" : "Work \(index + 1)")
            guard let net = phase.netIncome?.doubleValue else {
                error("planner.noNetIncome",
                      "\(label): enter the income after tax for this phase (netIncome).", .work, index: index,
                      option: "netIncome")
                continue
            }
            if net < 0 {
                error("planner.negativeIncome", "\(label): the income can't be negative.", .work, index: index,
                      option: "netIncome")
            }
            let until = phase.until.date
            if let until, until < phase.from {
                error("planner.workDates", "\(label) ends before it starts.", .work, index: index, option: "until")
            }
            work.append(WorkSpec(index: index, id: "work-\(index)", label: label, from: phase.from, until: until,
                                 net: net, realGrowth: phase.realGrowth?.doubleValue ?? 0,
                                 baseYear: max(phase.from.year, startDate.year)))
        }

        // Spending.
        let working = plan.spending.working.doubleValue
        let retired = plan.spending.retired.doubleValue
        if working < 0 || retired < 0 {
            error("planner.negativeSpending", "Spending can't be negative.", .spending)
        }
        var spending = SpendingSpec(working: working, retired: retired,
                                    phases: plan.spending.phases.sorted { $0.fromAge < $1.fromAge }
                                        .map { SpendingPhaseSpec(fromAge: $0.fromAge, factor: max(0, $0.factor.doubleValue)) })
        if let rule = plan.spending.flexibleRule {
            let flexible = FlexibleSpendingSpec(rule)
            if flexible.cut > 0, flexible.cut <= 1, flexible.floor >= 0, flexible.floor <= 1, flexible.upper > 0,
               flexible.lower > 0, flexible.lower < 1 {
                spending.flexible = flexible
            } else {
                error("planner.flexibleSpending",
                      "Flexible spending needs a cut above 0% and at most 100%, a floor from 0% to 100%, and "
                          + "guardrails above 0% (the lower one below 100%).", .spending, option: "flexible")
            }
        }

        // Pensions.
        var pensions: [PensionSpec] = []
        for (index, pension) in plan.pensions.enumerated() {
            let name = pension.name ?? (plan.pensions.count == 1 ? "Pension" : "Pension \(index + 1)")
            guard let perYear = pension.perYear?.doubleValue, let fromAge = pension.fromAge else {
                error("planner.pensionAmount",
                      "\(name): enter the yearly amount after tax and the age it starts at.", .pensions, index: index)
                continue
            }
            if perYear < 0 {
                error("planner.negativePension", "\(name): the amount can't be negative.", .pensions, index: index)
            }
            if fromAge < 0 || fromAge > 120 {
                error("planner.pensionAge", "\(name): the age it starts at has to be from 0 to 120.", .pensions,
                      index: index)
                continue
            }
            if fromAge > endAge {
                warning("planner.pensionAfterEnd", "\(name) starts after the plan's end age, so the plan never pays it.",
                        .pensions, index: index)
            }
            pensions.append(PensionSpec(index: index, id: "pension-\(index)", name: name, fromAge: fromAge,
                                        perYear: perYear))
        }

        // Other income.
        var income: [IncomeSpec] = []
        for (index, item) in plan.income.enumerated() {
            let name = item.name ?? (plan.income.count == 1 ? "Other income" : "Other income \(index + 1)")
            guard let perYear = item.perYear?.doubleValue, let from = item.from else {
                error("planner.otherIncomeAmount", "\(name): enter the yearly amount after tax and when it starts.",
                      .income, index: index)
                continue
            }
            if perYear < 0 {
                error("planner.negativeOtherIncome", "\(name): the amount can't be negative.", .income, index: index)
            }
            let outOfRange = { (age: Int?) in age.map { $0 < 0 || $0 > 120 } ?? false }
            if outOfRange(from.age) || outOfRange(item.untilAge) {
                error("planner.otherIncomeAge", "\(name): its ages have to be from 0 to 120.", .income, index: index)
                continue
            }
            if let fromAge = from.age, let untilAge = item.untilAge, untilAge <= fromAge {
                error("planner.otherIncomeAges", "\(name): the age it stops at has to be after the one it starts at.",
                      .income, index: index)
                continue
            }
            if let fromAge = from.age, fromAge > endAge {
                warning("planner.otherIncomeAfterEnd",
                        "\(name) starts after the plan's end age, so the plan never pays it.", .income, index: index)
            }
            income.append(IncomeSpec(index: index, id: "income-\(index)", name: name, fromAge: from.age,
                                     untilAge: item.untilAge, perYear: perYear))
        }

        // Simulation settings.
        let requestedRuns = plan.simulation.effectiveRuns
        if requestedRuns < 1 || requestedRuns > 10_000 {
            error("planner.runs", "The number of runs has to be from 1 to 10,000.", .simulation, option: "runs")
        }
        let confidence = plan.simulation.effectiveConfidence.doubleValue
        if !(confidence > 0 && confidence < 1) {
            error("planner.confidence", "The confidence level has to be above 0% and below 100%.", .simulation,
                  option: "confidence")
        }

        // Events.
        var events: [EventSpec] = []
        var probabilities: [Double] = []
        for (index, event) in plan.events.enumerated() {
            let year: Int = switch event.timing {
            case .year(let year): year
            case .age(let age): birthDate.year + age
            }
            let probability = event.effectiveProbability.doubleValue
            guard probability >= 0, probability <= 1 else {
                error("planner.eventProbability", "\(event.name): the probability has to be from 0% to 100%.",
                      .events, index: index)
                continue
            }
            guard frames.contains(where: { $0.year == year }) else {
                warning("planner.eventOutsidePlan", "\(event.name) (\(year)) falls outside the plan's years.",
                        .events, index: index)
                continue
            }
            var bit: Int?
            if probability < 1 {
                guard probabilities.count < 64 else {
                    error("planner.uncertainEvents", "A plan can have at most 64 uncertain events.", .events,
                          index: index)
                    continue
                }
                bit = probabilities.count
                probabilities.append(probability)
            }
            events.append(EventSpec(index: index, name: event.name, year: year, amount: event.amount.doubleValue,
                                    probability: probability, bit: bit))
        }

        // The portfolio, the target mixes and the returns.
        var mixClasses = Set(plan.portfolio.targetMix?.shares.filter { $0.value > 0 }.keys.map { $0 } ?? [])
        if let mix = plan.portfolio.targetMix {
            if Portfolio.shares(mix) == nil {
                warning("planner.targetMixEmpty", "The target mix has no asset class with a share; the money you "
                            + "can draw keeps its own mix.", .portfolio, option: "targetMix")
            } else if abs(mix.total.doubleValue - 1) > 0.001 {
                warning("planner.targetMixTotal",
                        "The target mix adds up to \(percent(mix.total.doubleValue)), not 100%; the plan scales it.",
                        .portfolio, option: "targetMix")
            }
        }
        // Steps by age: ages go up, a step after the end never applies, of two
        // `retirement` steps only the later can. One at or before today's age
        // applies from the start, which needs no message.
        var previousAge: Int?
        var lastRetirement: Int?
        for (index, step) in plan.portfolio.targetMixByAge.enumerated() {
            let start: String
            switch step.fromAge {
            case .age(let age):
                start = "\(age)"
                if let previousAge, age <= previousAge {
                    error("planner.targetMixAges", "The target mix's ages must go up: \(age) comes after \(previousAge).",
                          .portfolio, index: index, option: "targetMixByAge")
                }
                if age > endAge {
                    warning("planner.targetMixLate",
                            "The target mix from \(age) starts after the plan's end at \(endAge); it never applies.",
                            .portfolio, index: index, option: "targetMixByAge")
                }
                previousAge = max(previousAge ?? age, age)
            case .retirement:
                start = "retirement"
                if let earlier = lastRetirement {
                    warning("planner.targetMixRepeated", "Two target mixes start at retirement; only the later one "
                                + "applies.", .portfolio, index: earlier, option: "targetMixByAge")
                }
                lastRetirement = index
            }
            if Portfolio.shares(step.mix) == nil {
                error("planner.targetMixEmpty", "The target mix from \(start) has no asset class with a share.",
                      .portfolio, index: index, option: "targetMixByAge")
            } else if abs(step.mix.total.doubleValue - 1) > 0.001 {
                warning("planner.targetMixTotal",
                        "The target mix from \(start) adds up to \(percent(step.mix.total.doubleValue)), not 100%; the "
                            + "plan scales it.", .portfolio, index: index, option: "targetMixByAge")
            }
            mixClasses.formUnion(step.mix.shares.filter { $0.value > 0 }.keys)
        }
        let portfolio = Portfolio.build(library: library, date: startDate, plan: plan, currentAge: currentAge,
                                        extraClasses: mixClasses, issues: &issues)
        let returns = ReturnModel(assumptions: plan.assumptions, heldClasses: portfolio.classes, issues: &issues)
        let incomeYields = portfolio.classes.map { assetClass in
            min(1, max(0, plan.assumptions.returnAssumption(for: assetClass)?.incomeYield?.doubleValue ?? 0))
        }

        // Contributions, into an account's bucket.
        var contributions: [ContributionSpec] = []
        for (index, contribution) in plan.contributions.enumerated() {
            guard library.accounts[contribution.account] != nil else {
                error("planner.unknownAccount", "A contribution goes into \(contribution.account), which doesn't exist.",
                      .contributions, index: index, account: contribution.account)
                continue
            }
            guard let bucket = portfolio.buckets.firstIndex(where: { $0.accounts.contains(contribution.account) })
            else {
                warning("planner.contributionOutsidePlan",
                        "A contribution goes into \(contribution.account), which the plan doesn't count; it's "
                            + "left out.", .contributions, index: index)
                continue
            }
            let amount = contribution.amount?.doubleValue
            if contribution.perYear.doubleValue < 0 || (amount ?? 0) < 0 {
                error("planner.negativeContribution", "A contribution can't be negative.", .contributions,
                      index: index)
            }
            let oneOff: (year: Int, amount: Double)? = amount.map { (contribution.year ?? startDate.year, $0) }
            contributions.append(ContributionSpec(index: index, account: contribution.account, bucket: bucket,
                                                  perYear: contribution.perYear.doubleValue,
                                                  until: contribution.effectiveUntil.date, oneOff: oneOff))
        }

        guard !issues.contains(where: \.isError) else { return (nil, issues) }
        let model = PlanModel(
            plan: plan, currency: library.settings.baseCurrency, birthDate: birthDate, startDate: startDate,
            currentAge: currentAge, endAge: endAge, planAge: planAge, frames: frames, inflation: inflation,
            work: work, spending: spending, pensions: pensions, income: income, contributions: contributions,
            events: events,
            uncertainEventProbabilities: probabilities,
            taxes: TaxSpec(investmentRate: investmentRate, wealthRate: wealthRate, wealthAllowance: wealthAllowance),
            incomeYields: incomeYields, portfolio: portfolio, returns: returns,
            runs: options.runs(planRuns: requestedRuns), seed: plan.simulation.effectiveSeed,
            confidence: confidence, issues: issues)
        return (model, issues)
    }

    static func percent(_ value: Double) -> String {
        ReturnModel.percent(value)
    }
}
