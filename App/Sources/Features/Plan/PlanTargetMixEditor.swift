import Model
import Planner
import SwiftUI

/// The Target mix card (UI.md, "Target mix"): today's mix of the money you
/// can draw next to the mix the plan rebalances it to, each class's
/// median return, a running total that must reach 100%, and changes with
/// age. "Today's mix" writes nothing; edits are saved as you type. The
/// logic is in ``PlanTargetMixModel`` and the `plan…` subscripts.
struct PlanTargetMixEditor: View {
    @Binding var plan: PlanDocument
    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale

    var body: some View {
        let model = PlanTargetMixModel(plan: plan, library: library.library)
        let choosing = plan.portfolio.choosesTargetMix
        VStack(alignment: .leading, spacing: Metrics.s) {
            Text(PlanTargetMixModel.explanation)
                .font(.caption)
                .foregroundStyle(Palette.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
            Picker("Rebalance to", selection: $plan.portfolio[planChoosesMix: model.suggestion]) {
                Text("Today's mix").tag(false)
                Text("A mix I choose").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            PlanTargetMixTable(plan: $plan, model: model, choosing: choosing)
            if choosing {
                if plan.portfolio.targetMix == nil {
                    PlanTargetMixNote(text: "Until the first change below, each account keeps its own mix. Type a "
                        + "target to choose one from today.")
                } else {
                    PlanTargetMixTotal(mix: plan.portfolio.targetMix, model: model, comparedWithToday: true)
                }
                Divider()
                PlanTargetMixSteps(plan: $plan, model: model)
            } else {
                PlanTargetMixNote(text: PlanTargetMixModel.todaysMixExplanation)
                if let growth = model.todaysGrowth {
                    PlanTargetMixNote(text: "Today's mix grows at a median of "
                        + AmountFormat.percent(growth, locale: locale) + " a year, rebalanced every year.")
                }
            }
            PlanTargetMixNote(text: PlanTargetMixModel.wrappersNote)
        }
        .font(.subheadline)
    }
}

/// A caption line that wraps.
private struct PlanTargetMixNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Palette.mutedInk)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Per class: today's share of the money you can draw (and of all plan
/// assets below it), the target to type, and the median return.
private struct PlanTargetMixTable: View {
    @Binding var plan: PlanDocument
    let model: PlanTargetMixModel
    let choosing: Bool
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Metrics.m, verticalSpacing: Metrics.xs) {
                GridRow {
                    Text("Class")
                    Text("Today")
                        .gridColumnAlignment(.trailing)
                    if choosing {
                        Text("Target")
                            .gridColumnAlignment(.trailing)
                    }
                    Text("Median")
                        .gridColumnAlignment(.trailing)
                }
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
                .accessibilityHidden(true)
                ForEach(model.rows) { row in
                    GridRow {
                        Text(row.name)
                        today(row)
                        if choosing {
                            HStack(spacing: 2) {
                                PlanNumberField("\(row.name) target, percent",
                                                value: $plan.portfolio[planTargetShare: row.assetClass],
                                                kind: .percent, prompt: "0", isOptional: true)
                                    .frame(maxWidth: 56)
                                Text("%")
                                    .foregroundStyle(Palette.secondaryInk)
                                    .accessibilityHidden(true)
                            }
                        }
                        Text(row.median.map { AmountFormat.percent($0, locale: locale) } ?? "–")
                            .monospacedDigit()
                            .foregroundStyle(Palette.secondaryInk)
                            .accessibilityLabel(row.median.map {
                                "\(row.name) median return \(AmountFormat.percent($0, locale: locale)) a year"
                            } ?? "\(row.name): no return assumption")
                    }
                }
            }
            PlanTargetMixNote(text: PlanTargetMixModel.todayNote)
        }
    }

    /// "46%" over "44% of all".
    private func today(_ row: PlanTargetMixModel.Row) -> some View {
        let ordinary = row.ordinaryShare.map { AmountFormat.percent($0, digits: 0, locale: locale) } ?? "–"
        let all = row.allShare.map { AmountFormat.percent($0, digits: 0, locale: locale) } ?? "–"
        return VStack(alignment: .trailing, spacing: 0) {
            Text(ordinary)
                .monospacedDigit()
            Text("\(all) of all")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Palette.mutedInk)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.name) today: \(ordinary) of the money you can draw, \(all) of all plan assets")
    }
}

