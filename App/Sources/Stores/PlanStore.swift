import Foundation
import Model
import Observation
import Planner
import Storage

/// Plan runs and their results (UI.md, "How it's built": runs, cached
/// results, recompute scheduling).
///
/// The numbers come from a ``PlanEngine``; this store runs it off the main
/// thread, cancels a run when a newer one for the same plan starts, keeps
/// the latest results per plan, and saves headlines and baselines into the
/// library. With the stub engine (``UnavailablePlanEngine``) runs fail
/// quietly and the Overview shows the last recorded headline.
@Observable @MainActor
final class PlanStore {
    /// The latest full results per plan (without what-if changes).
    private(set) var results: [PlanID: PlanResults] = [:]
    /// The latest what-if results per plan, while the sliders are in use.
    private(set) var whatIfResults: [PlanID: PlanResults] = [:]
    /// The latest results per plan for another retirement age than the
    /// plan's own (tapping an age on the success curve), without what-if
    /// changes. See ``run(_:mode:whatIf:focusAge:)``.
    private(set) var focusResults: [PlanID: PlanResults] = [:]
    /// Plans with a run in progress.
    private(set) var running: Set<PlanID> = []
    /// Why the latest run of a plan failed.
    private(set) var errors: [PlanID: String] = [:]

    let engine: any PlanEngine
    private let library: LibraryStore
    @ObservationIgnored private var tasks: [RunKey: Task<PlanResults, any Error>] = [:]
    @ObservationIgnored private var tokens: [RunKey: UUID] = [:]
    @ObservationIgnored private var signatures: [RunKey: RunSignature] = [:]
    @ObservationIgnored private var scheduled: [PlanID: Task<Void, Never>] = [:]

    /// Runs of the same plan and kind replace each other.
    private struct RunKey: Hashable {
        enum Kind: Hashable {
            case base
            case whatIf
            case focus
        }

        var plan: PlanID
        var kind: Kind
    }

    /// Everything a run depends on: an identical request joins the run in
    /// progress instead of cancelling it (e.g. the Plan screen asking for
    /// the main plan while a check-in's run of it is still going).
    private struct RunSignature: Equatable {
        var plan: PlanDocument
        var inputs: PlanRunInputs
        var mode: PlanRunMode
        var whatIf: PlanWhatIf?
        var focusAge: Int?
        var asOf: CalendarDate
    }

    init(library: LibraryStore, engine: any PlanEngine = UnavailablePlanEngine()) {
        self.library = library
        self.engine = engine
    }

    /// Whether plans can be run (`false` until the Planner is in).
    var isAvailable: Bool { engine.isAvailable }

    func isRunning(_ plan: PlanID) -> Bool { running.contains(plan) }

    // MARK: Running

    /// Runs `plan` on the current library and returns its results, or `nil`
    /// if it was cancelled, superseded by a newer run, or failed (see
    /// ``errors``). A run in progress for the same plan and the same kind
    /// (plain, with what-if changes, or for another focus age) is cancelled
    /// first, unless it's the very same request, which is joined instead.
    ///
    /// - `whatIf`: results go to ``whatIfResults``.
    /// - `focusAge` without `whatIf`: the charts for that retirement age, in
    ///   ``focusResults``. With `whatIf`, the what-if run is for that age.
    @discardableResult
    func run(_ plan: PlanID, mode: PlanRunMode = .full, whatIf: PlanWhatIf? = nil, focusAge: Int? = nil) async
        -> PlanResults? {
        guard let document = library.library.plans[plan] else { return nil }
        let whatIf = whatIf?.isEmpty == true ? nil : whatIf
        let kind: RunKey.Kind = whatIf != nil ? .whatIf : focusAge != nil ? .focus : .base
        let key = RunKey(plan: plan, kind: kind)
        let signature = RunSignature(plan: document, inputs: PlanRunInputs(library.library), mode: mode,
                                     whatIf: whatIf, focusAge: focusAge, asOf: library.asOfDate)
        if let existing = tasks[key], let token = tokens[key], signatures[key] == signature {
            do {
                let value = try await existing.value
                return tokens[key] == nil || tokens[key] == token ? value : nil
            } catch {
                return nil
            }
        }
        tasks[key]?.cancel()
        let request = PlanRunRequest(plan: document, library: library.library, mode: mode, whatIf: whatIf,
                                     asOf: library.asOfDate, focusAge: focusAge)
        let engine = engine
        let task = Task { try await engine.run(request) }
        let token = UUID()
        tasks[key] = task
        tokens[key] = token
        signatures[key] = signature
        running.insert(plan)
        defer {
            if tokens[key] == token {
                tasks[key] = nil
                tokens[key] = nil
                signatures[key] = nil
                if !tasks.keys.contains(where: { $0.plan == plan }) { running.remove(plan) }
            }
        }
        do {
            let value = try await task.value
            guard tokens[key] == token else { return nil }
            switch kind {
            case .base: results[plan] = value
            case .whatIf: whatIfResults[plan] = value
            case .focus: focusResults[plan] = value
            }
            errors[plan] = nil
            return value
        } catch is CancellationError {
            return nil
        } catch {
            if tokens[key] == token { errors[plan] = PlanStore.describe(error) }
            return nil
        }
    }

