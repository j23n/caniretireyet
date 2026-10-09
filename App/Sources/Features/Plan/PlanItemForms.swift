import Model
import Planner
import SwiftUI

// The Taxes card, and the sheets that edit one work phase, pension, other
// income, contribution or event (the chapters list them, UI.md "The editors").

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

    var body: some View {
        switch target {
        case .work(let index, let phase):
            editor(\.work, at: index, item: phase, title: "Work phase", new: "New work phase") {
                PlanWorkPhaseForm(phase: $0, issues: issues.issues(for: .work, index: index))
            }
        case .pension(let index, let pension):
            editor(\.pensions, at: index, item: pension, title: "Pension", new: "New pension") {
                PlanPensionForm(pension: $0, issues: issues.issues(for: .pensions, index: index))
            }
        case .income(let index, let income):
            editor(\.income, at: index, item: income, title: "Other income", new: "New income") {
                PlanIncomeForm(income: $0, issues: issues.issues(for: .income, index: index))
            }
        case .contribution(let index, let contribution):
            editor(\.contributions, at: index, item: contribution, title: "Contribution", new: "New contribution") {
                PlanContributionForm(contribution: $0, issues: issues.issues(for: .contributions, index: index))
            }
        case .event(let index, let event):
            editor(\.events, at: index, item: event, title: "Event", new: "New event") {
                PlanEventForm(event: $0, issues: issues.issues(for: .events, index: index))
            }
        }
    }

    /// The editor of the item at `index` of the plan's `list`: titled
    /// `title`, or `new` for an item not in the list yet, which has no
    /// *Delete*. *Done* puts the item at its index.
    private func editor<Item: Equatable, Fields: View>(
        _ list: WritableKeyPath<PlanDocument, [Item]>, at index: Int, item: Item, title: String, new: String,
        @ViewBuilder fields: @escaping (Binding<Item>) -> Fields
    ) -> some View {
        let exists = index < session.editablePlan[keyPath: list].count
        return PlanItemEditor(exists ? title : new, item: item, onSave: { edited in
            session.edit { $0[keyPath: list] = PlanEditing.replacing(at: index, with: edited, in: $0[keyPath: list]) }
        }, onDelete: exists ? {
            session.edit { $0[keyPath: list] = PlanEditing.removing(at: index, from: $0[keyPath: list]) }
        } : nil, content: fields)
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
            TextField("Name", text: $phase.name.orEmpty, prompt: Text("Work"))
            DatePicker("From", selection: $phase.from.planDate, displayedComponents: .date)
            Toggle("Until retirement", isOn: $phase.planUntilRetirement)
            if !phase.planUntilRetirement {
                DatePicker("Until", selection: $phase.planUntilDate.planDate, displayedComponents: .date)
            }
        }
        Section {
            PlanNumberRow("Take-home pay", value: $phase.netIncome.perMonth, unit: "/month")
            PlanNumberRow("Real growth", value: $phase.realGrowth, kind: .percent, unit: "%/yr", prompt: "0")
        } header: {
            Text("Income")
        } footer: {
            Text("What reaches your bank account in a month, after income tax and social contributions, in "
                + "\(PlanMoney.todaysMoney(currency)). Growth is a year, above inflation.")
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
            TextField("Name", text: $pension.name.orEmpty, prompt: Text("Pension"))
            Stepper("Paid from \(pension.planFromAge)", value: $pension.planFromAge, in: 40...90)
            PlanNumberRow("After tax, a month", value: $pension.perYear.perMonth, unit: "/month")
        } header: {
            Text("Pension")
        } footer: {
            Text("From your pension statement, after the tax you expect to pay on it, in "
                + "\(PlanMoney.todaysMoney(currency)).")
        }
        PlanIssuesSection(issues: issues)
    }
}

/// Other income: its name, when it starts (an age, or when you stop
/// working) and stops, and what it pays after tax.
struct PlanIncomeForm: View {
    @Binding var income: PlanIncome
    let issues: [PlanIssue]
    @Environment(\.baseCurrency) private var currency

    var body: some View {
        Section {
            TextField("Name", text: $income.name.orEmpty, prompt: Text("Other income"))
            Toggle("From when you stop working", isOn: $income.planFromRetirement)
            if !income.planFromRetirement {
                Stepper("From \(income.planFromAge)", value: $income.planFromAge, in: 18...100)
            }
            Toggle("Stops at an age", isOn: $income.planHasEnd)
            if income.planHasEnd {
                Stepper("Until \(income.planUntilAge)", value: $income.planUntilAge, in: 19...110)
            }
            PlanNumberRow("After tax, a month", value: $income.perYear.perMonth, unit: "/month")
        } header: {
            Text("Other income")
        } footer: {
            Text("Rent, a side business, an annuity, or part-time work once you stop your main job, after tax, in "
                + "\(PlanMoney.todaysMoney(currency)). Unlike work, it doesn't stop when you retire.")
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
                Text("Every month").tag(false)
                Text("Once").tag(true)
            }
            .pickerStyle(.segmented)
            if contribution.planIsOneOff {
                PlanNumberRow("Amount", value: $contribution.planAmount)
                Stepper("In \(String(contribution.planYear))", value: $contribution.planYear, in: 2_000...2_150)
            } else {
                PlanNumberRow("A month", value: $contribution.perYear.perMonth, unit: "/month")
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
