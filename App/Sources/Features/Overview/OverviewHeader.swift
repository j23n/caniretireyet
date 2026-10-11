import Glance
import Model
import Planner
import SwiftUI
import Tracker

// The top of the Overview when the main plan has an answer (UI.md,
// "Overview"): a label row, the answer as a headline with the readiness
// ring beside it, and two tiles, *Net worth* and *On track?*. Three text
// styles: largeTitle for the headline, title for the tiles' values, and
// subheadline for the rest.

/// "Can I retire yet?" with the run status, an ⓘ and a chevron; the answer
/// as a headline ("In 15 years", "Yes", "Not yet", "At 54") with the
/// readiness ring at its right; then *Net worth* and *On track?* side by
/// side, or stacked at the largest text sizes. The label row and the
/// headline open the plan; *On track?* opens its Progress.
///
/// The earliest age, its month, the confidence, the readiness sentence and
/// the disclaimer are in the ⓘ, and VoiceOver reads them with the headline.
/// Out-of-date results dim the headline, the ring and the coast point
/// line, as the Plan screen dims them; net worth and the standing are
/// today's and the latest check-in's, so they don't dim.
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

    /// How out-of-date results dim, as on the Plan screen.
    static let dimmedOpacity = 0.7

    var body: some View {
        let words = OverviewAnswerWords(headline: headline, earliestDate: earliestDate, today: today, locale: locale)
        let isStale = headline.recordedOn == nil && !plans.staleReasons(of: plan.id).isEmpty
        VStack(alignment: .leading, spacing: Metrics.m) {
            answer(words, isStale: isStale)
            tiles(isStale: isStale)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: The answer

    /// The label row and the headline, which open the plan on a tap
    /// anywhere but the run status and the ⓘ; the chevron is its button for
    /// VoiceOver and the keyboard.
    private func answer(_ words: OverviewAnswerWords, isStale: Bool) -> some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            labelRow(words, isStale: isStale)
            OverviewHeadlineRow(words: words)
                .opacity(isStale ? Self.dimmedOpacity : 1)
            if !isCalculating, let error = plans.errors[plan.id], headline.recordedOn != nil || isStale {
                OverviewCantCalculate(plan: plan, error: error, font: .subheadline)
            }
            // An answer recorded before readiness existed has no ring.
            if headline.recordedOn != nil, words.ringPercent == nil {
                Text(PlanResultsText.readinessNotRecorded)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
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
    }

    /// "Can I retire yet?", then at the right the run status, the ⓘ and the chevron.
    private func labelRow(_ words: OverviewAnswerWords, isStale: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Text("Can I retire yet?")
                .foregroundStyle(Palette.secondaryInk)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Metrics.s)
            runStatus(isStale: isStale)
            OverviewAnswerInfo(paragraphs: words.info(isStale: isStale))
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

    /// In the label row: a calculation going on ("Calculating 29%"), when
    /// a recorded answer was recorded ("◷ 30 Sep"), or *Calculate* when the
    /// results are out of date (``PlanStore/run(_:mode:whatIf:focusAge:)``,
    /// as *Future* starts it). When the calculation fails, *Try Again*
    /// under the headline takes its place.
    @ViewBuilder
    private func runStatus(isStale: Bool) -> some View {
        if let progress = plans.progress(of: plan.id, .checkIn) ?? plans.progress(of: plan.id, .base) {
            Text("Calculating \(PlanRunText.overall(progress, locale: locale))")
                .monospacedDigit()
                .foregroundStyle(Palette.mutedInk)
                .accessibilityLabel(PlanRunText.accessibility(progress, isCheckIn: plans.isRunning(plan.id, .checkIn),
                                                              locale: locale))
        } else if let recorded = headline.recordedOn {
            Label(AmountFormat.shortDate(recorded, locale: locale), systemImage: "clock")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(Palette.mutedInk)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("As recorded at the check-in on \(AmountFormat.mediumDate(recorded, locale: locale))")
        } else if isStale, plans.errors[plan.id] == nil {
            Button("Calculate") { Task { await plans.run(plan.id) } }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isCalculating)
        }
    }

    private var isCalculating: Bool {
        plans.isRunning(plan.id, .base) || plans.isRunning(plan.id, .checkIn)
    }

    /// When the earliest age is reached: the results' date, or for an
    /// answer recorded at a check-in the birthday that age is reached on,
    /// as the widgets have it (Glance's `RetirementAnswer.earliestDate`);
    /// `nil` without a birth date.
    private var earliestDate: CalendarDate? {
        if let date = headline.earliestDate { return date }
        guard let recorded = headline.recordedOn, let age = headline.earliestAge,
              let birthDate = library.settings.person?.birthDate
        else { return nil }
        return RetirementAnswer.earliestDate(age: age, recordedOn: recorded, birthDate: birthDate)
    }

    // MARK: Tiles

    /// *Net worth* and *On track?*: side by side and as tall as each
    /// other, or at the largest text sizes stacked, each the full width.
    @ViewBuilder
    private func tiles(isStale: Bool) -> some View {
        let isWide = navigation.layout == .sidebar
        let gap = OverviewBaselineGap(plan: plan.id, library: library.library, valuator: library.valuator,
                                      asOf: library.asOfDate, locale: locale)
        let netWorthTile = OverviewNetWorthTile(hero: netWorth, isWide: isWide)
        let trackTile = OverviewTrackTile(gap: gap, coastAge: pastCoastAge, isWide: isWide, dimsCoast: isStale)
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Metrics.m) {
                netWorthTile
                trackTile
            }
        } else {
            EqualColumns(spacing: isWide ? Metrics.l : Metrics.m, fillsHeight: true) {
                netWorthTile
                trackTile
            }
        }
    }

    /// The coast age while you're past the coast point (UI.md,
    /// "Milestones"): from the latest results, else recorded at the latest
    /// check-in, as Progress's Milestones card has it (``PlanMilestones``);
    /// `nil` when you aren't past it, without a pension, and with "Yes".
    private var pastCoastAge: Int? {
        guard !headline.canRetireNow else { return nil }
        let coastAge: Int?
        if headline.recordedOn == nil, let coast = plans.latestResults(of: plan.id)?.details.agesWithout.coast {
            coastAge = coast.earliestAge
        } else {
            coastAge = library.library.headlines(for: plan.id)
                .filter { $0.date <= library.asOfDate }
                .max { $0.date < $1.date }?.coastAge
        }
        return MilestoneLadder.isPastCoastPoint(coastAge, plan: plan) ? coastAge : nil
    }
}

