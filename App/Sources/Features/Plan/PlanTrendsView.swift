import Glance
import Model
import Planner
import SwiftUI
import Tracker

/// Trends (UI.md, "Trends"; PROGRESS.md, "Trends"): how you've actually
/// been doing, from your own records, over the time span the Overview's
/// history uses. *Your last 12 months*, *Savings rate* and *Money in and
/// out* are built on money in and out, with the plan as reference lines,
/// and fold into one card while none is recorded; *Where your money came
/// from* splits plan assets into what you started with, what you put in
/// and what markets added; *Time to retirement* is the plan's answer at
/// each check-in; *Year by year* grades each calendar year in words. On
/// iPhone the grain and the span are at the top of the page; on the Mac and
/// iPad they're in the toolbar (``PlanTrendsControls``), the tiles are in a
/// row, the charts in two columns and *Year by year* is a table across the
/// page.
struct PlanTrendsView: View {
    let session: PlanSession
    var isWide = false
    /// Opens a year on Progress.
    var onShowYear: (Int) -> Void = { _ in }

    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale
    @AppStorage("overview.range") private var range: HistoryRange = .threeYears
    @AppStorage(PlanTrends.grainKey) private var storedGrain: PeriodGrain?

    private var gutter: CGFloat { isWide ? Metrics.xl : Metrics.l }

    private var grain: PeriodGrain {
        storedGrain ?? .trendsStandard(firstMoneyInOut: library.firstMoneyInOut, asOf: library.asOfDate)
    }

    private var isMainPlan: Bool { library.settings.mainPlan == session.planID }

    var body: some View {
        let model = trendsModel
        let reference = moneyReference(on: model.money.end)
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.l) {
                if isWide {
                    if model.money.isEmpty {
                        PlanMoneyInOutEmptyCard()
                        EqualColumns(spacing: Metrics.l) {
                            sourcesCard(model.sources)
                            answerCard(model.history)
                        }
                    } else {
                        PlanLastTwelveMonthsCard(year: model.lastTwelveMonths,
                                                 plannedSpending: reference.spendingWhileWorking, isWide: true)
                        EqualColumns(spacing: Metrics.l) {
                            VStack(alignment: .leading, spacing: Metrics.l) {
                                savingsRateCard(model.money, planRate: reference.savingsRate)
                                moneyCard(model.money, planSpending: reference.spending(per: model.money.grain))
                            }
                            VStack(alignment: .leading, spacing: Metrics.l) {
                                sourcesCard(model.sources)
                                answerCard(model.history)
                            }
                        }
                    }
                } else {
                    PlanTrendsControls()
                    if model.money.isEmpty {
                        PlanMoneyInOutEmptyCard()
                    } else {
                        PlanLastTwelveMonthsCard(year: model.lastTwelveMonths,
                                                 plannedSpending: reference.spendingWhileWorking)
                        savingsRateCard(model.money, planRate: reference.savingsRate)
                        moneyCard(model.money, planSpending: reference.spending(per: model.money.grain))
                    }
                    sourcesCard(model.sources)
                    answerCard(model.history)
                }
                yearsCard(model.years)
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
    /// span, from the progress Progress shows too (the session's
    /// `PlanProgressCache`), not each time the page draws.
    private var trendsModel: PlanTrends {
        session.progressCache.trends(for: session.progressKey, grain: grain, lastYears: range.years,
                                     library: library.library, valuator: library.valuator)
    }

    // MARK: Savings rate, Money in and out

    private func savingsRateCard(_ money: PlanMoneyInOut, planRate: Decimal?) -> some View {
        Card {
            if money.counted.isEmpty {
                notYet("No money in and out was recorded in this time span.")
            } else {
                PlanSavingsRateLegend(showsLastTwelveMonths: money.hasLastTwelveMonths, planRate: planRate)
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
                PlanMoneyInOutLegend(money: money, showsPlanSpending: planSpending != nil)
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

    // MARK: Where your money came from

    private func sourcesCard(_ sources: PlanMoneySources) -> some View {
        Card {
            if sources.hasEnoughData {
                PlanMoneySourcesLegend(showsLoss: sources.hasLoss)
                PlanMoneySourcesChart(sources: sources)
                AmountSentenceText(sources.words(locale: locale))
                    .font(PlanProgressFont.text)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                notYet("Where your money came from shows from your second check-in.")
            }
        } header: {
            SectionHeader("Where your money came from")
        }
    }

    // MARK: Time to retirement

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
                notYet("Time to retirement shows from the first check-in that records your answer.")
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
            SectionHeader("Time to retirement")
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

    // MARK: Year by year

    private func yearsCard(_ years: [PlanProgressYear]) -> some View {
        Card {
            if years.isEmpty {
                notYet("Year by year shows from your first check-in.")
            } else {
                PlanYearGradesTable(years: years, isWide: isWide, onShowYear: onShowYear)
            }
        } header: {
            SectionHeader("Year by year")
        }
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
/// the Overview's menu, sharing its choice): at the top of the page on
/// iPhone, beside the part picker in the toolbar on the Mac and iPad. The
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
    }
}

#Preview("Trends · Mac") {
    PlanPreviewHost(model: AppModel.preview()) { session in
        PlanTrendsView(session: session, isWide: true)
            .frame(width: 1_100, height: 800)
    }
}
