import Foundation
import Model
import Observation
import Planner
import Storage

/// Plan runs and their results (UI.md, "How it's built": runs, cached
/// results, progress, staleness).
///
/// The numbers come from a ``PlanEngine``; this store runs it off the main
/// thread, cancels a run when a newer one of the same kind starts, keeps
/// the latest results per plan with what they were computed from, and saves
/// headlines and baselines into the library. With the stub engine
/// (``UnavailablePlanEngine``) runs fail quietly and the Overview shows the
/// last recorded headline.
///
/// - **Nothing runs on its own.** A run starts only when asked: the Plan
///   screens' *Calculate*, *Recalculate* (⌘R) and *Run What-If* buttons,
///   saving a baseline without results, and a check-in recording its month's
///   answer (``recordCheckInAnswer(on:)``, caught up once the library is
///   loaded if it's missing: ``recordMissingCheckInAnswer(today:)``).
///   Opening a screen, editing a plan or a check-in elsewhere only makes
///   results out of date.
/// - **Out of date.** Each result keeps its ``PlanRunBasis``: the plan, the
///   library data a run reads, the start date, the what-if and focus age.
///   ``staleReasons(of:_:plan:whatIf:focusAge:)`` compares it with the plan
///   and library as they are now. ``adoptCached(_:modes:whatIf:focusAge:)``
///   picks up results the engine kept for exactly the current inputs.
/// - **Progress.** ``progress`` holds where each run in progress is
///   (`PlanRunProgress`), updated at most about ten times a second.
@Observable @MainActor
final class PlanStore {
    /// The latest full results per plan (without what-if changes).
    private(set) var results: [PlanID: PlanResults] = [:]
    /// The latest what-if results per plan.
    private(set) var whatIfResults: [PlanID: PlanResults] = [:]
    /// The latest results per plan for another retirement age than the
    /// plan's own (tapping an age on the success curve), without what-if
    /// changes. See ``run(_:mode:whatIf:focusAge:)``.
    private(set) var focusResults: [PlanID: PlanResults] = [:]
    /// What the results above were computed from, by plan and kind
    /// (`.base`, `.whatIf`, `.focus`).
    private(set) var bases: [PlanRunKey: PlanRunBasis] = [:]
    /// Plans with a run in progress.
    private(set) var running: Set<PlanID> = []
    /// Where each run in progress is, by plan and kind.
    private(set) var progress: [PlanRunKey: PlanRunProgress] = [:]
    /// Why the latest run of a plan failed.
    private(set) var errors: [PlanID: String] = [:]
    /// The answer the latest check-in is waiting for (UI.md, "After saving").
    private(set) var checkInAnswer: CheckInAnswerRun?

    /// The what-if each plan's screen was left with, so switching plans and
    /// coming back keeps it. Not saved.
    var whatIfs: [PlanID: PlanWhatIf] = [:]
    /// The retirement age each plan's charts were left on, when it isn't the plan's own.
    var focusAges: [PlanID: Int] = [:]

    let engine: any PlanEngine
    private let library: LibraryStore
    @ObservationIgnored private var tasks: [PlanRunKey: Task<PlanResults, any Error>] = [:]
    @ObservationIgnored private var tokens: [PlanRunKey: UUID] = [:]
    @ObservationIgnored private var signatures: [PlanRunKey: PlanRunBasis] = [:]
    /// The check-in each plan's missing answer was last caught up for
    /// (``recordMissingCheckInAnswer(today:)``), so it's tried once.
    @ObservationIgnored private var caughtUpAnswers: [PlanID: CalendarDate] = [:]

    init(library: LibraryStore, engine: any PlanEngine = UnavailablePlanEngine()) {
        self.library = library
        self.engine = engine
    }

    /// Whether plans can be run (`false` until the Planner is in).
    var isAvailable: Bool { engine.isAvailable }

    /// Whether any run of `plan` is in progress.
    func isRunning(_ plan: PlanID) -> Bool { running.contains(plan) }

    /// Whether a run of `plan` of `kind` is in progress.
    func isRunning(_ plan: PlanID, _ kind: PlanRunKey.Kind) -> Bool {
        tasks[PlanRunKey(plan: plan, kind: kind)] != nil
    }

