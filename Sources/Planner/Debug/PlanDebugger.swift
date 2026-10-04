import Foundation
import Model
import TaxKit

extension Planner {
    /// Runs a plan as ``run(plan:library:registry:options:progress:)`` does,
    /// then lays out every calculation behind the answer in a
    /// ``PlanDebugReport`` (PLANNER.md, "Plan debugger").
    ///
    /// The details are for one retirement age (``PlanDebugOptions/retirementAge``,
    /// by default today's, the scenario behind "needed to retire today"). On
    /// top of the normal run it simulates every run of that age once more,
    /// for the percentiles of withdrawals and taxes, and re-simulates the
    /// chosen runs with a recorder, which only reads the simulation: each
    /// traced run uses the same random draws as the main run and ends
    /// exactly as it did (``PlanDebugReport/TracedPath/matchesMainRun``).
    /// Normal runs record nothing, so they're no slower.
    ///
    /// Throws ``PlannerError/invalidPlan(_:)`` when the plan has errors.
    public static func debugReport(for plan: PlanDocument, library: Library, registry: TaxRegistry,
                                   options: PlanDebugOptions = PlanDebugOptions()) async throws -> PlanDebugReport {
        try await withTaskExecutorPreference(PlannerExecutor.shared) {
            try await PlanDebugger.report(plan: plan, library: library, registry: registry, options: options)
        }
    }
}

/// Builds a ``PlanDebugReport`` from a run's internals.
enum PlanDebugger {
    static func report(plan: PlanDocument, library: Library, registry: TaxRegistry,
                       options: PlanDebugOptions) async throws -> PlanDebugReport {
        // The age the details are for: the run's focus age.
        let (interpreted, issues) = PlanInterpreter.interpret(plan: plan, library: library, registry: registry,
                                                              options: options.planner)
        guard let first = interpreted else { throw PlannerError.invalidPlan(issues) }
        var plannerOptions = options.planner
        let choice: String
        switch options.retirementAge {
        case .today:
            plannerOptions.focusAge = first.currentAge
            choice = "today"
        case .target:
            plannerOptions.focusAge = first.planAge
            choice = "target"
        case .age(let age):
            plannerOptions.focusAge = age
            choice = "age"
        }
        let computed = try await Planner.computeRun(plan: plan, library: library, registry: registry,
                                                    options: plannerOptions, progress: nil)
        let engine = computed.engine
        let age = computed.result.focusAge
        try Task.checkCancellation()

        // What the percentiles and paths start from: the portfolio the
        // search for the assets needed found (today's plus the extra money
        // in the accessible buckets), or a multiple of every holding.
        let needed = computed.result.answer.assetsNeeded
        let planAssets = engine.model.portfolio.startAssets.double
        var neededExtra: Double?
        if let needed, let extra = needed.extra, planAssets > 0 {
            switch needed.outcome {
            case .found, .moreThanMaximum: neededExtra = extra
            case .atMost: neededExtra = options.startScale == .assetsNeeded ? extra : nil
            case .noPlanAssets: neededExtra = nil
            }
        }
        var scale = 1.0
        var scaleChoice = "actual"
        var extra: Double?
        switch options.startScale {
        case .automatic:
            if age == engine.model.currentAge, let neededExtra, neededExtra > 0 { extra = neededExtra }
        case .actual:
            break
        case .assetsNeeded:
            extra = neededExtra
        case .factor(let factor):
            if factor.isFinite, factor > 0 {
                scale = factor
                scaleChoice = "factor"
            }
        }
        if let extra {
            scale = (planAssets + extra) / planAssets
            scaleChoice = "assetsNeeded"
        }
        let start: Portfolio? = if let extra {
            extra == 0 ? nil : engine.portfolio.withExtra(extra)
        } else {
            scale == 1 ? nil : engine.portfolio.scaled(by: scale)
        }

        // Every run again, for the percentiles of what's drawn and taxed.
        let flows = try await engine.flowSummaries(age: age, spending: engine.model.spending.retired, start: start)
        try Task.checkCancellation()

        let builder = Builder(computed: computed, library: library, registry: registry, plan: plan, flows: flows,
                              scale: scale, scaleChoice: scaleChoice, extra: extra, start: start)
        var report = builder.build(options: options, choice: choice)
        if let anonymization = options.anonymization { report = report.anonymized(anonymization) }
        return report
    }
}

/// What one run at the chosen age drew and paid in taxes, year by year.
struct RunFlows: Sendable {
    let outcome: RunOutcome
    /// Per simulated year, up to the plan's end or the year it failed:
    /// gross sales and payouts, and taxes and contributions.
    let withdrawals: [Double]
    let taxes: [Double]
    /// Plan assets at every year-end (0 after a failure).
    let values: [Double]
}

extension Engine {
    /// Every run at `age` once more, in detail, from `start` (by default the
    /// plan's starting portfolio), keeping each year's withdrawals, taxes and
    /// year-end value: for the plan debugger's percentiles.
    func flowSummaries(age: Int, spending: Double, start: Portfolio? = nil) async throws -> [RunFlows] {
        let engine = self
        let parts = try await parallelMap(Self.chunks(scenarios.runs)) { range -> [RunFlows] in
            var simulator = engine.simulator(age: age, start: start)
            var flows: [RunFlows] = []
            flows.reserveCapacity(range.count)
            for run in range {
                if run > range.lowerBound, (run - range.lowerBound) % Self.runsPerChunk == 0 { try await Self.pause() }
                let (outcome, years) = simulator.detailedRun(run, spending: spending)
                flows.append(RunFlows(
                    outcome: outcome,
                    withdrawals: years.map { year in
                        year.income.filter { $0.kind == .withdrawal || $0.kind == .payout }.reduce(0) { $0 + $1.amount }
                    },
                    taxes: years.map { $0.totalTax + $0.totalContributions }, values: simulator.yearValues))
            }
            return flows
        }
        return parts.flatMap { $0 }
    }
}

