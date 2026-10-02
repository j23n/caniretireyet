import Foundation
import Model
import Observation
import Planner

/// One plan on screen: its edits, runs, what-if and focus age. Created by
/// `PlanScreen` for the plan it shows; the numbers themselves live in
/// `PlanStore` and the plan in `LibraryStore`.
///
/// - **Runs only on request.** Nothing runs on appear, after an edit, a
///   slider move or another focus age. The results shown stay until the
///   user asks for new ones (``calculate()``, ⌘R; ``runWhatIf()``), and
///   ``state`` says when they're out of date and why. Results the engine
///   kept for exactly the current inputs are picked up without a run
///   (``refresh()``), e.g. after changing an input back.
/// - **Editing.** Edits change a draft at once and are saved to the library
///   after a short pause (and when the screen goes away). Validation
///   (`Planner.validate`, a tenth of a second) still follows every edit.
///   Editing while a run is going lets it finish; its results then show as
///   out of date.
/// - **What if.** Moving a slider marks the what-if out of date; *Run
///   What-If* runs a quick estimate with fewer runs, then the full set.
///   *Keep* writes the change into the plan, *Reset* throws it away.
/// - **Focus age.** Tapping an age on the success curve shows the charts
///   for retiring then, at once when they were calculated before, else
///   after *Calculate*.
///
/// The what-if and the focus age are kept per plan in `PlanStore`, so
/// switching plans and coming back finds them as they were.
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

    /// The what-if changes on top of the plan.
    private(set) var whatIf: PlanWhatIf
    /// The retirement age the charts are for, when it isn't the plan's own.
    private(set) var focusAge: Int?

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var validateTask: Task<Void, Never>?
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var lookupTask: Task<Void, Never>?

    /// How long edits wait before they're saved.
    var saveDelay: Duration = .milliseconds(700)

    init(planID: PlanID, library: LibraryStore, plans: PlanStore) {
        self.planID = planID
        self.library = library
        self.plans = plans
        whatIf = plans.whatIfs[planID] ?? PlanWhatIf()
        focusAge = plans.focusAges[planID]
    }

    // MARK: The plan

    /// The plan as shown: the unsaved draft, else the library's.
    var plan: PlanDocument? {
        draft ?? library.library.plans[planID]
    }

    var canEdit: Bool { library.canEdit }

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
    /// results show as out of date until the user recalculates.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard let draft else { return }
        do {
            try library.save(draft)
            self.draft = nil
        } catch {
            saveError = LibraryStore.describe(error)
            self.draft = nil
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
        if let results = plans.results[planID], results.planHash == plan.map({ Planner.planHash($0) }) {
            issues += results.details?.issues ?? []
        }
        return PlanInputIssues(PlanIssueText.humanized(issues, plan: plan, library: library.library))
    }

    /// The warnings of the results shown, in words for the screen, each once.
    var resultWarnings: [String] {
        PlanResultsText.warnings(PlanIssueText.humanized(shownResults?.details?.issues ?? [], plan: plan,
                                                         library: library.library))
    }

    /// The currency of the plan's amounts: its own, else the library's.
    var currency: CurrencyCode {
        plan.map { PlanMoney.currency(of: $0, settings: library.settings) } ?? library.settings.baseCurrency
    }

    /// The currency of `results`' amounts: the one they were calculated in,
    /// else the plan's.
    func currency(of results: PlanResults) -> CurrencyCode {
        results.currency ?? currency
    }

    // MARK: What's shown

    /// The plan's own results.
    var baseResults: PlanResults? { plans.results[planID] }

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
            if let results = plans.whatIfResults[planID] {
                return (results, plans.staleReasons(of: planID, .whatIf, plan: plan, whatIf: whatIf,
                                                    focusAge: focusAge))
            }
            return base.map { ($0.0, $0.1 + [.whatIf]) }
        }
        if let focusAge {
            if let results = plans.focusResults[planID], results.details?.focus.age == focusAge {
                return (results, plans.staleReasons(of: planID, .focus, plan: plan, focusAge: focusAge))
            }
            return base.map { ($0.0, $0.0.details?.focus.age == focusAge ? $0.1 : $0.1 + [.focusAge]) }
        }
        return base
    }

    /// The results the charts show (see ``state`` for whether they're out of date).
    var shownResults: PlanResults? { shown?.results }

    /// What the results area shows: results (maybe out of date), else the
    /// answer recorded at the last check-in, else nothing; the run in
    /// progress; and the button that brings it up to date.
    var state: PlanResultsState {
        let content: PlanResultsState.Content
        var reasons: [PlanStaleReason] = []
        if let shown {
            content = .results(shown.results)
            reasons = shown.reasons
        } else if let recorded = plans.recordedHeadlines(for: planID).last {
            let changed = plan.map { recorded.planHash != Planner.planHash($0) } ?? false
            content = .recorded(PlanHeadline(recorded: recorded), planChanged: changed)
        } else {
            content = .nothing
        }
        return PlanResultsState(content: content, staleReasons: reasons, progress: runProgress,
                                canCancel: canCancelRun, focusAge: focusAge)
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
            await plans.adoptCached(planID)
        }
        await adoptCachedDetails()
    }

    /// The what-if's or the focus age's results, when the engine kept them.
    private func adoptCachedDetails() async {
        let whatIf = whatIf
        let focusAge = focusAge
        if whatIfIsOutOfDate {
            await plans.adoptCached(planID, modes: [.full, .fast], whatIf: whatIf, focusAge: focusAge)
        } else if whatIf.isEmpty, let focusAge, focusNeedsRun(focusAge) {
            await plans.adoptCached(planID, focusAge: focusAge)
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
            await self?.adoptCachedDetails()
        }
    }

    /// Whether the charts for retiring at `age` need a run: neither the
    /// plan's own results nor ones for that age fit.
    private func focusNeedsRun(_ age: Int) -> Bool {
        if baseResults?.details?.focus.age == age, baseIsUpToDate { return false }
        guard plans.focusResults[planID]?.details?.focus.age == age else { return true }
        return !plans.staleReasons(of: planID, .focus, plan: plan, focusAge: age).isEmpty
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
            await adoptCachedDetails()
            guard !Task.isCancelled, focusNeedsRun(focusAge) else { return }
            await plans.run(planID, focusAge: focusAge)
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
    /// the same random draws (PLANNER.md, "Speed").
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
        if await plans.adoptCached(planID, whatIf: whatIf, focusAge: focusAge) { return }
        guard !Task.isCancelled else { return }
        let quick = await plans.run(planID, mode: .fast, whatIf: whatIf, focusAge: focusAge)
        guard quick != nil, !Task.isCancelled, self.whatIf == whatIf, self.focusAge == focusAge else { return }
        await plans.run(planID, mode: .full, whatIf: whatIf, focusAge: focusAge)
    }

    /// Stops the runs this screen started; results stay as they were. A
    /// check-in's run goes on: it records the month's answer.
    func cancel() {
        runTask?.cancel()
        runTask = nil
        plans.cancel(planID)
    }

    // MARK: Focus age

    /// The retirement age the charts are for: the one chosen, else the
    /// results'.
    var shownFocusAge: Int? {
        focusAge ?? shownResults?.details?.focus.age
    }

    /// Shows the charts for retiring at `age`; `nil` or the plan's own age
    /// (the what-if's, while one is in use) goes back to it. Charts already
    /// calculated for that age show at once; otherwise they wait for
    /// *Calculate*.
    func selectFocus(_ age: Int?) {
        guard age != shownFocusAge || (age == nil && focusAge != nil) else { return }
        let own = whatIf.retirementAge ?? baseResults?.details?.focus.age
        if let age, age != own {
            focusAge = age
        } else {
            focusAge = nil
            plans.clearFocus(planID)
        }
        plans.focusAges[planID] = focusAge
        lookUpCachedDetails()
    }

    // MARK: What if

    /// Whether the what-if has any change.
    var hasWhatIf: Bool { !whatIf.isEmpty }

    /// Whether the what-if moved since it last ran (or never ran): the
    /// headline next to the sliders is then from before the change.
    var whatIfIsOutOfDate: Bool {
        guard !whatIf.isEmpty else { return false }
        guard plans.whatIfResults[planID] != nil else { return true }
        return !plans.staleReasons(of: planID, .whatIf, plan: plan, whatIf: whatIf, focusAge: focusAge).isEmpty
    }

    /// Whether the what-if's run is in progress.
    var isRunningWhatIf: Bool { plans.isRunning(planID, .whatIf) }

    /// The sliders' model for the plan as shown.
    var whatIfModel: PlanWhatIfModel? {
        plan.map { PlanWhatIfModel(plan: $0, results: baseResults, whatIf: whatIf) }
    }

    /// Moves a slider. Nothing runs: the what-if shows as out of date until
    /// *Run What-If*. Moving every slider back to the plan's value resets it.
    func set(_ slider: PlanWhatIfSlider, to value: Double) {
        guard let model = whatIfModel else { return }
        let changed = model.setting(slider, to: value)
        guard changed != whatIf else { return }
        whatIf = changed
        plans.whatIfs[planID] = changed
        if whatIf.isEmpty {
            reset()
        } else {
            lookUpCachedDetails()
        }
    }

    /// Throws the what-if away ("Reset").
    func reset() {
        runTask?.cancel()
        whatIf = PlanWhatIf()
        plans.whatIfs[planID] = nil
        plans.clearWhatIf(planID)
        plans.cancelWhatIf(planID)
        lookUpCachedDetails()
    }

    /// Writes the what-if into the plan ("Keep"). Its full results are the
    /// plan's own from then on, when they were calculated.
    func keep() {
        guard let model = whatIfModel, !whatIf.isEmpty else { return }
        let kept = model.kept
        runTask?.cancel()
        whatIf = PlanWhatIf()
        focusAge = nil
        plans.whatIfs[planID] = nil
        plans.focusAges[planID] = nil
        plans.clearWhatIf(planID)
        plans.clearFocus(planID)
        update(kept)
        saveNow()
        Task { [plans, planID] in
            await plans.adoptCached(planID)
        }
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

    /// The focus age for a stepper: reading the one shown, writing selects it.
    var editableFocusAge: Int {
        get { shownFocusAge ?? 55 }
        set { selectFocus(newValue) }
    }

    /// The what-if sliders' values, for `Slider`s: reading the value shown,
    /// writing moves it (see ``set(_:to:)``).
    var whatIfRetirementAge: Double {
        get { whatIfModel?.value(.retirementAge) ?? 0 }
        set { set(.retirementAge, to: newValue) }
    }

    var whatIfSpending: Double {
        get { whatIfModel?.value(.spending) ?? 0 }
        set { set(.spending, to: newValue) }
    }

    var whatIfSaving: Double {
        get { whatIfModel?.value(.saving) ?? 0 }
        set { set(.saving, to: newValue) }
    }

    var whatIfEquityReturn: Double {
        get { whatIfModel?.value(.equityReturn) ?? 0 }
        set { set(.equityReturn, to: newValue) }
    }

    // MARK: Baselines

    /// Saves the plan's full results as a manual baseline, calculating the
    /// plan first if they're missing or out of date (the user asked for it).
    func saveBaseline(label: String) async throws -> BaselineID {
        saveNow()
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? nil : trimmed
        if !baseIsUpToDate || baseResults?.mode != .full {
            await plans.run(planID)
        }
        return try plans.saveBaseline(for: planID, label: name, kind: .manual, on: .today())
    }
}
