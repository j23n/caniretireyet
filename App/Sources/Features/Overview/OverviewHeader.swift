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

    /// Out-of-date answers dim as the Plan screen dims its results.
    static let dimmedOpacity = 0.7

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

    /// The ring at the leading edge and the answer's words at its right
    /// (``RetirementAnswerRow``), with the run status under them.
    private func answerRow(_ words: OverviewAnswerText, dims: Bool) -> some View {
        RetirementAnswerRow(headline: headline, words: words, yearMove: yearMove, dims: dims) {
            runStatus
        }
    }

    /// How the age you could retire at moved in a year (UI.md, "Can I retire
    /// yet?"): "2 years sooner" over "than a year ago, at 56", against the
    /// answer recorded at the check-in a year ago; `nil` when it didn't
    /// move, or there's no answer from then.
    private var yearMove: OverviewYearMove? {
        guard let age = headline.earliestAge, !headline.canRetireNow,
              let then = library.library.headlines(for: plan.id).last(where: { $0.date <= today.adding(years: -1) }),
              let before = then.earliestAge, before != age
        else { return nil }
        let years = abs(age - before)
        let count = years == 1 ? "A year" : "\(years) years"
        return OverviewYearMove(lead: count + (age < before ? " sooner" : " later"),
                                detail: "than a year ago, at \(before)", isSooner: age < before)
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
                OverviewLinePair {
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

    /// *On track?* (``OverviewOnTrackTile``), which opens the main plan's Progress.
    private func onTrackTile(_ onTrack: OverviewOnTrack, dims: Bool) -> some View {
        OverviewOnTrackTile(onTrack: onTrack, currency: library.baseCurrency, dims: dims) {
            navigation.showPlan(at: PlanRoute(part: .progress))
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
