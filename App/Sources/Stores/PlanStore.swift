import Foundation
import Model
import Observation
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
    /// Plans with a run in progress.
    private(set) var running: Set<PlanID> = []
    /// Why the latest run of a plan failed.
    private(set) var errors: [PlanID: String] = [:]

    let engine: any PlanEngine
    private let library: LibraryStore
    @ObservationIgnored private var tasks: [RunKey: Task<PlanResults, any Error>] = [:]
    @ObservationIgnored private var tokens: [RunKey: UUID] = [:]
    @ObservationIgnored private var scheduled: [PlanID: Task<Void, Never>] = [:]

    private struct RunKey: Hashable {
        var plan: PlanID
        var isWhatIf: Bool
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
    /// ``errors``). A run in progress for the same plan (and the same kind:
    /// with or without what-if) is cancelled first.
    @discardableResult
    func run(_ plan: PlanID, mode: PlanRunMode = .full, whatIf: PlanWhatIf? = nil) async -> PlanResults? {
        guard let document = library.library.plans[plan] else { return nil }
        let whatIf = whatIf?.isEmpty == true ? nil : whatIf
        let key = RunKey(plan: plan, isWhatIf: whatIf != nil)
        tasks[key]?.cancel()
        let request = PlanRunRequest(plan: document, library: library.library, mode: mode, whatIf: whatIf,
                                     asOf: library.asOfDate)
        let engine = engine
        let task = Task { try await engine.run(request) }
        let token = UUID()
        tasks[key] = task
        tokens[key] = token
        running.insert(plan)
        defer {
            if tokens[key] == token {
                tasks[key] = nil
                tokens[key] = nil
                running.remove(plan)
            }
        }
        do {
            let value = try await task.value
            guard tokens[key] == token else { return nil }
            if whatIf == nil {
                results[plan] = value
            } else {
                whatIfResults[plan] = value
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
    func scheduleRun(_ plan: PlanID, mode: PlanRunMode = .full, whatIf: PlanWhatIf? = nil,
                     after delay: Duration = .milliseconds(300)) {
        scheduled[plan]?.cancel()
        scheduled[plan] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.run(plan, mode: mode, whatIf: whatIf)
        }
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
            planHash: Self.hash(of: plan), successAtTarget: results.headline.successAtTarget.map { Self.decimal($0) },
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
        guard let results = results[plan], results.mode == .full, let document = library.library.plans[plan] else {
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

    /// A short hash of a plan's inputs (`planHash` in headlines): FNV-1a over
    /// its canonical JSON, as 8 hex digits.
    static func hash(of plan: PlanDocument) -> String {
        let bytes = (try? CanonicalJSON.data(encoding: plan)) ?? Data()
        var hash: UInt32 = 2_166_136_261
        for byte in bytes {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 8 - hex.count) + hex
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
