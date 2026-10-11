#if os(iOS)
import Model
import Prices
import SwiftUI
import Tracker

/// The check-in on iPhone and iPad (UI.md, "Check-in"): one scrolling page,
/// no wizard. The date and the prices' status at the top, then the accounts
/// by group, each with its state (● updated, ✓ unchanged, ○ not reviewed),
/// and a floating bar with the progress and "Mark rest unchanged".
///
/// Fields use the decimal keypad. The bar above it moves between fields
/// (▲ ▼), flips the sign (±, since the keypad has no minus) and closes it.
/// Swipe a row right to mark it unchanged, left to skip it; long-press for
/// the same and more.
///
/// A past check-in lists the accounts that open after its date last, in a
/// collapsed "Opened later" section: a value entered there moves the
/// account's opening date back when the check-in is saved.
///
/// Under a cash or savings account's balance, after its first value: money
/// in and out (and a savings account's interest), with what moved between
/// your accounts. New money is typed only for the kinds that ask for it.
///
/// An account that records trades needs nothing typed: with new trades
/// since its last value it's done "from trades"; without, it waits for a
/// trade or *No Trades*. It shows what its trades hold and their value at
/// the check-in's prices, *Add Trade…* on the check-in's date, its cash
/// from the trades (read-only, with *Enter From Statement* to compare; none
/// for an account that holds no cash) and its new money from the trades.
struct CheckInList: View {
    let draft: CheckInDraft
    @Bindable var session: CheckInSession

    @Environment(CheckInStore.self) private var checkIn
    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale
    @FocusState private var focus: CheckInField?
    @State private var signToggle = 0

    init(draft: CheckInDraft, session: CheckInSession) {
        self.draft = draft
        _session = Bindable(session)
    }