// MARK: - The answer's words

/// The answer in words, for the headline, its ⓘ and VoiceOver.
struct OverviewAnswerWords {
    let headline: PlanHeadline
    /// When the earliest age is reached; `nil` when that isn't known.
    let earliestDate: CalendarDate?
    /// The time to go; `nil` without a date, or once it has passed.
    let countdown: RetirementCountdown?
    let locale: Locale

    init(headline: PlanHeadline, earliestDate: CalendarDate?, today: CalendarDate, locale: Locale = .current) {
        self.headline = headline
        self.earliestDate = earliestDate
        countdown = earliestDate.flatMap { RetirementCountdown(from: today, to: $0) }
        self.locale = locale
    }

    /// The headline: "Yes"; "Not yet" when no age works out; the time to
    /// go, "In 15 years" (``RetirementCountdown/headlineText``); or "At
    /// 54" when there's no time to go.
    var title: String {
        if headline.canRetireNow { return "Yes" }
        guard let age = headline.earliestAge else { return "Not yet" }
        return countdown?.headlineText ?? "At \(age)"
    }

    /// The earliest age, its month and the confidence: "At 54, in March
    /// 2042, in 9 of 10 futures."; "You could retire today, in at least 9
    /// of 10 futures."; "No age works in 9 of 10 futures yet."
    var when: String {
        let futures = GlanceText.futures(headline.confidence)
        if headline.canRetireNow { return "You could retire today, in at least \(futures) futures." }
        guard let age = headline.earliestAge else { return "No age works in \(futures) futures yet." }
        var parts = ["At \(age)"]
        if let earliestDate {
            parts.append("in \(GlanceText.monthAndYear(earliestDate, locale: locale))")
        }
        parts.append("in \(futures) futures")
        return parts.joined(separator: ", ") + "."
    }

