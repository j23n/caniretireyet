import Glance
import Model
import Planner
import SwiftUI

/// Ahead (UI.md, "Ahead"): the plan. On iPhone the title with the plan
/// menu and the eye, your last Monday on a card with the plan's chart to its end,
/// *What if…* and how far ahead of January's plan you are, which opens So
/// far; then the key numbers as tiles (``PlanResultTiles``) and *Your life
/// ahead*, the chapters and what changes along the way down a line, with
/// when you stop on it (``AheadLifeSection``). On the Mac and iPad a
/// header row, your date beside What if's levers, the chart on a card of
/// its own, your life ahead on the same line with what changes in a
/// chapter beside it, then the tiles.
///
/// What every chapter shares (*Assumptions…*, *Target Mix…*, *Flexible
/// Spending…*) is in the plan menu. The plan calculates on its own: when it
/// or the library changes, its results run again in the background, and
/// What if's levers run as they come to rest. Recalculate stays a Plan menu
/// command (⌘R).
struct AheadView: View {
    let session: PlanSession
    /// A sheet to open, from a route (``PlanRoute``): taken once, then cleared.
    @Binding var opening: PlanRoute.Sheet?
    /// What the plan menu does that the screen handles: New, Duplicate,
    /// Rename, Set as Main, Export Calculations, Delete.
    var actions = PlanActions()

