import Foundation
import Glance
import Model
import Planner
import Tracker

// The words of Trends (UI.md, "Trends"; PROGRESS.md, "Trends"): money in
// and out, where your money came from, and the answer at each check-in,
// over the time span the Overview's history uses. What it shows is the
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
    /// "You put in 164.000 € and markets added 98.000 €. In 2025 they added
    /// more than you did, for the first time."
    func words(locale: Locale) -> AmountSentence {
        func amount(_ value: Decimal) -> AmountSentence {
            .amount(AmountFormat.amount(abs(value), currency: currency, locale: locale))
        }
        let you: AmountSentence = putIn >= 0 ? "You put in \(amount(putIn))" : "You took out \(amount(putIn))"
        let them: AmountSentence = markets >= 0 ? "markets added \(amount(markets))"
            : "markets took \(amount(markets))"
        var sentence: AmountSentence = "\(you) and \(them)."
        if let year = firstYearMarketsAddedMore {
            sentence += " In \(String(year)) they added more than you did, for the first time."
        }
        return sentence
    }
}