    var body: some View {
        let snapshot = library.library
        let review = draft.review(in: snapshot)
        let sections = CheckInSection.sections(of: draft, in: snapshot)
        let visible = CheckInSection.visibleRows(of: sections, showsOpenedLater: session.showsOpenedLater)
        let moneyInOut = Set(visible.filter { CheckInRowDisplay.showsMoneyInOut($0) }.map(\.account))
        let order = CheckInFieldOrder.list(rows: visible, review: review, expanded: session.expanded,
                                           editingFlows: session.editingFlows, editingCash: session.editingCash,
                                           moneyInOut: moneyInOut)
        ScrollViewReader { proxy in
            list(review: review, sections: sections, order: order, proxy: proxy)
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom) {
                    if focus == nil {
                        CheckInBottomBar(draft: draft, session: session)
                    }
                }
                .toolbar {
                    keyboardBar(order: order, library: snapshot, proxy: proxy)
                }
                .tradeEditorSheet($session.tradeRequest)
                .onChange(of: session.focusRequest) { _, request in
                    if let request, session.page == nil {
                        applyFocusRequest(request, proxy: proxy, after: .milliseconds(100))
                    }
                }
                .onAppear {
                    // Back from the review with a field to fix: wait for the pop to finish.
                    if let request = session.focusRequest {
                        applyFocusRequest(request, proxy: proxy, after: .milliseconds(450))
                    }
                }
        }
    }

    private func list(review: CheckInReview, sections: [CheckInSection], order: CheckInFieldOrder,
                      proxy: ScrollViewProxy) -> some View {
        let showsLater = CheckInSection.showsOpenedLater(in: sections, expanded: session.showsOpenedLater)
        let canCollapse = sections.contains { !$0.isOpenedLater }
        return List {
            Section {
                CheckInListHeader(draft: draft, review: review, session: session)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: Metrics.xs, bottom: Metrics.s, trailing: Metrics.xs))
                if let priceStatus {
                    Button {
                        session.page = .prices
                    } label: {
                        CheckInPriceStatusLabel(summary: priceStatus)
                    }
                }
            }
            ForEach(sections) { section in
                Section {
                    if !section.isOpenedLater || showsLater {
                        ForEach(section.rows) { row in
                            CheckInListRow(
                                row: row, review: review.row(for: row.account), date: draft.date,
                                previousCheckIn: review.previousCheckIn, session: session, focus: $focus,
                                focused: focus, signToggle: signToggle
                            ) { field in
                                if let target = order.next(after: field) { move(to: target, proxy: proxy) }
                            }
                            .id(row.account)
                        }
                    }
                } header: {
                    if section.isOpenedLater && canCollapse {
                        openedLaterHeader(count: section.rows.count)
                    } else {
                        Text(verbatim: section.title)
                    }
                } footer: {
                    if section.isOpenedLater && showsLater {
                        Text("These accounts open after this date. Leave them empty to change nothing; a value "
                            + "moves the account's opening date back to this check-in.")
                    }
                }
            }
            Section {
                CheckInLegend(includesTrades: draft.rows.contains(where: \.isTrades))
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
    }

    /// "OPENED LATER (3) ›", a button that shows or hides the section's accounts.
    private func openedLaterHeader(count: Int) -> some View {
        Button {
            withAnimation { session.showsOpenedLater.toggle() }
        } label: {
            HStack(spacing: Metrics.xs) {
                Text(verbatim: "Opened later (\(count))")
                Spacer(minLength: Metrics.s)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .rotationEffect(.degrees(session.showsOpenedLater ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text(verbatim: "Opened later, \(count) account\(count == 1 ? "" : "s")"))
        .accessibilityHint(Text(verbatim: session.showsOpenedLater ? "Hides them" : "Shows them"))
    }

    /// The prices' status row; `nil` when the check-in needs no prices.
    private var priceStatus: CheckInPriceStatus? {
        let prices = CheckInPriceList.make(draft: draft, fetched: checkIn.priceList, library: library.library,
                                         locale: locale)
        return CheckInPriceStatus.make(prices, isFetching: checkIn.isFetchingPrices, locale: locale)
    }

    /// ▲ ▼ ± · the field's name · Done, above the keypad.
    @ToolbarContentBuilder
    private func keyboardBar(order: CheckInFieldOrder, library: Library, proxy: ScrollViewProxy) -> some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Button {
                if let target = order.previous(before: focus) { move(to: target, proxy: proxy) }
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(order.previous(before: focus) == nil)
            .accessibilityLabel("Previous field")
            Button {
                if let target = order.next(after: focus) { move(to: target, proxy: proxy) }
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(order.next(after: focus) == nil)
            .accessibilityLabel("Next field")
            Button {
                signToggle += 1
            } label: {
                Image(systemName: "plus.forwardslash.minus")
            }
            .accessibilityLabel("Change sign")
            Spacer()
            Text(verbatim: focus.map { $0.name(in: library) } ?? "")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
                .privacySensitiveInFeedback()
            Spacer()
            Button("Done") { focus = nil }
                .fontWeight(.semibold)
        }
    }

    /// Focuses a field someone asked for (the review, "Add a position").
    private func applyFocusRequest(_ request: CheckInField, proxy: ScrollViewProxy, after delay: Duration) {
        session.focusRequest = nil
        if draft[request.account]?.opensLater == true { session.showsOpenedLater = true }
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            move(to: request, proxy: proxy)
        }
    }

    /// Scrolls to a field's row and focuses it. A row far down may not
    /// exist until it's scrolled to, so the focus is set again a moment later.
    private func move(to field: CheckInField, proxy: ScrollViewProxy) {
        withAnimation { proxy.scrollTo(field.account, anchor: .center) }
        focus = field
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            if focus != field { focus = field }
        }
    }
}

// MARK: - Header

/// The date ("30 September 2026 ▾", with the date panel), the line under it
/// and the banners.
private struct CheckInListHeader: View {
    let draft: CheckInDraft
    let review: CheckInReview
    @Bindable var session: CheckInSession

    @Environment(CheckInStore.self) private var checkIn
    @Environment(\.locale) private var locale

