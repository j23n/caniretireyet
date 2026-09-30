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
        let order = CheckInFieldOrder.list(rows: sections.flatMap(\.rows), library: snapshot,
                                           expanded: session.expanded, editingFlows: session.editingFlows)
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
        List {
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
                    ForEach(section.rows) { row in
                        CheckInListRow(
                            row: row, review: review.row(for: row.account), previousCheckIn: review.previousCheckIn,
                            session: session, focus: $focus, focused: focus, signToggle: signToggle
                        ) { field in
                            if let target = order.next(after: field) { move(to: target, proxy: proxy) }
                        }
                        .id(row.account)
                    }
                } header: {
                    Text(verbatim: section.group.description)
                }
            }
            Section {
                CheckInLegend()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
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
                                                       accounts: draft.rows.count, locale: locale))
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
    let previousCheckIn: CalendarDate?
    let session: CheckInSession
    let focus: FocusState<CheckInField?>.Binding
    let focused: CheckInField?
    let signToggle: Int
    /// Moves on from a field (Return on a hardware keyboard).
    let next: (CheckInField) -> Void

    @Environment(CheckInStore.self) private var checkIn
    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            if row.mode == .holdings {
                holdings
            } else {
                balance
            }
        }
        .padding(.vertical, Metrics.xs)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if CheckInRowDisplay.canMarkUnchanged(row) && row.state != .unchanged {
                Button {
                    markUnchanged()
                } label: {
                    Label("Unchanged", systemImage: "checkmark")
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
            rowMenu
        }
    }

    // MARK: Values

    private var account: Account? { library.account(row.account) }
    private var name: String { account?.name ?? row.account.rawValue }
    private var currency: CurrencyCode { account?.currency ?? library.baseCurrency }
    private var symbol: String { AmountFormat.symbol(for: currency, locale: locale) }
    private var rule: FlowDefault { CheckInRowDisplay.flowRule(of: row.account, in: library.library) }
    private var showsFlowField: Bool {
        CheckInRowDisplay.showsFlowField(row, rule: rule, isEditing: session.editingFlows.contains(row.account))
    }
    private var lastValueNote: String? {
        CheckInWording.lastValueNote(for: row, previousCheckIn: previousCheckIn, locale: locale)
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
    private var otherInstruments: [Instrument] {
        library.library.instruments.values
            .filter { row.position(for: $0.id) == nil }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
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
                    field, focus: focus, isFocused: focused == field, value: row.balance, prompt: "0",
                    label: "\(name), value", signToggle: signToggle, onSubmit: { next(field) }
                ) { amount in
                    guard let amount else { return }
                    let isLiability = account?.kind.isLiability ?? false
                    checkIn.updateRow(row.account) { $0.setBalance(CheckInEditing.balance(amount, isLiability: isLiability)) }
                }
                Text(verbatim: symbol)
                    .foregroundStyle(Palette.secondaryInk)
            }
            .frame(width: 136)
            .checkInFieldBox(isFocused: focused == field, height: 44)
            CheckInStateIndicator(state: row.state)
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
            CheckInStateIndicator(state: row.state)
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
            Text(verbatim: priceText(unit: CheckInWording.unit(of: instrument), price: valued?.price))
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
        return HStack(spacing: Metrics.s) {
            Text("Cash")
                .font(.subheadline.weight(.semibold))
                .frame(width: 60, alignment: .leading)
            HStack(spacing: Metrics.xs) {
                CheckInNumberField(
                    field, focus: focus, isFocused: focused == field, value: row.cash, prompt: "0",
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

    @ViewBuilder
    private var rowMenu: some View {
        if CheckInRowDisplay.canMarkUnchanged(row) {
            Button {
                markUnchanged()
            } label: {
                Label("Mark Unchanged", systemImage: "checkmark")
            }
        }
        Button {
            skip()
        } label: {
            Label("Skip This Time", systemImage: "arrow.uturn.forward")
        }
        if row.isFlowEdited {
            Button {
                checkIn.updateRow(row.account) { $0.resetFlow() }
                session.editingFlows.remove(row.account)
            } label: {
                Label("Use Automatic New Money", systemImage: "arrow.counterclockwise")
            }
        } else if rule != .ask && row.state == .updated && !showsFlowField {
            Button {
                session.editFlow(row.account)
            } label: {
                Label("Edit New Money", systemImage: "pencil")
            }
        }
        if row.mode == .holdings {
            let others = otherInstruments
            if !others.isEmpty {
                Menu {
                    ForEach(others) { instrument in
                        Button(instrument.name) { addPosition(instrument.id) }
                    }
                } label: {
                    Label("Add a Position", systemImage: "plus")
                }
            }
        }
    }

    private func markUnchanged() {
        checkIn.updateRow(row.account) { $0.markUnchanged() }
        session.editingFlows.remove(row.account)
    }

    private func skip() {
        checkIn.updateRow(row.account) { $0.skip() }
    }

    private func addPosition(_ instrument: InstrumentID) {
        checkIn.updateRow(row.account) { $0.setQuantity(0, of: instrument) }
        session.expanded.insert(row.account)
        session.focusRequest = .quantity(row.account, instrument)
    }

    // MARK: Words

    /// "sh × 138,42", or "BTC × 111.400 USD" when the price is in another currency.
    private func priceText(unit: String, price: PriceRecord?) -> String {
        guard let price else { return unit.isEmpty ? "no price" : "\(unit) · no price" }
        var text = AmountFormat.number(price.price, maxDigits: 4, locale: locale)
        if price.currency != currency { text += " " + price.currency.rawValue }
        return unit.isEmpty ? "× " + text : "\(unit) × \(text)"
    }

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
                CheckInProgressBar(reviewed: draft.reviewedCount, total: draft.rows.count)
                    .frame(width: 112)
            }
            Spacer(minLength: Metrics.s)
            if draft.isReadyToSave {
                Button("Review") { session.page = .review }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Mark rest unchanged") { session.markRestUnchanged(checkIn: checkIn) }
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
    .previewEnvironment(model: model)
}
#endif