// MARK: - Building the report

private struct Builder {
    let computed: Planner.ComputedRun
    let library: Library
    let registry: TaxRegistry
    let plan: PlanDocument
    /// Every run at the chosen age, from the start scale's assets.
    let flows: [RunFlows]
    /// The plan assets the percentiles and paths start from, as a multiple of today's.
    let scale: Double
    let scaleChoice: String
    /// The extra money in the accessible buckets they start with, when they
    /// start from what the search for the assets needed found.
    let extra: Double?
    /// The starting portfolio they start from; `nil` for today's.
    let start: Portfolio?
    /// The deterministic run at the chosen age and start scale.
    let expected: (outcome: RunOutcome, years: [YearDetail])

    var result: PlanResult { computed.result }
    var engine: Engine { computed.engine }
    var model: PlanModel { engine.model }
    var portfolio: Portfolio { engine.portfolio }
    var age: Int { result.focusAge }
    var schedule: AgeSchedule { engine.schedules[age]! }
    var classes: [AssetClass] { portfolio.classes }
    /// Each run's outcome at the chosen age and start scale.
    var outcomes: [RunOutcome] { start == nil ? computed.outcomes : flows.map(\.outcome) }

    init(computed: Planner.ComputedRun, library: Library, registry: TaxRegistry, plan: PlanDocument,
         flows: [RunFlows], scale: Double, scaleChoice: String, extra: Double?, start: Portfolio?) {
        self.computed = computed
        self.library = library
        self.registry = registry
        self.plan = plan
        self.flows = flows
        self.scale = scale
        self.scaleChoice = scaleChoice
        self.extra = extra
        self.start = start
        var simulator = computed.engine.simulator(age: computed.result.focusAge, start: start)
        expected = simulator.detailedRun(nil, spending: computed.engine.model.spending.retired)
    }

    func build(options: PlanDebugOptions, choice: String) -> PlanDebugReport {
        let (paths, median) = tracedPaths(options: options)
        let start = startingPortfolio()
        var report = PlanDebugReport(
            header: header(options: options, choice: choice), diagnosis: [], person: person(),
            plan: planReading(start: start), assumptions: assumptions(shares: start.classShares), start: start,
            schedule: scheduleSection(), simulation: simulation(median: median), percentiles: percentiles(),
            paths: paths, issues: result.issues.map(Self.issue))
        report = report.mapped(.cents)
        report.diagnosis = PlanDebugDiagnosis.findings(for: report)
        return report
    }

    // MARK: Header and person

    func header(options: PlanDebugOptions, choice: String) -> PlanDebugReport.Header {
        PlanDebugReport.Header(
            engine: result.engine, runDate: options.runDate ?? .today(), planID: plan.id.rawValue, planName: plan.name,
            currency: model.currency.rawValue, startDate: model.startDate, runs: model.runs,
            fast: model.runs < plan.simulation.effectiveRuns, seed: model.seed, confidence: model.confidence,
            endAge: model.endAge, taxParameters: model.taxParameters, retirementAge: age,
            retirementAgeChoice: choice, startScale: scale, startScaleChoice: scaleChoice,
            startAssets: model.portfolio.startAssets.double + (extra ?? model.portfolio.startAssets.double * (scale - 1)),
            anonymization: nil, startExtra: extra)
    }

    func person() -> PlanDebugReport.Person {
        let setting = plan.retirement.age.age.map(String.init) ?? "earliest"
        return PlanDebugReport.Person(
            birthDate: model.birthDate, ageToday: model.currentAge,
            citizenships: model.citizenships, taxResidence: library.settings.taxResidence?.rawValue,
            retirementSetting: setting, targetAge: result.answer.targetAge, earliestAge: result.answer.earliestAge,
            chosenAge: age, retirementDate: schedule.retirementDate, endAge: model.endAge,
            firstYear: model.frames.first?.year ?? model.startDate.year, lastYear: model.lastYear)
    }

    // MARK: The plan as read

