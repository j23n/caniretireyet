import Model
import Planner
import SwiftUI

/// The plan (UI.md, "Plan"). On iPhone: the header card (the plan menu,
/// your date and *Levers*, which shows the levers under it), the key
/// numbers as tiles (``PlanResultTiles``), your chapters on one card, each
/// opening in a sheet, what changes along the way with *Add*, then
/// *Assumptions*. On the Mac and iPad the same page, with a header row and
/// its ••• menu in place of the header card, the levers beside your date,
/// and the assumptions in one sentence.
///
/// The plan calculates on its own: when it or the library changes, its
/// results run again in the background, and the levers' what-if runs as
/// they come to rest. Recalculate stays a Plan menu command (⌘R).
struct PlanTimelineView: View {
    let session: PlanSession
    /// The Target mix sheet, which the plan's screen opens too (``PlanRoute``).
    @Binding var showsTargetMix: Bool
    /// What the plan menu and the header's buttons do.
    var actions = PlanActions()

    @Environment(\.pageLayout) private var layout
    @Environment(\.locale) private var locale
    @Environment(LibraryStore.self) private var library
    @State private var editing: PlanEditTarget?
    @State private var showsAssumptions = false
    @State private var showsLevers = false
    @State private var showsChapter = false

    private var gutter: CGFloat { layout.gutter }

    private var words: PlanWords {
        PlanWords(currency: session.currency, locale: locale)
    }

    /// What decides whether the plan needs calculating.
    private struct AutoRun: Equatable {
        var revision: Int
        var upToDate: Bool
        var running: Bool
    }

    var body: some View {
        // Without the progress: only the progress view follows every update.
        let state = session.state
        let derived = session.derived(locale: locale)
        ScrollView {
            Group {
                if layout.isWide {
                    wide(state: state, derived: derived)
                } else {
                    narrow(state: state, derived: derived)
                }
            }
            .padding(.horizontal, gutter)
            .padding(.vertical, layout.isWide ? Metrics.l : Metrics.s)
            .frame(maxWidth: layout.isWide ? Metrics.wideReadableWidth : Metrics.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.page)
        .task(id: AutoRun(revision: library.revision, upToDate: session.baseIsUpToDate, running: state.isRunning)) {
            // A moment's pause, so a burst of edits runs once.
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            session.calculateIfNeeded()
        }
        // The levers show while they've moved, on iPhone too.
        .task(id: session.hasWhatIf) {
            if session.hasWhatIf { showsLevers = true }
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
        .sheet(isPresented: $showsChapter) {
            PlanChapterSheet(session: session)
        }
        .onDisappear { session.saveNow() }
    }

    // MARK: iPhone

    @ViewBuilder
    private func narrow(state: PlanResultsState, derived: PlanDerived) -> some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            PlanResultsBanners(session: session)
            PlanHeaderCard(session: session, actions: actions, showsLevers: $showsLevers)
            tryAgain(state: state)
            if showsLevers, session.plan != nil {
                PlanLeversCard(session: session)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            PlanResultWarnings(session: session)
            if session.plan != nil {
                if let results = state.results {
                    PlanResultTiles(session: session, results: results, milestones: derived.milestones)
                }
                chapterRows(state: state, derived: derived)
                sectionTitle("Assumptions")
                PlanAssumptionRows(session: session, onAssumptions: { showsAssumptions = true },
                                   onTargetMix: { showsTargetMix = true })
                disclaimer
            }
        }
    }

    /// "Your life in chapters" and a row per chapter, which opens it in a
    /// sheet; then *What changes along the way*, the inputs the chapters
    /// follow from, with *Add*.
    @ViewBuilder
    private func chapterRows(state: PlanResultsState, derived: PlanDerived) -> some View {
        @Bindable var session = session
        PlanUnplacedIssues(issues: session.inputIssues)
        if let model = derived.chapters, derived.timeline != nil {
            if model.chapters.chapters.isEmpty {
                PlanNoChapters(plan: $session.editablePlan)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    sectionTitle("Your life in chapters")
                    Text("They follow from your income, your pensions and the age you stop.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Metrics.xs)
                }
                let lines = PlanChapterLine.lines(model: model, results: state.results, words: words)
                PlanChapterRows(lines: lines) { index in
                    self.session.selectChapter(index, in: model)
                    showsChapter = true
                }
                changes(model)
            }
            outside(model)
        } else {
            PlanChaptersNeedBirthDate()
        }
    }

    /// *What changes along the way*: the work, pensions, other income,
    /// contributions, one-offs and later spending the chapters follow from,
    /// in the order the chapters meet them, each opening its sheet; *Add*
    /// for another. The chapters redraw around them.
    @ViewBuilder
    private func changes(_ model: PlanChaptersModel) -> some View {
        @Bindable var session = session
        let items = model.chapters.chapters.flatMap(\.items).filter(Self.isChange)
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            sectionTitle("What changes along the way")
            Spacer(minLength: Metrics.s)
            PlanAddMenu(model: model, plan: session.editablePlan, editing: $editing) {
                Text("Add")
                    .font(.body)
                    .foregroundStyle(Palette.accent)
                    .padding(.vertical, Metrics.s)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .disabled(!session.canEdit)
            .padding(.horizontal, Metrics.xs)
        }
        let rows = PlanChapterSettings.rows(for: items, model: model, issues: session.inputIssues, words: words,
                                            namesWork: true)
        if !rows.isEmpty {
            PlanSettingsList(rows: rows, plan: $session.editablePlan, model: model, canEdit: session.canEdit,
                             onSheet: show)
        }
        Text("Add income, a pension, a change in spending, saving into an account or a one-off. The chapters "
             + "redraw around them.")
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Metrics.xs)
    }

