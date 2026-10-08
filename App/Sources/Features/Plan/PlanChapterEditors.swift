import Model
import Planner
import SwiftUI

// The chapters' inputs (UI.md, "Plan"): those outside the plan's years,
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
    /// Opens an item's sheet, or the target mix's.
    var onOpen: (PlanToken) -> Void = { _ in }

    @Environment(LibraryStore.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
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
            PlanSettingsList(rows: PlanChapterSettings.rows(for: model.chapters.outside, plan: plan, model: model,
                                                            issues: issues, words: words),
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
        let lists: [PlanInputSection] = [.work, .pensions, .income, .contributions, .events]
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

// MARK: - Adding

/// *Add to this chapter*: a work phase or a contribution before retirement,
/// a pension or a later phase of spending in it, other income and an event
/// in any; each starting in the chapter.
struct PlanChapterAddMenu: View {
    let chapter: PlanChapter
    let model: PlanChaptersModel
    @Binding var plan: PlanDocument
    @Binding var editing: PlanEditTarget?

    @Environment(LibraryStore.self) private var library

    var body: some View {
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
            Button("Other income") {
                editing = .income(index: plan.income.count, income: model.newIncome(in: chapter))
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

// MARK: - What every chapter shares

/// All the assumptions, in a sheet: your birth date, taxes, returns and
/// inflation, the target mix and the simulation, as collapsible cards.
struct PlanAlwaysSheet: View {
    let session: PlanSession

    @Environment(LibraryStore.self) private var library
    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.baseCurrency) private var baseCurrency
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var expanded: [PlanInputSection: Bool] = [.assumptions: true]

    private static let sections: [PlanInputSection] = [.taxes, .assumptions, .targetMix, .simulation]

    var body: some View {
        @Bindable var session = session
        let issues = session.inputIssues
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.s) {
                    if let plan = session.plan {
                        let summaries = PlanInputSummaries(plan: plan, library: library.library, currency: baseCurrency,
                                                           hidesAmounts: hidesAmounts, locale: locale)
                        PlanSectionCard(section: .you, summary: Self.bornSummary(library.settings.person?.birthDate),
                                        issues: issues.issues(for: .you), isExpanded: $expanded[planFlag: .you]) {
                            PlanBirthDateEditor()
                                .disabled(!session.canEdit)
                        }
                        ForEach(Self.sections) { section in
                            PlanSectionCard(section: section, summary: summaries.summary(for: section),
                                            issues: issues.issues(for: section),
                                            listedIssues: issues.cardIssues(for: section, in: plan),
                                            isExpanded: $expanded[planFlag: section]) {
                                PlanSectionEditor(section: section, plan: $session.editablePlan)
                                    .disabled(!session.canEdit)
                            }
                        }
                    }
                }
                .padding(Metrics.l)
            }
            .background(Palette.page)
            .navigationTitle("Assumptions")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 600)
        #endif
    }

    /// "Born 1988", "No birth date".
    static func bornSummary(_ birthDate: CalendarDate?) -> String {
        birthDate.map { "Born \($0.year)" } ?? "No birth date"
    }
}

/// The target mix and its changes with age, in a sheet of their own.
struct PlanTargetMixSheet: View {
    @Binding var plan: PlanDocument

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                PlanTargetMixEditor(plan: $plan)
                    .padding(Metrics.l)
            }
            .background(Palette.page)
            .navigationTitle("Target mix")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
    }
}
