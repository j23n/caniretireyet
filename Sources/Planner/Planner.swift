import Foundation
import Model
import TaxKit

/// # Planner
///
/// The simulation engine (PLANNER.md). It contains no tax rules: every tax,
/// contribution and pension rule comes from a `TaxKit.TaxSystem` chosen by
/// the plan and looked up in a `TaxRegistry`.
///
/// - Builds the starting portfolio from a check-in (`Tracker.Valuator`),
///   grouped into buckets by tax wrapper.
/// - Runs yearly steps in today's money in the plan's currency: income, taxes (prepared once per
///   retirement age and year, assessed per path, gross-up for withdrawals),
///   spending, withdrawals, returns and rebalancing.
/// - A deterministic run and a seeded Monte Carlo simulation with common
///   random numbers across retirement ages and what-ifs; the earliest
///   retirement age, the success curve, the sustainable spending and the
///   plan assets retiring today would need.
///
/// Everything is `Sendable`, and `run` does its work off the main actor.
public enum Planner {
    /// The engine's version, recorded in headlines and baselines.
    public static let engineVersion = "1.0.0"

    /// The plan's problems without running it: the engine's checks and every
    /// tax system's validation. Errors would stop a run.
    ///
    /// When the plan names a retirement age, the tax systems also check its
    /// years one by one (`validate(_:years:parameters:)`), which finds
    /// problems that depend on each year's amounts, such as forfettario's
    /// revenue limit. With `earliest` the years aren't known yet; a run
    /// reports them for the age its details are for.
    public static func validate(plan: PlanDocument, library: Library, registry: TaxRegistry,
                                options: PlannerOptions = PlannerOptions()) -> [PlanIssue] {
        let (interpreted, issues) = PlanInterpreter.interpret(plan: plan, library: library, registry: registry,
                                                              options: options)
        guard let model = interpreted, let age = model.planAge else { return issues }
        let schedule = AgeSchedule(model: model, age: min(max(age, model.currentAge), model.endAge - 1),
                                   neededMasks: model.frames.map { _ in [] }, expectedMask: model.expectedEvents)
        return unique(issues + schedule.issues + model.yearIssues(for: schedule))
    }

    /// Runs a plan: the success curve by retirement age, the earliest age at
    /// the plan's confidence level, the details for one age (the plan's,
    /// the earliest, or `options.focusAge`), and what retiring today would
    /// need (``PlanAnswer/assetsNeeded``).
    ///
    /// Throws ``PlannerError/invalidPlan(_:)`` when the plan has errors, and
    /// `CancellationError` when the task is cancelled (e.g. a slider moved on).
    ///
    /// The work runs on the planner's own threads (`PlannerExecutor`), never
    /// on Swift's cooperative thread pool, so other async work in the app,
    /// such as fetching prices, carries on while it runs.
    ///
    /// `progress`, when given, is told where the run is (``PlannerProgress``):
    /// at most about ten times a second, on the planner's threads, one call
    /// at a time and in order, and always once more with `fraction` 1 just
    /// before the result is returned (not when the run fails or is
    /// cancelled). Keep it short, e.g. hand the value to another actor. The
    /// result is identical with or without it.
    public static func run(plan: PlanDocument, library: Library, registry: TaxRegistry,
                           options: PlannerOptions = PlannerOptions(),
                           progress: (@Sendable (PlannerProgress) -> Void)? = nil) async throws -> PlanResult {
        let reporter = progress.map { ProgressReporter(handler: $0) }
        return try await withTaskExecutorPreference(PlannerExecutor.shared) {
            try await compute(plan: plan, library: library, registry: registry, options: options, progress: reporter)
        }
    }

    static func compute(plan: PlanDocument, library: Library, registry: TaxRegistry, options: PlannerOptions,
                        progress: ProgressReporter?) async throws -> PlanResult {
        try await computeRun(plan: plan, library: library, registry: registry, options: options,
                             progress: progress).result
    }

