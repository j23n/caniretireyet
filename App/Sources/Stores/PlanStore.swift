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
/// the latest results per plan and kind with what they were computed from
/// (``slots``), and saves headlines and baselines into the library.
///
/// - **Nothing runs on its own.** A run starts only when asked: the Plan
///   screens' *Calculate*, *Recalculate* (⌘R) and *Run What-If* buttons,
///   saving a baseline without results, and a check-in recording its month's
///   answer (``recordCheckInAnswer(on:)``, caught up once the library is
///   loaded if it's missing: ``recordMissingCheckInAnswer(today:)``). Two
///   moments record an answer the same way, because the answer is what the
///   person is there for: the end of first launch's tour, and the import
///   after it that gives the plan its first answer or replaces the starting
///   estimates (UI.md, "Empty states and first launch"). Opening a screen,
///   editing a plan or a check-in elsewhere only makes results out of date.
/// - **What if and focus age.** Each plan's what-if and the retirement age
///   its charts are for live here, so switching plans and coming back keeps
///   them; the Plan screen's `PlanSession` reads and sets them here.
/// - **Out of date.** Each result keeps its ``PlanRunBasis``: the plan, the
///   library data a run reads, the start date, the what-if and focus age.
///   ``staleReasons(of:_:plan:)`` compares it with the plan and library as
///   they are now. ``lookUp(_:_:modes:)`` picks up results the engine kept
///   for exactly the current inputs.
/// - **In the base currency.** Results calculated in another base currency
///   than the library's (before it changed) aren't shown: the plan is
///   calculated again on request.
/// - **Progress.** ``progress`` holds where each run in progress is
///   (`PlanRunProgress`), updated at most about ten times a second.
/// - **Kept on the device.** Each plan's own results are written to the
///   ``archive`` after every run, and shown again when the library next
///   opens (``restoreKeptResults()``): up to date when the plan and the
///   library data it reads are as they were, else out of date.
@Observable @MainActor
final class PlanStore {
    /// The latest results of each plan and kind of run (`.base`, `.whatIf`,
    /// `.focus`; a check-in's are `.base`), with what they were computed
    /// from. Read them with ``results(of:_:)``, which leaves out results in
    /// another currency.
    private var slots: [PlanRunKey: PlanSlot] = [:]
    /// Plans with a run in progress.
    private(set) var running: Set<PlanID> = []
    /// Where each run in progress is, by plan and kind.
    private(set) var progress: [PlanRunKey: PlanRunProgress] = [:]
    /// Why the latest run of a plan failed.
    private(set) var errors: [PlanID: String] = [:]
    /// The answer the latest check-in is waiting for (UI.md, "After saving").
    private(set) var checkInAnswer: CheckInAnswerRun?
    /// The what-if each plan's screen was left with, never empty. Not saved.
    private var whatIfs: [PlanID: PlanWhatIf] = [:]
    /// The retirement age each plan's charts were left on, when it isn't the plan's own.
    private var focusAges: [PlanID: Int] = [:]

    let engine: any PlanEngine
    /// Where each plan's latest results are kept between launches; `nil`
    /// keeps nothing (previews, tests).
    let archive: PlanResultsArchive?
    private let library: LibraryStore
    /// The runs in progress, by plan and kind.
    @ObservationIgnored private var inFlight: [PlanRunKey: InFlight] = [:]
    /// A plan's years and milestones reached, worked out once for each
    /// state of the library (``planProgress(of:document:)``).
    @ObservationIgnored private let progressMemo = PlanProgressMemo()
    /// The check-in each plan's missing answer was last caught up for
    /// (``recordMissingCheckInAnswer(today:)``), so it's tried once.
    @ObservationIgnored private var caughtUpAnswers: [PlanID: CalendarDate] = [:]
    /// The library whose kept results were restored, so it's done once per library opened.
    @ObservationIgnored private var restoredLibrary: URL?
    /// What names a library kept in memory, which has no folder, for the
    /// ``archive``: the screen tests' (App/ScreenTests). `nil` keeps nothing for it.
    @ObservationIgnored var inMemoryLibrary: URL?
    /// The latest write to the ``archive``: writes wait for the one before,
    /// so an older result never replaces a newer one.
    @ObservationIgnored private var archiving: Task<Void, Never>?

