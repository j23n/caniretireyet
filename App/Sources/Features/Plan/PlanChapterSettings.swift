import Model
import Planner
import SwiftUI

// A chapter's settings (UI.md, "The plan"): the words only read, and the
// settings are where the plan changes. Every input that starts in a
// chapter is one row there, with its value (amounts a month, as the words
// say them); a row opens the value's small editor in a popover, or the
// item's sheet.

/// One setting: what it is, its value, and what a tap opens.
struct PlanSettingRow: Hashable, Identifiable {
    /// What a tap opens: the value's small editor, or the item's sheet (or the target mix's).
    enum Opens: Hashable {
        case editor(PlanToken)
        case sheet(PlanToken)
    }

    /// The colour of a row's icon, by what it is.
    enum Kind: Hashable {
        case work, spending, saving, event, pension, retirement, mix, end

        var color: Color {
            switch self {
            case .work: Palette.mutedInk
            case .spending: Palette.orange
            case .saving: Palette.accent
            case .event: Palette.green
            case .pension: Palette.violet
            case .retirement: Palette.red
            case .mix: Palette.aqua
            case .end: Palette.mutedInk
            }
        }
    }

    var id: String
    /// An SF Symbol.
    var symbol: String
    var kind: Kind
    var title: String
    var subtitle: String?
    var value: String
    var opens: Opens
    var issues: [PlanIssue] = []
}

enum PlanChapterSettings {
    /// A row for each of `items`, in their order: what starts in a chapter,
    /// or the inputs outside the plan's years. Amounts are a month's, in
    /// today's money; one-offs are their amount.
    static func rows(for items: [PlanChapter.Item], plan: PlanDocument, model: PlanChaptersModel,
                     issues: PlanInputIssues, words: PlanWords) -> [PlanSettingRow] {
        items.flatMap { item -> [PlanSettingRow] in
            switch item {
            case .retirement:
                let earliest = plan.retirement.age == .earliest
                return [PlanSettingRow(
                    id: "retirement", symbol: "figure.walk", kind: .retirement, title: "Stop working",
                    subtitle: earliest ? "At \(model.retirementAge), in \(model.retirementYear)"
                        : "In \(model.retirementYear)",
                    value: earliest ? "As early as you can" : "At \(plan.planRetirementAge)",
                    opens: .editor(.retirementAge))]
            case .workingSpending:
                return [PlanSettingRow(id: "working-spending", symbol: "cart", kind: .spending, title: "Spending",
                                       subtitle: "While working", value: words.monthly(plan.spending.working),
                                       opens: .editor(.workingSpending))]
            case .retiredSpending:
                let flexible = plan.spending.flexibleRule.map { "Never below \(words.percent($0.effectiveFloor))" }
                return [
                    PlanSettingRow(id: "retired-spending", symbol: "cart", kind: .spending, title: "Spending",
                                   subtitle: "In retirement", value: words.monthly(plan.spending.retired),
                                   opens: .editor(.retiredSpending)),
                    PlanSettingRow(id: "flexible-spending", symbol: "arrow.down.right", kind: .spending,
                                   title: "Flexible spending", subtitle: "Spending less after bad years",
                                   value: flexible ?? "Off", opens: .editor(.flexibleSpending)),
                ]
            case .spendingPhase(let index):
                guard plan.spending.phases.indices.contains(index) else { return [] }
                let phase = plan.spending.phases[index]
                return [PlanSettingRow(id: "spending-phase-\(index)", symbol: "cart", kind: .spending,
                                       title: "Spending from \(phase.fromAge)",
                                       subtitle: "\(words.percent(phase.factor)) of spending in retirement",
                                       value: words.monthly(plan.spending.retired * phase.factor),
                                       opens: .editor(.spendingPhase(index)))]
            case .work(let index):
                guard plan.work.indices.contains(index) else { return [] }
                let phase = plan.work[index]
                var subtitle = PlanWorkText.years(of: phase) + " · take-home pay"
                if let growth = phase.realGrowth, growth != 0 {
                    subtitle += " · grows \(words.percent(growth)) a year"
                }
                return [PlanSettingRow(id: "work-\(index)", symbol: "briefcase", kind: .work,
                                       title: plan.workName(index),
                                       subtitle: subtitle, value: phase.netIncome.map(words.monthly) ?? "Not set",
                                       opens: .sheet(.work(index)),
                                       issues: issues.issues(for: .work, index: index))]
            case .pension(let index):
                guard plan.pensions.indices.contains(index) else { return [] }
                let pension = plan.pensions[index]
                return [PlanSettingRow(id: "pension-\(index)", symbol: "building.columns", kind: .pension,
                                       title: plan.pensionName(index),
                                       subtitle: pension.fromAge.map { "From \($0), after tax" } ?? "No age yet",
                                       value: pension.perYear.map(words.monthly) ?? "Not set",
                                       opens: .sheet(.pension(index)),
                                       issues: issues.issues(for: .pensions, index: index))]
            case .income(let index):
                guard plan.income.indices.contains(index) else { return [] }
                let income = plan.income[index]
                return [PlanSettingRow(id: "income-\(index)", symbol: "banknote", kind: .pension,
                                       title: plan.incomeName(index),
                                       subtitle: PlanIncomeText.span(of: income) + ", after tax",
                                       value: income.perYear.map(words.monthly) ?? "Not set",
                                       opens: .sheet(.income(index)),
                                       issues: issues.issues(for: .income, index: index))]
            case .contribution(let index):
                guard plan.contributions.indices.contains(index) else { return [] }
                let contribution = plan.contributions[index]
                let subtitle: String
                let value: String
                if let amount = contribution.amount {
                    subtitle = contribution.year.map { "Once, in \(String($0))" } ?? "Once"
                    value = words.amount(amount)
                } else {
                    switch contribution.effectiveUntil {
                    case .retirement: subtitle = "Until you stop working"
                    case .date(let date): subtitle = "Until \(String(date.year))"
                    }
                    value = words.monthly(contribution.perYear)
                }
                return [PlanSettingRow(id: "contribution-\(index)", symbol: "arrow.down.to.line", kind: .saving,
                                       title: "Into \(model.accountName(contribution.account))", subtitle: subtitle,
                                       value: value, opens: .sheet(.contribution(index)),
                                       issues: issues.issues(for: .contributions, index: index))]
            case .event(let index):
                guard plan.events.indices.contains(index) else { return [] }
                let event = plan.events[index]
                var subtitle: String
                switch event.timing {
                case .age(let age): subtitle = "At \(age)"
                case .year(let year): subtitle = "In \(String(year))"
                }
                if event.effectiveProbability < 1 {
                    subtitle += " · \(words.percent(event.effectiveProbability)) likely"
                }
                let sign = event.amount > 0 && !words.hidesAmounts ? "+" : ""
                return [PlanSettingRow(id: "event-\(index)", symbol: "calendar", kind: .event, title: event.name,
                                       subtitle: subtitle, value: sign + words.amount(event.amount),
                                       opens: .sheet(.event(index)),
                                       issues: issues.issues(for: .events, index: index))]
            case .targetMix, .targetMixStep:
                var title = "Your savings"
                if case .targetMixStep(let index) = item, plan.portfolio.targetMixByAge.indices.contains(index) {
                    let step = plan.portfolio.targetMixByAge[index]
                    title += " " + PlanTargetMixModel.title(of: step.fromAge).lowercased()
                }
                let phrase = PlanChapterStory.mixPhrase(item, plan: plan, words: words)
                return [PlanSettingRow(id: "mix-\(item)", symbol: "chart.pie", kind: .mix, title: title,
                                       subtitle: "The target mix",
                                       value: phrase.prefix(1).uppercased() + phrase.dropFirst(),
                                       opens: .sheet(.targetMix))]
            case .end:
                return [PlanSettingRow(id: "end", symbol: "flag.checkered", kind: .end, title: "The plan ends at",
                                       value: "\(plan.effectiveEndAge)", opens: .editor(.endAge))]
            }
        }
    }
}

