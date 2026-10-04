import Model
import Planner
import SwiftUI
import TaxKit

/// Inputs (UI.md, "Inputs"): a collapsible card per section of the plan
/// file, each with a one-line summary, so the whole plan fits on one screen
/// when collapsed. Issues show on the card they concern. Edits are saved as
/// you go and the results follow.
struct PlanInputsView: View {
    let session: PlanSession
    /// In the Mac inspector: a narrower column with its own header.
    var isInspector = false

    @Environment(LibraryStore.self) private var library
    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.baseCurrency) private var baseCurrency
    @Environment(\.locale) private var locale
    @State private var expanded: [PlanInputSection: Bool] = [:]
    @State private var editing: PlanEditTarget?

    var body: some View {
        @Bindable var session = session
        if let plan = session.plan {
            let issues = session.inputIssues
            let summaries = PlanInputSummaries(plan: plan, library: library.library, registry: AppTaxRegistry.standard,
                                               currency: baseCurrency, hidesAmounts: hidesAmounts, locale: locale)
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.s) {
                    if isInspector {
                        PlanInputsHeader(issues: issues)
                    }
                    if !session.canEdit {
                        StatusBanner(.info, "Read-only", message: "This library can't be changed here.")
                    }
                    ForEach(PlanInputSection.allCases) { section in
                        PlanSectionCard(section: section, summary: summaries.summary(for: section),
                                        issues: issues.issues(for: section),
                                        listedIssues: issues.cardIssues(for: section, in: plan),
                                        isExpanded: $expanded[planFlag: section]) {
                            PlanSectionEditor(section: section, plan: $session.editablePlan, summaries: summaries,
                                              issues: issues, editing: $editing)
                                .disabled(!session.canEdit)
                        }
                    }
                }
                .padding(isInspector ? Metrics.m : Metrics.l)
                .frame(maxWidth: isInspector ? .infinity : Metrics.readableWidth)
                .frame(maxWidth: .infinity)
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
}

/// "Inputs · ⚠︎ 1 warning", at the top of the Mac inspector.
struct PlanInputsHeader: View {
    let issues: PlanInputIssues

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Inputs")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if issues.errorCount > 0 {
                Label(Self.count(issues.errorCount, "error"), systemImage: "xmark.octagon.fill")
                    .foregroundStyle(Palette.critical)
                    .font(.caption)
            } else if issues.warningCount > 0 {
                Label(Self.count(issues.warningCount, "warning"), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.warning)
                    .font(.caption)
            }
        }
        .padding(.horizontal, Metrics.xs)
    }

    /// "1 warning", "2 warnings".
    private static func count(_ count: Int, _ noun: String) -> String {
        count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
    }
}

/// Which item a sheet edits: its position (the list's count for a new
/// one) and a copy taken when the sheet opened.
enum PlanEditTarget: Hashable, Identifiable {
    case work(index: Int, phase: WorkPhase)
    case pension(index: Int, pension: PlanPension)
    case contribution(index: Int, contribution: PlanContribution)
    case event(index: Int, event: PlanEvent)
    case residence(index: Int, residence: PlanResidence)
    case overlay(index: Int, overlay: PlanOverlay)

    var id: String {
        switch self {
        case .work(let index, _): "work-\(index)"
        case .pension(let index, _): "pension-\(index)"
        case .contribution(let index, _): "contribution-\(index)"
        case .event(let index, _): "event-\(index)"
        case .residence(let index, _): "residence-\(index)"
        case .overlay(let index, _): "overlay-\(index)"
        }
    }
}

/// The editor inside one card.
struct PlanSectionEditor: View {
    let section: PlanInputSection
    @Binding var plan: PlanDocument
    let summaries: PlanInputSummaries
    let issues: PlanInputIssues
    @Binding var editing: PlanEditTarget?

    var body: some View {
        switch section {
        case .you:
            PlanYouEditor(plan: $plan)
        case .work:
            PlanWorkList(plan: plan, summaries: summaries, issues: issues, editing: $editing)
        case .spending:
            PlanSpendingEditor(plan: $plan)
        case .pensions:
            PlanPensionList(plan: plan, summaries: summaries, issues: issues, editing: $editing)
        case .contributions:
            PlanContributionList(plan: plan, summaries: summaries, issues: issues, editing: $editing)
        case .events:
            PlanEventList(plan: plan, summaries: summaries, issues: issues, editing: $editing)
        case .taxes:
            PlanTaxesEditor(plan: $plan, summaries: summaries, issues: issues, editing: $editing)
        case .assumptions:
            PlanAssumptionsEditor(plan: $plan)
        case .targetMix:
            PlanTargetMixEditor(plan: $plan)
        case .simulation:
            PlanSimulationEditor(plan: $plan)
        case .withdrawals:
            PlanWithdrawalsEditor(plan: $plan)
        }
    }
}

// MARK: - You