    init(library: LibraryStore, engine: any PlanEngine, archive: PlanResultsArchive? = nil) {
        self.library = library
        self.engine = engine
        self.archive = archive
    }

    /// A run in progress: its task, a token that tells it from a newer run
    /// of the same plan and kind, and what it runs, so the very same request
    /// joins it.
    private struct InFlight {
        var task: Task<PlanResults, any Error>
        var token: UUID
        var basis: PlanRunBasis
    }

    // MARK: Results

    /// The latest results of `plan` of `kind`; `nil` when there are none,
    /// or when they're in another currency than the library's base currency.
    func results(of plan: PlanID, _ kind: PlanRunKey.Kind = .base) -> PlanResults? {
        slot(plan, kind)?.results
    }

    private func slot(_ plan: PlanID, _ kind: PlanRunKey.Kind) -> PlanSlot? {
        guard let slot = slots[PlanRunKey(plan: plan, kind: kind.slot)],
              slot.results.currency == library.settings.baseCurrency
        else { return nil }
        return slot
    }

    /// Whether any run of `plan` is in progress.
    func isRunning(_ plan: PlanID) -> Bool { running.contains(plan) }

    /// Whether a run of `plan` of `kind` is in progress.
    func isRunning(_ plan: PlanID, _ kind: PlanRunKey.Kind) -> Bool {
        inFlight[PlanRunKey(plan: plan, kind: kind)] != nil
    }

    /// Where the run of `plan` of `kind` is, while it's in progress.
    func progress(of plan: PlanID, _ kind: PlanRunKey.Kind) -> PlanRunProgress? {
        progress[PlanRunKey(plan: plan, kind: kind)]
    }

    // MARK: What if and focus age

    /// The what-if on top of `plan`; empty without one.
    func whatIf(of plan: PlanID) -> PlanWhatIf {
        whatIfs[plan] ?? PlanWhatIf()
    }

    /// The retirement age `plan`'s charts are for, when it isn't the plan's own.
    func focusAge(of plan: PlanID) -> Int? {
        focusAges[plan]
    }

    /// Sets `plan`'s what-if. Nothing runs. An empty one throws the
    /// what-if's results away and stops its run ("Reset").
    func setWhatIf(_ whatIf: PlanWhatIf, for plan: PlanID) {
        guard !whatIf.isEmpty else {
            whatIfs[plan] = nil
            slots[PlanRunKey(plan: plan, kind: .whatIf)] = nil
            cancel(plan, kinds: [.whatIf])
            return
        }
        whatIfs[plan] = whatIf
    }

    /// Sets the retirement age `plan`'s charts are for. Nothing runs.
    /// `nil`, the plan's own, throws the other age's results away.
    func setFocusAge(_ age: Int?, for plan: PlanID) {
        focusAges[plan] = age
        if age == nil { slots[PlanRunKey(plan: plan, kind: .focus)] = nil }
    }

    /// The what-if and the focus age a run of `plan` of `kind` is for.
    private func inputs(of plan: PlanID, _ kind: PlanRunKey.Kind) -> (whatIf: PlanWhatIf?, focusAge: Int?) {
        switch kind {
        case .base, .checkIn: (nil, nil)
        case .whatIf: (whatIfs[plan], focusAges[plan])
        case .focus: (nil, focusAges[plan])
        }
    }

    // MARK: Running

