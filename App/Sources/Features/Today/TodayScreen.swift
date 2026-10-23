import Glance
import Model
import Planner
import SwiftUI
import Tracker

/// The home screen (UI.md, "Today"): your last Monday at work, what moved
/// it at the last check-in, and where you stand.
///
/// Top to bottom: the answer as a date (``TodayAnswerCard``), or before
/// there's one the next step (``OverviewAnswerCard``); *What changed* at
/// the last check-in; a card of rows (the plan's target age, the next
/// milestone, net worth, which opens the accounts); and *Needs attention*
/// only while something does. On the Mac and iPad the rows sit beside the
/// answer, the decades chart runs under both, and this year's change sits
/// beside the last check-in's.
///
/// When the main plan's results are out of date, Today calculates it in
/// the background: there's no *Calculate* here.
struct TodayScreen: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(AppPreferences.self) private var preferences
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
        .task(id: library.revision) { await calculateIfNeeded() }
    }

    private var content: some View {
        let valuator = library.valuator
        let today = CalendarDate.today()
        let mainPlan = library.mainPlan
        let latest = mainPlan == nil ? nil : plans.mainAnswer
        let answer = latest?.answer
        let spending = mainPlan.flatMap(MilestoneLadder.spending(of:))
        let change = valuator.changeSinceLastCheckIn(asOf: today)
        return ScrollView {
            VStack(alignment: .leading, spacing: Metrics.l) {
                if layout.isWide {
                    EqualColumns(spacing: Metrics.l) {
                        answerCard(answer, plan: mainPlan)
                        TodayRowsCard(answer: answer, plan: mainPlan, results: latest?.results, today: today)
                    }
                    if let mainPlan {
                        Card("Your timeline") {
                            DecadesChart(plan: mainPlan, results: latest?.results, today: today)
                        }
                    }
                    EqualColumns(spacing: Metrics.l) {
                        VStack(alignment: .leading, spacing: Metrics.l) {
                            if let change {
                                OverviewChangeCard(report: change, split: valuator.savedSplit(of: change),
                                                   yearlySpending: spending)
                            }
                            notesAndFirstValues(hasAnswer: answer != nil)
                        }
                        VStack(alignment: .leading, spacing: Metrics.l) {
                            OverviewAttentionCard(today: today)
                            if let report = valuator.changeThisYear(asOf: today) {
                                OverviewYearCard(
                                    report: report, split: valuator.savedSplit(of: report),
                                    savings: library.library.accountsTurningOffTrends.isEmpty
                                        ? valuator.savingsRate(from: report.from.adding(days: 1), through: today)
                                        : nil,
                                    yearlySpending: spending)
                            }
                        }
                    }
                } else {
                    answerCard(answer, plan: mainPlan)
                    if let change {
                        OverviewChangeCard(report: change, split: valuator.savedSplit(of: change),
                                           yearlySpending: spending)
                    }
                    TodayRowsCard(answer: answer, plan: mainPlan, results: latest?.results, today: today)
                    OverviewAttentionCard(today: today)
                    notesAndFirstValues(hasAnswer: answer != nil)
                }
            }
            .padding(layout.gutter)
            .frame(maxWidth: layout.isWide ? Metrics.wideReadableWidth : Metrics.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.page)
    }

    /// The date, or before there's one the next step.
    @ViewBuilder
    private func answerCard(_ answer: RetirementAnswer?, plan: PlanDocument?) -> some View {
        if let answer, let plan {
            TodayAnswerCard(answer: answer, plan: plan)
        } else {
            OverviewAnswerCard()
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

// MARK: - The answer

/// "Your last Monday at work", the date, "At 63, in 9 of 10 futures.", and
/// how it moved since the check-in before (UI.md, "Today"). A tap opens the
/// plan.
struct TodayAnswerCard: View {
    let answer: RetirementAnswer
    let plan: PlanDocument

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.locale) private var locale

    var body: some View {
        let lastMonday = LastMonday(answer)
        Button {
            navigation.showPlan()
        } label: {
            VStack(alignment: .leading, spacing: Metrics.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text(lastMonday == nil ? "Can I retire yet?" : "Your last Monday at work")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.secondaryInk)
                    Spacer(minLength: Metrics.s)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.mutedInk)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: Metrics.xs) {
                    Text(verbatim: headline(lastMonday))
                        .font(.largeTitle.bold())
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    Text(verbatim: line(lastMonday))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .privacySensitiveInFeedback()
                if let move {
                    TodayMoveChip(move: move)
                }
                status
            }
            .padding(Metrics.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the plan")
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
        } else if let error = plans.errors[plan.id] {
            Label("Can't be calculated: \(error)", systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .privacySensitiveInFeedback()
        }
    }
}

/// "A year sooner since September", green when sooner, orange when later,
/// grey when it stayed.
struct TodayMoveChip: View {
    let move: LastMondayMove
    /// What it says, when not since when (the plan's levers).
    var words: String?
    @Environment(\.locale) private var locale

    var body: some View {
        let color = move.years == 0 ? Palette.secondaryInk : move.isSooner ? Palette.positive : Palette.warning
        Label {
            Text(verbatim: words ?? GlanceText.move(move, relativeTo: .today(), locale: locale))
        } icon: {
            Image(systemName: move.years == 0 ? "equal" : move.isSooner ? "arrow.left" : "arrow.right")
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, Metrics.s)
        .padding(.vertical, Metrics.xs)
        .background(color.opacity(0.12), in: Capsule())
        .privacySensitiveInFeedback()
    }
}

// MARK: - Rows

/// Where you stand, a row each: the chance at the plan's target age, the
/// next milestone with how far there, and net worth, which opens the
/// accounts.
struct TodayRowsCard: View {
    let answer: RetirementAnswer?
    let plan: PlanDocument?
    let results: PlanResults?
    let today: CalendarDate

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.baseCurrency) private var currency
    @Environment(\.locale) private var locale

    var body: some View {
        let netWorth = NetWorthGlance(valuator: library.valuator, asOf: today)
        VStack(alignment: .leading, spacing: 0) {
            if let answer, let target = answer.targetAge, let success = answer.successAtTarget {
                row {
                    Text(verbatim: "At \(target), as planned")
                        .privacySensitiveInFeedback()
                } value: {
                    Text(verbatim: "\(GlanceText.futures(success)) futures")
                        .privacySensitiveInFeedback()
                }
                .onTapGesture { navigation.showPlan() }
                Divider()
            }
            if let plan, let next = milestones(of: plan).next {
                let text = PlanMilestoneText(currency: currency, locale: locale)
                row {
                    HStack(spacing: Metrics.xs) {
                        Text("Next:")
                        AmountSentenceText(text.name(next.milestone))
                    }
                } value: {
                    Text(verbatim: text.progress(next))
                        .privacySensitiveInFeedback()
                } below: {
                    ShareBarTrack(share: next.progress)
                }
                .onTapGesture { navigation.showTimeline(.year) }
                Divider()
            }
            Button {
                navigation.showAccounts()
            } label: {
                row {
                    Text("Net worth")
                } value: {
                    HStack(spacing: Metrics.s) {
                        AmountText(netWorth.total, animatesChanges: true)
                            .foregroundStyle(Palette.ink)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.mutedInk)
                            .accessibilityHidden(true)
                    }
                } below: {
                    if let change = netWorth.sinceLastCheckIn {
                        HStack(spacing: Metrics.xs) {
                            DeltaText(change.change)
                            Text(GlanceText.period(from: change.from, to: change.to, relativeTo: today,
                                                   locale: locale))
                                .foregroundStyle(Palette.secondaryInk)
                                .privacySensitiveInFeedback()
                        }
                        .font(.footnote)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows your accounts")
        }
        .padding(.horizontal, Metrics.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1)
        }
    }

    private func milestones(of plan: PlanDocument) -> PlanMilestones {
        let progress = plans.planProgress(of: plan.id, document: plan)
        return PlanMilestones(plan: plan, library: library.library, valuator: library.valuator,
                              asOf: library.asOfDate, results: results, reached: progress.reached)
    }

    private func row(@ViewBuilder _ title: () -> some View, @ViewBuilder value: () -> some View) -> some View {
        row(title, value: value, below: { EmptyView() })
    }

    private func row(@ViewBuilder _ title: () -> some View, @ViewBuilder value: () -> some View,
                     @ViewBuilder below: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                title()
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: Metrics.s)
                value()
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            below()
        }
        .font(.body)
        .padding(.vertical, Metrics.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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
