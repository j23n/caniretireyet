import Foundation
import Model
import Tracker

// The words of the charts' value axis. What the chart components draw is
// Tracker's (`ChartPoint`, `FanPoint`, `ChartMarker`, `ChartColor`,
// `ChartSegment`, `AmountScale`, `ChartSeries`, `BreakdownRow`) and the
// Planner's (`SuccessPoint`, `IncomeSegment`, `YearValue`).

extension AmountScale {
    /// A tick's label: compact, with the decimals the ticks need to read apart.
    func label(_ value: Double, locale: Locale = .current) -> String {
        AmountFormat.compact(value, step: step, locale: locale)
    }
}
