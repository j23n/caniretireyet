import Glance
import Model
import Planner
import SwiftUI
import Tracker

// Today's tiles (UI.md, "Today" and "Tiles"): net worth, the next
// milestone, the savings rate, this year, the next check-in and saving
// nothing more, and what moved it; then *Coming up*. Each tile takes a
// size on the home screen's grid of icons (``TileGrid``), so other screens
// can use them too.

/// Where you stand, as tiles: net worth (opening the accounts), the next
/// milestone (opening So far), the savings rate over the last 12 months
/// (opening So far too), this year so far, the next
/// check-in and saving nothing more as half tiles, and what moved at the
/// last check-in (opening the accounts). The tiles go into the page's
/// ``TileGrid``s, in parts:
///
/// - ``Part/all``: every tile, under the answer, where a row has two
///   slots, or before there's an answer. Net worth and what moved are wide; the milestone and
///   the savings rate are wide when only one has something to show.
/// - ``Part/beside(slots:)``: net worth and what moved, tall, beside the
///   answer in `slots` (two or four); with four each takes two, with two
///   one each, and net worth alone takes both.
/// - ``Part/under``: the rest, small and half tiles, under the answer and
///   those two.
/// - ``Part/saved``: a saved check-in's on iPhone: what moved, wide, then
///   the next milestone and the savings rate.
struct TodayTiles: View {
    enum Part {
        case all
        case beside(slots: Int)
        case under
        case saved
    }

