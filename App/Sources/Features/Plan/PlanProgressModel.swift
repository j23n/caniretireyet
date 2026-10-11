import Foundation
import Model
import Planner
import Tracker

/// What Progress works out from the library (UI.md, "Progress"): the
/// answers recorded, the milestones reached and the strip of years. It
/// values plan assets at every check-in and month end since the first
/// record, so the page works it out once for each state of the library and
/// the plan (``PlanProgressCache``), not each time it draws, as choosing a
/// year does.
struct PlanProgressModel {
    let history: PlanAnswerHistory
    /// Oldest first.
    let reached: [ReachedMilestone]
    let timeline: PlanProgressTimeline

    /// What the model is worked out from.
    struct Key: Hashable {
        /// ``LibraryStore/revision``: every change to the library.
        var revision: Int
        var plan: PlanID
        /// The plan as shown, which may hold an edit not saved yet.
        var document: PlanDocument?
        var asOf: CalendarDate
        var hidesAmounts: Bool
        var locale: String
    }

    init(plan: PlanID, document: PlanDocument?, library: Library, valuator: Valuator, asOf: CalendarDate,
         text: PlanMilestoneText) {
        let history = PlanAnswerHistory(library.headlines(for: plan))
        self.history = history
        let years = PlanProgressYear.years(for: plan, library: library, valuator: valuator, history: history,
                                           asOf: asOf)
        // What's reached doesn't depend on the results: only what's ahead does.
        reached = document.map {
            MilestoneLadder(plan: $0, library: library, on: asOf)
                .reached(plan: plan, library: library, valuator: valuator, through: asOf)
        } ?? []
        timeline = PlanProgressTimeline(years: years, library: library, valuator: valuator, history: history,
                                        milestones: reached, text: text)
    }
}

/// The last ``PlanProgressModel`` and what it was worked out from. A view
/// keeps it in `@State` and fills it while it draws: nothing observes it,
/// so filling it doesn't draw again.
@MainActor
final class PlanProgressCache {
    private var key: PlanProgressModel.Key?
    private var model: PlanProgressModel?

    /// The model for `key`: the last one when it's for the same, else `make()`'s.
    func model(for key: PlanProgressModel.Key, make: () -> PlanProgressModel) -> PlanProgressModel {
        if let model, self.key == key { return model }
        let made = make()
        self.key = key
        model = made
        return made
    }
}
