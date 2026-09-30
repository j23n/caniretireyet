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
/// - Runs yearly steps in today's euros: income, taxes (prepared once per
///   retirement age and year, assessed per path, gross-up for withdrawals),
///   spending, withdrawals, returns and rebalancing.
/// - A deterministic run and a seeded Monte Carlo simulation with common
///   random numbers across retirement ages and what-ifs; the earliest
///   retirement age, the success curve and the sustainable spending.
///
/// Everything is `Sendable`, and `run` does its work off the main actor.
public enum Planner {
    /// The engine's version, recorded in headlines and baselines.
    public static let engineVersion = "1.0.0"

    /// The plan's problems without running it: the engine's checks and every
    /// tax system's validation. Errors would stop a run.
    public static func validate(plan: PlanDocument, library: Library, registry: TaxRegistry,
                                options: PlannerOptions = PlannerOptions()) -> [PlanIssue] {
        PlanInterpreter.interpret(plan: plan, library: library, registry: registry, options: options).issues
    }

    /// Runs a plan: the success curve by retirement age, the earliest age at
    /// the plan's confidence level, and the details for one age (the plan's,
    /// the earliest, or `options.focusAge`).
    ///
    /// Throws ``PlannerError/invalidPlan(_:)`` when the plan has errors, and
    /// `CancellationError` when the task is cancelled (e.g. a slider moved on).
    public static func run(plan: PlanDocument, library: Library, registry: TaxRegistry,
                           options: PlannerOptions = PlannerOptions()) async throws -> PlanResult {
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

        var engine = try await Engine.make(model: model, ages: ages, maxAge: maxAge)
        let spending = model.spending.retired
        var rates = try await engine.successRates(ages: ages, spending: spending)

        // The headline scan refines between the last grid age below the
        // confidence level and the first one at or above it.
        if options.ageScan == .headline,
           let first = rates.keys.sorted().first(where: { rates[$0]! >= model.confidence }),
           let previous = rates.keys.sorted().last(where: { $0 < first }), first - previous > 1 {
            let between = Array((previous + 1)..<first)
            try await engine.prepare(ages: between)
            rates.merge(try await engine.successRates(ages: between, spending: spending)) { $1 }
        }
        try Task.checkCancellation()
        let sortedAges = rates.keys.sorted()
        let earliest = sortedAges.first { rates[$0]! >= model.confidence }
        let target = planAge ?? earliest
        let focus = options.focusAge.map(clamp) ?? target ?? maxAge
        try await engine.prepare(ages: [focus])

        // The focus age in detail.
        let (outcomes, values) = try await engine.evaluateInDetail(age: focus, spending: spending)
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
            sustainable = try await engine.sustainableSpending(age: age)
        }

        var fan: [FanYear] = []
        for t in 0..<years {
            let column = (0..<outcomes.count).map { values[$0 * years + t] }.sorted()
            fan.append(FanYear(
                year: model.frames[t].year, age: model.frames[t].age,
                p10: percentile(column, 0.1), p25: percentile(column, 0.25), p50: percentile(column, 0.5),
                p75: percentile(column, 0.75), p90: percentile(column, 0.9),
                expected: expectedYears.indices.contains(t) ? expectedYears[t].endAssets : 0))
        }

        let startValue = model.portfolio.startAssets.double
        let fi = fiNumber(schedule: focusSchedule, model: model, rate: options.fiWithdrawalRate)
        let successNow = rates[current] ?? 0
        let answer = PlanAnswer(
            canRetireNow: successNow >= model.confidence, confidence: model.confidence, currentAge: current,
            successIfRetiringNow: successNow, earliestAge: earliest,
            earliestDate: earliest.map { model.retirementDate(forAge: $0) }, targetAge: target,
            successAtTarget: target.flatMap { rates[$0] }, sustainableSpending: sustainable, fiNumber: fi,
            fiProgress: fi.map { $0 > 0 ? startValue / $0 : 1 })

        let curve = sortedAges.map { age in
            AgeSuccess(age: age, retirementDate: model.retirementDate(forAge: age), success: rates[age]!,
                       runs: model.runs,
                       pensionStartAges: Dictionary(uniqueKeysWithValues: engine.schedules[age]!.claims.compactMap {
                           $0.map { (model.pensions[$0.pension].id, $0.age) }
                       }))
        }

        return PlanResult(
            plan: plan, engine: engineVersion, planHash: planHash(plan), taxParameters: model.taxParameters,
            start: PlanStart(date: model.startDate, age: current, planAssets: model.portfolio.startAssets,
                             accounts: model.portfolio.accounts,
                             buckets: bucketSummaries(engine.portfolio)),
            settings: SimulationSettings(runs: model.runs, seed: model.seed, confidence: model.confidence,
                                         inflation: model.inflation, endAge: model.endAge),
            answer: answer, successCurve: curve, focusAge: focus, fan: fan,
            expectedPath: PathDetail(retirementAge: focus, failure: expectedOutcome.failure, years: expectedYears),
            medianPath: PathDetail(retirementAge: focus, failure: medianOutcome.failure, years: medianYears),
            failures: failureSummary(outcomes),
            markers: markers(schedule: focusSchedule, engine: engine),
            issues: engine.issues + focusSchedule.issues)
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

    private static func failureSummary(_ outcomes: [RunOutcome]) -> FailureSummary {
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

    /// The FI number: retirement spending not covered by pensions (net of
    /// the taxes the system charges on them, once all have started), over
    /// the withdrawal rate.
    private static func fiNumber(schedule: AgeSchedule, model: PlanModel, rate: Double) -> Double? {
        guard rate > 0 else { return nil }
        let claims = schedule.claims.compactMap { $0 }
        var pensions = 0.0
        if let year = claims.map(\.year).max(), let t = schedule.years.firstIndex(where: { $0.year == year }) {
            let scheduled = schedule.years[t]
            let fixed = scheduled.variants[scheduled.expectedVariant].fixed
            for claim in claims {
                let id = model.pensions[claim.pension].id
                let taxes = (fixed.lines + fixed.contributions).filter { $0.subject == id }.reduce(0) { $0 + $1.amount }
                pensions += claim.option.annualAmount(atAge: scheduled.age) - taxes
            }
        }
        return max(0, model.spending.retired - pensions) / rate
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
                                          amount: claim.option.annualAmount(atAge: claim.age)))
        }
        for (b, bucket) in engine.portfolio.buckets.enumerated() where !bucket.isLiquid {
            guard !schedule.years.isEmpty, !schedule.isAccessible(year: 0, bucket: b),
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