    func planReading(start: PlanDebugReport.StartingPortfolio) -> PlanDebugReport.PlanReading {
        let residence = model.residence.map { entry -> PlanDebugReport.Residence in
            let written = plan.tax.residence.first { $0.from == entry.from && $0.system.rawValue == entry.system }
            let system = registry.system(entry.system)
            return PlanDebugReport.Residence(
                from: entry.from, system: entry.system, systemName: system?.name ?? entry.system,
                systemCurrency: system?.currency,
                currencyRate: model.systems.first { $0.id == entry.system }?.currencyRate ?? 1,
                options: written?.options ?? [:])
        }
        let overlays = plan.tax.overlays.map {
            PlanDebugReport.Overlay(regime: $0.regime.rawValue,
                                    name: registry.regime($0.regime.rawValue)?.regime.name ?? $0.regime.rawValue,
                                    options: $0.options)
        }
        let work = model.work.map { phase -> PlanDebugReport.Work in
            let written = plan.work.indices.contains(phase.index) ? plan.work[phase.index] : nil
            let until = written.map { $0.until.date?.description ?? "retirement" } ?? "retirement"
            return PlanDebugReport.Work(
                id: phase.id, label: phase.label, kind: phase.kind.rawValue, regime: phase.regime, from: phase.from,
                lastDay: phase.lastDay(retiring: schedule.retirementDate), until: until, gross: phase.gross,
                costs: phase.costs, net: phase.net, realGrowth: phase.realGrowth, options: written?.options ?? [:])
        }
        let spending = PlanDebugReport.Spending(
            working: model.spending.working, retired: model.spending.retired,
            phases: model.spending.phases.map { PlanDebugReport.SpendingPhase(fromAge: $0.fromAge, factor: $0.factor) })

        var seeded: Set<String> = []
        let pensions = model.pensions.enumerated().map { index, pension -> PlanDebugReport.Pension in
            let written = plan.pensions.indices.contains(pension.index) ? plan.pensions[pension.index] : nil
            var seed: Double?
            if let found = start.schemeSeeds.first(where: { $0.scheme == pension.schemeID && $0.used }),
               seeded.insert(pension.schemeID).inserted {
                seed = found.value
            }
            let claim = schedule.claims[index]
            let claimText = switch pension.claim {
            case .earliest: "earliest"
            case .age(let age): String(age)
            }
            return PlanDebugReport.Pension(
                id: pension.id, name: pension.name, scheme: pension.schemeID, schemeName: pension.scheme.name,
                claim: claimText, claimRoute: pension.claimRoute, taxedIn: pension.taxedIn.rawValue,
                kind: pension.kind?.rawValue, sourceCountry: pension.sourceCountry, options: written?.options ?? [:],
                startingBalanceFromAccounts: seed,
                claimed: claim.map { claim in
                    PlanDebugReport.Claim(
                        year: claim.year, age: claim.age, startYear: claim.startYear, route: claim.option.route,
                        label: claim.option.label, yearlyAmount: claim.yearlyAmount(atAge: claim.age),
                        lumpSum: claim.option.lumpSum, lumpSumWrapper: claim.option.lumpSumWrapper,
                        realGrowthPerYear: claim.option.realGrowthPerYear)
                },
                offered: schedule.offeredClaims[index].map { option in
                    PlanDebugReport.ClaimChoice(
                        route: option.route, label: option.label, age: option.age, annualAmount: option.annualAmount,
                        fullYearAmount: option.fullYearAmount,
                        changes: option.changes.map { PlanDebugReport.AgeAmount(age: $0.age, amount: $0.annualAmount) },
                        lumpSum: option.lumpSum, lumpSumWrapper: option.lumpSumWrapper,
                        realGrowthPerYear: option.realGrowthPerYear, note: option.note,
                        chosen: claim?.option == option)
                })
        }
        let contributions = model.contributions.map { contribution -> PlanDebugReport.Contribution in
            let written = plan.contributions.indices.contains(contribution.index)
                ? plan.contributions[contribution.index] : nil
            return PlanDebugReport.Contribution(
                index: contribution.index,
                account: contribution.isScheme ? nil : written?.account.rawValue,
                pensionScheme: contribution.isScheme ? contribution.wrapper : nil, wrapper: contribution.wrapper,
                perYear: contribution.perYear, until: contribution.until?.description ?? "retirement",
                year: contribution.oneOff?.year, amount: contribution.oneOff?.amount)
        }
        let events = model.events.map { event in
            PlanDebugReport.Event(index: event.index, name: event.name, year: event.year,
                                  age: event.year - model.birthYear, amount: event.amount,
                                  probability: event.probability, kind: event.kind,
                                  inDeterministicRun: event.probability >= 0.5)
        }
        let withdrawals = PlanDebugReport.Withdrawals(
            strategy: plan.withdrawals.effectiveStrategy.rawValue, cashBuffer: model.cashBuffer,
            order: [
                "The liquid (taxable) buckets, in proportion to what each can sell, keeping the cash buffer: within "
                    + "a bucket, what the target mix doesn't want first, then the classes furthest above their share.",
                "Tax-advantaged buckets that can be drawn, in proportion, as payouts taxed by their rules.",
                "The cash buffer, last, before the run fails.",
            ],
            rebalancing: "Once a year, after the cash flows and before the returns, every bucket goes back to its "
                + "target mix. In a taxable bucket that's a sale: the gain is taxed and the tax paid from the bucket. "
                + "Inside a tax-advantaged wrapper it's free.")
        return PlanDebugReport.PlanReading(
            residence: residence, overlays: overlays, indexThresholds: model.indexThresholds,
            overrides: plan.tax.overrides, work: work, spending: spending, pensions: pensions,
            contributions: contributions, events: events, withdrawals: withdrawals,
            fees: "No separate fees: each class's expected return is net of fund costs. Taxes on growth inside a "
                + "wrapper and revaluations set by law are listed with the buckets.")
    }

    // MARK: Assumptions

    func assumptions(shares: [String: Double]) -> PlanDebugReport.Assumptions {
        let returns = model.returns
        let correlations = effectiveCorrelations()
        let weights = targetWeights()
        let portfolio = PlanDebugMath.growth(weights: weights, expected: returns.expected,
                                             volatility: returns.volatility, correlations: correlations)
        let classAssumptions = classes.indices.map { c -> PlanDebugReport.ClassAssumption in
            let share = weights[c]
            var without: Double?
            if share > 0, share < 1 - 1e-9 {
                var rest = weights
                rest[c] = 0
                let total = rest.reduce(0, +)
                rest = rest.map { $0 / total }
                without = PlanDebugMath.growth(weights: rest, expected: returns.expected,
                                               volatility: returns.volatility, correlations: correlations).medianReturn
            }
            return PlanDebugReport.ClassAssumption(
                assetClass: classes[c].rawValue, expectedReturn: returns.expected[c],
                volatility: returns.volatility[c],
                medianReturn: PlanDebugMath.median(expected: returns.expected[c],
                                                   variance: returns.volatility[c] * returns.volatility[c]),
                incomeYield: model.incomeYields.indices.contains(c) ? model.incomeYields[c] : 0,
                share: shares[classes[c].rawValue] ?? 0, targetShare: share, portfolioMedianWithout: without)
        }
        return PlanDebugReport.Assumptions(
            inflation: model.inflation, classes: classAssumptions, correlationClasses: classes.map(\.rawValue),
            correlations: correlations, portfolio: portfolio)
    }

