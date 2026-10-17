import Glance
import Model
import Planner
import SwiftUI

/// The top of the Overview while the main plan has an answer (UI.md, "Can I
/// retire yet?"): the answer in a tile of its own, then the *Net worth* and
/// *On track?* tiles under it. Everything starts at the tiles' leading edge.
///
/// - **Title row:** "Can I retire yet?", "First sketch" while starting
///   estimates are open (``OnboardingSketchChip``), and the chevron at the
///   trailing edge, above *On track?*'s.
///   The tile opens the plan, with a tap gesture rather than as a button, so
///   *Calculate* gets its own tap; the chevron is the button VoiceOver and
///   keyboards use.
/// - **The ring** (``ReadinessRing``) at the leading edge, with the
///   percentage inside it, by the *Readiness* widget's rules
///   (``ReadinessFigure``); it laps past 100%.
/// - **The answer's words** at the ring's right: the headline ("In 15
///   years", "Yes", "Not yet", or "At 54" without a time to go), when ("Age
///   54 · March 2042"), then the run status ("◷ As of 30 Sep" for an answer
///   recorded at a check-in, *Calculate* when the results are out of date,
///   "Calculating 29%"). Out-of-date results dim
///   the ring and the words, as the Plan screen dims them.
/// - **Tiles:** net worth with its changes, and where the latest check-in
///   stands against its baseline (opening Progress) with the coast point
///   line. Side by side and as tall as each other; stacked at the largest
///   text sizes.
struct OverviewHeader: View {
    /// The main plan's latest answer (``PlanStore/mainAnswer``).
    let headline: RetirementAnswer
    let plan: PlanDocument
    let netWorth: NetWorthGlance
    /// The day the Overview reports on.
    let today: CalendarDate

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.pageLayout) private var layout
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.redactionReasons) private var redactionReasons

    private var hidesAmounts: Bool { redactionReasons.hidesAmounts }

    /// Out-of-date answers dim as the Plan screen dims its results.
    private static let dimmedOpacity = 0.7
    /// The ring's size, the same at every text size.
    private static let ringSize: CGFloat = 144
    private static let ringLineWidth: CGFloat = 12

    var body: some View {
        let words = OverviewAnswerText(headline: headline, earliestDate: headline.earliestDate, today: today,
                                       locale: locale)
        let dims = dimsAnswer
        VStack(alignment: .leading, spacing: tileSpacing) {
            answerTile(words, dims: dims)
            tiles(dims: dims)
        }
    }

    // MARK: Answer

    /// The question, the ring and the answer's words in a tile as wide as
    /// the two under it; a tap anywhere but *Calculate* opens the plan.
    private func answerTile(_ words: OverviewAnswerText, dims: Bool) -> some View {
        FigureTile(surface: .raised) {
            titleRow
            answerRow(words, dims: dims)
                .padding(.top, Metrics.m)
            if headline.recordedOn != nil, headline.readiness == nil {
                // Recorded before readiness existed: its old FI progress disagreed with the
                // chance of retiring today, so a neutral line instead of a ring.
                Text(PlanResultsText.readinessNotRecorded)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Metrics.s)
            }
            if let error = plans.errors[plan.id], headline.recordedOn != nil || isStale {
                cantCalculate(error)
                    .padding(.top, Metrics.s)
            }
        }
        .font(.subheadline)
        .onTapGesture {
            navigation.showPlan()
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open the plan") {
            navigation.showPlan()
        }
    }

    /// "Can I retire yet?", and the chevron at the trailing edge.
    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Text("Can I retire yet?")
                .font(.title2.bold())
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if !library.library.openStartingEstimates.isEmpty {
                OnboardingSketchChip(showsDisclaimer: false)
            }
            Spacer(minLength: Metrics.xs)
            Button {
                navigation.showPlan()
            } label: {
                Image(systemName: "chevron.right")
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.mutedInk)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Open the plan")
        }
    }

    /// Under the answer's words: a calculation going on, when the answer was
    /// recorded, or *Calculate* when the results are out of date. Why the
    /// plan can't be calculated has a line of its own under the answer.
    @ViewBuilder
    private var runStatus: some View {
        if let progress = plans.progress(of: plan.id, .checkIn) ?? plans.progress(of: plan.id, .base) {
            Text(verbatim: "Calculating \(PlanRunText.overall(progress, locale: locale))")
                .monospacedDigit()
                .foregroundStyle(Palette.secondaryInk)
                .accessibilityLabel(Text(verbatim: PlanRunText.accessibility(
                    progress, isCheckIn: plans.isRunning(plan.id, .checkIn), locale: locale)))
        } else if let recorded = headline.recordedOn {
            Label("As of \(AmountFormat.shortDate(recorded, locale: locale))", systemImage: "clock")
                .foregroundStyle(Palette.secondaryInk)
                .privacySensitiveInFeedback()
                .accessibilityLabel(Text(verbatim:
                    "As recorded at the check-in on \(AmountFormat.mediumDate(recorded, locale: locale))"))
        } else if isStale, plans.errors[plan.id] == nil {
            Button("Calculate") { Task { await plans.run(plan.id) } }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    /// "Base case can't be calculated: …", with *Try Again* and *Open Plan*.
    private func cantCalculate(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Label("\(plan.name) can't be calculated: \(error)", systemImage: "exclamationmark.triangle")
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .privacySensitiveInFeedback()
            HStack(spacing: Metrics.s) {
                Button("Try Again") { Task { await plans.run(plan.id) } }
                Button("Open Plan") { navigation.showPlan(plan.id) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: Ring and words

    /// The ring at the leading edge and the answer's words at its right;
    /// at the largest text sizes the words go under the ring. VoiceOver
    /// reads the headline and the ring as one element.
    private func answerRow(_ words: OverviewAnswerText, dims: Bool) -> some View {
        let figure = headline.readinessFigure
        let percent = figure.text { AmountFormat.percent($0, digits: 0, locale: locale) }
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Metrics.m))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Metrics.l))
        return layout {
            if let percent {
                ring(figure, percent: percent)
                    .opacity(dims ? Self.dimmedOpacity : 1)
            }
            VStack(alignment: .leading, spacing: Metrics.s) {
                answerWords(words, nextToRing: percent != nil)
                    .opacity(dims ? Self.dimmedOpacity : 1)
                runStatus
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The headline, then when; the headline in largeTitle when there's no
    /// ring beside it.
    private func answerWords(_ words: OverviewAnswerText, nextToRing: Bool) -> some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            Text(words.title)
                .font(nextToRing ? .title.bold() : .largeTitle.bold())
                .foregroundStyle(Palette.ink)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            if let when = words.whenLine {
                Text(verbatim: when)
                    .foregroundStyle(Palette.ink)
            }
            if let move = yearMove {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: move.lead)
                        .fontWeight(.semibold)
                        .foregroundStyle(move.isSooner ? Palette.positive : Palette.ink)
                    Text(verbatim: move.detail)
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                }
                .padding(.top, Metrics.xs)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .privacySensitiveInFeedback()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [words.spoken, yearMove.map { "\($0.lead) \($0.detail)." }]
            .compactMap(\.self).joined(separator: " ")))
        .accessibilityAddTraits(.isHeader)
    }

    /// How the age you could retire at moved in a year (UI.md, "Can I retire
    /// yet?"): "2 years sooner" over "than a year ago, at 56", against the
    /// answer recorded at the check-in a year ago; `nil` when it didn't
    /// move, or there's no answer from then.
    private var yearMove: (lead: String, detail: String, isSooner: Bool)? {
        guard let age = headline.earliestAge, !headline.canRetireNow,
              let then = library.library.headlines(for: plan.id).last(where: { $0.date <= today.adding(years: -1) }),
              let before = then.earliestAge, before != age
        else { return nil }
        let years = abs(age - before)
        let count = years == 1 ? "A year" : "\(years) years"
        return (count + (age < before ? " sooner" : " later"), "than a year ago, at \(before)", age < before)
    }

    /// The ring, with the percentage and "ready" inside it; it keeps its
    /// size at every text size, and the percentage shrinks to fit.
    private func ring(_ figure: ReadinessFigure, percent: String) -> some View {
        ZStack {
            ReadinessRing(fraction: figure.lappingFill, lineWidth: Self.ringLineWidth, laps: true)
                .privacySensitiveInFeedback()
            VStack(spacing: 0) {
                Text(verbatim: percent)
                    .font(.system(size: 32, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .privacySensitiveInFeedback()
                Text("ready")
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(Self.ringLineWidth + Metrics.s)
        }
        .frame(width: Self.ringSize, height: Self.ringSize)
        .accessibilityHidden(true)
    }

    // MARK: Tiles

    /// *Net worth* and *On track?*: side by side, 12 points apart on iPhone
    /// and 16 on the Mac and iPad, as tall as each other; stacked, *Net
    /// worth* first, at the largest text sizes.
    @ViewBuilder
    private func tiles(dims: Bool) -> some View {
        let onTrack = OverviewOnTrack(plan: plan, library: library.library, valuator: library.valuator,
                                      asOf: library.asOfDate, results: plans.latestResults(of: plan.id),
                                      canRetireNow: headline.canRetireNow, locale: locale)
        let spacing = tileSpacing
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: spacing) {
                netWorthTile
                onTrackTile(onTrack, dims: dims)
            }
        } else {
            EqualColumns(spacing: spacing, equalHeights: true) {
                netWorthTile
                onTrackTile(onTrack, dims: dims)
            }
        }
    }

    /// Net worth today, with its changes ("▲ 4.210 € in September", "▲ 6,2%
    /// this year"), as the hero number has them.
    private var netWorthTile: some View {
        FigureTile(surface: .raised) {
            Text("Net worth")
                .foregroundStyle(Palette.secondaryInk)
            AmountText(netWorth.total, tabular: false, animatesChanges: true)
                .font(.title.bold())
                .foregroundStyle(Palette.ink)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let change = netWorth.sinceLastCheckIn {
                pair {
                    DeltaText(change.change)
                } then: {
                    // "in September", "31 Jul – 15 Sep": the check-in's change, not one up to today.
                    Text(GlanceText.period(from: change.from, to: change.to, relativeTo: netWorth.date))
                        .foregroundStyle(Palette.secondaryInk)
                        .privacySensitiveInFeedback()
                }
            }
            if let year = netWorth.thisYear {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
                    DeltaText(percent: year)
                    Text("this year")
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            if !netWorth.isComplete {
                Text("Some values are missing: see Needs attention.")
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    /// Where the latest check-in stands against its baseline, as Progress's
    /// *Are you on track?* says it ("On plan", "12.400 € ahead of January"),
    /// and the coast point line; opens Progress. While amounts are hidden,
    /// VoiceOver reads the standing without the amount.
    private func onTrackTile(_ onTrack: OverviewOnTrack, dims: Bool) -> some View {
        Button {
            navigation.showPlan(at: PlanRoute(part: .progress))
        } label: {
            FigureTile(surface: .raised) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
                    Text("On track?")
                        .foregroundStyle(Palette.secondaryInk)
                    Spacer(minLength: Metrics.xs)
                    Image(systemName: "chevron.right")
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.mutedInk)
                        .accessibilityHidden(true)
                }
                if let position = onTrack.position {
                    let standing = position.standing
                    Text(standing.shortLabel)
                        .font(.title.bold())
                        .foregroundStyle(standing.color)
                        .privacySensitiveInFeedback()
                        .accessibilityLabel(standing.label)
                    pair {
                        HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
                            AmountText(abs(position.gap), currency: library.baseCurrency, tabular: false)
                            Text(position.gap >= 0 ? "ahead" : "behind")
                                .privacySensitiveInFeedback()
                        }
                        .foregroundStyle(Palette.ink)
                    } then: {
                        // As Progress's years say it: "ahead of January", "behind January".
                        Text(position.gap >= 0 ? "of \(onTrack.expectation)" : onTrack.expectation)
                            .foregroundStyle(Palette.secondaryInk)
                            .privacySensitiveInFeedback()
                    }
                    .accessibilityHidden(hidesAmounts)
                } else {
                    Text("Not measured yet")
                        .font(.title.bold())
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let coast = onTrack.coastAge {
                    Text(OverviewOnTrack.coastLine(coast))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(dims ? Self.dimmedOpacity : 1)
                        .privacySensitiveInFeedback()
                        .accessibilityLabel(OverviewOnTrack.spokenCoastLine(coast))
                }
            }
            .font(.subheadline)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Shows your progress"))
    }

    /// Two parts of a line: on one row on the Mac and iPad, where every
    /// line fits on one; on iPhone the second under the first, so the
    /// tiles' rows line up.
    @ViewBuilder
    private func pair<First: View, Second: View>(@ViewBuilder _ first: () -> First,
                                                 @ViewBuilder then second: () -> Second) -> some View {
        if isWide {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
                first()
                second()
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                first()
                second()
            }
        }
    }

    // MARK: State

    /// The Mac and iPad.
    private var isWide: Bool { layout.isWide }

    /// Between the tiles: 12 points on iPhone, 16 on the Mac and iPad.
    private var tileSpacing: CGFloat { isWide ? Metrics.l : Metrics.m }

    /// Whether the results shown no longer fit the plan or the library.
    private var isStale: Bool {
        headline.recordedOn == nil && !plans.staleReasons(of: plan.id).isEmpty
    }

    /// Whether the headline, the ring and the coast point line dim: the
    /// results are out of date, or a calculation is replacing them. A
    /// what-if or focus-age run doesn't replace them, so it doesn't count.
    private var dimsAnswer: Bool {
        headline.recordedOn == nil
            && (isStale || plans.isRunning(plan.id, .base) || plans.isRunning(plan.id, .checkIn))
    }
}

/// The header with a made-up answer for the example library's main plan,
/// on the day of its latest check-in.
private struct OverviewHeaderPreview: View {
    var headline: RetirementAnswer
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let today = PreviewLibrary.latestCheckIn
        ScrollView {
            if let plan = library.mainPlan {
                OverviewHeader(headline: headline, plan: plan,
                               netWorth: NetWorthGlance(valuator: library.valuator, asOf: today), today: today)
                    .padding(Metrics.l)
            }
        }
        .background(Palette.page)
    }
}