    /// Where the run of `plan` of `kind` is, while it's in progress.
    func progress(of plan: PlanID, _ kind: PlanRunKey.Kind) -> PlanRunProgress? {
        progress[PlanRunKey(plan: plan, kind: kind)]
    }

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
    ///
    /// Only call it when the user asked for a run (or a check-in needs its
    /// answer): screens never run plans on their own.
    @discardableResult
    func run(_ plan: PlanID, mode: PlanRunMode = .full, whatIf: PlanWhatIf? = nil, focusAge: Int? = nil) async
        -> PlanResults? {
        await run(plan, mode: mode, whatIf: whatIf, focusAge: focusAge, checkIn: false)
    }

    private func run(_ plan: PlanID, mode: PlanRunMode, whatIf: PlanWhatIf?, focusAge: Int?, checkIn: Bool) async
        -> PlanResults? {
        guard let document = library.library.plans[plan] else { return nil }
        let whatIf = whatIf?.isEmpty == true ? nil : whatIf
        let slot = PlanRunKey.Kind.slot(whatIf: whatIf, focusAge: focusAge)
        let key = PlanRunKey(plan: plan, kind: checkIn ? .checkIn : slot)
        let signature = basis(document, mode: mode, whatIf: whatIf, focusAge: focusAge)
        // The very same request in progress, e.g. the Plan screen asking for
        // the main plan while a check-in's run of it is still going: join it.
        // A check-in joins only its own kind, which nothing else cancels.
        let candidates = checkIn ? [key] : [key, PlanRunKey(plan: plan, kind: .checkIn)]
        for candidate in candidates where signatures[candidate] == signature {
            guard let existing = tasks[candidate], let token = tokens[candidate] else { continue }
            do {
                let value = try await existing.value
                return tokens[candidate] == nil || tokens[candidate] == token ? value : nil
            } catch {
                return nil
            }
        }
        tasks[key]?.cancel()
        let request = PlanRunRequest(plan: document, library: library.library, mode: mode, whatIf: whatIf,
                                     asOf: library.asOfDate, focusAge: focusAge)
        let engine = engine
        let token = UUID()
        let report: PlanProgressHandler = { [weak self] value in
            Task { @MainActor in self?.receive(value, for: key, token: token) }
        }
        let task = Task { try await engine.run(request, progress: report) }
        tasks[key] = task
        tokens[key] = token
        signatures[key] = signature
        progress[key] = .starting(mode)
        running.insert(plan)
        defer {
            if tokens[key] == token {
                tasks[key] = nil
                tokens[key] = nil
                signatures[key] = nil
                progress[key] = nil
                if !tasks.keys.contains(where: { $0.plan == plan }) { running.remove(plan) }
            }
        }
        do {
            let value = try await task.value
            guard tokens[key] == token else { return nil }
            keep(value, in: PlanRunKey(plan: plan, kind: slot), basis: signature)
            errors[plan] = nil
            return value
        } catch is CancellationError {
            return nil
        } catch {
            if tokens[key] == token { errors[plan] = PlanStore.describe(error) }
            return nil
        }
    }

    /// A run's progress, if it's still the run in progress for `key`. Updates
    /// arrive in order; one that would move the bar back is dropped.
    private func receive(_ value: PlanRunProgress, for key: PlanRunKey, token: UUID) {
        guard tokens[key] == token else { return }
        if let current = progress[key], current.phase != .starting, value.fraction < current.fraction { return }
        progress[key] = value
    }

    /// Stores `value` as the latest results of `key` (`.base`, `.whatIf` or `.focus`).
    private func keep(_ value: PlanResults, in key: PlanRunKey, basis: PlanRunBasis) {
        switch key.kind {
        case .base, .checkIn: results[key.plan] = value
        case .whatIf: whatIfResults[key.plan] = value
        case .focus: focusResults[key.plan] = value
        }
        bases[PlanRunKey(plan: key.plan, kind: key.kind == .checkIn ? .base : key.kind)] = basis
    }

