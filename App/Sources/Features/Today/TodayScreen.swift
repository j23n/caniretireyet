import Glance
import Model
import Planner
import SwiftUI
import Tracker

/// The home screen (UI.md, "Today"): your last Monday at work, what moved
/// it at the last check-in, and where you stand.
///
/// On iPhone, top to bottom: the answer as a date (``TodayAnswerCard``),
/// or before there's one the next step (``TodayPlanCard``); *What moved
/// it* at the last check-in (``TodayMovedCard``); tiles for the next
/// milestone, the earliest age and net worth (``TodayTiles``); and what
/// needs attention, only while something does.
///
/// On the Mac and iPad the answer card holds four figures beside the date;
/// under it two columns (``TodayColumns``): *Your timeline*, the decades
/// chart, and what moved at the last check-in as a table on the left;
/// *Needs attention*, *This year so far* and *Coming up* on the right.
///
/// When the main plan's results are out of date, Today calculates it in
/// the background: there's no *Calculate* here.
struct TodayScreen: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.pageLayout) private var layout

    init() {}

    var body: some View {
        Group {
            if library.hasNoAccounts {
                TodayEmptyState()
            } else {
                content
            }
        }
        .navigationTitle("Today")
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Check In") { navigation.startCheckIn() }
                    .buttonStyle(.borderedProminent)
                    .help("Start this month's check-in")
            }
        }
        #endif
        .task(id: library.revision) { await calculateIfNeeded() }
    }

    private var content: some View {
        let today = CalendarDate.today()
        return ScrollView {
            Group {
                if layout.isWide {
                    wide(today: today)
                } else {
                    narrow(today: today)
                }
            }
            .padding(layout.gutter)
            .frame(maxWidth: layout.isWide ? Metrics.wideReadableWidth : Metrics.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.page)
    }

    /// iPhone: the date, what moved it, the tiles, what needs attention.
    private func narrow(today: CalendarDate) -> some View {
        let valuator = library.valuator
        let mainPlan = library.mainPlan
        let latest = mainPlan == nil ? nil : plans.mainAnswer
        let answer = latest?.answer
        let change = valuator.changeSinceLastCheckIn(asOf: today)
        return VStack(alignment: .leading, spacing: Metrics.m) {
            answerCard(answer, plan: mainPlan, results: latest?.results, year: nil, today: today)
            if let change {
                TodayMovedCard(report: change, split: valuator.savedSplit(of: change),
                               yearlySpending: mainPlan.flatMap(MilestoneLadder.spending(of:)))
            }
            TodayTiles(answer: answer, plan: mainPlan, results: latest?.results, today: today)
            TodayAttentionCard(today: today)
            notesAndFirstValues(hasAnswer: answer != nil)
        }
    }

    /// The Mac and iPad: the date with its figures, then the timeline and
    /// what moved beside what needs attention, this year and what's ahead.
    private func wide(today: CalendarDate) -> some View {
        let valuator = library.valuator
        let mainPlan = library.mainPlan
        let latest = mainPlan == nil ? nil : plans.mainAnswer
        let answer = latest?.answer
        let change = valuator.changeSinceLastCheckIn(asOf: today)
        let year = valuator.changeThisYear(asOf: today).map { report in
            TodayYear(report: report, split: valuator.savedSplit(of: report),
                      savings: library.library.accountsTurningOffTrends.isEmpty
                          ? valuator.savingsRate(from: report.from.adding(days: 1), through: today)
                          : nil)
        }
        return VStack(alignment: .leading, spacing: Metrics.l) {
            answerCard(answer, plan: mainPlan, results: latest?.results, year: year, today: today)
            TodayColumns {
                VStack(alignment: .leading, spacing: Metrics.l) {
                    if let mainPlan {
                        Card {
                            DecadesChart(plan: mainPlan, results: latest?.results, today: today, chartHeight: 240)
                        } header: {
                            timelineHeader
                        }
                    }
                    if let change {
                        TodayChangeTable(report: change, split: valuator.savedSplit(of: change),
                                         yearlySpending: mainPlan.flatMap(MilestoneLadder.spending(of:)))
                    }
                    notesAndFirstValues(hasAnswer: answer != nil)
                }
                VStack(alignment: .leading, spacing: Metrics.l) {
                    TodayAttentionCard(today: today)
                    if let year {
                        TodayYearCard(year: year, yourDate: moveThisYear(answer, plan: mainPlan, today: today))
                    }
                    TodayComingUpCard(plan: mainPlan, results: latest?.results, today: today)
                }
            }
        }
    }

    /// "Your timeline" with what it shows, and the Timeline's zooms, which
    /// open it there.
    private var timelineHeader: some View {
        HStack(alignment: .center, spacing: Metrics.s) {
            Text("Your timeline")
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .fixedSize()
                .accessibilityAddTraits(.isHeader)
            Text("your records to now, then the plan's futures")
                .font(.caption)
                .foregroundStyle(Palette.mutedInk)
                .lineLimit(1)
                .layoutPriority(-1)
            Spacer(minLength: Metrics.s)
            Picker("Open the Timeline at", selection: Binding(get: { TimelineZoom.decades },
                                                             set: { navigation.showTimeline($0) })) {
                ForEach(TimelineZoom.allCases) { zoom in
                    Text(zoom.title).tag(zoom)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .controlSize(.small)
        }
    }

    /// The date, or before there's one the next step.
    @ViewBuilder
    private func answerCard(_ answer: RetirementAnswer?, plan: PlanDocument?, results: PlanResults?,
                            year: TodayYear?, today: CalendarDate) -> some View {
        if let answer, let plan {
            TodayAnswerCard(answer: answer, plan: plan, results: results, year: year, today: today)
        } else {
            TodayPlanCard()
        }
    }

    /// How the date moved since the last check-in of last year, for *This
    /// year so far*; `nil` without one that recorded an age.
    private func moveThisYear(_ answer: RetirementAnswer?, plan: PlanDocument?,
                              today: CalendarDate) -> LastMondayMove? {
        guard let answer, let plan, let newYear = CalendarDate(year: today.year, month: 1, day: 1) else { return nil }
        let history = plans.recordedHeadlines(for: plan.id).map {
            AnswerPoint(date: $0.date, earliestAge: $0.earliestAge)
        }
        return LastMondayMove(answer: answer, history: history, latestCheckIn: newYear)
    }

    /// The yearly notes, offered once there's an answer, and before the
    /// first values the import that brings them.
    @ViewBuilder
    private func notesAndFirstValues(hasAnswer: Bool) -> some View {
        if hasAnswer {
            NotesOfferCard()
        }
        if library.latestCheckIn == nil {
            FirstCheckInCard()
        }
    }

    /// Calculates the main plan when its results are missing or out of
    /// date, so the date shown is the latest. A plan that failed waits for
    /// the Plan screen.
    private func calculateIfNeeded() async {
        guard library.canEdit, let plan = library.mainPlan?.id, plans.errors[plan] == nil,
              !plans.isRunning(plan, .base), !plans.isRunning(plan, .checkIn) else { return }
        guard plans.results(of: plan) == nil || !plans.staleReasons(of: plan).isEmpty else { return }
        _ = await plans.run(plan)
    }
}

// MARK: - The answer

/// "Your last Monday at work", the date, and how sure (UI.md, "Today").
///
/// On iPhone the whole card opens the plan: the date in large type, "At
/// 63, about 25 years from now, in 9 of 10 futures.", and a chip with how
/// it moved since the check-in before. On the Mac and iPad the date and
/// "At 63, in 9 of 10 futures. A year sooner since September." open the
/// plan, and four figures sit beside them (``TodayFigures``).
struct TodayAnswerCard: View {
    let answer: RetirementAnswer
    let plan: PlanDocument
    var results: PlanResults?
    /// This year so far, for the Mac's *Saved this year*.
    var year: TodayYear?
    let today: CalendarDate

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.pageLayout) private var layout
    @Environment(\.locale) private var locale
    /// The date's size on iPhone; it grows with Dynamic Type, and shrinks
    /// only when the date wouldn't fit on one line.
    @ScaledMetric(relativeTo: .largeTitle) private var dateSize: CGFloat = 52

    init(answer: RetirementAnswer, plan: PlanDocument, results: PlanResults? = nil, year: TodayYear? = nil,
         today: CalendarDate) {
        self.answer = answer
        self.plan = plan
        self.results = results
        self.year = year
        self.today = today
    }

    var body: some View {
        if layout.isWide {
            HStack(alignment: .center, spacing: Metrics.xl) {
                Button {
                    navigation.showPlan()
                } label: {
                    summary
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the plan")
                .frame(minWidth: 240, maxWidth: 420, alignment: .leading)
                TodayFigures(answer: answer, plan: plan, results: results, year: year, today: today)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, Metrics.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        } else {
            Button {
                navigation.showPlan()
            } label: {
                summary
                    .padding(.vertical, 18)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface()
                    .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the plan")
        }
    }

    /// The title, the date, the line under it, how it moved, and the status.
    private var summary: some View {
        let lastMonday = LastMonday(answer)
        let move = self.move
        return VStack(alignment: .leading, spacing: Metrics.xs) {
            Text(lastMonday == nil ? "Can I retire yet?" : "Your last Monday at work")
                .font(layout.isWide ? .body : .subheadline)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
            VStack(alignment: .leading, spacing: Metrics.xs) {
                Text(verbatim: headline(lastMonday))
                    .font(.system(size: layout.isWide ? 44 : dateSize, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                lineText(lastMonday, move: move)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .privacySensitiveInFeedback()
            if !layout.isWide, let move {
                TodayMoveChip(move: move)
                    .padding(.top, Metrics.s)
            }
            status
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// iPhone: "At 63, about 25 years from now, in 9 of 10 futures." The
    /// Mac and iPad: "At 63, in 9 of 10 futures." and how it moved, in the
    /// accent: "A year sooner since September."
    private func lineText(_ lastMonday: LastMonday?, move: LastMondayMove?) -> Text {
        guard layout.isWide else {
            return Text(verbatim: lastMonday.map { TodayText.line($0, today: today) } ?? line(lastMonday))
                .font(.callout)
        }
        let sure = Text(verbatim: line(lastMonday))
        guard let move else { return sure.font(.body) }
        let moved = Text(verbatim: GlanceText.move(move, relativeTo: today, locale: locale) + ".")
            .fontWeight(.semibold)
            .foregroundStyle(TodayMoveChip.color(of: move))
        return Text("\(sure) \(moved)").font(.body)
    }

    private func headline(_ lastMonday: LastMonday?) -> String {
        if let lastMonday { return GlanceText.lastMonday(lastMonday.date, locale: locale) }
        return answer.canRetireNow ? "Yes" : "Not yet"
    }

    private func line(_ lastMonday: LastMonday?) -> String {
        if let lastMonday { return GlanceText.lastMondayLine(lastMonday) }
        let futures = GlanceText.futures(answer.confidence)
        return answer.canRetireNow
            ? "You could stop working today, in \(futures) futures."
            : "No age works out in \(futures) futures yet. The plan shows what would change that."
    }

    /// How the earliest age moved since the check-in before the latest.
    private var move: LastMondayMove? {
        guard let latest = library.latestCheckIn else { return nil }
        let history = plans.recordedHeadlines(for: plan.id).map {
            AnswerPoint(date: $0.date, earliestAge: $0.earliestAge)
        }
        return LastMondayMove(answer: answer, history: history, latestCheckIn: latest)
    }

    /// A calculation going on, or why the plan can't be calculated.
    @ViewBuilder
    private var status: some View {
        if let progress = plans.progress(of: plan.id, .checkIn) ?? plans.progress(of: plan.id, .base) {
            HStack(spacing: Metrics.s) {
                ProgressView(value: min(1, max(0, progress.fraction)), total: 1)
                    .tint(Palette.accent)
                    .frame(maxWidth: 120)
                Text(verbatim: "Updating \(PlanRunText.overall(progress, locale: locale))")
                    .monospacedDigit()
            }
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
            .padding(.top, Metrics.xs)
        } else if let error = plans.errors[plan.id] {
            Label("Can't be calculated: \(error)", systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .privacySensitiveInFeedback()
                .padding(.top, Metrics.xs)
        }
    }
}

/// "A year sooner since September" in a tinted capsule: blue when sooner,
/// orange when later, grey when it stayed.
struct TodayMoveChip: View {
    let move: LastMondayMove
    /// What it says, when not since when (the plan's levers).
    var words: String?
    @Environment(\.locale) private var locale

    /// A move's colour: the accent when sooner, orange when later, grey
    /// when it stayed.
    static func color(of move: LastMondayMove) -> Color {
        move.years == 0 ? Palette.secondaryInk : move.isSooner ? Palette.accent : Palette.warning
    }

    var body: some View {
        let color = Self.color(of: move)
        Label {
            Text(verbatim: words ?? GlanceText.move(move, relativeTo: .today(), locale: locale))
                .lineLimit(1)
        } icon: {
            Image(systemName: move.years == 0 ? "equal" : move.isSooner ? "arrow.left" : "arrow.right")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, Metrics.m)
        .padding(.vertical, 6)
        .background(color.opacity(0.12), in: Capsule())
        .privacySensitiveInFeedback()
    }
}

// MARK: - Before the first values

/// Before the first values: one clear next step. Most values come from
/// imported files, so it opens the import.
struct FirstCheckInCard: View {
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        Card("Import your first values") {
            VStack(alignment: .leading, spacing: Metrics.m) {
                Text("Your accounts get their values from the files you import: bank statements, broker exports or "
                     + "a spreadsheet. Your history starts with them.")
                    .font(.callout)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Import Files…") { navigation.startImport() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// A new library without accounts: import files, which create them, or
/// add an account for a later import to fill.
private struct TodayEmptyState: View {
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        ContentUnavailableView {
            Label("No accounts yet", systemImage: AppSymbol.accounts)
        } description: {
            Text("Import your bank statements, broker exports or your own spreadsheet. Each file creates the "
                 + "accounts in it.")
        } actions: {
            Button("Import Files…") { navigation.startImport() }
                .buttonStyle(.borderedProminent)
            Button("Add an Account") { navigation.newAccount() }
        }
        .background(Palette.page)
    }
}

#Preview("Today") {
    NavigationStack {
        TodayScreen()
            .todayToolbar()
            .appDestinations()
    }
    .previewEnvironment()
}

#Preview("Hidden amounts") {
    NavigationStack {
        TodayScreen()
            .redacted(reason: .privacy)
    }
    .previewEnvironment()
}

#Preview("Empty") {
    NavigationStack {
        TodayScreen()
    }
    .previewEnvironment(PreviewLibrary.empty)
}