    /// "58% of what you'd need to retire today." (``PlanResultsText/readiness(_:locale:)``);
    /// `nil` without a readiness.
    var readiness: String? {
        PlanResultsText.readiness(headline, locale: locale).map { $0 + "." }
    }

    /// The readiness beside the ring, by the *Readiness* widget's rules.
    var figure: ReadinessFigure {
        ReadinessFigure(readiness: headline.readiness, isLowerBound: headline.readinessIsLowerBound,
                        needsMoreThanSearched: headline.needsMoreThanSearched)
    }

    /// "58%", "58%+", "<5%", "130%"; `nil` when there's no ring.
    var ringPercent: String? {
        figure.percent { AmountFormat.percent($0, digits: 0, locale: locale) }
    }

    /// The headline and the ring for VoiceOver: "Not yet. In about 15 years,
    /// at 54, in March 2042, in 9 of 10 futures. 58% of what you'd need to
    /// retire today."
    var spoken: String {
        var text: String
        if headline.canRetireNow {
            text = "Yes. \(when)"
        } else if headline.earliestAge == nil {
            text = "Not yet. \(when)"
        } else if let countdown {
            text = "Not yet. \(countdown.spokenHeadlineText), \(when.prefix(1).lowercased())\(when.dropFirst())"
        } else {
            text = "Not yet. \(when)"
        }
        if let readiness { text += " \(readiness)" }
        return text
    }

    /// The ⓘ's paragraphs, before the disclaimer: the earliest age, its
    /// month and the confidence; the readiness and what it compares; and
    /// "Calculated before your latest changes." when out of date.
    func info(isStale: Bool) -> [String] {
        var paragraphs = [when]
        if let readiness {
            paragraphs.append(readiness + " "
                + PlanResultsText.readinessExplanation(confidence: headline.confidence, locale: locale))
        }
        if isStale { paragraphs.append("Calculated before your latest changes.") }
        return paragraphs
    }
}

// MARK: - Headline

/// The answer in large type with the readiness ring at its right, centered
/// on it; where both don't fit on one line, the ring and its label go on a
/// line of their own under it. VoiceOver reads them as one.
private struct OverviewHeadlineRow: View {
    let words: OverviewAnswerWords

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Metrics.m) {
                title
                    .fixedSize()
                Spacer(minLength: 0)
                ring
            }
            VStack(alignment: .leading, spacing: Metrics.s) {
                title
                    .fixedSize(horizontal: false, vertical: true)
                ring
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(words.spoken)
    }

    private var title: some View {
        Text(words.title)
            .font(.largeTitle.bold())
            .foregroundStyle(Palette.ink)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    /// The percentage over "ready", right-aligned, then the ring, which
    /// keeps its size at every text size and laps itself past 100%.
    @ViewBuilder
    private var ring: some View {
        if let percent = words.ringPercent {
            HStack(spacing: Metrics.s) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(verbatim: percent)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.ink)
                    Text("ready")
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                }
                .fixedSize()
                ReadinessRing(fraction: words.figure.lappingFill, lineWidth: 6, laps: true)
                    .frame(width: 48, height: 48)
            }
        }
    }
}

/// The ⓘ in the label row: the whole answer in words, then the disclaimer.
private struct OverviewAnswerInfo: View {
    let paragraphs: [String]
    @State private var showsInfo = false

