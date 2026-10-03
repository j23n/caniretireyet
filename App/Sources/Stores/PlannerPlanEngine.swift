import Foundation
import Model
import Planner
import TaxGeneric
import TaxGermany
import TaxItaly
import TaxKit
import TaxSwitzerland

/// The tax systems the app knows, registered in one place (TAXES.md,
/// "Adding a system": registering a new one is an import and an entry
/// here, and the app target links its library product).
/// Everything else reads this registry: the residence, regime, scheme and
/// claim-route pickers, the option forms, the account wrappers, a new
/// plan's residence (the system for the residence country, else `generic`)
/// and the onboarding's note on tax rules.
enum AppTaxRegistry {
    /// Italy (`it`), Switzerland (`ch`), Germany (`de`) and the generic
    /// flat-rate system (`generic`).
    static let standard = TaxRegistry([ItalyTaxSystem(), SwissTaxSystem(), GermanTaxSystem(), GenericTaxSystem()])
}

/// The parts of a library a plan run reads: settings (birth date, base
/// currency), accounts, instruments and history (valuations, prices, FX,
/// inflation). Plans, projections and import profiles are left out, so
/// saving a headline or a baseline doesn't make a plan run again.
struct PlanRunInputs: Hashable, Sendable {
    var settings: LibrarySettings
    var accounts: [AccountID: Account]
    var instruments: [InstrumentID: Instrument]
    var months: [YearMonth: MonthFile]

    init(_ library: Library) {
        settings = library.settings
        accounts = library.accounts
        instruments = library.instruments
        months = library.months
    }
}

/// The `PlanEngine` the app uses: the Planner, with the Italian and generic
/// tax systems.
///
/// - **Modes.** `.full` runs every run the plan asks for over every
///   retirement age; `.fast` (what-if sliders being dragged) runs
///   `PlannerOptions.defaultFastRuns` runs with the same random draws, over
///   a coarse grid of ages refined around the answer.
/// - **Focus age.** A request for another retirement age (tapping the
///   success curve) reuses the plan's full results and simulates only that
///   age in detail, then merges its fan, income and failures in.
/// - **Cache.** Results are kept per plan hash, library inputs, mode, focus
///   age and start date, so going back to a plan, or a what-if back to where
///   it was, doesn't run again; ``cachedResults(for:)`` looks without running.
/// - **Progress.** The Planner's `PlannerProgress`, as `PlanRunProgress`.
///   A request that needs two runs (a what-if's saving needs the plan's own
///   run first; a focus age needs the full run) shares the bar between them.
/// - **Cancellation.** Runs stop promptly when their task is cancelled
///   (`PlanStore` cancels a superseded run); cancelled runs aren't cached.
struct PlannerPlanEngine: PlanEngine {
    let registry: TaxRegistry
    private let cache: PlanRunCache

    init(registry: TaxRegistry = AppTaxRegistry.standard, cacheCapacity: Int = 32) {
        self.registry = registry
        cache = PlanRunCache(capacity: cacheCapacity)
    }

    var version: String { Planner.engineVersion }

    func run(_ request: PlanRunRequest) async throws -> PlanResults {
        try await run(request, reporting: nil)
    }

    func run(_ request: PlanRunRequest, progress: @escaping PlanProgressHandler) async throws -> PlanResults {
        try await run(request, reporting: progress)
    }

    private func run(_ request: PlanRunRequest, reporting progress: PlanProgressHandler?) async throws -> PlanResults {
        // Running never comes back empty.
        guard let results = try await resolve(request, running: true, progress: progress) else {
            throw CancellationError()
        }
        return results
    }

    func cachedResults(for request: PlanRunRequest) async -> PlanResults? {
        try? await resolve(request, running: false, progress: nil)
    }

