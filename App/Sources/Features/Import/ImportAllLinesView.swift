import Foundation
import Importer
import Model
import SwiftUI

// All Lines (UI.md, "Import"): every line of the statements open, to change
// any of them alone or make a rule. On the Mac and iPad a sheet with a
// table; on iPhone a page pushed from Income, by month.

/// A line's *What it is* menu: Income, Spending, One-off, Tax, *Moved to or
/// from* (your accounts, an account sold, a new account), Interest and
/// *Left Out* for this line alone, then *Every “…” Line…*, which makes a rule.
struct StatementLineMenuItems: View {
    let model: ImportController
    let line: BatchStatementLine
    let askMove: (StatementMoveRequest) -> Void
    let makeRule: () -> Void

    var body: some View {
        let flow = model.flow
        let answer = flow.statementAnswer(line)
        ForEach([StatementClass.income, .spending, .oneOff, .tax], id: \.self) { statementClass in
            classToggle(statementClass, answered: answer != nil)
        }
        Menu("Moved to or from") {
            ForEach(flow.moveChoices(for: line), id: \.id) { account in
                Toggle(isOn: Binding(get: { answer == .moved(account.id) }, set: { _ in
                    model.flow.setStatementAsset(.moved(account.id), for: line)
                })) {
                    Text(verbatim: account.name)
                }
            }
            ForEach(flow.saleChoices(for: line), id: \.id) { account in
                Toggle(isOn: Binding(get: { answer == .sale(account.id) }, set: { _ in
                    model.flow.setStatementAsset(.sale(account.id), for: line)
                })) {
                    Text(verbatim: "Sold: \(account.name)")
                }
            }
            Divider()
            if line.amount < 0 {
                Button("A New Account…") { askMove(StatementMoveRequest(line: line, startsWithPurchase: true)) }
            }
            Button("Choose…") { askMove(StatementMoveRequest(line: line)) }
        }
        Divider()
        classToggle(.interest, answered: answer != nil)
        classToggle(.ignore, answered: answer != nil)
        Divider()
        Button {
            makeRule()
        } label: {
            Text(verbatim: "Every “\(ImportFlow.suggestedRulePhrase(for: line.line))” Line…")
        }
        if answer != nil {
            Button("Undo This Line's Answer") { model.flow.setStatementAsset(nil, for: line) }
        } else if line.line.source == .chosen {
            Button("Undo This Line's Choice") { model.flow.setStatementClass(nil, for: line) }
        }
    }

    /// A class, checked while the line has it and no answer.
    private func classToggle(_ statementClass: StatementClass, answered: Bool) -> some View {
        Toggle(ImportFlow.statementClassMenuTitle(statementClass), isOn: Binding(get: {
            !answered && line.line.statementClass == statementClass
        }, set: { _ in
            model.flow.setStatementClass(statementClass, for: line)
        }))
    }
}

// MARK: - The Mac and iPad

/// All Lines in a sheet: the lines in a table, newest first, with a search,
/// *Show* and the account, each line's *What it is* menu and why it is
/// what it is.
struct ImportAllLinesSheet: View {
    let model: ImportController

    @State private var filter: StatementLinesFilter
    @State private var selection: String?
    /// The line a new rule starts from.
    @State private var ruleLine: BatchStatementLine?
    @State private var moveRequest: StatementMoveRequest?
    @Environment(\.dismiss) private var dismiss

    init(model: ImportController, filter: StatementLinesFilter = StatementLinesFilter()) {
        self.model = model
        _filter = State(initialValue: filter)
    }

    private enum Columns {
        static let date = PageTableColumn(min: 60, max: 88)
        static let account = PageTableColumn(min: 90, max: 120)
        static let text = PageTableColumn(min: 160, max: .infinity)
        static let amount = PageTableColumn(min: 90, max: 110, alignment: .trailing)
        static let whatItIs = PageTableColumn(min: 170, max: 200)
        static let why = PageTableColumn(min: 120, max: 150)
    }

