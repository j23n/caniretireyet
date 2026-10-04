import Foundation
import Model
import TaxKit

/// A plan ready to simulate: the model, the shared random futures, and the
/// schedule of each retirement age prepared so far.
struct Engine: Sendable {
    let model: PlanModel
    let scenarios: MarketScenarios
    private(set) var portfolio: Portfolio
    private(set) var schedules: [Int: AgeSchedule] = [:]
    private(set) var issues: [PlanIssue]
    /// Per year, the local windfall masks that occur in some run.
    private let neededMasks: [[Int]]
    /// The flexible-spending rule every simulator applies: the plan's, or
    /// `nil` to simulate it with spending fixed in real terms (the plan
    /// debugger's comparison).
    var flexibleSpending: FlexibleSpendingSpec?

    /// Builds the scenarios and prepares the schedules of `ages` (plus the
    /// oldest age, so every wrapper that work credits gets a bucket).
    static func make(model: PlanModel, ages: [Int], maxAge: Int) async throws -> Engine {
        let scenarios = MarketScenarios(model: model.returns, fractions: model.frames.map(\.fraction), runs: model.runs,
                                        seed: model.seed, eventProbabilities: model.uncertainEventProbabilities)
        let neededMasks = model.frames.map { frame -> [Int] in
            let bits = model.events.filter { $0.year == frame.year && $0.isWindfall }.compactMap(\.bit)
            guard !bits.isEmpty else { return [0] }
            var masks = Set<Int>()
            for mask in scenarios.eventMasks + [scenarios.expectedEvents] {
                var local = 0
                for (position, bit) in bits.enumerated() where mask & (1 << UInt64(bit)) != 0 {
                    local |= 1 << position
                }
                masks.insert(local)
            }
            return masks.sorted()
        }
        let expected = scenarios.expectedEvents
        var built = try await parallelMap(Array(Set(ages + [maxAge])).sorted()) { age in
            AgeSchedule(model: model, age: age, neededMasks: neededMasks, expectedMask: expected)
        }

        // Every wrapper that receives money needs a bucket. One that only a
        // scheme's lump sum moves into (pension-fund assets into vested
        // benefits when work stops early) is expected to be new, so it gets
        // no warning; money paid or credited into one is worth one.
        var builder = model.portfolio
        var issues = model.issues
        let paidInto = Set(built.flatMap { schedule in
            schedule.years.flatMap { year in
                year.contributions.map(\.wrapper) + year.variants.flatMap { $0.accruals.map(\.wrapper) }
            }
        })
        let transferredInto = Set(built.flatMap { $0.years.flatMap { $0.transfers.map(\.wrapper) } })
        for wrapper in paidInto.union(transferredInto).sorted() {
            if let issue = builder.addBucket(wrapper: wrapper), paidInto.contains(wrapper) { issues.append(issue) }
        }
        let portfolio = builder.finalized()
        for index in built.indices { built[index].resolve(for: portfolio, model: model) }

        var engine = Engine(model: model, scenarios: scenarios, portfolio: portfolio, issues: issues,
                            neededMasks: neededMasks)
        for schedule in built { engine.schedules[schedule.retirementAge] = schedule }
        return engine
    }

    private init(model: PlanModel, scenarios: MarketScenarios, portfolio: Portfolio, issues: [PlanIssue],
                 neededMasks: [[Int]]) {
        self.model = model
        self.scenarios = scenarios
        self.portfolio = portfolio
        self.issues = issues
        self.neededMasks = neededMasks
        flexibleSpending = model.spending.flexible
    }

    /// Prepares the schedules of ages not prepared yet.
    mutating func prepare(ages: [Int]) async throws {
        let missing = ages.filter { schedules[$0] == nil }
        guard !missing.isEmpty else { return }
        let model = model
        let neededMasks = neededMasks
        let expected = scenarios.expectedEvents
        let portfolio = portfolio
        let built = try await parallelMap(missing) { age in
            var schedule = AgeSchedule(model: model, age: age, neededMasks: neededMasks, expectedMask: expected)
            schedule.resolve(for: portfolio, model: model)
            return schedule
        }
        for schedule in built { schedules[schedule.retirementAge] = schedule }
    }

