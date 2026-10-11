import Glance
import Model
import SwiftUI
import Tracker

/// Trends (UI.md, "Trends"; PROGRESS.md, "Trends"): how you've actually
/// been doing, from your own records, over the time span the Overview's
/// history uses. *Where your money came from* splits plan assets into what
/// you started with, what you put in and what markets added; *Time to
/// retirement* is the plan's answer at each check-in. On iPhone the grain
/// and the span are at the top of the page; on the Mac and iPad they're in
/// the toolbar (``PlanTrendsControls``), and the cards are in two columns.
struct PlanTrendsView: View {
    let session: PlanSession
    var isWide = false

    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale
    @AppStorage("overview.range") private var range: OverviewRange = .threeYears
    @AppStorage(PlanTrendsModel.grainKey) private var storedGrain: PeriodGrain?
    @State private var cache = PlanTrendsCache()

    private var gutter: CGFloat { isWide ? Metrics.xl : Metrics.l }

    private var grain: PeriodGrain {
        storedGrain ?? .trendsStandard(firstMoneyInOut: library.firstMoneyInOut, asOf: library.asOfDate)
    }

    private var isMainPlan: Bool { library.settings.mainPlan == session.planID }

    var body: some View {
        let model = trendsModel
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.l) {
                if isWide {
                    EqualColumns(spacing: Metrics.l) {
                        sourcesCard(model.sources)
                        answerCard(model.history)
                    }
                } else {
                    PlanTrendsControls()
                    sourcesCard(model.sources)
                    answerCard(model.history)
                }
            }
            .padding(gutter)
        }
        .background(Palette.page)
    }

    /// Worked out once for each state of the library, the grain and the
    /// span (``PlanTrendsModel``), not each time the page draws.
    private var trendsModel: PlanTrendsModel {
        let asOf = library.asOfDate
        let key = PlanTrendsModel.Key(revision: library.revision, plan: session.planID, grain: grain, range: range,
                                      asOf: asOf)
        return cache.model(for: key) {
            PlanTrendsModel(plan: session.planID, library: library.library, valuator: library.valuator, grain: grain,
                            range: range, asOf: asOf)
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
            items.append(ChartLegendItem(name: "Saving nothing more", swatch: .line(.neutral, dashed: true)))
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
/// the Overview's menu, sharing its choice): at the top of the page on
/// iPhone, beside the part picker in the toolbar on the Mac and iPad. The
/// grain is remembered once chosen.
struct PlanTrendsControls: View {
    @Environment(LibraryStore.self) private var library
    @AppStorage("overview.range") private var range: OverviewRange = .threeYears
    @AppStorage(PlanTrendsModel.grainKey) private var storedGrain: PeriodGrain?

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
