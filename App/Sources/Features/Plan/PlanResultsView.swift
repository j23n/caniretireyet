import Charts
import Model
import Planner
import SwiftUI

/// Results (UI.md, "Results"): the headline, the chance of success by
/// retirement age, the money over time, retirement income, when it fails
/// and, on the Mac and iPad, the key numbers. On iPhone the What-if panel
/// opens from the headline; on the Mac it's in the inspector.
///
/// Nothing runs on its own (UI.md, "Calculating"): before the first
/// calculation it shows the answer recorded at the last check-in and
/// *Calculate*; when the plan, the library or the what-if changed, an
/// *Out of date* banner with *Recalculate* or *Run What-If*; while a run
/// goes, its progress with *Cancel*, over the old results dimmed.
struct PlanResultsView: View {
    let session: PlanSession
    /// The sidebar layout: two columns and the key numbers.
    var isWide = false
    /// Opens the What-if sheet (iPhone).
    var onWhatIf: (() -> Void)?

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans

    var body: some View {
        // Without the progress: only the progress card follows every update.
        let state = session.stateWithoutProgress
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.l) {
                PlanResultsBanners(session: session)
                if state.isRunning {
                    PlanRunProgressCard(session: session)
                } else {
                    PlanOutOfDateBanner(state: state) { session.perform($0) }
                }
                if let results = state.results {
                    resultCards(results)
                        .opacity(state.isRunning ? 0.4 : state.isOutOfDate ? 0.65 : 1)
                        .animation(.default, value: state.dimsResults)
                } else if !state.isRunning {
                    PlanCalculatePrompt(state: state, runs: session.plan?.simulation.effectiveRuns ?? 2_000,
                                        isAvailable: plans.isAvailable) {
                        session.calculate()
                    }
                }
            }
            .padding(Metrics.l)
            .frame(maxWidth: isWide ? 1_120 : Metrics.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.page)
    }

    /// The cards, with amounts in the currency the results were calculated in.
    @ViewBuilder
    private func resultCards(_ results: PlanResults) -> some View {
        VStack(alignment: .leading, spacing: Metrics.l) {
            PlanHeadlineCard(session: session, results: results, isWide: isWide, onWhatIf: onWhatIf)
            if isWide {
                // Equal columns, not a Grid: the charts' widths mustn't feed back into their columns'.
                EqualColumns(spacing: Metrics.l) {
                    PlanSuccessCard(session: session, results: results)
                    PlanFanCard(session: session, results: results)
                }
                EqualColumns(spacing: Metrics.l) {
                    PlanIncomeCard(results: results)
                    VStack(spacing: Metrics.l) {
                        PlanKeyNumbersCard(results: results)
                        PlanFailureCard(results: results)
                        PlanLibraryCard(results: results)
                    }
                }
            } else {
                PlanSuccessCard(session: session, results: results)
                PlanFanCard(session: session, results: results)
                PlanIncomeCard(results: results)
                PlanFailureCard(results: results)
                PlanLibraryCard(results: results)
            }
        }
        .environment(\.baseCurrency, session.currency(of: results))
    }
}

/// The run's problems as banners: an error that stops the plan, and the
/// warnings of the results shown.
struct PlanResultsBanners: View {
    let session: PlanSession
    var limit = 2

    @Environment(PlanStore.self) private var plans