    // MARK: - Evaluating ages

    /// The share of runs that succeed at each age. `progress` counts the
    /// runs simulated.
    func successRates(ages: [Int], spending: Double, progress: ProgressReporter? = nil) async throws
        -> [Int: Double] {
        let engine = self
        let rates = try await parallelMap(ages) { age -> Double in
            var simulator = engine.simulator(age: age)
            var successes = 0
            for run in 0..<engine.scenarios.runs {
                if run > 0, run % Self.runsPerChunk == 0 {
                    progress?.advance(Self.runsPerChunk)
                    try await Self.pause()
                }
                if simulator.run(run, spending: spending).failure == nil { successes += 1 }
            }
            progress?.advance(Self.lastChunk(of: engine.scenarios.runs))
            return Double(successes) / Double(engine.scenarios.runs)
        }
        return Dictionary(uniqueKeysWithValues: zip(ages, rates))
    }

    /// Every run at one age, with year-end values (and, with flexible
    /// spending, the spending paid each year, run by run like the values;
    /// empty without it): split across workers. `progress` counts the runs
    /// simulated.
    func evaluateInDetail(age: Int, spending: Double, progress: ProgressReporter? = nil) async throws
        -> (outcomes: [RunOutcome], values: [Double], spending: [Double]) {
        let runs = scenarios.runs
        let years = model.frames.count
        let engine = self
        let chunks = Self.chunks(runs)
        let recordsSpending = flexibleSpending != nil
        let parts = try await parallelMap(chunks) { range -> ([RunOutcome], [Double], [Double]) in
            var simulator = engine.simulator(age: age)
            var outcomes: [RunOutcome] = []
            var values: [Double] = []
            var paid: [Double] = []
            outcomes.reserveCapacity(range.count)
            values.reserveCapacity(range.count * years)
            if recordsSpending { paid.reserveCapacity(range.count * years) }
            for run in range {
                if run > range.lowerBound, (run - range.lowerBound) % Self.runsPerChunk == 0 {
                    progress?.advance(Self.runsPerChunk)
                    try await Self.pause()
                }
                outcomes.append(simulator.run(run, spending: spending, recordValues: true))
                values += simulator.yearValues
                if recordsSpending { paid += simulator.yearSpending }
            }
            progress?.advance(Self.lastChunk(of: range.count))
            return (outcomes, values, paid)
        }
        return (parts.flatMap(\.0), parts.flatMap(\.1), parts.flatMap(\.2))
    }

    /// A simulator for one age's schedule, starting from `start` (by
    /// default the plan's own starting portfolio), with the engine's
    /// flexible-spending rule.
    func simulator(age: Int, start: Portfolio? = nil) -> PathSimulator {
        PathSimulator(schedule: schedules[age]!, scenarios: scenarios, portfolio: start ?? portfolio, model: model,
                      flexible: flexibleSpending)
    }

    // MARK: - Sustainable spending

    /// The highest yearly retirement spending that still reaches the
    /// confidence level at `age`, by bisection. Each run's success is
    /// monotone in spending, so runs already settled at a lower or higher
    /// level aren't simulated again. `progress` counts the levels tried
    /// (steps), against an estimate that grows when the search needs more.
    func sustainableSpending(age: Int, progress: ProgressReporter? = nil) async throws -> SustainableSpending? {
        try await sustainableSpendingSearch(age: age, progress: progress).answer
    }