    /// A run as ``compute(plan:library:registry:options:progress:)`` makes
    /// it, with what the plan debugger needs besides the result: the engine
    /// (its model, portfolio, scenarios and schedules), each run's outcome
    /// at the focus age, and the values the two searches tried.
    struct ComputedRun: Sendable {
        let result: PlanResult
        let engine: Engine
        /// Every run at ``PlanResult/focusAge``, by run index.
        let outcomes: [RunOutcome]
        /// The sustainable-spending search, in the order tried (empty when not solved).
        let spendingSteps: [SearchStep]
        /// The assets-needed search's scales, in the order tried (empty when not solved).
        let scaleSteps: [SearchStep]
    }

    static func computeRun(plan: PlanDocument, library: Library, registry: TaxRegistry, options: PlannerOptions,
                           progress: ProgressReporter?) async throws -> ComputedRun {
        let (interpreted, issues) = PlanInterpreter.interpret(plan: plan, library: library, registry: registry,
                                                              options: options)
        guard let model = interpreted else { throw PlannerError.invalidPlan(issues) }
        try Task.checkCancellation()

        let current = model.currentAge
        let maxAge = max(current, min(model.endAge - 1, max(options.maxRetirementAge, model.planAge ?? 0)))
        let clamp = { (age: Int) in min(max(age, current), model.endAge - 1) }
        let planAge = model.planAge.map(clamp)
        var ages: [Int]
        switch options.ageScan {
        case .full:
            ages = Array(current...maxAge)
        case .headline:
            ages = Array(stride(from: current, through: maxAge, by: 4)) + [maxAge]
        }
        ages = Array(Set(ages + [planAge, options.focusAge.map(clamp)].compactMap { $0 })).sorted()

        // The headline grid may be refined by up to 3 ages between two of its own.
        let refinement = options.ageScan == .headline ? min(3, max(0, maxAge - current + 1 - ages.count)) : 0
        progress?.plan(runs: model.runs, ages: ages.count + refinement,
                       solvesSpending: options.solveSustainableSpending,
                       solvesAssetsNeeded: options.solveAssetsNeeded)
        progress?.begin(.earliestAge, total: ages.count, per: model.runs, expected: ages.count + refinement,
                        ages: ages[0]...ages[ages.count - 1])
        var engine = try await Engine.make(model: model, ages: ages, maxAge: maxAge)
        let spending = model.spending.retired
        var rates = try await engine.successRates(ages: ages, spending: spending, progress: progress)

        // The headline scan refines between the last grid age below the
        // confidence level and the first one at or above it.
        if options.ageScan == .headline,
           let first = rates.keys.sorted().first(where: { rates[$0]! >= model.confidence }),
           let previous = rates.keys.sorted().last(where: { $0 < first }), first - previous > 1 {
            let between = Array((previous + 1)..<first)
            progress?.extend(to: ages.count + between.count, expected: ages.count + between.count)
            try await engine.prepare(ages: between)
            rates.merge(try await engine.successRates(ages: between, spending: spending, progress: progress)) { $1 }
        } else {
            progress?.expect(ages.count)
        }
        try Task.checkCancellation()
        let sortedAges = rates.keys.sorted()
        let earliest = sortedAges.first { rates[$0]! >= model.confidence }
        let target = planAge ?? earliest
        let focus = options.focusAge.map(clamp) ?? target ?? maxAge
        progress?.begin(.simulating, total: model.runs)
        try await engine.prepare(ages: [focus])

        // The focus age in detail.
        let (outcomes, values) = try await engine.evaluateInDetail(age: focus, spending: spending,
                                                                   progress: progress)
        var simulator = engine.simulator(age: focus)
        let (expectedOutcome, expectedYears) = simulator.detailedRun(nil, spending: spending)
        let years = model.frames.count
        let medianRun = Self.medianRun(outcomes)
        let (medianOutcome, medianYears) = simulator.detailedRun(medianRun, spending: spending)
        let focusSchedule = engine.schedules[focus]!

        try Task.checkCancellation()
        var sustainable: SustainableSpending?
        var spendingSteps: [SearchStep] = []
        if options.solveSustainableSpending {
            let age = target ?? focus
            try await engine.prepare(ages: [age])
            (sustainable, spendingSteps) = try await engine.sustainableSpendingSearch(age: age, progress: progress)
        }
        let startValue = model.portfolio.startAssets.double
        let successNow = rates[current] ?? 0
        try Task.checkCancellation()
        var assetsNeeded: AssetsNeeded?
        var scaleSteps: [SearchStep] = []
        if options.solveAssetsNeeded {
            let search = try await engine.assetsNeededSearch(age: current, startAssets: startValue,
                                                             successToday: successNow, progress: progress)
            assetsNeeded = search.answer
            scaleSteps = search.steps
        }
        progress?.begin(.summarising, total: 1)

        var fan: [FanYear] = []
        for t in 0..<years {
            let column = (0..<outcomes.count).map { values[$0 * years + t] }.sorted()
            fan.append(FanYear(
                year: model.frames[t].year, age: model.frames[t].age,
                p10: percentile(column, 0.1), p25: percentile(column, 0.25), p50: percentile(column, 0.5),
                p75: percentile(column, 0.75), p90: percentile(column, 0.9),
                expected: expectedYears.indices.contains(t) ? expectedYears[t].endAssets : 0))
        }

        let fi = fiNumber(schedule: focusSchedule, model: model, rate: options.fiWithdrawalRate)
        let answer = PlanAnswer(
            canRetireNow: successNow >= model.confidence, confidence: model.confidence, currentAge: current,
            successIfRetiringNow: successNow, earliestAge: earliest,
            earliestDate: earliest.map { model.retirementDate(forAge: $0) }, targetAge: target,
            successAtTarget: target.flatMap { rates[$0] }, sustainableSpending: sustainable, fiNumber: fi,
            fiProgress: fi.map { $0 > 0 ? startValue / $0 : 1 }, assetsNeeded: assetsNeeded)

        let curve = sortedAges.map { age in
            AgeSuccess(age: age, retirementDate: model.retirementDate(forAge: age), success: rates[age]!,
                       runs: model.runs,
                       pensionStartAges: Dictionary(uniqueKeysWithValues: engine.schedules[age]!.claims.compactMap {
                           $0.map { (model.pensions[$0.pension].id, $0.age) }
                       }))
        }

        let result = PlanResult(
            plan: plan, engine: engineVersion, planHash: planHash(plan), taxParameters: model.taxParameters,
            start: PlanStart(date: model.startDate, age: current, planAssets: model.portfolio.startAssets,
                             accounts: model.portfolio.accounts,
                             buckets: bucketSummaries(engine.portfolio), schemeSeeds: schemeSeeds(model)),
            settings: SimulationSettings(runs: model.runs, seed: model.seed, confidence: model.confidence,
                                         inflation: model.inflation, endAge: model.endAge),
            answer: answer, successCurve: curve, focusAge: focus, fan: fan,
            expectedPath: PathDetail(retirementAge: focus, failure: expectedOutcome.failure, years: expectedYears),
            medianPath: PathDetail(retirementAge: focus, failure: medianOutcome.failure, years: medianYears),
            failures: failureSummary(outcomes),
            markers: markers(schedule: focusSchedule, engine: engine),
            issues: unique(engine.issues + focusSchedule.issues + model.yearIssues(for: focusSchedule)),
            currency: model.currency)
        progress?.finish()
        return ComputedRun(result: result, engine: engine, outcomes: outcomes, spendingSteps: spendingSteps,
                           scaleSteps: scaleSteps)
    }