    var body: some View {
        Button {
            showsInfo = true
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(Palette.accent)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("About this answer")
        .popover(isPresented: $showsInfo) {
            VStack(alignment: .leading, spacing: Metrics.s) {
                ForEach(paragraphs, id: \.self) { paragraph in
                    Text(paragraph)
                        .font(.callout)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(AboutText.disclaimer)
                    .font(.footnote)
                    .foregroundStyle(Palette.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Metrics.l)
            .frame(idealWidth: 320, maxWidth: 360, alignment: .leading)
            .presentationCompactAdaptation(.popover)
        }
    }
}

// MARK: - Tiles

/// Net worth today, with its changes: "▲ 4.210 € in September" and "▲ 6,2%
/// this year", and a note when the total is partial.
private struct OverviewNetWorthTile: View {
    let hero: NetWorthGlance
    let isWide: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Net worth")
                .foregroundStyle(Palette.secondaryInk)
            AmountText(hero.total, tabular: false, animatesChanges: true)
                .font(.title.bold())
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let change = hero.sinceLastCheckIn {
                OverviewTileLine(isWide: isWide) {
                    DeltaText(change.change)
                } words: {
                    // "in September", "31 Jul – 15 Sep": the check-in's change, not one up to today.
                    Text(GlanceText.period(from: change.from, to: change.to, relativeTo: hero.date))
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            if let year = hero.thisYear {
                OverviewTileLine(isWide: true) {
                    DeltaText(percent: year)
                } words: {
                    Text("this year")
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            if !hero.isComplete {
                Text("Some values are missing: see Needs attention.")
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.subheadline)
        .overviewTile()
        .accessibilityElement(children: .combine)
    }
}

/// "On track?": where the latest check-in stands against its year's
/// baseline, as Progress's *Are you on track?* says it ("On plan",
/// "12.400 € ahead" / "of January"), or "Not measured yet"; then the coast
/// point while you're past it. Opens Progress.
private struct OverviewTrackTile: View {
    let gap: OverviewBaselineGap?
    /// The coast age while past the coast point; `nil` otherwise.
    let coastAge: Int?
    let isWide: Bool
    /// Whether the coast point line dims: it's from out-of-date results.
    let dimsCoast: Bool

    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        Button {
            navigation.showPlanProgress()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                    Text("On track?")
                        .foregroundStyle(Palette.secondaryInk)
                    Spacer(minLength: Metrics.xs)
                    Image(systemName: "chevron.right")
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.mutedInk)
                        .accessibilityHidden(true)
                }
                if let gap {
                    Text(gap.standing.shortLabel)
                        .font(.title.bold())
                        .foregroundStyle(gap.standing.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .accessibilityLabel(gap.standing.label)
                    OverviewTileLine(isWide: isWide) {
                        HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
                            AmountText(abs(gap.gap))
                            Text(gap.gap >= 0 ? "ahead" : "behind")
                        }
                        .foregroundStyle(Palette.ink)
                    } words: {
                        Text("of \(gap.expectation)")
                            .foregroundStyle(Palette.secondaryInk)
                    }
                } else {
                    Text("Not measured yet")
                        .font(.title.bold())
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let coastAge {
                    Text("Past the coast point: \(coastAge) without saving")
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(dimsCoast ? OverviewHeader.dimmedOpacity : 1)
                        .accessibilityLabel(
                            "You're past the coast point: saving nothing more, you could still retire at \(coastAge).")
                }
            }
            .font(.subheadline)
            .multilineTextAlignment(.leading)
            .overviewTile()
            .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Progress")
    }
}

/// A value and its words: on one line where the tiles are wide and it
/// fits ("▲ 4.210 € in September"), else the words under the value.
private struct OverviewTileLine<Value: View, Words: View>: View {
    let isWide: Bool
    let value: Value
    let words: Words

    init(isWide: Bool, @ViewBuilder value: () -> Value, @ViewBuilder words: () -> Words) {
        self.isWide = isWide
        self.value = value()
        self.words = words()
    }

    var body: some View {
        if isWide {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
                    value
                    words
                }
                stacked
            }
        } else {
            stacked
        }
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 2) {
            value
            words
        }
    }
}

private extension View {
    /// A tile: a card with 12 points of padding, filling the height it's
    /// offered so tiles side by side are as tall as each other.
    func overviewTile() -> some View {
        padding(Metrics.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1)
            }
    }
}