    /// Runs `plan` after `delay`, unless another request for it comes first:
    /// for recomputing while a plan is edited.
    func scheduleRun(_ plan: PlanID, mode: PlanRunMode = .full, whatIf: PlanWhatIf? = nil, focusAge: Int? = nil,
                     after delay: Duration = .milliseconds(300)) {
        scheduled[plan]?.cancel()
        scheduled[plan] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.run(plan, mode: mode, whatIf: whatIf, focusAge: focusAge)
        }
    }

    /// Whether a run of `plan` with what-if changes is in progress.
    func isRunningWhatIf(_ plan: PlanID) -> Bool {
        tasks[RunKey(plan: plan, kind: .whatIf)] != nil
    }

    /// Whether a run of `plan` for another focus age is in progress.
    func isRunningFocus(_ plan: PlanID) -> Bool {
        tasks[RunKey(plan: plan, kind: .focus)] != nil
    }

    /// Cancels every run of `plan` in progress or scheduled.
    func cancel(_ plan: PlanID) {
        scheduled[plan]?.cancel()
        scheduled[plan] = nil
        for (key, task) in tasks where key.plan == plan {
            task.cancel()
        }
    }

    /// Throws away the what-if results ("Reset").
    func clearWhatIf(_ plan: PlanID) {
        whatIfResults[plan] = nil
    }

    /// Throws away the results for another focus age (back to the plan's own).
    func clearFocus(_ plan: PlanID) {
        focusResults[plan] = nil
    }

    // MARK: Headlines

    /// The answer for the Overview's "Can I retire yet?" card: the main
    /// plan's latest results, or else its last recorded headline.
    var mainHeadline: PlanHeadline? {
        guard let main = library.settings.mainPlan else { return nil }
        if let results = results[main] { return results.headline }
        return library.library.headlines(for: main).last.map { PlanHeadline(recorded: $0) }
    }

    /// The headlines recorded at check-ins for `plan`, oldest first.
    func recordedHeadlines(for plan: PlanID) -> [Headline] {
        library.library.headlines(for: plan)
    }

    /// After a check-in: re-runs the main plan, records its headline, saves
    /// the yearly baseline at the year's first check-in, and returns the
    /// answer for the confirmation. `nil` without a main plan or a planner.
    func checkInSaved(on date: CalendarDate) async -> PlanHeadline? {
        guard let main = library.settings.mainPlan, let plan = library.library.plans[main],
              let results = await run(main, mode: .full)
        else { return nil }
        let headline = Headline(
            date: date, confidence: Self.decimal(results.headline.confidence), earliestAge: results.headline.earliestAge,
            engine: results.engine, fiProgress: results.headline.fiProgress.map { Self.decimal($0) },
            planHash: results.planHash ?? Self.hash(of: plan),
            successAtTarget: results.headline.successAtTarget.map { Self.decimal($0) },
            taxParameters: results.taxParameters)
        try? library.record(headline, for: main)
        let hasYearly = library.library.baselines(for: main).contains { $0.kind == .yearly && $0.created.year == date.year }
        if !hasYearly {
            _ = try? saveBaseline(for: main, label: "Start of \(date.year)", kind: .yearly, on: date)
        }
        return results.headline
    }

    // MARK: Baselines

    /// Saves the plan's latest full results as a baseline (PROGRESS.md,
    /// "Baselines") and returns its ID.
    @discardableResult
    func saveBaseline(for plan: PlanID, label: String?, kind: BaselineKind = .manual,
                      on date: CalendarDate = .today()) throws -> BaselineID {
        guard let results = results[plan], results.mode == .full, let document = library.library.plans[plan],
              results.planHash == nil || results.planHash == Self.hash(of: document)
        else {
            throw PlanStoreError.noResults
        }
        let headline = HeadlineSummary(
            confidence: Self.decimal(results.headline.confidence), earliestAge: results.headline.earliestAge,
            successAtTarget: results.headline.successAtTarget.map { Self.decimal($0) },
            fiProgress: results.headline.fiProgress.map { Self.decimal($0) })
        let baseline = Baseline(
            created: date, kind: kind, label: label, engine: results.engine, accounts: results.accounts,
            headline: headline, plan: try CanonicalJSON.json(encoding: document), start: results.start,
            taxParameters: results.taxParameters, years: results.years)
        return try library.saveBaseline(baseline, for: plan)
    }

    // MARK: Helpers

    /// A hash of a plan's inputs (`planHash` in headlines): the Planner's
    /// (FNV-1a, 64-bit, of its canonical JSON, as 16 hex digits), so
    /// headlines recorded here match the results' and PLANNER.md.
    static func hash(of plan: PlanDocument) -> String {
        Planner.planHash(plan)
    }

    /// A share as a decimal with four places, for the files.
    static func decimal(_ value: Double) -> Decimal {
        Decimal(Int((value * 10_000).rounded())) / 10_000
    }

    static func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}

enum PlanStoreError: Error, Equatable, Sendable, LocalizedError {
    /// There are no full results to save yet.
    case noResults

    var errorDescription: String? {
        switch self {
        case .noResults: "Run the plan first: there are no results to save."
        }
    }
}
