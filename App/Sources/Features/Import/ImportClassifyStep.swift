import Foundation
import Importer
import Model
import SwiftUI

/// Step 4 of a bank statement (the statement layout), Income: the days the
/// file covers, what its lines add up to, the large lines that need an
/// answer, what was bought and sold, and the rest of its money in by
/// sender, income or paid back. Other money out is spending unless a rule,
/// a trade or an account's name says it's a transfer. A sender's class is a
/// rule, which the profile keeps for next month's file; *All Lines* lists
/// every line to change one alone (IMPORT.md, "Bank statements",
/// "Purchases and sales").
struct ImportClassifyStep: View {
    let model: ImportController

    @State private var isShowingLines = false
    @State private var showsAllPaidBack = false
    /// The line out being answered as a purchase you keep.
    @State private var purchaseLine: StatementLine?
    /// The line in being answered as a sale.
    @State private var saleLine: StatementLine?

    /// How many senders of money paid back show before *Show All*.
    private static let paidBackShown = 5

    var body: some View {
        let flow = model.flow
        let currency = flow.statementAccount?.currency
        Form {
            ImportStatementDays(model: model)

            if flow.statementLines.isEmpty {
                Section {
                    Text(flow.statementAccount == nil
                         ? "Choose the statement's account on the File step to see its lines."
                         : "No lines can be read yet: say which columns hold the dates and amounts in How It's "
                            + "Read… on the File step.")
                        .foregroundStyle(Palette.secondaryInk)
                }
            } else {
                ImportStatementSumsSection(sums: flow.statementSums, currency: currency)
            }

            let questions = flow.statementQuestions
            if !questions.isEmpty {
                Section {
                    ForEach(questions) { line in
                        ImportStatementQuestionRow(model: model, line: line, currency: currency,
                                                   askPurchase: { purchaseLine = line },
                                                   askSale: { saleLine = line })
                    }
                } header: {
                    Text("Needs an answer")
                } footer: {
                    Text("More than a month's spending, or more than a regular payer's usual amount, came in or "
                        + "went out, and nothing says what it is. A one-off, such as an inheritance or the sale of "
                        + "something you didn't track, is neither income nor spending. A purchase you keep, such as "
                        + "a car or a home, starts an account worth what you paid, and a sale closes one. Until "
                        + "it's answered, money in counts as paid back and money out as spending.")
                }
            }

            let assets = flow.statementAssetLines
            if !assets.isEmpty {
                Section {
                    ForEach(assets) { line in
                        ImportStatementAssetRow(model: model, line: line, currency: currency)
                    }
                } header: {
                    Text("Bought and sold")
                } footer: {
                    Text("Importing starts an account for each purchase, worth what you paid, and closes each "
                        + "account sold. Both are money moved between your accounts, so they're neither spent "
                        + "nor came in.")
                }
            }

            let income = flow.incomingGroups(.income)
            if !income.isEmpty {
                Section {
                    ForEach(income) { group in
                        ImportStatementSenderRow(model: model, group: group, currency: currency,
                                                 change: (statementClass: .paidBack, title: "Not Income"))
                    }
                } header: {
                    Text("Income")
                } footer: {
                    Text("Pay, a pension, rent, a client: what came in. A sender's class is kept for next month's "
                        + "file, unless its words also match other lines.")
                }
            }

            let oneOffs = flow.incomingGroups(.oneOff)
            if !oneOffs.isEmpty {
                Section("One-offs") {
                    ForEach(oneOffs) { group in
                        ImportStatementSenderRow(model: model, group: group, currency: currency,
                                                 change: (statementClass: .paidBack, title: "Not a One-Off"))
                    }
                }
            }

            let paidBack = (flow.incomingGroups(.paidBack) + flow.incomingGroups(.spending))
                .sorted { ($0.total, $1.sender) > ($1.total, $0.sender) }
            if !paidBack.isEmpty {
                Section {
                    let shown = showsAllPaidBack ? paidBack : Array(paidBack.prefix(Self.paidBackShown))
                    ForEach(shown) { group in
                        ImportStatementSenderRow(model: model, group: group, currency: currency,
                                                 change: (statementClass: .income, title: "Income"))
                    }
                    if paidBack.count > Self.paidBackShown {
                        Button(showsAllPaidBack ? "Show Fewer" : "Show All \(paidBack.count) Senders") {
                            showsAllPaidBack.toggle()
                        }
                    }
                } header: {
                    Text("Paid back")
                } footer: {
                    Text("Refunds, a friend's share of a bill, an insurance payout: they lower what you spent. "
                        + "Money in is paid back unless its sender is income or pays you every month.")
                }
            }

            Section {
                Button("All Lines…") { isShowingLines = true }
            } footer: {
                Text("Money out is spending, unless a rule, a trade of another account or another account's name "
                    + "says it was moved between your accounts. All Lines shows every line and why it has its "
                    + "class, to change one alone or make a rule.")
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
        .sheet(isPresented: $isShowingLines) {
            ImportStatementLinesSheet(model: model)
        }
        .sheet(item: $purchaseLine) { line in
            ImportStatementPurchaseSheet(model: model, line: line, currency: currency)
        }
        .sheet(item: $saleLine) { line in
            ImportStatementSaleSheet(model: model, line: line, currency: currency)
        }
    }
}

// MARK: - The days the file covers

/// The days the file is read as covering, the first and last day when the
/// file covers part of a month, the balance before its first line when
/// it's needed, and notes on how the lines became values.
private struct ImportStatementDays: View {
    let model: ImportController

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
                ImportOpeningBalanceField(model: model)
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
    }

    /// The last day to start from: the file's last line, or the period's last day if earlier.
    private static func lastDay(of flow: ImportFlow) -> CalendarDate? {
        let today = CalendarDate.today()
        let last = flow.statementLines.last?.date ?? flow.statementPeriod?.through
        return last.map { min($0, today) }
    }
}

/// The balance before a statement's first line, typed in, for a file
/// without a balance column that doesn't follow on from the library's
/// values. Classify's Days and Preview show it.
struct ImportOpeningBalanceField: View {
    let model: ImportController

