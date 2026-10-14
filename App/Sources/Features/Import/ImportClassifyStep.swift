import Foundation
import Importer
import Model
import SwiftUI

/// Step 2 of bank statements, Income: every statement's lines on one page
/// (UI.md, "Import"; IMPORT.md, "Bank statements"). The lines asked about,
/// answered or not, with how many are left; what was moved between your
/// accounts, a rule's moves, the transfers paired between the files and
/// money that passed through; income by sender; and what came in, tax,
/// spent and saved. *All Lines* changes any line alone or makes a rule.
/// On the Mac and iPad the summary is a card beside the lists and All Lines
/// a sheet; on iPhone the summary is three figures on top, what was found
/// is one list, and All Lines is pushed.
struct ImportClassifyStep: View {
    let model: ImportController

    @Environment(\.pageLayout) private var layout
    @State private var isShowingLines = false
    /// What All Lines shows when it opens.
    @State private var linesFilter = StatementLinesFilter()
    /// The line being answered as money moved to or from an account.
    @State private var moveRequest: StatementMoveRequest?

    private var isCompact: Bool { !layout.isWide }

    var body: some View {
        let flow = model.flow
        Group {
            if flow.allStatementLines.isEmpty {
                ContentUnavailableView {
                    Label("No Lines Yet", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Say which columns hold the dates and amounts in How It's Read… on the Files step.")
                }
            } else if isCompact {
                compactPage(flow)
            } else {
                widePage(flow)
            }
        }
        .toolbar {
            if !isCompact && !flow.allStatementLines.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(flow.allLinesTitle + "…") { showLines(StatementLinesFilter()) }
                }
            }
        }
        .sheet(isPresented: $isShowingLines) {
            ImportAllLinesSheet(model: model, filter: linesFilter)
        }
        .sheet(item: $moveRequest) { request in
            ImportMovedSheet(model: model, request: request)
        }
    }

    private func showLines(_ filter: StatementLinesFilter) {
        linesFilter = filter
        isShowingLines = true
    }

    private func askMove(_ line: BatchStatementLine) {
        moveRequest = StatementMoveRequest(line: line)
    }

    // MARK: The Mac and iPad

    private func widePage(_ flow: ImportFlow) -> some View {
        ScrollView {
            HStack(alignment: .top, spacing: Metrics.xl) {
                VStack(alignment: .leading, spacing: Metrics.l) {
                    VStack(alignment: .leading, spacing: Metrics.xs) {
                        Text("What came in, and what went out?")
                            .font(.title2.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text("Every line is one of five things, in or out. Most are known; these weren't.")
                            .foregroundStyle(Palette.secondaryInk)
                    }
                    questionsSection(flow)
                    movesSection(flow)
                    incomeSection(flow)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let summary = flow.incomeSummary {
                    ImportIncomeSummaryCard(summary: summary)
                        .frame(width: 250)
                }
            }
            .padding(.top, 22)
            .padding(.leading, Metrics.xl * 2)
            .padding(.trailing, Metrics.xl + Metrics.l)
            .padding(.bottom, Metrics.xl)
        }
    }

    /// The lines asked about, with how many are left.
    @ViewBuilder
    private func questionsSection(_ flow: ImportFlow) -> some View {
        let questions = flow.statementQuestions
        if !questions.isEmpty {
            let color = flow.unansweredQuestions > 0 ? Palette.warning : Palette.secondaryInk
            IncomeSection(flow.questionsHeader, color: color) {
                ForEach(Array(questions.enumerated()), id: \.element.id) { index, line in
                    if index > 0 { Divider() }
                    ImportQuestionRow(model: model, line: line, askMove: { askMove(line) })
                }
            }
        }
    }

    /// A rule's moves, the transfers paired between the files, money that
    /// passed through, and lines moved one by one.
    @ViewBuilder
    private func movesSection(_ flow: ImportFlow) -> some View {
        let moves = flow.moveGroups
        if !moves.isEmpty {
            IncomeSection("Moved between your accounts") {
                ForEach(Array(moves.enumerated()), id: \.element.id) { index, group in
                    if index > 0 { Divider() }
                    moveRow(group, flow: flow)
                }
            }
        }
    }

    private func moveRow(_ group: StatementMoveGroup, flow: ImportFlow) -> some View {
        let currency = group.lines.first.flatMap { flow.currency(of: $0) }
        return ImportGroupRow(title: group.title, detail: group.detail, why: group.why, amount: group.total,
                              signed: group.isSigned, currency: currency, link: group.linkTitle) {
            showLines(group.filter)
        }
    }

    /// Income by sender.
    @ViewBuilder
    private func incomeSection(_ flow: ImportFlow) -> some View {
        let income = flow.incomeGroups
        if !income.isEmpty {
            IncomeSection(flow.incomeHeader(income)) {
                ForEach(Array(income.enumerated()), id: \.element.id) { index, group in
                    if index > 0 { Divider() }
                    senderRow(group, flow: flow)
                }
            }
        }
    }

    private func senderRow(_ group: StatementSenderGroup, flow: ImportFlow) -> some View {
        let currency = group.lines.first.flatMap { flow.currency(of: $0) }
        return ImportGroupRow(title: group.sender.isEmpty ? "No sender named" : group.sender, detail: nil,
                              why: flow.senderDetail(group), amount: group.total, signed: false,
                              currency: currency, link: "Change…") {
            showLines(ImportFlow.filter(for: group))
        }
    }

    // MARK: iPhone

    private func compactPage(_ flow: ImportFlow) -> some View {
        List {
            if let summary = flow.incomeSummary {
                Section {
                    ImportIncomeSummaryColumns(summary: summary)
                }
            }
            let questions = flow.statementQuestions
            if !questions.isEmpty {
                Section {
                    ForEach(questions) { line in
                        ImportQuestionRow(model: model, line: line, askMove: { askMove(line) })
                    }
                } header: {
                    Text(flow.questionsHeader)
                        .foregroundStyle(flow.unansweredQuestions > 0 ? Palette.warning : Palette.secondaryInk)
                }
            }
            let found = flow.foundForYou
            if !found.isEmpty {
                Section("Found for you") {
                    ForEach(found) { row in
                        LabeledContent {
                            AmountText(row.amount)
                                .foregroundStyle(Palette.secondaryInk)
                        } label: {
                            Text(verbatim: row.title)
                                .privacySensitiveInFeedback()
                        }
                    }
                }
            }
            Section {
                NavigationLink {
                    ImportAllLinesList(model: model)
                } label: {
                    Text(flow.allLinesTitle)
                }
            }
        }
    }
}

// MARK: - Sections and rows

/// A titled card of rows on the wide page: an uppercase header, then the
/// rows on a card.
private struct IncomeSection<Content: View>: View {
    let title: String
    let color: Color
    let content: Content

    init(_ title: String, color: Color = Palette.secondaryInk, @ViewBuilder content: () -> Content) {
        self.title = title
        self.color = color
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.4)
                .foregroundStyle(color)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1)
            }
        }
    }
}