    var body: some View {
        let dateText = AmountFormat.longDate(draft.date, locale: locale)
        VStack(alignment: .leading, spacing: Metrics.m) {
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    session.showsDatePicker = true
                } label: {
                    HStack(spacing: 6) {
                        Text(verbatim: dateText)
                            .font(.title2.bold())
                            .foregroundStyle(Palette.ink)
                            .privacySensitiveInFeedback()
                        Image(systemName: "chevron.down")
                            .font(.body.weight(.bold))
                            .foregroundStyle(Palette.accent)
                    }
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text(verbatim: "Check-in date: \(dateText)"))
                .accessibilityHint("Changes the date")
                .popover(isPresented: $session.showsDatePicker) {
                    CheckInDatePanel(date: draft.date, suggested: checkIn.suggestedDate) { date in
                        checkIn.changeDate(to: date)
                    }
                    .presentationDetents([.medium, .large])
                }
                Text(verbatim: CheckInWording.dateLine(previousCheckIn: review.previousCheckIn,
                                                       accounts: CheckInWording.accountCount(draft), locale: locale))
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                    .privacySensitiveInFeedback()
            }
            CheckInBanners(draft: draft, session: session)
        }
    }
}

/// "✓ Prices and FX updated (4) · VWCE, BTC, gold, USD · 09:41 ▸".
private struct CheckInPriceStatusLabel: View {
    let summary: CheckInPriceStatus

    var body: some View {
        HStack(spacing: Metrics.m) {
            CheckInPriceStatusIcon(kind: summary.kind)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: summary.title)
                    .foregroundStyle(Palette.ink)
                if let subtitle = summary.subtitle {
                    Text(verbatim: subtitle)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                        .privacySensitiveInFeedback()
                }
            }
            Spacer(minLength: Metrics.s)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.mutedInk)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the price list")
    }
}

// MARK: - Rows

/// One account: a balance field, or a trades account's holdings and cash
/// from its trades, with the line under it ("was 4.520,75 · new money −310,20") and,
/// where the kind asks for it, "Contributions since June".
private struct CheckInListRow: View {
    let row: CheckInRow
    let review: CheckInRowReview?
    /// The check-in's date.
    let date: CalendarDate
    let previousCheckIn: CalendarDate?
    let session: CheckInSession
    let focus: FocusState<CheckInField?>.Binding
    let focused: CheckInField?
    let signToggle: Int
    /// Moves on from a field (Return on a hardware keyboard).
    let next: (CheckInField) -> Void