/// Settings as one list: a row per setting, each opening its editor or its sheet.
struct PlanSettingsList: View {
    let rows: [PlanSettingRow]
    @Binding var plan: PlanDocument
    var model: PlanChaptersModel?
    var canEdit = true
    /// Opens an item's sheet, or the target mix's.
    var onSheet: (PlanToken) -> Void = { _ in }
    /// Goes back to the plan's own retirement age, when the charts are for another.
    var onUsePlanAge: (() -> Void)?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { offset, row in
                if offset > 0 {
                    Divider()
                        .padding(.leading, 50)
                }
                PlanSettingRowView(row: row, plan: $plan, model: model, canEdit: canEdit, onSheet: onSheet,
                                   onUsePlanAge: onUsePlanAge)
            }
        }
        .background(Palette.card, in: shape)
        .overlay { shape.strokeBorder(Palette.border, lineWidth: 1) }
    }
}

/// One setting: its icon, name and second line, its value, and a chevron.
/// A value opens its small editor in a popover pointing at the row (a sheet
/// on iPhone); an item opens its sheet.
struct PlanSettingRowView: View {
    let row: PlanSettingRow
    @Binding var plan: PlanDocument
    var model: PlanChaptersModel?
    var canEdit = true
    var onSheet: (PlanToken) -> Void = { _ in }
    var onUsePlanAge: (() -> Void)?

    @State private var showsEditor = false

    var body: some View {
        Button {
            switch row.opens {
            case .editor: showsEditor = true
            case .sheet(let token): onSheet(token)
            }
        } label: {
            HStack(alignment: .center, spacing: Metrics.m) {
                Image(systemName: row.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(row.kind.color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title)
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink)
                    if let subtitle = row.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                    ForEach(row.issues, id: \.self) { issue in
                        PlanIssueLine(issue)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Metrics.s)
                Text(row.value)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(canEdit ? Palette.accent : Palette.secondaryInk)
                    .multilineTextAlignment(.trailing)
                    .privacySensitive()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.mutedInk)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Metrics.m)
            .padding(.vertical, Metrics.s)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canEdit)
        .accessibilityElement(children: .combine)
        .popover(isPresented: $showsEditor) {
            if case .editor(let token) = row.opens {
                PlanTokenEditor(token: token, plan: $plan, model: model, onOpen: onSheet, onUsePlanAge: onUsePlanAge)
            }
        }
    }
}
