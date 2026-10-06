import Model
import Planner
import SwiftUI

// The chapters' inputs (UI.md, "Plan"): each one edited in place or in its
// sheet, what can be added to a chapter, the inputs outside the plan's
// years, and the sheets for what every chapter shares.

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

// MARK: - Adding

/// *Add to this chapter*: a work phase or a contribution before retirement,
/// a pension or a later phase of spending in it, an event in any; each
/// starting in the chapter.
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