/// Birth date and citizenships (from the library), retirement age, the
/// plan's end and its currency.
///
/// The birth date is written only when you pick one, from the picker's own
/// setter (`YouSettings`): opening the card writes nothing, and without a
/// birth date it says "Not set" rather than assuming one. Citizenships are
/// written when you add or remove one.
struct PlanYouEditor: View {
    @Binding var plan: PlanDocument
    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale
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
            CitizenshipRows(settings: library.settings) { change in
                guard library.canEdit else { return }
                try? library.updateSettings { $0 = change($0) }
            }
            Text(YouSettings.citizenshipExplanation)
                .font(.caption)
                .foregroundStyle(Palette.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Toggle("Retire as early as possible", isOn: $plan.planRetiresEarliest)
            if !plan.planRetiresEarliest {
                Stepper("Retire at \(plan.planRetirementAge)", value: $plan.planRetirementAge, in: 30...85)
            }
            Stepper("Plan to age \(plan.planEndAge)", value: $plan.planEndAge, in: 70...110)
            Divider()
            PlanCurrencyEditor(plan: $plan)
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

/// The plan's currency: the library's by default, a currency the library
/// has exchange rates for, or another code typed in. Amounts and results
/// are in it; your accounts are converted at the rates on the start date.
struct PlanCurrencyEditor: View {
    @Binding var plan: PlanDocument
    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale
    @State private var typed = ""

    var body: some View {
        let base = library.settings.baseCurrency
        VStack(alignment: .leading, spacing: Metrics.s) {
            Picker("Currency", selection: $plan.currency) {
                Text(PlanMoney.libraryChoiceTitle(base)).tag(CurrencyCode?.none)
                ForEach(PlanMoney.currencyChoices(for: plan, library: library.library), id: \.self) { code in
                    Text(CurrencyChoices.name(of: code, locale: locale)).tag(Optional(code))
                }
            }
            LabeledContent("Another currency") {
                TextField("Another currency", text: $typed, prompt: Text("e.g. SGD"))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80)
                    .onSubmit {
                        guard let code = PlanMoney.code(from: typed) else { return }
                        plan.currency = PlanMoney.choosing(code, base: base)
                        typed = ""
                    }
            }
            Text("Every amount in the plan, and its results, are in this currency in today's money. Your accounts "
                + "are converted at the exchange rates on the plan's start date.")
                .font(.caption)
                .foregroundStyle(Palette.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Spending

/// Spending while working and in retirement, and the later phases' factors.
struct PlanSpendingEditor: View {
    @Binding var plan: PlanDocument

    private static let fallback = SpendingPhase(fromAge: 75, factor: 1)

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            PlanNumberRow("While working", value: $plan.spending.working, unit: "/yr")
            PlanNumberRow("In retirement", value: $plan.spending.retired, unit: "/yr")
            if !plan.spending.phases.isEmpty {
                Text("Later in retirement, a share of that")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
            }
            ForEach(plan.spending.phases.indices, id: \.self) { index in
                HStack(spacing: Metrics.s) {
                    Stepper("From \(plan.spending.phases[planSafe: index, default: Self.fallback].fromAge)",
                            value: $plan.spending.phases[planSafe: index, default: Self.fallback].fromAge, in: 40...110)
                    PlanNumberField("Share of spending",
                                    value: $plan.spending.phases[planSafe: index, default: Self.fallback].factor,
                                    kind: .percent)
                        .frame(maxWidth: 64)
                    Text("%")
                        .foregroundStyle(Palette.secondaryInk)
                    Button {
                        plan.spending.phases = PlanEditing.removing(at: index, from: plan.spending.phases)
                    } label: {
                        Label("Remove", systemImage: "minus.circle")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button {
                plan.spending.phases.append(PlanEditing.newSpendingPhase(in: plan))
            } label: {
                Label("Add a later phase", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            Divider()
            PlanFlexibleSpendingEditor(spending: $plan.spending)
        }
        .font(.subheadline)
    }
}

/// Flexible spending (UI.md, "Inputs"): a switch, and when it's on, how
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

// MARK: - Simulation and withdrawals

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

/// How money is drawn in retirement.
struct PlanWithdrawalsEditor: View {
    @Binding var plan: PlanDocument

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            LabeledContent("Strategy", value: "Fixed real spending")
            Text("You spend what the plan says, adjusted for inflation, and the portfolio absorbs market swings. "
                + "Cash above the buffer goes first, then investments, then pension money once it opens.")
                .font(.caption)
                .foregroundStyle(Palette.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
            PlanNumberRow("Cash buffer", value: $plan.withdrawals.cashBuffer, prompt: "0")
        }
        .font(.subheadline)
    }
}

#Preview("Inputs") {
    PlanPreviewHost(model: AppModel.preview(planEngine: PlanPreviewEngine())) { session in
        PlanInputsView(session: session)
    }
}