    /// Takes the results the engine kept for exactly the current plan,
    /// library, what-if and focus age, if it has them, without running
    /// anything (e.g. a plan edited and changed back, or a focus age shown
    /// before). Tries `modes` in order. Returns whether there were any.
    @discardableResult
    func adoptCached(_ plan: PlanID, modes: [PlanRunMode] = [.full], whatIf: PlanWhatIf? = nil,
                     focusAge: Int? = nil) async -> Bool {
        guard let document = library.library.plans[plan] else { return false }
        let whatIf = whatIf?.isEmpty == true ? nil : whatIf
        let key = PlanRunKey(plan: plan, kind: .slot(whatIf: whatIf, focusAge: focusAge))
        for mode in modes {
            let basis = basis(document, mode: mode, whatIf: whatIf, focusAge: focusAge)
            if bases[key] == basis { return true }
            let request = PlanRunRequest(plan: document, library: library.library, mode: mode, whatIf: whatIf,
                                         asOf: library.asOfDate, focusAge: focusAge)
            guard let cached = await engine.cachedResults(for: request) else { continue }
            // The plan or the library may have changed while looking, or a
            // newer look replaced this one.
            guard !Task.isCancelled, let now = library.library.plans[plan],
                  self.basis(now, mode: mode, whatIf: whatIf, focusAge: focusAge) == basis
            else { return false }
            keep(cached, in: key, basis: basis)
            return true
        }
        return false
    }

    /// Cancels the runs of `plan` of `kinds` in progress. By default every
    /// run the Plan screens start, not a check-in's (it records the month's
    /// answer).
    func cancel(_ plan: PlanID, kinds: Set<PlanRunKey.Kind> = [.base, .whatIf, .focus]) {
        for (key, task) in tasks where key.plan == plan && kinds.contains(key.kind) {
            task.cancel()
        }
    }

    /// Throws away the what-if results ("Reset").
    func clearWhatIf(_ plan: PlanID) {
        whatIfResults[plan] = nil
        bases[PlanRunKey(plan: plan, kind: .whatIf)] = nil
    }

    /// Cancels the what-if run of `plan` in progress, if any (after "Reset").
    func cancelWhatIf(_ plan: PlanID) {
        cancel(plan, kinds: [.whatIf])
    }

    /// Throws away the results for another focus age (back to the plan's own).
    func clearFocus(_ plan: PlanID) {
        focusResults[plan] = nil
        bases[PlanRunKey(plan: plan, kind: .focus)] = nil
    }

    // MARK: Out of date

    /// What the results of `plan` of `kind` were computed from.
    func basis(of plan: PlanID, _ kind: PlanRunKey.Kind) -> PlanRunBasis? {
        bases[PlanRunKey(plan: plan, kind: kind == .checkIn ? .base : kind)]
    }

    /// What a run of `document` would be computed from now.
    func basis(_ document: PlanDocument, mode: PlanRunMode = .full, whatIf: PlanWhatIf? = nil,
               focusAge: Int? = nil) -> PlanRunBasis {
        PlanRunBasis(plan: document, inputs: PlanRunInputs(library.library), mode: mode,
                     whatIf: whatIf?.isEmpty == true ? nil : whatIf, focusAge: focusAge, asOf: library.asOfDate)
    }

    /// Why the results of `plan` of `kind` don't fit `document` (by default
    /// the library's plan), the library as it is now, `whatIf` and
    /// `focusAge`; empty when they do, or when there are none.
    func staleReasons(of plan: PlanID, _ kind: PlanRunKey.Kind = .base, plan document: PlanDocument? = nil,
                      whatIf: PlanWhatIf? = nil, focusAge: Int? = nil) -> [PlanStaleReason] {
        guard let stored = basis(of: plan, kind), let document = document ?? library.library.plans[plan] else {
            return []
        }
        return stored.staleReasons(comparedWith: basis(document, mode: stored.mode, whatIf: whatIf,
                                                       focusAge: focusAge))
    }

    // MARK: Headlines

    /// The answer for the Overview's "Can I retire yet?" card: the main
    /// plan's latest results, or else its last recorded headline. Never
    /// starts a run.
    var mainHeadline: PlanHeadline? {
        guard let main = library.settings.mainPlan else { return nil }
        if let results = results[main] { return results.headline }
        return library.library.headlines(for: main).last.map { PlanHeadline(recorded: $0) }
    }

    /// The headlines recorded at check-ins for `plan`, oldest first.
    func recordedHeadlines(for plan: PlanID) -> [Headline] {
        library.library.headlines(for: plan)
    }