    var body: some View {
        VStack(spacing: Metrics.s) {
            if !plans.isAvailable {
                StatusBanner(.info, "The planner isn't available",
                             message: "Plans can't run in this version. Answers recorded at past check-ins are shown.")
            }
            if let error = session.runError {
                StatusBanner(.error, "The plan can't run", message: error)
            }
            if let error = session.saveError {
                StatusBanner(.error, "Your change wasn't saved", message: error)
            }
            let warnings = session.resultWarnings
            ForEach(Array(warnings.prefix(limit)), id: \.self) { warning in
                StatusBanner(.warning, warning)
            }
            if warnings.count > limit {
                Text("\(warnings.count - limit) more on the Inputs they concern.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Headline

/// "Can I retire yet? Not yet. Earliest at 54 · March 2042, in 9 of 10
/// simulated futures", with the chance today and what you could spend.
struct PlanHeadlineCard: View {
    let session: PlanSession
    let results: PlanResults
    var isWide = false
    var onWhatIf: (() -> Void)?

    @Environment(\.locale) private var locale

    private var headline: PlanHeadline { results.headline }

    private var whatIfTitle: String {
        session.hasWhatIf ? "What if… (changed)" : "What if…"
    }

    /// "54 → 53" while a what-if's own results move the earliest age.
    private var change: String? {
        guard session.hasWhatIf, !session.whatIfIsOutOfDate, session.baseIsUpToDate,
              let base = session.baseResults else { return nil }
        return PlanResultsText.change(from: base.headline.earliestAge, to: headline.earliestAge)
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Metrics.xs) {
                Text(PlanResultsText.answer(headline))
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(PlanResultsText.earliest(headline, locale: locale))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                if let change {
                    Label("Earliest \(change)", systemImage: "arrow.triangle.branch")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                }
                Text(PlanResultsText.confidence(headline.confidence))
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Metrics.xl) { stats }
                VStack(alignment: .leading, spacing: Metrics.s) { stats }
            }
            .padding(.top, Metrics.xs)
            PlanReadinessView(headline: headline, assetsNeeded: results.details?.assetsNeeded)
            Text(AboutText.disclaimer)
                .font(.footnote)
                .foregroundStyle(Palette.mutedInk)
            if let onWhatIf {
                Button {
                    onWhatIf()
                } label: {
                    Label(whatIfTitle, systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
            }
        } header: {
            SectionHeader("Can I retire yet?") {
                PlanRunStatus(session: session, results: results)
            }
        }
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: headline.earliestAge)
        #endif
    }

    @ViewBuilder
    private var stats: some View {
        if let today = headline.successToday {
            PlanStat(title: "Retiring today") {
                Text(AmountFormat.percent(today, digits: 0, locale: locale))
            }
        }
        if let spending = headline.sustainableSpending {
            let age = results.details?.sustainableSpendingAge ?? headline.targetAge
            PlanStat(title: age.map { "At \($0) you could spend" } ?? "You could spend") {
                HStack(spacing: 2) {
                    AmountText(spending, tabular: false)
                    Text("/yr")
                }
            }
        }
    }
}

/// How close today's plan assets are to what retiring today needs (UI.md,
/// "Can I retire yet?" and "Results"): a bar, "58% of what you'd need to
/// retire today" with an ⓘ that says what it compares, and, when a run's
/// details have it, "Needed to retire today: 1.240.000 €". It comes from the
/// same simulation as the chance of retiring today, so it reaches 100%
/// exactly when that chance reaches the plan's confidence. An answer
/// recorded before it existed shows `fallback`, if any, instead of its old
/// FI progress.
struct PlanReadinessView: View {
    let headline: PlanHeadline
    /// The search's result, from a run (a recorded answer has none).
    var assetsNeeded: AssetsNeeded?
    /// Shown when there's no readiness, e.g. ``PlanResultsText/readinessNotRecorded``.
    var fallback: String?

    @Environment(\.locale) private var locale
    @State private var showsExplanation = false

    var body: some View {
        if let text = PlanResultsText.readiness(headline, locale: locale) {
            VStack(alignment: .leading, spacing: Metrics.xs) {
                if let readiness = headline.readiness {
                    ProgressView(value: PlanResultsText.readinessBar(readiness))
                        .tint(Palette.accent)
                        .accessibilityHidden(true)
                }
                HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
                    Text(text)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    explanationButton
                }
                if let amount = neededAmount {
                    HStack(spacing: Metrics.xs) {
                        Text("Needed to retire today:")
                        AmountText(PlanResultsText.whole(amount), tabular: false)
                    }
                    .foregroundStyle(Palette.secondaryInk)
                    .accessibilityElement(children: .combine)
                }
            }
            .font(.footnote)
        } else if let fallback {
            Text(fallback)
                .font(.footnote)
                .foregroundStyle(Palette.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The amount, when the search found one.
    private var neededAmount: Double? {
        guard let assetsNeeded, assetsNeeded.outcome == .found else { return nil }
        return assetsNeeded.amount
    }

    private var explanationButton: some View {
        Button {
            showsExplanation = true
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(Palette.accent)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("About this number")
        .popover(isPresented: $showsExplanation) {
            Text(PlanResultsText.readinessExplanation(confidence: headline.confidence, locale: locale))
                .font(.callout)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Metrics.l)
                .frame(idealWidth: 320, maxWidth: 360, alignment: .leading)
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// A small figure with its title above, for the headline.
struct PlanStat<Value: View>: View {
    let title: String
    private let value: Value

    init(title: String, @ViewBuilder value: () -> Value) {
        self.title = title
        self.value = value()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
            value
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.ink)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The run in progress, in a card: the one part of the results that reads
/// the progress, so the rest doesn't redraw with each update.
private struct PlanRunProgressCard: View {
    let session: PlanSession

    var body: some View {
        if let progress = session.runProgress {
            Card {
                PlanRunProgressView(progress: progress, isCheckIn: session.isCheckInRun,
                                    onCancel: session.stateWithoutProgress.canCancel ? { session.cancel() } : nil)
            }
        }
    }
}

/// "2.000 runs · 09:41", "Out of date", or "Calculating 34%" while a run
/// is going.
struct PlanRunStatus: View {
    let session: PlanSession
    let results: PlanResults?

    @Environment(\.locale) private var locale

    var body: some View {
        let state = session.state
        HStack(spacing: Metrics.xs) {
            if let progress = state.progress {
                Text(PlanRunText.status(progress, isCheckIn: session.isCheckInRun, locale: locale))
                    .monospacedDigit()
            } else if let results {
                if state.isOutOfDate {
                    Label(PlanRunText.outOfDateTitle, systemImage: "clock.arrow.circlepath")
                        .foregroundStyle(Palette.warning)
                    Text("·")
                }
                Text(runs(results) + " · " + results.computedAt.formatted(.dateTime.hour().minute().locale(locale)))
            }
        }
        .font(.caption)
        .foregroundStyle(Palette.secondaryInk)
    }

    private func runs(_ results: PlanResults) -> String {
        let count = AmountFormat.number(Decimal(results.runs), locale: locale)
        return results.mode == .fast ? "\(count) runs (quick)" : "\(count) runs"
    }
}

// MARK: - Charts

/// Chance of success by retirement age. Tapping (or, on the Mac, resting
/// on) an age shows the charts below for retiring then; the stepper does
/// the same without the chart.
struct PlanSuccessCard: View {
    let session: PlanSession
    let results: PlanResults

    @State private var chartSelection: Int?

    private var focus: Int? { session.shownFocusAge }

    /// The ages the curve covers.
    private var ages: ClosedRange<Int>? {
        let ages = results.successByAge.map(\.age)
        guard let low = ages.min(), let high = ages.max() else { return nil }
        return low...high
    }

    var body: some View {
        @Bindable var session = session
        Card {
            SuccessCurveChart(points: results.successByAge, threshold: results.headline.confidence,
                              highlightedAge: results.headline.earliestAge, selectedAge: $chartSelection)
            #if os(iOS)
            .onChange(of: chartSelection) { oldValue, newValue in
                // The selection ends when the finger lifts: that's the tap.
                if newValue == nil, let oldValue { session.selectFocus(oldValue) }
            }
            #endif
            #if os(macOS)
            .task(id: chartSelection) {
                // Resting on an age for a moment chooses it.
                guard let age = chartSelection else { return }
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                session.selectFocus(age)
            }
            #endif
            if let note = PlanResultsText.pensionStepNote(results.details?.pensionSteps ?? []) {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let focus, let ages {
                Stepper(value: $session.editableFocusAge, in: ages) {
                    HStack(spacing: Metrics.xs) {
                        Text("Charts for retiring at \(focus)")
                            .font(.subheadline)
                        if let success = results.successByAge.first(where: { $0.age == focus })?.success {
                            Text("· \(AmountFormat.percent(success, digits: 0))")
                                .font(.subheadline)
                                .foregroundStyle(Palette.secondaryInk)
                        }
                    }
                }
            }
        } header: {
            SectionHeader("Chance of success by retirement age") {
                if session.focusAge != nil {
                    Button("Plan's age") { session.selectFocus(nil) }
                        .buttonStyle(.borderless)
                }
            }
        }
    }
}

/// Your money over time: the fan in one hue, your actual history in ink,
/// and markers for retirement, pensions, locked money and events. One
/// control sets the time span, how far back and how far ahead (shared with
/// the Overview's chart and remembered on the device), so the years that
/// matter aren't a sliver of a chart running to 95.
struct PlanFanCard: View {
    let session: PlanSession
    let results: PlanResults

    @Environment(LibraryStore.self) private var library
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.baseCurrency) private var currency
    @Environment(\.locale) private var locale
    @AppStorage("overview.range") private var range: OverviewRange = .threeYears

    /// Your actual plan assets in the results' currency, at each check-in's rate.
    private var actual: PlanActualSeries {
        PlanActualSeries(library: library.library, valuator: library.valuator, through: results.start.date,
                         currency: currency, inMoneyOf: results.start.date)
    }

    var body: some View {
        let now = results.start.date.dateValue
        let retirement = results.retirementDate
        let window = ProjectionWindow(now: now, range: range, horizon: preferences.futureHorizon,
                                      retirement: retirement, planEnd: results.portfolio.last?.date ?? now)
        let actual = actual
        let history = window.history(actual.points)
        let money = PlanMoney.todaysMoney(currency)
        Card {
            HStack {
                TimeSpanMenu(range: $range, horizon: preferences.horizonBinding(start: now, retirement: retirement),
                             choices: FutureHorizon.choices(start: now, retirement: retirement))
                Spacer(minLength: 0)
            }
            FanChart(fan: window.fan(results.portfolio), actual: history,
                     markers: window.markers(results.markers, from: history.first?.date ?? now), showsLegend: true)
            ChartCaption(
                text: "In \(money).",
                detail: "Your plan assets in \(money): your actual values in ink, then the plan's projection. "
                    + "The line is the median of the simulated futures, the darker band holds half of them and the "
                    + "lighter band 8 in 10; the lighter band can run off the top, so the rest stays readable. "
                    + "Markers show retirement, pensions starting, locked money becoming accessible, windfalls and "
                    + "large expenses. The time span menu sets how far back and ahead the chart reaches.")
            if let note = PlanMoney.missingRatesNote(actual.missingRates, base: library.baseCurrency, currency: currency,
                                                     locale: locale) {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !actual.points.isEmpty,
               let note = PlanMoney.standInNote(actual.inflation, currency: currency, locale: locale) {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SectionHeader((results.details?.focus.age ?? session.shownFocusAge)
                .map { "Your money over time · retiring at \($0)" } ?? "Your money over time")
        }
    }
}

/// The fan chart's key: actual, median and the two bands, for a fan chart
/// that doesn't show its own (`FanChart(showsLegend: false)`).
struct PlanFanLegend: View {
    var showsActual = true

    var body: some View {
        ProjectionLegend(showsActual: showsActual)
    }
}

/// Retirement income by source, or taxes by line (Income | Taxes).
struct PlanIncomeCard: View {
    let results: PlanResults
    @State private var showsTaxes = false
    @Environment(\.baseCurrency) private var currency

    var body: some View {
        let money = PlanMoney.todaysMoney(currency)
        Card {
            if showsTaxes {
                IncomeStackChart(segments: results.taxes)
                ChartCaption(
                    text: "Median run · \(money).",
                    detail: "The taxes of each year of retirement in the median run, by tax: on income and "
                        + "pensions, on gains when investments are sold (also to rebalance), on what's paid out "
                        + "of pension savings, and on wealth. In \(money).")
            } else {
                IncomeStackChart(segments: results.income, spending: results.spending)
                ChartCaption(
                    text: "Median run · \(money) · sources after tax.",
                    detail: "Where each year's money comes from in the median run, in \(money). Withdrawals "
                        + "are what's sold from your investments; they also pay the tax on the sale and the "
                        + "previous year's wealth tax, so in a rich run they can be well above your spending. "
                        + "Lump sums and payouts are paid whether they're needed or not: a pension taken partly "
                        + "as capital, severance pay when a job ends, and pension savings the rules pay out at an "
                        + "age or over a few years. So that the chart reads against the spending line, each source "
                        + "is shown after its share of the year's taxes, and the taxes paid from this income are the "
                        + "grey band on top. Taxes on rebalancing are paid inside the portfolio: see Taxes.")
            }
        } header: {
            SectionHeader("Retirement income") {
                Picker("Show", selection: $showsTaxes) {
                    Text("Income").tag(false)
                    Text("Taxes").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
    }
}

/// When it fails: how often, when money usually runs out, and bridge
/// failures (running out before locked money opens).
struct PlanFailureCard: View {
    let results: PlanResults
    @Environment(\.locale) private var locale

    var body: some View {
        let sentences = PlanResultsText.failureSentences(results.failure, locale: locale)
        if !sentences.isEmpty {
            Card(PlanResultsText.failureTitle(results.failure)) {
                ForEach(sentences, id: \.self) { sentence in
                    Text(sentence)
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// How the plan reads your library: the accounts grouped by tax wrapper,
/// with their value on the start date and how they're drawn, and accounts
/// whose value starts a pension scheme instead of being money to draw on
/// (UI.md, "Results").
struct PlanLibraryCard: View {
    let results: PlanResults
    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale

    var body: some View {
        let notes = results.details?.reading.map {
            PlanResultsText.libraryNotes($0, accounts: library.library.accounts, locale: locale)
        } ?? []
        if !notes.isEmpty {
            Card("How the plan reads your library") {
                ForEach(notes) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                            Text(note.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                            Spacer(minLength: Metrics.s)
                            if let amount = note.amount {
                                AmountText(amount)
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.ink)
                            }
                        }
                        Text(note.detail)
                            .font(.footnote)
                            .foregroundStyle(Palette.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// The key numbers beside the charts (Mac and iPad).
struct PlanKeyNumbersCard: View {
    let results: PlanResults
    @Environment(\.locale) private var locale

    var body: some View {
        Card("Key numbers") {
            Grid(alignment: .leading, horizontalSpacing: Metrics.m, verticalSpacing: Metrics.s) {
                ForEach(PlanResultsText.keyNumbers(results, locale: locale)) { row in
                    GridRow {
                        Text(row.label)
                            .foregroundStyle(Palette.secondaryInk)
                        PlanFigureText(figure: row.value)
                            .fontWeight(row.isEmphasized ? .semibold : .regular)
                            .gridColumnAlignment(.trailing)
                    }
                }
            }
            .font(.subheadline)
        }
    }
}

/// A figure: amounts go through `AmountText`, so they hide with the others.
struct PlanFigureText: View {
    let figure: PlanFigure
    @Environment(\.locale) private var locale

    var body: some View {
        switch figure {
        case .amount(let amount, let unit):
            HStack(spacing: 2) {
                AmountText(amount)
                if let unit { Text(unit) }
            }
        case .amountIn(let amount, let currency, let unit):
            HStack(spacing: 2) {
                AmountText(amount, currency: currency)
                if let unit { Text(unit) }
            }
        case .percent(let share):
            Text(AmountFormat.percent(share, digits: 0, locale: locale))
                .monospacedDigit()
        case .text(let text):
            Text(text)
                .monospacedDigit()
        case .missing:
            Text("–")
                .foregroundStyle(Palette.mutedInk)
        }
    }
}

#Preview("Results · iPhone") {
    PlanResultsPreview(isWide: false)
}

#Preview("Results · Mac") {
    PlanResultsPreview(isWide: true)
        .frame(width: 1_000, height: 900)
}

/// A session on the preview library with results, for previews.
struct PlanResultsPreview: View {
    var isWide = false
    @State private var model = AppModel.preview(planEngine: PlanPreviewEngine())

    var body: some View {
        PlanPreviewHost(model: model) { session in
            PlanResultsView(session: session, isWide: isWide, onWhatIf: isWide ? nil : {})
        }
    }
}

/// Makes a session for the preview library's base plan and calculates it,
/// as the Calculate button would.
struct PlanPreviewHost<Content: View>: View {
    let model: AppModel
    private let content: (PlanSession) -> Content
    @State private var session: PlanSession

    init(model: AppModel, plan: PlanID = "base", @ViewBuilder content: @escaping (PlanSession) -> Content) {
        self.model = model
        self.content = content
        _session = State(initialValue: PlanSession(planID: plan, library: model.library, plans: model.plans))
    }

    var body: some View {
        NavigationStack {
            content(session)
        }
        .previewEnvironment(model: model)
        .task { session.calculate() }
    }
}
