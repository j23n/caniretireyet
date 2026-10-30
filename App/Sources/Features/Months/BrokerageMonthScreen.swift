import Model
import SwiftUI
import Tracker

/// A brokerage month (UI.md, "A brokerage month"): a trades account from
/// the check-in before to this one. What it opened and closed at, what you
/// put in and what markets did; money your current account's statement
/// moved to it without a deposit here, to add as one; its trades, from the
/// cash it opened with; whether they lead to the cash the broker states;
/// and what it holds at the month's end. *Import CSV…* opens the import
/// with the broker's file, whose types step asks once what each of the
/// broker's words is; *Add Trade* types one in.
///
/// On iPhone it's shorter: a deposit to add, the broker's cash, the trades
/// and one row for the holdings and value that opens the account. *Add
/// Trade* is the button at the bottom and *Import CSV…* is in the ••• menu.
struct BrokerageMonthScreen: View {
    let route: BrokerageRoute

    @Environment(LibraryStore.self) private var library
    @Environment(CheckInStore.self) private var checkIn
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.pageLayout) private var layout
    @Environment(\.locale) private var locale
    @State private var addsTrade = false
    @State private var showsAccount = false
    @State private var deleting: TradeKey?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let month, let account {
                content(month, account: account)
            } else {
                ContentUnavailableView("No such month", systemImage: "calendar")
            }
        }
        .background(Palette.page)
        .personalNavigationTitle(title, hidden: "Month")
        .toolbar { toolbar }
        .sheet(isPresented: $addsTrade) {
            AddTradeSheet(route: route)
        }
        .navigationDestination(isPresented: $showsAccount) {
            AccountDetailScreen(accountID: route.account)
        }
        .confirmationDialog("Delete this trade?", isPresented: confirmsDeletion, titleVisibility: .visible,
                            presenting: deleting) { key in
            Button("Delete Trade", role: .destructive) { delete(key) }
        } message: { key in
            Text(TradeEditNotes.removal(of: key, in: library.library, locale: locale))
        }
    }

    private var account: Account? { library.library.accounts[route.account] }

    /// The month, from the check-in before this one.
    private var month: BrokerageMonth? {
        checkIn.valuator(on: route.through).brokerageMonth(of: route.account, after: route.from,
                                                           through: route.through, in: library.library)
    }

    private var title: String {
        "\(account?.name ?? route.account.rawValue) · \(MonthText.title(route.through, locale: locale))"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if layout.isWide {
            ToolbarItemGroup(placement: .primaryAction) {
                importButton
                Button {
                    addsTrade = true
                } label: {
                    Label("Add Trade", systemImage: "plus")
                }
                .disabled(!library.canEdit)
            }
        } else {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    importButton
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
    }

    private var importButton: some View {
        Button {
            navigation.startImport()
        } label: {
            Label("Import CSV…", systemImage: AppSymbol.importData)
        }
        .disabled(!library.canEdit)
    }

    @ViewBuilder
    private func content(_ month: BrokerageMonth, account: Account) -> some View {
        if layout.isWide {
            wideContent(month, account: account)
        } else {
            compactContent(month, account: account)
        }
    }

    /// iPhone: a deposit to add, the broker's cash, the trades and the
    /// holdings' row, with *Add Trade* at the bottom.
    private func compactContent(_ month: BrokerageMonth, account: Account) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.l) {
                ForEach(month.depositsToAdd, id: \.key) { line in
                    BrokerageDepositCard(line: line, account: account)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(Palette.critical)
                }
                BrokerageCashCard(month: month, account: account)
                VStack(alignment: .leading, spacing: Metrics.s) {
                    Text("Trades")
                        .font(.headline)
                    if month.trades.isEmpty {
                        Text("No trades this month yet. Import the broker's CSV, or add them by hand.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondaryInk)
                    } else {
                        CardRows {
                            tradeRows(month, account: account)
                        }
                        .padding(.horizontal, Metrics.m)
                        .cardSurface()
                    }
                }
                holdingsRow(month, account: account)
            }
            .padding(layout.gutter)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                addsTrade = true
            } label: {
                Text("Add Trade")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!library.canEdit)
            .padding(.horizontal, layout.gutter)
            .padding(.vertical, Metrics.s)
            .background(.bar)
        }
    }

    /// "Holdings and value · 62.255 € ›", opening the account.
    private func holdingsRow(_ month: BrokerageMonth, account: Account) -> some View {
        let value = checkIn.valuator(on: month.through).value(of: account.id, on: month.through, in: .account)
        return Button {
            showsAccount = true
        } label: {
            HStack(spacing: Metrics.s) {
                Text("Holdings and value")
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: Metrics.s)
                if let total = value?.value {
                    AmountText(total, currency: account.currency)
                        .foregroundStyle(Palette.secondaryInk)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.mutedInk)
                    .accessibilityHidden(true)
            }
            .padding(Metrics.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func tradeRows(_ month: BrokerageMonth, account: Account) -> some View {
        ForEach(month.trades, id: \.trade.key) { entry in
            TradeListRowView(item: TradeListItem(entry, in: library.library, hasIssue: false, locale: locale),
                             currency: account.currency)
                .padding(.vertical, Metrics.s)
                .contextMenu {
                    Button("Delete Trade", role: .destructive) { deleting = entry.trade.key }
                        .disabled(!library.canEdit)
                }
        }
    }

    private func wideContent(_ month: BrokerageMonth, account: Account) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.xl) {
                if let from = month.from {
                    BrokerageSummaryCard(account: account, from: from, through: month.through)
                }
                ForEach(month.depositsToAdd, id: \.key) { line in
                    BrokerageDepositCard(line: line, account: account)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(Palette.critical)
                }
                tradesCard(month, account: account)
                BrokerageCashCard(month: month, account: account)
                BrokerageHoldingsCard(account: account, through: month.through)
            }
            .padding(layout.gutter)
            .frame(maxWidth: Metrics.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func tradesCard(_ month: BrokerageMonth, account: Account) -> some View {
        Card("Trades") {
            CardRows {
                HStack {
                    Text("Opening cash")
                        .foregroundStyle(Palette.secondaryInk)
                    Spacer(minLength: Metrics.s)
                    AmountText(month.openingCash, currency: account.currency, precision: .cents)
                }
                .padding(.vertical, Metrics.s)
                tradeRows(month, account: account)
            }
            if month.trades.isEmpty {
                Text("No trades this month yet. Import the broker's CSV, or add them by hand.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }

    private var confirmsDeletion: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    private func delete(_ key: TradeKey) {
        Task {
            do {
                try await library.removeTrade(key)
            } catch {
                errorMessage = LibraryStore.describe(error)
            }
        }
    }
}

/// What the account opened and closed the month at, what you put in, and
/// what markets did, in the account's currency.
private struct BrokerageSummaryCard: View {
    let account: Account
    let from: CalendarDate
    let through: CalendarDate

    @Environment(CheckInStore.self) private var checkIn

    var body: some View {
        let valuator = checkIn.valuator(on: through)
        if let change = valuator.change(of: account.id, from: from, to: through, in: .account)?.change {
            Card {
                VStack(alignment: .leading, spacing: Metrics.s) {
                    row("Opened at", change.start)
                    row("You put in", change.saved, signed: true)
                    row("Markets", change.market + change.other + change.lost, signed: true)
                    Divider()
                    row("Closed at", change.end, bold: true)
                }
            }
        }
    }

    private func row(_ title: String, _ amount: Decimal, signed: Bool = false, bold: Bool = false) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(bold ? Palette.ink : Palette.secondaryInk)
            Spacer(minLength: Metrics.s)
            AmountText(amount, currency: account.currency, precision: .cents, signed: signed)
        }
        .font(bold ? .body.weight(.semibold) : .body)
    }
}

/// Money a current account's statement moved to the account, with no
/// deposit of it here: *Add as Deposit* records it, so both accounts show
/// the same move.
private struct BrokerageDepositCard: View {
    let line: BankLine
    let account: Account

    @Environment(LibraryStore.self) private var library
    @Environment(\.pageLayout) private var layout
    @Environment(\.locale) private var locale
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            AmountSentenceText(sentence)
                .font(.body.weight(.semibold))
            if layout.isWide {
                Text(line.amount < 0 ? "Add it here as a deposit, so both accounts show the same move."
                    : "Add it here as a withdrawal, so both accounts show the same move.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Palette.critical)
            }
            Button(line.amount < 0 ? "Add as Deposit" : "Add as Withdrawal") { add() }
                .buttonStyle(.borderedProminent)
                .disabled(!library.canEdit)
        }
        .padding(Metrics.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: Metrics.cardRadius))
    }

    private var sentence: AmountSentence {
        let from = library.library.accounts[line.account]?.name ?? line.account.rawValue
        let amount = AmountFormat.amount(abs(line.amount), currency: account.currency, precision: .cents,
                                         locale: locale)
        let day = AmountFormat.mediumDate(line.date, locale: locale)
        return line.amount < 0 ? "\(from) moved \(amount: amount) to \(account.name) on \(day)"
            : "\(from) took \(amount: amount) from \(account.name) on \(day)"
    }

    private func add() {
        let line = self.line
        do {
            try library.update { $0.addDeposit(for: line) }
        } catch {
            errorMessage = LibraryStore.describe(error)
        }
    }
}

/// *Does the cash add up?*: the opening cash and the trades lead to a cash;
/// the cash the broker states on the check-in's date is typed beside it.
/// On iPhone only the broker's cash, with whether it adds up under it.
private struct BrokerageCashCard: View {
    let month: BrokerageMonth
    let account: Account

    @Environment(LibraryStore.self) private var library
    @Environment(\.pageLayout) private var layout
    @Environment(\.locale) private var locale
    @State private var statedText = ""
    @State private var errorMessage: String?
    @FocusState private var isEditing: Bool

    var body: some View {
        Group {
            if layout.isWide {
                card
            } else {
                compact
            }
        }
        .onAppear { statedText = month.statedCash.map { AmountInput.text(for: $0, locale: locale) } ?? "" }
        .onChange(of: month.statedCash) { _, stated in
            if !isEditing { statedText = stated.map { AmountInput.text(for: $0, locale: locale) } ?? "" }
        }
        .onChange(of: isEditing) { _, editing in
            if !editing { save() }
        }
    }

    /// "Directa says on 31 Oct", whether it adds up under it, and the
    /// broker's cash beside them.
    @ViewBuilder
    private var compact: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            if MonthText.isStillToCome(month.through) {
                Text("The broker's cash goes in at the check-in, on "
                    + "\(AmountFormat.mediumDate(month.through, locale: locale)).")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
            } else {
                HStack(spacing: Metrics.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(account.name) says on \(AmountFormat.shortDate(month.through, locale: locale))")
                            .privacySensitiveInFeedback()
                        status
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer(minLength: Metrics.s)
                    OutlinedAmountField(title: "Cash", text: $statedText, currency: account.currency,
                                        isFocused: $isEditing)
                        .onSubmit { save() }
                }
                .disabled(!library.canEdit)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Palette.critical)
            }
        }
        .padding(Metrics.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var card: some View {
        Card("Does the cash add up?") {
            VStack(alignment: .leading, spacing: Metrics.s) {
                row("Opening cash", month.openingCash)
                row("+ / − Trades", month.tradesCash, signed: true)
                row("= Cash from trades", month.cashFromTrades, bold: true)
                if MonthText.isStillToCome(month.through) {
                    Text("The broker's cash goes in at the check-in, on "
                        + "\(AmountFormat.mediumDate(month.through, locale: locale)).")
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                } else {
                    HStack {
                        Text("\(account.name) says on \(AmountFormat.shortDate(month.through, locale: locale))")
                            .foregroundStyle(Palette.secondaryInk)
                            .privacySensitiveInFeedback()
                        Spacer(minLength: Metrics.s)
                        OutlinedAmountField(title: "Cash", text: $statedText, currency: account.currency,
                                            isFocused: $isEditing)
                            .onSubmit { save() }
                    }
                    .disabled(!library.canEdit)
                }
                status
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Palette.critical)
                }
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if let difference = month.difference {
            if difference == 0 {
                Label(layout.isWide ? "Adds up" : "Cash adds up", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Palette.good)
            } else {
                let off = AmountFormat.amount(abs(difference), currency: account.currency, precision: .cents,
                                              locale: locale)
                Label {
                    AmountSentenceText("Off by \(amount: off): a trade is missing or wrong")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(Palette.warning)
            }
        }
    }

    private func row(_ title: String, _ amount: Decimal, signed: Bool = false, bold: Bool = false) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(bold ? Palette.ink : Palette.secondaryInk)
            Spacer(minLength: Metrics.s)
            AmountText(amount, currency: account.currency, precision: .cents, signed: signed)
        }
        .font(bold ? .body.weight(.semibold) : .body)
    }

    /// Saves the broker's cash typed, when it's a number that changed.
    private func save() {
        guard case .value(let cash) = AmountInput.parse(statedText, locale: locale) else {
            errorMessage = statedText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : "Type an amount."
            return
        }
        errorMessage = nil
        guard cash != month.statedCash, !MonthText.isStillToCome(month.through) else { return }
        let account = self.account.id
        let date = month.through
        do {
            try library.update { $0.setBrokerCash(cash, of: account, on: date) }
        } catch {
            errorMessage = LibraryStore.describe(error)
        }
    }
}

