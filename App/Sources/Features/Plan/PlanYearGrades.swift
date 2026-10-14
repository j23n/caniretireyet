import Foundation
import Model
import Planner
import Tracker

// The words of Trends' *Year by year* (UI.md, "Trends"; PROGRESS.md,
// "Trends"): each calendar year graded on what you control, against the
// baseline Progress measures the year against, and what markets did as
// context. The grades are the Planner's `PlanProgressYear`, the year Progress
// shows too.

extension MarketYear {
    /// "strong", "average", "hard".
    var word: String {
        switch self {
        case .strong: "strong"
        case .average: "average"
        case .hard: "hard"
        }
    }

    /// The year in Progress's words: "a strong year for markets", "a hard
    /// year for markets"; `nil` for an average one, which goes unsaid.
    var yearWords: String? {
        self == .average ? nil : "a \(word) year for markets"
    }
}

extension PlanComparison {
    /// "less than planned", "as planned", "more than planned".
    var words: String {
        switch self {
        case .less: "less than planned"
        case .asPlanned: "as planned"
        case .more: "more than planned"
        }
    }
}

extension PlanProgressYear {
    /// What a column says when it has no grade.
    static let ungraded = "—"

    /// What a year without a baseline says in place of its two grades.
    static let noPlan = "No plan to compare with"

    /// "2026 so far: you saved more than planned, you spent as planned,
    /// markets strong.", as VoiceOver reads the row.
    var spoken: String {
        let markets = "markets \(marketYear?.word ?? "not measured")"
        let title = isSoFar ? "\(year) so far" : "\(year)"
        guard baseline != nil else { return "\(title): \(Self.noPlan.lowercased()), \(markets)." }
        let saved = self.saved.map { "you saved \($0.words)" } ?? "you saved: not graded"
        let spent = self.spent.map { "you spent \($0.words)" } ?? "you spent: not graded"
        return "\(title): \(saved), \(spent), \(markets)."
    }
}
