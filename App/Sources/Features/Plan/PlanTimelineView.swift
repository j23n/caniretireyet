import Model
import Planner
import SwiftUI

/// The plan (UI.md, "Plan"): your date, the levers that move it, and
/// below them your life as chapters, each with its settings, where the
/// plan changes; then the key numbers and what every chapter assumes. On
/// the Mac and iPad the chance by retirement age sits beside the levers.
///
/// The plan calculates on its own: when it or the library changes, its
/// results run again in the background, and the levers' what-if runs as
/// they come to rest. Recalculate stays a Plan menu command (⌘R).
struct PlanTimelineView: View {
    let session: PlanSession
    /// The Target mix sheet, which the plan's screen opens too (``PlanRoute``).
    @Binding var showsTargetMix: Bool
    /// Export Calculations…
    var onExport: (() -> Void)?

    @Environment(\.pageLayout) private var layout
    @Environment(\.locale) private var locale
    @Environment(LibraryStore.self) private var library
    @State private var editing: PlanEditTarget?
    @State private var showsAssumptions = false

    private var gutter: CGFloat { layout.gutter }

    private var milestoneText: PlanMilestoneText {
        PlanMilestoneText(currency: session.currency, locale: locale)
    }

    /// What decides whether the plan needs calculating.
    private struct AutoRun: Equatable {
        var revision: Int
        var upToDate: Bool
        var running: Bool
    }

    var body: some View {
        @Bindable var session = session
        // Without the progress: only the progress view follows every update.
        let state = session.state
        let derived = session.derived(locale: locale)
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.l) {
                VStack(alignment: .leading, spacing: Metrics.m) {
                    PlanResultsBanners(session: session)
                    PlanDateHeader(session: session)
                    if session.runError != nil, !state.isRunning {
                        Button("Try Again") { session.calculate() }
                            .buttonStyle(.bordered)
                            .disabled(!session.canEdit)
                    }
                    PlanResultWarnings(session: session)
                }
                .padding(.horizontal, gutter)
                if session.plan != nil {
                    if layout.isRoomy, let results = state.results {
                        EqualColumns(spacing: Metrics.l) {
                            PlanLeversCard(session: session)
                            PlanSuccessCard(session: session, results: results)
                        }
                        .padding(.horizontal, gutter)
                    } else {
                        PlanLeversCard(session: session)
                            .padding(.horizontal, gutter)
                    }
                    chapters($session.editablePlan, state: state, derived: derived)
                    if let results = state.results {
                        PlanKeyNumbersCard(results: results)
                            .padding(.horizontal, gutter)
                    }
                    PlanAssumptionsFooter(onShowAll: { showsAssumptions = true }, onExport: onExport)
                        .padding(.horizontal, gutter)
                }
            }
            .padding(.vertical, gutter)
            .frame(maxWidth: layout.isWide ? Metrics.wideReadableWidth : .infinity, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.page)
        .task(id: AutoRun(revision: library.revision, upToDate: session.baseIsUpToDate, running: state.isRunning)) {
            // A moment's pause, so a burst of edits runs once.
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            session.calculateIfNeeded()
        }
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

    // MARK: The chapters

    /// "Your life in four chapters": a row each; the chosen one's words
    /// and settings below the list.
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
                PlanChapterList(timeline: timeline, model: model, selection: selection)
                    .padding(.horizontal, gutter)
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
}

// MARK: - The chapters

/// The chapters as a list (UI.md, "Plan"): each one's number, name and
/// span, the chosen one marked; choosing one shows its words and settings
/// under the list.
struct PlanChapterList: View {
    let timeline: PlanTimeline
    let model: PlanChaptersModel
    @Binding var selection: Int

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(timeline.cards) { card in
                    if card.index > 0 {
                        Divider()
                    }
                    Button {
                        withAnimation(.snappy) { selection = card.index }
                    } label: {
                        row(card)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(card.index == selection ? .isSelected : [])
                }
            }
        } header: {
            SectionHeader(PlanTimelineText.chapters(timeline.cards.count))
        }
    }

    private func row(_ card: PlanTimeline.Card) -> some View {
        let isSelected = card.index == selection
        return HStack(alignment: .center, spacing: Metrics.m) {
            PlanChapterBadge(number: card.index + 1, style: card.style, isSelected: isSelected)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(card.span)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondaryInk)
            }
            .privacySensitiveInFeedback()
            Spacer(minLength: Metrics.s)
            Image(systemName: isSelected ? "chevron.down" : "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isSelected ? Palette.accent : Palette.mutedInk)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Metrics.s)
        .contentShape(Rectangle())
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
/// keyboard, unless `hasShortcuts` is off), and *Today* when one of them
/// is today's.
struct PlanStepButtons: View {
    let index: Int
    let count: Int
    /// The item that holds today: *Today* selects it.
    var today: Int?
    /// Whether ⌘[ and ⌘] step too: off on a page that stays under what it
    /// opens, where they would step it unseen.
    var hasShortcuts = true
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
            .keyboardShortcut(hasShortcuts ? KeyboardShortcut("[", modifiers: .command) : nil)
            .help(hasShortcuts ? "Earlier (⌘[)" : "Earlier")
            .disabled(index <= 0)
            Button {
                select(index + 1)
            } label: {
                Label("Later", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
            }
            .keyboardShortcut(hasShortcuts ? KeyboardShortcut("]", modifiers: .command) : nil)
            .help(hasShortcuts ? "Later (⌘])" : "Later")
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
        PlanTimelineView(session: session, showsTargetMix: .constant(false), onExport: {})
            .environment(\.pageLayout, PageLayout())
    }
}

#Preview("Plan · Mac") {
    PlanPreviewHost(model: AppModel.preview()) { session in
        PlanTimelineView(session: session, showsTargetMix: .constant(false), onExport: {})
            .environment(\.pageLayout, PageLayout(isWide: true))
            .frame(width: 1_100, height: 1_000)
    }
}