    /// Runs `plan` on the current library and returns its results, or `nil`
    /// if it was cancelled, superseded by a newer run, or failed (see
    /// ``errors``). A run in progress for the same plan and the same kind is
    /// cancelled first, unless it's the very same request, which is joined
    /// instead.
    ///
    /// - `.base`: the plan as it is.
    /// - `.whatIf`: with the plan's what-if (``whatIf(of:)``), for its
    ///   focus age; nothing without a what-if.
    /// - `.focus`: the charts for the plan's focus age (``focusAge(of:)``);
    ///   nothing without one.
    /// - `.checkIn`: the plan as it is, recording the month's answer
    ///   (``checkInSaved(on:)``); the Plan screens don't cancel it.
    ///
    /// Only call it when the user asked for a run (or a check-in needs its
    /// answer): screens never run plans on their own.
    @discardableResult
    func run(_ plan: PlanID, _ kind: PlanRunKey.Kind = .base, mode: PlanRunMode = .full) async -> PlanResults? {
        guard let document = library.library.plans[plan] else { return nil }
        let (whatIf, focusAge) = inputs(of: plan, kind)
        if kind == .whatIf && whatIf == nil || kind == .focus && focusAge == nil { return nil }
        let key = PlanRunKey(plan: plan, kind: kind)
        let signature = basis(document, mode: mode, whatIf: whatIf, focusAge: focusAge)
        // The very same request in progress, e.g. the Plan screen asking for
        // the main plan while a check-in's run of it is still going: join it.
        // A check-in joins only its own kind, which nothing else cancels.
        let candidates = kind == .checkIn ? [key] : [key, PlanRunKey(plan: plan, kind: .checkIn)]
        for candidate in candidates {
            guard let existing = inFlight[candidate], existing.basis == signature else { continue }
            do {
                let value = try await existing.task.value
                let current = inFlight[candidate]?.token
                return current == nil || current == existing.token ? value : nil
            } catch {
                return nil
            }
        }
        inFlight[key]?.task.cancel()
        let request = PlanRunRequest(plan: document, library: library.library, mode: mode, whatIf: whatIf,
                                     asOf: library.asOfDate, focusAge: focusAge)
        let libraryURL = keptLibrary
        let engine = engine
        let token = UUID()
        let report: PlanProgressHandler = { [weak self] value in
            Task { @MainActor in self?.receive(value, for: key, token: token) }
        }
        let task = Task { try await engine.run(request, progress: report) }
        inFlight[key] = InFlight(task: task, token: token, basis: signature)
        progress[key] = .starting(mode)
        running.insert(plan)
        defer {
            if inFlight[key]?.token == token {
                inFlight[key] = nil
                progress[key] = nil
                if !inFlight.keys.contains(where: { $0.plan == plan }) { running.remove(plan) }
            }
        }
        do {
            let value = try await task.value
            guard inFlight[key]?.token == token else { return nil }
            slots[PlanRunKey(plan: plan, kind: kind.slot)] = PlanSlot(results: value, basis: signature)
            if kind.slot == .base { keepOnDevice(value, basis: signature, library: libraryURL) }
            errors[plan] = nil
            return value
        } catch is CancellationError {
            return nil
        } catch {
            if inFlight[key]?.token == token { errors[plan] = PlanStore.describe(error) }
            return nil
        }
    }

    /// A run's progress, if it's still the run in progress for `key`. Updates
    /// arrive in order; one that would move the bar back is dropped.
    private func receive(_ value: PlanRunProgress, for key: PlanRunKey, token: UUID) {
        guard inFlight[key]?.token == token else { return }
        if let current = progress[key], current.planner != nil, value.fraction < current.fraction { return }
        progress[key] = value
    }

    /// Takes the results the engine kept for exactly the current plan,
    /// library, what-if and focus age of `kind`, if it has them, without
    /// running anything (e.g. a plan edited and changed back, or a focus age
    /// shown before). Tries `modes` in order. Returns whether there were any.
    @discardableResult
    func lookUp(_ plan: PlanID, _ kind: PlanRunKey.Kind = .base, modes: [PlanRunMode] = [.full]) async -> Bool {
        guard let document = library.library.plans[plan] else { return false }
        let (whatIf, focusAge) = inputs(of: plan, kind)
        if kind == .whatIf && whatIf == nil || kind == .focus && focusAge == nil { return false }
        let key = PlanRunKey(plan: plan, kind: kind.slot)
        for mode in modes {
            let basis = basis(document, mode: mode, whatIf: whatIf, focusAge: focusAge)
            if slots[key]?.basis == basis { return true }
            let request = PlanRunRequest(plan: document, library: library.library, mode: mode, whatIf: whatIf,
                                         asOf: library.asOfDate, focusAge: focusAge)
            guard let cached = await engine.cachedResults(for: request) else { continue }
            // The plan or the library may have changed while looking, or a
            // newer look replaced this one.
            guard !Task.isCancelled, let now = library.library.plans[plan],
                  self.basis(now, mode: mode, whatIf: whatIf, focusAge: focusAge) == basis
            else { return false }
            slots[key] = PlanSlot(results: cached, basis: basis)
            return true
        }
        return false
    }

