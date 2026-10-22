import Model
import Planner
import SwiftUI

/// The plan (UI.md, "Plan"): the answer; your life as a strip of chapters
/// with one graph running through them; the chosen chapter below, in words
/// and with its settings, where the plan changes; what every chapter
/// assumes; and, folded away, the charts behind the answer.
///
/// Nothing runs on its own (UI.md, "Calculating"): before the first
/// calculation the answer recorded at the last check-in shows with
/// *Calculate*, and the strip has its chapters without the money; when the
/// plan or the library changed, an *Out of date* banner offers *Recalculate*.
struct PlanTimelineView: View {
    let session: PlanSession
    /// The Target mix sheet, which the plan's screen opens too (``PlanRoute``).
    @Binding var showsTargetMix: Bool
    /// Opens the What-if sheet (iPhone); on the Mac and iPad What if is in the toolbar.
    var onWhatIf: (() -> Void)?
    /// Shows Progress.
    var onShowProgress: (() -> Void)?
    /// Export Calculations…
    var onExport: (() -> Void)?

    @Environment(\.pageLayout) private var layout
    @Environment(\.locale) private var locale
    @State private var editing: PlanEditTarget?
    @State private var showsAssumptions = false
    @State private var showsMoreCharts = false

    private var gutter: CGFloat { layout.gutter }

    private var milestoneText: PlanMilestoneText {
        PlanMilestoneText(currency: session.currency, locale: locale)
    }