    /// Per class, its share of the mix the buckets are rebalanced to: each
    /// bucket's target mix weighted by its value at the start.
    func targetWeights() -> [Double] {
        var weights = [Double](repeating: 0, count: classes.count)
        var total = 0.0
        for (b, bucket) in portfolio.buckets.enumerated() {
            let value = portfolio.lots[bucket.lots].reduce(0) { $0 + $1.value }
            guard value > 0 else { continue }
            total += value
            for c in classes.indices { weights[c] += value * portfolio.targetShares[b * classes.count + c] }
        }
        return total > 0 ? weights.map { $0 / total } : weights
    }

    /// The correlations the simulation uses between the portfolio's
    /// classes: from the Cholesky factor, so a repaired matrix shows as repaired.
    func effectiveCorrelations() -> [[Double]] {
        let returns = model.returns
        return returns.drawIndex.map { i in
            returns.drawIndex.map { j in
                let a = returns.cholesky[i]
                let b = returns.cholesky[j]
                return zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
            }
        }
    }

    // MARK: Starting portfolio

    func startingPortfolio() -> PlanDebugReport.StartingPortfolio {
        var instruments: [InstrumentID] = []
        var rates: [String: PlanDebugReport.FXRate] = [:]
        let accounts = model.portfolio.readings.map { reading -> PlanDebugReport.Account in
            let account = library.accounts[reading.account]
            var outcome = "leftOut"
            var reason: String?
            var bucket: String?
            switch reading.outcome {
            case .included(let wrapper):
                outcome = "included"
                bucket = wrapper
            case .seed(let scheme):
                outcome = "schemeSeed"
                reason = "its value starts the pension scheme \(scheme)"
            case .leftOut(let why):
                reason = why
            }
            var holdings: [PlanDebugReport.Holding] = []
            for part in reading.parts {
                if let instrument = part.instrument, !instruments.contains(instrument) { instruments.append(instrument) }
                var rate: Double?
                if let fx = part.fx, !fx.legs.isEmpty {
                    rate = fx.rate.double
                    rates["\(fx.from)→\(fx.to)"] = PlanDebugReport.FXRate(from: fx.from.rawValue, to: fx.to.rawValue,
                                                                        rate: fx.rate.double, date: fx.date)
                }
                if part.value < 0 {
                    holdings.append(PlanDebugReport.Holding(
                        instrument: part.instrument?.rawValue, assetClass: "debt", category: "debt", value: part.value,
                        costBasis: nil, basisSource: "value", fxRate: rate))
                    continue
                }
                for holding in part.holdings {
                    holdings.append(PlanDebugReport.Holding(
                        instrument: part.instrument?.rawValue, assetClass: holding.assetClass.rawValue,
                        category: holding.category.rawValue, value: holding.value, costBasis: holding.basis,
                        basisSource: part.basis.rawValue, fxRate: rate))
                }
            }
            let bases = holdings.compactMap(\.costBasis)
            return PlanDebugReport.Account(
                id: reading.account.rawValue, name: account?.name ?? reading.account.rawValue,
                kind: account?.kind.rawValue ?? "", currency: account?.currency.rawValue ?? "",
                wrapper: account?.wrapper?.rawValue, outcome: outcome, reason: reason, bucket: bucket,
                value: reading.value, costBasis: bases.isEmpty ? nil : bases.reduce(0, +), holdings: holdings)
        }
        let instrumentRows = instruments.sorted().compactMap { id -> PlanDebugReport.Instrument? in
            guard let instrument = library.instruments[id] else { return nil }
            let total = instrument.assetClasses.total.double
            return PlanDebugReport.Instrument(
                id: id.rawValue, name: instrument.name, kind: instrument.kind.rawValue,
                fundType: instrument.effectiveFundType?.rawValue, currency: instrument.currency.rawValue,
                assetClasses: Dictionary(uniqueKeysWithValues: instrument.assetClasses.shares.map {
                    ($0.key.rawValue, total > 0 ? $0.value.double / total : 0)
                }))
        }

        let total = portfolio.totalValue
        var byClass: [String: Double] = [:]
        for lot in portfolio.lots where lot.value > 0 {
            byClass[classes[lot.classIndex].rawValue, default: 0] += lot.value
        }
        let firstYear = schedule.years.first?.year ?? model.startDate.year
        let buckets = portfolio.buckets.enumerated().map { b, bucket -> PlanDebugReport.Bucket in
            let lots = portfolio.lots[bucket.lots]
            var locked: String?
            if !schedule.years.isEmpty, case .locked(let why) = schedule.access[b] { locked = why }
            let revaluation = bucket.rule?.revaluation.map {
                "\(PlanDebugFormat.percent($0.fixedRate)) + \(PlanDebugFormat.percent($0.inflationShare)) of inflation"
            }
            return PlanDebugReport.Bucket(
                wrapper: bucket.wrapper, name: bucket.name, category: bucket.category.rawValue,
                liquid: bucket.isLiquid, receivesSavings: bucket.receivesSavings,
                value: lots.reduce(0) { $0 + $1.value },
                costBasis: lots.reduce(0) { $0 + ($1.documented ? $1.basis : 0) },
                targetMix: Dictionary(uniqueKeysWithValues: bucket.targetMix.map { ($0.key.rawValue, $0.value) }),
                accounts: bucket.accounts.map(\.rawValue),
                accessibleFromAge: schedule.years.isEmpty ? nil : schedule.accessibleFromAge(bucket: b, after: 0),
                lockedReason: locked,
                paidWhenJobEnds: bucket.rule.map { AgeSchedule.isPaidWhenJobEnds($0, year: firstYear) } ?? false,
                growthTaxRate: bucket.rule?.growthTaxRate, revaluation: revaluation)
        }
        return PlanDebugReport.StartingPortfolio(
            date: model.startDate, planAssets: model.portfolio.startAssets.double, accounts: accounts,
            instruments: instrumentRows, fxRates: rates.keys.sorted().map { rates[$0]! }, buckets: buckets,
            schemeSeeds: result.start.schemeSeeds.map {
                PlanDebugReport.Seed(scheme: $0.scheme, name: $0.name, wrapper: $0.wrapper,
                                     accounts: $0.accounts.map(\.rawValue), value: $0.value, used: $0.used)
            },
            debtPaidOff: model.portfolio.debtPaidOff,
            unrealizedGainShare: plan.portfolio.unrealizedGainShare?.double,
            classShares: total > 0 ? byClass.mapValues { $0 / total } : [:])
    }

