import Model
import Planner
import SwiftUI

/// The plan (UI.md, "Plan"): the answer; your life as a strip of chapters
/// with one graph running through them; the chosen chapter in words below,
/// with its values to change where they read; what every chapter assumes;
/// and, folded away, the charts behind the answer.
///
/// Nothing runs on its own (UI.md, "Calculating"): before the first
/// calculation the answer recorded at the last check-in shows with
/// *Calculate*, and the strip has its chapters without the money; when the
/// plan or the library changed, an *Out of date* banner offers *Recalculate*.
struct PlanTimelineView: View {
    let session: PlanSession
    /// The sidebar layout (Mac, iPad): wider cards, and a chapter's inputs
    /// beside its words.
    var isWide = false
    /// Opens the What-if sheet (iPhone).
    var onWhatIf: (() -> Void)?
    /// Shows Progress.
    var onShowProgress: (() -> Void)?
    /// Export Calculations…
    var onExport: (() -> Void)?

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale
    @State private var editing: PlanEditTarget?
    @State private var showsTargetMix = false
    @State private var showsAssumptions = false
    @State private var showsMoreCharts = false

    private var gutter: CGFloat { isWide ? Metrics.xl : Metrics.l }

    private var milestoneText: PlanMilestoneText {
        PlanMilestoneText(currency: session.currency, hidesAmounts: hidesAmounts, locale: locale)
    }

    var body: some View {
        @Bindable var session = session
        // Without the progress: only the progress card follows every update.
        let state = session.stateWithoutProgress
        let milestones = session.plan.map {
            PlanMilestones(plan: $0, library: library.library, valuator: library.valuator, asOf: library.asOfDate,
                           results: state.results)
        }
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.l) {
                VStack(alignment: .leading, spacing: Metrics.m) {
                    PlanResultsBanners(session: session)
                    if state.isRunning {
                        PlanRunProgressCard(session: session)
                    } else {
                        PlanOutOfDateBanner(state: state) { session.perform($0) }
                    }
                    headline(state, milestones: milestones)
                }
                .padding(.horizontal, gutter)
                if let plan = session.plan {
                    chapters(plan, binding: $session.editablePlan, state: state, milestones: milestones)
                    PlanAssumptionsFooter(plan: plan, words: words, onOpen: show,
                                          onShowAll: { showsAssumptions = true }, onExport: onExport,
                                          binding: $session.editablePlan)
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
            PlanTargetMixSheet(plan: $session.editablePlan)
        }
        .sheet(isPresented: $showsAssumptions) {
            PlanAlwaysSheet(session: session)
        }
        .onDisappear { session.saveNow() }
    }

    private var words: PlanWords {
        PlanWords(currency: session.currency, hidesAmounts: hidesAmounts, locale: locale)
    }

    // MARK: The answer

    @ViewBuilder
    private func headline(_ state: PlanResultsState, milestones: PlanMilestones?) -> some View {
        if let results = state.results {
            PlanTimelineHeadline(session: session, results: results, isWide: isWide, progress: progress,
                                 milestones: milestones, milestoneText: milestoneText,
                                 onShowProgress: onShowProgress, onWhatIf: onWhatIf)
                .opacity(state.isRunning ? 0.5 : 1)
        } else if !state.isRunning {
            PlanCalculatePrompt(state: state, runs: session.plan?.simulation.effectiveRuns ?? 2_000,
                                isAvailable: plans.isAvailable) {
                session.calculate()
            }
        }
    }

    /// Where the latest check-in stands against its year's baseline.
    private var progress: (position: PlanBaselineComparison.Position, currency: CurrencyCode)? {
        PlanProgressYear.latestPosition(for: session.planID, library: library.library, valuator: library.valuator,
                                        asOf: library.asOfDate)
    }

    // MARK: The chapters

