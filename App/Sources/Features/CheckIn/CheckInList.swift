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
/// An account that records trades needs nothing typed: it's done "from
/// trades" from the start. It shows what its trades hold and their value
/// at the check-in's prices, *Add Trade…* on the check-in's date, its cash
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
        let order = CheckInFieldOrder.list(rows: visible, review: review, expanded: session.expanded,
                                           editingFlows: session.editingFlows, editingCash: session.editingCash)
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
    @Environment(LibraryStore.self) private var library
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
                        Image(systemName: "chevron.down")
                            .font(.body.weight(.bold))
                            .foregroundStyle(Palette.accent)
                    }
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text(verbatim: "Check-in date: \(dateText)"))
                .accessibilityHint("Changes the date")
                .popover(isPresented: $session.showsDatePicker) {
                    CheckInDatePanel(date: draft.date, suggested: suggested) { date in
                        checkIn.changeDate(to: date)
                    }
                    .presentationDetents([.medium, .large])
                }
                Text(verbatim: CheckInWording.dateLine(previousCheckIn: review.previousCheckIn,
                                                       accounts: CheckInWording.accountCount(draft), locale: locale))
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
            }
            CheckInBanners(draft: draft, session: session)
        }
    }

    private var suggested: CalendarDate {
        CheckInDraft.suggestedDate(today: .today(), lastCheckIn: library.latestCheckIn)
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

/// One account: a balance field, or its positions and cash (expanded on
/// tap), with the line under it ("was 4.520,75 · new money −310,20") and,
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
    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.baseCurrency) private var baseCurrency
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            if row.isTrades {
                trades
            } else if row.mode == .holdings {
                holdings
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
            CheckInRowMenu(row: row, rule: rule, date: date, session: session, checkIn: checkIn,
                           instruments: library.library.instruments)
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
    /// the previous holdings' value in the base currency.
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
                if let lastValueNote {
                    Text(verbatim: lastValueNote)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
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
        if showsFlowField {
            flowField
        }
    }

    // MARK: Holdings

    @ViewBuilder
    private var holdings: some View {
        let isExpanded = session.expanded.contains(row.account)
        let toggleLabel = isExpanded ? "\(name), hide positions" : "\(name), show positions"
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
                        if let lastValueNote {
                            Text(verbatim: lastValueNote)
                                .font(.footnote)
                                .foregroundStyle(Palette.secondaryInk)
                        }
                    }
                    Spacer(minLength: Metrics.s)
                    if let value = review?.value?.knownValue {
                        AmountText(value, precision: .cents)
                            .foregroundStyle(Palette.ink)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(verbatim: toggleLabel))
            CheckInStateIndicator(row: row)
        }
        if isExpanded {
            ForEach(row.positions) { position in
                positionLines(position)
            }
            cashLine
            caption
            if showsFlowField {
                flowField
            }
        } else {
            Text(verbatim: CheckInWording.holdingsSummary(row, instruments: library.library.instruments, locale: locale))
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
        }
    }

    @ViewBuilder
    private func positionLines(_ position: CheckInPosition) -> some View {
        let instrument = library.library.instruments[position.instrument]
        let field = CheckInField.quantity(row.account, position.instrument)
        let valued = review?.positions.first(where: { $0.instrument == position.instrument })
        HStack(spacing: Metrics.s) {
            Text(verbatim: CheckInWording.instrumentLabel(position.instrument, instrument: instrument))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(width: 60, alignment: .leading)
            CheckInNumberField(
                field, focus: focus, isFocused: focused == field, value: position.quantity, style: .quantity,
                prompt: "0", label: field.name(in: library.library), onSubmit: { next(field) }
            ) { quantity in
                guard let quantity else { return }
                checkIn.updateRow(row.account) { $0.setQuantity(quantity, of: position.instrument) }
            }
            .frame(width: 72)
            .checkInFieldBox(isFocused: focused == field)
            Text(verbatim: CheckInWording.priceText(unit: CheckInWording.unit(of: instrument), price: valued?.price,
                                                    locale: locale))
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
            Spacer(minLength: 0)
            CheckInPlainAmount(valued?.value)
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
        }
        if position.quantityChange != 0 {
            HStack(spacing: Metrics.s) {
                CheckInQuantityChange(position.quantityChange)
                Text(verbatim: sinceText(position))
                if position.isIncrease {
                    Text("· paid")
                    Spacer(minLength: Metrics.xs)
                    paidField(position, estimate: valued?.estimatedPaid)
                }
            }
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
            .padding(.leading, 68)
        }
    }

    private func paidField(_ position: CheckInPosition, estimate: Decimal?) -> some View {
        let field = CheckInField.paid(row.account, position.instrument)
        return HStack(spacing: Metrics.xs) {
            CheckInNumberField(
                field, focus: focus, isFocused: focused == field, value: position.paid,
                prompt: CheckInFieldFormat.text(for: estimate, style: .amount, locale: locale),
                label: field.name(in: library.library), allowsEmpty: true, onSubmit: { next(field) }
            ) { amount in
                checkIn.updateRow(row.account) { $0.setPaid(amount, for: position.instrument) }
            }
            Text(verbatim: symbol)
                .foregroundStyle(Palette.secondaryInk)
        }
        .frame(width: 104)
        .checkInFieldBox(isFocused: focused == field)
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
                        Text(verbatim: summary)
                            .font(.footnote)
                            .foregroundStyle(Palette.secondaryInk)
                            .privacySensitive()
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
            .accessibilityLabel(Text(verbatim: hidesAmounts ? name : "\(name), \(summary)"))
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
    private var tradeFlowDetail: String? {
        tradeFlow.flatMap { CheckInWording.tradeFlowDetail($0, hidesAmounts: hidesAmounts, locale: locale) }
    }

    /// "Bought or sold since 30 Sep?  [⊕ Add Trade…]": a new trade, dated
    /// on the check-in's date. Once it's saved, the row follows it. The
    /// button goes under the question when both don't fit on a line.
    private var addTradeLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Metrics.s) {
                addTradePrompt
                Spacer(minLength: Metrics.s)
                addTradeButton
            }
            VStack(alignment: .leading, spacing: Metrics.xs) {
                addTradePrompt
                addTradeButton
            }
        }
    }

    private var addTradePrompt: some View {
        Text(verbatim: CheckInWording.addTradePrompt(for: row, locale: locale))
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
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
            if let note = CheckInWording.statementCashNote(row, hidesAmounts: hidesAmounts, locale: locale) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                        statementCashNote(note)
                        Spacer(minLength: Metrics.s)
                        useTradesCashButton
                    }
                    VStack(alignment: .leading, spacing: Metrics.xs) {
                        statementCashNote(note)
                        useTradesCashButton
                    }
                }
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
            }
        } else if CheckInRowDisplay.showsTradeCash(row, isEditing: isEditing),
                  let text = CheckInWording.tradeCash(row, hidesAmounts: hidesAmounts, locale: locale) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                    tradeCashText(text)
                    Spacer(minLength: Metrics.s)
                    enterStatementCashButton
                }
                VStack(alignment: .leading, spacing: Metrics.xs) {
                    tradeCashText(text)
                    enterStatementCashButton
                }
            }
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
        }
    }

    private func tradeCashText(_ text: String) -> some View {
        Text(verbatim: text)
            .monospacedDigit()
            .privacySensitive()
    }

    private func statementCashNote(_ text: String) -> some View {
        Text(verbatim: text)
            .monospacedDigit()
            .privacySensitive()
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
                Text(verbatim: detail)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .privacySensitive()
                    .accessibilityHint(Text(verbatim: CheckInWording.tradeFlowExplanation))
            }
            if showsFlowField {
                flowField
            }
        } else {
            if let flow = tradeFlow,
               let text = CheckInWording.tradeNewMoney(flow, total: review?.flow, hidesAmounts: hidesAmounts,
                                                       locale: locale) {
                Text(verbatim: text)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .monospacedDigit()
                    .privacySensitive()
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
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: CheckInWording.quantity(position.quantity, instrument: instrument, locale: locale))
                        .font(.subheadline)
                        .monospacedDigit()
                        .privacySensitive()
                    Text(verbatim: CheckInWording.priceText(unit: "", price: position.price, locale: locale))
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
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
                    Button {
                        session.editFlow(row.account)
                    } label: {
                        CheckInPlainAmount(review?.flow, signed: true, placeholder: "unknown")
                            .fontWeight(.semibold)
                            .foregroundStyle(Palette.accent)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityHint("Edits the new money")
                }
            }
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
        } else if let text = CheckInWording.caption(for: row, locale: locale) {
            Text(verbatim: text)
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
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

    // MARK: Words

    /// "since 31 Aug", or "new" for a position that wasn't held.
    private func sinceText(_ position: CheckInPosition) -> String {
        guard position.previousQuantity != 0, let date = row.previous?.date else { return "new" }
        return "since " + AmountFormat.shortDate(date, locale: locale)
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
