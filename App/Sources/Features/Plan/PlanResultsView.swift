import Charts
import Model
import SwiftUI

/// Results (UI.md, "Results"): the headline, the chance of success by
/// retirement age, the money over time, retirement income, when it fails
/// and, on the Mac and iPad, the key numbers. On iPhone the What-if panel
/// opens from the headline; on the Mac it's in the inspector.
struct PlanResultsView: View {
    let session: PlanSession
    /// The sidebar layout: two columns and the key numbers.
    var isWide = false
    /// Opens the What-if sheet (iPhone).
    var onWhatIf: (() -> Void)?

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.l) {
                PlanResultsBanners(session: session)
                if let results = session.shownResults {
                    PlanHeadlineCard(session: session, results: results, isWide: isWide, onWhatIf: onWhatIf)
                    if isWide {
                        Grid(alignment: .topLeading, horizontalSpacing: Metrics.l, verticalSpacing: Metrics.l) {
                            GridRow {
                                PlanSuccessCard(session: session, results: results)
                                PlanFanCard(session: session, results: results)
                            }
                            GridRow {
                                PlanIncomeCard(results: results)
                                VStack(spacing: Metrics.l) {
                                    PlanKeyNumbersCard(results: results)
                                    PlanFailureCard(results: results)
                                }
                            }
                        }
                    } else {
                        PlanSuccessCard(session: session, results: results)
                        PlanFanCard(session: session, results: results)
                        PlanIncomeCard(results: results)
                        PlanFailureCard(results: results)
                    }
                } else {
                    PlanResultsPlaceholder(session: session)
                }
            }
            .padding(Metrics.l)
            .frame(maxWidth: isWide ? 1_120 : Metrics.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.page)
    }
}

/// Before the first results: running, or why the plan can't run.
private struct PlanResultsPlaceholder: View {
    let session: PlanSession
    @Environment(PlanStore.self) private var plans

    var body: some View {
        Card("Can I retire yet?") {
            if session.isRunning {
                HStack(spacing: Metrics.s) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Simulating…")
                        .foregroundStyle(Palette.secondaryInk)
                }
            } else if plans.isAvailable, session.runError == nil {
                Button("Run the plan") {
                    Task { await session.refresh() }
                }
            } else {
                Text("No answer yet.")
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
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
            let warnings = PlanResultsText.warnings(session.shownResults)
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

    /// "54 → 53" while a what-if moves the earliest age.
    private var change: String? {
        guard session.hasWhatIf, let base = session.baseResults else { return nil }
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
        if isWide, let progress = headline.fiProgress {
            PlanStat(title: "Progress to FI") {
                Text(AmountFormat.percent(progress, digits: 0, locale: locale))
            }
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

/// "2.000 runs · updated 09:41", or a spinner while a run is going.
struct PlanRunStatus: View {
    let session: PlanSession
    let results: PlanResults?

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: Metrics.xs) {
            if session.isRunning {
                ProgressView()
                    .controlSize(.small)
                Text("Updating…")
            } else if let results {
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
/// and markers for retirement, pensions, locked money and events.
struct PlanFanCard: View {
    let session: PlanSession
    let results: PlanResults

    @Environment(LibraryStore.self) private var library

    private var actual: [ChartPoint] {
        PlanActualHistory.points(library: library.library, valuator: library.valuator, through: results.start.date,
                                 inEurosOf: results.start.date)
    }

    var body: some View {
        Card {
            PlanFanLegend(showsActual: true)
            FanChart(fan: results.portfolio, actual: actual, markers: results.markers)
            Text("In today's euros. Markers: retirement, pensions, locked money opening, windfalls and expenses.")
                .font(.caption)
                .foregroundStyle(Palette.mutedInk)
        } header: {
            SectionHeader(session.shownFocusAge.map { "Your money over time · retiring at \($0)" }
                ?? "Your money over time")
        }
    }
}

/// The fan chart's key: actual, median and the two bands.
struct PlanFanLegend: View {
    var showsActual = true

    var body: some View {
        HStack(spacing: Metrics.m) {
            if showsActual {
                item("Actual") { Capsule().fill(Palette.ink).frame(width: 14, height: 2) }
            }
            item("Median") { Capsule().fill(Palette.accent).frame(width: 14, height: 2) }
            item("25–75%") { RoundedRectangle(cornerRadius: 2).fill(Palette.accent.opacity(0.28)).frame(width: 14, height: 10) }
            item("10–90%") { RoundedRectangle(cornerRadius: 2).fill(Palette.accent.opacity(0.14)).frame(width: 14, height: 10) }
        }
        .font(.caption)
        .foregroundStyle(Palette.secondaryInk)
        .accessibilityElement(children: .combine)
    }

    private func item<Swatch: View>(_ title: String, @ViewBuilder swatch: () -> Swatch) -> some View {
        HStack(spacing: Metrics.xs) {
            swatch()
            Text(title)
        }
    }
}

/// Retirement income by source, or taxes by line (Income | Taxes).
struct PlanIncomeCard: View {
    let results: PlanResults
    @State private var showsTaxes = false

    var body: some View {
        Card {
            Text("Median run · today's euros")
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
            if showsTaxes {
                IncomeStackChart(segments: results.taxes)
            } else {
                IncomeStackChart(segments: results.income, spending: results.spending)
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

/// Makes a session for the preview library's base plan and runs it.
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
        .task { await session.refresh() }
    }
}
