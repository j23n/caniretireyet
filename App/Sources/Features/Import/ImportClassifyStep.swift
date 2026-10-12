import Foundation
import Importer
import Model
import SwiftUI

/// Step 4 of a bank statement (the statement layout), Classify: the days
/// the file covers, each class with its money in and out, every line with
/// its class and why it has it, and the rules that classify lines. A line's
/// class is changed for it alone, or for every line with the same words by
/// a rule, which the profile keeps for next month's file (IMPORT.md, "Bank
/// statements").
struct ImportClassifyStep: View {
    let model: ImportController

    /// The line a new rule starts from.
    @State private var ruleLine: StatementLine?

    var body: some View {
        let flow = model.flow
        let currency = flow.statementAccount?.currency
        Form {
            ImportStatementDays(model: model)

            let totals = flow.statementClassTotals
            if !totals.isEmpty {
                Section {
                    ForEach(totals) { total in
                        ImportStatementTotalRow(total: total, currency: currency)
                    }
                } header: {
                    Text("Classes")
                } footer: {
                    Text("Income and interest are money in, spending is money out, and a transfer between your "
                        + "accounts is neither. The money in and out of each month become the account's values.")
                }
            }

            Section {
                if flow.statementLines.isEmpty {
                    Text(flow.statementAccount == nil
                         ? "Choose the statement's account in Columns to see its lines."
                         : "No lines can be read yet: say which columns hold the dates and amounts in Columns.")
                        .foregroundStyle(Palette.secondaryInk)
                }
                ForEach(flow.statementLines) { line in
                    ImportStatementLineRow(model: model, line: line, currency: currency) {
                        ruleLine = line
                    }
                }
            } header: {
                Text("Lines")
            } footer: {
                Text("Each line's class comes from your rules, then a trade of another account moving the same "
                    + "amount, another account's name, the usual words, and last its sign. Change a line alone, or "
                    + "make a rule for every line with the same words.")
            }

            let rules = flow.statementRules
            if !rules.isEmpty {
                Section {
                    ForEach(rules, id: \.match) { rule in
                        ImportStatementRuleRow(model: model, rule: rule)
                    }
                } header: {
                    Text("Rules")
                } footer: {
                    Text("Rules are kept in the profile, if you save one, so next month's statement is classified "
                        + "the same way.")
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $ruleLine) { line in
            ImportStatementRuleSheet(model: model, line: line)
        }
    }
}

// MARK: - The days the file covers

/// The days the file is read as covering, the first and last day when the
/// file covers part of a month, the balance before its first line when
/// it's needed, and notes on how the lines became values.
private struct ImportStatementDays: View {
    let model: ImportController

    @State private var openingText = ""

    var body: some View {
        let flow = model.flow
        let period = flow.statementPeriod
        Section {
            if let period {
                LabeledContent("Read as covering") {
                    Text(AmountFormat.mediumDate(period.from) + " – " + AmountFormat.mediumDate(period.through))
                        .privacySensitiveInFeedback()
                }
            }
            Toggle("Starts on a day of its own", isOn: Binding(get: { model.flow.statementFrom != nil }, set: { on in
                model.flow.setStatementFrom(on ? (period?.from ?? model.flow.statementLines.first?.date) : nil)
            }))
            if let from = flow.statementFrom {
                DatePicker("First day", selection: Binding(get: { from.dateValue }, set: { date in
                    model.flow.setStatementFrom(CalendarDate(date, in: .current))
                }), in: ...(flow.statementThrough?.dateValue ?? Date()), displayedComponents: .date)
                    .personalControl()
            }
            Toggle("Ends on a day of its own", isOn: Binding(get: { model.flow.statementThrough != nil }, set: { on in
                model.flow.setStatementThrough(on ? Self.lastDay(of: model.flow) : nil)
            }))
            if let through = flow.statementThrough {
                DatePicker("Last day", selection: Binding(get: { through.dateValue }, set: { date in
                    model.flow.setStatementThrough(CalendarDate(date, in: .current))
                }), in: min(flow.statementFrom?.dateValue ?? .distantPast, Date())...Date(), displayedComponents: .date)
                    .personalControl()
            }
            if flow.needsOpeningBalance || flow.statementOpeningBalance != nil {
                LabeledContent("Balance before the first line") {
                    HStack(spacing: Metrics.s) {
                        TextField("Balance", text: $openingText)
                            .multilineTextAlignment(.trailing)
                            .onSubmit(applyOpening)
                        Button("Use", action: applyOpening)
                            .disabled(AmountInput.parse(openingText).value == flow.statementOpeningBalance)
                    }
                }
            }
            ForEach(flow.statementNotes, id: \.self) { note in
                Label(note.text, systemImage: note.isProblem ? "exclamationmark.triangle" : "info.circle")
                    .font(.footnote)
                    .foregroundStyle(note.isProblem ? Palette.warning : Palette.secondaryInk)
                    .privacySensitiveInFeedback()
            }
        } header: {
            Text("Days")
        } footer: {
            Text("A statement is read as whole months: from the first day of its first line's month to the last day "
                + "of its last line's month, or today. A bank's export of the last 90 days, or one made in the "
                + "middle of a month, covers less: give its first and last days. The last day gets a value of its "
                + "own, which next month's file follows on from.")
        }
        .onAppear {
            openingText = flow.statementOpeningBalance.map { AmountInput.text(for: $0) } ?? ""
        }
    }

    private func applyOpening() {
        switch AmountInput.parse(openingText) {
        case .empty: model.flow.setStatementOpeningBalance(nil)
        case .value(let value): model.flow.setStatementOpeningBalance(value)
        case .unreadable: break
        }
    }

    /// The last day to start from: the file's last line, or the period's last day if earlier.
    private static func lastDay(of flow: ImportFlow) -> CalendarDate? {
        let today = CalendarDate.today()
        let last = flow.statementLines.last?.date ?? flow.statementPeriod?.through
        return last.map { min($0, today) }
    }
}

// MARK: - Classes and lines

/// A class with how many lines have it and their money in and out.
private struct ImportStatementTotalRow: View {
    let total: StatementClassTotal
    let currency: CurrencyCode?

    var body: some View {
        LabeledContent {
            HStack(spacing: Metrics.m) {
                if total.moneyIn != 0 {
                    AmountText(total.moneyIn, currency: currency, precision: .cents, signed: true)
                }
                if total.moneyOut != 0 {
                    AmountText(-total.moneyOut, currency: currency, precision: .cents, signed: true)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(ImportFlow.statementClassName(total.statementClass))
                Text((total.lines == 1 ? "1 line" : "\(total.lines) lines") + " · "
                    + ImportFlow.statementClassMeaning(total.statementClass))
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }
}

/// A line of the statement: its text, date and amount, why it has its
/// class, and a menu to change the class or make a rule.
private struct ImportStatementLineRow: View {
    let model: ImportController
    let line: StatementLine
    let currency: CurrencyCode?
    let makeRule: () -> Void

    var body: some View {
        LabeledContent {
            HStack(spacing: Metrics.m) {
                AmountText(line.amount, currency: currency, precision: .cents, signed: true)
                Menu {
                    Picker("Class", selection: Binding(get: { line.statementClass }, set: { statementClass in
                        model.flow.setStatementClass(statementClass, forRow: line.row)
                    })) {
                        ForEach(ImportFlow.statementClasses, id: \.self) { statementClass in
                            Text(ImportFlow.statementClassName(statementClass)).tag(statementClass)
                        }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Button("Make a Rule…", action: makeRule)
                    if line.source == .chosen {
                        Button("Undo This Line's Choice") {
                            model.flow.setStatementClass(nil, forRow: line.row)
                        }
                    }
                } label: {
                    Text(ImportFlow.statementClassName(line.statementClass))
                }
                .fixedSize()
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: line.text.isEmpty ? "—" : line.text)
                    .lineLimit(2)
                    .privacySensitiveInFeedback()
                Text(AmountFormat.mediumDate(line.date) + " · " + model.flow.statementSourceText(line.source))
                    .font(.caption)
                    .foregroundStyle(line.source == .sign ? Palette.warning : Palette.secondaryInk)
                    .privacySensitiveInFeedback()
            }
        }
    }
}

/// A rule of the profile, with a button to remove it.
private struct ImportStatementRuleRow: View {
    let model: ImportController
    let rule: StatementRule

    var body: some View {
        LabeledContent {
            HStack(spacing: Metrics.m) {
                Text(ImportFlow.statementClassName(rule.statementClass))
                Button(role: .destructive) {
                    model.flow.setStatementRule(nil, for: rule.match)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove Rule")
            }
        } label: {
            Text(verbatim: "“\(rule.match)”")
                .privacySensitiveInFeedback()
        }
    }
}

// MARK: - A new rule

/// Makes a rule from a line: the words a line's text must have, and the
/// class every such line gets.
private struct ImportStatementRuleSheet: View {
    let model: ImportController
    let line: StatementLine

    @State private var phrase: String
    @State private var statementClass: StatementClass
    @Environment(\.dismiss) private var dismiss

    init(model: ImportController, line: StatementLine) {
        self.model = model
        self.line = line
        _phrase = State(initialValue: ImportFlow.suggestedRulePhrase(for: line))
        _statementClass = State(initialValue: line.statementClass)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Words", text: $phrase)
                    Picker("Class", selection: $statementClass) {
                        ForEach(ImportFlow.statementClasses, id: \.self) { statementClass in
                            Text(ImportFlow.statementClassName(statementClass)).tag(statementClass)
                        }
                    }
                } footer: {
                    Text(matches)
                }
                Section {
                    Text(verbatim: line.text)
                        .privacySensitiveInFeedback()
                } header: {
                    Text("The line")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Rule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.flow.setStatementRule(statementClass, for: phrase)
                        dismiss()
                    }
                    .disabled(model.flow.linesMatching(rule: phrase) == nil)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 280)
    }

    /// E.g. "Every line whose text has these words, ignoring case and accents: 3 lines in this file…".
    private var matches: String {
        guard let count = model.flow.linesMatching(rule: phrase) else {
            return "Give a word or more that a line's text has, ignoring case and accents."
        }
        return "Every line whose text has these words, ignoring case and accents: "
            + (count == 1 ? "1 line" : "\(count) lines") + " in this file. A line you changed alone keeps its "
            + "class. The rule is kept in the profile, if you save one."
    }
}

#Preview("Classify") {
    NavigationStack {
        ImportPreviewHost(step: .classify, file: .statement)
    }
    .previewEnvironment()
}