/// "Total 95%" with what it needs, and how the mix grows.
private struct PlanTargetMixTotal: View {
    let mix: AssetMix?
    let model: PlanTargetMixModel
    var comparedWithToday = false
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let problem = PlanTargetMixModel.problem(mix, locale: locale) {
                PlanIssueLine(message: PlanTargetMixModel.totalText(mix, locale: locale) + ". " + problem, isError: true)
            } else {
                Label(PlanTargetMixModel.totalText(mix, locale: locale), systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
            }
            if let growth = model.growthText(of: mix, comparedWithToday: comparedWithToday, locale: locale) {
                PlanTargetMixNote(text: growth)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The changes with age: a card per change (side by side when there's
/// room), each from an age or from retirement, with its mix and total.
private struct PlanTargetMixSteps: View {
    @Binding var plan: PlanDocument
    let model: PlanTargetMixModel

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Text("Changes with age")
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
                .accessibilityAddTraits(.isHeader)
            if plan.portfolio.targetMixByAge.isEmpty {
                PlanTargetMixNote(text: "For example 60% equity from retirement, then 40% from 75. The year a change "
                    + "starts, rebalancing sells what the new mix doesn't want, with tax on gains.")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: Metrics.s, alignment: .top)],
                      alignment: .leading, spacing: Metrics.s) {
                ForEach(plan.portfolio.targetMixByAge.indices, id: \.self) { index in
                    PlanTargetMixStepCard(plan: $plan, model: model, index: index)
                }
            }
            Button {
                plan.portfolio.targetMixByAge.append(PlanTargetMixModel.newStep(in: plan, currentAge: model.currentAge))
            } label: {
                Label("Add a change with age", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
    }
}

/// One change with age: when it starts, its mix, and its total.
private struct PlanTargetMixStepCard: View {
    @Binding var plan: PlanDocument
    let model: PlanTargetMixModel
    let index: Int

    var body: some View {
        let steps = plan.portfolio.targetMixByAge
        let step = steps.indices.contains(index) ? steps[index] : nil
        let range = model.ageRange(forStep: index)
        let fallback = min(max(model.retirementAge, range.lowerBound), range.upperBound)
        let atRetirement = step?.fromAge == .retirement
        VStack(alignment: .leading, spacing: Metrics.xs) {
            HStack {
                Text(step.map { PlanTargetMixModel.title(of: $0.fromAge) } ?? "")
                    .font(.subheadline.weight(.semibold))
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
            Picker("Starts", selection: $plan.portfolio[planStepAtRetirement: index, fallbackAge: fallback]) {
                Text("At an age").tag(false)
                Text("At retirement").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if atRetirement {
                PlanTargetMixNote(text: "The year you stop working, whatever age the plan finds"
                    + (plan.retirement.age.age.map { ": \($0) in this plan." } ?? "."))
            } else {
                Stepper("From \(plan.portfolio[planStepAge: index, fallback: fallback])",
                        value: $plan.portfolio[planStepAge: index, fallback: fallback], in: range)
            }
            if let note = model.startedNote(step: index), let age = model.currentAge {
                PlanTargetMixNote(text: note)
                Button("Make it the target mix") { plan.portfolio.foldTargetMixSteps(passedBy: age) }
                    .buttonStyle(.borderless)
            }
            ForEach(model.rows) { row in
                HStack(spacing: Metrics.xs) {
                    Text(row.name)
                    Spacer(minLength: Metrics.s)
                    PlanNumberField("\(row.name), \(step.map { PlanTargetMixModel.title(of: $0.fromAge) } ?? ""), percent",
                                    value: $plan.portfolio[planStepShare: index, row.assetClass], kind: .percent,
                                    prompt: "0", isOptional: true)
                        .frame(maxWidth: 56)
                    Text("%")
                        .foregroundStyle(Palette.secondaryInk)
                        .accessibilityHidden(true)
                }
            }
            PlanTargetMixTotal(mix: step?.mix, model: model)
        }
        .padding(Metrics.s)
        .background(Palette.page, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