    var body: some View {
        let flow = model.flow
        let lines = flow.statementLines(matching: filter)
        VStack(spacing: 0) {
            header(flow)
            Divider()
            ScrollView {
                PageTable(lines, open: { _ in }, selection: $selection) {
                    Text("Date").pageTableColumn(Columns.date)
                    Text("Account").pageTableColumn(Columns.account)
                    Text("Description").pageTableColumn(Columns.text)
                    Text("Amount").pageTableColumn(Columns.amount)
                    Text("What it is").pageTableColumn(Columns.whatItIs)
                    Text("Why").pageTableColumn(Columns.why)
                } row: { line in
                    row(line, flow: flow)
                } menu: { line in
                    menuItems(line)
                }
                .padding(.horizontal, Metrics.m)
                .padding(.vertical, Metrics.s)
            }
            .overlay {
                if lines.isEmpty {
                    Text(flow.allStatementLines.isEmpty ? "No lines yet." : "No lines match.")
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            Divider()
            HStack(spacing: Metrics.m) {
                Text("A change here applies to this line only. “Every … Line” makes a rule, kept for the next "
                    + "statement.")
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, Metrics.l)
            .padding(.vertical, Metrics.s)
        }
        .background(Palette.card)
        #if os(macOS)
        .frame(minWidth: 900, idealWidth: 1040, minHeight: 520, idealHeight: 700)
        #endif
        .sheet(item: $ruleLine) { line in
            ImportStatementRuleSheet(model: model, line: line)
        }
        .sheet(item: $moveRequest) { request in
            ImportMovedSheet(model: model, request: request)
        }
    }

    /// The title, how many lines, and the search, *Show* and the account.
    private func header(_ flow: ImportFlow) -> some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("All Lines")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Metrics.m)
                Text(flow.allLinesCaption)
                    .foregroundStyle(Palette.secondaryInk)
            }
            HStack(spacing: Metrics.m) {
                HStack(spacing: Metrics.xs) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Palette.secondaryInk)
                        .accessibilityHidden(true)
                    TextField("Search descriptions and senders", text: $filter.search)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, Metrics.s)
                .padding(.vertical, Metrics.xs)
                .background(Palette.page, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Picker("Show", selection: $filter.show) {
                    ForEach(StatementLinesFilter.Show.allCases, id: \.self) { show in
                        Text(show.title).tag(show)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                ImportLinesAccountPicker(model: model, account: $filter.account)
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
            }
        }
        .padding(.horizontal, Metrics.l)
        .padding(.top, Metrics.l)
        .padding(.bottom, Metrics.m)
    }

    @ViewBuilder
    private func row(_ line: BatchStatementLine, flow: ImportFlow) -> some View {
        let isSelected = selection == line.id
        Text(AmountFormat.shortDate(line.date))
            .monospacedDigit()
            .privacySensitiveInFeedback()
            .pageTableColumn(Columns.date)
        Text(verbatim: flow.accountName(line.account))
            .foregroundStyle(Palette.secondaryInk)
            .privacySensitiveInFeedback()
            .pageTableColumn(Columns.account)
        Text(verbatim: line.line.text.isEmpty ? "—" : line.line.text)
            .fontWeight(isSelected ? .semibold : .regular)
            .help(line.line.text)
            .privacySensitiveInFeedback()
            .pageTableColumn(Columns.text)
        Text(verbatim: ImportFlow.lineAmount(line.amount))
            .monospacedDigit()
            .privacySensitiveAmount()
            .pageTableColumn(Columns.amount)
        whatItIsMenu(line, flow: flow, isSelected: isSelected)
            .pageTableColumn(Columns.whatItIs)
        Text(verbatim: flow.why(line))
            .font(.caption)
            .foregroundStyle(Palette.secondaryInk)
            .privacySensitiveInFeedback()
            .pageTableColumn(Columns.why)
    }

    /// The line's class as a pop-up: plain, and bordered on the selected line.
    @ViewBuilder
    private func whatItIsMenu(_ line: BatchStatementLine, flow: ImportFlow, isSelected: Bool) -> some View {
        let menu = Menu {
            menuItems(line)
        } label: {
            Text(verbatim: flow.whatItIs(line))
        }
        .menuStyle(.button)
        .menuIndicator(.visible)
        .controlSize(.small)
        .fixedSize()
        .personalControl()
        if isSelected {
            menu.buttonStyle(.bordered)
        } else {
            menu.buttonStyle(.borderless)
        }
    }

    private func menuItems(_ line: BatchStatementLine) -> some View {
        StatementLineMenuItems(model: model, line: line, askMove: { moveRequest = $0 }, makeRule: { ruleLine = line })
    }
}

