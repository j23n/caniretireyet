import Charts
import Model
import Planner
import SwiftUI

// The cards behind the plan's answer (UI.md, "Plan", "More charts"): your
// money over time, the chance of success by retirement age, retirement
// income and taxes, and the key numbers; and the run's banners and status
// the Plan view shows above them.


/// What stops the plan from answering, above the answer: the planner
/// isn't available, the plan can't run, a change wasn't saved.
struct PlanResultsBanners: View {
    let session: PlanSession

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
        }
    }
}

/// What the answer assumed that you may want to change, under it, quietly
/// (UI.md, "Plan"): "TFR counts as cash: it has no mix of investments set.
/// Set one…", which opens the account. The first two; the rest show with
/// the inputs they concern.
struct PlanResultWarnings: View {
    let session: PlanSession
    var limit = 2

    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        let warnings = session.resultWarnings
        // What "Set one…" needs, without the view.
        let navigation = self.navigation
        let scheme = Self.accountScheme
        if !warnings.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.xs) {
                ForEach(Array(warnings.prefix(limit)), id: \.message) { issue in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(Palette.secondaryInk)
                            .accessibilityHidden(true)
                        Text(text(for: issue))
                            .foregroundStyle(Palette.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if warnings.count > limit {
                    Text("\(warnings.count - limit) more below, with the inputs they concern.")
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metrics.xs)
            // "Set one…" opens the account the warning is about.
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == scheme, let id = url.host() else { return .systemAction }
                MainActor.assumeIsolated { navigation.showAccount(AccountID(rawValue: id)) }
                return .handled
            })
        }
    }

    /// The links' scheme: "Set one…" leads to an account, inside the app.
    private static let accountScheme = "plan-warning-account"

    /// The warning in words, with a link where it can be fixed.
    private func text(for issue: PlanIssue) -> AttributedString {
        var text = AttributedString(issue.message)
        if issue.code == "planner.noAssetMix", let account = issue.account,
           let url = URL(string: "\(Self.accountScheme)://\(account.rawValue)") {
            var link = AttributedString("Set one…")
            link.link = url
            link.foregroundColor = Palette.accent
            text += AttributedString(" ") + link
        }
        return text
    }
}

/// How close today's plan assets are to what retiring today needs (UI.md,
/// "Can I retire yet?"; the plan's key numbers say it too): a bar, "58% of
/// what you'd need to retire today" with an ⓘ that says what it compares,
/// and, when a run's details have it, "Needed to retire today: 1.240.000 €".
/// It comes from the same simulation as the chance of retiring today, so it
/// reaches 100% exactly when that chance reaches the plan's confidence. An
/// answer recorded before it existed shows `fallback`, if any, instead of
/// its old FI progress.
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

/// The run in progress, in a card: the one part of the results that reads
/// the progress, so the rest doesn't redraw with each update.
struct PlanRunProgressCard: View {
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

// MARK: - Charts

/// Chance of success by retirement age. Tapping or clicking an age shows
/// the charts below for retiring then; dragging across the curve, or on
/// the Mac hovering over it, only reads it. The stepper chooses an age
/// without the chart.
struct PlanSuccessCard: View {
    let session: PlanSession
    let results: PlanResults

    /// The age being read on the curve (a finger on it, or the pointer over it).
    @State private var chartSelection: Int?
    /// The age read last and when that reading ended: lifting the finger
    /// (or the mouse button) can end it before the tap is recognised.
    @State private var lastReading: Int?
    @State private var lastReadingEnded = Date.distantPast

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
            .onChange(of: chartSelection) { oldValue, newValue in
                if newValue == nil, let oldValue {
                    lastReading = oldValue
                    lastReadingEnded = Date.now
                }
            }
            // Only a tap or a click chooses the age; reading the curve changes nothing.
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { chooseTappedAge() })
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

    /// Chooses the age under a tap or click: the one being read, or the
    /// one whose reading the tap's lift just ended. A tap where no age is
    /// read (an axis label) chooses nothing.
    private func chooseTappedAge() {
        let justRead = Date.now.timeIntervalSince(lastReadingEnded) < 0.5 ? lastReading : nil
        if let age = chartSelection ?? justRead { session.selectFocus(age) }
    }
}

/// Your money over time (UI.md, "More charts"): the fan in one hue, your
/// actual history in ink, and markers for retirement, pensions, locked
/// money and events. One control sets the time span, how far back and how
/// far ahead (shared with the Overview's chart and remembered on the
/// device), so the years that matter aren't a sliver of a chart running to 95.
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
                    detail: "The taxes of each year of retirement in the median run: on investments (the gain in "
                        + "what's sold, and the income your investments pay) and on wealth. Income from work, "
                        + "pensions and other income is entered after tax. In \(money).")
            } else {
                IncomeStackChart(segments: results.income, spending: results.spending)
                ChartCaption(
                    text: "Median run · \(money) · sources after tax.",
                    detail: "Where each year's money comes from in the median run, in \(money). Withdrawals "
                        + "are what's sold from your investments; they also pay the tax on the gain in the sale, "
                        + "the wealth tax and last year's tax on investment income. So that the chart reads against "
                        + "the spending line, each source is shown after its share of the year's taxes, and the "
                        + "taxes are the grey band on top.")
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
