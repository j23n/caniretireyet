import Foundation
import Glance
import Model
import Planner

/// Which of the milestones reached *Your way to retirement* shows (UI.md,
/// "Your way to retirement"): it opens on the newest and steps to an older
/// or a newer one, stopping at the oldest and the newest.
struct ReachedMilestonePager: Hashable {
    /// The milestones reached, oldest first.
    let reached: [ReachedMilestone]
    /// The id of the one shown; `nil` shows the newest, also once another
    /// is reached.
    var shownID: String?

    /// The index of the one shown in ``reached``; `nil` with none reached.
    var index: Int? {
        guard !reached.isEmpty else { return nil }
        return shownID.flatMap { id in reached.firstIndex { $0.id == id } } ?? reached.count - 1
    }

    /// The one shown; `nil` with none reached.
    var shown: ReachedMilestone? {
        index.map { reached[$0] }
    }

    /// Whether the one shown is the newest.
    var showsNewest: Bool {
        index == reached.count - 1
    }

    var canStepOlder: Bool {
        (index ?? 0) > 0
    }

    var canStepNewer: Bool {
        index.map { $0 < reached.count - 1 } ?? false
    }

    /// Shows the one `offset` steps newer (older when negative), stopping
    /// at the oldest and the newest.
    mutating func step(by offset: Int) {
        guard let index else { return }
        show(index + offset)
    }

    /// Shows the one at `index`, kept between the oldest and the newest.
    mutating func show(_ index: Int) {
        guard !reached.isEmpty else { return }
        let kept = min(max(index, 0), reached.count - 1)
        shownID = kept == reached.count - 1 ? nil : reached[kept].id
    }

    /// Whether the one shown was reached at the newest check-in, as the
    /// newest was: one check-in often reaches several.
    var showsLastReached: Bool {
        shown.map { $0.date == reached.last?.date } ?? false
    }

    /// "3 of 21", where it is among those reached, oldest first; `nil`
    /// with fewer than two, where there's nothing to step to.
    var position: String? {
        guard reached.count > 1, let index else { return nil }
        return "\(index + 1) of \(reached.count)"
    }

    /// "Last reached · August · 21 of 21" for one reached at the newest
    /// check-in, "Reached · March 2025 · 3 of 21" for an older one; without
    /// the position with only one reached.
    func label(relativeTo today: CalendarDate, locale: Locale) -> String? {
        guard let shown else { return nil }
        var parts = [showsLastReached ? "Last reached" : "Reached",
                     GlanceText.month(shown.date, relativeTo: today, locale: locale)]
        if let position {
            parts.append(position)
        }
        return parts.joined(separator: " · ")
    }
}