#Preview("Not yet") {
    OverviewHeaderPreview(headline: RetirementAnswer(confidence: 0.9, earliestAge: 54, earliestDate: "2042-03-12",
                                                 readiness: 0.5849))
        .previewEnvironment()
}

#Preview("Yes, lapping") {
    OverviewHeaderPreview(headline: RetirementAnswer(confidence: 0.9, earliestAge: 38, earliestDate: "2026-09-30",
                                                 successToday: 0.93, readiness: 1.3, canRetireNow: true))
        .previewEnvironment()
}

#Preview("Within two years") {
    OverviewHeaderPreview(headline: RetirementAnswer(confidence: 0.9, earliestAge: 40, earliestDate: "2028-03-31",
                                                 readiness: 0.88))
        .previewEnvironment()
}

#Preview("No age, more than searched") {
    OverviewHeaderPreview(headline: RetirementAnswer(confidence: 0.9, needsMoreThanSearched: true))
        .previewEnvironment()
}

#Preview("Hidden amounts") {
    OverviewHeaderPreview(headline: RetirementAnswer(confidence: 0.9, earliestAge: 54, earliestDate: "2042-03-12",
                                                 readiness: 0.58, readinessIsLowerBound: true))
        .redacted(reason: .privacy)
        .previewEnvironment()
}

#Preview("Large text") {
    OverviewHeaderPreview(headline: RetirementAnswer(confidence: 0.9, earliestAge: 54, earliestDate: "2042-03-12",
                                                 readiness: 0.5849))
        .dynamicTypeSize(.accessibility2)
        .previewEnvironment()
}
