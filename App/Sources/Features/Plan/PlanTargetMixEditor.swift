import Model
import Planner
import SwiftUI

/// The Target mix sheet's sections (UI.md, "Target mix"), for a grouped
/// `Form`: whether the plan rebalances to today's mix or one you choose,
/// each class's shares today, its target and its median return, the
/// running total that must reach 100%, and a section per change with age.
/// "Today's mix" writes nothing; edits are saved as you type. The logic is
/// in ``PlanTargetMixModel`` and the `plan…` subscripts.
struct PlanTargetMixEditor: View {
    @Binding var plan: PlanDocument
    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale

    var body: some View {
        let model = PlanTargetMixModel(plan: plan, library: library.library)
        let choosing = plan.portfolio.choosesTargetMix
        let targetMix = plan.portfolio.targetMix
        Section {
            Picker("Rebalance to", selection: $plan.portfolio[planChoosesMix: model.suggestion]) {
                Text("Today's mix").tag(false)
                Text("A mix I choose").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } header: {
            Text("Rebalance to")
        } footer: {
            PlanTargetMixFooter {
                Text(PlanTargetMixModel.explanation)
                if !choosing {
                    Text(PlanTargetMixModel.todaysMixExplanation)
                    if let growth = model.todaysGrowth {
                        Text("Today's mix grows at a median of " + AmountFormat.percent(growth, locale: locale)
                            + " a year, rebalanced every year.")
                    }
                }
            }
        }
        Section {
            ForEach(model.rows) { row in
                PlanTargetMixClassRow(plan: $plan, row: row, choosing: choosing)
            }
            if choosing, targetMix != nil {
                PlanTargetMixTotal(mix: targetMix)
            }
        } header: {
            Text(choosing ? "Target mix" : "Today's mix")
        } footer: {
            PlanTargetMixFooter {
                if choosing {
                    if targetMix == nil {
                        Text("Until the first change below, each account keeps its own mix. Type a target to "
                            + "choose one from today.")
                    } else if let growth = model.growthText(of: targetMix, comparedWithToday: true, locale: locale) {
                        Text(growth)
                    }
                }
                Text(PlanTargetMixModel.todayNote)
                if !choosing {
                    Text(PlanTargetMixModel.wrappersNote)
                }
            }
        }
        if choosing {
            ForEach(plan.portfolio.targetMixByAge.indices, id: \.self) { index in
                PlanTargetMixStepSection(plan: $plan, model: model, index: index)
            }
            Section {
                Button {
                    plan.portfolio.targetMixByAge.append(PlanTargetMixModel.newStep(in: plan,
                                                                                    currentAge: model.currentAge))
                } label: {
                    Label("Add a change with age", systemImage: "plus")
                }
            } footer: {
                PlanTargetMixFooter {
                    if plan.portfolio.targetMixByAge.isEmpty {
                        Text("For example 60% equity from retirement, then 40% from 75. The year a change starts, "
                            + "rebalancing sells what the new mix doesn't want, with tax on gains.")
                    }
                    Text(PlanTargetMixModel.wrappersNote)
                }
            }
        }
    }
}

/// A section's footer of several paragraphs.
private struct PlanTargetMixFooter<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            content
        }
    }
}

/// A target share typed as a percentage, with "%" after it. The same width
/// in every section, growing with the text size, so the fields line up.
private struct PlanTargetMixPercentField: View {
    let title: String
    @Binding var value: Decimal?
    @ScaledMetric(relativeTo: .body) private var width: CGFloat = 64

    init(_ title: String, value: Binding<Decimal?>) {
        self.title = title
        _value = value
    }

    var body: some View {
        HStack(spacing: Metrics.xs) {
            PlanNumberField(title, value: $value, kind: .percent, prompt: "0", isOptional: true)
                .frame(width: width)
            Text("%")
                .foregroundStyle(Palette.secondaryInk)
                .accessibilityHidden(true)
        }
    }
}

/// One class: its name, with today's shares and its median return under
/// it, and its target when you choose the mix.
private struct PlanTargetMixClassRow: View {
    @Binding var plan: PlanDocument
    let row: PlanTargetMixModel.Row
    let choosing: Bool
    @Environment(\.locale) private var locale

