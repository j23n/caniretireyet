import Foundation
import Model
import Planner
import TaxGeneric
import TaxItaly
import TaxKit

/// The tax systems the app knows, registered in one place (TAXES.md,
/// "Adding a system": registering a new one is this one line). The plan
/// editor reads regimes, options and pension schemes from the same registry.
enum AppTaxRegistry {
    /// Italy (`it`) and the generic flat-rate system (`generic`).
    static let standard = TaxRegistry([ItalyTaxSystem(), GenericTaxSystem()])
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
///   it was, doesn't run again.
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
        let inputs = PlanRunInputs(request.library)
        if let whatIf = request.whatIf, !whatIf.isEmpty {
            // Saving a month more (or less) is spending that much less while
            // working, so the plan's own saving is needed first.
            var baseSaving: Decimal?
            if whatIf.monthlySaving != nil {
                let base = try await results(for: request.plan, request: request, inputs: inputs,
                                             kind: .base(request.mode))
                baseSaving = base.details?.focus.monthlySaving
            }
            let plan = whatIf.applied(to: request.plan, baseMonthlySaving: baseSaving)
            return try await results(for: plan, request: request, inputs: inputs,
                                     kind: .base(request.mode), focusAge: request.focusAge)
        }
        if let focusAge = request.focusAge {
            let base = try await results(for: request.plan, request: request, inputs: inputs, kind: .base(.full))
            if base.details?.focus.age == focusAge { return base }
            let focused = try await results(for: request.plan, request: request, inputs: inputs, kind: .focus,
                                            focusAge: focusAge)
            return base.withFocus(of: focused)
        }
        return try await results(for: request.plan, request: request, inputs: inputs, kind: .base(request.mode))
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
            // The fewest ages the Planner allows: today's, the plan's and the focus age.
            PlannerOptions(mode: .full, ageScan: .headline, focusAge: focusAge, maxRetirementAge: 0,
                           solveSustainableSpending: false, today: asOf)
        }
    }

    private func results(for plan: PlanDocument, request: PlanRunRequest, inputs: PlanRunInputs, kind: RunKind,
                         focusAge: Int? = nil) async throws -> PlanResults {
        let key = PlanRunCache.Key(plan: plan, inputs: inputs, kind: kind, focusAge: focusAge, asOf: request.asOf)
        if let cached = await cache.value(for: key) { return cached }
        try Task.checkCancellation()
        let result: PlanResult
        do {
            result = try await Planner.run(plan: plan, library: request.library, registry: registry,
                                           options: Self.options(for: kind, focusAge: focusAge, asOf: request.asOf))
        } catch let error as PlannerError {
            throw PlanEngineError.invalidPlan(Self.message(for: error))
        }
        try Task.checkCancellation()
        let mode: PlanRunMode = if case .base(let runMode) = kind { runMode } else { .full }
        let results = PlanResults(
            result: result, mode: mode, birthDate: request.library.settings.person?.birthDate ?? result.start.date,
            registry: registry, scansEveryAge: kind == .base(.full))
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
            let volatility = plan.assumptions.returnAssumption(for: .equity)?.volatility ?? Decimal(string: "0.17")!
            plan.assumptions.returns[.equity] = ReturnAssumption(real: equityReturn, volatility: volatility)
        }
        return plan
    }
}