    /// ``sustainableSpending(age:progress:)`` with every level it tried and
    /// the success there, in the order tried, for the plan debugger.
    func sustainableSpendingSearch(age: Int, progress: ProgressReporter? = nil) async throws
        -> (answer: SustainableSpending?, steps: [SearchStep]) {
        let runs = scenarios.runs
        let confidence = model.confidence
        var succeedsUpTo = [Double](repeating: -.infinity, count: runs)
        var failsFrom = [Double](repeating: .infinity, count: runs)
        let engine = self
        // Levels tried so far, for `progress`: each is a step.
        var steps = 0
        var tried: [SearchStep] = []

        func success(at level: Double) async throws -> Double {
            let open = (0..<runs).filter { succeedsUpTo[$0] < level && level < failsFrom[$0] }
            let chunks = Self.chunks(open.count).map { Array(open[$0]) }
            let results = try await parallelMap(chunks) { chunk -> [(Int, Bool)] in
                var simulator = engine.simulator(age: age)
                var settled: [(Int, Bool)] = []
                settled.reserveCapacity(chunk.count)
                for (offset, run) in chunk.enumerated() {
                    if offset > 0, offset % Self.runsPerChunk == 0 { try await Self.pause() }
                    settled.append((run, simulator.run(run, spending: level).failure == nil))
                }
                return settled
            }
            for (run, succeeded) in results.joined() {
                if succeeded { succeedsUpTo[run] = level } else { failsFrom[run] = level }
            }
            steps += 1
            progress?.advance()
            let rate = Double((0..<runs).filter { succeedsUpTo[$0] >= level }.count) / Double(runs)
            tried.append(SearchStep(value: level, success: rate))
            return rate
        }

        var high = max(1000, model.spending.retired * 1.5)
        // Zero, the first upper bound, the bisection and the final check.
        progress?.begin(.sustainableSpending, total: 3 + Self.bisectionSteps(low: 0, high: high))
        guard try await success(at: 0) >= confidence else { return (nil, tried) }
        var low = 0.0
        while try await success(at: high) >= confidence {
            low = high
            high *= 2
            if high > 1e8 { break }
            progress?.extend(to: steps + 2 + Self.bisectionSteps(low: low, high: high))
        }
        progress?.extend(to: steps + 1 + Self.bisectionSteps(low: low, high: high))
        for _ in 0..<60 where high - low > max(10, low * 0.0005) {
            let mid = (low + high) / 2
            if try await success(at: mid) >= confidence { low = mid } else { high = mid }
        }
        let perYear = (low / 10).rounded(.down) * 10
        let answer = SustainableSpending(age: age, perYear: perYear, success: try await success(at: perYear))
        return (answer, tried)
    }

    // MARK: Assets needed to retire today

    /// The plan assets at the start that make retiring at `age` reach the
    /// confidence level (PLANNER.md, "Assets needed to retire today").
    ///
    /// It adds extra money X to the buckets that can be drawn at any age,
    /// the liquid ones (``startPortfolio(extra:)``: split by the target mix
    /// in force at today's age, with no unrealised gain), or takes money out of them (X < 0,
    /// never below zero), and searches the plan assets S + X as a multiple
    /// of today's S: from 1 it doubles (or halves) until the confidence
    /// level is crossed, between ``AssetsNeeded/maximumScale`` and the
    /// larger of 1 / ``AssetsNeeded/maximumScale`` and what's locked away,
    /// then bisects on a log scale until the bracket is narrower than
    /// ``AssetsNeeded/tolerance``. Every amount uses the same random draws,
    /// and a run is taken to succeed with every amount above one it
    /// succeeded with (more money to draw doesn't make it fail), so runs
    /// already settled aren't simulated again and the success rate never
    /// falls as the amount rises. At X = 0 the runs are the scan's own, so
    /// the result reaches 100% (`readiness` ≥ 1) exactly when retiring today
    /// does. `progress` counts the amounts tried (steps).
    ///
    /// - Parameters:
    ///   - startAssets: today's plan assets (``PlanStart/planAssets``), S.
    ///   - successToday: the scan's chance of success at `age`, used when
    ///     there are no plan assets.
    func assetsNeeded(age: Int, startAssets: Double, successToday: Double,
                      progress: ProgressReporter? = nil) async throws -> AssetsNeeded {
        try await assetsNeededSearch(age: age, startAssets: startAssets, successToday: successToday,
                                     progress: progress).answer
    }