    var body: some View {
        LabeledContent {
            if choosing {
                PlanTargetMixPercentField("\(row.name) target, percent",
                                          value: $plan.portfolio[planTargetShare: row.assetClass])
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                Group {
                    today
                    median
                }
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Palette.secondaryInk)
            }
        }
    }

    /// "Today 46% · 44% of all".
    private var today: some View {
        let ordinary = row.ordinaryShare.map { AmountFormat.percent($0, digits: 0, locale: locale) } ?? "–"
        let all = row.allShare.map { AmountFormat.percent($0, digits: 0, locale: locale) } ?? "–"
        return Text("Today \(ordinary) · \(all) of all")
            .accessibilityLabel("\(row.name) today: \(ordinary) of the money you can draw, \(all) of all plan assets")
    }

    /// "Median 5.0% a year".
    private var median: some View {
        let percent = row.median.map { AmountFormat.percent($0, locale: locale) }
        return Text(percent.map { "Median \($0) a year" } ?? "No return assumption")
            .accessibilityLabel(percent.map { "\(row.name) median return \($0) a year" }
                ?? "\(row.name): no return assumption")
    }
}

/// "✓ Total 100%", or what the total needs.
private struct PlanTargetMixTotal: View {
    let mix: AssetMix?
    @Environment(\.locale) private var locale

    var body: some View {
        if let problem = PlanTargetMixModel.problem(mix, locale: locale) {
            PlanIssueLine(message: PlanTargetMixModel.totalText(mix, locale: locale) + ". " + problem, isError: true)
        } else {
            Label(PlanTargetMixModel.totalText(mix, locale: locale), systemImage: "checkmark.circle")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
        }
    }
}

/// One change with age, as a section: its title and remove button, when
/// it starts, its mix and its total, and its growth in the footer.
private struct PlanTargetMixStepSection: View {
    @Binding var plan: PlanDocument
    let model: PlanTargetMixModel
    let index: Int
    @Environment(\.locale) private var locale

    var body: some View {
        let steps = plan.portfolio.targetMixByAge
        let step = steps.indices.contains(index) ? steps[index] : nil
        let title = step.map { PlanTargetMixModel.title(of: $0.fromAge) } ?? ""
        let range = model.ageRange(forStep: index)
        let fallback = min(max(model.retirementAge, range.lowerBound), range.upperBound)
        Section {
            Picker("Starts", selection: $plan.portfolio[planStepAtRetirement: index, fallbackAge: fallback]) {
                Text("At an age").tag(false)
                Text("At retirement").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if step?.fromAge == .retirement {
                Text("The year you stop working, whatever age the plan finds"
                    + (plan.retirement.age.age.map { ": \($0) in this plan." } ?? "."))
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            } else {
                Stepper("From \(plan.portfolio[planStepAge: index, fallback: fallback])",
                        value: $plan.portfolio[planStepAge: index, fallback: fallback], in: range)
            }
            if let note = model.startedNote(step: index), let age = model.currentAge {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                Button("Make it the target mix") { plan.portfolio.foldTargetMixSteps(passedBy: age) }
            }
            ForEach(model.rows) { row in
                LabeledContent {
                    PlanTargetMixPercentField("\(row.name), \(title), percent",
                                              value: $plan.portfolio[planStepShare: index, row.assetClass])
                } label: {
                    Text(row.name)
                }
            }
            PlanTargetMixTotal(mix: step?.mix)
        } header: {
            HStack {
                Text(title)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    plan.portfolio.targetMixByAge = PlanEditing.removing(at: index, from: plan.portfolio.targetMixByAge)
                } label: {
                    Label("Remove this change", systemImage: "minus.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
            }
        } footer: {
            if let growth = model.growthText(of: step?.mix, locale: locale) {
                Text(growth)
            }
        }
    }
}

/// The Target mix card of *Assumptions…*: the mix and its changes with age
/// in words, and a button that opens the Target mix sheet.
struct PlanTargetMixOverview: View {
    let portfolio: PlanPortfolio
    let onEdit: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Text(PlanTargetMixModel.explanation)
                .font(.caption)
                .foregroundStyle(Palette.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
            line("Rebalance to", PlanTargetMixModel.mixSummary(portfolio.targetMix, locale: locale))
            ForEach(portfolio.targetMixByAge.indices, id: \.self) { index in
                let step = portfolio.targetMixByAge[index]
                line(PlanTargetMixModel.title(of: step.fromAge),
                     PlanTargetMixModel.mixSummary(step.mix, locale: locale))
            }
            Button("Edit Target Mix…", action: onEdit)
                .buttonStyle(.borderless)
        }
        .font(.subheadline)
    }

    private func line(_ title: String, _ mix: String) -> some View {
        LabeledContent(title) {
            Text(mix)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Palette.secondaryInk)
        }
    }
}

#Preview("Target mix") {
    @Previewable @State var plan = PreviewLibrary.library.plans["part-time-from-50"]!
    PlanTargetMixSheet(plan: $plan)
        .previewEnvironment()
}
