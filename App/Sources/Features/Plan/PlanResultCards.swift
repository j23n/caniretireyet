import Charts
import Glance
import Model
import Planner
import SwiftUI
import Tracker

// The cards behind the plan's answer (UI.md, "Plan", "More charts"): your
// money over time, the chance of success by retirement age, retirement
// income and taxes, the tiles and the assumptions on iPhone, and the key
// numbers on the Mac and iPad; and the run's banners and status the Plan
// view shows above them.


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

/// Chance of success by retirement age, inside the answer's card on the
/// Mac and iPad. Tapping or clicking an age cuts the chapters at it;
/// dragging across the curve, or on the Mac hovering over it, only reads
/// it. The stepper chooses an age without the chart.
struct PlanSuccessChart: View {
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
        VStack(alignment: .leading, spacing: Metrics.s) {
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
                HStack(spacing: Metrics.m) {
                    Stepper(value: Binding(get: { session.shownFocusAge ?? 55 }, set: { session.selectFocus($0) }),
                            in: ages) {
                        HStack(spacing: Metrics.xs) {
                            Text("Chapters for stopping at \(focus)")
                                .lineLimit(1)
                            if let success = results.successByAge.first(where: { $0.age == focus })?.success {
                                Text(verbatim: "· \(PlanTimelineText.tenths(success)) in 10")
                                    .foregroundStyle(Palette.secondaryInk)
                                    .lineLimit(1)
                            }
                        }
                        .font(.subheadline)
                    }
                    .personalControl()
                    if session.focusAge != nil {
                        Button("Plan's age") { session.selectFocus(nil) }
                            .buttonStyle(.borderless)
                            .font(.subheadline)
                            .fixedSize()
                    }
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

// MARK: - Tiles

/// The plan's results as tiles on iPhone (UI.md, "The plan"): what you
/// could spend a month from the age the chapters are cut at, the age you
/// could stop saving nothing more (``CoastAgeTile``), and how sure you'd be
/// stopping at the ages around the answer (``PlanStopAgesTile``).
struct PlanResultTiles: View {
    let session: PlanSession
    let results: PlanResults
    let milestones: PlanMilestones?

    @Environment(\.locale) private var locale

    var body: some View {
        let headline = results.headline
        TileGrid {
            if let spending = headline.sustainableSpending {
                spendTile(spending, age: results.details.sustainableSpendingAge ?? headline.targetAge)
                    .tileSize(.small)
            }
            if let milestones, milestones.knowsCoastAge {
                CoastAgeTile(age: milestones.coastAge, target: milestones.ladder.coastTarget)
                    .tileSize(headline.sustainableSpending == nil ? .wide : .small)
            }
            if !results.successByAge.isEmpty {
                PlanStopAgesTile(session: session, results: results)
                    .tileSize(.wide)
            }
        }
    }

    /// "🛍️ You could spend from 63", "2.350 €", "a month, in 9 of 10 futures".
    private func spendTile(_ yearly: Decimal, age: Int?) -> some View {
        ColorTile(tint: .butter) {
            TileLabel(age.map { "You could spend from \($0)" } ?? "You could spend", emoji: "🛍️")
                .privacySensitiveInFeedback()
            Spacer(minLength: Metrics.s)
            AmountText(yearly / 12, currency: session.currency, tabular: false)
                .font(.title.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(verbatim: "a month, in \(GlanceText.futures(results.headline.confidence)) futures")
                .font(.caption)
                .opacity(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .privacySensitiveInFeedback()
        }
        .accessibilityElement(children: .combine)
    }
}

/// How sure you'd be stopping at the ages around the answer, as a wide
/// tile (UI.md, "The plan"): "🎯 If you stopped at another age", what that
/// means ("How many of 10 futures keep your money lasting to 95."), a bar
/// for each age to the height of the futures it lasts in, the answer's in
/// the accent and the age the chapters are cut at outlined, a dotted rule
/// at the plan's bar, and the answer in words. Tapping an age cuts the
/// chapters at it, as the chart on the Mac does.
struct PlanStopAgesTile: View {
    let session: PlanSession
    let results: PlanResults

    /// The ages either side of the answer that the tile shows.
    private static let shown = 11
    private static let barsHeight: CGFloat = 76

    /// Up to 11 ages around the answer: the earliest age, else the plan's.
    private var points: [SuccessPoint] {
        let all = results.successByAge.sorted { $0.age < $1.age }
        let anchor = results.headline.earliestAge ?? results.headline.targetAge ?? all.first?.age ?? 0
        guard let index = all.firstIndex(where: { $0.age >= anchor }) else { return Array(all.suffix(Self.shown)) }
        let start = max(0, min(index - 7, all.count - Self.shown))
        return Array(all[start..<min(all.count, start + Self.shown)])
    }

    var body: some View {
        let points = self.points
        let end = results.details.endAge
        let earliest = results.headline.earliestAge
        let focus = session.shownFocusAge
        ColorTile {
            TileLabel("If you stopped at another age", emoji: "🎯")
            Text("How many of 10 futures keep your money lasting to \(end).")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .privacySensitiveInFeedback()
                .padding(.top, Metrics.xs)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(points) { point in
                    Button {
                        session.selectFocus(point.age == earliest ? nil : point.age)
                    } label: {
                        bar(point, isAnswer: point.age == earliest, isFocus: point.age == focus)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: "At \(point.age), \(PlanTimelineText.tenths(point.success)) in 10"))
                    .accessibilityHint("Shows the chapters for stopping then")
                }
            }
            .overlay(alignment: .top) {
                rule
            }
            .padding(.top, Metrics.m)
            .privacySensitiveInFeedback()
            if let words = words(points, earliest: earliest) {
                Text(verbatim: words)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .privacySensitiveInFeedback()
                    .padding(.top, Metrics.s)
            }
        }
    }

    /// An age's bar over its age.
    private func bar(_ point: SuccessPoint, isAnswer: Bool, isFocus: Bool) -> some View {
        VStack(spacing: Metrics.xs) {
            ZStack(alignment: .bottom) {
                Color.clear
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(isAnswer ? Palette.accent : Palette.accent.opacity(0.28))
                    .frame(height: max(3, Self.barsHeight * CGFloat(min(1, max(0, point.success)))))
                    .overlay {
                        if isFocus && !isAnswer {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(Palette.accent, lineWidth: 2)
                        }
                    }
            }
            .frame(height: Self.barsHeight)
            Text(verbatim: "\(point.age)")
                .font(.caption2.weight(isAnswer ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(isAnswer ? Palette.accent : Palette.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    /// The plan's bar, dotted across at its height.
    private var rule: some View {
        let bar = results.headline.confidence
        return Path { path in
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: 2_000, y: 0))
        }
        .stroke(Palette.mutedInk, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        .frame(height: 1)
        .clipped()
        .offset(y: Self.barsHeight * CGFloat(1 - min(1, max(0, bar))))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// "Stop at 63: 9 in 10. Stop at 60: 6 in 10."; the second three years
    /// sooner, when it's shown.
    private func words(_ points: [SuccessPoint], earliest: Int?) -> String? {
        guard let earliest, let answer = points.first(where: { $0.age == earliest }) else { return nil }
        var words = "Stop at \(earliest): \(PlanTimelineText.tenths(answer.success)) in 10."
        if let sooner = points.first(where: { $0.age == earliest - 3 }) {
            words += " Stop at \(sooner.age): \(PlanTimelineText.tenths(sooner.success)) in 10."
        }
        return words
    }
}

// MARK: - Assumptions

/// *Assumptions* on iPhone (UI.md, "The plan"): what every chapter shares, a
/// row each on one card, opening *Assumptions…*; the target mix opens its
/// own sheet.
struct PlanAssumptionRows: View {
    let session: PlanSession
    var onAssumptions: () -> Void = {}
    var onTargetMix: () -> Void = {}

    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale

    var body: some View {
        if let plan = session.plan {
            let summaries = PlanInputSummaries(plan: plan, library: library.library, currency: session.currency,
                                               locale: locale)
            CardRows {
                ForEach(summaries.rows) { row in
                    Button {
                        if row.section == .targetMix { onTargetMix() } else { onAssumptions() }
                    } label: {
                        CardRow(opens: true) {
                            Text(row.label)
                        } value: {
                            AmountSentenceText(row.value)
                                .monospacedDigit()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .accessibilityHint("Shows what every chapter assumes")
        }
    }
}

/// The Mac's and iPad's column beside the chapters: the key numbers, then
/// the assumptions, each a card of rows. An assumption opens
/// *Assumptions…*, the target mix its own sheet.
struct PlanInspector: View {
    let session: PlanSession
    var onAssumptions: () -> Void = {}
    var onTargetMix: () -> Void = {}

    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale

    var body: some View {
        let words = PlanWords(currency: session.currency, locale: locale)
        VStack(alignment: .leading, spacing: Metrics.m) {
            if let results = session.state.results {
                Card("Key numbers") {
                    PlanTableRows {
                        ForEach(PlanResultsText.keyNumbers(results, words: words)) { row in
                            PlanTableRow(row.label, personalLabel: row.personalLabel) {
                                AmountSentenceText(row.value)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
            if let plan = session.plan {
                let summaries = PlanInputSummaries(plan: plan, library: library.library, currency: session.currency,
                                                   locale: locale)
                Card {
                    PlanTableRows {
                        ForEach(summaries.rows) { row in
                            Button {
                                if row.section == .targetMix { onTargetMix() } else { onAssumptions() }
                            } label: {
                                PlanTableRow(row.label, personalLabel: false, opens: true) {
                                    AmountSentenceText(row.value)
                                        .monospacedDigit()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    SectionHeader("Assumptions") {
                        Button("Edit…", action: onAssumptions)
                            .buttonStyle(.borderless)
                    }
                }
            }
        }
    }
}

/// Rows of a table on a card, a hairline between them (the Mac's denser
/// ``CardRows``).
struct PlanTableRows<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(rows) { row in
                    if row.id != rows.first?.id {
                        Divider()
                    }
                    row
                }
            }
        }
    }
}

/// A row of a table: its label on the left in grey, its value on the right,
/// each on one line; the label gives way first.
struct PlanTableRow<Value: View>: View {
    let label: String
    var personalLabel = false
    var opens = false
    private let value: Value

    init(_ label: String, personalLabel: Bool = false, opens: Bool = false, @ViewBuilder value: () -> Value) {
        self.label = label
        self.personalLabel = personalLabel
        self.opens = opens
        self.value = value()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Text(label)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
                .privacySensitiveInFeedback(personalLabel)
            Spacer(minLength: Metrics.s)
            value
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .layoutPriority(1)
            if opens {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.mutedInk)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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
