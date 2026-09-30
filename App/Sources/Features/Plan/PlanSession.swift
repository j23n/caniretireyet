import Foundation
import Model
import Observation
import Planner

/// One plan on screen: its edits, runs, what-if and focus age. Created by
/// `PlanScreen` for the plan it shows; the numbers themselves live in
/// `PlanStore` and the plan in `LibraryStore`.
///
/// - **Editing.** Edits change a draft at once and are saved to the library
///   after a short pause (and when the screen goes away), then the plan runs
///   again. Validation (`Planner.validate`) runs off the main actor.
/// - **What if.** While a slider is dragged, fast runs follow it, one at a
///   time; letting go runs the full set. *Keep* writes the change into the
///   plan, *Reset* throws it away.
/// - **Focus age.** Tapping an age on the success curve shows the charts
///   for retiring then.
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
    private(set) var whatIf = PlanWhatIf()
    /// Whether a what-if slider is being dragged.
    private(set) var isDragging = false
    /// The retirement age the charts are for, when it isn't the plan's own.
    private(set) var focusAge: Int?

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var validateTask: Task<Void, Never>?
    @ObservationIgnored private var whatIfTask: Task<Void, Never>?
    @ObservationIgnored private var fastRunInFlight = false
    @ObservationIgnored private var fastRunPending = false

    /// How long edits wait before they're saved.
    var saveDelay: Duration = .milliseconds(700)

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

    /// Saves the draft now, if there is one, then runs the plan again.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard let draft else { return }
        do {
            try library.save(draft)
            self.draft = nil
            plans.scheduleRun(planID, after: .milliseconds(50))
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
    /// latest run of the plan as shown.
    var inputIssues: PlanInputIssues {
        var issues = validationIssues
        if let results = plans.results[planID], results.planHash == plan.map({ Planner.planHash($0) }) {
            issues += results.details?.issues ?? []
        }
        return PlanInputIssues(issues)
    }

    // MARK: Running

    /// Runs the plan (and the what-if or focus age in use) on the current
    /// library. Cheap when nothing changed: the store joins a run in
    /// progress and the engine keeps results.
    func refresh() async {
        guard draft == nil, library.library.plans[planID] != nil else { return }
        scheduleValidation(after: .zero)
        await plans.run(planID)
        if !whatIf.isEmpty {
            await plans.run(planID, mode: .full, whatIf: whatIf, focusAge: focusAge)
        } else if let focusAge {
            await plans.run(planID, focusAge: focusAge)
        }
    }

    /// The plan's own results.
    var baseResults: PlanResults? { plans.results[planID] }

    /// The results the charts show: the what-if's while one is in use, the
    /// focus age's when one is chosen, else the plan's own.
    var shownResults: PlanResults? {
        if !whatIf.isEmpty, let results = plans.whatIfResults[planID] { return results }
        if let focusAge, let results = plans.focusResults[planID], results.details?.focus.age == focusAge {
            return results
        }
        return plans.results[planID]
    }

    /// Whether a run the screen waits for is in progress.
    var isRunning: Bool { plans.isRunning(planID) }

    /// Why the latest run failed.
    var runError: String? { plans.errors[planID] }

    // MARK: Focus age

    /// The retirement age the charts are for.
    var shownFocusAge: Int? {
        focusAge ?? shownResults?.details?.focus.age
    }

    /// Shows the charts for retiring at `age`; `nil` or the plan's own age
    /// (the what-if's, while one is in use) goes back to it.
    func selectFocus(_ age: Int?) {
        guard age != shownFocusAge || (age == nil && focusAge != nil) else { return }
        let own = whatIf.retirementAge ?? baseResults?.details?.focus.age
        guard let age, age != own else {
            focusAge = nil
            plans.clearFocus(planID)
            if !whatIf.isEmpty { runWhatIf(mode: .full) }
            return
        }
        focusAge = age
        if whatIf.isEmpty {
            let planID = planID
            Task { [plans] in await plans.run(planID, focusAge: age) }
        } else {
            runWhatIf(mode: .full)
        }
    }

    // MARK: What if

    /// Whether the what-if has any change.
    var hasWhatIf: Bool { !whatIf.isEmpty }

    /// The sliders' model for the plan as shown.
    var whatIfModel: PlanWhatIfModel? {
        plan.map { PlanWhatIfModel(plan: $0, results: baseResults, whatIf: whatIf) }
    }

    /// A slider started or stopped moving. Letting go runs every run.
    func setDragging(_ dragging: Bool) {
        isDragging = dragging
        if !dragging, !whatIf.isEmpty { runWhatIf(mode: .full) }
    }

    /// Moves a slider. While dragging, fast runs follow; otherwise (keyboard,
    /// VoiceOver) the full run follows after a short pause.
    func set(_ slider: PlanWhatIfSlider, to value: Double) {
        guard let model = whatIfModel else { return }
        let changed = model.setting(slider, to: value)
        guard changed != whatIf else { return }
        whatIf = changed
        if whatIf.isEmpty {
            reset()
        } else if isDragging {
            runFastWhatIf()
        } else {
            runWhatIf(mode: .full, after: .milliseconds(300))
        }
    }

    /// One fast run at a time while dragging; when it's done, the latest
    /// position runs next.
    private func runFastWhatIf() {
        if fastRunInFlight {
            fastRunPending = true
            return
        }
        fastRunInFlight = true
        Task { [weak self] in
            guard let self else { return }
            repeat {
                self.fastRunPending = false
                let whatIf = self.whatIf
                guard !whatIf.isEmpty, self.isDragging else { break }
                await self.plans.run(self.planID, mode: .fast, whatIf: whatIf, focusAge: self.focusAge)
            } while self.fastRunPending && self.isDragging
            self.fastRunInFlight = false
        }
    }

    private func runWhatIf(mode: PlanRunMode, after delay: Duration = .zero) {
        whatIfTask?.cancel()
        let planID = planID
        whatIfTask = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard let self, !Task.isCancelled, !self.whatIf.isEmpty else { return }
            await self.plans.run(planID, mode: mode, whatIf: self.whatIf, focusAge: self.focusAge)
        }
    }

    /// Throws the what-if away ("Reset").
    func reset() {
        whatIfTask?.cancel()
        whatIf = PlanWhatIf()
        plans.clearWhatIf(planID)
        plans.cancelWhatIf(planID)
        if let focusAge {
            let planID = planID
            Task { [plans] in await plans.run(planID, focusAge: focusAge) }
        }
    }

    /// Writes the what-if into the plan ("Keep").
    func keep() {
        guard let model = whatIfModel, !whatIf.isEmpty else { return }
        let kept = model.kept
        whatIfTask?.cancel()
        whatIf = PlanWhatIf()
        focusAge = nil
        plans.clearWhatIf(planID)
        plans.clearFocus(planID)
        update(kept)
        saveNow()
    }

    // MARK: Baselines

    /// Saves the plan's full results as a manual baseline, running it first
    /// if they're missing or older than the plan.
    func saveBaseline(label: String) async throws -> BaselineID {
        saveNow()
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? nil : trimmed
        do {
            return try plans.saveBaseline(for: planID, label: name, kind: .manual, on: .today())
        } catch PlanStoreError.noResults {
            await plans.run(planID)
            return try plans.saveBaseline(for: planID, label: name, kind: .manual, on: .today())
        }
    }
}
