#if os(macOS)
import Model
import Prices
import SwiftUI
import Tracker

/// The check-in on the Mac (UI.md, "On the Mac"): a table that can be
/// filled in without touching the mouse. Columns Account, Last, Now,
/// Change, New money and From (where the value comes from, or what to do
/// for it); accounts by group. Under a cash or savings account, its money
/// in and out (and a savings account's interest) and what moved between
/// your accounts; under a trades account, its positions and cash. New
/// money is typed only for the kinds that ask for it. A row's note is in
/// its menu.
///
/// The statements of the check-in come first (UI.md, "Statements first"),
/// in a card that takes dropped files. The rows they fill in are
/// read-only, with "In · Out · Moved" under them; the accounts typed by
/// hand are grouped in one band, "Pension · Property · Debts".
///
/// Tab moves to the next cell, Return down the Now column, ⌘↩ opens the
/// review, where ⌘↩ saves. Click a row's state to mark it unchanged, or
/// right-click it for more.
///
/// A past check-in lists the accounts that open after its date last, under
/// "Opened later": a value entered there moves the account's opening date
/// back when the check-in is saved.
///
/// An account that records trades needs nothing typed: with new trades
/// since its last value it's done "from trades", with its value and new
/// money from its trades; without, it waits for a trade or *No Trades*.
/// Under it, *Add Trade…* (and *No Trades*) on the check-in's date, what its trades hold as
/// read-only sub-rows, then its cash from the trades with *From
/// Statement…* to type a statement's (none for an account that holds no
/// cash). Right-click it to compare with a statement's quantities.
struct CheckInTable: View {
    let draft: CheckInDraft
    @Bindable var session: CheckInSession

    @Environment(LibraryStore.self) private var library
    @Environment(CheckInStore.self) private var checkIn
    @FocusState private var focus: CheckInField?

    init(draft: CheckInDraft, session: CheckInSession) {
        self.draft = draft
        _session = Bindable(session)
    }

    var body: some View {
        // The draft follows the library with the statements it holds imported.
        let snapshot = checkIn.statementsLibrary
        let review = draft.review(in: snapshot)
        let statements = checkIn.heldStatements(for: draft)
        let forStatements = statements.groupsForStatements(dismissed: session.typesEveryValue)
        let sections = CheckInSection.sections(of: draft, in: snapshot, forStatements: forStatements)
        let rows = sections.flatMap(\.rows)
        let moneyInOut = Set(rows.filter { CheckInRowDisplay.showsMoneyInOut($0, forStatements: forStatements) }
            .map(\.account))
        let readOnly = Set(rows.filter { statements.isFromStatement($0) }.map(\.account))
        let order = CheckInFieldOrder.nowColumn(rows: rows, editingCash: session.editingCash, moneyInOut: moneyInOut,
                                                readOnly: readOnly)
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    table(review: review, sections: sections, order: order, statements: statements,
                          forStatements: forStatements)
                }
                .onChange(of: session.focusRequest) { _, request in
                    guard let request, session.page == nil else { return }
                    session.focusRequest = nil
                    Task { @MainActor in
                        // Let a closing sheet hand the keyboard back first.
                        try? await Task.sleep(for: .milliseconds(250))
                        withAnimation { proxy.scrollTo(request.account, anchor: .center) }
                        focus = request
                    }
                }
            }
            Divider()
            CheckInTableFooter(draft: draft, statements: statements, session: session)
        }
        .frame(minWidth: 860)
        .background(Palette.card)
        .defaultFocus($focus, order.fields.first)
        .tradeEditorSheet($session.tradeRequest)
    }

    private func table(review: CheckInReview, sections: [CheckInSection], order: CheckInFieldOrder,
                       statements: CheckInStatements, forStatements: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CheckInBanners(draft: draft, session: session)
                .padding(.horizontal, CheckInColumns.inset)
                .padding(.vertical, Metrics.m)
            if library.canEdit, statements.isHeld || !statements.accounts.isEmpty || !statements.unreadable.isEmpty {
                CheckInStatementsBox(statements: statements, session: session) { urls in
                    Task { await session.addStatements(from: urls, checkIn: checkIn) }
                }
                .padding(.horizontal, CheckInColumns.inset)
                .padding(.bottom, Metrics.m)
            }
            CheckInTableHeader()
            Divider()
            ForEach(sections) { section in
                CheckInTableGroupHeader(title: section.title,
                                        note: section.isOpenedLater
                                            ? "Optional: a value moves the account's opening date back to this check-in"
                                            : nil)
                ForEach(section.rows) { row in
                    CheckInTableRow(
                        row: row, review: review.row(for: row.account), date: draft.date,
                        previousCheckIn: review.previousCheckIn, statements: statements,
                        forStatements: forStatements, session: session, focus: $focus, focused: focus
                    ) { field in
                        if let target = order.returnTarget(after: field) { focus = target }
                    }
                    .id(row.account)
                }
            }
            CheckInLegend(includesTrades: draft.rows.contains(where: \.isTrades))
                .padding(.horizontal, CheckInColumns.inset + Metrics.s)
                .padding(.vertical, Metrics.l)
        }
    }
}