/// What the account holds at the month's end: each instrument's quantity,
/// price and value, then the cash.
private struct BrokerageHoldingsCard: View {
    let account: Account
    let through: CalendarDate

    @Environment(LibraryStore.self) private var library
    @Environment(CheckInStore.self) private var checkIn
    @Environment(\.locale) private var locale

    var body: some View {
        let valuator = checkIn.valuator(on: through)
        let holdings = valuator.holdings(of: account.id, on: through)
        Card("Holdings on \(AmountFormat.shortDate(through, locale: locale))") {
            CardRows {
                ForEach(holdings, id: \.instrument) { holding in
                    row(holding)
                }
                HStack {
                    Text("Cash")
                    Spacer(minLength: Metrics.s)
                    if let cash = valuator.tradeCash(of: account.id, on: through) {
                        AmountText(cash, currency: account.currency, precision: .cents)
                    }
                }
                .padding(.vertical, Metrics.s)
            }
        }
    }

    private func row(_ holding: Holding) -> some View {
        let instrument = library.library.instruments[holding.instrument]
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(instrument?.name ?? holding.instrument.rawValue)
                    .font(.body.weight(.semibold))
                    .privacySensitiveInFeedback()
                AmountSentenceText(quantity(holding, unit: QuantityFormat.unit(of: instrument)))
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
            }
            Spacer(minLength: Metrics.s)
            if let amount = holding.amount {
                AmountText(amount, currency: account.currency, precision: .cents)
            } else {
                Text("No price")
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .padding(.vertical, Metrics.s)
    }

    /// "432 shares at 121,05 €".
    private func quantity(_ holding: Holding, unit: String?) -> AmountSentence {
        var text = QuantityFormat.quantitySentence(holding.quantity, unit: unit, locale: locale)
        if let price = holding.price {
            text.append(words: " " + QuantityFormat.atPrice(price.price, currency: price.currency, locale: locale))
        }
        return text
    }
}