    @ViewBuilder
    private func chapters(_ plan: PlanDocument, binding: Binding<PlanDocument>, state: PlanResultsState,
                          milestones: PlanMilestones?) -> some View {
        let issues = session.inputIssues
        PlanUnplacedIssues(issues: issues, plan: plan)
            .padding(.horizontal, gutter)
        if let model = session.chapters, let birthDate = library.settings.person?.birthDate {
            let timeline = PlanTimeline(model: model, results: state.results, birthDate: birthDate,
                                        currency: session.currency, milestones: milestones?.ahead ?? [],
                                        hidesAmounts: hidesAmounts, locale: locale)
            if model.chapters.chapters.isEmpty {
                PlanNoChapters(plan: binding)
                    .padding(.horizontal, gutter)
            } else {
                let selected = min(session.selectedChapter(in: model) ?? 0, model.chapters.chapters.count - 1)
                let selection = Binding<Int>(get: { selected },
                                             set: { session.selectChapter($0, in: model) })
                stripHeader(count: model.chapters.chapters.count, selection: selection)
                    .padding(.horizontal, gutter)
                PlanChapterStrip(timeline: timeline, selection: selection, pointsPerYear: isWide ? 26 : 22,
                                 cardHeight: 340, inset: gutter)
                    .opacity(state.dimsResults ? 0.7 : 1)
                PlanChapterDetails(
                    model: model, index: selected,
                    story: PlanChapterStory(chapterAt: selected, in: model, results: state.results, words: words),
                    barMaximum: barMaximum(model, results: state.results), plan: binding,
                    summaries: PlanInputSummaries(plan: plan, library: library.library, currency: session.currency,
                                                  hidesAmounts: hidesAmounts, locale: locale),
                    issues: issues, isWide: isWide, canEdit: session.canEdit, editing: $editing,
                    milestones: timeline.cards.indices.contains(selected) ? timeline.cards[selected].milestones : [],
                    milestoneText: milestoneText,
                    onOpen: show, onSelect: { selection.wrappedValue = $0 },
                    onUsePlanAge: { session.selectFocus(nil) })
                    .padding(.horizontal, gutter)
            }
            if !model.chapters.outside.isEmpty {
                PlanOutsideCard(model: model, plan: binding,
                                summaries: PlanInputSummaries(plan: plan, library: library.library,
                                                              currency: session.currency, hidesAmounts: hidesAmounts,
                                                              locale: locale),
                                issues: issues, editing: $editing, onShowTargetMix: { showsTargetMix = true })
                    .padding(.horizontal, gutter)
            }
        } else {
            PlanChaptersNeedBirthDate()
                .padding(.horizontal, gutter)
        }
    }

    /// "Your life in 6 chapters", with the arrows on the Mac.
    private func stripHeader(count: Int, selection: Binding<Int>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(PlanTimelineText.chapters(count))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(isWide ? "Scroll sideways, or use the arrows."
                            : "Scroll sideways through your life; tap a chapter.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
            }
            Spacer(minLength: Metrics.s)
            if isWide {
                PlanStepButtons(index: selection.wrappedValue, count: count, today: 0) { selection.wrappedValue = $0 }
            }
        }
    }

    /// The largest month among the chapters, so their bars compare.
    private func barMaximum(_ model: PlanChaptersModel, results: PlanResults?) -> Double {
        model.chapters.chapters.indices
            .compactMap { PlanChapterStory.bar(model.chapters.chapters[$0], model: model, results: results,
                                               words: words)?.total }
            .max() ?? 0
    }

    /// Opens what a value names: an item's sheet, or the target mix's.
    private func show(_ token: PlanToken) {
        guard let plan = session.plan else { return }
        switch token {
        case .work(let index) where plan.work.indices.contains(index):
            editing = .work(index: index, phase: plan.work[index])
        case .pension(let index) where plan.pensions.indices.contains(index):
            editing = .pension(index: index, pension: plan.pensions[index])
        case .contribution(let index) where plan.contributions.indices.contains(index):
            editing = .contribution(index: index, contribution: plan.contributions[index])
        case .event(let index) where plan.events.indices.contains(index):
            editing = .event(index: index, event: plan.events[index])
        case .targetMix:
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
                    PlanFanCard(session: session, results: results)
                    if isWide {
                        EqualColumns(spacing: Metrics.l) {
                            PlanSuccessCard(session: session, results: results)
                            PlanIncomeCard(results: results)
                        }
                        EqualColumns(spacing: Metrics.l) {
                            VStack(spacing: Metrics.l) {
                                PlanFailureCard(results: results)
                                PlanFlexibleSpendingCard(results: results)
                            }
                            VStack(spacing: Metrics.l) {
                                PlanKeyNumbersCard(results: results)
                                PlanLibraryCard(results: results)
                            }
                        }
                    } else {
                        PlanSuccessCard(session: session, results: results)
                        PlanIncomeCard(results: results)
                        PlanFailureCard(results: results)
                        PlanFlexibleSpendingCard(results: results)
                        PlanKeyNumbersCard(results: results)
                        PlanLibraryCard(results: results)
                    }
                }
                .padding(.top, Metrics.s)
                .environment(\.baseCurrency, session.currency(of: results))
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("More charts")
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                    Text("Your money over time, chance by retirement age, income and taxes, when it fails, key numbers.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
        }
    }
}