    // MARK: Schedule

    func scheduleSection() -> PlanDebugReport.Schedule {
        let names = portfolio.buckets.map(\.name)
        let years = schedule.years.indices.map { t -> PlanDebugReport.ScheduleYear in
            let year = schedule.years[t]
            let variant = year.variants[year.expectedVariant]
            let work = year.income.filter { $0.kind == .work }.reduce(0) { $0 + $1.amount }
            let spending = year.workingSpending + year.retiredUnit * model.spending.retired
            let expenses = year.expenses(for: engine.scenarios.expectedEvents)
            let credits = variant.accruals.filter { $0.amount != 0 }.map {
                PlanDebugReport.Amount(id: $0.wrapper, label: Self.name(of: $0.bucket, in: names, else: $0.wrapper),
                                       amount: $0.amount)
            } + year.transfers.filter { $0.amount != 0 }.map {
                PlanDebugReport.Amount(id: $0.wrapper, label: Self.name(of: $0.bucket, in: names, else: $0.wrapper),
                                       amount: $0.amount)
            }
            let required = year.severance.map { "\(names[$0]): all of it, as severance pay" }
                + year.scheduledPayouts.map {
                    $0.share >= 1 - 1e-12 ? "\(names[$0.bucket]): all of it"
                        : "\(names[$0.bucket]): \(PlanDebugFormat.percent($0.share)) of it"
                }
            return PlanDebugReport.ScheduleYear(
                year: year.year, age: year.age, fraction: year.fraction, workingShare: year.workingShare, work: work,
                pensions: year.income.filter { $0.kind == .pension }.map(Self.amount),
                windfalls: variant.windfalls.map(Self.amount), expenses: expenses,
                contributions: year.contributionTotal, credits: credits, spending: spending,
                taxes: variant.taxes.map(Self.amount), socialContributions: variant.contributions.map(Self.amount),
                netIncome: variant.netCash, toDraw: spending + expenses + year.contributionTotal - variant.netCash,
                requiredPayouts: required,
                accessible: portfolio.buckets.indices.filter { schedule.isAccessible(year: t, bucket: $0) }
                    .map { names[$0] })
        }
        return PlanDebugReport.Schedule(retirementAge: age, retirementDate: schedule.retirementDate, years: years)
    }

    static func name(of bucket: Int, in names: [String], else fallback: String) -> String {
        names.indices.contains(bucket) ? names[bucket] : fallback
    }

    static func amount(_ item: IncomeItem) -> PlanDebugReport.Amount {
        PlanDebugReport.Amount(id: item.id, label: item.label, amount: item.amount)
    }

    static func amount(_ item: AmountItem) -> PlanDebugReport.Amount {
        PlanDebugReport.Amount(id: item.id, label: item.label, amount: item.amount)
    }

    // MARK: Simulation summary

