import Charts
import Model
import SwiftUI

/// A bank statement's Preview charts (UI.md, "Import"): money in and out by
/// month as Trends will show it once the file is imported, and the file's
/// balance as a line with the account's values before the import as dots,
/// orange where they differ from the file's.
struct ImportStatementChartsCard: View {
    let charts: ImportStatementCharts

    var body: some View {
        Card("Does this look right?", systemImage: "chart.bar.xaxis") {
            if !charts.money.counted.isEmpty {
                Text("Money in and out by month, as Trends will show it after the import.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                PlanMoneyInOutLegend(money: charts.money, showsPlanSpending: false)
                PlanMoneyInOutChart(money: charts.money)
            }
            if charts.file.count > 1 {
                ImportBalanceChart(charts: charts)
                Text(charts.balanceCaption)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The file's balance as a line, the account's values before the import as
/// dots: ink where the file gives the same balance on that day, orange where
/// it doesn't.
private struct ImportBalanceChart: View {
    let charts: ImportStatementCharts

    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        let scale = AmountScale(values: (charts.file + charts.before).map(\.balance.doubleValue))
        Chart {
            ForEach(charts.file) { value in
                LineMark(x: .value("Date", value.date.dateValue), y: .value("Balance", value.balance.doubleValue),
                         series: .value("Series", "File"))
                    .foregroundStyle(Palette.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            ForEach(charts.before) { value in
                PointMark(x: .value("Date", value.date.dateValue), y: .value("Balance", value.balance.doubleValue))
                    .foregroundStyle(charts.agrees(value) ? Palette.ink : Palette.warning)
                    .symbolSize(charts.agrees(value) ? 36 : 64)
            }
        }
        .chartYScale(domain: scale.domain)
        .chartYAxis { amountAxis(hidesAmounts: redactionReasons.hidesAmounts, scale: scale) }
        .chartLegend(.hidden)
        .frame(height: 140)
        .privacySensitiveInFeedback()
        .accessibilityElement()
        .accessibilityLabel(Text("The file's balance, with the account's values before this import"))
    }
}
