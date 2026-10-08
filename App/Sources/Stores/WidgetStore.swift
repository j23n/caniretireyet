import Foundation
import Glance
import Model
import Observation
import Planner
import Tracker
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Keeps the widgets' snapshot (UI.md, "Widgets") in step with the library
/// and the main plan's answer. The widget extension never opens the library:
/// it draws the snapshot this store writes into the App Group's container
/// (``AppGroup``), and redraws when asked to.
///
/// The root view calls ``refresh()`` whenever ``inputs`` change: the library
/// loads or changes (here or on the other device), or the main plan gets new
/// results. An unchanged snapshot isn't written again.
@Observable @MainActor
final class WidgetStore {
    /// Where the snapshot is written; `nil` in previews and in a build
    /// without the App Group, where nothing is written.
    @ObservationIgnored let snapshotURL: URL?
    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private let plans: PlanStore
    /// The snapshot last written.
    @ObservationIgnored private var written: GlanceSnapshot?

    init(library: LibraryStore, plans: PlanStore, snapshotURL: URL?) {
        self.library = library
        self.plans = plans
        self.snapshotURL = snapshotURL
    }

    /// What the snapshot is made from: when it changes, so may the snapshot.
    struct Inputs: Hashable {
        var isReady: Bool
        var revision: Int
        var answer: PlanHeadline?
    }

    var inputs: Inputs {
        Inputs(isReady: library.phase == .ready, revision: library.revision, answer: plans.mainHeadline)
    }

    /// The snapshot of the library as it is; `nil` until it's loaded. The
    /// answer is the main plan's latest results, or else the last one
    /// recorded at a check-in, as on the Overview.
    func snapshot(today: CalendarDate = .today()) -> GlanceSnapshot? {
        guard library.phase == .ready else { return nil }
        let last = library.latestCheckIn
        let checkIn = CheckInGlance(last: last, next: last.map(CheckInSchedule.nextCheckIn(after:)) ?? today,
                                    dueWindow: CheckInSchedule.dueWindow)
        let answer = library.settings.mainPlan.flatMap { plans.latestResults(of: $0) }
            .map { RetirementAnswer($0.headline) }
        // Net worth today, as the Overview has it.
        var snapshot = GlanceSnapshot(library: library.library, valuator: library.valuator, asOf: today,
                                      answer: answer, checkIn: checkIn)
        snapshot.milestone = nextMilestone()
        return snapshot
    }

    /// The main plan's next milestone, as Progress shows it (UI.md,
    /// "Milestones"), from the same results as the answer; `nil` without a
    /// main plan or a milestone ahead.
    private func nextMilestone() -> MilestoneGlance? {
        guard let main = library.settings.mainPlan, let plan = library.library.plans[main] else { return nil }
        let milestones = PlanMilestones(plan: plan, library: library.library, valuator: library.valuator,
                                        asOf: library.asOfDate, results: plans.latestResults(of: main), reached: [])
        guard let next = milestones.next else { return nil }
        return MilestoneGlance(next.milestone, progress: next.progress, typically: milestones.nextDate)
    }

    /// Writes the snapshot if it changed, off the main thread, then asks the
    /// widgets to redraw. A failed write is tried again at the next change.
    func refresh() async {
        guard let url = snapshotURL, let snapshot = snapshot(), snapshot != written else { return }
        written = snapshot
        do {
            try await Task.detached(priority: .utility) {
                try GlanceFile.write(snapshot, to: url)
            }.value
        } catch {
            written = nil
            return
        }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

extension RetirementAnswer {
    /// The answer of a plan's results. Their headline has the date of the
    /// earliest age (the Planner's `PlanAnswer.earliestDate`).
    init(_ headline: PlanHeadline) {
        self.init(confidence: headline.confidence, earliestAge: headline.earliestAge,
                  earliestDate: headline.earliestDate, targetAge: headline.targetAge,
                  sustainableSpending: headline.sustainableSpending, readiness: headline.readiness,
                  readinessIsLowerBound: headline.readinessIsLowerBound,
                  needsMoreThanSearched: headline.needsMoreThanSearched, canRetireNow: headline.canRetireNow)
    }
}

extension MilestoneGlance {
    /// A Planner milestone, as the widgets read it.
    init(_ milestone: Milestone, progress: Double, typically: CalendarDate?) {
        switch milestone.kind {
        case .yearsOfSpending(let years):
            self.init(kind: .yearsOfSpending, amount: milestone.amount, years: years, progress: progress,
                      typically: typically)
        case .shareOfNeeded:
            self.init(kind: .shareOfNeeded, amount: milestone.amount, share: milestone.share, progress: progress,
                      typically: typically)
        case .crossover:
            self.init(kind: .crossover, amount: milestone.amount, progress: progress, typically: typically)
        case .roundAmount, .coastPoint:
            self.init(kind: .roundAmount, amount: milestone.amount, progress: progress, typically: typically)
        }
    }
}