    func simulation(median: PlanDebugReport.PathOutcome) -> PlanDebugReport.Simulation {
        let answer = result.answer
        let spending = answer.sustainableSpending.map { found in
            PlanDebugReport.SpendingSearch(
                age: found.age, perYear: found.perYear, success: found.success, planSpending: model.spending.retired,
                steps: computed.spendingSteps.map { PlanDebugReport.SpendingStep(spending: $0.value, success: $0.success) })
        } ?? (computed.spendingSteps.isEmpty ? nil : PlanDebugReport.SpendingSearch(
            age: answer.targetAge ?? age, perYear: nil, success: nil, planSpending: model.spending.retired,
            steps: computed.spendingSteps.map { PlanDebugReport.SpendingStep(spending: $0.value, success: $0.success) }))
        let planAssets = model.portfolio.startAssets.double
        let assets = answer.assetsNeeded.map { needed in
            PlanDebugReport.AssetsSearch(
                age: needed.age, outcome: Self.outcome(needed.outcome), scale: needed.scale, amount: needed.amount,
                success: needed.success, readiness: needed.readiness, planAssets: planAssets,
                maximumScale: AssetsNeeded.maximumScale,
                steps: computed.scaleSteps.map {
                    PlanDebugReport.ScaleStep(scale: planAssets > 0 ? (planAssets + $0.value) / planAssets : 1,
                                              amount: planAssets + $0.value, success: $0.success, extra: $0.value)
                },
                extra: needed.extra, accessible: needed.accessible)
        }
        let outcomes = self.outcomes
        let failures = Planner.failureSummary(outcomes)
        let expected = self.expected
        let reproduced = start != nil ? nil : flows.count == computed.outcomes.count
            && zip(flows, computed.outcomes).allSatisfy { $0.outcome.failedYear == $1.failedYear
                && $0.outcome.finalValue == $1.finalValue }
        // The search tried today's portfolio and extra money in the accessible buckets.
        let startExtra: Double? = extra ?? (start == nil ? 0 : nil)
        let searched = startExtra.flatMap { wanted in
            computed.scaleSteps.last { abs($0.value - wanted) <= 1e-9 * max(1, abs(wanted)) }
        }
        return PlanDebugReport.Simulation(
            successByAge: result.successCurve.map {
                PlanDebugReport.AgeSuccess(age: $0.age, year: $0.retirementDate.year, success: $0.success)
            },
            successToday: answer.successIfRetiringNow, earliestAge: answer.earliestAge, targetAge: answer.targetAge,
            successAtTarget: answer.successAtTarget, chosenAge: age, successAtChosenAge: result.success(atAge: age),
            successAtStartScale: Double(outcomes.filter { $0.failure == nil }.count) / Double(max(1, outcomes.count)),
            searchSuccessAtStartScale: age == model.currentAge ? searched?.success : nil,
            sustainableSpending: spending, assetsNeeded: assets,
            failures: PlanDebugReport.Failures(
                runs: failures.runs, failed: failures.failed, failureRate: failures.failureRate,
                medianFailureAge: failures.medianFailureAge, depleted: failures.failed - failures.bridgeFailures,
                bridging: failures.bridgeFailures,
                byAge: failures.byAge.map { PlanDebugReport.AgeCount(age: $0.age, count: $0.count) },
                bridges: failures.bridges.map {
                    PlanDebugReport.Bridge(wrapper: $0.wrapper, name: $0.name, accessibleFromAge: $0.accessibleFromAge,
                                           count: $0.count)
                }),
            expectedPath: PlanDebugReport.PathOutcome(
                run: nil, failed: expected.outcome.failure != nil, failureYear: expected.outcome.failure?.year,
                failureAge: expected.outcome.failure?.age, finalValue: expected.outcome.finalValue),
            medianPath: median, allRunsReproduced: reproduced)
    }

    static func outcome(_ outcome: AssetsNeeded.Outcome) -> String {
        switch outcome {
        case .found: "found"
        case .atMost: "atMost"
        case .moreThanMaximum: "moreThanMaximum"
        case .noPlanAssets: "noPlanAssets"
        }
    }

    // MARK: Percentiles

    /// Per year, across every run at the start scale (the fan, at scale 1).
    func percentiles() -> [PlanDebugReport.PercentileYear] {
        let runs = max(1, flows.count)
        return model.frames.indices.map { t in
            let frame = model.frames[t]
            let values = flows.map { $0.values.indices.contains(t) ? $0.values[t] : 0 }.sorted()
            let going = flows.filter { $0.outcome.failedYear.map { $0 > t } ?? true }
            let withdrawals = going.compactMap { $0.withdrawals.indices.contains(t) ? $0.withdrawals[t] : nil }.sorted()
            let taxes = going.compactMap { $0.taxes.indices.contains(t) ? $0.taxes[t] : nil }.sorted()
            return PlanDebugReport.PercentileYear(
                year: frame.year, age: frame.age, value: Self.percentiles(values),
                expected: expected.years.indices.contains(t) ? expected.years[t].endAssets : 0,
                withdrawals: Self.percentiles(withdrawals), taxes: Self.percentiles(taxes),
                going: Double(going.count) / Double(runs))
        }
    }

    static func percentiles(_ sorted: [Double]) -> PlanDebugReport.Percentiles {
        PlanDebugReport.Percentiles(
            p10: Planner.percentile(sorted, 0.1), p25: Planner.percentile(sorted, 0.25),
            p50: Planner.percentile(sorted, 0.5), p75: Planner.percentile(sorted, 0.75),
            p90: Planner.percentile(sorted, 0.9))
    }

    // MARK: Traced paths

