import Foundation
import Model
import Planner

extension PlanWhatIfSlider {
    var title: String {
        switch self {
        case .retirementAge: "Stop working at"
        case .takeHome: "Take-home pay, while working"
        case .spending: "Spend a month, retired"
        }
    }
}
