import Glance
import Model
import Planner
import SwiftUI

// The editors of the plan's inputs: those of *Assumptions…*'s cards
// (UI.md, "The editors"), and the pieces the chapters edit in place.

/// What a sheet edits: an item, by its position (the list's count for a
/// new one), or a part of spending; with a copy taken when the sheet opened.
enum PlanEditTarget: Hashable, Identifiable {
    case work(index: Int, phase: WorkPhase)
    case pension(index: Int, pension: PlanPension)
    case income(index: Int, income: PlanIncome)
    case contribution(index: Int, contribution: PlanContribution)
    case event(index: Int, event: PlanEvent)
    /// Spending while working.
    case workingSpending(PlanSpending)
    /// Spending in retirement.
    case retiredSpending(PlanSpending)
    /// Flexible spending, which changes spending in retirement.
    case flexibleSpending(PlanSpending)
    /// A later phase of spending in retirement.
    case spendingPhase(index: Int, phase: SpendingPhase)

    var id: String {
        switch self {
        case .work(let index, _): "work-\(index)"
        case .pension(let index, _): "pension-\(index)"
        case .income(let index, _): "income-\(index)"
        case .contribution(let index, _): "contribution-\(index)"
        case .event(let index, _): "event-\(index)"
        case .workingSpending: "working-spending"
        case .retiredSpending: "retired-spending"
        case .flexibleSpending: "flexible-spending"
        case .spendingPhase(let index, _): "spending-phase-\(index)"
        }
    }
}

/// The editor inside one of Always's cards. The other sections are edited
/// in the chapters, by the stretch of life each input belongs to.
struct PlanSectionEditor: View {
    let section: PlanInputSection
    @Binding var plan: PlanDocument

    var body: some View {
        switch section {
        case .you:
            PlanBirthDateEditor()
        case .taxes:
            PlanTaxesEditor(plan: $plan)
        case .assumptions:
            PlanAssumptionsEditor(plan: $plan)
        case .targetMix:
            PlanTargetMixEditor(plan: $plan)
        case .simulation:
            PlanSimulationEditor(plan: $plan)
        case .work, .spending, .pensions, .income, .contributions, .events:
            EmptyView()
        }
    }
}

// MARK: - Birth date

/// The birth date, from the library's settings.
///
/// It's written only when you pick one, from the picker's own setter
/// (`YouSettings`): showing it writes nothing, and without a birth date it
/// says "Not set" rather than assuming one.
struct PlanBirthDateEditor: View {
    @Environment(LibraryStore.self) private var library
    /// Whether the picker is shown before a birth date is picked.
    @State private var addsBirthDate = false

    var body: some View {
        let birthDate = library.settings.person?.birthDate
        VStack(alignment: .leading, spacing: Metrics.s) {
            if birthDate != nil || addsBirthDate {
                DatePicker("Born", selection: birthDateBinding, in: ...Date(), displayedComponents: .date)
            } else {
                HStack {
                    Text("Born")
                    Spacer()
                    Text("Not set")
                        .foregroundStyle(Palette.secondaryInk)
                    Button("Add") { addsBirthDate = true }
                        .buttonStyle(.borderless)
                        .disabled(!library.canEdit)
                }
            }
            if birthDate == nil {
                PlanIssueLine(message: "Add your birth date: plans need it for ages.", isError: true)
            }
        }
        .font(.subheadline)
    }

    /// The picker's date: the birth date, or where the picker starts
    /// before one is picked. Picking a date saves it.
    private var birthDateBinding: Binding<Date> {
        Binding(
            get: { (library.settings.person?.birthDate ?? YouSettings.suggestedBirthDate()).dateValue },
            set: { date in
                let birth = CalendarDate(date, in: .current)
                guard library.canEdit, birth != library.settings.person?.birthDate else { return }
                try? library.updateSettings { settings in
                    settings = YouSettings.setting(birthDate: birth, in: settings)
                }
            })
    }
}

// MARK: - Assumptions

/// Inflation, returns and volatility by asset class, and the portfolio's
/// estimate for unrecorded gains and the accounts it leaves out.
struct PlanAssumptionsEditor: View {
    @Binding var plan: PlanDocument
    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale

    /// The classes with a return to set, in the assumptions' order.
    private static let classes: [AssetClass] = [.equity, .bonds, .cash, .gold, .crypto]

    /// The classes whose income yield can be set: those that pay income
    /// (equity, bonds), and any other the plan gives one.
    private var incomeClasses: [AssetClass] {
        Self.classes.filter { assetClass in
            PlanEditing.incomeYieldClasses.contains(assetClass)
                || plan.assumptions.returnAssumption(for: assetClass)?.incomeYield != nil
        }
    }