// MARK: - The answer

/// "Not yet. Stop at 54, in March 2042.", the futures that last as ten
/// dots, and where you stand against this year's baseline, which opens
/// Progress. On iPhone a card, with What if… under it.
struct PlanTimelineHeadline: View {
    let session: PlanSession
    let results: PlanResults
    var isWide = false
    var progress: (position: PlanBaselineComparison.Position, currency: CurrencyCode)?
    var milestones: PlanMilestones?
    var milestoneText: PlanMilestoneText?
    var onShowProgress: (() -> Void)?
    var onWhatIf: (() -> Void)?

    @Environment(\.locale) private var locale

    private var focusAge: Int? { results.details?.focus.age ?? session.shownFocusAge }

    private var success: Double? {
        if let success = results.details?.focus.success { return success }
        guard let focusAge else { return results.headline.successAtTarget }
        return results.successByAge.first { $0.age == focusAge }?.success ?? results.headline.successAtTarget
    }

    private var endAge: Int { results.details?.endAge ?? session.plan?.effectiveEndAge ?? 95 }

    var body: some View {
        let title = PlanTimelineText.headline(results.headline, locale: locale)
        if isWide {
            HStack(alignment: .top, spacing: Metrics.l) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    lasting
                    nextMilestone
                    PlanRunStatus(session: session, results: results)
                }
                Spacer(minLength: Metrics.l)
                VStack(alignment: .trailing, spacing: Metrics.s) {
                    progressPill
                    if let onWhatIf {
                        whatIfButton(onWhatIf)
                    }
                }
            }
        } else {
            Card {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Can I retire yet?")
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                    Text(title)
                        .font(.title.weight(.bold))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                lasting
                nextMilestone
                HStack(spacing: Metrics.s) {
                    if let onWhatIf {
                        whatIfButton(onWhatIf)
                    }
                    Spacer(minLength: 0)
                    progressPill
                }
                PlanRunStatus(session: session, results: results)
            }
        }
    }

    @ViewBuilder
    private var lasting: some View {
        if let success {
            HStack(alignment: .center, spacing: Metrics.s) {
                PlanTenthsView(filled: PlanTimelineText.tenths(success))
                Text(PlanTimelineText.lasting(success, endAge: endAge, stoppingAt: focusAge))
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "Next milestone: 400.000 € · 88% there", with its bar; it opens Progress.
    @ViewBuilder
    private var nextMilestone: some View {
        if let milestones, let next = milestones.next, let milestoneText {
            Button {
                onShowProgress?()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Metrics.xs) {
                        Image(systemName: "flag")
                            .accessibilityHidden(true)
                        Text("Next milestone: \(milestoneText.name(next.milestone)) · \(milestoneText.progress(next))")
                            .fixedSize(horizontal: false, vertical: true)
                        if onShowProgress != nil {
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .accessibilityHidden(true)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.secondaryInk)
                    PlanMilestoneBar(progress: next.progress)
                        .frame(maxWidth: 280)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onShowProgress == nil)
            .accessibilityHint(Text("Shows your milestones in Progress"))
        }
    }

    private func whatIfButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(session.hasWhatIf ? "What if… (changed)" : "What if…", systemImage: "slider.horizontal.3")
        }
        .buttonStyle(.bordered)
    }

    /// "Ahead of plan by 18.400 € ›".
    @ViewBuilder
    private var progressPill: some View {
        if let progress, let onShowProgress {
            let ahead = progress.position.gap >= 0
            Button(action: onShowProgress) {
                HStack(spacing: 4) {
                    Text(ahead ? "Ahead of plan by" : "Behind plan by")
                    AmountText(abs(progress.position.gap), currency: progress.currency, tabular: false)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ahead ? Palette.positive : Palette.orangeStroke)
                .padding(.horizontal, Metrics.m)
                .padding(.vertical, 6)
                .background((ahead ? Palette.positive : Palette.orange).opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Shows your progress"))
        }
    }
}

/// ‹ › buttons that step through `count` items, and *Today* when one of
/// them is today's.
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
            .disabled(index <= 0)
            Button {
                select(index + 1)
            } label: {
                Label("Later", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
            }
            .disabled(index >= count - 1)
        }
        .buttonStyle(.bordered)
    }
}

