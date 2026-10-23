import Foundation
import Model
import Tracker

// The words of a chart's time span, history continued into a projection:
// how far back (Tracker's `HistoryRange`) and how far ahead (its
// `FutureHorizon`), chosen together in one control (UI.md, "Today",
// "Your money over time").

extension FutureHorizon {
    /// In the menu: "Retirement + 10 years", or "+10 years" once retirement
    /// is behind.
    func title(fromRetirement: Bool) -> String {
        guard let years else { return "To retirement" }
        return fromRetirement ? "Retirement + \(years) years" : "+\(years) years"
    }

    /// In the control's label, after the past range: "5Y · retirement +10".
    func shortTitle(fromRetirement: Bool) -> String {
        guard let years else { return "to retirement" }
        return fromRetirement ? "retirement +\(years)" : "+\(years) years"
    }

    /// In the control's label where room is short (an iPhone): "5Y → ret. +10".
    func compactTitle(fromRetirement: Bool) -> String {
        guard let years else { return "retiring" }
        return fromRetirement ? "ret. +\(years)" : "+\(years)y"
    }
}

/// The control's label for a time span: "5Y", or "5Y · retirement +10"
/// while the future is shown ("5Y → ret. +10" when `compact`; "5Y · +10
/// years" once retirement is behind).
func timeSpanTitle(range: HistoryRange, horizon: FutureHorizon?, fromRetirement: Bool,
                   compact: Bool = false) -> String {
    guard let horizon else { return range.title }
    return compact
        ? "\(range.title) → \(horizon.compactTitle(fromRetirement: fromRetirement))"
        : "\(range.title) · \(horizon.shortTitle(fromRetirement: fromRetirement))"
}
