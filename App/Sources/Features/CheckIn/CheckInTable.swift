#if os(macOS)
import Model
import Prices
import SwiftUI
import Tracker

/// The check-in on the Mac (UI.md, "On the Mac"): a table that can be
/// filled in without touching the mouse. Columns Account, Last, Now,
/// Change, New money and Note; accounts by group, positions and cash as
/// sub-rows.
///
/// Tab moves to the next cell, Return down the Now column, ⌘↩ opens the
/// review, where ⌘↩ saves. Click a row's state to mark it unchanged, or
/// right-click it for more.
///
/// A past check-in lists the accounts that open after its date last, under
/// "Opened later": a value entered there moves the account's opening date
/// back when the check-in is saved.
///
/// An account that records trades needs nothing typed: it's done "from
/// trades" from the start, with its value and new money from its trades.
/// Under it, *Add Trade…* on the check-in's date, what its trades hold as
/// read-only sub-rows, then its cash from the trades with *From
/// Statement…* to type a statement's (none for an account that holds no
/// cash). Right-click it to compare with a statement's quantities.
struct CheckInTable: View {
    let draft: CheckInDraft
    let session: CheckInSession

    @Environment(LibraryStore.self) private var library
    @FocusState private var focus: CheckInField?

    init(draft: CheckInDraft, session: CheckInSession) {
        self.draft = draft
        self.session = session
    }