    /// The paths to trace, traced, and the median run's outcome with its
    /// retirement totals (traced whether or not it's shown).
    func tracedPaths(options: PlanDebugOptions) -> ([PlanDebugReport.TracedPath], PlanDebugReport.PathOutcome) {
        let outcomes = self.outcomes
        let count = outcomes.count
        let ranked = outcomes.indices.sorted {
            let a = (outcomes[$0].failedYear ?? .max, outcomes[$0].finalValue)
            let b = (outcomes[$1].failedYear ?? .max, outcomes[$1].finalValue)
            return a != b ? a < b : $0 < $1
        }
        var rank = [Int](repeating: 0, count: count)
        for (position, run) in ranked.enumerated() { rank[run] = position + 1 }
        func at(_ share: Double) -> Int? {
            ranked.isEmpty ? nil : ranked[Int((Double(count - 1) * share).rounded(.down))]
        }
        let medianRun = ranked.isEmpty ? nil : ranked[count / 2]

        var picks: [(kind: String, label: String, run: Int)] = []
        switch options.paths {
        case .automatic(let wanted):
            let candidates: [(String, String, Int?)] = [
                ("median", "The median outcome", medianRun),
                ("p10", "A 10th-percentile outcome", at(0.1)),
                ("firstFailure", "The first run that fails", outcomes.firstIndex { $0.failure != nil }),
                ("p25", "A 25th-percentile outcome", at(0.25)),
                ("p75", "A 75th-percentile outcome", at(0.75)),
                ("p90", "A 90th-percentile outcome", at(0.9)),
            ]
            for (kind, label, run) in candidates where picks.count < wanted {
                guard let run, !picks.contains(where: { $0.run == run }) else { continue }
                picks.append((kind, label, run))
            }
        case .runs(let runs):
            for run in runs where (0..<count).contains(run) && !picks.contains(where: { $0.run == run }) {
                picks.append(("chosen", "Run \(run)", run))
            }
        }

        var paths: [PlanDebugReport.TracedPath] = []
        if options.tracesExpectedPath {
            paths.append(trace(run: nil, kind: "expected", label: "The deterministic run (expected returns every year)",
                               rank: nil).path)
        }
        var median: PlanDebugReport.PathOutcome?
        for pick in picks {
            let traced = trace(run: pick.run, kind: pick.kind, label: pick.label, rank: rank[pick.run])
            paths.append(traced.path)
            if pick.run == medianRun { median = traced.outcome }
        }
        if median == nil, let medianRun {
            median = trace(run: medianRun, kind: "median", label: "The median outcome", rank: rank[medianRun]).outcome
        }
        return (paths, median ?? PlanDebugReport.PathOutcome(run: nil, failed: false, finalValue: 0))
    }

    /// One run (`nil`: the deterministic run) traced.
    func trace(run: Int?, kind: String, label: String, rank: Int?)
        -> (path: PlanDebugReport.TracedPath, outcome: PlanDebugReport.PathOutcome) {
        var simulator = engine.simulator(age: age, start: start)
        let recorder = PathRecorder()
        let spending = model.spending.retired
        let (outcome, details) = simulator.tracedRun(run, spending: spending, recorder: recorder)
        // The same run untraced: the main run's at scale 1, else the percentiles' pass.
        let matches: Bool
        if let run {
            let main = outcomes[run]
            matches = main.failedYear == outcome.failedYear && main.finalValue == outcome.finalValue
        } else {
            let main = start == nil ? (result.expectedPath.failure, result.expectedPath.years.map(\.endAssets))
                : (expected.outcome.failure, expected.years.map(\.endAssets))
            matches = main.0 == outcome.failure && main.1 == details.map(\.endAssets)
        }

        var grossIncome = 0.0
        var taxes = 0.0
        var marketTaxes = 0.0
        var withdrawals = 0.0
        let years = zip(recorder.years, details).map { year, detail -> PlanDebugReport.TracedYear in
            let traced = tracedYear(year, detail: detail)
            if schedule.years[year.index].workingShare == 0 {
                grossIncome += detail.income.filter { $0.kind != .work }.reduce(0) { $0 + $1.amount }
                withdrawals += detail.income.filter { $0.kind == .withdrawal || $0.kind == .payout }
                    .reduce(0) { $0 + $1.amount }
                taxes += detail.totalTax + detail.totalContributions
                marketTaxes += traced.taxes.reduce(0) { $0 + $1.market }
            }
            return traced
        }
        let failure = outcome.failure
        let path = PlanDebugReport.TracedPath(
            kind: kind, label: label, run: run, rank: rank, matchesMainRun: matches,
            buckets: portfolio.buckets.map { PlanDebugReport.BucketRef(wrapper: $0.wrapper, name: $0.name) },
            classes: classes.map(\.rawValue), failed: failure != nil, failureYear: failure?.year,
            failureAge: failure?.age, failureReason: failure.map { Self.reason($0.reason) },
            finalValue: outcome.finalValue, years: years)
        let summary = PlanDebugReport.PathOutcome(
            run: run, failed: failure != nil, failureYear: failure?.year, failureAge: failure?.age,
            finalValue: outcome.finalValue, retiredGrossIncome: grossIncome, retiredTaxes: taxes,
            retiredMarketTaxes: marketTaxes, retiredWithdrawals: withdrawals)
        return (path, summary)
    }

    static func reason(_ reason: FailureReason) -> String {
        switch reason {
        case .depleted:
            return "The money ran out: every bucket that could be drawn was empty."
        case .locked(let money):
            let opens = money.accessibleFromAge.map { " until \($0)" } ?? ""
            let why = money.reason.isEmpty ? "" : " (\(money.reason))"
            return "The money ran out while \(money.name) still held money it wouldn't release\(opens)\(why)."
        }
    }

