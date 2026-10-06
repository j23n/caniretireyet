import Model
import Planner
import SwiftUI

/// Chapters (UI.md, "Chapters"): the plan's inputs by the stretch of life
/// they belong to. A map at the top (the money over time, with the chapters
/// as bands), then a card per chapter: what pays for your life, where the
/// money stands at its end, what starts in it (each editable in place or in
/// a sheet), what carries on from before, and *Add to this chapter*. Inputs
/// that apply in none of the plan's years follow, then *Always*: what holds
/// in every chapter (your birth date, taxes, returns, the target mix, the
/// simulation).
///
/// Choosing a chapter on the map (here or in Results) scrolls to its card.
/// Edits are saved as you go, and move the chapters at once.
struct PlanChaptersView: View {
    let session: PlanSession
    /// In the Mac inspector: a narrower column with its own header, and no
    /// map (Results has it, next to the inspector).
    var isInspector = false

    @Environment(LibraryStore.self) private var library
    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.baseCurrency) private var baseCurrency
    @Environment(\.locale) private var locale
    @State private var expanded: [PlanInputSection: Bool] = [:]
    @State private var editing: PlanEditTarget?
    /// A chapter chosen in the list itself: it's already in view.
    @State private var choseInList = false

    /// The cards of Always, in order.
    private static let alwaysSections: [PlanInputSection] = [.taxes, .assumptions, .targetMix, .simulation]

    var body: some View {
        @Bindable var session = session
        if let plan = session.plan {
            let issues = session.inputIssues
            let summaries = PlanInputSummaries(plan: plan, library: library.library, currency: baseCurrency,
                                               hidesAmounts: hidesAmounts, locale: locale)
            let chapters = session.chapters
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Metrics.m) {
                        if isInspector {
                            PlanInputsHeader(title: "Chapters", issues: issues)
                        }
                        if !session.canEdit {
                            StatusBanner(.info, "Read-only", message: "This library can't be changed here.")
                        }
                        if !isInspector, let chapters {
                            PlanChaptersMap(session: session, chapters: chapters)
                        }
                        PlanUnplacedIssues(issues: issues, plan: plan)
                        if let chapters {
                            chapterCards(chapters, plan: $session.editablePlan, summaries: summaries, issues: issues,
                                         proxy: proxy)
                        } else {
                            PlanChaptersNeedBirthDate()
                        }
                        always(plan: plan, summaries: summaries, issues: issues)
                    }
                    .padding(isInspector ? Metrics.m : Metrics.l)
                    .frame(maxWidth: isInspector ? .infinity : Metrics.readableWidth)
                    .frame(maxWidth: .infinity)
                }
                .onAppear { scrollToSelection(proxy, animated: false) }
                .onChange(of: session.selectedChapterYear) {
                    if choseInList {
                        choseInList = false
                    } else {
                        scrollToSelection(proxy, animated: true)
                    }
                }
            }
            .background(isInspector ? Color.clear : Palette.page)
            .sheet(item: $editing) { target in
                PlanItemSheet(session: session, target: target, issues: issues)
            }
            .onDisappear { session.saveNow() }
        } else {
            ContentUnavailableView("No plan", systemImage: AppSymbol.plan)
        }
    }

    // MARK: Chapters

    @ViewBuilder
    private func chapterCards(_ chapters: PlanChaptersModel, plan: Binding<PlanDocument>,
                              summaries: PlanInputSummaries, issues: PlanInputIssues,
                              proxy: ScrollViewProxy) -> some View {
        let selected = session.selectedChapter(in: chapters)
        let state = session.stateWithoutProgress
        if chapters.chapters.chapters.isEmpty {
            PlanNoChapters(plan: plan)
        }
        ForEach(chapters.chapters.chapters.indices, id: \.self) { index in
            PlanChapterCard(
                index: index, chapter: chapters.chapters.chapters[index], model: chapters, plan: plan,
                summaries: summaries, issues: issues, outcome: chapters.outcomes[index],
                currency: session.shownResults.map { session.currency(of: $0) },
                isSelected: selected == index, dimsOutcome: state.dimsResults, editing: $editing,
                onSelect: {
                    choseInList = session.selectedChapter(in: chapters) != index
                    session.selectChapter(index, in: chapters)
                },
                onShowTargetMix: { show(.targetMix, proxy: proxy) },
                onUsePlanAge: { session.selectFocus(nil) })
                .id(PlanChaptersAnchor.chapter(index))
        }
        if !chapters.chapters.outside.isEmpty {
            PlanOutsideCard(model: chapters, plan: plan, summaries: summaries, issues: issues, editing: $editing,
                            onShowTargetMix: { show(.targetMix, proxy: proxy) })
                .id(PlanChaptersAnchor.outside)
        }
    }

    /// Scrolls to the selected chapter's card.
    private func scrollToSelection(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let chapters = session.chapters, let index = session.selectedChapter(in: chapters) else { return }
        if animated {
            withAnimation(.snappy) { proxy.scrollTo(PlanChaptersAnchor.chapter(index), anchor: .top) }
        } else {
            proxy.scrollTo(PlanChaptersAnchor.chapter(index), anchor: .top)
        }
    }

    /// Opens an Always card and scrolls to it.
    private func show(_ section: PlanInputSection, proxy: ScrollViewProxy) {
        expanded[section] = true
        withAnimation(.snappy) { proxy.scrollTo(PlanChaptersAnchor.section(section), anchor: .top) }
    }

    // MARK: Always

    @ViewBuilder
    private func always(plan: PlanDocument, summaries: PlanInputSummaries, issues: PlanInputIssues) -> some View {
        @Bindable var session = session
        VStack(alignment: .leading, spacing: 2) {
            Text("Always")
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text("What holds in every chapter.")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
        }
        .padding(.top, Metrics.m)
        .padding(.horizontal, Metrics.xs)
        PlanSectionCard(section: .you, summary: Self.bornSummary(library.settings.person?.birthDate),
                        issues: issues.issues(for: .you), isExpanded: $expanded[planFlag: .you]) {
            PlanBirthDateEditor()
                .disabled(!session.canEdit)
        }
        .id(PlanChaptersAnchor.section(.you))
        ForEach(Self.alwaysSections) { section in
            PlanSectionCard(section: section, summary: summaries.summary(for: section),
                            issues: issues.issues(for: section),
                            listedIssues: issues.cardIssues(for: section, in: plan),
                            isExpanded: $expanded[planFlag: section]) {
                PlanSectionEditor(section: section, plan: $session.editablePlan)
                    .disabled(!session.canEdit)
            }
            .id(PlanChaptersAnchor.section(section))
        }
    }

    /// "Born 1988", "No birth date".
    static func bornSummary(_ birthDate: CalendarDate?) -> String {
        birthDate.map { "Born \($0.year)" } ?? "No birth date"
    }
}