    @Environment(\.pageLayout) private var layout
    @Environment(\.locale) private var locale
    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigation.self) private var navigation
    @State private var editing: PlanEditTarget?
    @State private var showsTargetMix = false
    @State private var showsAssumptions = false
    @State private var showsWhatIf = false
    @State private var showsChapter = false

    private var words: PlanWords {
        PlanWords(currency: session.currency, locale: locale)
    }

    /// The plan menu's actions, with the sheets this page opens.
    private var menuActions: PlanActions {
        var menu = actions
        menu.assumptions = { showsAssumptions = true }
        menu.targetMix = { showsTargetMix = true }
        menu.flexibleSpending = { editing = .flexibleSpending(session.editablePlan.spending) }
        return menu
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
            .padding(.horizontal, layout.gutter)
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
        .sheet(isPresented: $showsWhatIf) {
            PlanWhatIfSheet(session: session)
        }
        .onChange(of: opening, initial: true) { _, sheet in
            if let sheet { open(sheet) }
        }
        .onDisappear { session.saveNow() }
    }

    /// Opens a route's sheet, once.
    private func open(_ sheet: PlanRoute.Sheet) {
        opening = nil
        switch sheet {
        case .targetMix:
            showsTargetMix = true
        case .whatIf:
            // On the Mac and iPad the levers are on the page.
            if !layout.isWide { showsWhatIf = true }
        case .newEvent:
            if let plan = session.plan {
                editing = .event(index: plan.events.count,
                                 event: PlanEditing.newEvent(in: plan, asOf: library.asOfDate))
            }
        }
    }

    // MARK: iPhone

    @ViewBuilder
    private func narrow(state: PlanResultsState, derived: PlanDerived) -> some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            HStack(alignment: .center, spacing: Metrics.s) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.m) {
                    Text("Ahead")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: Metrics.s)
                    PlanMenu(session: session, actions: menuActions)
                }
                TitleHideAmountsButton()
            }
            .padding(.horizontal, Metrics.xs)
            .padding(.top, Metrics.s)
            PlanResultsBanners(session: session)
            tryAgain(state: state)
            if let plan = session.plan {
                AheadAnswerCard(session: session, plan: plan, showsChart: true,
                                onWhatIf: { showsWhatIf = true }, onSoFar: { navigation.showSoFar() })
                PlanResultWarnings(session: session)
                if let results = state.results {
                    PlanResultTiles(session: session, results: results, milestones: derived.milestones)
                }
                life(state: state, derived: derived, columns: false)
                disclaimer
            }
        }
    }

    // MARK: Mac and iPad

    @ViewBuilder
    private func wide(state: PlanResultsState, derived: PlanDerived) -> some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            header
            PlanResultsBanners(session: session)
            tryAgain(state: state)
            PlanResultWarnings(session: session)
            if let plan = session.plan {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Metrics.m) {
                        AheadAnswerCard(session: session, plan: plan, showsChart: false,
                                        onSoFar: { navigation.showSoFar() })
                            .frame(minWidth: Self.leversWidth)
                        PlanLeversCard(session: session)
                            .frame(width: Self.leversWidth)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: Metrics.m) {
                        AheadAnswerCard(session: session, plan: plan, showsChart: false,
                                        onSoFar: { navigation.showSoFar() })
                        PlanLeversCard(session: session)
                    }
                }
                chartCard(plan, state: state)
                life(state: state, derived: derived, columns: true)
                if let results = state.results {
                    PlanResultTiles(session: session, results: results, milestones: derived.milestones)
                }
                disclaimer
            }
        }
    }

    /// The levers' width beside the answer, and the narrowest the answer
    /// gets beside them before the levers go under it.
    private static let leversWidth: CGFloat = 320

    /// The header row on the Mac and iPad: "Ahead", the plan menu under
    /// it, and how the results shown were calculated.
    private var header: some View {
        HStack(alignment: .center, spacing: Metrics.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ahead")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: Metrics.s) {
                    PlanMenu(session: session, actions: menuActions)
                    Text(session.shownResults.map { PlanRunText.calculated($0, locale: locale) }
                         ?? "Not calculated yet")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Metrics.m)
        }
    }

    /// "Your money to 95", the legend beside it,
    /// and the chart, the plan as it is dashed under the levers once they
    /// moved.
    private func chartCard(_ plan: PlanDocument, state: PlanResultsState) -> some View {
        let compared = session.hasWhatIf && session.whatIfResults != nil ? session.baseResults : nil
        let endAge = state.results?.details.endAge ?? plan.effectiveEndAge
        return VStack(alignment: .leading, spacing: Metrics.m) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.m) {
                    chartTitle(endAge)
                    Spacer(minLength: Metrics.m)
                    DecadesLegend(compared: compared == nil ? nil : "As it is", changed: "With the levers")
                        .fixedSize()
                }
                VStack(alignment: .leading, spacing: Metrics.s) {
                    chartTitle(endAge)
                    DecadesLegend(compared: compared == nil ? nil : "As it is", changed: "With the levers")
                }
            }
            DecadesChart(plan: session.shownPlan ?? plan, results: state.results, compared: compared, today: .today(),
                         chartHeight: 380)
                .opacity(state.dimsResults ? Metrics.dimmedOpacity : 1)
        }
        .padding(Metrics.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func chartTitle(_ endAge: Int) -> some View {
        Text(verbatim: "Your money to \(endAge)")
            .font(.title3.weight(.bold))
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .privacySensitiveInFeedback()
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Shared

    /// *Your life ahead*, with the problems no chapter shows above it and
    /// the inputs outside the plan's years under it; without a birth date,
    /// what to add.
    @ViewBuilder
    private func life(state: PlanResultsState, derived: PlanDerived, columns: Bool) -> some View {
        @Bindable var session = session
        PlanUnplacedIssues(issues: session.inputIssues)
        if let model = derived.chapters, derived.timeline != nil {
            if model.chapters.chapters.isEmpty {
                PlanNoChapters(plan: $session.editablePlan)
            } else {
                AheadLifeSection(session: session, model: model, results: state.results, words: words,
                                 columns: columns, editing: $editing,
                                 onChapter: { index in
                                     self.session.selectChapter(index, in: model)
                                     showsChapter = true
                                 },
                                 onSheet: show,
                                 onTargetMix: { showsTargetMix = true })
                    .opacity(state.dimsResults ? Metrics.dimmedOpacity : 1)
            }
            if !model.chapters.outside.isEmpty {
                PlanOutsideCard(model: model, plan: $session.editablePlan, issues: session.inputIssues,
                                words: words, onOpen: show)
            }
        } else {
            PlanChaptersNeedBirthDate()
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

// MARK: - Your last Monday

/// Your last Monday on Ahead's card: "Your last Monday", the date and age
/// large, how sure ("In 9 of 10 futures your money lasts to 95."), how far
/// What if moved it once a lever has moved, and a calculation's progress.
/// On iPhone the plan's chart under it, then *What if…* and how far ahead
/// of January's plan you are ("21.572 € ahead ›"), which opens So far; on
/// the Mac and iPad, where the levers and the chart have cards of their
/// own, only the latter.
struct AheadAnswerCard: View {
    let session: PlanSession
    let plan: PlanDocument
    let showsChart: Bool
    /// Opens What if; `nil` where the levers are on the page.
    var onWhatIf: (() -> Void)?
    var onSoFar: () -> Void = {}

    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale

    var body: some View {
        let state = session.state
        let words = PlanAnswerWords(session: session, locale: locale)
        VStack(alignment: .leading, spacing: Metrics.m) {
            VStack(alignment: .leading, spacing: Metrics.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                    Text(session.hasWhatIf ? "Your last Monday, with the levers" : "Your last Monday")
                        .font(.subheadline)
                        .foregroundStyle(session.hasWhatIf ? Palette.accent : Palette.secondaryInk)
                        .lineLimit(1)
                    Spacer(minLength: Metrics.s)
                    if session.isRunningWhatIf {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Updating your date")
                    }
                    if let move = words.leverMove {
                        PlanMoveChip(move: move)
                    }
                }
                if let date = words.dateAndAge {
                    Text(verbatim: date)
                        .font(.title.weight(.bold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .opacity(words.dims ? Metrics.dimmedOpacity : 1)
                        .privacySensitiveInFeedback()
                        .accessibilityLabel(Text(verbatim: "\(date), in \(words.futures) futures"))
                    if let sentence = sentence(state.results) {
                        Text(verbatim: sentence)
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                            .privacySensitiveInFeedback()
                    }
                } else {
                    Text(words.placeholder)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let note = words.note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .privacySensitiveInFeedback()
                }
                if state.isRunning, !session.isRunningWhatIf, let progress = session.runProgress {
                    PlanRunProgressView(progress: progress, isCheckIn: session.isCheckInRun,
                                        onCancel: session.isCheckInRun ? nil : { session.cancel() })
                        .padding(.top, Metrics.xs)
                }
            }
            if showsChart {
                let compared = session.hasWhatIf && session.whatIfResults != nil ? session.baseResults : nil
                VStack(alignment: .leading, spacing: Metrics.s) {
                    if state.results != nil {
                        DecadesLegend(compared: compared == nil ? nil : "As it is", changed: "With the levers")
                    }
                    DecadesChart(plan: session.shownPlan ?? plan, results: state.results, compared: compared,
                                 today: .today(), chartHeight: 230)
                        .opacity(state.dimsResults ? Metrics.dimmedOpacity : 1)
                }
            }
            buttons
        }
        .padding(Metrics.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardSurface()
    }

    /// *What if…*, filled once a lever has moved, and how far ahead of
    /// January's plan you are. Only for the main plan, which So far follows.
    @ViewBuilder
    private var buttons: some View {
        let year = library.settings.mainPlan == session.planID ? session.progress.latestYear : nil
        let gap = year?.position?.gap
        if onWhatIf != nil || gap != nil {
            HStack(spacing: Metrics.s) {
                if let onWhatIf {
                    Button(action: onWhatIf) {
                        Text("What if…")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, Metrics.xs)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(session.hasWhatIf ? Palette.accent : Palette.accent.opacity(0.85))
                    .accessibilityHint("Shows the levers that move your date")
                }
                if let gap {
                    Button(action: onSoFar) {
                        AheadGapLabel(gap: gap, currency: session.currency,
                                      against: onWhatIf == nil ? year?.expectation(locale: locale) : nil)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Shows how you've been doing so far")
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// "In 9 of 10 futures your money lasts to 95."; on the Mac and iPad,
    /// how sure stopping at the plan's own age is too ("Stop at 60: 6 in
    /// 10.") when that isn't the earliest age.
    private func sentence(_ results: PlanResults?) -> String? {
        guard let results else { return nil }
        let headline = results.headline
        var sentence = "In \(GlanceText.futures(headline.confidence)) futures your money lasts to "
            + "\(results.details.endAge)."
        if onWhatIf == nil, let target = headline.targetAge, let success = headline.successAtTarget,
           target != headline.earliestAge {
            sentence += " Stop at \(target): \(PlanTimelineText.tenths(success)) in 10."
        }
        return sentence
    }
}

/// How far ahead of the year's plan your money is, or behind it:
/// "21.572 € ahead ›", or "21.572 € ahead of your January plan" with what
/// it's `against`.
struct AheadGapLabel: View {
    let gap: Decimal
    let currency: CurrencyCode
    var against: String?

    @Environment(\.locale) private var locale

    var body: some View {
        let words = PlanWords(currency: currency, locale: locale)
        let side = gap >= 0 ? "ahead" : "behind"
        AmountSentenceText(Self.sentence(gap: gap, side: side, against: against, words: words))
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(gap >= 0 ? Palette.positive : Palette.orangeStroke)
    }

    /// "21.572 € ahead ›", or "21.572 € ahead of your January plan".
    private static func sentence(gap: Decimal, side: String, against: String?, words: PlanWords) -> AmountSentence {
        guard let against else { return "\(words.unsigned(gap)) \(side) ›" }
        return "\(words.unsigned(gap)) \(side) of \(against)"
    }
}

#Preview("Ahead · iPhone") {
    PlanPreviewHost(model: AppModel.preview()) { session in
        AheadView(session: session, opening: .constant(nil))
            .environment(\.pageLayout, PageLayout())
    }
}

#Preview("Ahead · Mac") {
    PlanPreviewHost(model: AppModel.preview()) { session in
        AheadView(session: session, opening: .constant(nil))
            .environment(\.pageLayout, PageLayout(isWide: true))
            .frame(width: 1_100, height: 1_000)
    }
}