    @State private var openingText = ""

    var body: some View {
        LabeledContent("Balance before the first line") {
            HStack(spacing: Metrics.s) {
                TextField("Balance", text: $openingText)
                    .multilineTextAlignment(.trailing)
                    .onSubmit(apply)
                Button("Use", action: apply)
                    .disabled(AmountInput.parse(openingText).value == model.flow.statementOpeningBalance)
            }
        }
        .onAppear {
            openingText = model.flow.statementOpeningBalance.map { AmountInput.text(for: $0) } ?? ""
        }
    }

    private func apply() {
        switch AmountInput.parse(openingText) {
        case .empty: model.flow.setStatementOpeningBalance(nil)
        case .value(let value): model.flow.setStatementOpeningBalance(value)
        case .unreadable: break
        }
    }
}

// MARK: - Sums, questions and senders

/// What the file's lines add up to: what came in, what was paid back and
/// spent, one-offs, and what was moved between your accounts.
private struct ImportStatementSumsSection: View {
    let sums: StatementSums
    let currency: CurrencyCode?

    var body: some View {
        Section {
            row("Came in", sums.cameIn)
            if sums.interest != 0 { row("Interest", sums.interest) }
            if sums.oneOffs != 0 { row("One-offs", sums.oneOffs) }
            if sums.bought != 0 { row("Bought to keep", sums.bought) }
            if sums.sold != 0 { row("Sold", sums.sold) }
            row("Spent", sums.spent, detail: sums.paidBack == 0 ? nil : "after paid back")
            if sums.paidBack != 0 { row("Paid back", sums.paidBack) }
            if sums.moved != 0 { row("Moved between your accounts", sums.moved, signed: true) }
            if sums.leftOut != 0 { row("Left out", sums.leftOut, signed: true) }
        } header: {
            Text("This file")
        } footer: {
            Text("What you saved comes from the balances, so these classes only move money between came in and "
                + "spent.")
        }
    }

    private func row(_ title: String, _ amount: Decimal, detail: String? = nil, signed: Bool = false) -> some View {
        LabeledContent {
            AmountText(amount, currency: currency, precision: .cents, signed: signed)
        } label: {
            if let detail {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                }
            } else {
                Text(title)
            }
        }
    }
}