    var body: some View {
        let accounts = PlanEditing.contributionAccounts(in: library.library)
        VStack(alignment: .leading, spacing: Metrics.s) {
            PlanNumberRow("Inflation", value: $plan.assumptions.inflation, kind: .percent, unit: "%", prompt: "2")
            Text("Real return: mean · median · volatility")
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
            ForEach(Self.classes, id: \.self) { assetClass in
                let name = PlanIssueText.assetClassName(assetClass.rawValue)
                HStack(spacing: Metrics.xs) {
                    Text(name)
                    Spacer(minLength: Metrics.s)
                    PlanNumberField("\(name) mean real return",
                                    value: $plan.assumptions[planReal: assetClass], kind: .percent)
                        .frame(maxWidth: 52)
                    Text("% ·")
                        .foregroundStyle(Palette.secondaryInk)
                    PlanNumberField("\(name) median real return",
                                    value: $plan.assumptions[planMedianReal: assetClass], kind: .percent)
                        .frame(maxWidth: 52)
                    Text("% ·")
                        .foregroundStyle(Palette.secondaryInk)
                    PlanNumberField("\(name) volatility",
                                    value: $plan.assumptions[planVolatility: assetClass], kind: .percent)
                        .frame(maxWidth: 52)
                    Text("%")
                        .foregroundStyle(Palette.secondaryInk)
                }
                if let note = PlanEditing.previousDefaultNote(for: assetClass, in: plan.assumptions, locale: locale) {
                    HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                        Text(note)
                            .foregroundStyle(Palette.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: Metrics.xs)
                        Button("Use Default") { plan.assumptions.useDefaultReturn(for: assetClass) }
                            .buttonStyle(.borderless)
                            .disabled(!library.canEdit)
                            .accessibilityLabel("Use the default return for \(name)")
                    }
                    .font(.caption)
                }
            }
            Text(PlanEditing.returnsExplanation)
                .font(.caption)
                .foregroundStyle(Palette.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
            Text("Income yield")
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
            ForEach(incomeClasses, id: \.self) { assetClass in
                let name = PlanIssueText.assetClassName(assetClass.rawValue)
                HStack(spacing: Metrics.xs) {
                    Text(name)
                    Spacer(minLength: Metrics.s)
                    PlanNumberField("\(name) income yield", value: $plan.assumptions[planIncomeYield: assetClass],
                                    kind: .percent, prompt: "–", isOptional: true)
                        .frame(maxWidth: 56)
                    Text("%")
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            Text(PlanEditing.incomeYieldExplanation)
                .font(.caption)
                .foregroundStyle(Palette.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            PlanNumberRow("Unrealised gains, estimate", value: $plan.portfolio.unrealizedGainShare, kind: .percent,
                          unit: "%", prompt: "–")
            Text("For holdings with no purchase cost recorded: the share of their value that's gain.")
                .font(.caption)
                .foregroundStyle(Palette.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
            if !accounts.isEmpty {
                Text("Accounts in this plan")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                ForEach(accounts) { account in
                    Toggle(account.name, isOn: $plan.portfolio[planIncludes: account.id])
                }
            }
        }
        .font(.subheadline)
    }
}

// MARK: - Simulation

/// The number of runs, the confidence level and the random seed.
struct PlanSimulationEditor: View {
    @Binding var plan: PlanDocument
    @Environment(\.locale) private var locale

    private var runChoices: [Int] {
        Array(Set([500, 1_000, 2_000, 5_000, plan.simulation.effectiveRuns])).sorted()
    }

    private var confidenceChoices: [Decimal] {
        let standard = ["0.8", "0.85", "0.9", "0.95"].compactMap { Decimal(string: $0) }
        return Array(Set(standard + [plan.simulation.effectiveConfidence])).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Picker("Runs", selection: $plan.simulation.planRuns) {
                ForEach(runChoices, id: \.self) { runs in
                    Text(AmountFormat.number(Decimal(runs), locale: locale)).tag(runs)
                }
            }
            Picker("Confidence for a “yes”", selection: $plan.simulation.planConfidence) {
                ForEach(confidenceChoices, id: \.self) { share in
                    Text(AmountFormat.percent(share, digits: 0, locale: locale)).tag(share)
                }
            }
            Text("A “yes” needs success \(GlanceText.inSimulatedFutures(plan.simulation.effectiveConfidence.doubleValue)).")
                .font(.caption)
                .foregroundStyle(Palette.mutedInk)
            PlanNumberRow("Random seed", value: $plan.simulation.planSeed, kind: .integer)
            Text("Every run of this plan uses the same random draws, so differences come from your changes.")
                .font(.caption)
                .foregroundStyle(Palette.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
    }
}
