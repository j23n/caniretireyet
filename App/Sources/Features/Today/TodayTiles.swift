import Glance
import Model
import Planner
import SwiftUI
import Tracker

// Today's tiles on iPhone (UI.md, "Today" and "Tiles"): the next
// milestone and the earliest age side by side, net worth under them. Each
// tile takes a size on the home screen's grid of icons, 2 × 2 or 2 × 4
// (``TileGrid``), so other screens can use them too.

/// Where you stand on iPhone, as tiles: the next milestone, which opens the
/// Timeline at *Year*; the earliest age, which opens the plan; and net
/// worth, which opens the accounts. Before there's an answer the milestone
/// tile is wide and there's no age.
struct TodayTiles: View {
    let answer: RetirementAnswer?
    let plan: PlanDocument?
    let results: PlanResults?
    let today: CalendarDate

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        let netWorth = NetWorthGlance(valuator: library.valuator, asOf: today, historyFrom: today.adding(years: -1))
        let milestoneSize: TileSize = answer == nil ? .wide : .small
        TileGrid {
            if let plan {
                Button {
                    navigation.showTimeline(.year)
                } label: {
                    MilestoneTile(content: milestoneContent(plan), size: milestoneSize, planName: plan.name,
                                  today: today)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows this year on the Timeline")
                .tileSize(milestoneSize)
            }
            if let answer, let plan {
                Button {
                    navigation.showPlan()
                } label: {
                    RetirementAgeTile(answer: answer, move: move(of: answer, plan: plan), updating: updating(plan),
                                      today: today)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the plan")
                .tileSize(.small)
            }
            Button {
                navigation.showAccounts()
            } label: {
                NetWorthTile(netWorth: netWorth, today: today)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows your accounts")
            .tileSize(.wide)
        }
    }

    /// The main plan's milestones as the tile shows them: those passed at
    /// the latest check-in, else the next.
    private func milestoneContent(_ plan: PlanDocument) -> MilestoneTileContent {
        let milestones = TodayMilestones.of(plan, results: results, library: library, plans: plans)
        let valuator = library.valuator
        let latest = library.latestCheckIn
        let previous = latest.flatMap { valuator.previousCheckIn(before: $0, in: .planAssets) }
        return MilestoneTileContent(milestones, hasResults: results != nil, latestCheckIn: latest,
                                    previousCheckIn: previous,
                                    assetsBefore: previous.map { valuator.total(on: $0, in: .planAssets).total })
    }

    /// How the earliest age moved since the check-in before the latest.
    private func move(of answer: RetirementAnswer, plan: PlanDocument) -> LastMondayMove? {
        guard let latest = library.latestCheckIn else { return nil }
        let history = plans.recordedHeadlines(for: plan.id).map {
            AnswerPoint(date: $0.date, earliestAge: $0.earliestAge)
        }
        return LastMondayMove(answer: answer, history: history, latestCheckIn: latest)
    }

    /// How far the main plan's calculation has got, while one runs.
    private func updating(_ plan: PlanDocument) -> Double? {
        (plans.progress(of: plan.id, .checkIn) ?? plans.progress(of: plan.id, .base)).map(\.fraction)
    }
}

// MARK: - Next milestone

/// What the next-milestone tile shows (UI.md, "Tiles").
enum MilestoneTileContent {
    /// Passed at the latest check-in: the newest, the others newest first,
    /// and the next one ahead.
    case passed(ReachedMilestone, also: [ReachedMilestone], next: NextMilestone?)
    /// The next milestone, with when the median future typically reaches
    /// it, the last one passed, the one after it, and how far there it was
    /// at the check-in before when that was further (markets fell back).
    case next(NextMilestone, date: CalendarDate?, last: ReachedMilestone?, after: ProjectedMilestone?,
              before: (progress: Double, date: CalendarDate)?)
    /// None ahead; `calculated` says whether the plan has results.
    case empty(calculated: Bool)

    /// The milestones passed at `latestCheckIn` (since the check-in before
    /// it, `previousCheckIn`), else the next one. `assetsBefore` are the
    /// plan assets at the check-in before.
    init(_ milestones: PlanMilestones, hasResults: Bool, latestCheckIn: CalendarDate?,
         previousCheckIn: CalendarDate?, assetsBefore: Decimal?) {
        if let latestCheckIn {
            let passed = milestones.passed(since: previousCheckIn, through: latestCheckIn)
            if let newest = passed.last {
                self = .passed(newest, also: Array(passed.dropLast().reversed()), next: milestones.next)
                return
            }
        }
        guard let next = milestones.next else {
            self = .empty(calculated: hasResults)
            return
        }
        var before: (progress: Double, date: CalendarDate)?
        if let previousCheckIn, let assetsBefore,
           let progress = PlanMilestones.progress(toward: next.milestone, assets: assetsBefore),
           progress > next.progress + 0.005 {
            before = (progress, previousCheckIn)
        }
        self = .next(next, date: milestones.nextDate, last: milestones.reached.last, after: milestones.afterNext,
                     before: before)
    }
}

extension Milestone {
    /// Its tile's tint: butter for round amounts, mint for years of
    /// spending, lilac for shares of what retiring today needs, peach for
    /// the crossover, sky for the coast point.
    var tileTint: TileTint {
        switch kind {
        case .roundAmount: .butter
        case .yearsOfSpending: .mint
        case .shareOfNeeded: .lilac
        case .crossover: .peach
        case .coastPoint: .sky
        }
    }

    /// Its emoji, beside its name on a tile: 💰 🛋️ 🧩 ⚖️ ⛵, and 🏖️ for all of
    /// what retiring today needs.
    var tileEmoji: String {
        switch kind {
        case .roundAmount: "💰"
        case .yearsOfSpending: "🛋️"
        case .shareOfNeeded(let numerator, let denominator): numerator == denominator ? "🏖️" : "🧩"
        case .crossover: "⚖️"
        case .coastPoint: "⛵"
        }
    }
}

/// The next milestone as a tile (UI.md, "Tiles"), small (2 × 2) or wide
/// (2 × 4): tinted by its kind, with its emoji, its name, how far there as
/// a bar and when it typically comes; the wide one adds the last one passed
/// and the one after. Passed at the latest check-in, it turns pink until
/// the next check-in.
struct MilestoneTile: View {
    let content: MilestoneTileContent
    var size: TileSize = .small
    /// The main plan's name, before it has results.
    let planName: String
    let today: CalendarDate

    @Environment(\.baseCurrency) private var currency
    @Environment(\.locale) private var locale

    /// A milestone this close is "Almost there".
    static let almostThere = 0.95

    var body: some View {
        let text = PlanMilestoneText(currency: currency, locale: locale)
        switch content {
        case .passed(let newest, let also, let next):
            passed(newest, also: also, next: next, text: text)
        case .next(let next, let date, let last, let after, let before):
            ahead(next, date: date, last: last, after: after, before: before, text: text)
        case .empty(let calculated):
            ColorTile {
                TileLabel("Milestones", emoji: calculated ? "🌅" : "🧮")
                Spacer(minLength: Metrics.s)
                Text(verbatim: calculated ? "No more before the plan's end."
                                          : "Your next milestone shows once \(planName) is calculated.")
                    .font(.subheadline)
                    .opacity(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .privacySensitiveInFeedback(!calculated)
            }
        }
    }

    // MARK: Ahead

    private func ahead(_ next: NextMilestone, date: CalendarDate?, last: ReachedMilestone?,
                       after: ProjectedMilestone?, before: (progress: Double, date: CalendarDate)?,
                       text: PlanMilestoneText) -> some View {
        let milestone = next.milestone
        let isWide = size == .wide
        let percent = AmountFormat.percent(next.progress, digits: 0, locale: locale)
        return ColorTile(tint: milestone.tileTint) {
            HStack(spacing: Metrics.s) {
                TileLabel(next.progress >= Self.almostThere ? "Almost there" : "Next milestone",
                          emoji: milestone.tileEmoji)
                if isWide, let date {
                    Spacer(minLength: Metrics.s)
                    Text(verbatim: "typically \(PlanMilestoneText.when(date))")
                        .font(.caption)
                        .opacity(0.8)
                        .lineLimit(1)
                        .privacySensitiveInFeedback()
                }
            }
            Spacer(minLength: Metrics.s)
            HStack(alignment: .lastTextBaseline, spacing: Metrics.m) {
                AmountSentenceText(text.name(milestone))
                    .font(nameFont(milestone))
                    .lineLimit(isWide ? 2 : 3)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                if isWide {
                    Spacer(minLength: 0)
                    Text(verbatim: percent)
                        .font(.title2.bold())
                        .monospacedDigit()
                        .privacySensitiveInFeedback()
                }
            }
            TileBar(progress: next.progress, before: before?.progress)
                .padding(.top, 10)
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                if isWide {
                    wideFooter(last: last, after: after, before: before, text: text)
                } else {
                    Text(verbatim: "\(percent) there")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .privacySensitiveInFeedback()
                    Spacer(minLength: Metrics.xs)
                    if let date {
                        Text(verbatim: PlanMilestoneText.when(date))
                            .font(.caption)
                            .opacity(0.8)
                            .privacySensitiveInFeedback()
                    }
                }
            }
            .lineLimit(1)
            .padding(.top, 7)
        }
    }

    /// Under a wide tile's bar: how far there it was at the check-in before
    /// when markets fell back, else the last one passed; and the one after.
    @ViewBuilder
    private func wideFooter(last: ReachedMilestone?, after: ProjectedMilestone?,
                            before: (progress: Double, date: CalendarDate)?, text: PlanMilestoneText) -> some View {
        Group {
            if let before {
                Text(verbatim: "\(AmountFormat.percent(before.progress, digits: 0, locale: locale)) in "
                     + GlanceText.month(before.date, relativeTo: today, locale: locale))
                    .privacySensitiveInFeedback()
            } else if let last {
                AmountSentenceText("Last: \(last.milestone.tileEmoji) " + text.name(last.milestone)
                                   + AmountSentence(", \(GlanceText.shortMonthAndYear(last.date, locale: locale))"))
            }
            Spacer(minLength: Metrics.s)
            if let after {
                AmountSentenceText("Then: \(after.milestone.tileEmoji) " + text.name(after.milestone))
            }
        }
        .font(.caption)
        .opacity(0.8)
    }

    /// A round amount's name is a number and takes the largest type; the
    /// other names are words and take less.
    private func nameFont(_ milestone: Milestone) -> Font {
        if case .roundAmount = milestone.kind {
            return size == .wide ? .title.bold() : .title2.bold()
        }
        return size == .wide ? .title3.bold() : .headline
    }

    // MARK: Passed

    private func passed(_ newest: ReachedMilestone, also: [ReachedMilestone], next: NextMilestone?,
                        text: PlanMilestoneText) -> some View {
        let isWide = size == .wide
        let month = GlanceText.month(newest.date, relativeTo: today, locale: locale)
        let count = also.count + 1
        return ColorTile(tint: .pink) {
            TileLabel(count == 1 ? "Passed in \(month)" : "\(count) passed in \(month)",
                      emoji: newest.milestone.tileEmoji == "🏖️" ? "🏖️" : "🎉")
                .privacySensitiveInFeedback()
            Spacer(minLength: Metrics.s)
            if also.isEmpty {
                passedOne(newest.milestone, text: text)
            } else {
                VStack(alignment: .leading, spacing: Metrics.xs) {
                    ForEach([newest] + also.prefix(isWide ? 2 : 1), id: \.id) { reached in
                        AmountSentenceText("\(reached.milestone.tileEmoji) " + text.name(reached.milestone))
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    if also.count > (isWide ? 2 : 1) {
                        Text("and \(also.count - (isWide ? 2 : 1)) more")
                            .font(.caption)
                            .opacity(0.8)
                            .privacySensitiveInFeedback()
                    }
                }
            }
            if let next {
                let progress = isWide ? AmountSentence(", \(text.progress(next))") : AmountSentence()
                AmountSentenceText("Next: \(next.milestone.tileEmoji) " + text.name(next.milestone) + progress)
                    .font(.caption)
                    .opacity(0.8)
                    .lineLimit(1)
                    .padding(.top, 6)
            }
        }
    }

    /// One milestone passed: the coast point as its age, the others by name,
    /// with what it means on a wide tile and for all of what retiring today
    /// needs.
    @ViewBuilder
    private func passedOne(_ milestone: Milestone, text: PlanMilestoneText) -> some View {
        if case .coastPoint(let age) = milestone.kind {
            Text(verbatim: "\(age)")
                .font(.system(size: 44, weight: .bold))
                .monospacedDigit()
                .privacySensitiveInFeedback()
            Text("Saving nothing more, you could still retire at \(age).")
                .font(.caption)
                .opacity(0.85)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .privacySensitiveInFeedback()
        } else {
            AmountSentenceText(text.name(milestone))
                .font(nameFont(milestone))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            if milestone.tileEmoji == "🏖️" {
                Text("You could stop now.")
                    .font(.caption)
                    .opacity(0.85)
                    .privacySensitiveInFeedback()
            } else if size == .wide, let detail = text.detail(milestone) {
                AmountSentenceText(detail)
                    .font(.caption)
                    .opacity(0.85)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Retirement age

/// The earliest age as a small tile (UI.md, "Tiles"): the age, its last
/// Monday, and how it moved since the check-in before, the tile mint when
/// sooner, peach when later and white when the same; without a move, sky,
/// with a dot for each of 10 futures it works in. "Yes" in pink when you
/// could stop today, "Not yet" in lilac when no age works out.
struct RetirementAgeTile: View {
    let answer: RetirementAnswer
    var move: LastMondayMove?
    /// How far a calculation has got, 0 to 1, while one runs.
    var updating: Double?
    let today: CalendarDate

    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .largeTitle) private var ageSize: CGFloat = 54

    var body: some View {
        let futures = GlanceText.futures(answer.confidence)
        if let lastMonday = LastMonday(answer) {
            ColorTile(tint: tint) {
                TileLabel("Earliest age")
                Spacer(minLength: Metrics.xs)
                Group {
                    Text(verbatim: "\(lastMonday.age)")
                        .font(.system(size: ageSize, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .opacity(updating == nil ? 1 : 0.4)
                    Text(verbatim: GlanceText.shortLastMonday(lastMonday.date, locale: locale))
                        .font(.caption)
                        .opacity(0.8)
                        .lineLimit(1)
                }
                .privacySensitiveInFeedback()
                Group {
                    if let updating {
                        Text(verbatim: "Updating \(AmountFormat.percent(min(1, max(0, updating)), digits: 0, locale: locale))")
                            .font(.caption)
                            .opacity(0.8)
                            .monospacedDigit()
                        TileBar(progress: updating)
                            .padding(.top, Metrics.xs)
                    } else if let move {
                        moveChip(move)
                    } else {
                        FuturesDots(share: lastMonday.confidence)
                    }
                }
                .padding(.top, Metrics.s)
            }
        } else if answer.canRetireNow {
            ColorTile(tint: .pink) {
                TileLabel("Can I retire yet?")
                Spacer(minLength: Metrics.s)
                Text("Yes")
                    .font(.system(size: ageSize, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .privacySensitiveInFeedback()
                Text("You could stop working today, in \(futures) futures.")
                    .font(.caption)
                    .opacity(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .privacySensitiveInFeedback()
            }
        } else {
            ColorTile(tint: .lilac) {
                TileLabel("Can I retire yet?")
                Spacer(minLength: Metrics.s)
                Text("Not yet")
                    .font(.system(size: ageSize * 0.75, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .privacySensitiveInFeedback()
                Text("No age works out in \(futures) futures yet.")
                    .font(.caption)
                    .opacity(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .privacySensitiveInFeedback()
            }
        }
    }

    /// Mint when it moved sooner, peach when later, the card when it stayed;
    /// sky without a check-in to compare with.
    private var tint: TileTint {
        guard let move else { return .sky }
        return move.years == 0 ? .card : move.isSooner ? .mint : .peach
    }

    /// "← A year sooner", "→ 2 years later", "= The same", in a capsule.
    private func moveChip(_ move: LastMondayMove) -> some View {
        Label {
            Text(verbatim: TodayText.move(move))
                .lineLimit(1)
        } icon: {
            Image(systemName: move.years == 0 ? "equal" : move.isSooner ? "arrow.left" : "arrow.right")
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 9)
        .padding(.vertical, Metrics.xs)
        .background(.primary.opacity(0.08), in: Capsule())
        .privacySensitiveInFeedback()
        .accessibilityLabel(Text(verbatim: GlanceText.move(move, relativeTo: today, locale: locale)))
    }
}

/// A dot for each of 10 futures, filled for those the age works in.
struct FuturesDots: View {
    let share: Double

    var body: some View {
        let filled = Int((min(1, max(0, share)) * 10).rounded())
        HStack(spacing: 3) {
            ForEach(0..<10, id: \.self) { index in
                Circle()
                    .fill(index < filled ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary.opacity(0.12)))
                    .frame(width: 10, height: 10)
            }
        }
        .privacySensitiveInFeedback()
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: GlanceText.inFutures(share)))
    }
}

// MARK: - Net worth

/// Net worth as a wide tile on the card (UI.md, "Tiles"): today's total,
/// how it changed over the last 12 months and at the last check-in, and
/// the 12 month ends as a line in sky blue with a wash under it. While
/// amounts are hidden, the changes show in per cent and the line keeps its
/// shape.
struct NetWorthTile: View {
    let netWorth: NetWorthGlance
    let today: CalendarDate

    @Environment(\.redactionReasons) private var redactionReasons
    @Environment(\.locale) private var locale

    var body: some View {
        let values = Self.values(netWorth)
        ColorTile {
            HStack(spacing: Metrics.s) {
                TileLabel("Net worth")
                Spacer(minLength: Metrics.s)
                if values.count > 1, let first = netWorth.history.first, first.date <= today.adding(months: -11) {
                    Text("12 months")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            Spacer(minLength: Metrics.s)
            HStack(alignment: .bottom, spacing: Metrics.m) {
                VStack(alignment: .leading, spacing: 3) {
                    AmountText(netWorth.total, tabular: false, animatesChanges: true)
                        .font(.system(size: 30, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    yearChange
                    lastCheckIn
                }
                .layoutPriority(1)
                if values.count > 1 {
                    sparkline(values)
                        .frame(maxWidth: 150)
                        .frame(height: 56)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The month ends of the last 12 months, and today.
    static func values(_ netWorth: NetWorthGlance) -> [Double] {
        var values = netWorth.history.map { $0.value.doubleValue }
        if netWorth.history.last?.date != netWorth.date {
            values.append(netWorth.total.doubleValue)
        }
        return values
    }

    /// "▲ +36.210 € in a year", or "since March" for a shorter history; in
    /// per cent while amounts are hidden.
    @ViewBuilder
    private var yearChange: some View {
        if let first = netWorth.history.first, first.date < netWorth.date {
            let change = netWorth.total - first.value
            HStack(spacing: Metrics.xs) {
                if redactionReasons.hidesAmounts, first.value != 0 {
                    DeltaText(percent: (change / abs(first.value)).doubleValue)
                } else {
                    DeltaText(change)
                }
                Text(verbatim: first.date <= today.adding(months: -11)
                    ? "in a year" : "since \(GlanceText.shortMonth(first.date, relativeTo: today, locale: locale))")
                    .foregroundStyle(Palette.secondaryInk)
                    .privacySensitiveInFeedback()
            }
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
        }
    }

    /// "+5.418 € in September": the change at the last check-in, without
    /// color; in per cent while amounts are hidden.
    @ViewBuilder
    private var lastCheckIn: some View {
        if let change = netWorth.sinceLastCheckIn {
            HStack(spacing: Metrics.xs) {
                if redactionReasons.hidesAmounts, let fraction = change.fraction {
                    Text(verbatim: AmountFormat.percent(fraction, signed: true, locale: locale))
                        .privacySensitiveInFeedback()
                } else {
                    AmountText(change.change, signed: true)
                }
                Text(verbatim: GlanceText.period(from: change.from, to: change.to, relativeTo: today, locale: locale))
                    .privacySensitiveInFeedback()
            }
            .font(.caption)
            .foregroundStyle(Palette.secondaryInk)
            .lineLimit(1)
        }
    }

    /// The line, a wash under it and a dot on today's value.
    private func sparkline(_ values: [Double]) -> some View {
        let color = TileTint.sky.accent
        return ZStack {
            SparklineShape(values: values, closesArea: true)
                .fill(color.opacity(0.14))
            SparklineShape(values: values, closesArea: false)
                .stroke(color, style: StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, lineJoin: .round))
            SparklineDot(values: values, radius: 3.5)
                .fill(color)
        }
        .privacySensitiveInFeedback()
        .accessibilityHidden(true)
    }
}