/// Where the chapters list can scroll to.
enum PlanChaptersAnchor: Hashable {
    case chapter(Int)
    case outside
    case section(PlanInputSection)
}

// MARK: - The map

/// The map at the top of Chapters (iPhone, and Mac or iPad without the
/// inspector's narrow column): the money over the plan's whole length with
/// the chapters as bands, and a button under each band that goes to its
/// card. Before the plan is calculated, only the buttons, over the plan's
/// years.
struct PlanChaptersMap: View {
    let session: PlanSession
    let chapters: PlanChaptersModel

    @Environment(PlanStore.self) private var plans
    @State private var width: CGFloat = ChartStyle.defaultWidth

    private var selection: Binding<Int?> {
        Binding(get: { session.selectedChapter(in: chapters) },
                set: { session.selectChapter($0, in: chapters) })
    }

    var body: some View {
        let state = session.stateWithoutProgress
        Card {
            if let results = state.results {
                FanChart(fan: results.portfolio, markers: results.markers, currency: session.currency(of: results),
                         height: 200, bands: chapters.bands, selectedBand: selection)
                    .opacity(state.isRunning ? 0.4 : state.isOutOfDate ? 0.65 : 1)
                Text("In \(PlanMoney.todaysMoney(session.currency(of: results))). Choose a chapter to go to it.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            } else {
                ChartBandStrip(bands: chapters.bands,
                               layout: ChartBandLayout(bands: chapters.bands, domain: chapters.domain,
                                                       plotWidth: Double(width)),
                               selection: selection)
                    .measuringWidth($width)
                HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                    Text("Calculate the plan to see your money through its chapters.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Metrics.s)
                    if !state.isRunning {
                        Button("Calculate") { session.calculate() }
                            .font(.footnote.weight(.semibold))
                            .buttonStyle(.borderless)
                            .disabled(!plans.isAvailable)
                    }
                }
            }
        } header: {
            SectionHeader("Your chapters") {
                Text(verbatim: "\(chapters.chapters.chapters.count)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondaryInk)
                    .accessibilityLabel(Text("\(chapters.chapters.chapters.count) chapters"))
            }
        }
    }
}

// MARK: - A chapter

/// One chapter's card: its number, title and years, where the money stands
/// at its end, what starts in it, what carries on, and *Add to this chapter*.
struct PlanChapterCard: View {
    let index: Int
    let chapter: PlanChapter
    let model: PlanChaptersModel
    @Binding var plan: PlanDocument
    let summaries: PlanInputSummaries
    let issues: PlanInputIssues
    let outcome: PlanChaptersModel.Outcome?
    /// The currency of the results the outcome comes from.
    var currency: CurrencyCode?
    var isSelected = false
    /// The outcome is from results out of date, or being recalculated.
    var dimsOutcome = false
    @Binding var editing: PlanEditTarget?
    var onSelect: () -> Void = {}
    var onShowTargetMix: () -> Void = {}
    var onUsePlanAge: () -> Void = {}

    @Environment(LibraryStore.self) private var library

    private var isLast: Bool { index == model.chapters.chapters.count - 1 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(alignment: .leading, spacing: Metrics.m) {
            Button(action: onSelect) {
                header
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Shows the chapter on the map"))
            if let outcome {
                PlanChapterOutcomeView(outcome: outcome, isLast: isLast, currency: currency)
                    .opacity(dimsOutcome ? 0.6 : 1)
            }
            if !chapter.items.isEmpty {
                VStack(alignment: .leading, spacing: Metrics.s) {
                    ForEach(chapter.items, id: \.self) { item in
                        PlanChapterItemRow(item: item, model: model, plan: $plan, summaries: summaries,
                                           issues: issues, editing: $editing, onShowTargetMix: onShowTargetMix,
                                           onUsePlanAge: onUsePlanAge)
                    }
                }
                .disabled(!library.canEdit)
            }
            if let continuing = model.continuing(in: chapter) {
                Text(continuing)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            addMenu
                .disabled(!library.canEdit)
        }
        .padding(Metrics.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: shape)
        .overlay {
            shape.strokeBorder(isSelected ? Palette.accent : Palette.border, lineWidth: isSelected ? 2 : 1)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Text(verbatim: "\(index + 1)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.white : Palette.accent)
                .frame(minWidth: 22, minHeight: 22)
                .background(isSelected ? Palette.accent : Palette.accent.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title(of: chapter))
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(PlanChaptersModel.span(of: chapter))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondaryInk)
                Text(model.subtitle(of: chapter))
                    .font(.footnote)
                    .foregroundStyle(Palette.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Chapter \(index + 1): \(model.title(of: chapter)), "
            + PlanChaptersModel.spokenSpan(of: chapter)))
        .accessibilityAddTraits(.isHeader)
    }

    /// What can start in the chapter: work and contributions before
    /// retirement, a pension and a later spending phase in it, events in any.
    private var addMenu: some View {
        Menu {
            if chapter.isRetired {
                Button("Pension") {
                    editing = .pension(index: plan.pensions.count, pension: model.newPension(in: chapter))
                }
                Button("Later spending") {
                    plan.spending.phases.append(model.newSpendingPhase(in: chapter))
                }
            } else {
                Button("Work phase") {
                    editing = .work(index: plan.work.count, phase: model.newWorkPhase(in: chapter))
                }
                Button("Contribution") {
                    if let contribution = model.newContribution(in: chapter, library: library.library) {
                        editing = .contribution(index: plan.contributions.count, contribution: contribution)
                    }
                }
                .disabled(PlanEditing.contributionAccounts(in: library.library).isEmpty)
            }
            Button("Event") {
                editing = .event(index: plan.events.count, event: model.newEvent(in: chapter))
            }
        } label: {
            Label("Add to this chapter", systemImage: "plus")
                .font(.subheadline)
        }
        .fixedSize()
    }
}

/// Where the money stands at a chapter's end: "End of 2028 · age 40", the
/// median and the range 8 in 10 futures fall in, and how many futures run
/// out during the chapter.
struct PlanChapterOutcomeView: View {
    let outcome: PlanChaptersModel.Outcome
    var isLast = false
    var currency: CurrencyCode?

    @Environment(\.locale) private var locale

    private var when: String {
        let age = "age \(outcome.age)"
        return isLast ? "At the plan's end, \(outcome.year) · \(age)" : "End of \(outcome.year) · \(age)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(when)
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
            HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
                Text("Median")
                    .foregroundStyle(Palette.secondaryInk)
                AmountText(Decimal(wholeNumber: outcome.median), currency: currency, tabular: false)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.ink)
            }
            .font(.subheadline)
            HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
                Text("8 in 10 futures between")
                AmountText(Decimal(wholeNumber: outcome.low), currency: currency, tabular: false)
                Text("and")
                AmountText(Decimal(wholeNumber: outcome.high), currency: currency, tabular: false)
            }
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
            if let share = outcome.failureShare, share > 0 {
                Label {
                    Text(Self.failureText(share, locale: locale))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.warning)
                }
                .font(.footnote)
                .foregroundStyle(Palette.ink)
            }
        }
        .padding(Metrics.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// "The money runs out during these years in 3% of futures."
    static func failureText(_ share: Double, locale: Locale = .current) -> String {
        let percent = AmountFormat.percent(share, digits: share < 0.01 ? 1 : 0, locale: locale)
        return "The money runs out during these years in \(percent) of futures."
    }
}

// MARK: - Inputs in a chapter

/// One input in a chapter: spending, when work stops and the plan's end
/// are edited in place; work, pensions, contributions and events open
/// their sheet; the target mix goes to its card in Always.
struct PlanChapterItemRow: View {
    let item: PlanChapter.Item
    let model: PlanChaptersModel
    @Binding var plan: PlanDocument
    let summaries: PlanInputSummaries
    let issues: PlanInputIssues
    @Binding var editing: PlanEditTarget?
    var onShowTargetMix: () -> Void = {}
    var onUsePlanAge: () -> Void = {}