    /// The results of `request`: from the cache, else run when `running`
    /// (else `nil`).
    private func resolve(_ request: PlanRunRequest, running: Bool, progress: PlanProgressHandler?) async throws
        -> PlanResults? {
        let inputs = PlanRunInputs(request.library)
        /// The results of one run, which gets `share` of the request's bar.
        func step(_ plan: PlanDocument, _ kind: RunKind, focusAge: Int? = nil, share: ClosedRange<Double> = 0...1)
            async throws -> PlanResults? {
            let key = PlanRunCache.Key(plan: plan, inputs: inputs, kind: kind, focusAge: focusAge, asOf: request.asOf)
            if let cached = await cache.value(for: key) { return cached }
            guard running else { return nil }
            return try await results(for: key, library: request.library,
                                     progress: progress.map { Self.share($0, share, mode: request.mode) })
        }

        if let whatIf = request.whatIf, !whatIf.isEmpty {
            // Saving a month more (or less) is spending that much less while
            // working, so the plan's own saving is needed first.
            var baseSaving: Decimal?
            var share: ClosedRange<Double> = 0...1
            if whatIf.monthlySaving != nil {
                let cached = await isCached(request.plan, .base(request.mode), inputs: inputs, asOf: request.asOf)
                guard let base = try await step(request.plan, .base(request.mode), share: 0...0.5) else { return nil }
                baseSaving = base.details?.focus.monthlySaving
                if !cached { share = 0.5...1 }
            }
            let plan = whatIf.applied(to: request.plan, baseMonthlySaving: baseSaving)
            return try await step(plan, .base(request.mode), focusAge: request.focusAge, share: share)
        }
        if let focusAge = request.focusAge {
            let cached = await isCached(request.plan, .base(.full), inputs: inputs, asOf: request.asOf)
            // The full run scans every age; the focus age alone is a few.
            guard let base = try await step(request.plan, .base(.full), share: 0...0.9) else { return nil }
            if base.details?.focus.age == focusAge { return base }
            guard let focused = try await step(request.plan, .focus, focusAge: focusAge,
                                               share: cached ? 0...1 : 0.9...1) else { return nil }
            return base.withFocus(of: focused)
        }
        return try await step(request.plan, .base(request.mode))
    }

    private func isCached(_ plan: PlanDocument, _ kind: RunKind, inputs: PlanRunInputs, asOf: CalendarDate) async
        -> Bool {
        await cache.value(for: PlanRunCache.Key(plan: plan, inputs: inputs, kind: kind, focusAge: nil, asOf: asOf))
            != nil
    }

    /// `handler` for one run of a request: the Planner's progress, with the
    /// whole run's share mapped into `share` of the request's bar.
    static func share(_ handler: @escaping PlanProgressHandler, _ share: ClosedRange<Double>, mode: PlanRunMode)
        -> @Sendable (PlannerProgress) -> Void {
        { progress in
            handler(PlanRunProgress(
                phase: PlanRunProgress.Phase(progress.phase), completed: progress.completed, total: progress.total,
                fraction: share.lowerBound + (share.upperBound - share.lowerBound) * progress.fraction,
                ages: progress.ages, mode: mode))
        }
    }

    // MARK: Running

    /// What a run computes.
    enum RunKind: Hashable, Sendable {
        /// The whole answer: every age (full) or a refined grid (fast).
        case base(PlanRunMode)
        /// Only the details for one retirement age.
        case focus
    }

    /// The Planner's options for a run of `kind` starting on `asOf`.
    static func options(for kind: RunKind, focusAge: Int?, asOf: CalendarDate) -> PlannerOptions {
        switch kind {
        case .base(.full):
            PlannerOptions(mode: .full, ageScan: .full, focusAge: focusAge, today: asOf)
        case .base(.fast):
            PlannerOptions(mode: .fast(runs: PlannerOptions.defaultFastRuns), ageScan: .headline, focusAge: focusAge,
                           today: asOf)
        case .focus:
            // The fewest ages the Planner allows: today's, the plan's and the focus age. The
            // headline numbers (sustainable spending, what retiring today needs) stay the plan's.
            PlannerOptions(mode: .full, ageScan: .headline, focusAge: focusAge, maxRetirementAge: 0,
                           solveSustainableSpending: false, solveAssetsNeeded: false, today: asOf)
        }
    }

