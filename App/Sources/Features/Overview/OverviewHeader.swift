import Glance
import Model
import Planner
import SwiftUI

/// The top of the Overview while the main plan has an answer (UI.md, "Can I
/// retire yet?"): a label row, the answer as a headline with the readiness
/// ring beside it, then the *Net worth* and *On track?* tiles. Three text
/// styles: largeTitle, title and subheadline.
///
/// - **Label row:** "Can I retire yet?", the run status ("◷ 30 Sep" for an
///   answer recorded at a check-in, *Calculate* when the results are out of
///   date, "Calculating 29%"), an ⓘ that explains the whole answer, and the
///   chevron. The label row and the headline open the plan, with a tap
///   gesture rather than as a button, so the ⓘ and *Calculate* get their
///   own taps; the chevron is the button VoiceOver and keyboards use.
/// - **Headline:** the time to go ("In 15 years"), "Yes", "Not yet", or
///   "At 54" without a time to go; the ring (``ReadinessRing``) laps past
///   100%, its label by the *Readiness* widget's rules (``ReadinessFigure``).
///   Out-of-date results dim it, as the Plan screen dims them.
/// - **Tiles:** net worth with its changes, and where the latest check-in
///   stands against its baseline (opening Progress) with the coast point
///   line. Side by side and as tall as each other; stacked at the largest
///   text sizes.
struct OverviewHeader: View {
    /// The main plan's answer (``PlanStore/mainHeadline``).
    let headline: PlanHeadline
    let plan: PlanDocument
    let netWorth: NetWorthGlance
    /// The day the Overview reports on.
    let today: CalendarDate

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.redactionReasons) private var redactionReasons
    @State private var showsExplanation = false

    private var hidesAmounts: Bool { redactionReasons.hidesAmounts }

    /// Out-of-date answers dim as the Plan screen dims its results.
    private static let dimmedOpacity = 0.7

    var body: some View {
        let words = OverviewAnswerText(headline: headline, earliestDate: earliestDate, today: today, locale: locale)
        let dims = dimsAnswer
        VStack(alignment: .leading, spacing: Metrics.m) {
            VStack(alignment: .leading, spacing: Metrics.xs) {
                labelRow(words)
                answerRow(words)
                    .opacity(dims ? Self.dimmedOpacity : 1)
                if headline.recordedOn != nil, headline.readiness == nil {
                    // Recorded before readiness existed: its old FI progress disagreed with the
                    // chance of retiring today, so a neutral line instead of a ring.
                    Text(PlanResultsText.readinessNotRecorded)
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = plans.errors[plan.id], headline.recordedOn != nil || isStale {
                    cantCalculate(error)
                        .padding(.top, Metrics.xs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                navigation.showPlan()
            }
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: "Open the plan") {
                navigation.showPlan()
            }
            tiles(dims: dims)
        }
    }

    // MARK: Label row

    private func labelRow(_ words: OverviewAnswerText) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Text("Can I retire yet?")
                .foregroundStyle(Palette.secondaryInk)
            Spacer(minLength: Metrics.s)
            runStatus
            explanationButton(words)
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
        .font(.subheadline)
    }

    /// In the label row: a calculation going on, when the answer was
    /// recorded, or *Calculate* when the results are out of date. Why the
    /// plan can't be calculated has a line of its own under the headline.
    @ViewBuilder
    private var runStatus: some View {
        if let progress = plans.progress(of: plan.id, .checkIn) ?? plans.progress(of: plan.id, .base) {
            Text(verbatim: "Calculating \(PlanRunText.overall(progress, locale: locale))")
                .monospacedDigit()
                .foregroundStyle(Palette.secondaryInk)
                .accessibilityLabel(Text(verbatim: PlanRunText.accessibility(
                    progress, isCheckIn: plans.isRunning(plan.id, .checkIn), locale: locale)))
        } else if let recorded = headline.recordedOn {
            Label(AmountFormat.shortDate(recorded, locale: locale), systemImage: "clock")
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

    /// The ⓘ: when and how sure, the readiness and what it compares, that
    /// the results are out of date, and the disclaimer.
    private func explanationButton(_ words: OverviewAnswerText) -> some View {
        Button {
            showsExplanation = true
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(Palette.accent)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("About this answer")
        .popover(isPresented: $showsExplanation) {
            Text(words.explanation(isOutOfDate: isStale).joined(separator: "\n\n"))
                .font(.callout)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .privacySensitiveInFeedback()
                .padding(Metrics.l)
                .frame(idealWidth: 320, maxWidth: 360, alignment: .leading)
                .presentationCompactAdaptation(.popover)
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
        .font(.subheadline)
    }

    // MARK: Headline and ring

    /// The headline with the ring at its right, or the ring on a line of
    /// its own under it when both don't fit on one. VoiceOver reads them
    /// as one element.
    private func answerRow(_ words: OverviewAnswerText) -> some View {
        let figure = headline.readinessFigure
        let percent = figure.text { AmountFormat.percent($0, digits: 0, locale: locale) }
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Metrics.m) {
                title(words)
                Spacer(minLength: Metrics.s)
                if let percent {
                    ring(figure, percent: percent)
                }
            }
            VStack(alignment: .leading, spacing: Metrics.s) {
                title(words)
                if let percent {
                    ring(figure, percent: percent)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: words.spoken))
        .accessibilityAddTraits(.isHeader)
    }

    private func title(_ words: OverviewAnswerText) -> some View {
        Text(words.title)
            .font(.largeTitle.bold())
            .foregroundStyle(Palette.ink)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .fixedSize(horizontal: false, vertical: true)
            .privacySensitiveInFeedback()
    }

    /// "58%" over "ready", right-aligned, left of a ring 48 points across
    /// that keeps its size at every text size.
    private func ring(_ figure: ReadinessFigure, percent: String) -> some View {
        HStack(spacing: Metrics.s) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(verbatim: percent)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .privacySensitiveInFeedback()
                Text("ready")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
            }
            .multilineTextAlignment(.trailing)
            ReadinessRing(fraction: figure.lappingFill, lineWidth: 6, laps: true)
                .frame(width: 48, height: 48)
                .privacySensitiveInFeedback()
        }
        .fixedSize()
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
        let spacing = isWide ? Metrics.l : Metrics.m
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
        OverviewTile {
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
        .accessibilityElement(children: .combine)
    }

    /// Where the latest check-in stands against its baseline, as Progress's
    /// *Are you on track?* says it ("On plan", "12.400 € ahead of January"),
    /// and the coast point line; opens Progress. While amounts are hidden,
    /// VoiceOver reads the standing without the amount.
    private func onTrackTile(_ onTrack: OverviewOnTrack, dims: Bool) -> some View {
        Button {
            navigation.showPlanProgress()
        } label: {
            OverviewTile {
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
    private var isWide: Bool { navigation.layout == .sidebar }

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

    /// When the earliest age is reached; for an answer recorded at a
    /// check-in, as the widgets have it (Glance's
    /// `RetirementAnswer.earliestDate`); `nil` without a birth date.
    private var earliestDate: CalendarDate? {
        if let date = headline.earliestDate { return date }
        guard let recorded = headline.recordedOn, let age = headline.earliestAge,
              let birthDate = library.settings.person?.birthDate
        else { return nil }
        return RetirementAnswer.earliestDate(age: age, recordedOn: recorded, birthDate: birthDate)
    }
}

/// One of the header's tiles: a card with 12 points of padding, filling
/// the height its row gives it.
private struct OverviewTile<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            content
        }
        .font(.subheadline)
        .padding(Metrics.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }
}

/// The header with a made-up answer for the example library's main plan,
/// on the day of its latest check-in.
private struct OverviewHeaderPreview: View {
    var headline: PlanHeadline
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
    OverviewHeaderPreview(headline: PlanHeadline(confidence: 0.9, earliestAge: 54, earliestDate: "2042-03-12",
                                                 readiness: 0.5849))
        .previewEnvironment()
}

#Preview("Yes, lapping") {
    OverviewHeaderPreview(headline: PlanHeadline(confidence: 0.9, earliestAge: 38, earliestDate: "2026-09-30",
                                                 successToday: 0.93, readiness: 1.3))
        .previewEnvironment()
}

#Preview("Within two years") {
    OverviewHeaderPreview(headline: PlanHeadline(confidence: 0.9, earliestAge: 40, earliestDate: "2028-03-31",
                                                 readiness: 0.88))
        .previewEnvironment()
}

#Preview("No age, more than searched") {
    OverviewHeaderPreview(headline: PlanHeadline(confidence: 0.9, needsMoreThanSearched: true))
        .previewEnvironment()
}

#Preview("Hidden amounts") {
    OverviewHeaderPreview(headline: PlanHeadline(confidence: 0.9, earliestAge: 54, earliestDate: "2042-03-12",
                                                 readiness: 0.58, readinessIsLowerBound: true))
        .redacted(reason: .privacy)
        .previewEnvironment()
}

#Preview("Large text") {
    OverviewHeaderPreview(headline: PlanHeadline(confidence: 0.9, earliestAge: 54, earliestDate: "2042-03-12",
                                                 readiness: 0.5849))
        .dynamicTypeSize(.accessibility2)
        .previewEnvironment()
}