/// *All Accounts* or one account of the statements open.
private struct ImportLinesAccountPicker: View {
    let model: ImportController
    @Binding var account: AccountID?

    var body: some View {
        Picker("Account", selection: $account) {
            Text("All Accounts").tag(AccountID?.none)
            ForEach(model.flow.statementAccountsOpen, id: \.id) { account in
                Text(verbatim: account.name).tag(AccountID?.some(account.id))
            }
        }
        .personalControl()
    }
}

// MARK: - iPhone

/// All Lines on iPhone, pushed from Income: the lines by month, newest
/// first, with a search, chips for *Show* and the account in the toolbar.
/// Tap a line to answer it, with *Every “…” Line…* under it; swipe it for
/// *Left Out* or *Interest*.
struct ImportAllLinesList: View {
    let model: ImportController

    @State private var filter = StatementLinesFilter()
    /// The line open to answer, by ID.
    @State private var expanded: String?
    @State private var ruleLine: BatchStatementLine?
    @State private var moveRequest: StatementMoveRequest?

    var body: some View {
        let flow = model.flow
        let months = flow.statementLineMonths(matching: filter)
        let showsAccount = filter.account == nil && flow.statementAccountsOpen.count > 1
        List {
            Section {
                chips
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            ForEach(months) { month in
                Section {
                    ForEach(month.lines) { line in
                        row(line, flow: flow, showsAccount: showsAccount)
                    }
                } header: {
                    Text(ImportFlow.monthTitle(month.month))
                        .privacySensitiveInFeedback()
                } footer: {
                    if month.id == months.last?.id {
                        Text("Tap a line to change what it is. Swipe left for Left Out or Interest.")
                    }
                }
            }
        }
        .overlay {
            if months.isEmpty {
                Text(flow.allStatementLines.isEmpty ? "No lines yet." : "No lines match.")
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .searchable(text: $filter.search, prompt: "Search")
        .navigationTitle("All Lines")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ImportLinesAccountPicker(model: model, account: $filter.account)
                        .pickerStyle(.inline)
                } label: {
                    HStack(spacing: Metrics.xs) {
                        Text(verbatim: filter.account.map { flow.accountName($0) } ?? "All Accounts")
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .accessibilityHidden(true)
                    }
                }
                .personalControl()
            }
        }
        .sheet(item: $ruleLine) { line in
            ImportStatementRuleSheet(model: model, line: line)
        }
        .sheet(item: $moveRequest) { request in
            ImportMovedSheet(model: model, request: request)
        }
    }

    /// *Show* as chips: All, Income, Spending, One-off, Tax, Moved.
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Metrics.s) {
                ForEach(StatementLinesFilter.Show.allCases, id: \.self) { show in
                    let isSelected = filter.show == show
                    Button {
                        filter.show = show
                    } label: {
                        Text(show.title)
                            .font(.subheadline)
                            .padding(.horizontal, Metrics.m)
                            .padding(.vertical, 5)
                            .foregroundStyle(isSelected ? Palette.card : Palette.ink)
                            .background(isSelected ? Palette.ink : Palette.card, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ line: BatchStatementLine, flow: ImportFlow, showsAccount: Bool) -> some View {
        let isExpanded = expanded == line.id
        VStack(alignment: .leading, spacing: Metrics.xs) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: line.line.text.isEmpty ? "—" : line.line.text)
                        .fontWeight(isExpanded ? .semibold : .regular)
                        .lineLimit(isExpanded ? 3 : 1)
                        .privacySensitiveInFeedback()
                    Spacer(minLength: Metrics.s)
                    Text(verbatim: ImportFlow.lineAmount(line.amount))
                        .monospacedDigit()
                        .privacySensitiveAmount()
                }
                Text(verbatim: flow.linesCaption(line, showsAccount: showsAccount, showsClass: !isExpanded))
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .privacySensitiveInFeedback()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation { expanded = isExpanded ? nil : line.id }
            }
            .accessibilityAddTraits(.isButton)
            if isExpanded {
                StatementAnswerPicker(selection: flow.answerChoice(line, current: true),
                                      isAsking: line.line.needsAnswer) { choice in
                    switch choice {
                    case .statementClass(let statementClass): model.flow.setStatementClass(statementClass, for: line)
                    case .moved: moveRequest = StatementMoveRequest(line: line)
                    }
                }
                .padding(.top, Metrics.xs)
                Button {
                    ruleLine = line
                } label: {
                    Text(verbatim: "Every “\(ImportFlow.suggestedRulePhrase(for: line.line))” Line…")
                        .privacySensitiveInFeedback()
                }
                .buttonStyle(.borderless)
            }
        }
        .listRowBackground(isExpanded ? Palette.accent.opacity(0.08) : Palette.card)
        .swipeActions(edge: .trailing) {
            Button("Left Out") { model.flow.setStatementClass(.ignore, for: line) }
                .tint(Palette.secondaryInk)
            Button("Interest") { model.flow.setStatementClass(.interest, for: line) }
                .tint(Palette.accent)
        }
    }
}

