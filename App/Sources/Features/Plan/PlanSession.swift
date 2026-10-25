import Foundation
import Model
import Observation
import Planner
import Tracker

/// One plan on screen: its edits, runs, what-if and focus age. Created by
/// `PlanScreen` for the plan it shows; the numbers themselves live in
/// `PlanStore` and the plan in `LibraryStore`.
///
/// - **Runs only on request.** Nothing runs on appear, after an edit, a
///   slider move or another focus age. The results shown stay until the
///   user asks for new ones (``calculate()``, ⌘R; ``runWhatIf()``), and
///   ``state`` says when they're out of date and why.
///   Results the engine kept for exactly the current inputs are picked up
///   without a run (``refresh()``), e.g. after changing an input back.
/// - **Editing.** Edits change a draft at once and are saved to the library
///   after a short pause (and when the screen goes away). Validation
///   (`Planner.validate`, a tenth of a second) still follows every edit.
///   Editing while a run is going lets it finish; its results then show as
///   out of date.
/// - **What if.** Moving a slider marks the what-if out of date; *Run
///   What-If* runs a quick estimate with fewer runs, then the full set.
///   *Keep* writes the change into the plan, *Reset* throws it away.
/// - **Focus age.** Tapping an age on `PlanStopAgesTile` shows the charts
///   for retiring then, at once when they were calculated before, else
///   after *Calculate*.
///
/// The what-if and the focus age are `PlanStore`'s, per plan, so switching
/// plans and coming back finds them as they were. What the pages show
/// that's worked out from the plan, the library and the results shown
/// (``derived(locale:)``, ``progress``, ``trends(grain:lastYears:)``) is
/// worked out once for each change of them, not each time a page draws.
@Observable @MainActor
final class PlanSession {
    let planID: PlanID
    private let library: LibraryStore
    private let plans: PlanStore

    /// Edits not saved yet.
    private(set) var draft: PlanDocument?
    /// Problems found by validating the plan as shown.
    private(set) var validationIssues: [PlanIssue] = []
    /// The last save that failed, e.g. a read-only library.
    private(set) var saveError: String?

    /// The chapter selected on the map and in the chapters list, by a year
    /// it covers, so it stays put while edits renumber the chapters.
    var selectedChapterYear: Int?

    @ObservationIgnored private let progressMemo = Memo<ProgressKey, PlanProgress>()
    @ObservationIgnored private let trendsMemo = Memo<TrendsKey, PlanTrends>()
    @ObservationIgnored private let derivedMemo = Memo<DerivedKey, PlanDerived>()
    @ObservationIgnored private let baseDerivedMemo = Memo<DerivedKey, PlanDerived>()

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var validateTask: Task<Void, Never>?
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var lookupTask: Task<Void, Never>?
    @ObservationIgnored private var leverTask: Task<Void, Never>?

    /// How long edits wait before they're saved.
    private let saveDelay: Duration = .milliseconds(700)
    /// How long a lever waits, after it last moved, before its what-if runs.
    private let leverDelay: Duration = .milliseconds(350)

    init(planID: PlanID, library: LibraryStore, plans: PlanStore) {
        self.planID = planID
        self.library = library
        self.plans = plans
    }

    // MARK: The plan

    /// The plan as shown: the unsaved draft, else the library's.
    var plan: PlanDocument? {
        draft ?? library.library.plans[planID]
    }

    var canEdit: Bool { library.canEdit }

    // MARK: Progress and Trends

    /// What Progress and Trends are worked out from: the library as it is,
    /// the plan as shown, through the latest check-in.
    private struct ProgressKey: Equatable {
        var revision: Int
        var document: PlanDocument?
        var asOf: CalendarDate
    }

    private struct TrendsKey: Equatable {
        var progress: ProgressKey
        var grain: PeriodGrain
        var lastYears: Int?
    }

    private var progressKey: ProgressKey {
        ProgressKey(revision: library.revision, document: plan, asOf: library.asOfDate)
    }

    /// The plan's years, answers and milestones reached (the Planner's
    /// `PlanProgress`), which Progress and Trends both show.
    var progress: PlanProgress {
        progressMemo.value(for: progressKey) {
            PlanProgress(plan: planID, document: plan, library: library.library, valuator: library.valuator,
                         asOf: library.asOfDate)
        }
    }

    /// Trends' page by `grain` over the last `lastYears` (all of them when
    /// `nil`), from ``progress``.
    func trends(grain: PeriodGrain, lastYears: Int?) -> PlanTrends {
        let progress = self.progress
        return trendsMemo.value(for: TrendsKey(progress: progressKey, grain: grain, lastYears: lastYears)) {
            PlanTrends(progress: progress, valuator: library.valuator, grain: grain, lastYears: lastYears,
                       asOf: library.asOfDate)
        }
    }