    let part: Part
    let plan: PlanDocument?
    let results: PlanResults?
    let today: CalendarDate
    /// Whether the next check-in's tile shows: not on the saved check-in.
    var showsCheckIn = true

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(CheckInStore.self) private var checkIn
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.locale) private var locale

    var body: some View {
        let moved = library.valuator.changeSinceLastCheckIn(asOf: today)
        switch part {
        case .all:
            let twelveMonths = self.twelveMonths
            netWorth(isTall: false)
                .tileSize(.wide)
            figures(twelveMonths, pairSize: plan != nil && twelveMonths != nil ? .small : .wide)
            year
            halves
            if let moved {
                movedTile(moved, isTall: false)
                    .tileSize(.wide)
            }
        case .beside(let slots):
            netWorth(isTall: true)
                .tileSize(moved == nil || slots >= 4 ? .wide : .small)
            if let moved {
                movedTile(moved, isTall: true)
                    .tileSize(slots >= 4 ? .wide : .small)
            }
        case .under:
            figures(twelveMonths, pairSize: .small)
            year
            halves
        case .saved:
            if let moved {
                movedTile(moved, isTall: false)
                    .tileSize(.wide)
            }
            let twelveMonths = self.twelveMonths
            figures(twelveMonths, pairSize: plan != nil && twelveMonths != nil ? .small : .wide)
        }
    }

    private func netWorth(isTall: Bool) -> some View {
        Button {
            navigation.showAccounts()
        } label: {
            NetWorthTile(netWorth: NetWorthGlance(valuator: library.valuator, asOf: today,
                                                  historyFrom: today.adding(years: -1)),
                         today: today, isTall: isTall)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows your accounts")
    }

    /// The next milestone and the savings rate.
    @ViewBuilder
    private func figures(_ twelveMonths: PlanLastTwelveMonths?, pairSize: TileSize) -> some View {
        if let plan {
            Button {
                navigation.showSoFar()
            } label: {
                MilestoneTile(content: MilestoneTileContent(milestones(of: plan), hasResults: results != nil,
                                                            library: library),
                              size: pairSize, planName: plan.name, today: today)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows this year on So far")
            .tileSize(pairSize)
        }
        if let twelveMonths, let rate = twelveMonths.tiles.first {
            Button {
                navigation.showSoFar()
            } label: {
                TwelveMonthsTile(tile: rate, currency: twelveMonths.current.moneyInOut.currency,
                                 period: twelveMonths.since == nil ? "last 12 months" : nil)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows your savings rate on So far")
            .tileSize(pairSize)
        }
    }

    /// This year so far.
    @ViewBuilder
    private var year: some View {
        let valuator = library.valuator
        if let report = valuator.changeThisYear(asOf: today) {
            Button {
                navigation.showSoFar(year: report.to.year)
            } label: {
                TodayYearTile(report: report, split: valuator.savedSplit(of: report))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows this year on So far")
            .tileSize(.small)
        }
    }

    /// The next check-in and saving nothing more.
    @ViewBuilder
    private var halves: some View {
        let status = checkIn.status
        if showsCheckIn, status.lastCheckIn != nil {
            Button {
                navigation.startCheckIn()
            } label: {
                CheckInTile(status: status)
            }
            .buttonStyle(.plain)
            .accessibilityHint(status.isOpen ? "Continues the check-in" : "Starts the check-in")
            .tileSize(.half)
        }
        let planMilestones = plan.map { milestones(of: $0) }
        if let planMilestones, planMilestones.knowsCoastAge {
            Button {
                navigation.showSoFar()
            } label: {
                CoastAgeTile(age: planMilestones.coastAge, target: planMilestones.ladder.coastTarget, size: .half)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows this year on So far")
            .tileSize(.half)
        }
    }

    private func movedTile(_ change: ChangeReport, isTall: Bool) -> some View {
        Button {
            navigation.showAccounts()
        } label: {
            TodayMovedTile(report: change, split: library.valuator.savedSplit(of: change),
                           yearlySpending: plan.flatMap(MilestoneLadder.spending(of:)), isTall: isTall)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows your accounts")
    }

    /// The last 12 months' money in and out, as So far has them (through
    /// the latest check-in of the plan's accounts), when Trends is on and
    /// they recorded some that came in.
    private var twelveMonths: PlanLastTwelveMonths? {
        let valuator = library.valuator
        let end = valuator.latestCheckIn(onOrBefore: library.asOfDate, in: .planAssets) ?? library.asOfDate
        guard library.library.accountsTurningOffTrends.isEmpty,
              let year = PlanLastTwelveMonths(valuator: valuator, through: end,
                                              recordedSince: library.moneyInOutRecordedSince),
              year.current.rate != nil
        else { return nil }
        return year
    }

    private func milestones(of plan: PlanDocument) -> PlanMilestones {
        TodayMilestones.of(plan, results: results, library: library, plans: plans)
    }
}

/// *Coming up* (UI.md, "Today"): the main plan's milestones its median
/// future reaches after the next, soonest first, a small tile each, as many
/// as a row of `slots` holds and at least two. Each opens So far,
/// where *All Milestones* is. Nothing without any.
struct TodayComingUp: View {
    let plan: PlanDocument?
    let results: PlanResults?
    let slots: Int

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        let ahead = self.ahead
        if !ahead.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.s) {
                SectionHeader("Coming up")
                    .padding(.horizontal, Metrics.xs)
                TileGrid {
                    ForEach(ahead, id: \.id) { milestone in
                        Button {
                            navigation.showSoFar()
                        } label: {
                            AheadMilestoneTile(milestone: milestone)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows this year on So far")
                        .tileSize(.small)
                    }
                }
            }
        }
    }

    /// The milestones ahead after the next one.
    private var ahead: [ProjectedMilestone] {
        guard let plan else { return [] }
        let milestones = TodayMilestones.of(plan, results: results, library: library, plans: plans)
        let next = milestones.next?.milestone.id
        return Array(milestones.ahead.filter { $0.id != next }.prefix(max(2, slots)))
    }
}

/// A milestone ahead as a small tile on *Coming up*: tinted by its kind,
/// with its emoji and what kind of milestone it is, its name, and when the
/// median future typically reaches it.
struct AheadMilestoneTile: View {
    let milestone: ProjectedMilestone

    @Environment(\.baseCurrency) private var currency
    @Environment(\.locale) private var locale

    var body: some View {
        let text = PlanMilestoneText(currency: currency, locale: locale)
        ColorTile(tint: milestone.milestone.tileTint) {
            TileLabel(PlanMilestoneText.kindName(milestone.milestone.kind), emoji: milestone.milestone.tileEmoji)
            Spacer(minLength: Metrics.s)
            AmountSentenceText(text.name(milestone.milestone))
                .font(.headline)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            TileCaption(verbatim: "typically \(PlanMilestoneText.when(milestone.date))")
                .privacySensitiveInFeedback()
                .padding(.top, 2)
        }
        .accessibilityElement(children: .combine)
    }
}

/// This year so far as a small tile (UI.md, "Today"): "📅 Net worth
/// change in 2026", how net worth changed since the end of last year, then
/// what you saved and what markets did. In per cent while amounts are
/// hidden.
struct TodayYearTile: View {
    let report: ChangeReport
    /// Its split with saved as the savings rate counts it.
    let split: ValueChange

    @Environment(\.redactionReasons) private var redactionReasons
    @Environment(\.locale) private var locale

    var body: some View {
        let total = report.total
        ColorTile(tint: .mint) {
            TileLabel("Net worth change in \(String(report.to.year))", emoji: "📅")
            Spacer(minLength: Metrics.s)
            Group {
                if redactionReasons.hidesAmounts, let relative = total.relativeChange {
                    Text(verbatim: AmountFormat.percent(relative, signed: true, locale: locale))
                        .privacySensitiveInFeedback()
                } else {
                    AmountText(total.change, signed: true, tabular: false)
                }
            }
            .font(.title2.bold())
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Metrics.xs) {
                    Text("Saved")
                    AmountText(split.saved)
                }
                HStack(spacing: Metrics.xs) {
                    Text("Markets")
                    AmountText(split.market, signed: true)
                }
            }
            .font(.caption)
            .opacity(0.8)
            .lineLimit(1)
            .padding(.top, Metrics.xs)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The next check-in as a half tile (UI.md, "Today"): its date and how
/// soon, or that one is under way.
struct CheckInTile: View {
    let status: CheckInStatus

    @Environment(\.locale) private var locale

    var body: some View {
        let words = status.tileWords(locale: locale)
        HalfTile(tint: .sky, title: status.isOpen ? "Check-in" : "Next check-in", emoji: "🗓️") {
            Text(verbatim: words.figure)
                .privacySensitiveInFeedback()
        } caption: {
            Text(verbatim: words.caption)
        }
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
            TileLabel(next.progress >= Self.almostThere ? "Almost there" : "Next milestone",
                      emoji: milestone.tileEmoji)
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
            if isWide, let date {
                TileCaption(verbatim: "typically \(PlanMilestoneText.when(date))")
                    .privacySensitiveInFeedback()
                    .padding(.top, 2)
            }
            TileBar(progress: next.progress, before: before?.progress)
                .padding(.top, 10)
            Group {
                if isWide {
                    HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                        wideFooter(last: last, after: after, before: before, text: text)
                    }
                } else {
                    let there = Text(verbatim: "\(percent) there")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .privacySensitiveInFeedback()
                    if let date {
                        LineOrStack(there, Text(verbatim: PlanMilestoneText.when(date))
                            .font(.caption)
                            .opacity(0.8)
                            .privacySensitiveInFeedback(), spread: true)
                    } else {
                        there
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
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
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

// MARK: - Net worth

/// Net worth as a wide tile on the card (UI.md, "Tiles"): today's total,
/// how it changed over the last 12 months and at the last check-in, and
/// the 12 month ends as a line in sky blue with a wash under it, beside
/// them, or under them filling a tall tile (`isTall`). While amounts are
/// hidden, the changes show in per cent and the line keeps its shape.
struct NetWorthTile: View {
    let netWorth: NetWorthGlance
    let today: CalendarDate
    /// Whether it's a tall tile beside the answer, the line under the figures.
    var isTall = false

    @Environment(\.redactionReasons) private var redactionReasons
    @Environment(\.locale) private var locale

    var body: some View {
        let values = Self.values(netWorth)
        ColorTile {
            TileLabel("Net worth", emoji: "📊")
            Spacer(minLength: Metrics.s)
            if isTall {
                figures
                if values.count > 1 {
                    sparkline(values)
                        .frame(minHeight: 56, maxHeight: .infinity)
                        .padding(.top, Metrics.m)
                }
            } else {
                HStack(alignment: .bottom, spacing: Metrics.m) {
                    figures
                        .layoutPriority(1)
                    if values.count > 1 {
                        sparkline(values)
                            .frame(maxWidth: 150)
                            .frame(height: 56)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The total, and how it changed in a year and at the last check-in.
    private var figures: some View {
        VStack(alignment: .leading, spacing: 3) {
            AmountText(netWorth.total, tabular: false, animatesChanges: true)
                .font(.system(size: 30, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            yearChange
            lastCheckIn
        }
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
            let delta = Group {
                if redactionReasons.hidesAmounts, first.value != 0 {
                    DeltaText(percent: (change / abs(first.value)).doubleValue)
                } else {
                    DeltaText(change)
                }
            }
            let period = Text(verbatim: first.date <= today.adding(months: -11)
                ? "in a year" : "since \(GlanceText.shortMonth(first.date, relativeTo: today, locale: locale))")
                .foregroundStyle(Palette.secondaryInk)
                .privacySensitiveInFeedback()
            LineOrStack(delta, period)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
    }

    /// "+5.418 € in September": the change at the last check-in, without
    /// color; in per cent while amounts are hidden.
    @ViewBuilder
    private var lastCheckIn: some View {
        if let change = netWorth.sinceLastCheckIn {
            let amount = Group {
                if redactionReasons.hidesAmounts, let fraction = change.fraction {
                    Text(verbatim: AmountFormat.percent(fraction, signed: true, locale: locale))
                        .privacySensitiveInFeedback()
                } else {
                    AmountText(change.change, signed: true)
                }
            }
            let period = Text(verbatim: GlanceText.period(from: change.from, to: change.to, relativeTo: today,
                                                          locale: locale))
                .privacySensitiveInFeedback()
            LineOrStack(amount, period)
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
