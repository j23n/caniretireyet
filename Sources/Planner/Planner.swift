import Foundation
import Model
import Tracker

/// # Planner
///
/// The simulation engine (PLANNER.md). Income from work and pensions comes
/// in after tax; the only taxes it computes are the plan's two rates: on
/// investment income and gains, and on wealth.
///
/// - Builds the starting portfolio from a check-in (`Tracker.Valuator`),
///   grouped by when the money can be drawn.
/// - Runs yearly steps in today's money in the base currency: income,
///   spending, taxes, saving or selling (more by the tax on the gains of
///   what's sold), returns and rebalancing.
/// - A deterministic run and a seeded Monte Carlo simulation with common
///   random numbers across retirement ages and what-ifs; the earliest
///   retirement age, the success curve, the sustainable spending and the
///   plan assets retiring today would need.
///
/// Everything is `Sendable`, and `run` does its work off the main actor.
public enum Planner {
    /// The engine's version, recorded in headlines and baselines.
    public static let engineVersion = "2.0.0"

    /// The plan's problems without running it. Errors would stop a run.
    public static func validate(plan: PlanDocument, library: Library,
                                options: PlannerOptions = PlannerOptions()) -> [PlanIssue] {
        unique(PlanInterpreter.interpret(plan: plan, library: library, options: options).1)
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
    public static func run(plan: PlanDocument, library: Library, options: PlannerOptions = PlannerOptions(),
                           progress: (@Sendable (PlannerProgress) -> Void)? = nil) async throws -> PlanResult {
        let reporter = progress.map { ProgressReporter(handler: $0) }
        return try await withTaskExecutorPreference(PlannerExecutor.shared) {
            try await computeRun(plan: plan, library: library, options: options, progress: reporter).result
        }
    }

    /// A run as ``run(plan:library:options:progress:)`` makes it, on the
    /// caller's executor: the result, and the model it ran, which the
    /// calculations report reads too.
    static func computeRun(plan: PlanDocument, library: Library, options: PlannerOptions,
                           progress: ProgressReporter?) async throws -> (result: PlanResult, model: PlanModel) {
        let (interpreted, issues) = PlanInterpreter.interpret(plan: plan, library: library, options: options)
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
        let changes: [AgeWithout.Change] = (options.solveCoastAge ? [.saving] : [])
            + (options.solveWithoutWindfalls ? uncertainWindfalls(plan).map { .windfall(index: $0) } : [])
        let pace = options.solvePaceAge
            ? Valuator(library: library).savingPace(asOf: model.startDate, inflation: InflationIndex(library: library))
            : nil
        progress?.plan(runs: model.runs, ages: ages.count + refinement,
                       solvesSpending: options.solveSustainableSpending,
                       solvesAssetsNeeded: options.solveAssetsNeeded,
                       agesWithout: changes.count + (pace == nil ? 0 : 1))
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
        let (outcomes, values, paid) = try await engine.evaluateInDetail(age: focus, spending: spending,
                                                                         progress: progress)
        var simulator = engine.simulator(age: focus)
        let (expectedOutcome, expectedYears) = simulator.detailedRun(nil, spending: spending)
        let years = model.frames.count
        let medianRun = Self.medianRun(outcomes)
        let (medianOutcome, medianYears) = simulator.detailedRun(medianRun, spending: spending)
        let focusSchedule = engine.schedules[focus]!

        try Task.checkCancellation()
        var sustainable: SustainableSpending?
        if options.solveSustainableSpending {
            let age = target ?? focus
            try await engine.prepare(ages: [age])
            sustainable = try await engine.sustainableSpending(age: age, progress: progress)
        }
        let startValue = model.portfolio.startAssets.doubleValue
        let successNow = rates[current] ?? 0
        try Task.checkCancellation()
        var assetsNeeded: AssetsNeeded?
        if options.solveAssetsNeeded {
            assetsNeeded = try await engine.assetsNeeded(age: current, startAssets: startValue,
                                                         successToday: successNow, progress: progress)
        }
        var agesWithout: [AgeWithout] = []
        if !changes.isEmpty || pace != nil {
            // Less to live on never makes an earlier age work, so each search
            // starts at the plan's own earliest age; without one, none works.
            let lowest = earliest ?? maxAge
            progress?.begin(.agesWithout, total: changes.count * bisectionSteps(from: lowest, to: maxAge)
                + (pace == nil ? 0 : bisectionSteps(from: current, to: maxAge)))
            for change in changes {
                try Task.checkCancellation()
                var age: Int?
                if earliest != nil {
                    age = try await earliestAge(of: Self.plan(plan, without: change), library: library,
                                                options: options, from: lowest, maxAge: maxAge, progress: progress)
                }
                agesWithout.append(AgeWithout(change: change, earliestAge: age))
            }
            // The pace may save more than the plan, so its search starts at
            // today's age, with or without an earliest age of the plan's.
            if let pace {
                try Task.checkCancellation()
                let age = try await earliestAge(of: Self.plan(plan, atPace: pace, library: library), library: library,
                                                options: options, from: current, maxAge: maxAge, progress: progress)
                agesWithout.append(AgeWithout(change: .pace, earliestAge: age))
            }
        }
        progress?.begin(.summarising, total: 1)

        var fan: [FanYear] = []
        for t in 0..<years {
            let column = (0..<outcomes.count).map { values[$0 * years + t] }.sorted()
            var spent: SpendingPercentiles?
            if paid.count == outcomes.count * years {
                let paidColumn = (0..<outcomes.count).map { paid[$0 * years + t] }.sorted()
                spent = SpendingPercentiles(p10: percentile(paidColumn, 0.1), p50: percentile(paidColumn, 0.5),
                                            p90: percentile(paidColumn, 0.9))
            }
            fan.append(FanYear(
                year: model.frames[t].year, age: model.frames[t].age,
                p10: percentile(column, 0.1), p25: percentile(column, 0.25), p50: percentile(column, 0.5),
                p75: percentile(column, 0.75), p90: percentile(column, 0.9),
                expected: expectedYears.indices.contains(t) ? expectedYears[t].endAssets : 0, spending: spent))
        }

        let answer = PlanAnswer(
            confidence: model.confidence, currentAge: current,
            successIfRetiringNow: successNow, earliestAge: earliest,
            earliestDate: earliest.map { model.retirementDate(forAge: $0) }, targetAge: target,
            successAtTarget: target.flatMap { rates[$0] }, sustainableSpending: sustainable,
            assetsNeeded: assetsNeeded, agesWithout: agesWithout)

        let curve = sortedAges.map { age in
            AgeSuccess(age: age, retirementDate: model.retirementDate(forAge: age), success: rates[age]!)
        }

        let result = PlanResult(
            plan: plan, engine: engineVersion, planHash: planHash(plan),
            start: PlanStart(date: model.startDate, planAssets: model.portfolio.startAssets,
                             accounts: model.portfolio.accounts, buckets: bucketSummaries(model.portfolio)),
            settings: SimulationSettings(runs: model.runs, endAge: model.endAge),
            answer: answer, successCurve: curve, focusAge: focus, fan: fan,
            expectedPath: PathDetail(failure: expectedOutcome.failure, years: expectedYears),
            medianPath: PathDetail(failure: medianOutcome.failure, years: medianYears),
            failures: failureSummary(outcomes),
            markers: markers(schedule: focusSchedule, model: model),
            issues: unique(issues),
            currency: model.currency,
            flexibleSpending: model.spending.flexible.flatMap { rule in
                flexibleSummary(outcomes, rule: rule, age: focus, planSpending: spending,
                                retirementYears: simulator.retirementYears)
            })
        progress?.finish()
        return (result, model)
    }

    // MARK: Ages without

    /// The earliest age from `lowest` to `maxAge` at which `plan` reaches its
    /// confidence level, by bisection over ages (retiring later rarely does
    /// worse): `nil` when `maxAge` doesn't, or when the plan can't run. With
    /// the same options, it simulates the same futures as the plan's own run.
    static func earliestAge(of plan: PlanDocument, library: Library, options: PlannerOptions, from lowest: Int,
                            maxAge: Int, progress: ProgressReporter?) async throws -> Int? {
        let (interpreted, _) = PlanInterpreter.interpret(plan: plan, library: library, options: options)
        guard let model = interpreted else { return nil }
        let lowest = min(max(lowest, model.currentAge), maxAge)
        var engine = try await Engine.make(model: model, ages: [lowest], maxAge: maxAge)
        guard try await engine.reaches(maxAge, progress: progress) else { return nil }
        guard lowest < maxAge else { return maxAge }
        if try await engine.reaches(lowest, progress: progress) { return lowest }
        var low = lowest
        var high = maxAge
        while high - low > 1 {
            let middle = (low + high) / 2
            try await engine.prepare(ages: [middle])
            if try await engine.reaches(middle, progress: progress) { high = middle } else { low = middle }
        }
        return high
    }

    /// The ages a bisection from `lowest` to `highest` tries at most: both
    /// ends, then halving the gap.
    static func bisectionSteps(from lowest: Int, to highest: Int) -> Int {
        var steps = 2
        var span = highest - lowest
        while span > 1 {
            span = (span + 1) / 2
            steps += 1
        }
        return steps
    }

    /// `plan` with one thing different (``AgeWithout/Change``): saving
    /// nothing more, each work phase paying at most the spending while
    /// working, without growth, and no contributions; or an uncertain
    /// windfall that never comes (its probability 0, so the other events'
    /// draws stay the same). The plan at the pace needs the pace, so
    /// ``AgeWithout/Change/pace`` leaves it as it is: use
    /// ``plan(_:atPace:library:)``.
    public static func plan(_ plan: PlanDocument, without change: AgeWithout.Change) -> PlanDocument {
        var plan = plan
        switch change {
        case .saving:
            for index in plan.work.indices {
                if let income = plan.work[index].netIncome {
                    plan.work[index].netIncome = min(income, plan.spending.working)
                }
                plan.work[index].realGrowth = nil
            }
            plan.contributions = []
        case .windfall(let index):
            if plan.events.indices.contains(index) { plan.events[index].probability = 0 }
        case .pace:
            break
        }
        return plan
    }

    /// `plan` saving at `pace` until retirement instead of as written
    /// (PLANNER.md, "Continue as you have"): one work phase paying the
    /// spending while working plus the pace, without growth, so each working
    /// year saves the pace. What went into an account that opens at a later
    /// age (`availableFromAge`) is paid into it as a yearly contribution, and
    /// the rest is saved where the plan saves cash. An account the pace
    /// leaves out keeps the plan's contributions, which the income pays on
    /// top; one-off contributions and events stay, as the pace leaves out
    /// unusual months.
    public static func plan(_ plan: PlanDocument, atPace pace: SavingPace, library: Library) -> PlanDocument {
        var plan = plan
        let excluded = Set(plan.portfolio.exclude)
        let kept = plan.contributions.filter { $0.isOneOff || pace.leftOut.contains($0.account) }
        let locked = pace.byAccount
            .filter { account, amount in
                amount > 0 && !pace.leftOut.contains(account) && !excluded.contains(account)
                    && library.accounts[account]?.availableFromAge != nil
            }
            .sorted { $0.key < $1.key }
            .map { PlanContribution(account: $0.key, perYear: $0.value.rounded(scale: 0)) }
        let paidOnTop = kept.filter { !$0.isOneOff }.reduce(Decimal(0)) { $0 + $1.perYear }
        let from = min(plan.work.map(\.from).min() ?? pace.asOf, pace.asOf)
        plan.work = [WorkPhase(from: from, until: .retirement,
                               netIncome: (plan.spending.working + pace.perYear + paidOnTop).rounded(scale: 0))]
        plan.contributions = kept + locked
        return plan
    }

    /// The indices of `plan`'s uncertain windfalls: events that bring money,
    /// likely but not certain.
    public static func uncertainWindfalls(_ plan: PlanDocument) -> [Int] {
        plan.events.indices.filter { index in
            let event = plan.events[index]
            return event.amount > 0 && event.effectiveProbability > 0 && event.effectiveProbability < 1
        }
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

    /// What flexible spending did over `outcomes`, the runs at `age`
    /// (``FlexibleSpendingSummary``); `nil` without runs or retirement years.
    static func flexibleSummary(_ outcomes: [RunOutcome], rule: FlexibleSpendingSpec, age: Int, planSpending: Double,
                                retirementYears: Int) -> FlexibleSpendingSummary? {
        guard !outcomes.isEmpty, retirementYears > 0 else { return nil }
        let count = outcomes.count
        // Nearest rank, so a level is one some run paid; a failure ranks lowest.
        func rank(_ p: Double) -> Int { Int((Double(count - 1) * p).rounded(.down)) }
        func key(_ outcome: RunOutcome) -> Double { outcome.failure == nil ? outcome.lowestLevel : -1 }
        let byLevel = outcomes.sorted { key($0) < key($1) }
        func level(at p: Double) -> Double? {
            let outcome = byLevel[rank(p)]
            return outcome.failure == nil ? outcome.lowestLevel : nil
        }
        let below = outcomes.map(\.yearsBelowPlan).sorted()
        let shares = below.map { Double($0) / Double(retirementYears) }
        return FlexibleSpendingSummary(
            cut: rule.cut, floor: rule.floor, upperGuardrail: rule.upper, lowerGuardrail: rule.lower,
            planSpending: planSpending, age: age, runs: count, retirementYears: retirementYears,
            shareWithCut: Double(outcomes.filter { $0.failure != nil || $0.lowestLevel < 1 - 1e-9 }.count)
                / Double(count),
            failureRate: Double(outcomes.filter { $0.failure != nil }.count) / Double(count),
            medianLowestLevel: level(at: 0.5), p10LowestLevel: level(at: 0.1),
            medianShareBelow: percentile(shares, 0.5), medianYearsBelow: below[rank(0.5)],
            p90YearsBelow: below[Int((Double(count - 1) * 0.9).rounded(.up))])
    }

    static func failureSummary(_ outcomes: [RunOutcome]) -> FailureSummary {
        let failures = outcomes.compactMap(\.failure)
        let ages = failures.map(\.age).sorted()
        var byAge: [Int: Int] = [:]
        for age in ages { byAge[age, default: 0] += 1 }
        var bridges: [String: BridgeFailure] = [:]
        for failure in failures {
            guard case .locked(let money) = failure.reason else { continue }
            bridges[money.name, default: BridgeFailure(name: money.name, accessibleFromAge: money.accessibleFromAge,
                                                       count: 0, share: 0)].count += 1
        }
        let runs = max(1, outcomes.count)
        return FailureSummary(
            runs: outcomes.count, failed: failures.count, failureRate: Double(failures.count) / Double(runs),
            medianFailureAge: ages.isEmpty ? nil : ages[(ages.count - 1) / 2],
            byAge: byAge.keys.sorted().map { AgeCount(age: $0, count: byAge[$0]!) },
            bridges: bridges.values.map { bridge in
                var bridge = bridge
                bridge.share = Double(bridge.count) / Double(runs)
                return bridge
            }.sorted { ($1.count, $0.name) < ($0.count, $1.name) })
    }

    private static func bucketSummaries(_ portfolio: Portfolio) -> [BucketSummary] {
        portfolio.buckets.map { bucket in
            let value = bucket.value
            var mix: [AssetClass: Double] = [:]
            if value > 0 {
                for (c, assetClass) in portfolio.classes.enumerated() where bucket.values[c] > 0 {
                    mix[assetClass] = bucket.values[c] / value
                }
            }
            return BucketSummary(name: bucket.name, availableFromAge: bucket.opensAtAge, value: value,
                                 costBasis: bucket.basis, mix: mix, accounts: bucket.accounts)
        }
    }

    private static func markers(schedule: AgeSchedule, model: PlanModel) -> [TimelineMarker] {
        var markers: [TimelineMarker] = []
        let retirement = schedule.retirementDate
        if retirement > model.startDate, retirement.year <= model.lastYear {
            markers.append(TimelineMarker(kind: .retirement, year: retirement.year, age: schedule.retirementAge,
                                          label: "Retirement"))
        }
        for pension in model.pensions where pension.perYear > 0 {
            let year = model.birthYear + pension.fromAge
            guard year > model.startDate.year || pension.fromAge > model.currentAge, year <= model.lastYear else {
                continue
            }
            markers.append(TimelineMarker(kind: .pensionStart, year: year, age: pension.fromAge, label: pension.name))
        }
        for bucket in model.portfolio.buckets {
            guard let age = bucket.opensAtAge, bucket.value > 0 else { continue }
            let year = model.firstYear(atAge: age)
            guard year <= model.lastYear else { continue }
            markers.append(TimelineMarker(kind: .accessible, year: year, age: age, label: bucket.name))
        }
        for event in model.events {
            markers.append(TimelineMarker(kind: event.isWindfall ? .windfall : .expense, year: event.year,
                                          age: event.year - model.birthYear, label: event.name))
        }
        return markers.sorted { ($0.year, $0.kind.rawValue, $0.label) < ($1.year, $1.kind.rawValue, $1.label) }
    }
}
