import Glance
import Model
import Planner
import SwiftUI
import Tracker

/// The home screen (UI.md, "Today"): your last Monday at work, what moved
/// it at the last check-in, and where you stand.
///
/// One layout at every width: the answer as a date on the app icon's dusk
/// (``TodayAnswerCard``), or before there's one the next step
/// (``TodayPlanCard``); then tiles (``TodayTiles``) on a grid of slots as
/// wide as an iPhone's (``TileGrid``). Where a row has four slots or six
/// the answer takes two of them, with net worth and what moved beside it
/// as tall tiles that end with it, and the smaller tiles under them. Then
/// what needs attention, only while something does, and *Coming up*, the
/// milestones ahead as tiles (``TodayComingUp``).
///
/// When the main plan's results are out of date, Today calculates it in
/// the background: there's no *Calculate* here.
struct TodayScreen: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.pageLayout) private var layout
    /// The page's width inside its margins, which sets the slots.
    @State private var pageWidth: CGFloat = 0

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
            page(today: today)
                .measuringWidth($pageWidth)
                .padding(layout.gutter)
                .frame(maxWidth: layout.isWide ? Metrics.wideReadableWidth : Metrics.readableWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .background(Palette.page)
    }

    /// The answer with net worth and what moved beside it where a row has
    /// four slots or six, and the other tiles; then what needs attention
    /// and *Coming up*.
    private func page(today: CalendarDate) -> some View {
        let mainPlan = library.mainPlan
        let latest = mainPlan == nil ? nil : plans.mainAnswer
        let answer = latest?.answer
        let results = latest?.results
        let slots = TileGrid.slots(width: pageWidth)
        return VStack(alignment: .leading, spacing: Metrics.l) {
            TodayAnswerAndTiles(answer: answer, plan: mainPlan, results: results, today: today, pageWidth: pageWidth)
            TodayAttentionCard(today: today)
            TodayComingUp(plan: mainPlan, results: results, slots: slots)
            notesAndFirstValues(hasAnswer: answer != nil)
        }
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

// MARK: - The answer and the tiles

/// The answer with net worth and what moved beside it where a row has
/// four slots or six, and the other tiles under them; else the answer, or
/// before there's one the next step, above every tile. Today shows it, and
/// so does the check-in once it's saved.
struct TodayAnswerAndTiles: View {
    let answer: RetirementAnswer?
    let plan: PlanDocument?
    let results: PlanResults?
    let today: CalendarDate
    /// The page's width inside its margins, which sets the slots.
    let pageWidth: CGFloat
    /// Whether the next check-in's tile shows: not on the saved check-in.
    var showsCheckIn = true

    var body: some View {
        let slots = TileGrid.slots(width: pageWidth)
        if let answer, let plan, slots >= 4 {
            VStack(alignment: .leading, spacing: Metrics.m) {
                let answerWidth = 2 * TileGrid.smallWidth(width: pageWidth) + Metrics.m
                HStack(alignment: .top, spacing: Metrics.m) {
                    TodayAnswerCard(answer: answer, plan: plan, results: results, today: today)
                        .frame(width: answerWidth)
                    TileGrid(fillsHeight: true) {
                        TodayTiles(part: .beside(slots: slots - 2), plan: plan, results: results, today: today)
                    }
                    // At most the rest of the page: never unbounded while the
                    // stack measures it, and narrowing with the page.
                    .frame(maxWidth: max(0, pageWidth - answerWidth - Metrics.m))
                }
                .fixedSize(horizontal: false, vertical: true)
                TileGrid {
                    TodayTiles(part: .under, plan: plan, results: results, today: today, showsCheckIn: showsCheckIn)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: Metrics.m) {
                if let answer, let plan {
                    TodayAnswerCard(answer: answer, plan: plan, results: results, today: today)
                } else {
                    TodayPlanCard()
                }
                TileGrid {
                    TodayTiles(part: .all, plan: plan, results: results, today: today, showsCheckIn: showsCheckIn)
                }
            }
        }
    }
}

// MARK: - The answer

/// "Your last Monday at work", the date, and how sure, on the app icon's
/// dusk (UI.md, "Today"); the whole card opens the plan. In white: the day
/// and month in large type and the year under them in the sun's light,
/// "At 63 · in 9 of 10 futures", "About 25 years from now.", a chip with
/// how it moved since the check-in before, and a calculation going on or
/// why the plan can't be calculated; the horizon and the sun under them.
/// Beside tiles it fills their height, and the horizon stays at its
/// bottom.
struct TodayAnswerCard: View {
    let answer: RetirementAnswer
    let plan: PlanDocument
    var results: PlanResults?
    let today: CalendarDate

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.locale) private var locale
    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif
    /// The date's size; it grows with Dynamic Type, and shrinks only when
    /// the date wouldn't fit on one line.
    @ScaledMetric(relativeTo: .largeTitle) private var dateSize: CGFloat = 64

    /// A short screen (iPhone in landscape): the date on one line and less
    /// room for the horizon, so the card fits the screen's height.
    private var isShort: Bool {
        #if os(iOS)
        verticalSizeClass == .compact
        #else
        false
        #endif
    }

    init(answer: RetirementAnswer, plan: PlanDocument, results: PlanResults? = nil, today: CalendarDate) {
        self.answer = answer
        self.plan = plan
        self.results = results
        self.today = today
    }

    var body: some View {
        Button {
            navigation.showPlan()
        } label: {
            hero
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the plan")
    }

    /// The room under the words for the dusk's horizon and its sun.
    private var horizonRoom: CGFloat { isShort ? 90 : 150 }

    private var hero: some View {
        let lastMonday = LastMonday(answer)
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        return VStack(alignment: .leading, spacing: Metrics.xs) {
            Text(lastMonday == nil ? "Can I retire yet?" : "Your last Monday at work")
                .font(.subheadline.weight(.semibold))
                .opacity(0.85)
                .lineLimit(1)
            Group {
                if let lastMonday {
                    let layout = isShort ? AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
                        : AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                    layout {
                        Text(verbatim: lastMonday.date.dateValue
                            .formatted(.dateTime.day().month(.wide).locale(locale)))
                        Text(verbatim: String(lastMonday.date.year))
                            .foregroundStyle(DuskBackground.sunLight)
                    }
                    .font(.system(size: isShort ? dateSize * 0.7 : dateSize, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .padding(.top, Metrics.xs)
                    Text(verbatim: TodayText.ageAndFutures(lastMonday))
                        .font(.headline)
                        .padding(.top, Metrics.s)
                    if let away = TodayText.away(lastMonday, today: today) {
                        Text(verbatim: away.capitalizedFirst + ".")
                            .font(.subheadline)
                            .opacity(0.85)
                    }
                } else {
                    Text(verbatim: answer.canRetireNow ? "Yes" : "Not yet")
                        .font(.system(size: dateSize, weight: .heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(verbatim: line)
                        .font(.callout)
                        .opacity(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .privacySensitiveInFeedback()
            if let move {
                TodayMoveChip(move: move, onDusk: true)
                    .padding(.top, Metrics.s)
            }
            status
        }
        .foregroundStyle(.white)
        .padding(.top, 22)
        .padding(.horizontal, 22)
        .padding(.bottom, horizonRoom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            DuskBackground(horizonHeight: horizonRoom)
                .clipShape(shape)
                .accessibilityHidden(true)
        }
        .contentShape(shape)
    }

    /// Without an age that works: whether you could stop today, and in how
    /// many futures.
    private var line: String {
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
        let ink = Color.white.opacity(0.85)
        if let progress = plans.progress(of: plan.id, .checkIn) ?? plans.progress(of: plan.id, .base) {
            HStack(spacing: Metrics.s) {
                ProgressView(value: min(1, max(0, progress.fraction)), total: 1)
                    .tint(ink)
                    .frame(maxWidth: 120)
                Text(verbatim: "Updating \(PlanRunText.overall(progress, locale: locale))")
                    .monospacedDigit()
            }
            .font(.footnote)
            .foregroundStyle(ink)
            .padding(.top, Metrics.xs)
        } else if let error = plans.errors[plan.id] {
            Label("Can't be calculated: \(error)", systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
                .privacySensitiveInFeedback()
                .padding(.top, Metrics.xs)
        }
    }
}

/// "A year sooner since September" in a tinted capsule: blue when sooner,
/// orange when later, grey when it stayed; on Today's dusk, white.
struct TodayMoveChip: View {
    let move: LastMondayMove
    /// What it says, when not since when (the plan's levers).
    var words: String?
    /// White on a translucent capsule, for Today's dusk.
    var onDusk = false
    @Environment(\.locale) private var locale

    /// A move's colour: the accent when sooner, orange when later, grey
    /// when it stayed.
    static func color(of move: LastMondayMove) -> Color {
        move.years == 0 ? Palette.secondaryInk : move.isSooner ? Palette.accent : Palette.warning
    }

    var body: some View {
        let color = onDusk ? Color.white : Self.color(of: move)
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
        .background(color.opacity(onDusk ? 0.18 : 0.12), in: Capsule())
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
