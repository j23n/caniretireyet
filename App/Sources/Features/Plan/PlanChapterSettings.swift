import Model
import Planner
import SwiftUI

// A chapter's settings (UI.md, "The plan"): the words only read, and the
// settings are where the plan changes. Every input that starts in a
// chapter is one row there, with its value (amounts a month, as the words
// say them); a row opens the value's small editor in a popover (the ages),
// or a sheet (spending and the items).

/// A value a setting changes in its small editor (``PlanValueEditor``)
/// rather than in a sheet.
enum PlanValue: Hashable {
    case retirementAge
    case endAge
}

/// What a setting's sheet edits: an item (the target mix's sheet, for the
/// mix and its changes), or flexible spending, which belongs to spending in
/// retirement's item.
enum PlanSettingSheet: Hashable {
    case item(PlanChapter.Item)
    case flexibleSpending
}

/// One setting: what it is, its value, and what a tap opens.
struct PlanSettingRow: Hashable, Identifiable {
    /// What a tap opens: the value's small editor, or a sheet.
    enum Opens: Hashable {
        case editor(PlanValue)
        case sheet(PlanSettingSheet)
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
    /// Its value: an amount hides with the eye.
    var value: AmountSentence
    var opens: Opens
    var issues: [PlanIssue] = []
    /// Whether the title and the second line show the person's data (a
    /// name, an age, a year, a share), hidden in a feedback screenshot. The
    /// value hides itself (``AmountSentenceText``).
    var personalTitle = true
    var personalSubtitle = true
}

enum PlanChapterSettings {
    /// A row for each of `items`, in their order: what starts in a chapter,
    /// or the inputs outside the plan's years. Amounts are a month's, in
    /// today's money; one-offs are their amount. A work phase reads
    /// "Take-home pay" in its chapter, which bears its name, and by its
    /// name with `namesWork` (outside the plan's years).
    static func rows(for items: [PlanChapter.Item], model: PlanChaptersModel, issues: PlanInputIssues,
                     words: PlanWords, namesWork: Bool = false) -> [PlanSettingRow] {
        let plan = model.plan
        return items.flatMap { item -> [PlanSettingRow] in
            switch item {
            case .retirement:
                let earliest = plan.retirement.age == .earliest
                return [PlanSettingRow(
                    id: "retirement", symbol: "figure.walk", kind: .retirement, title: "Stop working",
                    subtitle: earliest ? "At \(model.retirementAge), in \(model.retirementYear)"
                        : "In \(model.retirementYear)",
                    value: earliest ? "As early as you can" : "At \(plan.planRetirementAge)",
                    opens: .editor(.retirementAge), personalTitle: false)]
            case .workingSpending:
                return [PlanSettingRow(id: "working-spending", symbol: "cart", kind: .spending, title: "Spending",
                                       subtitle: "While working", value: words.monthly(plan.spending.working),
                                       opens: .sheet(.item(item)), personalTitle: false, personalSubtitle: false)]
            case .retiredSpending:
                let flexible = plan.spending.flexibleRule.map { "Never below \(words.percent($0.effectiveFloor))" }
                return [
                    PlanSettingRow(id: "retired-spending", symbol: "cart", kind: .spending, title: "Spending",
                                   subtitle: "In retirement", value: words.monthly(plan.spending.retired),
                                   opens: .sheet(.item(item)), personalTitle: false, personalSubtitle: false),
                    PlanSettingRow(id: "flexible-spending", symbol: "arrow.down.right", kind: .spending,
                                   title: "Flexible spending", subtitle: "Spending less after bad years",
                                   value: AmountSentence(flexible ?? "Off"), opens: .sheet(.flexibleSpending),
                                   personalTitle: false, personalSubtitle: false),
                ]
            case .spendingPhase(let index):
                guard plan.spending.phases.indices.contains(index) else { return [] }
                let phase = plan.spending.phases[index]
                return [PlanSettingRow(id: "spending-phase-\(index)", symbol: "cart", kind: .spending,
                                       title: "Spending from \(phase.fromAge)",
                                       subtitle: "\(words.percent(phase.factor)) of spending in retirement",
                                       value: words.monthly(plan.spending.retired * phase.factor),
                                       opens: .sheet(.item(item)))]
            case .work(let index):
                guard plan.work.indices.contains(index) else { return [] }
                let phase = plan.work[index]
                var subtitle = PlanWorkText.years(of: phase) + " · take-home pay"
                if let growth = phase.realGrowth, growth != 0 {
                    subtitle += " · grows \(words.percent(growth)) a year"
                }
                return [PlanSettingRow(id: "work-\(index)", symbol: "briefcase", kind: .work,
                                       title: namesWork ? plan.workName(index) : "Take-home pay",
                                       subtitle: subtitle, value: phase.netIncome.map(words.monthly) ?? "Not set",
                                       opens: .sheet(.item(item)),
                                       issues: issues.issues(for: .work, index: index), personalTitle: namesWork)]
            case .pension(let index):
                guard plan.pensions.indices.contains(index) else { return [] }
                let pension = plan.pensions[index]
                return [PlanSettingRow(id: "pension-\(index)", symbol: "building.columns", kind: .pension,
                                       title: plan.pensionName(index),
                                       subtitle: pension.fromAge.map { "From \($0), after tax" } ?? "No age yet",
                                       value: pension.perYear.map(words.monthly) ?? "Not set",
                                       opens: .sheet(.item(item)),
                                       issues: issues.issues(for: .pensions, index: index))]
            case .income(let index):
                guard plan.income.indices.contains(index) else { return [] }
                let income = plan.income[index]
                return [PlanSettingRow(id: "income-\(index)", symbol: "banknote", kind: .pension,
                                       title: plan.incomeName(index),
                                       subtitle: PlanIncomeText.span(of: income) + ", after tax",
                                       value: income.perYear.map(words.monthly) ?? "Not set",
                                       opens: .sheet(.item(item)),
                                       issues: issues.issues(for: .income, index: index))]
            case .contribution(let index):
                guard plan.contributions.indices.contains(index) else { return [] }
                let contribution = plan.contributions[index]
                let subtitle: String
                let value: AmountSentence
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
                                       value: value, opens: .sheet(.item(item)),
                                       issues: issues.issues(for: .contributions, index: index))]
            case .event(let index):
                guard plan.events.indices.contains(index) else { return [] }
                let event = plan.events[index]
                var subtitle: String
                let when: String
                switch event.timing {
                case .age(let age):
                    subtitle = "At \(age)"
                    when = "at \(age)"
                case .year(let year):
                    subtitle = "In \(String(year))"
                    when = String(year)
                }
                if event.effectiveProbability < 1 {
                    subtitle += " · \(words.percent(event.effectiveProbability)) likely"
                }
                return [PlanSettingRow(id: "event-\(index)", symbol: "calendar", kind: .event, title: event.name,
                                       subtitle: subtitle, value: "\(when), \(words.signedAmount(event.amount))",
                                       opens: .sheet(.item(item)),
                                       issues: issues.issues(for: .events, index: index))]
            case .targetMix, .targetMixStep:
                var title = "Your savings"
                var personalTitle = false
                if case .targetMixStep(let index) = item, plan.portfolio.targetMixByAge.indices.contains(index) {
                    let step = plan.portfolio.targetMixByAge[index]
                    title += " " + PlanTargetMixModel.title(of: step.fromAge).lowercased()
                    personalTitle = true
                }
                let phrase = PlanChapterStory.mixPhrase(item, plan: plan, words: words)
                return [PlanSettingRow(id: "mix-\(item)", symbol: "chart.pie", kind: .mix, title: title,
                                       subtitle: "The target mix",
                                       value: AmountSentence(phrase.capitalizedFirst),
                                       opens: .sheet(.item(item)), personalTitle: personalTitle,
                                       personalSubtitle: false)]
            case .end:
                return [PlanSettingRow(id: "end", symbol: "flag.checkered", kind: .end, title: "The plan ends at",
                                       value: "\(plan.effectiveEndAge)", opens: .editor(.endAge),
                                       personalTitle: false)]
            }
        }
    }
}