    @Environment(CheckInStore.self) private var checkIn
    @Environment(LibraryStore.self) private var library
    @Environment(\.redactionReasons) private var redactionReasons
    @Environment(\.baseCurrency) private var baseCurrency
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            if row.isTrades {
                trades
            } else {
                balance
            }
        }
        .padding(.vertical, Metrics.xs)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if row.canMarkUnchanged && row.state != .unchanged {
                Button {
                    markUnchanged()
                } label: {
                    Label(CheckInWording.markUnchangedSwipeTitle(for: row), systemImage: "checkmark")
                }
                .tint(Palette.accent)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if row.state != .skipped {
                Button {
                    skip()
                } label: {
                    Label("Skip", systemImage: "arrow.uturn.forward")
                }
                .tint(Palette.mutedInk)
            }
        }
        .contextMenu {
            CheckInRowMenu(row: row, rule: rule, date: date, session: session, checkIn: checkIn)
        }
    }

    // MARK: Values

    private var account: Account? { library.account(row.account) }
    private var name: String { account?.name ?? row.account.rawValue }
    private var currency: CurrencyCode { account?.currency ?? library.baseCurrency }
    private var symbol: String { AmountFormat.symbol(for: currency, locale: locale) }
    private var rule: FlowDefault { review?.flowRule ?? .ask }
    private var showsFlowField: Bool {
        CheckInRowDisplay.showsFlowField(row, rule: rule, isEditing: session.editingFlows.contains(row.account))
    }
    private var lastValueNote: String? {
        CheckInWording.lastValueNote(for: row, previousCheckIn: previousCheckIn, locale: locale)
    }
    /// "Saving moves its opening date to 31 Mar 2024.", for an account that opens later.
    private var openingNote: String? {
        CheckInWording.openingNote(for: row, opened: account?.opened, date: date, locale: locale)
    }
    /// The value it was: the previous balance in the account's currency, or
    /// a trades account's previous value in the base currency.
    private var previousAmount: Decimal? {
        row.mode == .balance ? row.previous?.balance : review?.previousValue
    }
    /// The new money the field shows: what was entered, else the automatic amount.
    private var flowValue: Decimal? {
        row.isFlowEdited ? row.enteredFlow : review?.defaultFlow
    }

    // MARK: Balance

    @ViewBuilder
    private var balance: some View {
        let field = CheckInField.balance(row.account)
        HStack(spacing: Metrics.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                    .privacySensitiveInFeedback()
                if let lastValueNote {
                    Text(verbatim: lastValueNote)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                        .privacySensitiveInFeedback()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Metrics.xs) {
                CheckInNumberField(
                    field, focus: focus, isFocused: focused == field, value: row.balance,
                    style: CheckInRowDisplay.balanceStyle(of: row.account, in: library.library), prompt: "0",
                    label: "\(name), value", signToggle: signToggle, onSubmit: { next(field) }
                ) { amount in
                    guard let amount else { return }
                    checkIn.updateRow(row.account) { $0.setBalance(amount) }
                }
                Text(verbatim: symbol)
                    .foregroundStyle(Palette.secondaryInk)
            }
            .frame(width: 136)
            .checkInFieldBox(isFocused: focused == field, height: 44)
            CheckInStateIndicator(row: row)
        }
        caption
        if CheckInRowDisplay.showsMoneyInOut(row) {
            moneyInOutFields
            if CheckInRowDisplay.showsInterest(row) {
                interestField
            }
            movedLine
        }
        if showsFlowField {
            flowField
        }
    }

    /// "In [ 3.400,00 ] Out [ 3.010,30 ]" (docs/ACCOUNTS.md, "Pre-filled
    /// values"): empty, money in is 0; a current account's money out
    /// follows money in and the change until it's typed, and a savings
    /// account's is 0.
    private var moneyInOutFields: some View {
        let inField = CheckInField.moneyIn(row.account)
        let outField = CheckInField.moneyOut(row.account)
        return HStack(spacing: Metrics.s) {
            Text("In")
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
            CheckInNumberField(
                inField, focus: focus, isFocused: focused == inField, value: row.moneyIn,
                prompt: CheckInWording.moneyPrompt, label: inField.name(in: library.library), allowsEmpty: true,
                onSubmit: { next(inField) }
            ) { amount in
                checkIn.updateRow(row.account) { $0.setMoneyIn(amount) }
            }
            .checkInFieldBox(isFocused: focused == inField)
            Text("Out")
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
            CheckInNumberField(
                outField, focus: focus, isFocused: focused == outField,
                value: row.enteredMoneyOut ?? review?.valuation?.moneyOut, prompt: CheckInWording.moneyPrompt,
                label: outField.name(in: library.library), allowsEmpty: true, onSubmit: { next(outField) }
            ) { amount in
                checkIn.updateRow(row.account) { $0.setMoneyOut(amount) }
            }
            .checkInFieldBox(isFocused: focused == outField)
            Color.clear
                .frame(width: 22, height: 1)
        }
    }

    /// "Interest [ 35,05 ]", a savings account's: its new money is the
    /// change less the interest, which counts as markets.
    private var interestField: some View {
        let field = CheckInField.interest(row.account)
        return HStack(spacing: Metrics.s) {
            Text("Interest")
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Metrics.xs) {
                CheckInNumberField(
                    field, focus: focus, isFocused: focused == field, value: row.interest,
                    prompt: CheckInWording.moneyPrompt, label: field.name(in: library.library), allowsEmpty: true,
                    signToggle: signToggle, onSubmit: { next(field) }
                ) { amount in
                    checkIn.updateRow(row.account) { $0.setInterest(amount) }
                }
                Text(verbatim: symbol)
                    .foregroundStyle(Palette.secondaryInk)
            }
            .frame(width: 116)
            .checkInFieldBox(isFocused: focused == field)
            Color.clear
                .frame(width: 22, height: 1)
        }
    }

    /// "Moved +500,00 between your accounts", read-only: what's left once
    /// money in and out (and the interest) are taken out of the change.
    @ViewBuilder
    private var movedLine: some View {
        if let text = CheckInWording.moved(review?.moved, locale: locale) {
            AmountSentenceText(text)
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .monospacedDigit()
                .accessibilityHint(Text(verbatim: CheckInWording.movedExplanation))
        }
    }

    private var cashLine: some View {
        let field = CheckInField.cash(row.account)
        // A trades account's cash is pre-filled from its trades; emptied, the trades say.
        let prompt = row.isTrades && row.derived != nil
            ? CheckInFieldFormat.text(for: row.derived?.cash, style: .amount, locale: locale) : "0"
        return HStack(spacing: Metrics.s) {
            Text("Cash")
                .font(.subheadline.weight(.semibold))
                .frame(width: 60, alignment: .leading)
            HStack(spacing: Metrics.xs) {
                CheckInNumberField(
                    field, focus: focus, isFocused: focused == field, value: row.cash, prompt: prompt,
                    label: field.name(in: library.library), allowsEmpty: true, signToggle: signToggle,
                    onSubmit: { next(field) }
                ) { amount in
                    checkIn.updateRow(row.account) { $0.setCash(amount) }
                }
                Text(verbatim: symbol)
                    .foregroundStyle(Palette.secondaryInk)
            }
            .frame(width: 104)
            .checkInFieldBox(isFocused: focused == field)
            Spacer(minLength: 0)
        }
    }

    // MARK: Trades

    /// A trades account (UI.md, "Accounts that record trades"): nothing to
    /// type, so it's done "from trades" from the start. Its name, what its
    /// trades hold and their value (expanded: the positions, read-only at
    /// the check-in's prices, and a statement's quantities to compare);
    /// *Add Trade…* on the check-in's date for what was bought or sold
    /// since; its cash from the trades, read-only, with *Enter From
    /// Statement* (nothing for an account that holds no cash); its new
    /// money from the trades.
    @ViewBuilder
    private var trades: some View {
        let isExpanded = session.expanded.contains(row.account)
        let summary = CheckInWording.tradesSummary(row, instruments: library.library.instruments, locale: locale)
        let value = review?.value?.knownValue
        HStack(spacing: Metrics.s) {
            Button {
                withAnimation { session.toggleExpanded(row.account) }
            } label: {
                HStack(spacing: Metrics.s) {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.mutedInk)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: name)
                            .fontWeight(.semibold)
                            .foregroundStyle(Palette.ink)
                            .privacySensitiveInFeedback()
                        AmountSentenceText(summary)
                            .font(.footnote)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                    Spacer(minLength: Metrics.s)
                    if let value {
                        AmountText(value, precision: .cents)
                            .foregroundStyle(Palette.ink)
                            .layoutPriority(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            // "Directa, 423 VWCE · from trades", its value, and what tapping does.
            .accessibilityLabel(Text(verbatim: "\(name), \(summary.spoken(hidesAmounts: hidesAmounts))"))
            .accessibilityValue(Text(verbatim: value.map { amount in
                hidesAmounts ? "Amount hidden"
                    : AmountFormat.amount(amount, currency: baseCurrency, precision: .cents, locale: locale)
            } ?? ""))
            .accessibilityHint(Text(verbatim: isExpanded ? "Hides the positions" : "Shows the positions"))
            CheckInStateIndicator(row: row)
        }
        if isExpanded {
            ForEach(review?.positions ?? [], id: \.instrument) { position in
                derivedPositionLine(position)
            }
            statementPositions
        }
        addTradeLine
        tradeCashLines
        tradeMoneyLines
    }

    /// The parts of the new money, for the lines under the row.
    private var tradeFlow: CheckInTradeFlow? {
        CheckInTradeFlow.make(for: row, date: date, valuator: library.valuator)
    }

    /// "deposits +200,60 · cash difference +11,30", when there's something to split.
    private var tradeFlowDetail: AmountSentence? {
        tradeFlow.flatMap { CheckInWording.tradeFlowDetail($0, locale: locale) }
    }

    /// Whether amounts are hidden: VoiceOver doesn't read them.
    private var hidesAmounts: Bool { redactionReasons.hidesAmounts }

    /// "Bought or sold since 30 Sep?  [⊕ Add Trade…]": a new trade, dated
    /// on the check-in's date. Once it's saved, the row follows it. A row
    /// waiting for its trades also offers *No Trades* (docs/ACCOUNTS.md,
    /// "Settled questions" 4). The buttons go under the question when they
    /// don't fit on a line.
    private var addTradeLine: some View {
        textThenButton(addTradePrompt, tradeButtons)
    }

    private var tradeButtons: some View {
        HStack(spacing: Metrics.s) {
            if CheckInRowDisplay.offersNoTrades(row) {
                Button("No Trades") {
                    markUnchanged()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(Text(verbatim: "No trades in \(name) since its last value"))
            }
            addTradeButton
        }
    }

    private var addTradePrompt: some View {
        Text(verbatim: CheckInWording.addTradePrompt(for: row, locale: locale))
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
            .privacySensitiveInFeedback()
            .accessibilityHidden(true)
    }

    private var addTradeButton: some View {
        Button {
            session.addTrade(to: row.account, on: date)
        } label: {
            Label("Add Trade…", systemImage: "plus.circle")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(!library.canEdit)
        .accessibilityLabel(Text(verbatim: CheckInWording.addTradeLabel(account: name, date: date, locale: locale)))
    }

    /// The cash: "Cash 1.234,56 · from trades" with *Enter From Statement*;
    /// or a field for a cash from a statement, with what the trades give and
    /// *Use Trades' Cash*. Nothing for an account that holds no cash.
    @ViewBuilder
    private var tradeCashLines: some View {
        let isEditing = session.editingCash.contains(row.account)
        if CheckInRowDisplay.showsCashField(row, isEditing: isEditing) {
            cashLine
            if let note = CheckInWording.statementCashNote(row, locale: locale) {
                textThenButton(figures(note), useTradesCashButton, alignment: .firstTextBaseline)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
        } else if CheckInRowDisplay.showsTradeCash(row, isEditing: isEditing),
                  let text = CheckInWording.tradeCash(row, locale: locale) {
            textThenButton(figures(text), enterStatementCashButton, alignment: .firstTextBaseline)
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
        }
    }

    /// A line with amounts in it, which hide with the eye.
    private func figures(_ text: AmountSentence) -> some View {
        AmountSentenceText(text)
            .monospacedDigit()
    }

    /// `text`, then `button` after it on the same line when both fit, else
    /// under it.
    private func textThenButton(_ text: some View, _ button: some View,
                                alignment: VerticalAlignment = .center) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: alignment, spacing: Metrics.s) {
                text
                Spacer(minLength: Metrics.s)
                button
            }
            VStack(alignment: .leading, spacing: Metrics.xs) {
                text
                button
            }
        }
    }

    private var enterStatementCashButton: some View {
        Button("Enter From Statement") {
            session.enterStatementCash(row.account)
        }
        .buttonStyle(.borderless)
        .disabled(!library.canEdit)
        .accessibilityLabel(Text(verbatim: "Enter \(name)'s cash from a statement"))
        .accessibilityHint("Its trades give the cash. A different amount counts as money added or taken out.")
    }

    private var useTradesCashButton: some View {
        Button("Use Trades' Cash") {
            session.useTradesCash(row.account, checkIn: checkIn)
        }
        .buttonStyle(.borderless)
        .accessibilityHint("Drops the cash from the statement")
    }

    /// The new money: from the trades, read-only ("New money +1.200,00 ·
    /// paid from outside"); with a cash from a statement, "was 57.410,35 ·
    /// new money +1.458,10" (editable) and its split, as for other
    /// accounts. A skipped or not reviewed row says so instead.
    @ViewBuilder
    private var tradeMoneyLines: some View {
        if row.state == .updated && CheckInRowDisplay.canEditTradeFlow(row) {
            caption
            if let detail = tradeFlowDetail {
                AmountSentenceText(detail)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .accessibilityHint(Text(verbatim: CheckInWording.tradeFlowExplanation))
            }
            if showsFlowField {
                flowField
            }
        } else {
            if let flow = tradeFlow, let text = CheckInWording.tradeNewMoney(flow, total: review?.flow, locale: locale) {
                AmountSentenceText(text)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .monospacedDigit()
                    .accessibilityHint(Text(verbatim: CheckInWording.tradeFlowExplanation))
            }
            if row.state == .notReviewed || row.state == .skipped {
                caption
            } else {
                openingNoteLabel
            }
        }
    }

    /// A position the trades hold on the date: "VWCE 422,5 sh × 138,42 € 58.482", read-only.
    private func derivedPositionLine(_ position: CheckInPositionReview) -> some View {
        let instrument = library.library.instruments[position.instrument]
        let change = position.quantity - position.previousQuantity
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                Text(verbatim: CheckInWording.instrumentLabel(position.instrument, instrument: instrument))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .frame(width: 60, alignment: .leading)
                    .privacySensitiveInFeedback()
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: CheckInWording.quantity(position.quantity, instrument: instrument, locale: locale))
                        .font(.subheadline)
                        .monospacedDigit()
                        .privacySensitiveAmount()
                    Text(verbatim: CheckInWording.priceText(unit: "", price: position.price, locale: locale))
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                        .privacySensitiveInFeedback()
                }
                Spacer(minLength: 0)
                CheckInPlainAmount(position.value)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
            }
            if change != 0 {
                HStack(spacing: Metrics.s) {
                    CheckInQuantityChange(change)
                    Text(verbatim: row.previous.map { "since " + AmountFormat.shortDate($0.date, locale: locale) }
                        ?? "new")
                        .privacySensitiveInFeedback()
                    Text("· from trades")
                }
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .padding(.leading, 68)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Expanded: *Compare With a Statement*, or the statement's quantities
    /// entered to compare with the trades, and *Stop Comparing*.
    @ViewBuilder
    private var statementPositions: some View {
        if row.positions.isEmpty {
            if !(review?.positions ?? []).isEmpty {
                Button {
                    checkIn.updateRow(row.account) { $0.enterStatementQuantities() }
                } label: {
                    Label("Compare With a Statement", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .font(.footnote)
                .disabled(!library.canEdit)
            }
        } else {
            Text("From a statement, to compare")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.secondaryInk)
            ForEach(row.positions) { position in
                statementLine(position)
            }
            Button {
                session.stopComparing(row.account, checkIn: checkIn)
            } label: {
                Label("Stop Comparing", systemImage: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .font(.footnote)
        }
    }

    /// A quantity entered from a broker statement, to compare with the trades.
    private func statementLine(_ position: CheckInPosition) -> some View {
        let instrument = library.library.instruments[position.instrument]
        let field = CheckInField.quantity(row.account, position.instrument)
        return HStack(spacing: Metrics.s) {
            Text(verbatim: CheckInWording.instrumentLabel(position.instrument, instrument: instrument))
                .font(.subheadline)
                .lineLimit(1)
                .frame(width: 60, alignment: .leading)
                .privacySensitiveInFeedback()
            CheckInNumberField(
                field, focus: focus, isFocused: focused == field, value: position.quantity, style: .quantity,
                prompt: "0", label: field.name(in: library.library) + ", statement", onSubmit: { next(field) }
            ) { quantity in
                guard let quantity else { return }
                checkIn.updateRow(row.account) { $0.setQuantity(quantity, of: position.instrument) }
            }
            .frame(width: 72)
            .checkInFieldBox(isFocused: focused == field)
            if position.quantityChange != 0 {
                CheckInQuantityChange(position.quantityChange)
                    .font(.footnote)
                Text("vs trades")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
            Spacer(minLength: 0)
            Button {
                checkIn.updateRow(row.account) { $0.removePosition(position.instrument) }
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(verbatim: "Remove \(position.instrument.rawValue) from the statement"))
        }
    }

    // MARK: New money

    /// "was 4.520,75 · new money −310,20" for an updated row (tap the amount
    /// to edit it), else "Unchanged", "Pre-filled from 31 Aug", ….
    @ViewBuilder
    private var caption: some View {
        if row.state == .updated {
            HStack(spacing: Metrics.xs) {
                if let previousAmount {
                    Text("was")
                    CheckInPlainAmount(previousAmount)
                }
                if !showsFlowField {
                    if previousAmount != nil {
                        Text(verbatim: "·")
                    }
                    Text("new money")
                    if CheckInRowDisplay.canEditFlow(row, rule: rule) {
                        Button {
                            session.editFlow(row.account)
                        } label: {
                            CheckInPlainAmount(review?.flow, signed: true, placeholder: "unknown")
                                .fontWeight(.semibold)
                                .foregroundStyle(Palette.accent)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityHint("Edits the new money")
                    } else {
                        // Worked out from what's typed (docs/ACCOUNTS.md, "New money").
                        CheckInPlainAmount(review?.flow, signed: true, placeholder: "unknown")
                    }
                }
            }
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
        } else if let text = CheckInWording.caption(for: row, locale: locale) {
            Text(verbatim: text)
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .privacySensitiveInFeedback()
        }
        openingNoteLabel
    }

    /// "Saving moves its opening date to 31 Mar 2024.", for an account that opens later.
    @ViewBuilder
    private var openingNoteLabel: some View {
        if let openingNote {
            Label {
                Text(verbatim: openingNote)
                    .fixedSize(horizontal: false, vertical: true)
                    .privacySensitiveInFeedback()
            } icon: {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(Palette.accent)
            }
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
        }
    }

    /// "Contributions since June [ 1.325,00 € ]", or the automatic new money being edited.
    private var flowField: some View {
        let field = CheckInField.flow(row.account)
        let rule = self.rule
        return HStack(spacing: Metrics.s) {
            Text(verbatim: CheckInWording.flowTitle(kind: account?.kind, rule: rule, previous: row.previous,
                                                    locale: locale))
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .privacySensitiveInFeedback()
            HStack(spacing: Metrics.xs) {
                CheckInNumberField(
                    field, focus: focus, isFocused: focused == field, value: flowValue,
                    prompt: rule == .ask ? "unknown" : "0", label: field.name(in: library.library), allowsEmpty: true,
                    signToggle: signToggle, onSubmit: { next(field) }
                ) { amount in
                    checkIn.updateRow(row.account) { CheckInEditing.enterFlow(amount, rule: rule, in: &$0) }
                }
                Text(verbatim: symbol)
                    .foregroundStyle(Palette.secondaryInk)
            }
            .frame(width: 116)
            .checkInFieldBox(isFocused: focused == field)
            Color.clear
                .frame(width: 22, height: 1)
        }
    }

    // MARK: Actions

    private func markUnchanged() {
        session.markUnchanged(row.account, checkIn: checkIn)
    }

    private func skip() {
        checkIn.updateRow(row.account) { $0.skip() }
    }
}

// MARK: - Bottom bar

/// "7 of 9 reviewed ▬▬▬▭ [Mark rest unchanged]", floating over the list on
/// glass; "Review" once everything is reviewed.
private struct CheckInBottomBar: View {
    let draft: CheckInDraft
    let session: CheckInSession

    @Environment(CheckInStore.self) private var checkIn

    var body: some View {
        HStack(spacing: Metrics.m) {
            VStack(alignment: .leading, spacing: Metrics.xs) {
                Text(verbatim: CheckInWording.reviewed(draft))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                CheckInProgressBar(reviewed: draft.reviewedCount, total: draft.progressTotal)
                    .frame(width: 112)
            }
            Spacer(minLength: Metrics.s)
            if draft.isReadyToSave {
                Button("Review") { session.page = .review }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Mark rest unchanged") { checkIn.markRestUnchanged() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, Metrics.s)
        .padding(.vertical, Metrics.s)
        .glassEffect()
        .padding(.horizontal, Metrics.l)
        .padding(.bottom, Metrics.s)
    }
}

#Preview("iPhone list") {
    let model = CheckInPreviewData.model()
    NavigationStack {
        if let draft = model.checkIn.draft {
            CheckInList(draft: draft, session: CheckInSession())
                .navigationTitle("Check-in")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
    .appEnvironment(model)
}

#Preview("iPhone list, trades accounts from trades") {
    let model = CheckInPreviewData.model()
    NavigationStack {
        if let draft = model.checkIn.draft {
            CheckInList(draft: draft, session: CheckInPreviewData.session(expanding: ["directa", "gold-coins"]))
                .navigationTitle("Check-in")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
    .appEnvironment(model)
}

#Preview("iPhone list, trades account compared with a statement") {
    let model = CheckInPreviewData.modelComparingStatement()
    NavigationStack {
        if let draft = model.checkIn.draft {
            CheckInList(draft: draft, session: CheckInPreviewData.session(expanding: ["directa"]))
                .navigationTitle("Check-in")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
    .appEnvironment(model)
}

#Preview("iPhone list, large text") {
    let model = CheckInPreviewData.model()
    NavigationStack {
        if let draft = model.checkIn.draft {
            CheckInList(draft: draft, session: CheckInPreviewData.session(expanding: ["directa"]))
                .navigationTitle("Check-in")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
    .dynamicTypeSize(.accessibility2)
    .appEnvironment(model)
}
#endif