    var body: some View {
        @Bindable var session = session
        // Without the progress: only the progress card follows every update.
        let state = session.state
        let derived = session.derived(locale: locale)
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.l) {
                VStack(alignment: .leading, spacing: Metrics.m) {
                    PlanResultsBanners(session: session)
                    if state.isRunning {
                        PlanRunProgressCard(session: session)
                    } else {
                        PlanOutOfDateBanner(state: state) { session.perform($0) }
                    }
                    headline(state, onTrack: derived.onTrack)
                    PlanResultWarnings(session: session)
                }
                .padding(.horizontal, gutter)
                if session.plan != nil {
                    chapters($session.editablePlan, state: state, derived: derived)
                    PlanAssumptionsFooter(onShowAll: { showsAssumptions = true }, onExport: onExport)
                        .padding(.horizontal, gutter)
                    moreCharts(state.results)
                        .padding(.horizontal, gutter)
                }
            }
            .padding(.vertical, gutter)
        }
        .background(Palette.page)
        .sheet(item: $editing) { target in
            PlanItemSheet(session: session, target: target, issues: session.inputIssues)
        }
        .sheet(isPresented: $showsTargetMix) {
            PlanTargetMixSheet(session: session)
        }
        .sheet(isPresented: $showsAssumptions) {
            PlanAlwaysSheet(session: session)
        }
        .onDisappear { session.saveNow() }
    }

    private var words: PlanWords {
        PlanWords(currency: session.currency, locale: locale)
    }

    // MARK: The answer

    @ViewBuilder
    private func headline(_ state: PlanResultsState, onTrack: OverviewOnTrack?) -> some View {
        if let results = state.results {
            // On iPhone the ring and its words dim as on the Overview; the tiles stay.
            PlanTimelineHeadline(session: session, results: results, onTrack: onTrack, dims: state.dimsResults,
                                 onShowProgress: onShowProgress, onWhatIf: onWhatIf)
                .opacity(layout.isWide && state.isRunning ? 0.5 : 1)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("plan.answer")
        } else if !state.isRunning {
            PlanCalculatePrompt(state: state,
                                runs: session.plan?.simulation.effectiveRuns ?? PlanSimulation.defaultRuns) {
                session.calculate()
            }
        }
    }

    // MARK: The chapters

    @ViewBuilder
    private func chapters(_ plan: Binding<PlanDocument>, state: PlanResultsState, derived: PlanDerived)
        -> some View {
        let issues = session.inputIssues
        PlanUnplacedIssues(issues: issues)
            .padding(.horizontal, gutter)
        if let model = derived.chapters, let timeline = derived.timeline {
            if model.chapters.chapters.isEmpty {
                PlanNoChapters(plan: plan)
                    .padding(.horizontal, gutter)
            } else {
                let count = model.chapters.chapters.count
                let selected = min(session.selectedChapter(in: model) ?? 0, count - 1)
                let selection = Binding<Int>(get: { selected },
                                             set: { session.selectChapter($0, in: model) })
                PlanStripHeader(
                    title: PlanTimelineText.chapters(count),
                    hint: layout.isWide ? "Scroll sideways, or use the arrows." : "Scroll sideways; tap a chapter.",
                    steps: layout.isWide ? PlanStepButtons(index: selected, count: count, today: 0,
                                                    select: { selection.wrappedValue = $0 }) : nil)
                    .padding(.horizontal, gutter)
                PlanChapterStrip(timeline: timeline, selection: selection)
                    .opacity(state.dimsResults ? 0.7 : 1)
                PlanChapterDetails(
                    model: model, index: selected,
                    story: PlanChapterStory(chapterAt: selected, in: model, results: state.results, words: words),
                    barMaximum: derived.barMaximum, plan: plan, words: words,
                    issues: issues, canEdit: session.canEdit,
                    editing: $editing,
                    milestones: timeline.cards.indices.contains(selected) ? timeline.cards[selected].milestones : [],
                    milestoneText: milestoneText,
                    onOpen: show, onSelect: { selection.wrappedValue = $0 },
                    onUsePlanAge: { session.selectFocus(nil) })
                    .padding(.horizontal, gutter)
            }
            if !model.chapters.outside.isEmpty {
                PlanOutsideCard(model: model, plan: plan, issues: issues, words: words, onOpen: show)
                    .padding(.horizontal, gutter)
            }
        } else {
            PlanChaptersNeedBirthDate()
                .padding(.horizontal, gutter)
        }
    }

    /// Opens a setting's sheet: spending's, an item's, or the target mix's.
    private func show(_ sheet: PlanSettingSheet) {
        guard let plan = session.plan else { return }
        switch sheet {
        case .item(.workingSpending):
            editing = .workingSpending(plan.spending)
        case .item(.retiredSpending):
            editing = .retiredSpending(plan.spending)
        case .flexibleSpending:
            editing = .flexibleSpending(plan.spending)
        case .item(.spendingPhase(let index)) where plan.spending.phases.indices.contains(index):
            editing = .spendingPhase(index: index, phase: plan.spending.phases[index])
        case .item(.work(let index)) where plan.work.indices.contains(index):
            editing = .work(index: index, phase: plan.work[index])
        case .item(.pension(let index)) where plan.pensions.indices.contains(index):
            editing = .pension(index: index, pension: plan.pensions[index])
        case .item(.income(let index)) where plan.income.indices.contains(index):
            editing = .income(index: index, income: plan.income[index])
        case .item(.contribution(let index)) where plan.contributions.indices.contains(index):
            editing = .contribution(index: index, contribution: plan.contributions[index])
        case .item(.event(let index)) where plan.events.indices.contains(index):
            editing = .event(index: index, event: plan.events[index])
        case .item(.targetMix), .item(.targetMixStep):
            showsTargetMix = true
        default:
            break
        }
    }

    // MARK: More charts

    @ViewBuilder
    private func moreCharts(_ results: PlanResults?) -> some View {
        if let results {
            DisclosureGroup(isExpanded: $showsMoreCharts) {
                VStack(alignment: .leading, spacing: Metrics.l) {
                    PlanFanCard(results: results)
                    if layout.isRoomy {
                        EqualColumns(spacing: Metrics.l) {
                            PlanSuccessCard(session: session, results: results)
                            PlanIncomeCard(results: results)
                        }
                        EqualColumns(spacing: Metrics.l) {
                            PlanKeyNumbersCard(results: results)
                            Color.clear
                                .frame(height: 1)
                        }
                    } else {
                        PlanSuccessCard(session: session, results: results)
                        PlanIncomeCard(results: results)
                        PlanKeyNumbersCard(results: results)
                    }
                }
                .padding(.top, Metrics.s)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("More charts")
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                    Text("Your money over time, chance by retirement age, income and taxes, key numbers.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
        }
    }
}

// MARK: - The answer

/// The plan's answer (UI.md, "The plan").
///
/// - **iPhone:** the Overview's *Can I retire yet?* tile, the ring and its
///   words (``RetirementAnswerRow``); under it *What if* (``PlanWhatIfTile``)
///   beside *On track?* (``OverviewOnTrackTile``), which opens Progress; then
///   why, in a quiet line ("At 55, as planned, 4 in 10 futures last to 95.
///   Your bar is 9 in 10.").
/// - **Mac and iPad:** a header: "Not yet. Stop at 63, in April 2051.", why,
///   as ten dots and in words, and where you stand against this year's
///   baseline, which opens Progress. What if is in the toolbar.
struct PlanTimelineHeadline: View {
    let session: PlanSession
    let results: PlanResults
    /// Where the latest check-in stands, as the Overview's *On track?* has it.
    var onTrack: OverviewOnTrack?
    /// Whether the answer dims: the results are out of date or being recalculated.
    var dims = false
    var onShowProgress: (() -> Void)?
    var onWhatIf: (() -> Void)?

    @Environment(\.pageLayout) private var layout
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var focusAge: Int { results.details.focus.age }

    private var success: Double? { results.details.focus.success ?? results.headline.successAtTarget }

    private var endAge: Int { results.details.endAge }

    private var progress: PlanBaselineComparison.Position? { onTrack?.position }

    var body: some View {
        let title = PlanTimelineText.headline(results.headline, locale: locale)
        // On the Mac and iPad, the pill goes under the words rather than
        // beside them when What if narrows the page.
        if layout.isWide && layout.besideWhatIf {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(Self.wideTitleFont)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .privacySensitiveInFeedback()
                    .accessibilityAddTraits(.isHeader)
                reason
                    .foregroundStyle(Palette.secondaryInk)
                progressPill
                    .padding(.top, Metrics.xs)
            }
        } else if layout.isWide {
            HStack(alignment: .top, spacing: Metrics.l) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(Self.wideTitleFont)
                        .foregroundStyle(Palette.ink)
                        .privacySensitiveInFeedback()
                        .accessibilityAddTraits(.isHeader)
                    reason
                        .foregroundStyle(Palette.secondaryInk)
                }
                Spacer(minLength: Metrics.l)
                progressPill
            }
        } else {
            VStack(alignment: .leading, spacing: Metrics.m) {
                answerTile
                tiles
                if let success {
                    Text(reasonText(success))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(dims ? OverviewHeader.dimmedOpacity : 1)
                        .privacySensitiveInFeedback()
                }
            }
        }
    }

    // MARK: iPhone

    /// The Overview's answer tile without its chevron and run status: the
    /// banners above say when the results are out of date or calculating.
    private var answerTile: some View {
        let headline = results.headline
        let words = OverviewAnswerText(headline: headline, earliestDate: headline.earliestDate,
                                       today: CalendarDate.today(), locale: locale)
        return FigureTile(surface: .raised) {
            Text("Can I retire yet?")
                .font(.title2.bold())
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            RetirementAnswerRow(headline: headline, words: words, dims: dims)
                .padding(.top, Metrics.m)
        }
        .font(.subheadline)
        .accessibilityElement(children: .contain)
    }

    /// *What if* and *On track?*, side by side and as tall as each other, 12
    /// points apart as on the Overview; stacked at the largest text sizes.
    @ViewBuilder
    private var tiles: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Metrics.m) {
                tileContent
            }
        } else {
            EqualColumns(spacing: Metrics.m, equalHeights: true) {
                tileContent
            }
        }
    }

    @ViewBuilder
    private var tileContent: some View {
        if let onWhatIf {
            PlanWhatIfTile(session: session, action: onWhatIf)
        }
        if let onTrack, let onShowProgress {
            OverviewOnTrackTile(onTrack: onTrack, currency: session.currency, dims: dimsCoastLine,
                                action: onShowProgress)
        }
    }

    /// Whether *On track?*'s coast point line dims: with the rest of the
    /// results, and while they're a quick estimate, which doesn't solve the
    /// coast age, so the line is the one the latest check-in recorded.
    private var dimsCoastLine: Bool { dims || results.mode == .fast }

    // MARK: Mac and iPad

    /// The answer's title on the Mac and iPad: 22 points on the Mac.
    private static var wideTitleFont: Font {
        #if os(macOS)
        Font.title.weight(.bold)
        #else
        Font.title2.weight(.bold)
        #endif
    }

    /// Why: the futures that last at the age shown, as dots and in words, against your bar.
    @ViewBuilder
    private var reason: some View {
        if let success {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                PlanTenthsView(filled: PlanTimelineText.tenths(success))
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                Text(reasonText(success))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .privacySensitiveInFeedback()
            }
        }
    }

    /// "At 55, as planned, 4 in 10 futures last to 95. Your bar is 9 in 10."
    private func reasonText(_ success: Double) -> String {
        let isPlanned = !session.hasWhatIf && focusAge == results.headline.targetAge
        return PlanTimelineText.reason(success, endAge: endAge, age: focusAge, isPlanned: isPlanned,
                                       bar: results.headline.confidence)
    }

    /// "On plan · 18.400 € ahead ›": the amount against the baseline's
    /// median, in orange only when behind plan
    /// (``PlanBaselineComparison/Standing``).
    @ViewBuilder
    private var progressPill: some View {
        if let progress, let onShowProgress {
            let standing = progress.standing
            Button(action: onShowProgress) {
                HStack(spacing: 4) {
                    Text(verbatim: "\(standing.label) ·")
                        .privacySensitiveInFeedback()
                    AmountText(abs(progress.gap), currency: session.currency, tabular: false)
                    Text(verbatim: progress.gap >= 0 ? "ahead" : "behind")
                        .privacySensitiveInFeedback()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(standing.color)
                .padding(.horizontal, Metrics.m)
                .padding(.vertical, 6)
                .background(standing.tint.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityHint(Text("Shows your progress"))
        }
    }
}

/// *What if* on iPhone (UI.md, "The plan"): a tile tinted in the accent
/// beside *On track?*, which opens the sliders in a sheet. Without a change
/// it says what it's for; with one, what's changed ("Stop at 52", "Spend
/// 2.800 € a month") and, once it has run, how the earliest age moved
/// ("Earliest 54 → 53").
struct PlanWhatIfTile: View {
    let session: PlanSession
    let action: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        let words = PlanWords(currency: session.currency, locale: locale)
        let changes = session.whatIfModel.map { PlanWhatIfText.changes($0, words: words) } ?? []
        Button(action: action) {
            FigureTile(surface: .accent) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
                    Text("What if…")
                        .fontWeight(.semibold)
                    Spacer(minLength: Metrics.xs)
                    Image(systemName: "slider.horizontal.3")
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Palette.accent)
                if changes.isEmpty {
                    Text("Try a change before you make it in the plan.")
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                        AmountSentenceText(change)
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let change = PlanWhatIfPanel.change(in: session) {
                        Text("Earliest \(change)")
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundStyle(Palette.accent)
                            .privacySensitiveInFeedback()
                    }
                }
            }
            .font(.subheadline)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens What if"))
    }
}

