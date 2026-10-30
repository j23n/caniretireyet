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
struct BrokerageMonthScreen: View {
    let route: BrokerageRoute

    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.pageLayout) private var layout
    @Environment(\.locale) private var locale
    @State private var addsTrade = false
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
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    navigation.startImport()
                } label: {
                    Label("Import CSV…", systemImage: AppSymbol.importData)
                }
                .disabled(!library.canEdit)
                Button {
                    addsTrade = true
                } label: {
                    Label("Add Trade", systemImage: "plus")
                }
                .disabled(!library.canEdit)
            }
        }
        .sheet(isPresented: $addsTrade) {
            AddTradeSheet(route: route)
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
        library.valuator.brokerageMonth(of: route.account, after: route.from, through: route.through,
                                        in: library.library)
    }

    private var title: String {
        "\(account?.name ?? route.account.rawValue) · \(MonthText.title(route.through, locale: locale))"
    }

    private func content(_ month: BrokerageMonth, account: Account) -> some View {
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

    @Environment(LibraryStore.self) private var library

    var body: some View {
        if let change = library.valuator.change(of: account.id, from: from, to: through, in: .account)?.change {
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
    @Environment(\.locale) private var locale
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            AmountSentenceText(sentence)
                .font(.body.weight(.semibold))
            Text(line.amount < 0 ? "Add it here as a deposit, so both accounts show the same move."
                : "Add it here as a withdrawal, so both accounts show the same move.")
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
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
private struct BrokerageCashCard: View {
    let month: BrokerageMonth
    let account: Account

    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale
    @State private var statedText = ""
    @State private var errorMessage: String?
    @FocusState private var isEditing: Bool

    var body: some View {
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
        .onAppear { statedText = month.statedCash.map { AmountInput.text(for: $0, locale: locale) } ?? "" }
        .onChange(of: month.statedCash) { _, stated in
            if !isEditing { statedText = stated.map { AmountInput.text(for: $0, locale: locale) } ?? "" }
        }
        .onChange(of: isEditing) { _, editing in
            if !editing { save() }
        }
    }

    @ViewBuilder
    private var status: some View {
        if let difference = month.difference {
            if difference == 0 {
                Label("Adds up", systemImage: "checkmark.circle.fill")
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
    @Environment(\.locale) private var locale

    var body: some View {
        let holdings = library.valuator.holdings(of: account.id, on: through)
        Card("Holdings on \(AmountFormat.shortDate(through, locale: locale))") {
            CardRows {
                ForEach(holdings, id: \.instrument) { holding in
                    row(holding)
                }
                HStack {
                    Text("Cash")
                    Spacer(minLength: Metrics.s)
                    if let cash = library.valuator.tradeCash(of: account.id, on: through) {
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