/// Settings as one list: a row per setting, each opening its editor or its sheet.
struct PlanSettingsList: View {
    let rows: [PlanSettingRow]
    @Binding var plan: PlanDocument
    let model: PlanChaptersModel
    var canEdit = true
    /// Opens a setting's sheet.
    var onSheet: (PlanSettingSheet) -> Void = { _ in }
    /// Goes back to the plan's own retirement age, when the charts are for another.
    var onUsePlanAge: (() -> Void)?

    var body: some View {
        CardRows {
            ForEach(rows) { row in
                PlanSettingRowView(row: row, plan: $plan, model: model, canEdit: canEdit, onSheet: onSheet,
                                   onUsePlanAge: onUsePlanAge)
            }
        }
    }
}

/// One setting as a card's row: its name on the left, its value on the
/// right, each on one line, and a chevron; its problems under it. A value
/// opens its small editor in a popover pointing at the row (a sheet on
/// iPhone); spending and an item open a sheet. The second line ("At 54, in
/// 2042") is what VoiceOver adds.
struct PlanSettingRowView: View {
    let row: PlanSettingRow
    @Binding var plan: PlanDocument
    let model: PlanChaptersModel
    var canEdit = true
    var onSheet: (PlanSettingSheet) -> Void = { _ in }
    var onUsePlanAge: (() -> Void)?

