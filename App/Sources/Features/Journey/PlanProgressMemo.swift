import Model
import Planner

/// A plan's years, answers and milestones reached through the latest
/// check-in (the Planner's `PlanProgress`), worked out once for each state
/// of the library and the plan: for *Your way to retirement*, *Your year*
/// and the widgets' snapshot, which show the main plan's journey outside
/// the plan's own screen.
@MainActor
final class PlanProgressMemo {
    private struct Key: Equatable {
        var revision: Int
        var plan: PlanID
        var document: PlanDocument
        var asOf: CalendarDate
    }

    private let memo = Memo<Key, PlanProgress>()

    nonisolated init() {}

    /// The progress of `plan` (`id`'s document) in `library` as it is.
    func progress(of id: PlanID, plan: PlanDocument, library: LibraryStore) -> PlanProgress {
        let key = Key(revision: library.revision, plan: id, document: plan, asOf: library.asOfDate)
        return memo.value(for: key) {
            PlanProgress(plan: id, document: plan, library: library.library, valuator: library.valuator,
                         asOf: library.asOfDate)
        }
    }
}