    /// Runs the Planner for `key` and keeps the results.
    private func results(for key: PlanRunCache.Key, library: Library,
                         progress: (@Sendable (PlannerProgress) -> Void)?) async throws -> PlanResults {
        try Task.checkCancellation()
        let result: PlanResult
        do {
            result = try await Planner.run(plan: key.plan, library: library, registry: registry,
                                           options: Self.options(for: key.kind, focusAge: key.focusAge, asOf: key.asOf),
                                           progress: progress)
        } catch let error as PlannerError {
            throw PlanEngineError.invalidPlan(Self.message(for: error))
        }
        try Task.checkCancellation()
        let mode: PlanRunMode = if case .base(let runMode) = key.kind { runMode } else { .full }
        let results = PlanResults(
            result: result, mode: mode, birthDate: library.settings.person?.birthDate ?? result.start.date,
            registry: registry, scansEveryAge: key.kind == .base(.full))
        await cache.insert(results, for: key)
        return results
    }

    /// Why a plan can't run, in one sentence per error.
    static func message(for error: PlannerError) -> String {
        let errors = error.issues.filter(\.isError).map(\.message)
        return errors.isEmpty ? "The plan can't run." : errors.joined(separator: " ")
    }

    // MARK: Validation

    /// The plan's problems without running it (`Planner.validate`), off the
    /// main actor: it takes about a tenth of a second.
    static func validate(_ plan: PlanDocument, library: Library, asOf: CalendarDate,
                         registry: TaxRegistry = AppTaxRegistry.standard) async -> [PlanIssue] {
        let task = Task.detached(priority: .userInitiated) {
            Planner.validate(plan: plan, library: library, registry: registry, options: PlannerOptions(today: asOf))
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

extension PlanRunProgress.Phase {
    /// The Planner's phase.
    init(_ phase: PlannerProgress.Phase) {
        switch phase {
        case .earliestAge: self = .earliestAge
        case .simulating: self = .simulating
        case .sustainableSpending: self = .sustainableSpending
        case .assetsNeeded: self = .assetsNeeded
        case .summarising: self = .summarising
        }
    }
}

/// The latest results of the engine, keyed by everything that goes into a
/// run. Holds at most `capacity` results; the oldest go first.
actor PlanRunCache {
    struct Key: Hashable, Sendable {
        var plan: PlanDocument
        var inputs: PlanRunInputs
        var kind: PlannerPlanEngine.RunKind
        var focusAge: Int?
        var asOf: CalendarDate
    }

    private let capacity: Int
    private var entries: [Key: PlanResults] = [:]
    private var order: [Key] = []

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    func value(for key: Key) -> PlanResults? {
        entries[key]
    }

    func insert(_ value: PlanResults, for key: Key) {
        if entries.updateValue(value, forKey: key) == nil {
            order.append(key)
        }
        while order.count > capacity {
            entries[order.removeFirst()] = nil
        }
    }

    var count: Int { entries.count }
}

extension PlanWhatIf {
    /// `plan` with these changes: the retirement age, retirement spending,
    /// the equity return, and saving per month, which moves spending while
    /// working by as much (a month's saving more is 12 × that less spent a
    /// year). Without `baseMonthlySaving`, a saving change can't be applied
    /// and is left out.
    func applied(to plan: PlanDocument, baseMonthlySaving: Decimal?) -> PlanDocument {
        var plan = plan
        if let retirementAge {
            plan.retirement.age = .age(retirementAge)
        }
        if let retiredSpending {
            plan.spending.retired = max(0, retiredSpending)
        }
        if let monthlySaving, let baseMonthlySaving {
            plan.spending.working = max(0, plan.spending.working - (monthlySaving - baseMonthlySaving) * 12)
        }
        if let equityReturn {
            let current = plan.assumptions.returnAssumption(for: .equity)
            plan.assumptions.returns[.equity] = ReturnAssumption(
                real: equityReturn, volatility: current?.volatility ?? Decimal(string: "0.17")!,
                incomeYield: current?.incomeYield)
        }
        return plan
    }
}
