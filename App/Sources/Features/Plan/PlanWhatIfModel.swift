import Foundation
import Planner

extension PlanWhatIfSlider {
    var title: String {
        switch self {
        case .retirementAge: "Stop working at"
        case .spending: "Spending"
        case .saving: "Saving"
        case .equityReturn: "Shares, above inflation"
        }
    }
}