    /// ``assetsNeeded(age:startAssets:successToday:progress:)`` with every
    /// amount it tried, as the extra money in the accessible buckets, and
    /// the success there, in the order tried, for the plan debugger.
    func assetsNeededSearch(age: Int, startAssets: Double, successToday: Double,
                            progress: ProgressReporter? = nil) async throws
        -> (answer: AssetsNeeded, steps: [SearchStep]) {
        let runs = scenarios.runs
        let confidence = model.confidence
        let spending = model.spending.retired
        let maximum = AssetsNeeded.maximumScale
        guard startAssets > 0, portfolio.totalValue > 1e-6 else {
            let enough = successToday >= confidence
            return (AssetsNeeded(age: age, outcome: .noPlanAssets, amount: enough ? 0 : nil,
                                 success: enough ? successToday : nil, readiness: enough ? nil : 0), [])
        }
        // What can be taken out: the accessible money, down to 1 / maximum of today's plan assets.
        let accessible = portfolio.accessibleValue
        let lowest = max(startAssets / maximum, startAssets - accessible)
        let floor = min(1, lowest / startAssets)
        let fewest = min(0, lowest - startAssets)
        // The extra money at a multiple of today's plan assets.
        func extra(at scale: Double) -> Double {
            scale <= floor ? fewest : scale == 1 ? 0 : (scale - 1) * startAssets
        }

        // Per run, the smallest multiple it succeeded at and the largest it failed at.
        var succeedsFrom = [Double](repeating: .infinity, count: runs)
        var failsUpTo = [Double](repeating: -.infinity, count: runs)
        let engine = self
        var steps = 0
        var tried: [SearchStep] = []

        func success(at scale: Double) async throws -> Double {
            let open = (0..<runs).filter { failsUpTo[$0] < scale && scale < succeedsFrom[$0] }
            let start = engine.startPortfolio(extra: extra(at: scale))
            let chunks = Self.chunks(open.count).map { Array(open[$0]) }
            let results = try await parallelMap(chunks) { chunk -> [(Int, Bool)] in
                var simulator = engine.simulator(age: age, start: start)
                var settled: [(Int, Bool)] = []
                settled.reserveCapacity(chunk.count)
                for (offset, run) in chunk.enumerated() {
                    if offset > 0, offset % Self.runsPerChunk == 0 { try await Self.pause() }
                    settled.append((run, simulator.run(run, spending: spending).failure == nil))
                }
                return settled
            }
            for (run, succeeded) in results.joined() {
                if succeeded { succeedsFrom[run] = scale } else { failsUpTo[run] = scale }
            }
            steps += 1
            progress?.advance()
            tried.append(SearchStep(value: extra(at: scale), success: rate(at: scale)))
            return rate(at: scale)
        }

        func rate(at scale: Double) -> Double {
            Double((0..<runs).filter { succeedsFrom[$0] <= scale }.count) / Double(runs)
        }

        // Today's assets, a step out, the bisection over a doubling.
        progress?.begin(.assetsNeeded, total: 2 + Self.logBisectionSteps(low: 1, high: 2))
        var low = 1.0
        var high = 1.0
        if try await success(at: 1) >= confidence {
            while true {
                guard high > floor else {
                    return (AssetsNeeded(age: age, outcome: .atMost, scale: floor, amount: startAssets + fewest,
                                         success: rate(at: floor), readiness: 1 / floor, extra: fewest,
                                         accessible: accessible), tried)
                }
                low = max(floor, high / 2)
                guard try await success(at: low) >= confidence else { break }
                high = low
                progress?.extend(to: steps + 1 + Self.logBisectionSteps(low: max(floor, high / 2), high: high))
            }
        } else {
            high = 2
            while try await success(at: high) < confidence {
                low = high
                if high >= maximum {
                    return (AssetsNeeded(age: age, outcome: .moreThanMaximum, scale: maximum,
                                         extra: extra(at: maximum), accessible: accessible), tried)
                }
                high = min(maximum, high * 2)
                progress?.extend(to: steps + 1 + Self.logBisectionSteps(low: low, high: high))
            }
        }
        progress?.extend(to: steps + Self.logBisectionSteps(low: low, high: high))
        while high / low > 1 + AssetsNeeded.tolerance {
            let middle = (low * high).squareRoot()
            if try await success(at: middle) >= confidence { high = middle } else { low = middle }
        }
        let needed = extra(at: high)
        return (AssetsNeeded(age: age, outcome: .found, scale: high, amount: startAssets + needed,
                             success: rate(at: high), readiness: startAssets / (startAssets + needed), extra: needed,
                             accessible: accessible), tried)
    }