/// A strip's title ("Your life in 6 chapters", "Year by year"), how to move
/// along it, and on the Mac and iPad ‹ › beside them.
struct PlanStripHeader: View {
    let title: String
    let hint: String?
    let steps: PlanStepButtons?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                if let hint {
                    Text(hint)
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            Spacer(minLength: Metrics.s)
            if let steps {
                steps
            }
        }
    }
}

/// ‹ › buttons that step through `count` items (⌘[ and ⌘] with a
/// keyboard), and *Today* when one of them is today's.
struct PlanStepButtons: View {
    let index: Int
    let count: Int
    /// The item that holds today: *Today* selects it.
    var today: Int?
    let select: (Int) -> Void

    var body: some View {
        HStack(spacing: Metrics.xs) {
            if let today {
                Button("Today") { select(today) }
                    .disabled(index == today)
            }
            Button {
                select(index - 1)
            } label: {
                Label("Earlier", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
            }
            .keyboardShortcut("[", modifiers: .command)
            .help("Earlier (⌘[)")
            .disabled(index <= 0)
            Button {
                select(index + 1)
            } label: {
                Label("Later", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
            }
            .keyboardShortcut("]", modifiers: .command)
            .help("Later (⌘])")
            .disabled(index >= count - 1)
        }
        .buttonStyle(.bordered)
    }
}

// MARK: - A chapter in words

/// The chosen chapter (UI.md, "Plan"): its number, name and span; what
/// happens in it, in words that only read (its values in bold), a month's
/// money as a bar, the milestones along the way and what can go wrong; and
/// its settings, where the plan changes: every input that starts in it,
/// once. Side by side on the Mac and iPad; on iPhone the settings follow.
struct PlanChapterDetails: View {
    let model: PlanChaptersModel
    let index: Int
    let story: PlanChapterStory
    /// The largest month among the chapters, for the bar.
    let barMaximum: Double
    @Binding var plan: PlanDocument
    /// Amounts in the plan's currency, hidden with the eye.
    let words: PlanWords
    let issues: PlanInputIssues
    var canEdit = true
    @Binding var editing: PlanEditTarget?
    /// The milestones the median future reaches in the chapter.
    var milestones: [ProjectedMilestone] = []
    let milestoneText: PlanMilestoneText
    /// Opens a setting's sheet.
    var onOpen: (PlanSettingSheet) -> Void = { _ in }
    var onSelect: (Int) -> Void = { _ in }
    var onUsePlanAge: () -> Void = {}

    /// The milestones listed before "and N more".
    private static let shownMilestones = 4

    @Environment(\.pageLayout) private var layout

    private var chapter: PlanChapter { model.chapters.chapters[index] }

    var body: some View {
        // The settings beside the words when the page has the room.
        if layout.isRoomy {
            Card {
                VStack(alignment: .leading, spacing: Metrics.l) {
                    header
                    HStack(alignment: .top, spacing: Metrics.xl) {
                        reading
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                        settings
                            .frame(width: 380, alignment: .leading)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: Metrics.l) {
                Card {
                    VStack(alignment: .leading, spacing: Metrics.l) {
                        header
                        reading
                    }
                }
                settings
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Metrics.s) {
            PlanChapterBadge(number: index + 1, style: model.style(of: chapter))
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title(of: chapter))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("\(model.span(ofChapterAt: index)) · \(model.length(ofChapterAt: index))")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondaryInk)
            }
            .privacySensitiveInFeedback()
            Spacer(minLength: Metrics.s)
            // ‹ › on iPhone; on the Mac and iPad they're above the strip.
            if !layout.isWide {
                PlanStepButtons(index: index, count: model.chapters.chapters.count, select: onSelect)
            }
        }
    }

    /// What happens: the words, a month's money, the milestones along the
    /// way, and what can go wrong.
    private var reading: some View {
        VStack(alignment: .leading, spacing: Metrics.l) {
            VStack(alignment: .leading, spacing: Metrics.xs) {
                PlanPartLabel("What happens")
                PlanStoryText(runs: story.story)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
            }
            if let bar = story.bar {
                PlanMonthBarView(bar: bar, maximum: barMaximum)
                    .frame(maxWidth: 440, alignment: .leading)
            }
            if !milestones.isEmpty {
                VStack(alignment: .leading, spacing: Metrics.xs) {
                    PlanPartLabel("Along the way, typically")
                    ForEach(Array(milestones.prefix(Self.shownMilestones))) { item in
                        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                            Image(systemName: "flag")
                                .foregroundStyle(Palette.accent)
                                .accessibilityHidden(true)
                            AmountSentenceText(milestoneText.name(item.milestone))
                                .foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: Metrics.s)
                            Text(PlanMilestoneText.when(item.date))
                                .monospacedDigit()
                                .foregroundStyle(Palette.secondaryInk)
                                .privacySensitiveInFeedback()
                        }
                        .font(.subheadline)
                        .accessibilityElement(children: .combine)
                    }
                    if milestones.count > Self.shownMilestones {
                        Text("And \(milestones.count - Self.shownMilestones) more ahead.")
                            .font(.footnote)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                }
            }
            if !story.risks.isEmpty {
                VStack(alignment: .leading, spacing: Metrics.xs) {
                    PlanPartLabel("What can go wrong")
                    ForEach(story.risks, id: \.self) { risk in
                        Label {
                            Text(risk)
                                .fixedSize(horizontal: false, vertical: true)
                                .privacySensitiveInFeedback()
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Palette.orangeStroke)
                        }
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink)
                    }
                }
            }
        }
    }

    /// Every input that starts in the chapter, once; what carries on into
    /// it; and *Add to this chapter*.
    private var settings: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                Text("Settings")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Metrics.s)
                Text("A month, in \(PlanMoney.todaysMoney(words.currency))")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
            }
            let rows = PlanChapterSettings.rows(for: chapter.items, model: model, issues: issues, words: words)
            if rows.isEmpty {
                Text("Nothing starts in this chapter.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
            } else {
                PlanSettingsList(rows: rows, plan: $plan, model: model, canEdit: canEdit, onSheet: onOpen,
                                 onUsePlanAge: onUsePlanAge)
            }
            if let continuing = model.continuing(in: chapter) {
                Text(continuing)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .privacySensitiveInFeedback()
            }
            PlanChapterAddMenu(chapter: chapter, model: model, plan: plan, editing: $editing)
                .disabled(!canEdit)
        }
    }
}

