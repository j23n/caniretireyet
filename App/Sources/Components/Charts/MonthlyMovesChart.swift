import Charts
import Model
import SwiftUI
import Tracker

/// What you saved and what markets did in each month, as a pair of bars per
/// month (UI.md, "Check-in" and "Your year"): saved in the accent, markets
/// in orange, below the line when they took. The bars' heights compare the
/// months; the chart has no amount axis, so it shows no amount.
struct MonthlyMovesChart: View {
    let months: [MonthlyChange]
    var height: CGFloat = 150
    /// The month to pick out; the others draw lighter. `nil` draws all alike.
    var highlighted: YearMonth?

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            HStack(spacing: Metrics.m) {
                legend("Saved", Palette.accent)
                legend("Markets", Palette.orange)
            }
            .font(.caption)
            .foregroundStyle(Palette.secondaryInk)
            Chart {
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(Palette.axis)
                    .lineStyle(StrokeStyle(lineWidth: 0.5))
                ForEach(months) { month in
                    let date = month.month.firstDay.dateValue
                    BarMark(x: .value("Month", date, unit: .month), y: .value("Amount", month.saved.doubleValue))
                        .position(by: .value("Kind", "Saved"))
                        .foregroundStyle(Palette.accent)
                        .opacity(opacity(month))
                        .cornerRadius(2)
                    BarMark(x: .value("Month", date, unit: .month), y: .value("Amount", month.markets.doubleValue))
                        .position(by: .value("Kind", "Markets"))
                        .foregroundStyle(Palette.orange)
                        .opacity(opacity(month))
                        .cornerRadius(2)
                }
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: months.count > 6 ? 3 : 1)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: .dateTime.month(.abbreviated))
                                .font(.caption2)
                                .foregroundStyle(Palette.mutedInk)
                        }
                    }
                }
            }
            .chartLegend(.hidden)
            .frame(height: height)
            .privacySensitiveInFeedback()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Saved and what markets did in each of the last "
            + Wording.count(months.count, "month") + "."))
    }

    private func opacity(_ month: MonthlyChange) -> Double {
        guard let highlighted else { return 1 }
        return month.month == highlighted ? 1 : 0.45
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: Metrics.xs) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(title)
        }
    }
}