    func tracedYear(_ year: PathRecorder.Year, detail: YearDetail) -> PlanDebugReport.TracedYear {
        let scheduled = schedule.years[year.index]
        let variant = scheduled.variants[year.variant]
        let classCount = classes.count
        let failed = year.failure != nil
        let buckets = portfolio.buckets.indices.map { b -> PlanDebugReport.TracedBucket in
            let credited = year.afterCredits[b] - year.start[b]
            let flow = year.afterFlows[b] - year.afterPayouts[b]
            let row = b * classCount
            var rebalancing = [Double](repeating: 0, count: classCount)
            var rebalancingTax = 0.0
            var growth = 0.0
            if !failed {
                for c in 0..<classCount {
                    rebalancing[c] = year.rebalancedClasses[row + c] - year.flowClasses[row + c]
                }
                if portfolio.buckets[b].isLiquid { rebalancingTax = max(0, year.afterFlows[b] - year.afterRebalancing[b]) }
                growth = year.end[b] - year.afterRebalancing[b]
            }
            return PlanDebugReport.TracedBucket(
                start: year.start[b], moneyIn: credited + max(0, flow),
                requiredPayouts: max(0, year.afterCredits[b] - year.afterPayouts[b]), withdrawn: max(0, -flow),
                rebalancingTax: rebalancingTax, rebalancing: rebalancing, growth: growth, end: year.end[b],
                endCostBasis: year.endBasis[b], endClasses: Array(year.endClasses[row..<(row + classCount)]))
        }
        let sales = year.withdrawalSales.map { Self.sale($0, purpose: "withdrawal") }
            + year.rebalancingSales.map { Self.sale($0, purpose: "rebalancing") }
        let payouts = year.requiredPayouts.map { Self.payout($0, purpose: "required") }
            + year.withdrawalPayouts.map { Self.payout($0, purpose: "withdrawal") }
        let target = year.spending + year.expenses
        return PlanDebugReport.TracedYear(
            year: scheduled.year, age: scheduled.age, fraction: scheduled.fraction, returns: year.returns,
            startAssets: year.startTotal, endAssets: year.endAssets, netIncome: variant.netCash,
            payoutsNet: year.payoutsNet, contributions: year.contributions, spending: year.spending,
            expenses: year.expenses, lastYearsTaxes: year.carriedIn, cashFlow: year.cash, shortfall: year.shortfall,
            spendingTarget: target, spendingMet: failed ? max(0, target - year.shortfall) : target, buckets: buckets,
            sales: sales, payouts: payouts, withheldOnPayouts: year.withheldOnPayouts,
            withheldOnWithdrawals: year.withheldOnWithdrawals, withheldOnRebalancing: year.withheldOnRebalancing,
            taxes: Self.taxLines(variant: variant, assessment: year.assessment), carriedToNextYear: year.carriedOut,
            failed: failed)
    }

    static func sale(_ sale: VariableYear.Sale, purpose: String) -> PlanDebugReport.Sale {
        PlanDebugReport.Sale(wrapper: sale.wrapper, category: sale.category.rawValue, proceeds: sale.proceeds,
                             costBasis: sale.costBasis, gain: sale.costBasis.map { sale.proceeds - $0 },
                             purpose: purpose)
    }

    static func payout(_ payout: VariableYear.WrapperPayout, purpose: String) -> PlanDebugReport.Payout {
        PlanDebugReport.Payout(wrapper: payout.wrapper, amount: payout.amount, costBasis: payout.costBasis,
                               form: payout.form.rawValue, purpose: purpose)
    }

    /// Every tax and contribution line: the fixed part (as the year's
    /// cash flow counts it, for the part of the year simulated) and the
    /// market-dependent part (the assessment less the fixed one, as the
    /// engine charges it).
    static func taxLines(variant: YearVariant, assessment: TaxAssessment?) -> [PlanDebugReport.TaxLine] {
        var lines: [PlanDebugReport.TaxLine] = []
        func add(_ id: String, _ label: String, kind: String, fixed: Double = 0, market: Double = 0) {
            if let index = lines.firstIndex(where: { $0.id == id && $0.kind == kind }) {
                lines[index].fixed += fixed
                lines[index].market += market
            } else {
                lines.append(PlanDebugReport.TaxLine(id: id, label: label, kind: kind, fixed: fixed, market: market))
            }
        }
        for item in variant.taxes { add(item.id, item.label, kind: "tax", fixed: item.amount) }
        for item in variant.contributions { add(item.id, item.label, kind: "contribution", fixed: item.amount) }
        if let assessment {
            for line in assessment.lines { add(line.id, line.label, kind: "tax", market: line.amount) }
            for line in variant.fixed.lines { add(line.id, line.label, kind: "tax", market: -line.amount) }
            for line in assessment.contributions { add(line.id, line.label, kind: "contribution", market: line.amount) }
            for line in variant.fixed.contributions {
                add(line.id, line.label, kind: "contribution", market: -line.amount)
            }
        }
        return lines.filter { abs($0.fixed) > 0.005 || abs($0.market) > 0.005 }
    }

    // MARK: Issues

    static func issue(_ issue: PlanIssue) -> PlanDebugReport.Issue {
        PlanDebugReport.Issue(severity: issue.isError ? "error" : "warning", code: issue.code, message: issue.message,
                              section: issue.section.rawValue, year: issue.year, account: issue.account?.rawValue)
    }
}

// MARK: - Math

/// The log-normal arithmetic behind the assumptions table and the diagnosis.
enum PlanDebugMath {
    /// The median of a log-normal yearly return with this expected (mean)
    /// return and variance: (1 + μ) / √(1 + σ² / (1 + μ)²) − 1.
    static func median(expected: Double, variance: Double) -> Double {
        let mean = 1 + expected
        guard mean > 0 else { return -1 }
        return mean / (1 + variance / (mean * mean)).squareRoot() - 1
    }

    /// A mix rebalanced every year: its expected return, volatility and median.
    static func growth(weights: [Double], expected: [Double], volatility: [Double],
                       correlations: [[Double]]) -> PlanDebugReport.Growth {
        var mean = 0.0
        var variance = 0.0
        for i in weights.indices {
            mean += weights[i] * expected[i]
            for j in weights.indices {
                variance += weights[i] * weights[j] * volatility[i] * volatility[j] * correlations[i][j]
            }
        }
        variance = max(0, variance)
        return PlanDebugReport.Growth(expectedReturn: mean, volatility: variance.squareRoot(),
                                      medianReturn: median(expected: mean, variance: variance))
    }
}