// MARK: - Assumptions

/// Under the chapters (UI.md, "Plan"): *Assumptions…*, the sheet with what
/// every chapter shares, *Export Calculations…* and the disclaimer.
struct PlanAssumptionsFooter: View {
    var onShowAll: () -> Void = {}
    var onExport: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            HStack(spacing: Metrics.l) {
                Button("Assumptions…", action: onShowAll)
                    .buttonStyle(.borderless)
                if let onExport {
                    Button("Export Calculations…", action: onExport)
                        .buttonStyle(.borderless)
                }
            }
            Text(AboutText.disclaimer)
                .font(.footnote)
                .foregroundStyle(Palette.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview("Plan · iPhone") {
    PlanPreviewHost(model: AppModel.preview()) { session in
        PlanTimelineView(session: session, showsTargetMix: .constant(false), onWhatIf: {}, onShowProgress: {},
                         onExport: {})
            .environment(\.pageLayout, PageLayout())
    }
}

#Preview("Plan · Mac") {
    PlanPreviewHost(model: AppModel.preview()) { session in
        PlanTimelineView(session: session, showsTargetMix: .constant(false), onShowProgress: {}, onExport: {})
            .environment(\.pageLayout, PageLayout(isWide: true))
            .frame(width: 1_100, height: 1_000)
    }
}