    @Environment(\.locale) private var locale

    var body: some View {
        switch item {
        case .retirement:
            PlanRetirementEditor(plan: $plan, model: model, onUsePlanAge: onUsePlanAge)
        case .workingSpending:
            PlanNumberRow("Spending while working", value: $plan.spending.working, unit: "/yr")
                .font(.subheadline)
        case .retiredSpending:
            PlanRetiredSpendingEditor(spending: $plan.spending)
        case .spendingPhase(let index):
            PlanSpendingPhaseRow(phases: $plan.spending.phases, index: index)
                .font(.subheadline)
        case .work(let index):
            if plan.work.indices.contains(index) {
                let phase = plan.work[index]
                PlanListRow(title: "\(PlanWorkText.title(of: phase, index: index, of: plan.work.count)) · "
                                + PlanWorkText.years(of: phase),
                            detail: summaries.detail(of: phase), issues: issues.issues(for: .work, index: index)) {
                    editing = .work(index: index, phase: phase)
                }
            }
        case .pension(let index):
            if plan.pensions.indices.contains(index) {
                let pension = plan.pensions[index]
                PlanListRow(title: PlanResultsMapping.pensionName(pension, index: index, of: plan.pensions.count),
                            detail: summaries.detail(of: pension),
                            issues: issues.issues(for: .pensions, index: index)) {
                    editing = .pension(index: index, pension: pension)
                }
            }
        case .contribution(let index):
            if plan.contributions.indices.contains(index) {
                let contribution = plan.contributions[index]
                PlanListRow(title: model.name(of: item), detail: summaries.detail(of: contribution),
                            issues: issues.issues(for: .contributions, index: index)) {
                    editing = .contribution(index: index, contribution: contribution)
                }
            }
        case .event(let index):
            if plan.events.indices.contains(index) {
                let event = plan.events[index]
                PlanListRow(title: "\(event.name) · \(Self.when(event))", detail: summaries.detail(of: event),
                            issues: issues.issues(for: .events, index: index)) {
                    editing = .event(index: index, event: event)
                }
            }
        case .targetMix, .targetMixStep:
            PlanListRow(title: model.name(of: item), detail: model.mixText(of: item, locale: locale),
                        action: onShowTargetMix)
        case .end:
            Stepper("Plan to age \(plan.planEndAge)", value: $plan.planEndAge, in: 70...110)
                .font(.subheadline)
        }
    }