/// A line that needs an answer: who sent or was paid it, when, how much,
/// and the answers for this line. Money in: income, one-off or paid back,
/// and *A Sale…* when an account could have been sold. Money out:
/// spending, or *A Purchase You'll Keep…*.
private struct ImportStatementQuestionRow: View {
    let model: ImportController
    let line: StatementLine
    let currency: CurrencyCode?
    let askPurchase: () -> Void
    let askSale: () -> Void

    private static let answers: [StatementClass] = [.income, .oneOff, .paidBack]

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: line.sender.isEmpty ? line.text : line.sender)
                        .lineLimit(2)
                        .privacySensitiveInFeedback()
                    Text(AmountFormat.mediumDate(line.date))
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                        .privacySensitiveInFeedback()
                }
                Spacer()
                AmountText(line.amount, currency: currency, precision: .cents, signed: true)
            }
            if line.amount > 0 {
                Picker("What is it?", selection: Binding(get: { StatementClass?.none }, set: { answer in
                    if let answer { model.flow.setStatementClass(answer, forRow: line.row) }
                })) {
                    ForEach(Self.answers, id: \.self) { answer in
                        Text(ImportFlow.statementClassName(answer)).tag(StatementClass?.some(answer))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if !model.flow.saleChoices(for: line).isEmpty {
                    Button("A Sale…", action: askSale)
                        .buttonStyle(.bordered)
                }
            } else {
                HStack(spacing: Metrics.m) {
                    Button(ImportFlow.statementClassName(.spending)) {
                        model.flow.setStatementClass(.spending, forRow: line.row)
                    }
                    Button("A Purchase You'll Keep…", action: askPurchase)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

/// A line answered as a purchase you keep or a sale: what was bought or
/// sold, when, the amount, and *Undo*, which asks again.
private struct ImportStatementAssetRow: View {
    let model: ImportController
    let line: StatementLine
    let currency: CurrencyCode?

    var body: some View {
        LabeledContent {
            HStack(spacing: Metrics.m) {
                AmountText(line.amount, currency: currency, precision: .cents, signed: true)
                Button("Undo") {
                    model.flow.setStatementAsset(nil, forRow: line.row)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .lineLimit(1)
                    .privacySensitiveInFeedback()
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(line.asset == nil ? Palette.warning : Palette.secondaryInk)
                    .privacySensitiveInFeedback()
            }
        }
    }

    /// The new account's name, or the account sold.
    private var title: String {
        switch model.flow.statementAnswer(line) {
        case .purchase(let name, _)?: name
        case .sale(let id)?: model.flow.accountName(id)
        case nil: line.text
        }
    }

    /// "Belongings · bought 20 Feb 2026", "Sold 18 Mar 2026", or why it
    /// isn't recorded.
    private var detail: String {
        if line.asset == nil, model.flow.statementAnswer(line) != nil {
            return "Not recorded: " + model.flow.statementAssetLeftOutReason(line)
        }
        return switch model.flow.statementAnswer(line) {
        case .purchase(_, let kind)?: "\(kind.displayName) · bought \(AmountFormat.mediumDate(line.date))"
        case .sale?: "Sold \(AmountFormat.mediumDate(line.date))"
        case nil: AmountFormat.mediumDate(line.date)
        }
    }
}

/// Answers a line out as a purchase you keep: the new account's name and
/// kind.
private struct ImportStatementPurchaseSheet: View {
    let model: ImportController
    let line: StatementLine
    let currency: CurrencyCode?

    @State private var name = ""
    @State private var kind: AccountKind = .belongings
    @Environment(\.dismiss) private var dismiss

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("Car"))
                    Picker("Kind", selection: $kind) {
                        ForEach(StatementAsset.purchaseKinds, id: \.self) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                } footer: {
                    Text("Importing starts this account, worth what you paid from the day you paid it. The money "
                        + "moved from this account into something you keep, so it counts as saved, not spent. As "
                        + "it gains or loses value, update it at a check-in.")
                }
                ImportStatementLineSection(line: line, currency: currency)
            }
            .formStyle(.grouped)
            .navigationTitle("A Purchase You'll Keep")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.flow.setStatementAsset(.purchase(name: trimmedName, kind: kind), forRow: line.row)
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 320)
    }
}

/// Answers a line in as the sale of one of your accounts.
private struct ImportStatementSaleSheet: View {
    let model: ImportController
    let line: StatementLine
    let currency: CurrencyCode?

    @State private var account: AccountID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let choices = model.flow.saleChoices(for: line)
        NavigationStack {
            Form {
                Section {
                    Picker("Account", selection: $account) {
                        Text("Choose…").tag(AccountID?.none)
                        ForEach(choices, id: \.id) { choice in
                            Text(verbatim: choice.name).tag(AccountID?.some(choice.id))
                        }
                    }
                    .personalControl()
                } footer: {
                    Text("Importing values the account at nothing after the sale and closes it. What it sold for, "
                        + "less its last value, is a gain or a loss. The money moved from it into this account, so "
                        + "it didn't come in.")
                }
                ImportStatementLineSection(line: line, currency: currency)
            }
            .formStyle(.grouped)
            .navigationTitle("A Sale")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let account { model.flow.setStatementAsset(.sale(account), forRow: line.row) }
                        dismiss()
                    }
                    .disabled(account == nil)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 300)
    }
}

