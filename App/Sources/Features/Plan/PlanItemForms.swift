import Model
import Planner
import SwiftUI

// The lists of a plan's work phases, pensions, contributions and events,
// the Taxes card, and the sheets that edit one item.

// MARK: - Lists

/// Work phases as rows ("Employee · 2026–28"); a row opens its editor.
struct PlanWorkList: View {
    let plan: PlanDocument
    let summaries: PlanInputSummaries
    let issues: PlanInputIssues
    @Binding var editing: PlanEditTarget?
    @Environment(LibraryStore.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            ForEach(plan.work.indices, id: \.self) { index in
                let phase = plan.work[index]
                PlanListRow(title: "\(PlanWorkText.title(of: phase, index: index, of: plan.work.count)) · "
                                + PlanWorkText.years(of: phase),
                            detail: summaries.detail(of: phase), issues: issues.issues(for: .work, index: index)) {
                    editing = .work(index: index, phase: phase)
                }
                Divider()
            }
            Button {
                editing = .work(index: plan.work.count,
                                phase: PlanEditing.newWorkPhase(in: plan, asOf: library.asOfDate))
            } label: {
                Label("Add a work phase", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
    }
}

/// Pensions as rows ("State pension", "From 67 · 14.000 €/yr after tax").
struct PlanPensionList: View {
    let plan: PlanDocument
    let summaries: PlanInputSummaries
    let issues: PlanInputIssues
    @Binding var editing: PlanEditTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            ForEach(plan.pensions.indices, id: \.self) { index in
                let pension = plan.pensions[index]
                PlanListRow(title: PlanResultsMapping.pensionName(pension, index: index, of: plan.pensions.count),
                            detail: summaries.detail(of: pension), issues: issues.issues(for: .pensions, index: index)) {
                    editing = .pension(index: index, pension: pension)
                }
                Divider()
            }
            Button {
                editing = .pension(index: plan.pensions.count, pension: PlanEditing.newPension())
            } label: {
                Label("Add a pension", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
    }
}

/// Contributions as rows ("Fondo pensione · Every year until retirement ·
/// 5.000 €/yr"); a row opens its editor.
struct PlanContributionList: View {
    let plan: PlanDocument
    let summaries: PlanInputSummaries
    let issues: PlanInputIssues
    @Binding var editing: PlanEditTarget?
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let accounts = PlanEditing.contributionAccounts(in: library.library)
        VStack(alignment: .leading, spacing: Metrics.xs) {
            ForEach(plan.contributions.indices, id: \.self) { index in
                let contribution = plan.contributions[index]
                PlanListRow(title: summaries.title(of: contribution), detail: summaries.detail(of: contribution),
                            issues: issues.issues(for: .contributions, index: index)) {
                    editing = .contribution(index: index, contribution: contribution)
                }
                Divider()
            }
            Button {
                if let contribution = PlanEditing.newContribution(in: library.library, plan: plan) {
                    editing = .contribution(index: plan.contributions.count, contribution: contribution)
                }
            } label: {
                Label("Add a contribution", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .disabled(accounts.isEmpty)
        }
    }
}

/// One-off events as rows ("Inheritance · at 62").
struct PlanEventList: View {
    let plan: PlanDocument
    let summaries: PlanInputSummaries
    let issues: PlanInputIssues
    @Binding var editing: PlanEditTarget?
    @Environment(LibraryStore.self) private var library

    private func when(_ event: PlanEvent) -> String {
        switch event.timing {
        case .age(let age): "at \(age)"
        case .year(let year): "in \(String(year))"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            ForEach(plan.events.indices, id: \.self) { index in
                let event = plan.events[index]
                PlanListRow(title: "\(event.name) · \(when(event))", detail: summaries.detail(of: event),
                            issues: issues.issues(for: .events, index: index)) {
                    editing = .event(index: index, event: event)
                }
                Divider()
            }
            Button {
                editing = .event(index: plan.events.count,
                                 event: PlanEditing.newEvent(in: plan, asOf: library.asOfDate))
            } label: {
                Label("Add an event", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
    }
}

// MARK: - Taxes

/// Taxes (PLANNER.md, "The model in brief"): one rate on investment income and gains,
/// and an optional wealth tax on the money you can draw above an allowance.
/// Income from work and pensions is entered after tax, so it needs none.
struct PlanTaxesEditor: View {
    @Binding var plan: PlanDocument
    @Environment(\.baseCurrency) private var currency

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            PlanNumberRow("Tax on investments", value: $plan.tax.investmentRate, kind: .percent, unit: "%",
                          prompt: "–")
            Text(PlanEditing.investmentRateExplanation)
                .font(.caption)
                .foregroundStyle(Palette.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Toggle("Wealth tax", isOn: $plan.tax.planHasWealthTax)
            if plan.tax.planHasWealthTax {
                PlanNumberRow("Rate", value: $plan.tax.wealthRate, kind: .percent, unit: "%/yr", prompt: "0")
                PlanNumberRow("Untaxed allowance", value: $plan.tax.wealthAllowance, unit: currency.rawValue,
                              prompt: "0")
            }
            Text(PlanEditing.wealthTaxExplanation)
                .font(.caption)
                .foregroundStyle(Palette.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
    }
}

// MARK: - Sheets

/// The sheet editing one list item.
struct PlanItemSheet: View {
    let session: PlanSession
    let target: PlanEditTarget
    let issues: PlanInputIssues

    private var plan: PlanDocument { session.editablePlan }

    /// A delete action for an item that exists (not a new one).
    private func deletion(_ exists: Bool, _ action: @escaping () -> Void) -> (() -> Void)? {
        exists ? action : nil
    }

    var body: some View {
        switch target {
        case .work(let index, let phase):
            PlanItemEditor(index < plan.work.count ? "Work phase" : "New work phase", item: phase, onSave: { edited in
                session.edit { $0.work = PlanEditing.replacing(at: index, with: edited, in: $0.work) }
            }, onDelete: deletion(index < plan.work.count) {
                session.edit { $0.work = PlanEditing.removing(at: index, from: $0.work) }
            }) { binding in
                PlanWorkPhaseForm(phase: binding, issues: issues.issues(for: .work, index: index))
            }
        case .pension(let index, let pension):
            PlanItemEditor(index < plan.pensions.count ? "Pension" : "New pension", item: pension, onSave: { edited in
                session.edit { $0.pensions = PlanEditing.replacing(at: index, with: edited, in: $0.pensions) }
            }, onDelete: deletion(index < plan.pensions.count) {
                session.edit { $0.pensions = PlanEditing.removing(at: index, from: $0.pensions) }
            }) { binding in
                PlanPensionForm(pension: binding, issues: issues.issues(for: .pensions, index: index))
            }
        case .contribution(let index, let contribution):
            PlanItemEditor(index < plan.contributions.count ? "Contribution" : "New contribution", item: contribution,
                           onSave: { edited in
                session.edit { $0.contributions = PlanEditing.replacing(at: index, with: edited, in: $0.contributions) }
            }, onDelete: deletion(index < plan.contributions.count) {
                session.edit { $0.contributions = PlanEditing.removing(at: index, from: $0.contributions) }
            }) { binding in
                PlanContributionForm(contribution: binding, issues: issues.issues(for: .contributions, index: index))
            }
        case .event(let index, let event):
            PlanItemEditor(index < plan.events.count ? "Event" : "New event", item: event, onSave: { edited in
                session.edit { $0.events = PlanEditing.replacing(at: index, with: edited, in: $0.events) }
            }, onDelete: deletion(index < plan.events.count) {
                session.edit { $0.events = PlanEditing.removing(at: index, from: $0.events) }
            }) { binding in
                PlanEventForm(event: binding, issues: issues.issues(for: .events, index: index))
            }
        }
    }
}

/// A list of issues as a form section.
struct PlanIssuesSection: View {
    let issues: [PlanIssue]

    var body: some View {
        if !issues.isEmpty {
            Section {
                ForEach(issues, id: \.self) { issue in
                    PlanIssueLine(issue)
                }
            }
        }
    }
}

// MARK: - Forms

/// A work phase: its name, dates, income after tax and its growth.
struct PlanWorkPhaseForm: View {
    @Binding var phase: WorkPhase
    let issues: [PlanIssue]
    @Environment(\.baseCurrency) private var currency

    var body: some View {
        Section("Work") {
            TextField("Name", text: $phase.planName, prompt: Text("Work"))
            DatePicker("From", selection: $phase.from.planDate, displayedComponents: .date)
            Toggle("Until retirement", isOn: $phase.planUntilRetirement)
            if !phase.planUntilRetirement {
                DatePicker("Until", selection: $phase.planUntilDate.planDate, displayedComponents: .date)
            }
        }
        Section {
            PlanNumberRow("Income after tax", value: $phase.netIncome, unit: "/yr")
            PlanNumberRow("Real growth", value: $phase.realGrowth, kind: .percent, unit: "%/yr", prompt: "0")
        } header: {
            Text("Income")
        } footer: {
            Text("What reaches your bank account in a year, after income tax and social contributions, in "
                + "\(PlanMoney.todaysMoney(currency)). Growth is above inflation.")
        }
        PlanIssuesSection(issues: issues)
    }
}

/// A pension: its name, the age it starts at and what it pays after tax,
/// from your pension statement.
struct PlanPensionForm: View {
    @Binding var pension: PlanPension
    let issues: [PlanIssue]
    @Environment(\.baseCurrency) private var currency

    var body: some View {
        Section {
            TextField("Name", text: $pension.planName, prompt: Text("Pension"))
            Stepper("Paid from \(pension.planFromAge)", value: $pension.planFromAge, in: 40...90)
            PlanNumberRow("After tax per year", value: $pension.perYear, unit: "/yr")
        } header: {
            Text("Pension")
        } footer: {
            Text("From your pension statement, after the tax you expect to pay on it, in "
                + "\(PlanMoney.todaysMoney(currency)).")
        }
        PlanIssuesSection(issues: issues)
    }
}

/// A contribution into an account, paid every year while working (until
/// retirement or a date) or once, in a year.
struct PlanContributionForm: View {
    @Binding var contribution: PlanContribution
    let issues: [PlanIssue]
    @Environment(LibraryStore.self) private var library
    @Environment(\.baseCurrency) private var currency

    var body: some View {
        let accounts = PlanEditing.contributionAccounts(in: library.library)
        Section {
            Picker("Into", selection: $contribution.account) {
                if !accounts.contains(where: { $0.id == contribution.account }) {
                    Text(contribution.account.rawValue).tag(contribution.account)
                }
                ForEach(accounts) { account in
                    Text(account.name).tag(account.id)
                }
            }
        } header: {
            Text("Contribution")
        } footer: {
            Text("Paid into the account, and drawn once it's available (Available from age on the account). The "
                + "rest of your savings goes to the money you can draw.")
        }
        Section {
            Picker("Paid", selection: $contribution.planIsOneOff) {
                Text("Every year").tag(false)
                Text("Once").tag(true)
            }
            .pickerStyle(.segmented)
            if contribution.planIsOneOff {
                PlanNumberRow("Amount", value: $contribution.planAmount)
                Stepper("In \(String(contribution.planYear))", value: $contribution.planYear, in: 2_000...2_150)
            } else {
                PlanNumberRow("Per year", value: $contribution.perYear, unit: "/yr")
                Toggle("Until retirement", isOn: $contribution.planUntilRetirement)
                if !contribution.planUntilRetirement {
                    DatePicker("Until", selection: $contribution.planUntilDate.planDate, displayedComponents: .date)
                }
            }
        } header: {
            Text("Amount")
        } footer: {
            Text("In \(PlanMoney.todaysMoney(currency)).")
        }
        PlanIssuesSection(issues: issues)
    }
}

/// A one-off event: money in (a windfall, an inheritance) or an expense,
/// by age or year, with the chance it happens.
struct PlanEventForm: View {
    @Binding var event: PlanEvent
    let issues: [PlanIssue]

    private var whenLabel: String {
        event.planByAge ? "At \(event.planWhen)" : "In \(String(event.planWhen))"
    }

    var body: some View {
        Section("Event") {
            TextField("Name", text: $event.name)
            Picker("Type", selection: $event.planType) {
                ForEach(PlanEventType.allCases, id: \.self) { type in
                    Text(type.title).tag(type)
                }
            }
            PlanNumberRow("Amount", value: $event.planSize)
        }
        Section("When") {
            Picker("Set by", selection: $event.planByAge) {
                Text("Age").tag(true)
                Text("Year").tag(false)
            }
            .pickerStyle(.segmented)
            Stepper(whenLabel, value: $event.planWhen, in: event.planByAge ? 18...110 : 2_000...2_150)
        }
        if event.planType != .expense {
            Section {
                PlanNumberRow("Chance it happens", value: $event.planProbability, kind: .percent, unit: "%")
            } footer: {
                Text("Each simulated future draws whether it happens; the expected path includes it from 50%.")
            }
        }
        PlanIssuesSection(issues: issues)
    }
}

#Preview("Work phase") {
    PlanItemEditor("Work phase", item: PreviewLibrary.library.plans["base"]!.work[1], onSave: { _ in }) { phase in
        PlanWorkPhaseForm(phase: phase, issues: [])
    }
    .previewEnvironment()
}
