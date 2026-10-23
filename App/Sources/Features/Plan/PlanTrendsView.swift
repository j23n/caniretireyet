import Glance
import Model
import Planner
import SwiftUI
import Tracker

/// The Timeline looking back (UI.md, "Timeline"; PROGRESS.md, "Trends"):
/// how you've actually been doing, from your own records, over the time
/// span the decades chart uses. *Your last 12 months*, *Savings rate* and
/// *Money in and out* are built on money in and out, with the plan as
/// reference lines, and fold into one card while none is recorded; *Your
/// last Monday, check-in by check-in* is the plan's answer at each
/// check-in. The grain and the span are under the zoom on iPhone, and in
/// the toolbar on the Mac and iPad (``PlanTrendsControls``), where the
/// tiles are in a row and the charts in two columns. While a savings or
/// investment account's values are typed, one card says looking back is
/// off instead (``PlanTrendsOffCard``).
struct PlanTrendsView: View {
    let session: PlanSession

    @Environment(LibraryStore.self) private var library
    @Environment(\.pageLayout) private var layout
    @Environment(\.locale) private var locale
    @AppStorage("overview.range") private var range: HistoryRange = .threeYears
    @AppStorage(PlanTrends.grainKey) private var storedGrain: PeriodGrain?

    private var isWide: Bool { layout.isWide }

    private var gutter: CGFloat { layout.gutter }

    private var grain: PeriodGrain {
        storedGrain ?? .trendsStandard(firstMoneyInOut: library.firstMoneyInOut, asOf: library.asOfDate)
    }

    private var isMainPlan: Bool { library.settings.mainPlan == session.planID }

    var body: some View {
        let typedAccounts = library.library.accountsTurningOffTrends
        if typedAccounts.isEmpty {
            trends
        } else {
            ScrollView {
                PlanTrendsOffCard(accounts: typedAccounts)
                    .padding(gutter)
            }
            .background(Palette.page)
        }
    }

    private var trends: some View {
        let model = trendsModel
        let reference = moneyReference(on: model.money.end)
        return ScrollView {
            VStack(alignment: .leading, spacing: Metrics.l) {
                if isWide {
                    if model.money.isEmpty {
                        PlanMoneyInOutEmptyCard()
                        answerCard(model.history)
                    } else {
                        PlanLastTwelveMonthsCard(year: model.lastTwelveMonths,
                                                 plannedSpending: reference.spendingWhileWorking)
                        EqualColumns(spacing: Metrics.l) {
                            VStack(alignment: .leading, spacing: Metrics.l) {
                                savingsRateCard(model.money, planRate: reference.savingsRate)
                                moneyCard(model.money, planSpending: reference.spending(per: model.money.grain))
                            }
                            answerCard(model.history)
                        }
                    }
                } else {
                    if model.money.isEmpty {
                        PlanMoneyInOutEmptyCard()
                    } else {
                        PlanLastTwelveMonthsCard(year: model.lastTwelveMonths,
                                                 plannedSpending: reference.spendingWhileWorking)
                        savingsRateCard(model.money, planRate: reference.savingsRate)
                        moneyCard(model.money, planSpending: reference.spending(per: model.money.grain))
                    }
                    answerCard(model.history)
                }
            }
            .padding(gutter)
        }
        .background(Palette.page)
    }

    /// The plan's references for money in and out on the latest check-in:
    /// its spending while working and its own savings rate. From the plan
    /// as shown, so an edit moves them at once.
    private func moneyReference(on date: CalendarDate) -> PlanMoneyReference {
        PlanMoneyReference(plan: session.plan, on: date,
                           earliestAge: library.library.headlines(for: session.planID).last?.earliestAge,
                           birthDate: library.settings.person?.birthDate)
    }

    /// Worked out once for each state of the library, the grain and the
    /// span, from the progress Progress shows too (``PlanSession/trends(grain:lastYears:)``),
    /// not each time the page draws.
    private var trendsModel: PlanTrends {
        session.trends(grain: grain, lastYears: range.years)
    }

    // MARK: Savings rate, Money in and out

    private func savingsRateCard(_ money: PlanMoneyInOut, planRate: Decimal?) -> some View {
        Card {
            if money.counted.isEmpty {
                notYet("No money in and out was recorded in this time span.")
            } else {
                PlanSavingsRateLegend(money: money, planRate: planRate,
                                      cuts: money.cutsRates(planRate: planRate))
                PlanSavingsRateChart(money: money, planRate: planRate)
            }
            whereItStarts(money)
        } header: {
            SectionHeader("Savings rate")
        }
    }

