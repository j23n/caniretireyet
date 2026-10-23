import Foundation
import Glance
import Model
import Planner
import Tracker

// The words of Trends (UI.md, "Trends"; PROGRESS.md, "Trends"): money in
// and out, where your money came from, and the answer at each check-in,
// over the time span Today's history uses. What it shows is the
// Planner's `PlanTrends`, worked out from the plan's `PlanProgress`.

extension PeriodGrain {
    /// "Months", "Years".
    var title: String {
        switch self {
        case .months: "Months"
        case .years: "Years"
        }
    }
}

extension PlanTrends {
    /// The device remembers the grain once chosen.
    static let grainKey = "trends.grain"
}

extension PlanMoneySources {
    /// "You saved 164.000 € and markets added 98.000 €. In 2025 they added
    /// more than you did, for the first time."
    func words(locale: Locale) -> AmountSentence {
        var sentence = PlanWords(currency: currency, locale: locale)
            .savedAndMarkets(saved: saved, markets: markets).capitalizedFirst
        if let year = firstYearMarketsAddedMore {
            sentence += " In \(String(year)) they added more than you did, for the first time."
        }
        return sentence
    }
}

extension Library {
    /// The accounts whose typed values turn Trends off (UI.md, "Trends";
    /// ``Model/Account/typedValuesTurnOffTrends``), by name: open savings
    /// and investment accounts set to typed values.
    var accountsTurningOffTrends: [Account] {
        accounts.values.filter(\.typedValuesTurnOffTrends)
            .sorted { ($0.name.lowercased(), $0.id) < ($1.name.lowercased(), $1.id) }
    }
}
