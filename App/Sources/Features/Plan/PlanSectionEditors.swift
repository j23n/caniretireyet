import Model
import Planner
import SwiftUI

// The editors of the plan's inputs: those of *All assumptions…*'s cards
// (UI.md, "The editors"), and the pieces the chapters edit in place.

/// Which item a sheet edits: its position (the list's count for a new
/// one) and a copy taken when the sheet opened.
enum PlanEditTarget: Hashable, Identifiable {
    case work(index: Int, phase: WorkPhase)
    case pension(index: Int, pension: PlanPension)
    case contribution(index: Int, contribution: PlanContribution)
    case event(index: Int, event: PlanEvent)

    var id: String {
        switch self {
        case .work(let index, _): "work-\(index)"
        case .pension(let index, _): "pension-\(index)"
        case .contribution(let index, _): "contribution-\(index)"
        case .event(let index, _): "event-\(index)"
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
        case .work, .spending, .pensions, .contributions, .events:
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

// MARK: - Spending

/// A later phase of retirement spending: from an age, a share of what the
/// plan spends in retirement, with a button that removes it.
struct PlanSpendingPhaseRow: View {
    @Binding var phases: [SpendingPhase]
    let index: Int

    private static let fallback = SpendingPhase(fromAge: 75, factor: 1)

    var body: some View {
        HStack(spacing: Metrics.s) {
            Stepper("From \(phases[planSafe: index, default: Self.fallback].fromAge)",
                    value: $phases[planSafe: index, default: Self.fallback].fromAge, in: 40...110)
            PlanNumberField("Share of spending", value: $phases[planSafe: index, default: Self.fallback].factor,
                            kind: .percent)
                .frame(maxWidth: 64)
            Text("%")
                .foregroundStyle(Palette.secondaryInk)
            Button {
                phases = PlanEditing.removing(at: index, from: phases)
            } label: {
                Label("Remove", systemImage: "minus.circle")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
        }
    }
}

/// Flexible spending (UI.md, "The editors"): a switch, and when it's on, how
/// much a cut takes, the floor (also in money), and the guardrails, folded
/// away. Fields left empty take the defaults their prompts show.
struct PlanFlexibleSpendingEditor: View {
    @Binding var spending: PlanSpending
    @State private var showsGuardrails = false

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Toggle("Flexible spending", isOn: $spending.planFlexibleOn)
            Text(PlanEditing.flexibleExplanation)
                .font(.caption)
                .foregroundStyle(Palette.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
            if spending.planFlexibleOn {
                PlanNumberRow("Cut by", value: $spending.planFlexibleCut, kind: .percent, unit: "%", prompt: "10")
                PlanNumberRow("Never below", value: $spending.planFlexibleFloor, kind: .percent, unit: "%",
                              prompt: "80")
                HStack(spacing: Metrics.xs) {
                    Text("of the plan's spending:")
                    AmountText(spending.planFlexibleFloorAmount)
                    Text("/yr")
                }
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
                DisclosureGroup("Guardrails", isExpanded: $showsGuardrails) {
                    VStack(alignment: .leading, spacing: Metrics.s) {
                        PlanNumberRow("Cut when it rises by", value: $spending.planFlexibleUpperGuardrail,
                                      kind: .percent, unit: "%", prompt: "20")
                        PlanNumberRow("Restore when it falls by", value: $spending.planFlexibleLowerGuardrail,
                                      kind: .percent, unit: "%", prompt: "20")
                        Text(PlanEditing.guardrailsExplanation)
                            .font(.caption)
                            .foregroundStyle(Palette.mutedInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

// MARK: - Assumptions

/// Inflation, returns and volatility by asset class, and the portfolio's
/// estimate for unrecorded gains and the accounts it leaves out.
struct PlanAssumptionsEditor: View {
    @Binding var plan: PlanDocument
    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale

    private struct AssetRow: Identifiable {
        var assetClass: AssetClass
        var name: String
        var id: String { assetClass.rawValue }
    }

    private static let rows: [AssetRow] = [
        AssetRow(assetClass: .equity, name: "Equity"), AssetRow(assetClass: .bonds, name: "Bonds"),
        AssetRow(assetClass: .cash, name: "Cash"), AssetRow(assetClass: .gold, name: "Gold"),
        AssetRow(assetClass: .crypto, name: "Crypto"),
    ]

    /// The classes whose income yield can be set: those that pay income
    /// (equity, bonds), and any other the plan gives one.
    private var incomeRows: [AssetRow] {
        Self.rows.filter { row in
            PlanEditing.incomeYieldClasses.contains(row.assetClass)
                || plan.assumptions.returnAssumption(for: row.assetClass)?.incomeYield != nil
        }
    }

    var body: some View {
        let accounts = PlanEditing.excludableAccounts(in: library.library)
        VStack(alignment: .leading, spacing: Metrics.s) {
            PlanNumberRow("Inflation", value: $plan.assumptions.inflation, kind: .percent, unit: "%", prompt: "2")
            Text("Real return: mean · median · volatility")
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
            ForEach(Self.rows) { row in
                HStack(spacing: Metrics.xs) {
                    Text(row.name)
                    Spacer(minLength: Metrics.s)
                    PlanNumberField("\(row.name) mean real return",
                                    value: $plan.assumptions[planReal: row.assetClass], kind: .percent)
                        .frame(maxWidth: 52)
                    Text("% ·")
                        .foregroundStyle(Palette.secondaryInk)
                    PlanNumberField("\(row.name) median real return",
                                    value: $plan.assumptions[planMedianReal: row.assetClass], kind: .percent)
                        .frame(maxWidth: 52)
                    Text("% ·")
                        .foregroundStyle(Palette.secondaryInk)
                    PlanNumberField("\(row.name) volatility",
                                    value: $plan.assumptions[planVolatility: row.assetClass], kind: .percent)
                        .frame(maxWidth: 52)
                    Text("%")
                        .foregroundStyle(Palette.secondaryInk)
                }
                if let note = PlanEditing.previousDefaultNote(for: row.assetClass, in: plan.assumptions,
                                                              locale: locale) {
                    HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                        Text(note)
                            .foregroundStyle(Palette.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: Metrics.xs)
                        Button("Use Default") { plan.assumptions.useDefaultReturn(for: row.assetClass) }
                            .buttonStyle(.borderless)
                            .disabled(!library.canEdit)
                            .accessibilityLabel("Use the default return for \(row.name)")
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
            ForEach(incomeRows) { row in
                HStack(spacing: Metrics.xs) {
                    Text(row.name)
                    Spacer(minLength: Metrics.s)
                    PlanNumberField("\(row.name) income yield", value: $plan.assumptions[planIncomeYield: row.assetClass],
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
            Text("A “yes” needs success \(PlanResultsText.confidence(plan.simulation.effectiveConfidence.doubleValue)).")
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
