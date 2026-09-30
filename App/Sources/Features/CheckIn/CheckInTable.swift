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
        let order = CheckInFieldOrder.nowColumn(rows: sections.flatMap(\.rows))
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
    }

    private func table(review: CheckInReview, sections: [CheckInSection], order: CheckInFieldOrder) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CheckInBanners(draft: draft, session: session)
                .padding(.horizontal, CheckInColumns.inset)
                .padding(.vertical, Metrics.m)
            CheckInTableHeader(previousCheckIn: review.previousCheckIn)
            Divider()
            ForEach(sections) { section in
                CheckInTableGroupHeader(group: section.group)
                ForEach(section.rows) { row in
                    CheckInTableRow(
                        row: row, review: review.row(for: row.account), previousCheckIn: review.previousCheckIn,
                        session: session, focus: $focus, focused: focus
                    ) { field in
                        if let target = order.returnTarget(after: field) { focus = target }
                    }
                    .id(row.account)
                }
            }
            CheckInLegend()
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

/// "CASH", "INVESTMENTS", … on a band across the table.
private struct CheckInTableGroupHeader: View {
    let group: AccountGroup

    var body: some View {
        Text(verbatim: group.description.uppercased())
            .tracking(0.5)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Palette.secondaryInk)
            .padding(.horizontal, CheckInColumns.inset + Metrics.s)
            .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
            .background(Palette.page)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Rows

/// One account's line, and for holdings a line per position and one for
/// cash. Balances are in the account's currency; holdings' totals in the
/// base currency.
private struct CheckInTableRow: View {
    let row: CheckInRow
    let review: CheckInRowReview?
    let previousCheckIn: CalendarDate?
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
            if row.mode == .holdings {
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
    /// the currency when it isn't the base one.
    private var detail: String? {
        var parts: [String] = []
        if row.mode == .holdings {
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

    // MARK: Account line

    private var accountLine: some View {
        CheckInTableLine {
            Button {
                markUnchanged()
            } label: {
                CheckInStateIndicator(state: row.state, size: 20)
            }
            .buttonStyle(.plain)
            .disabled(!CheckInRowDisplay.canMarkUnchanged(row) || row.state == .unchanged)
            .help(CheckInRowDisplay.canMarkUnchanged(row) ? "Mark unchanged" : CheckInWording.stateName(row.state))
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
                field, focus: focus, isFocused: focused == field, value: row.balance, prompt: "0,00",
                label: "\(name), now", onSubmit: { onReturn(field) }
            ) { amount in
                guard let amount else { return }
                let isLiability = account?.kind.isLiability ?? false
                checkIn.updateRow(row.account) { $0.setBalance(CheckInEditing.balance(amount, isLiability: isLiability)) }
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

    private var cashLine: some View {
        let field = CheckInField.cash(row.account)
        let change: Decimal? = row.cash == nil && row.previous?.cash == nil
            ? nil : (row.cash ?? 0) - (row.previous?.cash ?? 0)
        return CheckInTableLine {
            Color.clear
        } account: {
            HStack(spacing: 0) {
                Text("Cash")
                    .fontWeight(.medium)
                Text(verbatim: " · " + currency.rawValue)
                    .foregroundStyle(Palette.secondaryInk)
            }
            .padding(.leading, Metrics.l)
        } last: {
            CheckInPlainAmount(row.previous?.cash)
                .foregroundStyle(Palette.secondaryInk)
        } now: {
            CheckInNumberField(
                field, focus: focus, isFocused: focused == field, value: row.cash, prompt: "0,00",
                label: field.name(in: library.library), allowsEmpty: true, onSubmit: { onReturn(field) }
            ) { amount in
                checkIn.updateRow(row.account) { $0.setCash(amount) }
            }
            .checkInFieldBox(isFocused: focused == field, height: 24)
        } change: {
            CheckInPlainDelta(change)
        } newMoney: {
            Text(verbatim: "—")
                .foregroundStyle(Palette.mutedInk)
        } note: {
            Color.clear
        }
        .font(.callout)
        .frame(height: 30)
    }

    // MARK: Actions

    @ViewBuilder
    private var rowMenu: some View {
        if CheckInRowDisplay.canMarkUnchanged(row) {
            Button("Mark Unchanged") { markUnchanged() }
        }
        Button("Skip This Time") {
            checkIn.updateRow(row.account) { $0.skip() }
        }
        if row.isFlowEdited {
            Button("Use Automatic New Money") {
                checkIn.updateRow(row.account) { $0.resetFlow() }
            }
        }
        if row.mode == .holdings {
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
        checkIn.updateRow(row.account) { $0.markUnchanged() }
    }

    /// "× 138,42", or "× 111.400 USD" in another currency than the account's.
    private func priceText(_ price: PriceRecord?) -> String {
        guard let price else { return "no price" }
        var text = "× " + AmountFormat.number(price.price, maxDigits: 4, locale: locale)
        if price.currency != currency { text += " " + price.currency.rawValue }
        return text
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
                CheckInProgressBar(reviewed: draft.reviewedCount, total: draft.rows.count)
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
    .previewEnvironment(model: model)
}
#endif