/// The line a sheet answers: its text, date and amount.
private struct ImportStatementLineSection: View {
    let line: StatementLine
    let currency: CurrencyCode?

    var body: some View {
        Section {
            LabeledContent {
                AmountText(line.amount, currency: currency, precision: .cents, signed: true)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: line.text.isEmpty ? "—" : line.text)
                        .lineLimit(2)
                        .privacySensitiveInFeedback()
                    Text(AmountFormat.mediumDate(line.date))
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                        .privacySensitiveInFeedback()
                }
            }
        } header: {
            Text("The line")
        }
    }
}

/// A sender's money in of one class: who, how many payments, the total,
/// why, and a button that gives all of them another class.
private struct ImportStatementSenderRow: View {
    let model: ImportController
    let group: StatementSenderGroup
    let currency: CurrencyCode?
    /// The class the button gives, and its title.
    let change: (statementClass: StatementClass, title: String)

    var body: some View {
        LabeledContent {
            HStack(spacing: Metrics.m) {
                AmountText(group.total, currency: currency, precision: .cents)
                Button(change.title) {
                    model.flow.setStatementClass(change.statementClass, for: group)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: group.sender.isEmpty ? "No sender named" : group.sender)
                    .lineLimit(1)
                    .privacySensitiveInFeedback()
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .privacySensitiveInFeedback()
            }
        }
    }

    /// "3 payments · Pays you every month".
    private var detail: String {
        let count = group.lines.count == 1 ? "1 payment" : "\(group.lines.count) payments"
        guard let source = group.source else { return count }
        return count + " · " + model.flow.statementSourceText(source)
    }
}

// MARK: - All lines

/// Every line of the file with its class and why, each class's money in
/// and out, a menu to change a line alone, and *Make a Rule…*.
private struct ImportStatementLinesSheet: View {
    let model: ImportController

    /// The line a new rule starts from.
    @State private var ruleLine: StatementLine?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let flow = model.flow
        let currency = flow.statementAccount?.currency
        NavigationStack {
            List {
                Section {
                    ForEach(flow.statementClassTotals) { total in
                        ImportStatementTotalRow(total: total, currency: currency)
                    }
                } header: {
                    Text("Classes")
                }
                Section {
                    ForEach(flow.statementLines) { line in
                        ImportStatementLineRow(model: model, line: line, currency: currency) {
                            ruleLine = line
                        }
                    }
                } header: {
                    Text("Lines")
                } footer: {
                    Text("Each line's class comes from your rules, then a trade of another account moving the "
                        + "same amount, another account's name, the usual words, a sender you paid before or one "
                        + "who pays every month, and last its sign.")
                }
            }
            .navigationTitle("All Lines")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 640, idealWidth: 760, minHeight: 520, idealHeight: 680)
        #endif
        .sheet(item: $ruleLine) { line in
            ImportStatementRuleSheet(model: model, line: line)
        }
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
                    if model.flow.statementAnswer(line) != nil {
                        Button("Undo This Line's Answer") {
                            model.flow.setStatementAsset(nil, forRow: line.row)
                        }
                    } else if line.source == .chosen {
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
                Text(AmountFormat.mediumDate(line.date) + " · "
                    + (model.flow.statementAssetText(line) ?? model.flow.statementSourceText(line.source)))
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