    // MARK: Kept on the device

    /// Shows each plan's results kept on this device (``archive``) once its
    /// library is open, as if they'd just been calculated: up to date when
    /// the plan and the library data it reads are as they were, else out of
    /// date for that reason (``staleReasons(of:_:plan:)``). Results this
    /// session already has win. Results whose library data is the same are
    /// also handed to the engine, so going back to exactly them later finds
    /// them (``lookUp(_:_:modes:)``). Once per library opened, when the
    /// library is loaded (`AppModel`).
    func restoreKeptResults() async {
        guard let archive, let url = keptLibrary, restoredLibrary != url else { return }
        restoredLibrary = url
        let snapshot = library.library
        let restored = await archive.restore(forLibraryAt: url, library: snapshot, engine: engine.version)
        for item in restored {
            let entry = item.entry
            let plan = entry.results.plan
            let key = PlanRunKey(plan: plan, kind: .base)
            guard slots[key] == nil, library.library.plans[plan] != nil else { continue }
            let basis = PlanRunBasis(plan: entry.plan, inputs: item.inputsMatch ? PlanRunInputs(snapshot) : nil,
                                     mode: entry.results.mode, whatIf: nil, focusAge: nil, asOf: entry.asOf)
            slots[key] = PlanSlot(results: entry.results, basis: basis)
            let reasons = staleReasons(of: plan)
            PlanResultsLog.notice("Restored \(plan)'s results calculated \(entry.results.computedAt): "
                                  + (reasons.isEmpty ? "up to date."
                                     : "out of date (\(reasons.map(\.rawValue).joined(separator: ", ")))."))
            if item.inputsMatch {
                await engine.remember(entry.results, for: PlanRunRequest(
                    plan: entry.plan, library: snapshot, mode: entry.results.mode, whatIf: nil, asOf: entry.asOf))
            }
        }
    }

    /// The library the ``archive`` keeps results for: the open library's
    /// folder, or ``inMemoryLibrary``.
    private var keptLibrary: URL? {
        library.location?.url ?? inMemoryLibrary
    }

    /// Writes a plan's own results, calculated from the library at `url`,
    /// to the ``archive``, off the main thread, after the write before.
    private func keepOnDevice(_ results: PlanResults, basis: PlanRunBasis, library url: URL?) {
        guard let archive, let url else { return }
        let previous = archiving
        archiving = Task {
            await previous?.value
            do {
                try await archive.save(results, basis: basis, library: url)
            } catch {
                PlanResultsLog.notice("Couldn't keep \(results.plan)'s results: \(error)")
            }
        }
    }

    /// Cancels the runs of `plan` of `kinds` in progress. By default every
    /// run the Plan screens start, not a check-in's (it records the month's
    /// answer).
    func cancel(_ plan: PlanID, kinds: Set<PlanRunKey.Kind> = [.base, .whatIf, .focus]) {
        for (key, run) in inFlight where key.plan == plan && kinds.contains(key.kind) {
            run.task.cancel()
        }
    }

    // MARK: Out of date

    /// What a run of `document` would be computed from now.
    private func basis(_ document: PlanDocument, mode: PlanRunMode, whatIf: PlanWhatIf?, focusAge: Int?)
        -> PlanRunBasis {
        PlanRunBasis(plan: document, inputs: PlanRunInputs(library.library), mode: mode, whatIf: whatIf,
                     focusAge: focusAge, asOf: library.asOfDate)
    }