/// The answers to a line, as a segmented control: Income, Spending,
/// One-off, Tax, *Moved…*. Ringed in the warning color while the line
/// waits for an answer.
struct StatementAnswerPicker: View {
    let selection: StatementAnswerChoice?
    let isAsking: Bool
    let choose: (StatementAnswerChoice) -> Void

    var body: some View {
        Picker("What is it?", selection: Binding(get: { selection }, set: { choice in
            if let choice { choose(choice) }
        })) {
            ForEach(StatementAnswerChoice.all, id: \.self) { choice in
                Text(choice.title).tag(StatementAnswerChoice?.some(choice))
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .overlay {
            if isAsking {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Palette.warning, lineWidth: 1.5)
                    .padding(-2)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// A line asked about: who sent or was paid it and how much, its
/// description, its day and account and what it was answered (a move
/// opens its sheet again), and the answers. On the Mac the answers are
/// beside it; on iPhone below it, and the row opens a move's sheet.
private struct ImportQuestionRow: View {
    let model: ImportController
    let line: BatchStatementLine
    @Environment(\.pageLayout) private var layout
    private var isCompact: Bool { !layout.isWide }
    let askMove: () -> Void

    var body: some View {
        let flow = model.flow
        let picker = StatementAnswerPicker(selection: flow.answerChoice(line), isAsking: line.line.needsAnswer,
                                           choose: answer)
        if isCompact {
            VStack(alignment: .leading, spacing: Metrics.s) {
                info(flow)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if flow.answerDetail(line)?.opensSheet == true { askMove() }
                    }
                picker
            }
            .padding(.vertical, Metrics.xs)
        } else {
            HStack(alignment: .center, spacing: Metrics.l) {
                info(flow)
                picker.fixedSize()
            }
            .padding(.vertical, Metrics.m)
            .padding(.horizontal, Metrics.l)
        }
    }

    /// A class answers the line alone; *Moved…* asks where in a sheet.
    private func answer(_ choice: StatementAnswerChoice) {
        switch choice {
        case .statementClass(let statementClass): model.flow.setStatementClass(statementClass, for: line)
        case .moved: askMove()
        }
    }

    private func info(_ flow: ImportFlow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.m) {
                Text(verbatim: line.title.isEmpty ? "—" : line.title)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .privacySensitiveInFeedback()
                Spacer(minLength: Metrics.s)
                AmountText(line.amount, currency: flow.currency(of: line), precision: .cents, signed: true)
                    .fontWeight(.semibold)
            }
            if !line.line.sender.isEmpty && line.line.text != line.line.sender {
                Text(verbatim: line.line.text)
                    .font(isCompact ? .footnote : .caption)
                    .foregroundStyle(Palette.ink.opacity(0.8))
                    .lineLimit(2)
                    .privacySensitiveInFeedback()
            }
            HStack(spacing: 0) {
                Text(verbatim: flow.dateAndAccount(line))
                if let detail = flow.answerDetail(line) {
                    Text(verbatim: " · ")
                    if detail.opensSheet {
                        Button(action: askMove) {
                            Text(verbatim: detail.text)
                                .foregroundStyle(detail.isProblem ? Palette.warning : Palette.accent)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(verbatim: detail.text)
                    }
                }
            }
            .font(isCompact ? .footnote : .caption)
            .foregroundStyle(Palette.secondaryInk)
            .lineLimit(1)
            .privacySensitiveInFeedback()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A row of *Moved between your accounts* or *Income* on the wide page:
/// its title and detail, why, the amount, and a link to its lines in All
/// Lines.
private struct ImportGroupRow: View {
    let title: String
    let detail: String?
    let why: String
    let amount: Decimal
    let signed: Bool
    let currency: CurrencyCode?
    let link: String
    let open: () -> Void

    var body: some View {
        HStack(spacing: Metrics.m) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
                Text(verbatim: title)
                    .fontWeight(.semibold)
                if let detail {
                    Text(verbatim: detail)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .privacySensitiveInFeedback()
            Text(verbatim: why)
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(2)
                .frame(width: 190, alignment: .leading)
                .privacySensitiveInFeedback()
            AmountText(amount, currency: currency, precision: .cents, signed: signed)
                .frame(width: 110, alignment: .trailing)
            Button(link, action: open)
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(Palette.accent)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, Metrics.l)
    }
}

// MARK: - The summary

/// What came in, tax, after tax, spent, saved and the savings rate, beside
/// the lists on the Mac and iPad.
private struct ImportIncomeSummaryCard: View {
    let summary: IncomeSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: summary.title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.4)
                .foregroundStyle(Palette.secondaryInk)
                .privacySensitiveInFeedback()
            row("Came in", summary.cameIn)
            row("Tax, paid and set aside", -summary.tax, signed: true)
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                Text("Came in after tax")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                AmountText(summary.afterTax, tabular: false)
                    .font(.title.bold())
            }
            row("Spent", summary.spent)
            row("Saved", summary.saved)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Savings rate")
                    Spacer(minLength: Metrics.s)
                    Text(verbatim: summary.rateText)
                        .monospacedDigit()
                        .privacySensitiveInFeedback()
                }
                .fontWeight(.semibold)
                ProgressView(value: min(max(summary.rate?.doubleValue ?? 0, 0), 1))
                    .tint(Palette.accent)
                    .privacySensitiveInFeedback()
                    .accessibilityHidden(true)
            }
            Text("Saved comes from the balances, so answers move only what came in, the tax and what you spent.")
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Metrics.l)
        .padding(.horizontal, 18)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1)
        }
    }

    private func row(_ title: String, _ amount: Decimal, signed: Bool = false) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Palette.secondaryInk)
            Spacer(minLength: Metrics.s)
            AmountText(amount, signed: signed)
        }
    }
}

/// The summary on iPhone: after tax, spent, and the savings rate.
private struct ImportIncomeSummaryColumns: View {
    let summary: IncomeSummary

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.s) {
            column("After tax") { AmountText(summary.afterTax) }
            column("Spent") { AmountText(summary.spent) }
            column("Saved") {
                Text(verbatim: summary.rateText)
                    .monospacedDigit()
                    .privacySensitiveInFeedback()
            }
        }
    }

    private func column<Value: View>(_ title: String, @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
            value()
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Income") {
    NavigationStack {
        ImportPreviewHost(step: .classify, file: .statement)
    }
    .previewEnvironment()
}
