import Foundation
import Model
import Planner

extension PlanWhatIfSlider {
    var title: String {
        switch self {
        case .retirementAge: "Stop working at"
        case .spending: "Spend a month"
        case .saving: "Save a month"
        case .equityReturn: "Shares above inflation"
        }
    }
}

/// What a what-if changes, in words, for the plan's *What if* tile (UI.md,
/// "The plan").
enum PlanWhatIfText {
    /// A line for each slider moved away from the plan's value, in the
    /// sliders' order: "Stop at 52", "Spend 2.800 € a month", "Save 500 € a
    /// month", "Shares 4.75% a year"; empty without a change.
    static func changes(_ model: PlanWhatIfModel, words: PlanWords) -> [AmountSentence] {
        PlanWhatIfSlider.allCases.filter(model.isChanged).map { slider -> AmountSentence in
            let value = model.value(slider)
            switch slider {
            case .retirementAge:
                return AmountSentence("Stop at \(Int(wholeNumber: value))")
            case .spending:
                return "Spend \(words.amount(monthly: value)) a month"
            case .saving:
                return "Save \(words.amount(monthly: value)) a month"
            case .equityReturn:
                return AmountSentence("Shares \(AmountFormat.percent(value, digits: 2, locale: words.locale)) a year")
            }
        }
    }
}