    /// Why the results of `plan` of `kind` don't fit `document` (by default
    /// the library's plan), the library as it is now, and the plan's what-if
    /// and focus age; empty when they do, or when there are none.
    func staleReasons(of plan: PlanID, _ kind: PlanRunKey.Kind = .base, plan document: PlanDocument? = nil)
        -> [PlanStaleReason] {
        guard let stored = slot(plan, kind)?.basis, let document = document ?? library.library.plans[plan] else {
            return []
        }
        let (whatIf, focusAge) = inputs(of: plan, kind)
        return stored.staleReasons(comparedWith: basis(document, mode: stored.mode, whatIf: whatIf,
                                                       focusAge: focusAge))
    }

    // MARK: Headlines

    /// The main plan's latest answer, for Today's "Can I retire
    /// yet?" card, Progress and the widgets: the Planner's `LatestAnswer`
    /// of its latest results and its recorded headlines. Never starts a run.
    var mainAnswer: LatestAnswer? {
        guard let main = library.settings.mainPlan else { return nil }
        return latestAnswer(of: main)
    }

    /// `plan`'s years, answers and milestones reached (the Planner's
    /// `PlanProgress`) for `document`, worked out once for each state of
    /// the library and the plan and shared by *Your way to retirement*,
    /// *Your year* and the widgets' snapshot: it reads every check-in.
    func planProgress(of plan: PlanID, document: PlanDocument) -> PlanProgress {
        progressMemo.progress(of: plan, plan: document, library: library)
    }

    /// The main plan's latest answer itself (``mainAnswer``).
    var mainHeadline: RetirementAnswer? { mainAnswer?.answer }

    /// `plan`'s latest answer: its results, unless they're out of date with
    /// the library and a check-in they didn't see recorded its answer, else
    /// its last recorded headline (`LatestAnswer`).
    func latestAnswer(of plan: PlanID) -> LatestAnswer? {
        LatestAnswer(plan: plan, library: library.library, results: results(of: plan),
                     upToDate: resultsSeeLibrary(of: plan))
    }

    /// The plan's latest results, unless they're out of date with the
    /// library and a check-in after the latest one they saw recorded an
    /// answer (`LatestAnswer.latestResults`).
    func latestResults(of plan: PlanID) -> PlanResults? {
        LatestAnswer.latestResults(results(of: plan), recorded: library.library.headlines(for: plan),
                                   upToDate: resultsSeeLibrary(of: plan))
    }

    /// Whether `plan`'s results were calculated from the library as it is
    /// now (no `.library` among their ``staleReasons(of:_:plan:)``), so they
    /// saw every check-in it holds.
    private func resultsSeeLibrary(of plan: PlanID) -> Bool {
        !staleReasons(of: plan).contains(.library)
    }

    /// The headlines recorded at check-ins for `plan`, oldest first.
    func recordedHeadlines(for plan: PlanID) -> [Headline] {
        library.library.headlines(for: plan)
    }

