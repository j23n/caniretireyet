import Foundation
import Model
@testable import Planner
import TaxGeneric
import TaxItaly
import TaxKit
import Testing
import TestSupport

/// The progress a run reports (`Planner.run(…, progress:)`): its phases in
/// order, counts in their own units, an overall share that never goes
/// back, a last update with everything done, throttling, cancellation, and
/// above all the same result as without it.
struct ProgressTests {
    /// Born 1986, 150,000 in equity with 15% volatility, saving while
    /// working: every phase has work to do, and the answer depends on the
    /// random draws.
    let library = Sample.library(birth: "1986-01-01", on: "2025-12-31",
                                 [SampleAccount(id: "broker", balance: 150_000)])

    func plan(retire: AgeChoice = .earliest, runs: Int = 120) -> PlanDocument {
        Sample.plan(retire: retire, endAge: 80, working: "30000", retired: "32000", equityReturn: "0.04",
                    volatility: "0.15", work: [Sample.employee(from: "2026-01-01", gross: "60000")], runs: runs)
    }

    /// Every update a run hands over, in order.
    final class Updates: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [PlannerProgress] = []

        func append(_ progress: PlannerProgress) {
            lock.withLock { values.append(progress) }
        }

        var all: [PlannerProgress] { lock.withLock { values } }
    }

    // MARK: The same result

    @Test(arguments: [PlannerOptions.AgeScan.full, .headline])
    func theResultIsIdenticalWithOrWithoutProgress(scan: PlannerOptions.AgeScan) async throws {
        let options = PlannerOptions(ageScan: scan, maxRetirementAge: 70, solveSustainableSpending: true)
        let registry = Sample.registry()
        let without = try await Planner.run(plan: plan(), library: library, registry: registry, options: options)
        let updates = Updates()
        let with = try await Planner.run(plan: plan(), library: library, registry: registry, options: options,
                                         progress: { updates.append($0) })
        #expect(with == without)
        #expect(bits(with) == bits(without))
        #expect(updates.all.last?.isFinished == true)
    }

    @Test func theExamplePlanIsIdenticalWithOrWithoutProgress() async throws {
        let library = try Fixtures.exampleLibrary()
        let base = try #require(library.plans["base"])
        let registry = TaxRegistry([ItalyTaxSystem(), GenericTaxSystem()])
        var options = PlannerOptions.fast(runs: 60)
        options.ageScan = .headline
        let without = try await Planner.run(plan: base, library: library, registry: registry, options: options)
        let with = try await Planner.run(plan: base, library: library, registry: registry, options: options,
                                         progress: { _ in })
        #expect(with == without)
        #expect(bits(with) == bits(without))
    }

    /// Every number in `value`, bit for bit (`==` would let −0 equal 0),
    /// with dictionaries and sets in a fixed order.
    func bits(_ value: Any) -> String {
        if let double = value as? Double { return String(double.bitPattern, radix: 16) }
        let mirror = Mirror(reflecting: value)
        guard !mirror.children.isEmpty else { return String(describing: value) }
        var parts = mirror.children.map { ($0.label ?? "") + ":" + bits($0.value) }
        if mirror.displayStyle == .dictionary || mirror.displayStyle == .set { parts.sort() }
        return "(" + parts.joined(separator: ",") + ")"
    }

    // MARK: What it reports

    /// Every update, unthrottled.
    func everyUpdate(_ plan: PlanDocument, options: PlannerOptions) async throws -> (PlanResult, [PlannerProgress]) {
        let updates = Updates()
        let reporter = ProgressReporter(interval: .zero) { updates.append($0) }
        let result = try await Planner.compute(plan: plan, library: library, registry: Sample.registry(),
                                               options: options, progress: reporter)
        return (result, updates.all)
    }

    @Test func thePhasesComeInOrderWithTheirOwnCounts() async throws {
        let options = PlannerOptions(maxRetirementAge: 70, solveSustainableSpending: true)
        let (result, updates) = try await everyUpdate(plan(), options: options)
        let phases = PlannerProgress.Phase.allCases

        // Phases in order, each one present.
        let order = updates.map { phases.firstIndex(of: $0.phase)! }
        #expect(order == order.sorted())
        #expect(Set(updates.map(\.phase)) == Set(phases))

        // The overall share never goes back, and ends at exactly 1.
        let fractions = updates.map(\.fraction)
        #expect(fractions == fractions.sorted())
        #expect(fractions.allSatisfy { (0...1).contains($0) })
        #expect(updates.last?.fraction == 1 && updates.last?.isFinished == true)
        #expect(updates.dropLast().allSatisfy { !$0.isFinished })
        #expect(updates.allSatisfy { $0.completed >= 0 && $0.completed <= $0.total && $0.runs == 120 })

        // The scan counts ages: every one from today's (39) to 70.
        let scan = updates.filter { $0.phase == .earliestAge }
        #expect(scan.allSatisfy { $0.ages == 39...70 && $0.total == 32 })
        #expect(scan.first?.completed == 0 && scan.last?.completed == 32)
        #expect(result.successCurve.count == 32)

        // The focus age's runs, one by one.
        let simulating = updates.filter { $0.phase == .simulating }
        #expect(simulating.allSatisfy { $0.total == 120 })
        #expect(simulating.last?.completed == 120)

        // Bisection steps: a dozen or so, never more than the total says.
        let steps = updates.filter { $0.phase == .sustainableSpending }
        let last = try #require(steps.last)
        #expect(last.completed >= 10 && last.completed <= last.total && last.total <= last.completed + 3)
        #expect(steps.map(\.completed) == steps.map(\.completed).sorted())
    }

    @Test func theHeadlineScanCountsTheAgesItRefines() async throws {
        let options = PlannerOptions(ageScan: .headline, maxRetirementAge: 70, solveSustainableSpending: false)
        let (result, updates) = try await everyUpdate(plan(), options: options)
        let scan = updates.filter { $0.phase == .earliestAge }
        let last = try #require(scan.last)
        #expect(last.total == result.successCurve.count)
        #expect(last.completed == last.total)
        #expect(!updates.contains { $0.phase == .sustainableSpending })
        #expect(updates.map(\.fraction) == updates.map(\.fraction).sorted())
        #expect(updates.last?.isFinished == true)
    }

    // MARK: Throttling and threads

    @Test func updatesAreThrottledButTheLastOneAlwaysArrives() {
        let updates = Updates()
        let reporter = ProgressReporter(interval: .seconds(60)) { updates.append($0) }
        reporter.plan(runs: 100, ages: 10, solvesSpending: false)
        reporter.begin(.earliestAge, total: 10, per: 100, ages: 40...49)
        for _ in 0..<1_000 { reporter.advance(1) }
        reporter.begin(.simulating, total: 100)
        reporter.advance(100)
        reporter.finish()
        // The first update, then nothing for a minute, then the last.
        #expect(updates.all.count == 2)
        #expect(updates.all.first?.phase == .earliestAge && updates.all.first?.completed == 0)
        #expect(updates.all.last?.isFinished == true)
    }

    @Test func aRealRunSendsAboutTenUpdatesASecondAtMost() async throws {
        let updates = Updates()
        let start = ContinuousClock.now
        _ = try await Planner.run(plan: plan(runs: 200), library: library, registry: Sample.registry(),
                                  options: PlannerOptions(maxRetirementAge: 70), progress: { updates.append($0) })
        let seconds = Double((ContinuousClock.now - start).components.seconds) + 1
        #expect(Double(updates.all.count) <= seconds * 10 + 2)
        #expect(updates.all.last?.isFinished == true)
    }

    @Test func countingFromManyThreadsAddsUp() async {
        let updates = Updates()
        let reporter = ProgressReporter(interval: .zero) { updates.append($0) }
        reporter.plan(runs: 64, ages: 40, solvesSpending: false)
        reporter.begin(.earliestAge, total: 40, per: 64, ages: 30...69)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<40 {
                group.addTask {
                    for _ in 0..<64 { reporter.advance() }
                }
            }
        }
        let scan = updates.all
        #expect(scan.last?.completed == 40)
        #expect(scan.map(\.completed) == scan.map(\.completed).sorted())
        #expect(scan.map(\.fraction) == scan.map(\.fraction).sorted())
    }

    // MARK: Cancellation

    @Test func cancellingStillStopsTheRunAndSendsNoLastUpdate() async throws {
        let updates = Updates()
        let (started, signal) = AsyncStream<Void>.makeStream()
        let plan = plan(runs: 2_000)
        let library = library
        let task = Task {
            try await Planner.run(plan: plan, library: library, registry: Sample.registry(),
                                  options: PlannerOptions(maxRetirementAge: 50), progress: { progress in
                                      updates.append(progress)
                                      signal.yield()
                                  })
        }
        for await _ in started { break }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!updates.all.contains { $0.isFinished })
    }
}