    /// After a check-in: starts the main plan's run that records this
    /// month's answer, and returns at once. ``checkInAnswer`` follows it: its
    /// progress is ``progress(of:_:)`` with `.checkIn`, then the headline.
    /// Nothing happens without a main plan or a planner.
    ///
    /// This is the one run that starts without a button: recording the
    /// month's answer is what a check-in is for. The confirmation says the
    /// app can be closed meanwhile, so on iOS the run and its writes ask for
    /// background time (``BackgroundActivity``); an answer that still didn't
    /// get recorded is caught up at the next launch
    /// (``recordMissingCheckInAnswer(today:)``).
    func recordCheckInAnswer(on date: CalendarDate) {
        guard isAvailable, let main = library.settings.mainPlan, library.library.plans[main] != nil else {
            checkInAnswer = nil
            return
        }
        let answer = CheckInAnswerRun(date: date, plan: main)
        checkInAnswer = answer
        let activity = BackgroundActivity(named: "Record this month's answer")
        Task { [weak self] in
            defer { activity.end() }
            guard let self else { return }
            let headline = await self.checkInSaved(on: date)
            guard self.checkInAnswer == answer else { return }
            self.checkInAnswer?.isRunning = false
            self.checkInAnswer?.headline = headline
            self.checkInAnswer?.error = headline == nil ? self.errors[main] : nil
        }
    }

    /// Records the main plan's answer for the latest check-in when it's
    /// missing: the app was closed or stopped before that check-in's run
    /// finished. The root view calls it once the library is loaded.
    ///
    /// It runs as ``recordCheckInAnswer(on:)`` does, at most once per plan
    /// and date while the app runs, so a plan that fails isn't run again
    /// and again. Nothing happens without a planner or a main plan, for a
    /// read-only library, when a headline on or after the latest check-in
    /// is recorded (also from the other device), or when the latest
    /// check-in is in the future (a typo).
    func recordMissingCheckInAnswer(today: CalendarDate = .today()) {
        guard isAvailable, library.canEdit, let main = library.settings.mainPlan, library.library.plans[main] != nil,
              let latest = library.latestCheckIn, latest <= today, checkInAnswer?.isRunning != true,
              !library.library.headlines(for: main).contains(where: { $0.date >= latest }),
              caughtUpAnswers[main] != latest
        else { return }
        caughtUpAnswers[main] = latest
        recordCheckInAnswer(on: latest)
    }