    /// Issues without repeats, in their first order.
    private static func unique(_ issues: [PlanIssue]) -> [PlanIssue] {
        var seen: Set<PlanIssue> = []
        return issues.filter { seen.insert($0).inserted }
    }

    // MARK: - Assembling results

    /// The run in the middle when runs are ranked by how long their money
    /// lasts, then by what's left at the end.
    static func medianRun(_ outcomes: [RunOutcome]) -> Int {
        let ranked = outcomes.indices.sorted {
            let a = (outcomes[$0].failedYear ?? .max, outcomes[$0].finalValue)
            let b = (outcomes[$1].failedYear ?? .max, outcomes[$1].finalValue)
            return a != b ? a < b : $0 < $1
        }
        return ranked[ranked.count / 2]
    }

    /// The `p` quantile of sorted values, interpolating linearly.
    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard let first = sorted.first else { return 0 }
        guard sorted.count > 1 else { return first }
        let position = Double(sorted.count - 1) * p
        let low = Int(position.rounded(.down))
        let high = min(sorted.count - 1, low + 1)
        return sorted[low] + (sorted[high] - sorted[low]) * (position - Double(low))
    }

    static func failureSummary(_ outcomes: [RunOutcome]) -> FailureSummary {
        let failures = outcomes.compactMap(\.failure)
        let ages = failures.map(\.age).sorted()
        var byAge: [Int: Int] = [:]
        for age in ages { byAge[age, default: 0] += 1 }
        var bridges: [String: BridgeFailure] = [:]
        for failure in failures {
            guard case .locked(let money) = failure.reason else { continue }
            bridges[money.wrapper, default: BridgeFailure(wrapper: money.wrapper, name: money.name,
                                                          accessibleFromAge: money.accessibleFromAge, count: 0,
                                                          share: 0)].count += 1
        }
        let runs = max(1, outcomes.count)
        return FailureSummary(
            runs: outcomes.count, failed: failures.count, failureRate: Double(failures.count) / Double(runs),
            medianFailureAge: ages.isEmpty ? nil : ages[(ages.count - 1) / 2],
            byAge: byAge.keys.sorted().map { AgeCount(age: $0, count: byAge[$0]!) },
            bridgeFailures: bridges.values.reduce(0) { $0 + $1.count },
            bridges: bridges.values.map { bridge in
                var bridge = bridge
                bridge.share = Double(bridge.count) / Double(runs)
                return bridge
            }.sorted { ($1.count, $0.wrapper) < ($0.count, $1.wrapper) })
    }

    /// The FI number, kept for compatibility (``PlanAnswer/fiNumber``; the
    /// results show ``PlanAnswer/assetsNeeded`` instead): retirement
    /// spending not covered by pensions, over the withdrawal rate. The
    /// pensions count once all have started: a whole year of each (the year after the last one starts, when the plan
    /// reaches it), net of the tax they add. That tax is the difference
    /// between the year assessed by its residence system with the pensions
    /// and without them, since taxes such as IRPEF are charged on total
    /// income and belong to no one pension.
    static func fiNumber(schedule: AgeSchedule, model: PlanModel, rate: Double) -> Double? {
        guard rate > 0 else { return nil }
        let claims = schedule.claims.compactMap { $0 }
        var pensions = 0.0
        if let last = claims.map(\.year).max(),
           let t = schedule.years.firstIndex(where: { $0.year == last + 1 })
            ?? schedule.years.firstIndex(where: { $0.year == last }) {
            let frame = model.frames[t]
            let paid = claims.map { claim in
                let pension = model.pensions[claim.pension]
                return FixedYear.Pension(id: pension.id, scheme: pension.schemeID,
                                         amount: claim.yearlyAmount(atAge: frame.age), taxedIn: pension.taxedIn,
                                         kind: pension.kind, startYear: claim.startYear,
                                         sourceCountry: pension.sourceCountry,
                                         mandatoryShare: claim.option.mandatoryShare)
            }
            let system = model.systems[frame.system].system
            let overlays = model.overlays.filter { system.regime($0.regime) != nil }
            let state = schedule.years[t].taxState
            func taxes(_ pensions: [FixedYear.Pension]) -> Double {
                // The paying countries' tax on pensions taxed at source counts too.
                let foreign = NonResidentTaxes(model: model, frame: frame, pensions: pensions, state: state)
                let year = FixedYear(year: frame.year, age: frame.age, systemOptions: frame.systemOptions,
                                     overlays: overlays, pensions: foreign.pensions,
                                     inflationFactor: frame.inflationFactor,
                                     indexThresholds: model.indexThresholds, currencyRate: frame.currencyRate,
                                     citizenships: model.citizenships, birthDate: model.birthDate.birthDate,
                                     residence: model.residence)
                let assessment = system.prepare(year, state: state, parameters: frame.parameters).fixedAssessment
                return assessment.totalTax + assessment.totalContributions + foreign.total
            }
            pensions = paid.reduce(0) { $0 + $1.amount } - (taxes(paid) - taxes([]))
        }
        return max(0, model.spending.retired - pensions) / rate
    }

    /// The accounts that started a pension scheme, and whether it used them.
    private static func schemeSeeds(_ model: PlanModel) -> [SchemeSeed] {
        model.portfolio.seeds.map { seed in
            let pension = model.pensions.first { $0.schemeID == seed.scheme }
            let used = pension?.options["startingBalance"] == .number(seed.value)
            return SchemeSeed(scheme: seed.scheme, name: pension?.scheme.name ?? seed.scheme, wrapper: seed.wrapper,
                              accounts: seed.accounts, value: seed.value, used: used)
        }
    }

    private static func bucketSummaries(_ portfolio: Portfolio) -> [BucketSummary] {
        portfolio.buckets.map { bucket in
            let lots = portfolio.lots[bucket.lots]
            return BucketSummary(
                wrapper: bucket.wrapper, name: bucket.name, category: bucket.category,
                receivesSavings: bucket.receivesSavings, value: lots.reduce(0) { $0 + $1.value },
                costBasis: lots.reduce(0) { $0 + ($1.documented ? $1.basis : 0) }, targetMix: bucket.targetMix,
                accounts: bucket.accounts)
        }
    }

    private static func markers(schedule: AgeSchedule, engine: Engine) -> [TimelineMarker] {
        let model = engine.model
        var markers: [TimelineMarker] = []
        let retirement = schedule.retirementDate
        if retirement > model.startDate, retirement.year <= model.lastYear {
            markers.append(TimelineMarker(kind: .retirement, year: retirement.year, age: schedule.retirementAge,
                                          label: "Retirement"))
        }
        for claim in schedule.claims.compactMap({ $0 }) {
            markers.append(TimelineMarker(kind: .pensionStart, year: claim.year, age: claim.age,
                                          label: model.pensions[claim.pension].name,
                                          amount: claim.yearlyAmount(atAge: claim.age)))
        }
        // Severance pay is paid out when the job ends, so it gets no marker.
        for (b, bucket) in engine.portfolio.buckets.enumerated() where !bucket.isLiquid {
            guard !schedule.years.isEmpty, !schedule.years.contains(where: { $0.severance.contains(b) }),
                  !schedule.isAccessible(year: 0, bucket: b),
                  let t = schedule.years.indices.first(where: { schedule.isAccessible(year: $0, bucket: b) })
            else { continue }
            markers.append(TimelineMarker(kind: .accessible, year: schedule.years[t].year, age: schedule.years[t].age,
                                          label: bucket.name))
        }
        for event in model.events {
            markers.append(TimelineMarker(kind: event.isWindfall ? .windfall : .expense, year: event.year,
                                          age: event.year - model.birthYear, label: event.name, amount: event.amount,
                                          probability: event.probability < 1 ? event.probability : nil))
        }
        return markers.sorted { ($0.year, $0.kind.rawValue, $0.label) < ($1.year, $1.kind.rawValue, $1.label) }
    }
}
