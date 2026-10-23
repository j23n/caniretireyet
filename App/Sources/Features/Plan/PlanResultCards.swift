import Charts
import Model
import Planner
import SwiftUI
import Tracker

// The cards behind the plan's answer (UI.md, "Plan", "More charts"): your
// money over time, the chance of success by retirement age, retirement
// income and taxes, and the key numbers; and the run's banners and status
// the Plan view shows above them.


/// What stops the plan from answering, above the answer: the plan can't
/// run, a change wasn't saved.
struct PlanResultsBanners: View {
    let session: PlanSession

    var body: some View {
        VStack(spacing: Metrics.s) {
            if let error = session.runError {
                StatusBanner(.error, "The plan can't run", message: error, personal: .message)
            }
            if let error = session.saveError {
                StatusBanner(.error, "Your change wasn't saved", message: error, personal: .message)
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
                            .privacySensitiveInFeedback()
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

/// The run in progress, in a card: the one part of the results that reads
/// the progress, so the rest doesn't redraw with each update.
struct PlanRunProgressCard: View {
    let session: PlanSession

    var body: some View {
        if let progress = session.runProgress {
            Card {
                PlanRunProgressView(progress: progress, isCheckIn: session.isCheckInRun,
                                    onCancel: session.state.canCancel ? { session.cancel() } : nil)
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
                Stepper(value: Binding(get: { session.shownFocusAge ?? 55 }, set: { session.selectFocus($0) }),
                        in: ages) {
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
                .personalControl()
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
                            .privacySensitiveInFeedback()
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
                .privacySensitiveInFeedback()
        case .text(let text):
            Text(text)
                .monospacedDigit()
                .privacySensitiveInFeedback()
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
        .appEnvironment(model)
        .task { session.calculate() }
    }
}
