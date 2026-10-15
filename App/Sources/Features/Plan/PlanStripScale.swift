import Foundation
import Model
import Planner

extension PlanStripScale {
    /// A gridline's amount, compact with the decimals the ticks need to read
    /// apart: "1,1M €", "1,15M €", "1,2M €".
    func label(_ tick: Double, currency: CurrencyCode, locale: Locale = .current) -> String {
        let amount = AmountFormat.compact(tick, step: step, locale: locale)
        return "\(amount) \(AmountFormat.symbol(for: currency, locale: locale))"
    }
}