    @State private var showsEditor = false

    var body: some View {
        Button {
            switch row.opens {
            case .editor: showsEditor = true
            case .sheet(let sheet): onSheet(sheet)
            }
        } label: {
            CardRow(opens: true) {
                Text(row.title)
                    .privacySensitiveInFeedback(row.personalTitle)
            } value: {
                AmountSentenceText(row.value)
                    .monospacedDigit()
            } below: {
                if !row.issues.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(row.issues, id: \.self) { issue in
                            PlanIssueLine(issue)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!canEdit)
        .accessibilityHint(Text(row.subtitle ?? ""))
        .accessibilityIdentifier("plan.setting.\(row.id)")
        .popover(isPresented: $showsEditor) {
            if case .editor(let value) = row.opens {
                PlanValueEditor(value: value, plan: $plan, model: model, onUsePlanAge: onUsePlanAge)
            }
        }
    }
}

extension PlanSettingSheet {
    /// Whether it's the target mix's sheet, which has a sheet of its own.
    var isTargetMix: Bool {
        switch self {
        case .item(.targetMix), .item(.targetMixStep): true
        default: false
        }
    }
}

extension PlanEditTarget {
    /// What a setting's sheet edits, from the plan as it is: spending's,
    /// flexible spending's or an item's; `nil` for the target mix, which
    /// has a sheet of its own (``PlanSettingSheet/isTargetMix``), and for an
    /// item that's no longer there.
    init?(_ sheet: PlanSettingSheet, in plan: PlanDocument) {
        switch sheet {
        case .item(.workingSpending):
            self = .workingSpending(plan.spending)
        case .item(.retiredSpending):
            self = .retiredSpending(plan.spending)
        case .flexibleSpending:
            self = .flexibleSpending(plan.spending)
        case .item(.spendingPhase(let index)) where plan.spending.phases.indices.contains(index):
            self = .spendingPhase(index: index, phase: plan.spending.phases[index])
        case .item(.work(let index)) where plan.work.indices.contains(index):
            self = .work(index: index, phase: plan.work[index])
        case .item(.pension(let index)) where plan.pensions.indices.contains(index):
            self = .pension(index: index, pension: plan.pensions[index])
        case .item(.income(let index)) where plan.income.indices.contains(index):
            self = .income(index: index, income: plan.income[index])
        case .item(.contribution(let index)) where plan.contributions.indices.contains(index):
            self = .contribution(index: index, contribution: plan.contributions[index])
        case .item(.event(let index)) where plan.events.indices.contains(index):
            self = .event(index: index, event: plan.events[index])
        default:
            return nil
        }
    }
}