    private func moneyCard(_ money: PlanMoneyInOut, planSpending: Decimal?) -> some View {
        Card {
            if money.counted.isEmpty {
                notYet("No money in and out was recorded in this time span.")
            } else {
                PlanMoneyInOutLegend(money: money, showsPlanSpending: planSpending != nil,
                                     cuts: money.cutsAmounts(planSpending: planSpending))
                PlanMoneyInOutChart(money: money, planSpending: planSpending)
            }
            whereItStarts(money)
        } header: {
            SectionHeader("Money in and out")
        }
    }

    /// "Money in and out is recorded since 30 Jun 2026: 3 months so far.",
    /// when the span reaches back before it.
    @ViewBuilder
    private func whereItStarts(_ money: PlanMoneyInOut) -> some View {
        if let line = money.whereItStarts(locale: locale) {
            Text(line)
                .font(PlanProgressFont.caption)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .privacySensitiveInFeedback()
        }
    }

    // MARK: Your date at each check-in

    private func answerCard(_ history: PlanAnswerHistory) -> some View {
        Card {
            if !isMainPlan {
                notYet("Only your main plan records an answer at each check-in.")
                Button {
                    setMainPlan()
                } label: {
                    Label("Set as Main Plan", systemImage: "star")
                }
                .buttonStyle(.borderless)
                .font(PlanProgressFont.caption)
                .disabled(!library.canEdit)
            } else if history.latestAge == nil {
                notYet("Your date shows here from the first check-in that records it.")
            } else {
                ChartLegendRow(items: answerLegend(history))
                PlanAnswerHistoryChart(history: history)
                if let line = history.nowLine(locale: locale) {
                    Text(line)
                        .font(PlanProgressFont.text)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .privacySensitiveInFeedback()
                }
                if !history.markers.isEmpty {
                    HStack(spacing: Metrics.m) {
                        ForEach(PlanAnswerHistory.Change.allCases, id: \.self) { change in
                            if history.markers.contains(where: { $0.changes.contains(change) }) {
                                Label(change.label, systemImage: change.systemImage)
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                }
            }
        } header: {
            SectionHeader("Your last Monday, check-in by check-in")
        }
    }

    /// "━ earliest age ┄ at your pace ┈ saving nothing more", for the lines drawn.
    private func answerLegend(_ history: PlanAnswerHistory) -> [ChartLegendItem] {
        var items = [ChartLegendItem(name: "Earliest age", swatch: .line(.accent, dashed: false))]
        if !history.pacePoints.isEmpty {
            items.append(ChartLegendItem(name: "At your pace", swatch: .line(.taxes, dashed: true)))
        }
        if !history.coastPoints.isEmpty {
            items.append(ChartLegendItem(name: "Saving nothing more", swatch: .dottedLine(.neutral)))
        }
        return items
    }

    private func setMainPlan() {
        do {
            try library.setMainPlan(session.planID)
        } catch {
            library.reportError("The main plan couldn't be changed. \(LibraryStore.describe(error))")
        }
    }

    /// What a card needs before it can show anything, in a line.
    private func notYet(_ text: String) -> some View {
        Text(text)
            .font(PlanProgressFont.text)
            .foregroundStyle(Palette.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Trends' grain (*Months | Years*) and time span (the *History* half of
/// Today's menu, sharing its choice): at the top of the page on
/// iPhone under the Timeline's zoom, beside it in the toolbar on the Mac and iPad. The
/// grain is remembered once chosen.
struct PlanTrendsControls: View {
    @Environment(LibraryStore.self) private var library
    @AppStorage("overview.range") private var range: HistoryRange = .threeYears
    @AppStorage(PlanTrends.grainKey) private var storedGrain: PeriodGrain?

    var body: some View {
        HStack(spacing: Metrics.m) {
            Picker("Grain", selection: grain) {
                ForEach(PeriodGrain.allCases, id: \.self) { grain in
                    Text(grain.title).tag(grain)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer(minLength: 0)
            TimeSpanMenu(range: $range, horizon: nil, choices: [])
        }
    }

    private var grain: Binding<PeriodGrain> {
        Binding(get: { storedGrain ?? .trendsStandard(firstMoneyInOut: library.firstMoneyInOut,
                                                      asOf: library.asOfDate) },
                set: { storedGrain = $0 })
    }
}

#Preview("Trends") {
    PlanPreviewHost(model: AppModel.preview()) { session in
        PlanTrendsView(session: session)
            .environment(\.pageLayout, PageLayout())
    }
}

#Preview("Trends · Mac") {
    PlanPreviewHost(model: AppModel.preview()) { session in
        PlanTrendsView(session: session)
            .frame(width: 1_100, height: 800)
            .environment(\.pageLayout, PageLayout(isWide: true))
    }
}