// MARK: - A chapter in words

/// The chosen chapter (UI.md, "Plan"): its number, name and span, its
/// story with the values to change where they read, a month's money as a
/// bar, what it assumes, and everything in it, each input editable, with
/// *Add to this chapter*. Beside the words on the Mac, folded under them on
/// iPhone.
struct PlanChapterDetails: View {
    let model: PlanChaptersModel
    let index: Int
    let story: PlanChapterStory
    /// The largest month among the chapters, for the bar.
    let barMaximum: Double
    @Binding var plan: PlanDocument
    let summaries: PlanInputSummaries
    let issues: PlanInputIssues
    var isWide = false
    var canEdit = true
    @Binding var editing: PlanEditTarget?
    /// The milestones the median future reaches in the chapter.
    var milestones: [ProjectedMilestone] = []
    var milestoneText: PlanMilestoneText?
    /// Opens an item's sheet, or the target mix's.
    var onOpen: (PlanToken) -> Void = { _ in }
    var onSelect: (Int) -> Void = { _ in }
    var onUsePlanAge: () -> Void = {}

    @State private var showsInputs = false

    private var chapter: PlanChapter { model.chapters.chapters[index] }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: Metrics.m) {
            header
            if isWide {
                HStack(alignment: .top, spacing: Metrics.xl) {
                    words
                        .frame(maxWidth: .infinity, alignment: .leading)
                    inputs
                        .frame(width: 360, alignment: .leading)
                }
            } else {
                words
                DisclosureGroup(isExpanded: $showsInputs) {
                    inputs
                        .padding(.top, Metrics.s)
                } label: {
                    Text("Everything in this chapter")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(Metrics.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: shape)
        .overlay { shape.strokeBorder(Palette.border, lineWidth: 1) }
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
            Spacer(minLength: Metrics.s)
            if !isWide {
                PlanStepButtons(index: index, count: model.chapters.chapters.count, select: onSelect)
            }
        }
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            PlanEditableStory(runs: story.story, canEdit: canEdit, onSheet: onOpen) { token in
                PlanTokenEditor(token: token, plan: $plan, model: model, onOpen: onOpen)
            }
            .font(.body)
            .foregroundStyle(Palette.ink)
            if let milestoneText, !milestones.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
                    Image(systemName: "flag")
                        .foregroundStyle(Palette.accent)
                        .accessibilityHidden(true)
                    Text(Self.alongTheWay(milestones, text: milestoneText))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
            }
            if let bar = story.bar {
                PlanMonthBarView(bar: bar, maximum: barMaximum)
            }
            PlanEditableStory(runs: story.assumes, canEdit: canEdit, onSheet: onOpen) { token in
                PlanTokenEditor(token: token, plan: $plan, model: model, onOpen: onOpen)
            }
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
        }
    }

    private var inputs: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            if isWide {
                Text("In this chapter")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.secondaryInk)
            }
            ForEach(chapter.items, id: \.self) { item in
                PlanChapterItemRow(item: item, model: model, plan: $plan, summaries: summaries, issues: issues,
                                   editing: $editing, onShowTargetMix: { onOpen(.targetMix) },
                                   onUsePlanAge: onUsePlanAge)
            }
            if let continuing = model.continuing(in: chapter) {
                Text(continuing)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PlanChapterAddMenu(chapter: chapter, model: model, plan: $plan, editing: $editing)
        }
        .disabled(!canEdit)
    }

    /// "Along the way, typically: 400.000 € in mid 2027 and 10 years of
    /// spending in early 2028."
    static func alongTheWay(_ milestones: [ProjectedMilestone], text: PlanMilestoneText) -> String {
        let shown = milestones.prefix(3).map { "\(text.name($0.milestone)) in \(PlanMilestoneText.when($0.date))" }
        let more = milestones.count > 3 ? ", and \(milestones.count - 3) more" : ""
        let list = shown.count > 1 && more.isEmpty
            ? shown.dropLast().joined(separator: ", ") + " and " + (shown.last ?? "")
            : shown.joined(separator: ", ") + more
        return "Along the way, typically: \(list)."
    }

}