    /// "at 62", "in 2031".
    static func when(_ event: PlanEvent) -> String {
        switch event.timing {
        case .age(let age): "at \(age)"
        case .year(let year): "in \(String(year))"
        }
    }
}

/// When work stops: as early as possible, or at an age; and what the
/// chapters are cut at, with *Plan's age* when the charts are for another.
struct PlanRetirementEditor: View {
    @Binding var plan: PlanDocument
    let model: PlanChaptersModel
    var onUsePlanAge: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Toggle("Retire as early as possible", isOn: earliest)
            if !plan.planRetiresEarliest {
                Stepper("Retire at \(plan.planRetirementAge)", value: $plan.planRetirementAge, in: 30...85)
            }
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                Text(model.retirementNote)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                if model.ageSource == .chosen {
                    Spacer(minLength: Metrics.xs)
                    Button("Plan's age", action: onUsePlanAge)
                        .font(.footnote)
                        .buttonStyle(.borderless)
                }
            }
        }
        .font(.subheadline)
    }

    /// Turning "as early as possible" off keeps the age the chapters show.
    private var earliest: Binding<Bool> {
        Binding(get: { plan.retirement.age == .earliest },
                set: { isOn in plan.retirement.age = isOn ? .earliest : .age(model.retirementAge) })
    }
}

