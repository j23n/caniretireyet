import Foundation
import Glance
import Model
import Planner
import Tracker

// The words of Trends (UI.md, "Money in and out, year by year"; PROGRESS.md, "Trends"): money in
// and out, where your money came from, and the answer at each check-in,
// over the time span Today's history uses. What it shows is the
// Planner's `PlanTrends`, worked out from the plan's `PlanProgress`.

extension Library {
    /// The accounts whose typed values turn Trends off (UI.md, "Money in and out, year by year";
    /// ``Model/Account/typedValuesTurnOffTrends``), by name: open savings
    /// and investment accounts set to typed values.
    var accountsTurningOffTrends: [Account] {
        accounts.values.filter(\.typedValuesTurnOffTrends)
            .sorted { ($0.name.lowercased(), $0.id) < ($1.name.lowercased(), $1.id) }
    }
}