    /// After a check-in: re-runs the main plan, records its headline, saves
    /// the yearly baseline at the year's first check-in, waits for the
    /// writes, and returns the answer. `nil` without a main plan or a
    /// planner. The Plan screens can't cancel this run. A headline or
    /// baseline that can't be saved shows in the library's error
    /// (`LibraryStore.lastError`).
    func checkInSaved(on date: CalendarDate) async -> PlanHeadline? {
        guard let main = library.settings.mainPlan, let plan = library.library.plans[main],
              let results = await run(main, mode: .full, whatIf: nil, focusAge: nil, checkIn: true)
        else { return nil }
        do {
            try library.record(Self.headline(of: results, plan: plan, on: date), for: main)
        } catch {
            library.reportError("This month's answer couldn't be recorded. \(LibraryStore.describe(error))")
        }
        let hasYearly = library.library.baselines(for: main).contains { $0.kind == .yearly && $0.created.year == date.year }
        if !hasYearly {
            do {
                _ = try saveBaseline(for: main, label: "Start of \(date.year)", kind: .yearly, on: date)
            } catch PlanStoreError.noResults {
                // The plan changed during the run: the year's next check-in saves it.
            } catch {
                library.reportError("The baseline for \(date.year) couldn't be saved. \(LibraryStore.describe(error))")
            }
        }
        // A write that fails shows in lastError too.
        await library.waitForPendingWrites()
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
        let baseline = Baseline(
            created: date, kind: kind, label: label, engine: results.engine, accounts: results.accounts,
            headline: Self.headline(of: results, plan: document, on: date).summary,
            plan: try CanonicalJSON.json(encoding: document), start: results.start,
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

    /// The headline to record for `results` on `date`: the Planner's own
    /// (`PlanResult.headline`), so the app and the CLI write identical
    /// records. Results without one (the preview engine) are rounded here.
    static func headline(of results: PlanResults, plan: PlanDocument, on date: CalendarDate) -> Headline {
        if var headline = results.details?.headline {
            headline.date = date
            return headline
        }
        return Headline(
            date: date, confidence: decimal(results.headline.confidence), earliestAge: results.headline.earliestAge,
            engine: results.engine, fiProgress: results.headline.fiProgress.map { decimal($0) },
            planHash: results.planHash ?? hash(of: plan),
            readiness: results.headline.readiness.map { readinessDecimal($0) },
            successAtTarget: results.headline.successAtTarget.map { decimal($0) },
            taxParameters: results.taxParameters)
    }

    /// A share as a decimal with four places, for results without the
    /// Planner's headline.
    static func decimal(_ value: Double) -> Decimal {
        Decimal(wholeNumber: value * 10_000) / 10_000
    }

    /// A readiness as a decimal with two places, rounded down as the
    /// Planner records it, so a recorded 1 means retiring today works.
    static func readinessDecimal(_ value: Double) -> Decimal {
        Decimal(wholeNumber: value * 100 + 1e-9, rounding: .down) / 100
    }

    static func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}

/// A plan and a kind of run. Runs of the same key replace each other, and
/// each kind keeps its own results.
struct PlanRunKey: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// The plan as it is: ``PlanStore/results``.
        case base
        /// With what-if changes: ``PlanStore/whatIfResults``.
        case whatIf
        /// The charts for another retirement age: ``PlanStore/focusResults``.
        case focus
        /// After a check-in, recording the month's answer: its results are
        /// the plan's own (`.base`), but the Plan screens don't cancel it.
        case checkIn

        /// Where results with `whatIf` and `focusAge` go.
        static func slot(whatIf: PlanWhatIf?, focusAge: Int?) -> Kind {
            whatIf != nil ? .whatIf : focusAge != nil ? .focus : .base
        }
    }

    var plan: PlanID
    var kind: Kind
}

/// Everything a run depends on: the plan, the library data it reads, the
/// start date, the mode, the what-if and the focus age. Results keep the
/// basis they were computed from, so a screen can tell when they no
/// longer fit (``staleReasons(comparedWith:)``), and an identical request
/// joins the run in progress instead of cancelling it.
struct PlanRunBasis: Equatable, Sendable {
    var plan: PlanDocument
    var inputs: PlanRunInputs
    var mode: PlanRunMode
    var whatIf: PlanWhatIf?
    var focusAge: Int?
    var asOf: CalendarDate

    /// Why results computed from this basis don't fit `current`, most
    /// important first; empty when they do. The mode doesn't count (a quick
    /// estimate is still for the same inputs), and neither does the plan's
    /// name.
    func staleReasons(comparedWith current: PlanRunBasis) -> [PlanStaleReason] {
        var reasons: [PlanStaleReason] = []
        var own = plan
        own.name = current.plan.name
        if own != current.plan { reasons.append(.plan) }
        if inputs != current.inputs || asOf != current.asOf { reasons.append(.library) }
        if whatIf != current.whatIf { reasons.append(.whatIf) }
        if focusAge != current.focusAge { reasons.append(.focusAge) }
        return reasons
    }
}

/// Why results are out of date (UI.md, "Out of date").
enum PlanStaleReason: String, CaseIterable, Hashable, Sendable {
    /// The plan's inputs changed.
    case plan
    /// The library data the plan reads changed: a check-in, prices, accounts.
    case library
    /// The what-if sliders moved.
    case whatIf
    /// Another retirement age was chosen for the charts.
    case focusAge
}

/// The run a saved check-in waits for, to show its progress and then the
/// month's answer in the confirmation.
struct CheckInAnswerRun: Hashable, Sendable {
    var date: CalendarDate
    var plan: PlanID
    var isRunning = true
    /// The answer, once it's there.
    var headline: PlanHeadline?
    /// Why the plan couldn't run.
    var error: String?
}

enum PlanStoreError: Error, Equatable, Sendable, LocalizedError {
    /// There are no full results to save yet.
    case noResults

    var errorDescription: String? {
        switch self {
        case .noResults: "Calculate the plan first: there are no results to save."
        }
    }
}
