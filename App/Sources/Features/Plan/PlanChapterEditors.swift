import Model
import Planner
import SwiftUI

// The chapters' inputs (UI.md, "Ahead"): those outside the plan's years,
// what can be added to a chapter, and the sheets for what every chapter
// shares. A chapter's own settings are in PlanChapterSettings.swift.

// MARK: - Outside the chapters

/// Inputs that apply in none of the plan's years: before it starts, after
/// its end, or a pension without an age; as settings, each opening its
/// editor or its sheet.
struct PlanOutsideCard: View {
    let model: PlanChaptersModel
    @Binding var plan: PlanDocument
    let issues: PlanInputIssues
    let words: PlanWords
    /// Opens a setting's sheet.
    var onOpen: (PlanSettingSheet) -> Void = { _ in }

    @Environment(LibraryStore.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PlanPartLabel("Outside the plan's years")
            PlanSettingsList(rows: PlanChapterSettings.rows(for: model.chapters.outside, model: model, issues: issues,
                                                            words: words, namesWork: true),
                             plan: $plan, model: model, canEdit: library.canEdit, onSheet: onOpen)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .privacySensitiveInFeedback()
            Stepper("Plan to age \(plan.planEndAge)", value: $plan.planEndAge, in: 70...110)
                .font(.subheadline)
                .personalControl()
        }
        .padding(Metrics.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
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
        .padding(Metrics.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

/// The problems no chapter shows: spending's, and those about a list as a
/// whole rather than one of its items. Each on its own line, above the
/// chapters.
struct PlanUnplacedIssues: View {
    let issues: PlanInputIssues

    private var unplaced: [PlanIssue] {
        let lists: [PlanInputSection] = [.work, .pensions, .income, .contributions, .events]
        return issues.issues(for: .spending) + lists.flatMap { issues.issues(for: $0).filter { $0.index == nil } }
    }

    var body: some View {
        let unplaced = self.unplaced
        if !unplaced.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.s) {
                ForEach(unplaced, id: \.self) { issue in
                    PlanIssueLine(issue)
                }
            }
            .padding(Metrics.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }
}

// MARK: - Adding

/// *Add to this chapter*: a work phase or a contribution before retirement,
/// a pension or a later phase of spending in it, other income and an event
/// in any; each starting in the chapter.
struct PlanChapterAddMenu: View {
    let chapter: PlanChapter
    let model: PlanChaptersModel
    let plan: PlanDocument
    @Binding var editing: PlanEditTarget?

    @Environment(LibraryStore.self) private var library

    var body: some View {
        Menu {
            if chapter.isRetired {
                Button("Pension") {
                    editing = .pension(index: plan.pensions.count, pension: model.newPension(in: chapter))
                }
                Button("Later spending") {
                    editing = .spendingPhase(index: plan.spending.phases.count,
                                             phase: model.newSpendingPhase(in: chapter))
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
            Button("Other income") {
                editing = .income(index: plan.income.count, income: model.newIncome(in: chapter))
            }
            Button("Event") {
                editing = .event(index: plan.events.count, event: model.newEvent(in: chapter))
            }
        } label: {
            Text("Add to This Chapter")
                .font(.body)
                .foregroundStyle(Palette.accent)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Palette.card, in: Capsule())
                .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}

/// *Add* beside *Your life ahead*: something new in the chapter it starts
/// in. A work phase in the last chapter you work in, a pension or a later
/// phase of spending in the first retired one, a contribution and an event
/// in the first, other income from when work stops, and a change of mix,
/// which the target mix's sheet adds. Each opens its sheet, which adds
/// nothing until *Apply*.
struct PlanAddMenu<MenuLabel: View>: View {
    let model: PlanChaptersModel
    let plan: PlanDocument
    @Binding var editing: PlanEditTarget?
    /// Opens the target mix's sheet, where its changes with age are added.
    var onTargetMix: () -> Void = {}
    @ViewBuilder var label: MenuLabel

    @Environment(LibraryStore.self) private var library

    var body: some View {
        let chapters = model.chapters.chapters
        let working = chapters.last { !$0.isRetired }
        let retired = chapters.first { $0.isRetired }
        Menu {
            if let working {
                Button("Work Phase") {
                    editing = .work(index: plan.work.count, phase: model.newWorkPhase(in: working))
                }
            }
            if let retired {
                Button("Pension") {
                    editing = .pension(index: plan.pensions.count, pension: model.newPension(in: retired))
                }
                Button("Later Spending") {
                    editing = .spendingPhase(index: plan.spending.phases.count,
                                             phase: model.newSpendingPhase(in: retired))
                }
            }
            if let first = chapters.first {
                Button("Other Income") {
                    editing = .income(index: plan.income.count, income: model.newIncome(in: retired ?? first))
                }
                Button("Contribution") {
                    if let contribution = model.newContribution(in: first, library: library.library) {
                        editing = .contribution(index: plan.contributions.count, contribution: contribution)
                    }
                }
                .disabled(first.isRetired || PlanEditing.contributionAccounts(in: library.library).isEmpty)
                Button("Event") {
                    editing = .event(index: plan.events.count, event: model.newEvent(in: first))
                }
                Button("Change of Mix…", action: onTargetMix)
            }
        } label: {
            label
        }
        .menuIndicator(.hidden)
        .disabled(chapters.isEmpty || !library.canEdit)
    }
}

// MARK: - What every chapter shares

/// All the assumptions, in a sheet: your birth date, taxes, returns and
/// inflation, the target mix and the simulation, as collapsible cards. The
/// target mix's card opens its own sheet, ``PlanTargetMixSheet``.
struct PlanAlwaysSheet: View {
    let session: PlanSession

    @Environment(LibraryStore.self) private var library
    @Environment(\.baseCurrency) private var baseCurrency
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var expanded: [PlanInputSection: Bool] = [.assumptions: true]
    @State private var showsTargetMix = false

    private static let sections: [PlanInputSection] = [.you, .taxes, .assumptions, .targetMix, .simulation]

    var body: some View {
        @Bindable var session = session
        let issues = session.inputIssues
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.s) {
                    if let plan = session.plan {
                        let summaries = PlanInputSummaries(plan: plan, library: library.library, currency: baseCurrency,
                                                           locale: locale)
                        ForEach(Self.sections) { section in
                            PlanSectionCard(section: section, summary: summaries.summary(for: section),
                                            issues: issues.issues(for: section),
                                            isExpanded: $expanded[planFlag: section]) {
                                if section == .targetMix {
                                    PlanTargetMixOverview(portfolio: plan.portfolio) { showsTargetMix = true }
                                        .disabled(!session.canEdit)
                                } else {
                                    PlanSectionEditor(section: section, plan: $session.editablePlan)
                                        .disabled(!session.canEdit)
                                }
                            }
                        }
                    }
                }
                .padding(Metrics.l)
            }
            .background(Palette.page)
            .sheetTitle("Assumptions") { dismiss() }
            .sheet(isPresented: $showsTargetMix) {
                PlanTargetMixSheet(session: session)
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 600)
        #endif
    }
}

/// The target mix and its changes with age, in a sheet of their own: a
/// grouped form editing a copy of the plan, then *With this change*.
/// *Apply* writes the copy's mix and its changes with age to the plan;
/// *Cancel* discards them.
struct PlanTargetMixSheet: View {
    let session: PlanSession

    var body: some View {
        let apply: (inout PlanDocument, PlanDocument) -> Void = { plan, edited in
            plan.portfolio.targetMix = edited.portfolio.targetMix
            plan.portfolio.targetMixByAge = edited.portfolio.targetMixByAge
        }
        PlanItemEditor("Target mix", item: session.editablePlan,
                       preview: PlanEditPreview(session: session, applying: apply),
                       onSave: { edited in session.edit { apply(&$0, edited) } }) { plan in
            PlanTargetMixEditor(plan: plan)
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
    }
}