/// Spending in retirement, with flexible spending folded away.
struct PlanRetiredSpendingEditor: View {
    @Binding var spending: PlanSpending
    @State private var showsFlexible = false

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            PlanNumberRow("Spending in retirement", value: $spending.retired, unit: "/yr")
            DisclosureGroup(isExpanded: $showsFlexible) {
                PlanFlexibleSpendingEditor(spending: $spending)
                    .padding(.top, Metrics.xs)
            } label: {
                HStack {
                    Text("Flexible spending")
                    Spacer(minLength: Metrics.s)
                    Text(spending.planFlexibleOn ? "On" : "Off")
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
        }
        .font(.subheadline)
    }
}

// MARK: - Outside the chapters

/// Inputs that apply in none of the plan's years: before it starts, after
/// its end, or a pension without an age.
struct PlanOutsideCard: View {
    let model: PlanChaptersModel
    @Binding var plan: PlanDocument
    let summaries: PlanInputSummaries
    let issues: PlanInputIssues
    @Binding var editing: PlanEditTarget?
    var onShowTargetMix: () -> Void = {}

    @Environment(LibraryStore.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Outside the plan's years")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("These apply in no year the plan runs: before it starts, after it ends, or without an age.")
                    .font(.footnote)
                    .foregroundStyle(Palette.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: Metrics.s) {
                ForEach(model.chapters.outside, id: \.self) { item in
                    PlanChapterItemRow(item: item, model: model, plan: $plan, summaries: summaries, issues: issues,
                                       editing: $editing, onShowTargetMix: onShowTargetMix)
                }
            }
            .disabled(!library.canEdit)
        }
        .padding(Metrics.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1)
        }
    }
}

/// The plan's years are over (its end age is reached): a way to plan further.
struct PlanNoChapters: View {
    @Binding var plan: PlanDocument

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Text("The plan ends at \(plan.planEndAge), before its first year.")
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
            Stepper("Plan to age \(plan.planEndAge)", value: $plan.planEndAge, in: 70...110)
                .font(.subheadline)
        }
        .padding(Metrics.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// No birth date: chapters need ages.
struct PlanChaptersNeedBirthDate: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Text("Add your birth date")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            Text("A plan's chapters start and end at ages: when work stops, when a pension starts.")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            PlanBirthDateEditor()
        }
        .padding(Metrics.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// The problems no chapter shows: spending's, and those about a list as a
/// whole rather than one of its items. Each on its own line, above the
/// chapters.
struct PlanUnplacedIssues: View {
    let issues: PlanInputIssues
    let plan: PlanDocument

    private var unplaced: [PlanIssue] {
        let lists: [PlanInputSection] = [.work, .pensions, .contributions, .events]
        return issues.issues(for: .spending) + lists.flatMap { issues.cardIssues(for: $0, in: plan) }
    }

    var body: some View {
        let unplaced = self.unplaced
        if !unplaced.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.s) {
                ForEach(unplaced, id: \.self) { issue in
                    PlanIssueLine(issue)
                }
            }
            .padding(Metrics.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

#Preview("Chapters") {
    PlanPreviewHost(model: AppModel.preview(planEngine: PlanPreviewEngine())) { session in
        PlanChaptersView(session: session)
    }
}

#Preview("Chapters · inspector") {
    PlanPreviewHost(model: AppModel.preview(planEngine: PlanPreviewEngine())) { session in
        PlanChaptersView(session: session, isInspector: true)
            .frame(width: 380, height: 900)
    }
}