// MARK: - What every chapter assumes

/// The assumptions every chapter shares, in words with their values to
/// change: returns, inflation, taxes and when a plan works; then *All
/// assumptions…* and *Export Calculations…*.
struct PlanAssumptionsFooter: View {
    let plan: PlanDocument
    let words: PlanWords
    var onOpen: (PlanToken) -> Void = { _ in }
    var onShowAll: () -> Void = {}
    var onExport: (() -> Void)?
    @Binding var binding: PlanDocument

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: Metrics.s) {
            Text("Assumptions")
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            PlanEditableStory(runs: PlanChapterStory.shared(plan: plan, words: words), onSheet: onOpen) { token in
                PlanTokenEditor(token: token, plan: $binding, onOpen: onOpen)
            }
            .font(.subheadline)
            .foregroundStyle(Palette.ink)
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Metrics.m) {
                    disclaimer
                    Spacer(minLength: Metrics.s)
                    buttons
                }
                VStack(alignment: .leading, spacing: Metrics.s) {
                    disclaimer
                    HStack(spacing: Metrics.m) { buttons }
                }
            }
        }
        .padding(Metrics.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: shape)
        .overlay { shape.strokeBorder(Palette.border, lineWidth: 1) }
    }

    private var disclaimer: some View {
        Text(AboutText.disclaimer)
            .font(.footnote)
            .foregroundStyle(Palette.mutedInk)
    }

    @ViewBuilder
    private var buttons: some View {
        Button("All assumptions…", action: onShowAll)
            .buttonStyle(.borderless)
        if let onExport {
            Button("Export Calculations…", action: onExport)
                .buttonStyle(.borderless)
        }
    }
}

#Preview("Plan · iPhone") {
    PlanPreviewHost(model: AppModel.preview(planEngine: PlanPreviewEngine())) { session in
        PlanTimelineView(session: session, onWhatIf: {}, onShowProgress: {}, onExport: {})
    }
}

#Preview("Plan · Mac") {
    PlanPreviewHost(model: AppModel.preview(planEngine: PlanPreviewEngine())) { session in
        PlanTimelineView(session: session, isWide: true, onShowProgress: {}, onExport: {})
            .frame(width: 1_100, height: 1_000)
    }
}