/// The table's column widths. The Account column takes what's left.
private enum CheckInColumns {
    static let state: CGFloat = 32
    static let accountMin: CGFloat = 170
    static let last: CGFloat = 116
    static let now: CGFloat = 146
    static let change: CGFloat = 116
    static let newMoney: CGFloat = 126
    static let fromMin: CGFloat = 190
    /// Space left and right of the table.
    static let inset: CGFloat = Metrics.xl
}

/// One line of the table: seven cells at the columns' widths. The
/// Account and From columns share what's left.
private struct CheckInTableLine<StateCell: View, AccountCell: View, LastCell: View, NowCell: View, ChangeCell: View,
    NewMoneyCell: View, FromCell: View>: View {
    let state: StateCell
    let account: AccountCell
    let last: LastCell
    let now: NowCell
    let change: ChangeCell
    let newMoney: NewMoneyCell
    let from: FromCell

    init(@ViewBuilder state: () -> StateCell, @ViewBuilder account: () -> AccountCell,
         @ViewBuilder last: () -> LastCell, @ViewBuilder now: () -> NowCell, @ViewBuilder change: () -> ChangeCell,
         @ViewBuilder newMoney: () -> NewMoneyCell, @ViewBuilder from: () -> FromCell) {
        self.state = state()
        self.account = account()
        self.last = last()
        self.now = now()
        self.change = change()
        self.newMoney = newMoney()
        self.from = from()
    }

    var body: some View {
        HStack(spacing: 0) {
            state
                .frame(width: CheckInColumns.state)
            account
                .padding(.horizontal, Metrics.s)
                .frame(minWidth: CheckInColumns.accountMin, maxWidth: .infinity, alignment: .leading)
            last
                .padding(.horizontal, Metrics.s)
                .frame(width: CheckInColumns.last, alignment: .trailing)
            now
                .padding(.horizontal, Metrics.xs)
                .frame(width: CheckInColumns.now, alignment: .trailing)
            change
                .padding(.horizontal, Metrics.s)
                .frame(width: CheckInColumns.change, alignment: .trailing)
            newMoney
                .padding(.horizontal, Metrics.xs)
                .frame(width: CheckInColumns.newMoney, alignment: .trailing)
            from
                .padding(.horizontal, Metrics.s)
                .frame(minWidth: CheckInColumns.fromMin, maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, CheckInColumns.inset)
    }
}

/// Account · Last · Now · Change · New money · From.
private struct CheckInTableHeader: View {
    var body: some View {
        CheckInTableLine {
            Color.clear
        } account: {
            Text("Account")
        } last: {
            Text("Last")
        } now: {
            Text("Now")
        } change: {
            Text("Change")
        } newMoney: {
            Text("New money")
        } from: {
            Text("From")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Palette.secondaryInk)
        .frame(height: 28)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// "CASH", "INVESTMENTS", …, "OPENED LATER" on a band across the table,
/// with an optional note after it.
private struct CheckInTableGroupHeader: View {
    let title: String
    var note: String?

    var body: some View {
        HStack(spacing: Metrics.s) {
            Text(verbatim: title.uppercased())
                .tracking(0.5)
                .font(.caption2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            if let note {
                Text(verbatim: note)
                    .font(.caption2)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(Palette.secondaryInk)
        .padding(.horizontal, CheckInColumns.inset + Metrics.s)
        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
        .background(Palette.page)
    }
}

// MARK: - Rows

/// One account's line, and the lines under it: money in, out, interest and
/// moved for cash and savings; a trades account's trades, positions and
/// cash. Balances are in the account's currency; a trades account's value
/// in the base currency.
private struct CheckInTableRow: View {
    let row: CheckInRow
    let review: CheckInRowReview?
    /// The check-in's date.
    let date: CalendarDate
    let previousCheckIn: CalendarDate?
    /// The statements the check-in holds: the rows they fill in are
    /// read-only, and the From column says where each value comes from.
    let statements: CheckInStatements
    /// Whether the check-in starts with its statements: a row not reviewed
    /// shows money in and out once its balance is typed.
    let forStatements: Bool
    let session: CheckInSession
    let focus: FocusState<CheckInField?>.Binding
    let focused: CheckInField?
    /// Return in a field: down the Now column.
    let onReturn: (CheckInField) -> Void

    @Environment(CheckInStore.self) private var checkIn
    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            accountLine
            if isFromStatement {
                if let figures = statements.statementFigures(for: row, review: review, locale: locale) {
                    figuresLine(figures)
                }
            } else if row.isTrades {
                tradeActionsLine
                ForEach(review?.positions ?? [], id: \.instrument) { position in
                    derivedLine(position)
                }
                ForEach(row.positions) { position in
                    statementLine(position)
                }
                if row.showsCash && row.state != .skipped {
                    cashLine
                }
            } else if CheckInRowDisplay.showsMoneyInOut(row, forStatements: forStatements) {
                // Empty, money in is 0; money out follows money in and the change (a savings account's is 0).
                moneyLine(.moneyIn(row.account), title: "In", value: row.moneyIn) {
                    $0.setMoneyIn($1)
                }
                moneyLine(.moneyOut(row.account), title: "Out",
                          value: row.enteredMoneyOut ?? review?.valuation?.moneyOut) {
                    $0.setMoneyOut($1)
                }
                if CheckInRowDisplay.showsInterest(row, forStatements: forStatements) {
                    moneyLine(.interest(row.account), title: "Interest", value: row.interest) {
                        $0.setInterest($1)
                    }
                }
                if let moved = review?.moved {
                    movedLine(moved)
                }
            }
            Divider()
                .padding(.leading, CheckInColumns.inset)
        }
        .contextMenu {
            CheckInRowMenu(row: row, rule: rule, date: date, session: session, checkIn: checkIn,
                           isFromStatement: isFromStatement,
                           isFilledByStatement: statements.filled.contains(row.account))
        }
    }

    // MARK: Values

    private var isFromStatement: Bool { statements.isFromStatement(row) }

    private var account: Account? { library.account(row.account) }
    private var name: String { account?.name ?? row.account.rawValue }
    private var currency: CurrencyCode { account?.currency ?? library.baseCurrency }
    private var rule: FlowDefault { review?.flowRule ?? .ask }

    /// "last value 31 May", plus the currency when it isn't the base one.
    /// For an account that opens later, when it opens or that saving moves
    /// that. Where the value comes from is in the From column.
    private var detail: String? {
        var parts: [String] = []
        if let opening = CheckInWording.openingDetail(for: row, opened: account?.opened, date: date,
                                                      locale: locale) {
            parts.append(opening)
        } else if !row.isTrades,
                  let note = CheckInWording.lastValueNote(for: row, previousCheckIn: previousCheckIn, locale: locale) {
            parts.append(note.prefix(1).lowercased() + String(note.dropFirst()))
        }
        if currency != library.baseCurrency { parts.append(currency.rawValue) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Balances in the account's currency; a trades account's value in the base currency.
    private var lastAmount: Decimal? {
        row.mode == .balance ? row.previous?.balance : review?.previousValue
    }

    private var nowAmount: Decimal? {
        row.mode == .balance ? row.balance : review?.value?.knownValue
    }

    /// "—" while the row isn't reviewed, or is skipped.
    private var changeAmount: Decimal? {
        guard row.state != .skipped, row.state != .notReviewed, let now = nowAmount, let last = lastAmount else {
            return nil
        }
        return now - last
    }

    /// What the state cell says on hover.
    private var stateHelp: String {
        if row.followsTrades { return "From trades: its value and new money come from its trades" }
        guard row.canMarkUnchanged else { return CheckInWording.stateName(for: row) }
        return row.isTrades ? CheckInWording.markUnchangedTitle(for: row) : "Mark unchanged"
    }

    // MARK: Account line

    private var accountLine: some View {
        CheckInTableLine {
            Button {
                markUnchanged()
            } label: {
                CheckInStateIndicator(row: row, size: 20)
            }
            .buttonStyle(.plain)
            .disabled(!row.canMarkUnchanged || row.state == .unchanged || isFromStatement)
            .help(stateHelp)
        } account: {
            HStack(spacing: 0) {
                Text(verbatim: name)
                    .fontWeight(.semibold)
                    .privacySensitiveInFeedback()
                if let detail {
                    Text(verbatim: " · " + detail)
                        .foregroundStyle(Palette.secondaryInk)
                        .privacySensitiveInFeedback()
                }
            }
            .lineLimit(1)
            .help(CheckInWording.openingNote(for: row, opened: account?.opened, date: date, locale: locale) ?? "")
        } last: {
            CheckInPlainAmount(lastAmount)
                .foregroundStyle(Palette.secondaryInk)
        } now: {
            nowCell
        } change: {
            CheckInPlainDelta(changeAmount)
        } newMoney: {
            flowCell
        } from: {
            fromCell
        }
        .frame(height: 34)
    }

    @ViewBuilder
    private var nowCell: some View {
        if isFromStatement {
            CheckInPlainAmount(row.balance)
                .fontWeight(.semibold)
        } else if row.mode == .balance {
            let field = CheckInField.balance(row.account)
            let style = CheckInRowDisplay.balanceStyle(of: row.account, in: library.library)
            // Not reviewed, with money a statement moved into it: empty, with
            // the balance it can expect as the prompt.
            let suggestion = statements.suggestedBalance(for: row)
            CheckInNumberField(
                field, focus: focus, isFocused: focused == field, value: suggestion == nil ? row.balance : nil,
                style: style,
                prompt: suggestion.map { CheckInFieldFormat.text(for: $0, style: style, locale: locale) } ?? "0,00",
                label: "\(name), now", onSubmit: { onReturn(field) }
            ) { amount in
                guard let amount else { return }
                checkIn.updateRow(row.account) { $0.setBalance(amount) }
            }
            .checkInFieldBox(isFocused: focused == field, height: 26)
        } else {
            CheckInPlainAmount(nowAmount)
                .fontWeight(.medium)
        }
    }

    @ViewBuilder
    private var flowCell: some View {
        if row.state == .notReviewed, let expected = expectedFlow {
            // What the statements moved into it, until its value is typed.
            CheckInPlainAmount(expected, signed: true)
                .foregroundStyle(Palette.mutedInk)
                .help("What the statements moved into it since its last value")
        } else if row.state == .skipped {
            Text(verbatim: "—")
                .foregroundStyle(Palette.mutedInk)
        } else if !CheckInRowDisplay.canEditFlow(row, rule: rule) {
            // Worked out (docs/ACCOUNTS.md, "New money"): from the trades, or from what's typed.
            CheckInPlainAmount(row.state == .notReviewed ? nil : review?.flow, signed: true)
                .foregroundStyle(Palette.secondaryInk)
                .help(row.isTrades ? CheckInWording.tradeFlowExplanation : CheckInWording.workedOutFlowExplanation)
        } else {
            let field = CheckInField.flow(row.account)
            let rule = self.rule
            let value = row.isFlowEdited ? row.enteredFlow : (row.state == .notReviewed ? nil : review?.flow)
            CheckInNumberField(
                field, focus: focus, isFocused: focused == field, value: value,
                prompt: row.state == .notReviewed ? "—" : (rule == .ask ? "unknown" : "0,00"),
                label: field.name(in: library.library), allowsEmpty: true, onSubmit: { onReturn(field) }
            ) { amount in
                checkIn.updateRow(row.account) { CheckInEditing.enterFlow(amount, rule: rule, in: &$0) }
            }
            .checkInFieldBox(isFocused: focused == field, height: 26)
        }
    }

    /// The new money the statements' moves give a row not reviewed: `nil`
    /// when they only paid it (a debt), whose new money is worked out once
    /// its value is typed.
    private var expectedFlow: Decimal? {
        guard let moves = statements.expectedMoves(for: row), !moves.allSatisfy(\.isPayment) else { return nil }
        return statements.expectedAmount(for: row)
    }

    /// Where the value comes from, or what to do for it: "Statement · 2
    /// lines to answer" opens that file's Income. A row's note shows after
    /// it; it's written in the row's menu.
    @ViewBuilder
    private var fromCell: some View {
        let from = statements.from(for: row, locale: locale)
        HStack(spacing: Metrics.xs) {
            if let file = from.opensFile {
                Button {
                    session.answer(file: file, checkIn: checkIn)
                } label: {
                    AmountSentenceText(from.text)
                        .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)
                .help("Opens the statement's Income to answer its lines")
            } else {
                AmountSentenceText(from.text)
                    .foregroundStyle(Palette.secondaryInk)
            }
            if let note = row.note, !note.isEmpty {
                Image(systemName: "note.text")
                    .foregroundStyle(Palette.mutedInk)
                    .help(note)
                    .accessibilityLabel(Text(verbatim: "Note: " + note))
                    .privacySensitiveInFeedback()
            }
        }
        .font(.caption)
        .lineLimit(2)
        .monospacedDigit()
    }

    /// "In 3.400,00 · Out 3.210,20 · Moved −500,00" under a row a statement
    /// filled in, read-only.
    private func figuresLine(_ figures: AmountSentence) -> some View {
        CheckInTableLine {
            Color.clear
        } account: {
            AmountSentenceText(figures)
                .foregroundStyle(Palette.secondaryInk)
                .monospacedDigit()
                .lineLimit(1)
                .padding(.leading, Metrics.l)
        } last: {
            Color.clear
        } now: {
            Color.clear
        } change: {
            Color.clear
        } newMoney: {
            Color.clear
        } from: {
            Color.clear
        }
        .font(.caption)
        .frame(height: 20)
        .padding(.bottom, 4)
    }

    // MARK: Trades accounts

    /// A position the trades hold on the date, read-only: "VWCE · × 138,42 = 58.482".
    private func derivedLine(_ position: CheckInPositionReview) -> some View {
        let instrument = library.library.instruments[position.instrument]
        return CheckInTableLine {
            Color.clear
        } account: {
            HStack(spacing: 0) {
                Text(verbatim: CheckInWording.instrumentLabel(position.instrument, instrument: instrument))
                    .fontWeight(.medium)
                    .privacySensitiveInFeedback()
                Text(verbatim: " · " + CheckInWording.priceText(unit: "", price: position.price, locale: locale) + " = ")
                    .foregroundStyle(Palette.secondaryInk)
                    .privacySensitiveInFeedback()
                CheckInPlainAmount(position.value)
                    .foregroundStyle(Palette.secondaryInk)
            }
            .lineLimit(1)
            .padding(.leading, Metrics.l)
        } last: {
            Text(verbatim: CheckInWording.quantity(position.previousQuantity, instrument: instrument, locale: locale))
                .monospacedDigit()
                .foregroundStyle(Palette.secondaryInk)
                .privacySensitiveAmount()
        } now: {
            Text(verbatim: CheckInWording.quantity(position.quantity, instrument: instrument, locale: locale))
                .monospacedDigit()
                .privacySensitiveAmount()
                .help("From the account's trades. Add a trade to change it.")
        } change: {
            CheckInQuantityChange(position.quantity - position.previousQuantity)
        } newMoney: {
            Text("from trades")
                .foregroundStyle(Palette.mutedInk)
        } from: {
            Color.clear
        }
        .font(.callout)
        .frame(height: 30)
    }

    /// A quantity entered from a broker statement, compared with the trades.
    private func statementLine(_ position: CheckInPosition) -> some View {
        let instrument = library.library.instruments[position.instrument]
        let field = CheckInField.quantity(row.account, position.instrument)
        return CheckInTableLine {
            Color.clear
        } account: {
            HStack(spacing: 0) {
                Text("Statement")
                    .foregroundStyle(Palette.secondaryInk)
                Text(verbatim: " · " + CheckInWording.instrumentLabel(position.instrument, instrument: instrument))
                    .fontWeight(.medium)
                    .privacySensitiveInFeedback()
            }
            .lineLimit(1)
            .padding(.leading, Metrics.l)
        } last: {
            Text(verbatim: CheckInWording.quantity(position.previousQuantity, instrument: instrument, locale: locale))
                .monospacedDigit()
                .foregroundStyle(Palette.secondaryInk)
                .privacySensitiveAmount()
                .help("What the trades give")
        } now: {
            CheckInNumberField(
                field, focus: focus, isFocused: focused == field, value: position.quantity, style: .quantity,
                prompt: "0", label: field.name(in: library.library) + ", statement", onSubmit: { onReturn(field) }
            ) { quantity in
                guard let quantity else { return }
                checkIn.updateRow(row.account) { $0.setQuantity(quantity, of: position.instrument) }
            }
            .checkInFieldBox(isFocused: focused == field, height: 24)
        } change: {
            CheckInQuantityChange(position.quantityChange)
                .help("The statement minus the trades")
        } newMoney: {
            Button("Remove") {
                checkIn.updateRow(row.account) { $0.removePosition(position.instrument) }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        } from: {
            Color.clear
        }
        .font(.callout)
        .frame(height: 30)
    }

    /// "Bought or sold since 30 Sep? [Add Trade…] [No Trades]" and the new
    /// money's parts.
    private var tradeActionsLine: some View {
        CheckInTableLine {
            Color.clear
        } account: {
            HStack(spacing: Metrics.m) {
                Text(verbatim: CheckInWording.addTradePrompt(for: row, locale: locale))
                    .font(.callout)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .privacySensitiveInFeedback()
                    .accessibilityHidden(true)
                Button {
                    session.addTrade(to: row.account, on: date)
                } label: {
                    Label("Add Trade…", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!library.canEdit)
                .accessibilityLabel(Text(verbatim: CheckInWording.addTradeLabel(account: name, date: date,
                                                                                locale: locale)))
                if CheckInRowDisplay.offersNoTrades(row) {
                    // Waiting for its trades: there may have been none (docs/ACCOUNTS.md, "Settled questions" 4).
                    Button("No Trades") { markUnchanged() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("No trades since the last value: keeps what the trades give")
                }
                if let detail = tradeFlowDetail {
                    AmountSentenceText(detail)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                        .help(CheckInWording.tradeFlowExplanation)
                }
            }
            .padding(.leading, Metrics.l)
        } last: {
            Color.clear
        } now: {
            Color.clear
        } change: {
            Color.clear
        } newMoney: {
            Color.clear
        } from: {
            Color.clear
        }
        .frame(height: 32)
    }

    /// "deposits +200,60 · cash difference +11,30", when there's something to split.
    private var tradeFlowDetail: AmountSentence? {
        CheckInTradeFlow.make(for: row, date: date, valuator: library.valuator)
            .flatMap { CheckInWording.tradeFlowDetail($0, locale: locale) }
    }

    /// The cash. A trades account's comes from its trades, read-only, with
    /// *From Statement…* to type a statement's instead; once typed, *Use
    /// Trades' Cash* goes back.
    private var cashLine: some View {
        let field = CheckInField.cash(row.account)
        let hasField = CheckInRowDisplay.showsCashField(row, isEditing: session.editingCash.contains(row.account))
        let cash = row.isTrades && !hasField ? (row.cash ?? row.derived?.cash) : row.cash
        let change: Decimal? = cash == nil && row.previous?.cash == nil
            ? nil : (cash ?? 0) - (row.previous?.cash ?? 0)
        return CheckInTableLine {
            Color.clear
        } account: {
            HStack(spacing: 0) {
                Text("Cash")
                    .fontWeight(.medium)
                Text(verbatim: " · " + currency.rawValue + cashSource)
                    .foregroundStyle(Palette.secondaryInk)
            }
            .lineLimit(1)
            .padding(.leading, Metrics.l)
        } last: {
            CheckInPlainAmount(row.previous?.cash)
                .foregroundStyle(Palette.secondaryInk)
        } now: {
            if hasField {
                CheckInNumberField(
                    field, focus: focus, isFocused: focused == field, value: row.cash,
                    prompt: row.isTrades && row.derived != nil
                        ? CheckInFieldFormat.text(for: row.derived?.cash, style: .amount, locale: locale) : "0,00",
                    label: field.name(in: library.library), allowsEmpty: true, onSubmit: { onReturn(field) }
                ) { amount in
                    checkIn.updateRow(row.account) { $0.setCash(amount) }
                }
                .checkInFieldBox(isFocused: focused == field, height: 24)
            } else {
                CheckInPlainAmount(cash)
                    .help("From the account's trades. Use From Statement… to compare with a statement's cash.")
            }
        } change: {
            CheckInPlainDelta(change)
        } newMoney: {
            cashAction(hasField: hasField)
        } from: {
            Color.clear
        }
        .font(.callout)
        .frame(height: 30)
    }

    /// Money in or out of a cash or savings account, or a savings account's
    /// interest, under its balance (docs/ACCOUNTS.md, "Settled questions" 8).
    /// Money out follows money in and the change until it's typed.
    private func moneyLine(_ field: CheckInField, title: LocalizedStringKey, value: Decimal?,
                           set: @escaping (inout CheckInRow, Decimal?) -> Void) -> some View {
        CheckInTableLine {
            Color.clear
        } account: {
            Text(title)
                .fontWeight(.medium)
                .lineLimit(1)
                .padding(.leading, Metrics.l)
        } last: {
            Color.clear
        } now: {
            CheckInNumberField(
                field, focus: focus, isFocused: focused == field, value: value, prompt: CheckInWording.moneyPrompt,
                label: field.name(in: library.library), allowsEmpty: true, onSubmit: { onReturn(field) }
            ) { amount in
                checkIn.updateRow(row.account) { set(&$0, amount) }
            }
            .checkInFieldBox(isFocused: focused == field, height: 24)
        } change: {
            Color.clear
        } newMoney: {
            Color.clear
        } from: {
            Color.clear
        }
        .font(.callout)
        .frame(height: 30)
    }

    /// "Moved" and the row's part in what moved between your own accounts,
    /// read-only in the Now column: worked out, not typed.
    private func movedLine(_ moved: Decimal) -> some View {
        CheckInTableLine {
            Color.clear
        } account: {
            Text("Moved between your accounts")
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
                .padding(.leading, Metrics.l)
        } last: {
            Color.clear
        } now: {
            CheckInPlainAmount(moved, signed: true)
                .foregroundStyle(Palette.secondaryInk)
                .help(CheckInWording.movedExplanation)
        } change: {
            Color.clear
        } newMoney: {
            Color.clear
        } from: {
            Color.clear
        }
        .font(.callout)
        .frame(height: 30)
    }

    /// " · from trades" or " · from a statement" after a trades account's cash.
    private var cashSource: String {
        guard row.isTrades, row.derived != nil else { return "" }
        return row.hasStatementCash ? " · from a statement" : " · from trades"
    }

    /// A trades account's *From Statement…* or *Use Trades' Cash*; "—" otherwise.
    @ViewBuilder
    private func cashAction(hasField: Bool) -> some View {
        if row.isTrades && row.derived != nil {
            if hasField {
                Button("Use Trades' Cash") { session.useTradesCash(row.account, checkIn: checkIn) }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Drops the cash from the statement")
            } else {
                Button("From Statement…") { session.enterStatementCash(row.account) }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(!library.canEdit)
                    .help("Type the cash from a statement, to compare: a difference counts as new money")
            }
        } else {
            Text(verbatim: "—")
                .foregroundStyle(Palette.mutedInk)
        }
    }

    // MARK: Actions

    private func markUnchanged() {
        session.markUnchanged(row.account, checkIn: checkIn)
    }
}

// MARK: - Footer

/// "4 of 8 done · 3 from statements, 1 from trades · 2 lines to answer
/// first   [Mark Rest Unchanged] [Review]". Lines to answer are a hint:
/// Review opens all the same.
private struct CheckInTableFooter: View {
    let draft: CheckInDraft
    let statements: CheckInStatements
    let session: CheckInSession

    @Environment(CheckInStore.self) private var checkIn

    var body: some View {
        let progress = CheckInWording.progress(draft, statements: statements, compact: false)
        HStack(spacing: Metrics.l) {
            HStack(spacing: 0) {
                Text(verbatim: progress.lead)
                    .fontWeight(.semibold)
                if let detail = progress.detail {
                    Text(verbatim: " · " + detail)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            .font(.callout)
            .monospacedDigit()
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            Spacer(minLength: Metrics.m)
            Button("Mark Rest Unchanged") { checkIn.markRestUnchanged() }
                .disabled(draft.isReadyToSave)
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .help("Keeps the last value of every account not reviewed yet (⇧⌘U)")
            Button("Review") { session.page = .review }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(session.isSaving)
                .help("Review the check-in before saving it (⌘↩)")
        }
        .padding(.horizontal, Metrics.xl)
        .frame(height: 52)
        .background(.bar)
    }
}

#Preview("Mac table") {
    let model = CheckInPreviewData.model()
    NavigationStack {
        if let draft = model.checkIn.draft {
            CheckInTable(draft: draft, session: CheckInSession())
                .navigationTitle("Check-in")
        }
    }
    .frame(width: 1100, height: 720)
    .appEnvironment(model)
}

#Preview("Mac table, comparing a statement") {
    let model = CheckInPreviewData.modelComparingStatement()
    NavigationStack {
        if let draft = model.checkIn.draft {
            CheckInTable(draft: draft, session: CheckInSession())
                .navigationTitle("Check-in")
        }
    }
    .frame(width: 1100, height: 720)
    .appEnvironment(model)
}
#endif
