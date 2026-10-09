import Foundation
import Model
import Planner

/// The parts of a library a plan run reads: settings (birth date, base
/// currency), accounts, instruments and history (valuations, prices, FX,
/// inflation). Plans, projections and import profiles are left out, so
/// saving a headline or a baseline doesn't make a plan run again.
struct PlanRunInputs: Hashable, Sendable {
    /// The settings without what the Planner never reads, which only the
    /// screens use: the main plan, the person's name and the inflation
    /// index actual values are adjusted with. So "Set as Main Plan" doesn't
    /// make every plan's results out of date.
    var settings: LibrarySettings
    var accounts: [AccountID: Account]
    var instruments: [InstrumentID: Instrument]
    var months: [YearMonth: MonthFile]

    init(_ library: Library) {
        var settings = library.settings
        settings.mainPlan = nil
        settings.person?.name = nil
        settings.inflationIndex = nil
        self.settings = settings
        accounts = library.accounts
        instruments = library.instruments
        months = library.months
    }
}

/// The `PlanEngine` the app uses: the Planner.
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
///   Results kept on the device from an earlier launch come back in through
///   ``remember(_:for:)``.
/// - **Progress.** The Planner's `PlannerProgress`, in a `PlanRunProgress`.
///   A request that needs two runs (a what-if's saving needs the plan's own
///   run first; a focus age needs the full run) shares the bar between them.
/// - **Cancellation.** Runs stop promptly when their task is cancelled
///   (`PlanStore` cancels a superseded run); cancelled runs aren't cached.
struct PlannerPlanEngine: PlanEngine {
    private let cache = PlanRunCache(capacity: 32)

    var version: String { Planner.engineVersion }

    func run(_ request: PlanRunRequest, progress: PlanProgressHandler?) async throws -> PlanResults {
        // Running never comes back empty.
        guard let results = try await resolve(request, running: true, progress: progress) else {
            throw CancellationError()
        }
        return results
    }

    func cachedResults(for request: PlanRunRequest) async -> PlanResults? {
        try? await resolve(request, running: false, progress: nil)
    }

    /// Keeps a plan's own results (no what-if, no other age), as its run
    /// would have.
    func remember(_ results: PlanResults, for request: PlanRunRequest) async {
        guard request.whatIf?.isEmpty ?? true, request.focusAge == nil else { return }
        await cache.insert(results, for: PlanRunCache.Key(plan: request.plan, inputs: PlanRunInputs(request.library),
                                                         kind: .base(request.mode), focusAge: nil,
                                                         asOf: request.asOf))
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
                baseSaving = base.details.focus.monthlySaving
                if !cached { share = 0.5...1 }
            }
            let plan = whatIf.applied(to: request.plan, baseMonthlySaving: baseSaving)
            return try await step(plan, .base(request.mode), focusAge: request.focusAge, share: share)
        }
        if let focusAge = request.focusAge {
            let cached = await isCached(request.plan, .base(.full), inputs: inputs, asOf: request.asOf)
            // The full run scans every age; the focus age alone is a few.
            guard let base = try await step(request.plan, .base(.full), share: 0...0.9) else { return nil }
            if base.details.focus.age == focusAge { return base }
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
            var progress = progress
            progress.fraction = share.lowerBound + (share.upperBound - share.lowerBound) * progress.fraction
            handler(PlanRunProgress(mode: mode, planner: progress))
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
            // With the coast age, which check-ins record, and the earliest
            // age without each uncertain windfall, for the plan's words.
            PlannerOptions(mode: .full, ageScan: .full, focusAge: focusAge, solveCoastAge: true,
                           solveWithoutWindfalls: true, today: asOf)
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
            result = try await Planner.run(plan: key.plan, library: library,
                                           options: Self.options(for: key.kind, focusAge: key.focusAge, asOf: key.asOf),
                                           progress: progress)
        } catch let error as PlannerError {
            throw PlanEngineError.invalidPlan(Self.message(for: error))
        }
        try Task.checkCancellation()
        let mode: PlanRunMode = if case .base(let runMode) = key.kind { runMode } else { .full }
        let results = PlanResults(result: result, mode: mode,
                                  birthDate: library.settings.person?.birthDate ?? result.start.date)
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
    static func validate(_ plan: PlanDocument, library: Library, asOf: CalendarDate) async -> [PlanIssue] {
        await Task.detached(priority: .userInitiated) {
            Planner.validate(plan: plan, library: library, options: PlannerOptions(today: asOf))
        }.value
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
}

extension PlanWhatIf {
    /// `plan` with these changes: the retirement age, retirement spending,
    /// equity's median return (its typical year, keeping its volatility and
    /// income yield; the default isn't written), and saving per month,
    /// which moves spending while working by as much (a month's saving more
    /// is 12 × that less spent a year). Without `baseMonthlySaving`, a
    /// saving change can't be applied and is left out.
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
            plan.assumptions.setReturnAssumption(ReturnAssumption(
                medianReal: equityReturn, volatility: current?.volatility ?? Decimal(string: "0.17")!,
                incomeYield: current?.incomeYield), for: .equity)
        }
        return plan
    }
}