    /// After a check-in: starts the main plan's run that records this
    /// month's answer, and returns at once. ``checkInAnswer`` follows it: its
    /// progress is ``progress(of:_:)`` with `.checkIn`, then the headline.
    /// Nothing happens without a main plan.
    ///
    /// This is the one run that starts without a button: recording the
    /// month's answer is what a check-in is for. The confirmation says the
    /// app can be closed meanwhile, so on iOS the run and its writes ask for
    /// background time (``BackgroundActivity``); an answer that still didn't
    /// get recorded is caught up at the next launch
    /// (``recordMissingCheckInAnswer(today:)``).
    func recordCheckInAnswer(on date: CalendarDate) {
        guard let main = library.settings.mainPlan, library.library.plans[main] != nil else {
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
    /// and again. Nothing happens without a main plan, for a read-only
    /// library, when a headline on or after the latest check-in is recorded
    /// (also from the other device), or when the latest check-in is in the
    /// future (a typo).
    func recordMissingCheckInAnswer(today: CalendarDate = .today()) {
        guard library.canEdit, let main = library.settings.mainPlan, library.library.plans[main] != nil,
              let latest = library.latestCheckIn, latest <= today, checkInAnswer?.isRunning != true,
              !library.library.headlines(for: main).contains(where: { $0.date >= latest }),
              caughtUpAnswers[main] != latest
        else { return }
        caughtUpAnswers[main] = latest
        recordCheckInAnswer(on: latest)
    }

    /// After a check-in: re-runs the main plan, records its headline, saves
    /// the yearly baseline at the year's first check-in, waits for the
    /// writes, and returns the answer. First launch's sketch, a day whose
    /// values are all starting estimates, saves no baseline: the year's
    /// first check-in with imported values does. `nil` without a main plan. The Plan
    /// screens can't cancel this run. A headline or baseline that can't be
    /// saved shows in the library's error (`LibraryStore.lastError`).
    func checkInSaved(on date: CalendarDate) async -> RetirementAnswer? {
        guard let main = library.settings.mainPlan,
              let results = await run(main, .checkIn)
        else { return nil }
        do {
            try library.record(Self.headline(of: results, on: date), for: main)
        } catch {
            library.reportError("This month's answer couldn't be recorded. \(LibraryStore.describe(error))")
        }
        if !library.library.valuesAreStartingEstimates(on: date),
           !library.library.baselines(for: main).contains(where: { $0.isYearly(of: date.year) }) {
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
        guard let results = self.results(of: plan), results.mode == .full, let document = library.library.plans[plan],
              results.details.planHash == Planner.planHash(document)
        else {
            throw PlanStoreError.noResults
        }
        let baseline = Baseline(
            created: date, kind: kind, label: label, engine: results.engine, accounts: results.accounts,
            headline: Self.headline(of: results, on: date).summary,
            plan: try CanonicalJSON.json(encoding: document), start: results.start, years: results.years)
        return try library.saveBaseline(baseline, for: plan)
    }

    /// Calculates `document` as you planned it on `start`, a day in the past
    /// (PROGRESS.md, "Past baselines"): from your plan assets that day, as
    /// your history values them. Saves the outputs as a past baseline and
    /// returns its ID.
    @discardableResult
    func savePastBaseline(for plan: PlanID, document: PlanDocument, from start: CalendarDate,
                          label: String?) async throws -> BaselineID {
        var past = document
        past.portfolio.start = .date(start)
        let request = PlanRunRequest(plan: past, library: library.library, mode: .full, whatIf: nil, asOf: start)
        let results = try await engine.run(request, progress: nil)
        let baseline = Baseline(
            created: .today(), kind: .past, label: label, engine: results.engine, accounts: results.accounts,
            headline: Self.headline(of: results, on: start).summary,
            plan: try CanonicalJSON.json(encoding: past), start: results.start, years: results.years)
        return try library.saveBaseline(baseline, for: plan)
    }

    // MARK: Helpers

    /// The headline to record for `results` on `date`: the Planner's own
    /// (`PlanResult.headline`), so the app and the CLI write identical
    /// records.
    static func headline(of results: PlanResults, on date: CalendarDate) -> Headline {
        var headline = results.details.headline
        headline.date = date
        return headline
    }

    static func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}

/// A plan and a kind of run. Runs of the same key replace each other, and
/// each kind but `.checkIn` keeps its own results.
struct PlanRunKey: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// The plan as it is.
        case base
        /// With the plan's what-if changes.
        case whatIf
        /// The charts for another retirement age.
        case focus
        /// After a check-in, recording the month's answer: its results are
        /// the plan's own (`.base`), but the Plan screens don't cancel it.
        case checkIn

        /// The kind whose results a run of this kind gives.
        var slot: Kind { self == .checkIn ? .base : self }
    }

    var plan: PlanID
    var kind: Kind
}

/// A plan's latest results of one kind, and what they were computed from.
struct PlanSlot: Sendable {
    var results: PlanResults
    var basis: PlanRunBasis
}

/// Everything a run depends on: the plan, the library data it reads, the
/// start date, the mode, the what-if and the focus age. Results keep the
/// basis they were computed from, so a screen can tell when they no
/// longer fit (``staleReasons(comparedWith:)``), and an identical request
/// joins the run in progress instead of cancelling it.
struct PlanRunBasis: Equatable, Sendable {
    var plan: PlanDocument
    /// `nil` for results kept on the device whose library data changed
    /// since: they're out of date (`.library`).
    var inputs: PlanRunInputs?
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
    var headline: RetirementAnswer?
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