    /// Today's portfolio with `extra` more money in the buckets that can be
    /// drawn at any age (less, when negative), as the search for the assets
    /// needed tries it (``Portfolio/withExtra(_:step:)``): split by the
    /// target mix in force in the first year of retiring today, so a
    /// `retirement` step of the plan's target mix applies.
    func startPortfolio(extra: Double) -> Portfolio {
        portfolio.withExtra(extra, step: schedules[model.currentAge]?.startStep)
    }

    /// How many halvings of the log of `high / low` the search for the
    /// assets needed takes to get within ``AssetsNeeded/tolerance``.
    static func logBisectionSteps(low: Double, high: Double) -> Int {
        var steps = 0
        var ratio = high / low
        while steps < 60, ratio > 1 + AssetsNeeded.tolerance {
            ratio = ratio.squareRoot()
            steps += 1
        }
        return steps
    }

    /// At most how many halvings the bisection between `low` and `high`
    /// takes: its tolerance only grows as `low` does.
    static func bisectionSteps(low: Double, high: Double) -> Int {
        var steps = 0
        var gap = high - low
        while steps < 60, gap > max(10, low * 0.0005) {
            gap /= 2
            steps += 1
        }
        return steps
    }

    // MARK: - Helpers

    /// How many runs a task simulates between pauses (``pause()``).
    static let runsPerChunk = 64

    /// The runs of a loop of `count` after its last pause: what's left to
    /// count for progress once it ends.
    static func lastChunk(of count: Int) -> Int {
        guard count > 0 else { return 0 }
        return count - (count - 1) / runsPerChunk * runsPerChunk
    }

    /// Between chunks of work: stops if the run was cancelled, and lets the
    /// other jobs waiting for the planner's threads go first.
    static func pause() async throws {
        try Task.checkCancellation()
        await Task.yield()
    }

    /// Splits `count` items into one range per planner thread.
    static func chunks(_ count: Int) -> [Range<Int>] {
        let workers = max(1, min(PlannerExecutor.shared.threadCount, count))
        guard count > 0 else { return [] }
        let size = (count + workers - 1) / workers
        return stride(from: 0, to: count, by: size).map { $0..<min(count, $0 + size) }
    }
}

/// One value a search tried, and the share of runs that succeed with it:
/// a yearly spending, or the extra money in the accessible buckets.
struct SearchStep: Sendable {
    let value: Double
    let success: Double
}

/// Maps `items` concurrently, keeping their order. Each item is a child
/// task, on the planner's threads when the caller prefers them; an item
/// doesn't start once the task is cancelled.
func parallelMap<Item: Sendable, Result: Sendable>(
    _ items: [Item], _ transform: @escaping @Sendable (Item) async throws -> Result
) async throws -> [Result] {
    try await withThrowingTaskGroup(of: (Int, Result).self) { group in
        for (index, item) in items.enumerated() {
            group.addTask {
                try Task.checkCancellation()
                return (index, try await transform(item))
            }
        }
        var results = [Result?](repeating: nil, count: items.count)
        for try await (index, result) in group { results[index] = result }
        return results.map { $0! }
    }
}