// MARK: - A rule

/// *Every “…” Line*: makes a rule from a line, in every statement open: the
/// words a line's text must have (the line's sender to start), and what
/// every such line is, a class or money moved to or from one of your
/// accounts. A rule with the words already can be removed.
struct ImportStatementRuleSheet: View {
    let model: ImportController
    let line: BatchStatementLine

    @State private var phrase: String
    @State private var target: StatementRuleTarget
    @Environment(\.dismiss) private var dismiss

    init(model: ImportController, line: BatchStatementLine) {
        self.model = model
        self.line = line
        let phrase = ImportFlow.suggestedRulePhrase(for: line.line)
        _phrase = State(initialValue: phrase)
        _target = State(initialValue: model.flow.statementRuleTarget(matching: phrase)
            ?? Self.target(of: line, in: model.flow))
    }

    /// What the line is now, as a rule's target.
    private static func target(of line: BatchStatementLine, in flow: ImportFlow) -> StatementRuleTarget {
        if line.line.statementClass == .transfer, let account = flow.moveAccount(line),
           flow.moveChoices(for: line).contains(where: { $0.id == account }) {
            return .moved(account)
        }
        let statementClass = line.line.statementClass
        return ImportFlow.statementClasses.contains(statementClass) ? .statementClass(statementClass)
            : .statementClass(.spending)
    }

    /// The targets to pick from, the one picked among them.
    private func choices(in flow: ImportFlow) -> [StatementRuleTarget] {
        let offered = flow.statementRuleTargets(for: line)
        return offered.contains(target) ? offered : offered + [target]
    }

    var body: some View {
        let flow = model.flow
        let offered = choices(in: flow)
        let existing = flow.statementRule(matching: phrase)
        NavigationStack {
            Form {
                Section {
                    TextField("Words", text: $phrase)
                        .privacySensitiveInFeedback()
                    Picker("Every such line is", selection: $target) {
                        ForEach(offered, id: \.self) { target in
                            Text(verbatim: flow.statementRuleTargetTitle(target)).tag(target)
                        }
                    }
                    .personalControl()
                } footer: {
                    Text(matches)
                }
                Section {
                    Text(verbatim: line.line.text)
                        .privacySensitiveInFeedback()
                } header: {
                    Text("The line")
                }
                if existing != nil {
                    Section {
                        Button("Remove Rule", role: .destructive) {
                            model.flow.setStatementRule(to: nil, for: phrase)
                            dismiss()
                        }
                    } footer: {
                        Text("Its lines get the class the rest of the rules, the words or their sign give them.")
                    }
                }
            }
            .formStyle(.grouped)
            .personalNavigationTitle("Every “\(phrase.trimmingCharacters(in: .whitespaces))” Line", hidden: "Rule")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.flow.setStatementRule(to: target, for: phrase)
                        dismiss()
                    }
                    .disabled(flow.linesMatching(rule: phrase) == nil)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #endif
    }

    /// E.g. "Every line whose text has these words, ignoring case and accents: 3 lines in these statements…".
    private var matches: String {
        guard let count = model.flow.linesMatching(rule: phrase) else {
            return "Give a word or more that a line's text has, ignoring case and accents."
        }
        return "Every line whose text has these words, ignoring case and accents: " + Wording.count(count, "line")
            + " in these statements. A line you changed alone keeps its class. The rule is kept for the next "
            + "statement."
    }
}