    var body: some View {
        let snapshot = library.library
        let review = draft.review(in: snapshot)
        let sections = CheckInSection.sections(of: draft, in: snapshot)
        let order = CheckInFieldOrder.nowColumn(rows: sections.flatMap(\.rows), editingCash: session.editingCash)
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    table(review: review, sections: sections, order: order)
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
            CheckInTableFooter(draft: draft, session: session)
        }
        .frame(minWidth: 860)
        .background(Palette.card)
        .defaultFocus($focus, order.fields.first)
        .tradeEditorSheet(tradeRequest)
    }

    /// The trade being added from a trades account's row.
    private var tradeRequest: Binding<TradeEditorTarget?> {
        Binding {
            session.tradeRequest
        } set: { target in
            session.tradeRequest = target
        }
    }

    private func table(review: CheckInReview, sections: [CheckInSection], order: CheckInFieldOrder) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CheckInBanners(draft: draft, session: session)
                .padding(.horizontal, CheckInColumns.inset)
                .padding(.vertical, Metrics.m)
            CheckInTableHeader(previousCheckIn: review.previousCheckIn)
            Divider()
            ForEach(sections) { section in
                CheckInTableGroupHeader(title: section.title,
                                        note: section.isOpenedLater
                                            ? "Optional: a value moves the account's opening date back to this check-in"
                                            : nil)
                ForEach(section.rows) { row in
                    CheckInTableRow(
                        row: row, review: review.row(for: row.account), date: draft.date,
                        previousCheckIn: review.previousCheckIn, session: session, focus: $focus, focused: focus
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
    static let note: CGFloat = 160
    /// Space left and right of the table.
    static let inset: CGFloat = Metrics.xl
}

/// One line of the table: seven cells at the columns' widths.
private struct CheckInTableLine<StateCell: View, AccountCell: View, LastCell: View, NowCell: View, ChangeCell: View,
    NewMoneyCell: View, NoteCell: View>: View {
    let state: StateCell
    let account: AccountCell
    let last: LastCell
    let now: NowCell
    let change: ChangeCell
    let newMoney: NewMoneyCell
    let note: NoteCell

    init(@ViewBuilder state: () -> StateCell, @ViewBuilder account: () -> AccountCell,
         @ViewBuilder last: () -> LastCell, @ViewBuilder now: () -> NowCell, @ViewBuilder change: () -> ChangeCell,
         @ViewBuilder newMoney: () -> NewMoneyCell, @ViewBuilder note: () -> NoteCell) {
        self.state = state()
        self.account = account()
        self.last = last()
        self.now = now()
        self.change = change()
        self.newMoney = newMoney()
        self.note = note()
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
            note
                .padding(.horizontal, Metrics.xs)
                .frame(width: CheckInColumns.note, alignment: .leading)
        }
        .padding(.horizontal, CheckInColumns.inset)
    }
}

/// Account · Last · 31 Aug · Now · Change · New money · Note.
private struct CheckInTableHeader: View {
    let previousCheckIn: CalendarDate?

    @Environment(\.locale) private var locale

    var body: some View {
        CheckInTableLine {
            Color.clear
        } account: {
            Text("Account")
        } last: {
            Text(verbatim: previousCheckIn.map { "Last · " + AmountFormat.shortDate($0, locale: locale) } ?? "Last")
        } now: {
            Text("Now")
        } change: {
            Text("Change")
        } newMoney: {
            Text("New money")
        } note: {
            Text("Note")
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

/// One account's line, and for holdings a line per position and one for
/// cash. Balances are in the account's currency; holdings' totals in the
/// base currency.
private struct CheckInTableRow: View {
    let row: CheckInRow
    let review: CheckInRowReview?
    /// The check-in's date.
    let date: CalendarDate
    let previousCheckIn: CalendarDate?
    let session: CheckInSession
    let focus: FocusState<CheckInField?>.Binding
    let focused: CheckInField?
    /// Return in a field: down the Now column.
    let onReturn: (CheckInField) -> Void

    @Environment(CheckInStore.self) private var checkIn
    @Environment(LibraryStore.self) private var library
    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            accountLine
            if row.isTrades {
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
            } else if row.mode == .holdings {
                ForEach(row.positions) { position in
                    positionLine(position)
                }
                cashLine
            }
            Divider()
                .padding(.leading, CheckInColumns.inset)
        }
        .contextMenu {
            rowMenu
        }
    }

    // MARK: Values

    private var account: Account? { library.account(row.account) }
    private var name: String { account?.name ?? row.account.rawValue }
    private var currency: CurrencyCode { account?.currency ?? library.baseCurrency }
    private var rule: FlowDefault { CheckInRowDisplay.flowRule(of: row.account, in: library.library) }

    /// "FinecoBank", "3 positions · 1 changed", "last value 31 May", plus
    /// the currency when it isn't the base one. For an account that opens
    /// later, when it opens or that saving moves that.
    private var detail: String? {
        var parts: [String] = []
        if let opening = CheckInWording.openingDetail(for: row, opened: account?.opened, date: date,
                                                      locale: locale) {
            parts.append(opening)
        } else if row.isTrades {
            parts.append(CheckInWording.tradesSummary(row, instruments: library.library.instruments, locale: locale))
        } else if row.mode == .holdings {
            parts.append(CheckInWording.holdingsSummary(row, instruments: library.library.instruments, locale: locale))
        } else if let note = CheckInWording.lastValueNote(for: row, previousCheckIn: previousCheckIn, locale: locale) {
            parts.append(note.prefix(1).lowercased() + String(note.dropFirst()))
        } else if let institution = account?.institution {
            parts.append(institution)
        }
        if currency != library.baseCurrency { parts.append(currency.rawValue) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Balances in the account's currency; holdings in the base currency.
    private var lastAmount: Decimal? {
        row.mode == .balance ? row.previous?.balance : review?.previousValue
    }

    private var nowAmount: Decimal? {
        row.mode == .balance ? row.balance : review?.value?.knownValue
    }

    private var changeAmount: Decimal? {
        guard row.state != .skipped, let now = nowAmount, let last = lastAmount else { return nil }
        return now - last
    }

    /// What the state cell says on hover.
    private var stateHelp: String {
        if row.followsTrades { return "From trades: its value and new money come from its trades" }
        guard CheckInRowDisplay.canMarkUnchanged(row) else { return CheckInWording.stateName(for: row) }
        return row.isTrades ? "Use the trades' values" : "Mark unchanged"
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
            .disabled(!CheckInRowDisplay.canMarkUnchanged(row) || row.state == .unchanged)
            .help(stateHelp)
        } account: {
            HStack(spacing: 0) {
                Text(verbatim: name)
                    .fontWeight(.medium)
                if let detail {
                    Text(verbatim: " · " + detail)
                        .foregroundStyle(Palette.secondaryInk)
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
        } note: {
            noteCell
        }
        .frame(height: 34)
    }

    @ViewBuilder
    private var nowCell: some View {
        if row.mode == .balance {
            let field = CheckInField.balance(row.account)
            CheckInNumberField(
                field, focus: focus, isFocused: focused == field, value: row.balance,
                style: CheckInRowDisplay.balanceStyle(of: row.account, in: library.library), prompt: "0,00",
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
        if row.state == .skipped {
            Text(verbatim: "—")
                .foregroundStyle(Palette.mutedInk)
        } else if row.isTrades && !CheckInRowDisplay.canEditTradeFlow(row) {
            CheckInPlainAmount(row.state == .notReviewed ? nil : review?.flow, signed: true)
                .foregroundStyle(Palette.secondaryInk)
                .help(CheckInWording.tradeFlowExplanation)
        } else {
            let field = CheckInField.flow(row.account)
            let rule = self.rule
            let value = row.isFlowEdited ? row.enteredFlow : (row.state == .notReviewed ? nil : review?.flow)
            CheckInNumberField(
                field, focus: focus, isFocused: focused == field, value: value,
                prompt: row.state == .notReviewed ? "—" : (rule == .ask ? "unknown" : "0,00"),
                label: field.name(in: library.library), allowsEmpty: true, onSubmit: { onReturn(field) }
            ) { amount in
                checkIn.updateRow(row.account) { row in
                    if let amount {
                        row.setFlow(amount)
                    } else if rule == .ask {
                        row.setFlow(nil)
                    } else {
                        row.resetFlow()
                    }
                }
            }
            .checkInFieldBox(isFocused: focused == field, height: 26)
        }
    }

    private var noteCell: some View {
        let field = CheckInField.note(row.account)
        return CheckInNoteField(
            field, focus: focus, isFocused: focused == field, note: row.note, label: "\(name), note",
            onSubmit: { onReturn(field) }
        ) { text in
            checkIn.updateRow(row.account) { $0.note = text.isEmpty ? nil : text }
        }
        .foregroundStyle(Palette.secondaryInk)
        .checkInFieldBox(isFocused: focused == field, height: 26)
    }

    // MARK: Positions and cash

    private func positionLine(_ position: CheckInPosition) -> some View {
        let instrument = library.library.instruments[position.instrument]
        let valued = review?.positions.first(where: { $0.instrument == position.instrument })
        let quantityField = CheckInField.quantity(row.account, position.instrument)
        let paidField = CheckInField.paid(row.account, position.instrument)
        return CheckInTableLine {
            Color.clear
        } account: {
            HStack(spacing: 0) {
                Text(verbatim: CheckInWording.instrumentLabel(position.instrument, instrument: instrument))
                    .fontWeight(.medium)
                Text(verbatim: " · " + priceText(valued?.price) + " = ")
                    .foregroundStyle(Palette.secondaryInk)
                CheckInPlainAmount(valued?.value)
                    .foregroundStyle(Palette.secondaryInk)
            }
            .lineLimit(1)
            .padding(.leading, Metrics.l)
        } last: {
            Text(verbatim: CheckInWording.quantity(position.previousQuantity, of: position.instrument,
                                                   instrument: instrument, locale: locale))
                .monospacedDigit()
                .foregroundStyle(Palette.secondaryInk)
        } now: {
            CheckInNumberField(
                quantityField, focus: focus, isFocused: focused == quantityField, value: position.quantity,
                style: .quantity, prompt: "0", label: quantityField.name(in: library.library),
                onSubmit: { onReturn(quantityField) }
            ) { quantity in
                guard let quantity else { return }
                checkIn.updateRow(row.account) { $0.setQuantity(quantity, of: position.instrument) }
            }
            .checkInFieldBox(isFocused: focused == quantityField, height: 24)
        } change: {
            CheckInQuantityChange(position.quantityChange)
        } newMoney: {
            if position.isIncrease {
                CheckInNumberField(
                    paidField, focus: focus, isFocused: focused == paidField, value: position.paid,
                    prompt: CheckInFieldFormat.text(for: valued?.estimatedPaid, style: .amount, locale: locale),
                    label: paidField.name(in: library.library), allowsEmpty: true,
                    onSubmit: { onReturn(paidField) }
                ) { amount in
                    checkIn.updateRow(row.account) { $0.setPaid(amount, for: position.instrument) }
                }
                .checkInFieldBox(isFocused: focused == paidField, height: 24)
                .help("What you paid for the added quantity. Empty uses the price on the check-in date.")
            } else {
                Text(verbatim: "—")
                    .foregroundStyle(Palette.mutedInk)
            }
        } note: {
            Color.clear
        }
        .font(.callout)
        .frame(height: 30)
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
                Text(verbatim: " · " + priceText(position.price) + " = ")
                    .foregroundStyle(Palette.secondaryInk)
                CheckInPlainAmount(position.value)
                    .foregroundStyle(Palette.secondaryInk)
            }
            .lineLimit(1)
            .padding(.leading, Metrics.l)
        } last: {
            Text(verbatim: CheckInWording.quantity(position.previousQuantity, of: position.instrument,
                                                   instrument: instrument, locale: locale))
                .monospacedDigit()
                .foregroundStyle(Palette.secondaryInk)
        } now: {
            Text(verbatim: CheckInWording.quantity(position.quantity, of: position.instrument, instrument: instrument,
                                                   locale: locale))
                .monospacedDigit()
                .privacySensitive()
                .help("From the account's trades. Add a trade to change it.")
        } change: {
            CheckInQuantityChange(position.quantity - position.previousQuantity)
        } newMoney: {
            Text("from trades")
                .foregroundStyle(Palette.mutedInk)
        } note: {
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
            }
            .lineLimit(1)
            .padding(.leading, Metrics.l)
        } last: {
            Text(verbatim: CheckInWording.quantity(position.previousQuantity, of: position.instrument,
                                                   instrument: instrument, locale: locale))
                .monospacedDigit()
                .foregroundStyle(Palette.secondaryInk)
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
        } note: {
            Color.clear
        }
        .font(.callout)
        .frame(height: 30)
    }

    /// "Bought or sold since 30 Sep? [Add Trade…]" and the new money's parts.
    private var tradeActionsLine: some View {
        CheckInTableLine {
            Color.clear
        } account: {
            HStack(spacing: Metrics.m) {
                Text(verbatim: CheckInWording.addTradePrompt(for: row, locale: locale))
                    .font(.callout)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
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
                if let detail = tradeFlowDetail {
                    Text(verbatim: detail)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                        .privacySensitive()
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
        } note: {
            Color.clear
        }
        .frame(height: 32)
    }

    /// "deposits +200,60 · cash difference +11,30", when there's something to split.
    private var tradeFlowDetail: String? {
        guard row.state == .updated || row.state == .unchanged,
              let flow = CheckInTradeFlow.make(for: row, date: date, valuator: library.valuator)
        else { return nil }
        return CheckInWording.tradeFlowDetail(flow, hidesAmounts: hidesAmounts, locale: locale)
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
        } note: {
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

    @ViewBuilder
    private var rowMenu: some View {
        if CheckInRowDisplay.canMarkUnchanged(row) && !row.followsTrades {
            Button(CheckInWording.markUnchangedTitle(for: row)) { markUnchanged() }
        }
        Button("Skip This Time") {
            checkIn.updateRow(row.account) { $0.skip() }
        }
        if row.isFlowEdited {
            Button("Use Automatic New Money") {
                checkIn.updateRow(row.account) { $0.resetFlow() }
            }
        }
        if row.isTrades {
            Button("Add Trade…") { session.addTrade(to: row.account, on: date) }
            if row.showsCash && row.state != .skipped && row.derived != nil {
                if CheckInRowDisplay.showsCashField(row, isEditing: session.editingCash.contains(row.account)) {
                    Button("Use Trades' Cash") { session.useTradesCash(row.account, checkIn: checkIn) }
                } else {
                    Button("Enter Cash From a Statement") { session.enterStatementCash(row.account) }
                }
            }
            if row.positions.isEmpty {
                Button("Compare With a Statement") {
                    checkIn.updateRow(row.account) { $0.enterStatementQuantities() }
                    if let first = row.derived?.positions.first(where: { $0.quantity != 0 }) {
                        session.focusRequest = .quantity(row.account, first.instrument)
                    }
                }
            } else {
                Button("Stop Comparing With a Statement") {
                    session.stopComparing(row.account, checkIn: checkIn)
                }
            }
        } else if row.mode == .holdings {
            let others = library.library.instruments.values
                .filter { row.position(for: $0.id) == nil }
                .sorted { $0.name.lowercased() < $1.name.lowercased() }
            if !others.isEmpty {
                Menu("Add a Position") {
                    ForEach(others) { instrument in
                        Button(instrument.name) {
                            checkIn.updateRow(row.account) { $0.setQuantity(0, of: instrument.id) }
                            session.focusRequest = .quantity(row.account, instrument.id)
                        }
                    }
                }
            }
        }
    }

    private func markUnchanged() {
        session.markUnchanged(row.account, checkIn: checkIn)
    }

    /// "× 138,42 €", "× 111.400,00 $": in the price's own currency.
    private func priceText(_ price: PriceRecord?) -> String {
        CheckInWording.priceText(unit: "", price: price, locale: locale)
    }
}

// MARK: - Footer

/// "7 of 9 reviewed ▬▬▬▭ · Not reviewed: Fondo pensione, Mutuo ·
/// [Mark rest unchanged] [Review & save ⌘↩]".
private struct CheckInTableFooter: View {
    let draft: CheckInDraft
    let session: CheckInSession

    @Environment(CheckInStore.self) private var checkIn
    @Environment(LibraryStore.self) private var library

    var body: some View {
        HStack(spacing: Metrics.l) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: CheckInWording.reviewed(draft))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                CheckInProgressBar(reviewed: draft.reviewedCount, total: draft.progressTotal)
                    .frame(width: 140)
            }
            if let notReviewed = CheckInWording.notReviewed(notReviewedNames) {
                Text(verbatim: notReviewed)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
            }
            Spacer(minLength: Metrics.m)
            Text("Tab and Return move between cells · ⌘↩ reviews and saves")
                .font(.caption)
                .foregroundStyle(Palette.mutedInk)
                .lineLimit(1)
            Button("Mark rest unchanged") { session.markRestUnchanged(checkIn: checkIn) }
                .disabled(draft.isReadyToSave)
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .help("Keeps the last value of every account not reviewed yet (⇧⌘U)")
            Button("Review & save") { session.page = .review }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(session.isSaving)
        }
        .padding(.horizontal, Metrics.xl)
        .frame(height: 60)
        .background(.bar)
    }

    private var notReviewedNames: [String] {
        draft.notReviewed.map { library.account($0)?.name ?? $0.rawValue }
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