    /// Whether an input changes the plan along the way: work, pensions,
    /// other income, contributions, one-offs and later spending; not the
    /// spending, the target mix, when work stops or the end, which every
    /// plan has.
    private static func isChange(_ item: PlanChapter.Item) -> Bool {
        switch item {
        case .work, .pension, .income, .contribution, .event, .spendingPhase: true
        case .retirement, .workingSpending, .retiredSpending, .targetMix, .targetMixStep, .end: false
        }
    }

    // MARK: Mac and iPad

    @ViewBuilder
    private func wide(state: PlanResultsState, derived: PlanDerived) -> some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            PlanWideHeader(session: session, actions: actions, onAssumptions: { showsAssumptions = true },
                           onTargetMix: { showsTargetMix = true },
                           onFlexibleSpending: { editing = .flexibleSpending(session.editablePlan.spending) })
            PlanResultsBanners(session: session)
            tryAgain(state: state)
            PlanResultWarnings(session: session)
            if session.plan != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Metrics.m) {
                        PlanAnswerCard(session: session)
                            .frame(minWidth: Self.leversWidth)
                        PlanLeversCard(session: session)
                            .frame(width: Self.leversWidth)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: Metrics.m) {
                        PlanAnswerCard(session: session)
                        PlanLeversCard(session: session)
                    }
                }
                if let results = state.results {
                    PlanResultTiles(session: session, results: results, milestones: derived.milestones)
                }
                chapterRows(state: state, derived: derived)
                assumptionsLine
                disclaimer
            }
        }
    }

    /// The levers' width beside the answer, and the narrowest the answer
    /// gets beside them before the levers go under it.
    private static let leversWidth: CGFloat = 290

    /// What every chapter assumes, in one sentence, with *Assumptions…*.
    @ViewBuilder
    private var assumptionsLine: some View {
        if let plan = session.plan {
            let summaries = PlanInputSummaries(plan: plan, library: library.library, currency: session.currency,
                                               locale: locale)
            let sentence = summaries.rows.map { AmountSentence("\($0.label) ") + $0.value }.joined(separator: " · ")
            HStack(alignment: .firstTextBaseline, spacing: Metrics.m) {
                AmountSentenceText(sentence)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Assumptions…") { showsAssumptions = true }
                    .buttonStyle(.bordered)
                    .fixedSize()
            }
            .padding(.horizontal, Metrics.xs)
            .padding(.top, Metrics.s)
        }
    }

    // MARK: Shared

    /// The inputs outside the plan's years, after the chapters.
    @ViewBuilder
    private func outside(_ model: PlanChaptersModel) -> some View {
        @Bindable var session = session
        if !model.chapters.outside.isEmpty {
            PlanOutsideCard(model: model, plan: $session.editablePlan, issues: session.inputIssues, words: words,
                            onOpen: show)
        }
    }

    /// *Try Again* after a failed run.
    @ViewBuilder
    private func tryAgain(state: PlanResultsState) -> some View {
        if session.runError != nil, !state.isRunning {
            Button("Try Again") { session.calculate() }
                .buttonStyle(.bordered)
                .disabled(!session.canEdit)
        }
    }

    /// A section's title on the page: "Your life in chapters", "Assumptions".
    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title2.weight(.bold))
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .padding(.horizontal, Metrics.xs)
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
    }

    private var disclaimer: some View {
        Text(AboutText.disclaimer)
            .font(.footnote)
            .foregroundStyle(Palette.mutedInk)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Metrics.xs)
            .padding(.top, Metrics.s)
    }

    /// Opens a setting's sheet: spending's, an item's, or the target mix's.
    private func show(_ sheet: PlanSettingSheet) {
        guard let plan = session.plan else { return }
        if sheet.isTargetMix {
            showsTargetMix = true
        } else {
            editing = PlanEditTarget(sheet, in: plan)
        }
    }
}

/// A strip's title ("Year by year"), how to move along it, and on the Mac
/// and iPad ‹ › beside them.
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

#Preview("Plan · iPhone") {
    PlanPreviewHost(model: AppModel.preview()) { session in
        PlanTimelineView(session: session, showsTargetMix: .constant(false))
            .environment(\.pageLayout, PageLayout())
    }
}

#Preview("Plan · Mac") {
    PlanPreviewHost(model: AppModel.preview()) { session in
        PlanTimelineView(session: session, showsTargetMix: .constant(false))
            .environment(\.pageLayout, PageLayout(isWide: true))
            .frame(width: 1_100, height: 1_000)
    }
}
