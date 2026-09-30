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

        // Every wrapper that receives money needs a bucket.
        var builder = model.portfolio
        var issues = model.issues
        let wrappers = Set(built.flatMap { schedule in
            schedule.years.flatMap { year in
                year.contributions.map(\.wrapper) + year.variants.flatMap { $0.accruals.map(\.wrapper) }
            }
        })
        for wrapper in wrappers.sorted() {
            if let issue = builder.addBucket(wrapper: wrapper) { issues.append(issue) }
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

    /// The share of runs that succeed at each age.
    func successRates(ages: [Int], spending: Double) async throws -> [Int: Double] {
        let engine = self
        let rates = try await parallelMap(ages) { age -> Double in
            var simulator = engine.simulator(age: age)
            var successes = 0
            for run in 0..<engine.scenarios.runs {
                if run % 64 == 0, Task.isCancelled { throw CancellationError() }
                if simulator.run(run, spending: spending).failure == nil { successes += 1 }
            }
            return Double(successes) / Double(engine.scenarios.runs)
        }
        return Dictionary(uniqueKeysWithValues: zip(ages, rates))
    }

    /// Every run at one age, with year-end values: split across workers.
    func evaluateInDetail(age: Int, spending: Double) async throws -> (outcomes: [RunOutcome], values: [Double]) {
        let runs = scenarios.runs
        let years = model.frames.count
        let engine = self
        let chunks = Self.chunks(runs)
        let parts = try await parallelMap(chunks) { range -> ([RunOutcome], [Double]) in
            var simulator = engine.simulator(age: age)
            var outcomes: [RunOutcome] = []
            var values: [Double] = []
            outcomes.reserveCapacity(range.count)
            values.reserveCapacity(range.count * years)
            for run in range {
                if run % 64 == 0, Task.isCancelled { throw CancellationError() }
                outcomes.append(simulator.run(run, spending: spending, recordValues: true))
                values += simulator.yearValues
            }
            return (outcomes, values)
        }
        return (parts.flatMap(\.0), parts.flatMap(\.1))
    }

    /// A simulator for one age's schedule.
    func simulator(age: Int) -> PathSimulator {
        PathSimulator(schedule: schedules[age]!, scenarios: scenarios, portfolio: portfolio, model: model)
    }

    // MARK: - Sustainable spending

    /// The highest yearly retirement spending that still reaches the
    /// confidence level at `age`, by bisection. Each run's success is
    /// monotone in spending, so runs already settled at a lower or higher
    /// level aren't simulated again.
    func sustainableSpending(age: Int) async throws -> SustainableSpending? {
        let runs = scenarios.runs
        let confidence = model.confidence
        var succeedsUpTo = [Double](repeating: -.infinity, count: runs)
        var failsFrom = [Double](repeating: .infinity, count: runs)
        let engine = self

        func success(at level: Double) async throws -> Double {
            let open = (0..<runs).filter { succeedsUpTo[$0] < level && level < failsFrom[$0] }
            let chunks = Self.chunks(open.count).map { Array(open[$0]) }
            let results = try await parallelMap(chunks) { chunk -> [(Int, Bool)] in
                var simulator = engine.simulator(age: age)
                return try chunk.enumerated().map { offset, run in
                    if offset % 64 == 0, Task.isCancelled { throw CancellationError() }
                    return (run, simulator.run(run, spending: level).failure == nil)
                }
            }
            for (run, succeeded) in results.joined() {
                if succeeded { succeedsUpTo[run] = level } else { failsFrom[run] = level }
            }
            return Double((0..<runs).filter { succeedsUpTo[$0] >= level }.count) / Double(runs)
        }

        guard try await success(at: 0) >= confidence else { return nil }
        var low = 0.0
        var high = max(1000, model.spending.retired * 1.5)
        while try await success(at: high) >= confidence {
            low = high
            high *= 2
            if high > 1e8 { break }
        }
        for _ in 0..<60 where high - low > max(10, low * 0.0005) {
            let mid = (low + high) / 2
            if try await success(at: mid) >= confidence { low = mid } else { high = mid }
        }
        let perYear = (low / 10).rounded(.down) * 10
        return SustainableSpending(age: age, perYear: perYear, success: try await success(at: perYear))
    }

    // MARK: - Helpers

    /// Splits `count` items into one range per worker.
    static func chunks(_ count: Int) -> [Range<Int>] {
        let workers = max(1, min(ProcessInfo.processInfo.activeProcessorCount, count))
        guard count > 0 else { return [] }
        let size = (count + workers - 1) / workers
        return stride(from: 0, to: count, by: size).map { $0..<min(count, $0 + size) }
    }
}

/// Maps `items` concurrently, keeping their order.
func parallelMap<Item: Sendable, Result: Sendable>(
    _ items: [Item], _ transform: @escaping @Sendable (Item) throws -> Result
) async throws -> [Result] {
    try await withThrowingTaskGroup(of: (Int, Result).self) { group in
        for (index, item) in items.enumerated() {
            group.addTask { (index, try transform(item)) }
        }
        var results = [Result?](repeating: nil, count: items.count)
        for try await (index, result) in group { results[index] = result }
        return results.map { $0! }
    }
}