    /// The plan's latest answer: its results, unless a check-in recorded a
    /// newer one, else its last recorded (``PlanStore/latestAnswer(of:)``).
    var latestAnswer: LatestAnswer? {
        plans.latestAnswer(of: planID)
    }

    /// Replaces the plan with an edited copy; it's saved after a pause.
    func update(_ plan: PlanDocument) {
        guard plan != self.plan else { return }
        draft = plan
        saveError = nil
        saveTask?.cancel()
        let delay = saveDelay
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
        scheduleValidation()
    }

    /// Edits the plan in place.
    func edit(_ change: (inout PlanDocument) -> Void) {
        guard var plan else { return }
        change(&plan)
        update(plan)
    }

    /// Saves the draft now, if there is one. It doesn't run the plan: the
    /// results show as out of date until the user recalculates. If the
    /// library refuses the edit (read-only, being moved), the draft stays
    /// on screen with ``saveError``, and the next save tries again.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard let draft else { return }
        do {
            try library.save(draft)
            self.draft = nil
        } catch {
            saveError = LibraryStore.describe(error)
        }
    }

    /// Checks the plan as shown, off the main actor, after a short pause.
    func scheduleValidation(after delay: Duration = .milliseconds(250)) {
        validateTask?.cancel()
        guard let plan else { return }
        let snapshot = library.library
        let asOf = library.asOfDate
        validateTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            let issues = await PlannerPlanEngine.validate(plan, library: snapshot, asOf: asOf)
            guard !Task.isCancelled else { return }
            self?.validationIssues = issues
        }
    }

    /// Every issue to show on Inputs: validation, and warnings from the
    /// latest run of the plan as shown, in words for the screen
    /// (``PlanIssueText``).
    var inputIssues: PlanInputIssues {
        var issues = validationIssues
        if let results = baseResults, results.details.planHash == plan.map({ Planner.planHash($0) }) {
            issues += results.details.issues
        }
        return PlanInputIssues(PlanIssueText.humanized(issues, plan: plan, library: library.library))
    }

    /// The warnings of the results shown, in words for the screen, each once.
    var resultWarnings: [PlanIssue] {
        PlanResultsText.warnings(PlanIssueText.humanized(shownResults?.details.issues ?? [], plan: plan,
                                                         library: library.library))
    }

    /// The currency of the plan's amounts: the library's base currency.
    var currency: CurrencyCode { library.settings.baseCurrency }

    // MARK: What's shown

    /// The what-if changes on top of the plan (``PlanStore/whatIf(of:)``).
    var whatIf: PlanWhatIf { plans.whatIf(of: planID) }

    /// The retirement age the charts are for, when it isn't the plan's own
    /// (``PlanStore/focusAge(of:)``).
    var focusAge: Int? { plans.focusAge(of: planID) }

    /// The plan's own results.
    var baseResults: PlanResults? { plans.results(of: planID) }

    /// Whether the plan's own results fit the plan and library as they are.
    var baseIsUpToDate: Bool {
        baseResults != nil && plans.staleReasons(of: planID, .base, plan: plan).isEmpty
    }

    /// The results the charts show and why they're out of date: the
    /// what-if's while one is in use, the focus age's when one is chosen,
    /// else the plan's own. Until a what-if or another age has run, the
    /// plan's own results show, out of date.
    private var shown: (results: PlanResults, reasons: [PlanStaleReason])? {
        let plan = plan
        let base = baseResults.map { ($0, plans.staleReasons(of: planID, .base, plan: plan)) }
        if !whatIf.isEmpty {
            if let results = plans.results(of: planID, .whatIf) {
                return (results, plans.staleReasons(of: planID, .whatIf, plan: plan))
            }
            return base.map { ($0.0, $0.1 + [.whatIf]) }
        }
        if let focusAge {
            if let results = plans.results(of: planID, .focus), results.details.focus.age == focusAge {
                return (results, plans.staleReasons(of: planID, .focus, plan: plan))
            }
            return base.map { ($0.0, $0.0.details.focus.age == focusAge ? $0.1 : $0.1 + [.focusAge]) }
        }
        return base
    }

    /// The results the charts show (see ``state`` for whether
    /// they're out of date).
    var shownResults: PlanResults? { shown?.results }

    /// What the results area shows: results (maybe out of date), else the
    /// answer recorded at the last check-in, else nothing; whether a run is
    /// going; and the button that brings it up to date. Not how far along
    /// the run is (``runProgress``, which only the progress card reads), so
    /// the views don't redraw with every progress update (on the Mac, the
    /// toolbar and the results redrawing ten times a second while the
    /// window laid itself out could loop).
    var state: PlanResultsState {
        let content: PlanResultsState.Content
        var reasons: [PlanStaleReason] = []
        if let shown {
            content = .results(shown.results)
            reasons = shown.reasons
        } else if let recorded = plans.recordedHeadlines(for: planID).last {
            let changed = plan.map { recorded.planHash != Planner.planHash($0) } ?? false
            content = .recorded(RetirementAnswer(recorded: recorded, birthDate: library.settings.person?.birthDate),
                                planChanged: changed)
        } else {
            content = .nothing
        }
        return PlanResultsState(content: content, staleReasons: reasons, canCancel: canCancelRun,
                                focusAge: focusAge, isRunning: isRunning)
    }

    /// Whether a run of this plan is in progress (also a check-in's).
    var isRunning: Bool { plans.isRunning(planID) }

    /// Where the run the screen waits for is: the what-if's, another age's,
    /// the plan's own, or a check-in's recording the month's answer.
    var runProgress: PlanRunProgress? {
        for kind in [PlanRunKey.Kind.whatIf, .focus, .base, .checkIn] {
            if let progress = plans.progress(of: planID, kind) { return progress }
        }
        return nil
    }

    /// Whether the run in progress is only a check-in's, which can't be cancelled here.
    var isCheckInRun: Bool {
        plans.isRunning(planID, .checkIn) && !canCancelRun
    }

    private var canCancelRun: Bool {
        [PlanRunKey.Kind.whatIf, .focus, .base].contains { plans.isRunning(planID, $0) }
    }

    /// Why the latest run failed.
    var runError: String? { plans.errors[planID] }

    // MARK: Running

    /// Shows what's already calculated for the plan, library, what-if and
    /// focus age as they are now (results the engine kept), and validates
    /// the plan. Never runs it: on appear and whenever the library changes.
    func refresh() async {
        guard draft == nil, library.library.plans[planID] != nil else { return }
        scheduleValidation(after: .zero)
        if !baseIsUpToDate {
            await plans.lookUp(planID)
        }
        await lookUpDetails()
    }

    /// The what-if's or the focus age's results, when the engine kept them.
    private func lookUpDetails() async {
        if whatIfIsOutOfDate {
            await plans.lookUp(planID, .whatIf, modes: [.full, .fast])
        } else if whatIf.isEmpty, let focusAge, focusNeedsRun(focusAge) {
            await plans.lookUp(planID, .focus)
        }
    }

    /// Looks for the what-if's or the focus age's results after a short
    /// pause, so a slider being dragged doesn't look at every step; a newer
    /// look replaces it.
    private func lookUpCachedDetails() {
        lookupTask?.cancel()
        lookupTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await self?.lookUpDetails()
        }
    }

    /// Whether the charts for retiring at `age` need a run: neither the
    /// plan's own results nor ones for that age fit.
    private func focusNeedsRun(_ age: Int) -> Bool {
        if baseResults?.details.focus.age == age, baseIsUpToDate { return false }
        guard plans.results(of: planID, .focus)?.details.focus.age == age else { return true }
        return !plans.staleReasons(of: planID, .focus, plan: plan).isEmpty
    }

    /// Calculate, Recalculate (⌘R): saves any pending edit, then runs what
    /// the screen shows that's missing or out of date: the plan's own
    /// results, then the what-if (a quick estimate, then every run) or the
    /// charts for the chosen age. Up-to-date results aren't run again.
    func calculate() {
        saveNow()
        runTask?.cancel()
        runTask = Task { [weak self] in
            await self?.performCalculation()
        }
    }

    private func performCalculation() async {
        if !baseIsUpToDate {
            guard await plans.run(planID) != nil, !Task.isCancelled else { return }
        }
        if !whatIf.isEmpty {
            if whatIfIsOutOfDate { await runWhatIfNow() }
        } else if let focusAge, focusNeedsRun(focusAge) {
            await lookUpDetails()
            guard !Task.isCancelled, focusNeedsRun(focusAge) else { return }
            await plans.run(planID, .focus)
        }
    }

    /// Does what the results area's button says (``PlanResultsState/action``).
    func perform(_ action: PlanResultsState.Action) {
        switch action {
        case .runWhatIf: runWhatIf()
        case .calculate, .recalculate, .calculateFocus: calculate()
        }
    }

    /// Run What-If: a quick estimate with fewer runs, then every run, with
    /// the same random draws (PLANNER.md, "Engine details").
    func runWhatIf() {
        saveNow()
        runTask?.cancel()
        runTask = Task { [weak self] in
            await self?.runWhatIfNow()
        }
    }

    private func runWhatIfNow() async {
        let whatIf = whatIf
        let focusAge = focusAge
        guard !whatIf.isEmpty else { return }
        if await plans.lookUp(planID, .whatIf) { return }
        guard !Task.isCancelled else { return }
        let quick = await plans.run(planID, .whatIf, mode: .fast)
        guard quick != nil, !Task.isCancelled, self.whatIf == whatIf, self.focusAge == focusAge else { return }
        await plans.run(planID, .whatIf, mode: .full)
    }

    /// Stops the runs this screen started; results stay as they were. A
    /// check-in's run goes on: it records the month's answer.
    func cancel() {
        runTask?.cancel()
        runTask = nil
        plans.cancel(planID)
    }

    // MARK: Derived

    /// What ``derived(locale:)`` is worked out from.
    private struct DerivedKey: Equatable {
        var revision: Int
        var document: PlanDocument?
        var results: PlanResults?
        var focusAge: Int?
        var whatIfAge: Int?
        var asOf: CalendarDate
        var locale: Locale
    }

    /// What the plan's pages show that's worked out from the plan as shown,
    /// the library and the results shown, in `locale`'s words: worked out
    /// once for each change of them.
    func derived(locale: Locale) -> PlanDerived {
        let key = DerivedKey(revision: library.revision, document: plan, results: shownResults, focusAge: focusAge,
                             whatIfAge: whatIf.retirementAge, asOf: library.asOfDate, locale: locale)
        return derivedMemo.value(for: key) { derived(for: key) }
    }

    /// The same, for the plan as it is and its own results, without the
    /// what-if or a chosen age: what the Timeline shows.
    func baseDerived(locale: Locale) -> PlanDerived {
        let key = DerivedKey(revision: library.revision, document: plan, results: baseResults, focusAge: nil,
                             whatIfAge: nil, asOf: library.asOfDate, locale: locale)
        return baseDerivedMemo.value(for: key) { derived(for: key) }
    }

    private func derived(for key: DerivedKey) -> PlanDerived {
        PlanDerived(plan: key.document, library: library.library, valuator: library.valuator,
                    results: key.results, chosenAge: key.focusAge, whatIfAge: key.whatIfAge,
                    asOf: key.asOf, reached: progress.reached, locale: key.locale)
    }

    // MARK: Chapters

    /// The index of the selected chapter in `chapters`.
    func selectedChapter(in chapters: PlanChaptersModel) -> Int? {
        selectedChapterYear.flatMap { chapters.chapterIndex(nearest: $0) }
    }

    /// Selects the chapter at `index` of `chapters`, by its first year.
    func selectChapter(_ index: Int?, in chapters: PlanChaptersModel) {
        guard let index, chapters.chapters.chapters.indices.contains(index) else {
            selectedChapterYear = nil
            return
        }
        selectedChapterYear = chapters.chapters.chapters[index].years.lowerBound
    }

    // MARK: Focus age

    /// The retirement age the charts are for: the one chosen, else the
    /// results'.
    var shownFocusAge: Int? {
        focusAge ?? shownResults?.details.focus.age
    }

    /// Shows the charts for retiring at `age`; `nil` or the plan's own age
    /// (the what-if's, while one is in use) goes back to it. Charts already
    /// calculated for that age show at once; otherwise they wait for
    /// *Calculate*.
    func selectFocus(_ age: Int?) {
        guard age != shownFocusAge || (age == nil && focusAge != nil) else { return }
        let own = whatIf.retirementAge ?? baseResults?.details.focus.age
        plans.setFocusAge(age == own ? nil : age, for: planID)
        lookUpCachedDetails()
    }

    // MARK: What if

    /// Whether the what-if has any change.
    var hasWhatIf: Bool { !whatIf.isEmpty }

    /// Whether the what-if moved since it last ran (or never ran): the
    /// headline next to the sliders is then from before the change.
    var whatIfIsOutOfDate: Bool {
        guard !whatIf.isEmpty else { return false }
        guard plans.results(of: planID, .whatIf) != nil else { return true }
        return !plans.staleReasons(of: planID, .whatIf, plan: plan).isEmpty
    }

    /// Whether the what-if's run is in progress.
    var isRunningWhatIf: Bool { plans.isRunning(planID, .whatIf) }

    /// The what-if's latest results, while the levers have moved; they may
    /// be from before the latest move (``whatIfIsOutOfDate``).
    var whatIfResults: PlanResults? {
        whatIf.isEmpty ? nil : plans.results(of: planID, .whatIf)
    }

    /// The sliders' model for the plan as shown.
    var whatIfModel: PlanWhatIfModel? {
        plan.map { PlanWhatIfModel(plan: $0, results: baseResults, whatIf: whatIf) }
    }

    /// Moves a lever. Once the levers rest for a moment, the what-if runs:
    /// a quick estimate, then every run (``runWhatIf()``), so the date
    /// follows as you drag. Moving every lever back to the plan's value
    /// resets it.
    func set(_ slider: PlanWhatIfSlider, to value: Double) {
        guard let model = whatIfModel else { return }
        let changed = model.setting(slider, to: value)
        guard changed != whatIf else { return }
        if changed.isEmpty {
            reset()
        } else {
            plans.setWhatIf(changed, for: planID)
            lookUpCachedDetails()
            scheduleWhatIf()
        }
    }

    /// Runs the what-if once the levers have rested for ``leverDelay``.
    private func scheduleWhatIf() {
        leverTask?.cancel()
        leverTask = Task { [weak self, leverDelay] in
            try? await Task.sleep(for: leverDelay)
            guard !Task.isCancelled, let self, self.whatIfIsOutOfDate else { return }
            self.runWhatIf()
        }
    }

    /// Throws the what-if away ("Reset").
    func reset() {
        leverTask?.cancel()
        runTask?.cancel()
        plans.setWhatIf(PlanWhatIf(), for: planID)
        lookUpCachedDetails()
    }

    /// Saves the plan with the levers where they are as a new plan named
    /// `name` ("Save as a New Plan…"), and puts this plan's levers back.
    /// Returns the new plan's ID.
    func saveAsPlan(named name: String) throws -> PlanID {
        guard let model = whatIfModel, !whatIf.isEmpty else { throw LibraryEditError.unknownPlan(planID) }
        let id = try saveAsNewPlan(model.kept, named: name)
        leverTask?.cancel()
        runTask?.cancel()
        plans.setWhatIf(PlanWhatIf(), for: planID)
        plans.setFocusAge(nil, for: planID)
        lookUpCachedDetails()
        return id
    }

    /// Saves `document`, this plan with a change, as a new plan named `name`
    /// ("Base case, changed" when it's empty); this plan stays as it was.
    /// Returns the new plan's ID.
    func saveAsNewPlan(_ document: PlanDocument, named name: String) throws -> PlanID {
        saveNow()
        var copy = document
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.name = PlanEditing.uniqueName(trimmed.isEmpty ? "\(copy.name), changed" : trimmed,
                                           among: library.library.plans.values)
        copy.id = library.newPlanID(for: copy.name)
        try library.save(copy)
        return copy.id
    }

    /// *Apply to Base case*: writes the levers into the plan (the age into
    /// when work stops, the pay into each work phase, the spending into
    /// spending in retirement) and puts them back. The plan then calculates
    /// as after any edit; the what-if's full results are the engine's
    /// already, so they show at once.
    func applyWhatIf() {
        guard let model = whatIfModel, !whatIf.isEmpty else { return }
        update(model.kept)
        reset()
    }

    // MARK: Previews

    /// The results of the plan with a change not made yet
    /// (``PlanStore/preview(_:mode:)``): an editor's *With this change*.
    func preview(_ document: PlanDocument, mode: PlanRunMode) async throws -> PlanResults {
        try await plans.preview(document, mode: mode)
    }

    /// The results of `document` already calculated, full ones first.
    func cachedPreview(_ document: PlanDocument) async -> PlanResults? {
        await plans.cachedPreview(document, modes: [.full, .fast])
    }

    /// Calculates the plan when its own results are missing or out of
    /// date and nothing runs: the plan screen does it on its own, in the
    /// background, so there's no *Calculate* to press. A plan whose last
    /// run failed waits for *Try Again*.
    func calculateIfNeeded() {
        guard canEdit, !isRunning, runError == nil, plan != nil, !baseIsUpToDate else { return }
        calculate()
    }

    // MARK: Bindings

    /// The plan for the editors (`$session.editablePlan`): reads the plan
    /// shown, and an edit replaces it (saved after a pause).
    var editablePlan: PlanDocument {
        get {
            plan ?? PlanDocument(id: planID, name: "", retirement: PlanRetirement(age: .earliest),
                                 spending: PlanSpending(working: 0, retired: 0))
        }
        set { update(newValue) }
    }
}