// MARK: - Previews

/// Answers for the previews, on the example library's main plan.
private enum OverviewHeaderPreview {
    static let today = PreviewLibrary.latestCheckIn

    static var plan: PlanDocument? {
        PreviewLibrary.library.settings.mainPlan.flatMap { PreviewLibrary.library.plans[$0] }
    }

    static var netWorth: NetWorthGlance {
        NetWorthGlance(valuator: PreviewLibrary.valuator, asOf: today)
    }

    static let notYet = PlanHeadline(confidence: 0.9, earliestAge: 54, earliestDate: "2042-03-12", readiness: 0.5849)
    static let soon = PlanHeadline(confidence: 0.9, earliestAge: 41, earliestDate: "2028-03-12", readiness: 0.91,
                                   readinessIsLowerBound: true)
    static let yes = PlanHeadline(confidence: 0.9, earliestAge: 39, earliestDate: "2026-09-30", successToday: 0.95,
                                  readiness: 1.3)
    static let noAge = PlanHeadline(confidence: 0.9, readiness: nil, needsMoreThanSearched: true)

    /// Recorded at the latest check-in before readiness existed.
    static var recorded: PlanHeadline {
        var headline = PlanHeadline(confidence: 0.9, earliestAge: 54)
        headline.recordedOn = today
        return headline
    }

    static let all: [(String, PlanHeadline)] = [
        ("Not yet", notYet), ("Within two years", soon), ("Yes", yes), ("No age", noAge), ("Recorded", recorded),
    ]
}

#Preview("Header") {
    ScrollView {
        VStack(alignment: .leading, spacing: Metrics.xl) {
            if let plan = OverviewHeaderPreview.plan {
                ForEach(OverviewHeaderPreview.all, id: \.0) { item in
                    OverviewHeader(headline: item.1, plan: plan, netWorth: OverviewHeaderPreview.netWorth,
                                   today: OverviewHeaderPreview.today)
                }
            }
        }
        .padding(Metrics.l)
    }
    .background(Palette.page)
    .previewEnvironment()
}

#Preview("Header, hidden amounts") {
    ScrollView {
        if let plan = OverviewHeaderPreview.plan {
            OverviewHeader(headline: OverviewHeaderPreview.notYet, plan: plan, netWorth: OverviewHeaderPreview.netWorth,
                           today: OverviewHeaderPreview.today)
                .padding(Metrics.l)
        }
    }
    .background(Palette.page)
    .environment(\.hidesAmounts, true)
    .previewEnvironment()
}

#Preview("Header, large text") {
    ScrollView {
        if let plan = OverviewHeaderPreview.plan {
            OverviewHeader(headline: OverviewHeaderPreview.notYet, plan: plan, netWorth: OverviewHeaderPreview.netWorth,
                           today: OverviewHeaderPreview.today)
                .padding(Metrics.l)
        }
    }
    .background(Palette.page)
    .dynamicTypeSize(.accessibility3)
    .previewEnvironment()
}

#Preview("Readiness rings") {
    HStack(spacing: Metrics.l) {
        ForEach([0.0, 0.58, 1.0, 1.3, 2.0], id: \.self) { fraction in
            ReadinessRing(fraction: fraction, lineWidth: 6, laps: true)
                .frame(width: 48, height: 48)
        }
    }
    .padding()
}
