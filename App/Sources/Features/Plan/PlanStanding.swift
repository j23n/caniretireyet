import Planner
import SwiftUI

// Whether you're ahead of, on or behind plan, as the screens say it and
// color it (UI.md, "Progress"; PROGRESS.md, "On track").

extension BaselineStanding {
    /// "Ahead of plan", "On plan", "Behind plan".
    var label: String {
        switch self {
        case .ahead: "Ahead of plan"
        case .onPlan: "On plan"
        case .behind: "Behind plan"
        }
    }

    /// "Ahead of plan.", "On plan.", "Behind plan."
    var title: String { label + "." }

    /// Only behind is a warning.
    var isWarning: Bool { self == .behind }

    /// Orange behind plan, the only warning; green ahead and on plan.
    var color: Color { isWarning ? Palette.orangeStroke : Palette.positive }

    /// The tint behind ``color``, as on the plan's progress pill.
    var tint: Color { isWarning ? Palette.orange : Palette.positive }

    /// ``color`` for a position; green without one.
    static func color(of position: PlanBaselineComparison.Position?) -> Color {
        position?.standing.color ?? Palette.positive
    }
}
