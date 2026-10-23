import Model
import SwiftUI
import Tracker

/// One account (UI.md, "Account detail"): its value and change, a history
/// chart with new-money ticks, the list of valuations, the details, and
/// closing, reopening and deleting. On the Mac the valuations are a table.
/// Imported values are read-only (a wrong one can be deleted). An account
/// that takes typed values (`Account.acceptsTypedValues`) offers *Update
/// Value…*, and its typed values open *Edit Value* (`TypedValueSheet`).
///
/// An account that records trades shows, instead of its values, its
/// holdings with average cost and share, its trades by month (a table on
/// the Mac), its income and gains by year, what's wrong
/// with its trades, and the values that record a statement (docs/TRADES.md).
///
/// Pushing an `AccountID` onto any navigation stack shows it.
struct AccountDetailScreen: View {
    let accountID: AccountID

    @Environment(LibraryStore.self) private var library
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var action: AccountAction?
    /// What waits for the user to confirm deleting it.
    @State private var pendingDeletion: AccountDeletion?
    /// Why the last change failed, shown in an alert.
    @State private var error: String?
    @State private var fillsPastPrices = false
    @State private var tradeFilter = TradeListFilter()

    init(accountID: AccountID) {
        self.accountID = accountID
    }

    // The words the iPhone and Mac layouts share.
    private static let incomeNote =
        "Realised gains use the average cost. Dividends and interest are before tax withheld."
    private static let noTrades =
        "No trades yet. Import the broker's transactions for this account."
    private static let statementsNote = "Values that record a broker statement, as a check on the trades. A cash "
        + "that differs from the trades counts as money added or taken out, and positions that differ are pointed "
        + "out above."

    var body: some View {
        if let account = library.account(accountID) {
            let data = AccountDetailData(account: account, library: library.library, valuator: library.valuator,
                                         today: .today(), stalenessThreshold: preferences.stalenessThreshold)
            let trades: TradeList? = account.recordsTrades
                ? TradeList(account: accountID, library: library.library, valuator: library.valuator,
                            filter: tradeFilter, locale: locale)
                : nil
            layout(data, trades: trades)
                .personalNavigationTitle(account.name, hidden: "Account")
                .toolbar { toolbarContent(offersUpdateValue: data.offersUpdateValue) }
                .sheet(item: $action) { action in
                    AccountActionSheet(action: action)
                }
                .pastPricesSheet(isPresented: $fillsPastPrices)
                .confirmationDialog(deletionTitle(of: account), isPresented: confirmsDeletion,
                                    titleVisibility: .visible, presenting: pendingDeletion) { deletion in
                    Button(deletion.buttonTitle, role: .destructive) { delete(deletion) }
                } message: { deletion in
                    Text(verbatim: deletionMessage(deletion, of: account))
                }
                .alert("Couldn't change the account", isPresented: showsError, presenting: error) { _ in
                    Button("OK", role: .cancel) {}
                } message: { error in
                    Text(error)
                }
        } else {
            ContentUnavailableView("This account no longer exists", systemImage: "questionmark.folder")
        }
    }

    @ViewBuilder
    private func layout(_ data: AccountDetailData, trades: TradeList?) -> some View {
        #if os(macOS)
        macLayout(data, trades: trades)
        #else
        listLayout(data, trades: trades)
        #endif
    }

    // MARK: iPhone and iPad

    private func listLayout(_ data: AccountDetailData, trades: TradeList?) -> some View {
        List {
            Section {
                AccountDetailHeader(data: data)
                AccountHistoryChart(points: data.history, savedTicks: data.savedTicks, currency: data.currency)
                    .padding(.vertical, Metrics.xs)
                chartNotes(data)
            }
            if let since = data.emptySince {
                Section {
                    emptyAccountBanner(since)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                }
            }
            ForEach(data.sections, id: \.self) { section in
                listSection(section, data, trades: trades)
            }
            Section {
                AccountInfoRows(account: data.account)
            } header: {
                Text("Details")
            }
            Section {
                lifecycleButtons(data)
            }
            Section {
                Button("Delete Account…", role: .destructive) {
                    pendingDeletion = .account
                }
                .disabled(!library.canEdit)
            } footer: {
                Text("Deleting is for mistakes. To stop tracking an account, close it: it keeps its history.")
            }
        }
    }

    @ViewBuilder
    private func listSection(_ section: AccountDetailSection, _ data: AccountDetailData,
                             trades: TradeList?) -> some View {
        let currency = data.currency
        switch section {
        case .tradeIssues:
            Section {
                TradeIssueBanners(notes: data.tradeIssues) { perform($0) }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
            }
        case .holdings:
            if let holdings = data.tradeHoldings {
                Section {
                    TradeHoldingsRows(holdings: holdings, currency: currency)
                    NavigationLink {
                        InstrumentsScreen()
                    } label: {
                        Label("Instruments", systemImage: AppSymbol.instruments)
                    }
                } header: {
                    Text("Holdings")
                } footer: {
                    Text("From the trades, at the latest prices. The average cost is what was paid per unit, fees "
                        + "included; the gain is the value minus it.")
                }
            }
        case .trades:
            if let trades {
                tradeSections(trades, currency: currency)
            }
        case .income:
            Section {
                ForEach(data.incomeYears) { year in
                    TradeIncomeYearView(year: year, currency: currency)
                        .padding(.vertical, 2)
                }
            } header: {
                Text("Income & gains")
            } footer: {
                Text(Self.incomeNote)
            }
        case .statements:
            Section {
                ForEach(data.statements) { row in
                    AccountStatementListRow(row: row, currency: currency)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            deleteButton(.valuation(row.id))
                        }
                }
            } header: {
                Text("Statements")
            } footer: {
                Text(Self.statementsNote + " Swipe one to delete it.")
            }
        case .values:
            Section {
                if data.valuations.isEmpty {
                    Text(data.noValuesText)
                        .foregroundStyle(Palette.secondaryInk)
                }
                ForEach(data.valuations) { row in
                    valuationRow(row, data)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            deleteButton(.valuation(row.id))
                        }
                }
            } header: {
                Text("Values")
            } footer: {
                if !data.valuations.isEmpty {
                    Text(data.valuesSource
                        + (data.account.acceptsTypedValues ? " Tap a typed value to change it, or swipe a wrong one "
                            + "to delete it." : " Swipe a wrong one to delete it.")
                        + (data.movedNote.map { " " + $0 } ?? ""))
                }
            }
        }
    }

    /// A value in the iPhone list: a typed one opens *Edit Value* when
    /// tapped; an imported one is read-only.
    @ViewBuilder
    private func valuationRow(_ row: AccountValuationRow, _ data: AccountDetailData) -> some View {
        if data.isEditable(row) {
            Button {
                action = AccountAction(.editValue(row.id), accountID)
            } label: {
                AccountValuationListRow(row: row, currency: data.currency)
            }
        } else {
            AccountValuationListRow(row: row, currency: data.currency)
        }
    }

    /// A swipe action's *Delete*, which asks first.
    private func deleteButton(_ deletion: AccountDeletion) -> some View {
        Button {
            pendingDeletion = deletion
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .tint(Palette.critical)
    }

    // MARK: Mac

    #if os(macOS)
    /// One scrolling page. Everything on it is as tall as its content, and
    /// nothing scrolls on its own: the values and trades are `PageTable`s,
    /// not `Table`s with a guessed height, and the income years aren't a
    /// lazy grid, so the page's height is exact and it scrolls to its last
    /// button.
    private func macLayout(_ data: AccountDetailData, trades: TradeList?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.l) {
                AccountDetailHeader(data: data)
                if let since = data.emptySince {
                    emptyAccountBanner(since)
                }
                Card {
                    AccountHistoryChart(points: data.history, savedTicks: data.savedTicks, currency: data.currency,
                                        height: 240)
                    chartNotes(data)
                }
                ForEach(data.sections, id: \.self) { section in
                    macSection(section, data, trades: trades)
                }
                Card("Details") {
                    VStack(alignment: .leading, spacing: Metrics.s) {
                        AccountInfoRows(account: data.account)
                    }
                }
                HStack(spacing: Metrics.m) {
                    lifecycleButtons(data)
                    Spacer()
                    Button("Delete Account…", role: .destructive) {
                        pendingDeletion = .account
                    }
                    .disabled(!library.canEdit)
                }
                .buttonStyle(.bordered)
            }
            .padding(Metrics.xl)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.page)
    }

    @ViewBuilder
    private func macSection(_ section: AccountDetailSection, _ data: AccountDetailData,
                            trades: TradeList?) -> some View {
        let currency = data.currency
        switch section {
        case .tradeIssues:
            TradeIssueBanners(notes: data.tradeIssues) { perform($0) }
        case .holdings:
            if let holdings = data.tradeHoldings {
                Card("Holdings") {
                    if holdings.rows.isEmpty && holdings.cash == nil {
                        Text("No positions: the trades leave nothing held yet.")
                            .foregroundStyle(Palette.secondaryInk)
                    } else {
                        TradeHoldingsGrid(holdings: holdings, currency: currency)
                    }
                }
            }
        case .trades:
            if let trades {
                macTradesCard(trades, currency: currency)
            }
        case .income:
            Card("Income & gains") {
                TradeIncomeColumns(years: data.incomeYears, currency: currency)
                Text(Self.incomeNote)
                    .font(.caption)
                    .foregroundStyle(Palette.mutedInk)
            }
        case .statements:
            Card {
                AccountStatementsTable(rows: data.statements, currency: currency,
                                       delete: { pendingDeletion = .valuation($0) })
                Text(Self.statementsNote)
                    .font(.caption)
                    .foregroundStyle(Palette.mutedInk)
            } header: {
                SectionHeader("Statements")
            }
        case .values:
            Card {
                if data.valuations.isEmpty {
                    Text(data.noValuesText)
                        .foregroundStyle(Palette.secondaryInk)
                } else {
                    AccountValuationsTable(
                        rows: data.valuations, currency: currency,
                        showsMoneyInOut: data.valuationsShowMoneyInOut,
                        showsInterest: data.valuationsShowInterest,
                        editable: library.canEdit ? Set(data.valuations.filter(data.isEditable).map(\.id)) : [],
                        edit: { action = AccountAction(.editValue($0), accountID) },
                        delete: { pendingDeletion = .valuation($0) })
                }
                if let note = data.movedNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Palette.mutedInk)
                }
            } header: {
                SectionHeader("Values") {
                    Text(data.account.acceptsTypedValues
                        ? data.valuesSource + " Double-click a typed value to edit it." : data.valuesSource)
                        .font(.caption)
                        .foregroundStyle(Palette.mutedInk)
                }
            }
        }
    }

    /// The trades as a table, with the filter.
    private func macTradesCard(_ trades: TradeList, currency: CurrencyCode) -> some View {
        Card {
            if trades.isEmpty {
                Text(Self.noTrades)
                    .foregroundStyle(Palette.secondaryInk)
            } else if trades.shownCount == 0 {
                Text("No trades match the filter.")
                    .foregroundStyle(Palette.secondaryInk)
            } else {
                TradesTable(items: trades.items, currency: currency, delete: { pendingDeletion = .trade($0) })
            }
        } header: {
            SectionHeader("Trades") {
                HStack(spacing: Metrics.m) {
                    Text(tradeCountText(trades))
                        .font(.caption)
                        .foregroundStyle(Palette.mutedInk)
                    if !trades.isEmpty {
                        TradeFilterMenu(list: trades, filter: $tradeFilter)
                            .controlSize(.small)
                            .fixedSize()
                    }
                }
            }
        }
    }
    #endif

    // MARK: Trades

    /// The count and the filter, then a section per month, newest first.
    /// Swipe or long-press a trade to delete it.
    @ViewBuilder
    private func tradeSections(_ trades: TradeList, currency: CurrencyCode) -> some View {
        Section {
            if !trades.isEmpty {
                HStack {
                    Text(tradeCountText(trades))
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                    Spacer(minLength: Metrics.s)
                    TradeFilterMenu(list: trades, filter: $tradeFilter)
                        .labelStyle(.titleAndIcon)
                        .font(.footnote)
                }
            } else {
                Text(Self.noTrades)
                    .foregroundStyle(Palette.secondaryInk)
            }
        } header: {
            Text("Trades")
        }
        ForEach(trades.sections) { month in
            Section {
                ForEach(month.items) { item in
                    TradeListRowView(item: item, currency: currency)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            deleteButton(.trade(item.id))
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                pendingDeletion = .trade(item.id)
                            } label: {
                                Label("Delete Trade…", systemImage: "trash")
                            }
                        }
                }
            } header: {
                Text(verbatim: month.title(locale: locale))
                    .privacySensitiveInFeedback()
            }
        }
    }

    /// "24 trades", or "3 of 24 trades" with a filter.
    private func tradeCountText(_ trades: TradeList) -> String {
        let total = trades.totalCount == 1 ? "1 trade" : "\(trades.totalCount) trades"
        return trades.shownCount == trades.totalCount ? total : "\(trades.shownCount) of \(total)"
    }

    // MARK: Shared

    /// An open account that's held nothing for a while: offered to be
    /// closed on the day it emptied, instead of being called stale.
    private func emptyAccountBanner(_ since: CalendarDate) -> some View {
        StatusBanner(
            .info, "This account has been empty since \(AmountFormat.mediumDate(since, locale: locale)). Close it?",
            message: "Closing keeps its history: it stays in every chart up to that day, and leaves check-ins.",
            personal: .title, actionTitle: library.canEdit ? "Close Account…" : nil,
            action: { action = AccountAction(.close, accountID, date: since) })
    }

    @ViewBuilder
    private func lifecycleButtons(_ data: AccountDetailData) -> some View {
        if data.account.isClosed {
            Button("Reopen Account") { reopen() }
                .disabled(!library.canEdit)
        } else {
            if data.offersUpdateValue {
                Button("Update Value…") { action = AccountAction(.updateValue, accountID) }
                    .disabled(!library.canEdit)
            }
            Button("Close Account…") { action = AccountAction(.close, accountID) }
                .disabled(!library.canEdit)
        }
        Button("Edit Account…") { action = AccountAction(.edit, accountID) }
            .disabled(!library.canEdit)
    }

    /// *Update Value* for an account that takes typed values, and *Edit Account*.
    @ToolbarContentBuilder
    private func toolbarContent(offersUpdateValue: Bool) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if offersUpdateValue {
                Button {
                    action = AccountAction(.updateValue, accountID)
                } label: {
                    Label("Update Value", systemImage: "square.and.pencil")
                }
                .disabled(!library.canEdit)
            }
            Button {
                action = AccountAction(.edit, accountID)
            } label: {
                Label("Edit Account", systemImage: "pencil")
            }
            .disabled(!library.canEdit)
        }
    }

    // MARK: Actions

    private func reopen() {
        do {
            try library.reopenAccount(accountID)
        } catch {
            show(error)
        }
    }

    /// Whether a deletion waits to be confirmed; dismissing the dialog drops it.
    private var confirmsDeletion: Binding<Bool> {
        Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
    }

    private func deletionTitle(of account: Account) -> String {
        switch pendingDeletion {
        case .account, nil: "Delete \(account.name)?"
        case .valuation: "Delete this value?"
        case .trade: "Delete this trade?"
        }
    }

    private func deletionMessage(_ deletion: AccountDeletion, of account: Account) -> String {
        switch deletion {
        case .account:
            "This removes the account and all its values\(account.recordsTrades ? " and trades" : ""), as if it "
                + "never existed. It's for mistakes: to stop tracking an account, close it instead."
        case .valuation(let key):
            AccountValueNotes.deleteMessage(removing: key, in: library.library, locale: locale)
        case .trade(let key):
            TradeEditNotes.removal(of: key, in: library.library, locale: locale)
        }
    }

    private func delete(_ deletion: AccountDeletion) {
        Task {
            do {
                switch deletion {
                case .account:
                    try await library.deleteAccount(accountID)
                    dismiss()
                case .valuation(let key):
                    try library.removeValue(key)
                case .trade(let key):
                    try await library.removeTrade(key)
                }
            } catch {
                show(error)
            }
        }
    }

    /// Does what a trade issue's banner offers.
    private func perform(_ action: TradeIssueAction) {
        switch action {
        case .editAccount: self.action = AccountAction(.edit, accountID)
        }
    }

    /// The notes under the chart: values that can't be worked out, and old
    /// prices, each offering *Fill In Past Prices…*.
    @ViewBuilder
    private func chartNotes(_ data: AccountDetailData) -> some View {
        if let note = missingValueNote(data) {
            OldPriceNoteView(text: note, systemImage: "exclamationmark.triangle") { fillsPastPrices = true }
        }
        if let note = oldPriceNote(data) {
            OldPriceNoteView(text: note) { fillsPastPrices = true }
        }
    }

    /// The note under the chart when some values can't be worked out, or
    /// can't be converted to the base currency for net worth.
    private func missingValueNote(_ data: AccountDetailData) -> String? {
        MissingValueNote.account(chart: data.missing, netWorth: data.missingBaseRates, name: { id in
            library.library.instruments[id]?.name ?? id.rawValue
        }, locale: locale)
    }

    /// The note under the chart when its values use old prices.
    private func oldPriceNote(_ data: AccountDetailData) -> String? {
        data.oldPrices.map { summary in
            OldPriceNote.text(summary) { library.library.instruments[$0]?.name ?? $0.rawValue }
        }
    }

    /// Whether the alert shows ``error``; dismissing it clears it.
    private var showsError: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }

    private func show(_ error: any Error) {
        self.error = LibraryStore.describe(error)
    }
}

/// A deletion on an account's page, waiting for the user to confirm it.
private enum AccountDeletion: Hashable {
    case account
    case valuation(ValuationKey)
    case trade(TradeKey)

    var buttonTitle: String {
        switch self {
        case .account: "Delete Account and Its History"
        case .valuation: "Delete Value"
        case .trade: "Delete Trade"
        }
    }
}

// MARK: - Header

/// The kind, institution, value and its change since the previous value,
/// split into markets, saved and other.
private struct AccountDetailHeader: View {
    let data: AccountDetailData
    @Environment(\.locale) private var locale

    private struct Part: Identifiable {
        var name: String
        var amount: Decimal
        var id: String { name }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            HStack(spacing: Metrics.s) {
                Label(data.account.kind.displayName, systemImage: data.account.kind.systemImage)
                    .lineLimit(1)
                if let institution = data.account.institution {
                    Text(institution)
                        .lineLimit(1)
                        .privacySensitiveInFeedback()
                }
                if data.stale != nil {
                    AccountStaleBadge()
                }
            }
            .font(.subheadline)
            .foregroundStyle(Palette.secondaryInk)
            AmountText(data.amount, currency: data.currency, precision: .cents, tabular: false,
                       animatesChanges: true)
                .font(.largeTitle.bold())
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            baseValueLine
            if !data.amountIsComplete {
                Text("A price or exchange rate is missing, so part of the value is left out.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let change = data.change, let from = data.changeFrom {
                HStack(spacing: Metrics.xs) {
                    DeltaText(change.change, currency: data.currency, precision: .cents)
                    Text("since \(AmountFormat.shortDate(from, relativeTo: .today(), locale: locale))")
                        .foregroundStyle(Palette.secondaryInk)
                        .privacySensitiveInFeedback()
                }
                .font(.subheadline)
                let parts = self.parts(of: change)
                // One part alone repeats the change, unless it says it was saved (or other).
                if parts.count > 1 || parts.first.map({ $0.name != "Markets" }) == true {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Metrics.m) { partViews(parts) }
                        VStack(alignment: .leading, spacing: 2) { partViews(parts) }
                    }
                    .font(.footnote)
                }
            }
            Text(statusLine)
                .font(.caption)
                .foregroundStyle(Palette.mutedInk)
                .privacySensitiveInFeedback()
        }
        .padding(.vertical, Metrics.xs)
    }

    /// For an account in another currency, its value in the base currency
    /// at the date's rate, or that the rate is missing.
    @ViewBuilder
    private var baseValueLine: some View {
        switch data.baseValue {
        case .known(let value):
            AmountText(value, precision: .cents)
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
        case .rateMissing:
            Text("Value in \(data.baseCurrency.rawValue): rate missing")
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
        case nil:
            EmptyView()
        }
    }

    /// The parts that don't show as zero.
    private func parts(of change: ValueChange) -> [Part] {
        [Part(name: "Markets", amount: change.market), Part(name: "Saved", amount: change.saved),
         Part(name: "Other", amount: change.other)]
            .filter { DeltaFormat.direction(of: $0.amount, precision: .whole) != 0 }
    }

    private func partViews(_ parts: [Part]) -> some View {
        ForEach(parts) { part in
            HStack(spacing: 4) {
                Text(part.name)
                    .foregroundStyle(Palette.secondaryInk)
                DeltaText(part.amount, currency: data.currency, showsArrow: false)
            }
        }
    }

    private var statusLine: String {
        if let closed = data.account.closed {
            return "Closed on \(AmountFormat.mediumDate(closed, locale: locale))"
        }
        guard let latest = data.latest else { return "No value yet" }
        return "Last value on \(AmountFormat.mediumDate(latest.date, locale: locale))"
    }
}

// MARK: - Positions

/// A position's first line: its name, and its value in the account's
/// currency (or "No price").
struct AccountPositionNameLine: View {
    let row: AccountHoldingRow
    let currency: CurrencyCode

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Text(row.name)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .privacySensitiveInFeedback()
            Spacer(minLength: Metrics.s)
            if let amount = row.amount {
                AmountText(amount, currency: currency, precision: .cents)
                    .foregroundStyle(Palette.ink)
                    .layoutPriority(1)
            } else {
                Text("No price")
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }
}

/// A position's quantity × price, with `trailing` (its share, or its gain)
/// at the end of the line: "0,10383916 BTC × 73.785,11 €   95 % of the
/// account". When that doesn't fit, the quantity and `trailing` share a
/// line and "at 73.785,11 €" goes on the next; at the largest text sizes
/// each is a line of its own. In footnote type, secondary ink.
struct AccountPositionQuantityLine<Trailing: View>: View {
    let row: AccountHoldingRow
    @ViewBuilder let trailing: () -> Trailing

    @Environment(\.locale) private var locale

    var body: some View {
        let quantity = AccountPositionText.quantity(row, locale: locale)
        let price = AccountPositionText.price(row, locale: locale)
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                AmountSentenceText(AccountPositionText.quantityAndPrice(row, locale: locale))
                    .lineLimit(1)
                Spacer(minLength: Metrics.s)
                trailing()
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                    AmountSentenceText(quantity)
                        .lineLimit(1)
                    Spacer(minLength: Metrics.s)
                    trailing()
                }
                if let price {
                    Text(verbatim: price)
                        .lineLimit(1)
                        .privacySensitiveInFeedback()
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                AmountSentenceText(quantity)
                if let price {
                    Text(verbatim: price)
                        .privacySensitiveInFeedback()
                }
                trailing()
            }
        }
        .font(.footnote)
        .foregroundStyle(Palette.secondaryInk)
    }
}

/// A position's unrealised gain: "▼ −2.871 € −27,3 %", the amount and its
/// fraction of the cost kept together.
struct AccountPositionGain: View {
    let gain: Decimal
    let fraction: Double?
    let currency: CurrencyCode

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
            DeltaText(gain, currency: currency)
            if let fraction {
                DeltaText(percent: fraction, showsArrow: false)
            }
        }
        .fixedSize()
    }
}

// MARK: - Valuations

/// A valuation's value in the account's currency, else (a price or rate
/// missing) what could be valued, in the base currency.
private struct AccountValuationValue: View {
    let row: AccountValuationRow
    let currency: CurrencyCode

    var body: some View {
        if let amount = row.amount {
            AmountText(amount, currency: currency, precision: .cents)
        } else {
            AmountText(row.value, precision: .cents)
        }
    }
}

/// One valuation in the iPhone list: date and note, value, and what was saved,
/// or for a cash or savings value that records them, money in and out,
/// interest and what moved between your own accounts.
private struct AccountValuationListRow: View {
    let row: AccountValuationRow
    let currency: CurrencyCode

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(AmountFormat.mediumDate(row.valuation.date))
                    .foregroundStyle(Palette.ink)
                    .privacySensitiveInFeedback()
                if let note = row.valuation.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(2)
                        .privacySensitiveInFeedback()
                }
            }
            Spacer(minLength: Metrics.s)
            VStack(alignment: .trailing, spacing: 2) {
                AccountValuationValue(row: row, currency: currency)
                    .foregroundStyle(Palette.ink)
                if row.recordsMoneyInOut {
                    moneyInOut
                } else {
                    savedText
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// "in 3.400,00 € out 2.554,65 €", the interest, and "moved −1.150,00 €".
    @ViewBuilder
    private var moneyInOut: some View {
        HStack(spacing: 4) {
            Text("in")
                .foregroundStyle(Palette.secondaryInk)
            AmountText(row.valuation.moneyIn ?? 0, currency: currency, precision: .cents)
            Text("out")
                .foregroundStyle(Palette.secondaryInk)
            AmountText(row.valuation.moneyOut ?? 0, currency: currency, precision: .cents)
        }
        .font(.caption)
        if let interest = row.valuation.interest, interest != 0 {
            HStack(spacing: 4) {
                Text("interest")
                    .foregroundStyle(Palette.secondaryInk)
                DeltaText(interest, currency: currency, precision: .automatic, showsArrow: false)
            }
            .font(.caption)
        }
        if let moved = row.moved {
            HStack(spacing: 4) {
                Text("moved")
                    .foregroundStyle(Palette.secondaryInk)
                DeltaText(moved, currency: currency, precision: .automatic, showsArrow: false)
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private var savedText: some View {
        if let saved = row.saved {
            if saved != 0 {
                HStack(spacing: 4) {
                    Text("saved")
                        .foregroundStyle(Palette.secondaryInk)
                    DeltaText(saved, currency: currency, precision: .automatic, showsArrow: false)
                }
                .font(.caption)
            }
        } else {
            Text("saved unknown")
                .font(.caption)
                .foregroundStyle(Palette.mutedInk)
        }
    }
}

// MARK: - Statements

/// A statement's positions in words ("2 positions listed, as the trades
/// give"), in warning ink when one differs from the trades.
private struct AccountStatementPositions: View {
    let row: AccountStatementRow

    var body: some View {
        if let text = row.positionsText {
            Text(text)
                .foregroundStyle(row.mismatchCount > 0 ? Palette.warning : Palette.secondaryInk)
                .privacySensitiveInFeedback()
        }
    }
}

/// One statement of a trades account in the iPhone list: date, positions
/// and note; the cash it shows and how much of it no trade records.
private struct AccountStatementListRow: View {
    let row: AccountStatementRow
    let currency: CurrencyCode

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(AmountFormat.mediumDate(row.valuation.date))
                    .foregroundStyle(Palette.ink)
                    .privacySensitiveInFeedback()
                AccountStatementPositions(row: row)
                    .font(.caption)
                if let note = row.valuation.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(2)
                        .privacySensitiveInFeedback()
                }
            }
            Spacer(minLength: Metrics.s)
            VStack(alignment: .trailing, spacing: 2) {
                if let cash = row.cash {
                    HStack(spacing: 4) {
                        Text("cash")
                            .foregroundStyle(Palette.secondaryInk)
                        AmountText(cash, currency: currency, precision: .cents)
                            .foregroundStyle(Palette.ink)
                    }
                }
                if let difference = row.cashDifference {
                    HStack(spacing: 4) {
                        Text("not in the trades")
                            .foregroundStyle(Palette.secondaryInk)
                        DeltaText(difference, currency: currency, precision: .automatic, showsArrow: false)
                    }
                    .font(.caption)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#if os(macOS)
/// A trades account's statements as a table on the Mac: date, cash, the
/// part of it no trade records, positions and note, as tall as its lines
/// (`PageTable`). The context menu deletes one.
private struct AccountStatementsTable: View {
    let rows: [AccountStatementRow]
    let currency: CurrencyCode
    let delete: (ValuationKey) -> Void

    private enum Columns {
        static let date = PageTableColumn(min: 84, max: 120)
        static let cash = PageTableColumn(min: 100, max: 160, alignment: .trailing)
        static let difference = PageTableColumn(min: 110, max: 160, alignment: .trailing)
        static let positions = PageTableColumn(min: 160, max: 280)
        static let note = PageTableColumn(min: 0, max: .infinity)
    }

    var body: some View {
        PageTable(rows, open: { _ in }) {
            Text("Date").pageTableColumn(Columns.date)
            Text("Cash").pageTableColumn(Columns.cash)
            Text("Not in the trades").pageTableColumn(Columns.difference)
            Text("Positions").pageTableColumn(Columns.positions)
            Text("Note").pageTableColumn(Columns.note)
        } row: { row in
            Text(AmountFormat.mediumDate(row.valuation.date))
                .monospacedDigit()
                .privacySensitiveInFeedback()
                .pageTableColumn(Columns.date)
            Group {
                if let cash = row.cash {
                    AmountText(cash, currency: currency, precision: .cents)
                } else {
                    Text("")
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .pageTableColumn(Columns.cash)
            Group {
                if let difference = row.cashDifference {
                    DeltaText(difference, currency: currency, precision: .automatic, showsArrow: false)
                } else {
                    Text("")
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .pageTableColumn(Columns.difference)
            AccountStatementPositions(row: row)
                .lineLimit(2)
                .pageTableColumn(Columns.positions)
            Text(row.valuation.note ?? "")
                .foregroundStyle(Palette.secondaryInk)
                .privacySensitiveInFeedback()
                .pageTableColumn(Columns.note)
        } menu: { row in
            Button("Delete Statement…", role: .destructive) { delete(row.id) }
        }
    }
}
#endif

#if os(macOS)
/// The valuations as a table on the Mac: date, value, saved and note,
/// and for a cash or savings account (`showsMoneyInOut`) money in, money
/// out, the interest (a savings account's, `showsInterest`) and what moved
/// between your own accounts. As tall as its lines, so the page scrolls
/// them (`PageTable`). Double-click (or the context menu) edits a typed
/// value (`editable`); the context menu deletes any.
private struct AccountValuationsTable: View {
    let rows: [AccountValuationRow]
    let currency: CurrencyCode
    let showsMoneyInOut: Bool
    let showsInterest: Bool
    /// The values *Edit Value* can change: typed ones.
    let editable: Set<ValuationKey>
    let edit: (ValuationKey) -> Void
    let delete: (ValuationKey) -> Void

    private enum Columns {
        static let date = PageTableColumn(min: 84, max: 120)
        static let value = PageTableColumn(min: 100, max: 160, alignment: .trailing)
        static let saved = PageTableColumn(min: 90, max: 140, alignment: .trailing)
        static let amount = PageTableColumn(min: 80, max: 130, alignment: .trailing)
        static let note = PageTableColumn(min: 0, max: .infinity)
    }

    var body: some View {
        PageTable(rows, open: { key in if editable.contains(key) { edit(key) } }) {
            Text("Date").pageTableColumn(Columns.date)
            Text("Value").pageTableColumn(Columns.value)
            Text("Saved").pageTableColumn(Columns.saved)
            if showsMoneyInOut {
                Text("In").pageTableColumn(Columns.amount)
                Text("Out").pageTableColumn(Columns.amount)
                if showsInterest {
                    Text("Interest").pageTableColumn(Columns.amount)
                }
                Text("Moved").pageTableColumn(Columns.amount)
            }
            Text("Note").pageTableColumn(Columns.note)
        } row: { row in
            Text(AmountFormat.mediumDate(row.valuation.date))
                .monospacedDigit()
                .privacySensitiveInFeedback()
                .pageTableColumn(Columns.date)
            AccountValuationValue(row: row, currency: currency)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .pageTableColumn(Columns.value)
            AccountValuationSavedCell(row: row, currency: currency)
                .pageTableColumn(Columns.saved)
            if showsMoneyInOut {
                AccountValuationAmountCell(amount: row.valuation.moneyIn, currency: currency)
                    .pageTableColumn(Columns.amount)
                AccountValuationAmountCell(amount: row.valuation.moneyOut, currency: currency)
                    .pageTableColumn(Columns.amount)
                if showsInterest {
                    AccountValuationAmountCell(amount: row.valuation.interest, currency: currency, signed: true)
                        .pageTableColumn(Columns.amount)
                }
                AccountValuationAmountCell(amount: row.moved, currency: currency, signed: true)
                    .pageTableColumn(Columns.amount)
            }
            Text(row.valuation.note ?? "")
                .foregroundStyle(Palette.secondaryInk)
                .privacySensitiveInFeedback()
                .pageTableColumn(Columns.note)
        } menu: { row in
            if editable.contains(row.id) {
                Button("Edit Value…") { edit(row.id) }
            }
            Button("Delete Value…", role: .destructive) { delete(row.id) }
        }
    }
}

/// A trades account's income and gains, a year per column: as many columns
/// of at least 220 points as fit, like an adaptive `LazyVGrid`. Not lazy, so
/// the page measures its height exactly.
private struct TradeIncomeColumns: View {
    let years: [TradeIncomeYear]
    let currency: CurrencyCode

    private static let columnWidth: CGFloat = 220

    var body: some View {
        ViewThatFits(in: .horizontal) {
            grid(columns: 3)
            grid(columns: 2)
            grid(columns: 1)
        }
    }

    private func grid(columns: Int) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: Metrics.xl, verticalSpacing: Metrics.l) {
            ForEach(Array(stride(from: 0, to: years.count, by: columns)), id: \.self) { start in
                GridRow {
                    ForEach(start..<(start + columns), id: \.self) { index in
                        if index < years.count {
                            TradeIncomeYearView(year: years[index], currency: currency)
                                .frame(minWidth: Self.columnWidth, idealWidth: Self.columnWidth, maxWidth: .infinity,
                                       alignment: .topLeading)
                        } else {
                            // Keeps a short last row in the same columns.
                            Color.clear
                                .frame(minWidth: Self.columnWidth, idealWidth: Self.columnWidth, maxWidth: .infinity,
                                       maxHeight: 0)
                        }
                    }
                }
            }
        }
    }
}

/// An amount in the Mac's table of values, empty when it isn't recorded:
/// money in or out, or with a sign, the interest or what moved.
private struct AccountValuationAmountCell: View {
    let amount: Decimal?
    let currency: CurrencyCode
    var signed = false

    var body: some View {
        Group {
            if let amount {
                if signed {
                    DeltaText(amount, currency: currency, precision: .automatic, showsArrow: false)
                } else {
                    AmountText(amount, currency: currency, precision: .cents)
                }
            } else {
                Text("")
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct AccountValuationSavedCell: View {
    let row: AccountValuationRow
    let currency: CurrencyCode

    var body: some View {
        Group {
            if let saved = row.saved {
                DeltaText(saved, currency: currency, precision: .automatic, showsArrow: false)
            } else {
                Text("Unknown")
                    .foregroundStyle(Palette.mutedInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
#endif

// MARK: - Details

/// A label and a value in a details list.
private struct AccountInfoRow<Value: View>: View {
    let title: String
    private let value: Value

    init(title: String, @ViewBuilder value: () -> Value) {
        self.title = title
        self.value = value()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.m) {
            Text(title)
                .foregroundStyle(Palette.secondaryInk)
            Spacer(minLength: Metrics.m)
            value
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

extension AccountInfoRow where Value == Text {
    init(title: String, text: String) {
        self.init(title: title) { Text(text) }
    }
}

/// What came in and went out of a cash or savings account over the last
/// twelve months (PROGRESS.md, "Money in and out").
private struct AccountMoneyInOutRows: View {
    let account: Account
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let summary = library.valuator.moneyInOut(overYearEndingOn: .today(), accounts: [account.id])
        if !summary.isEmpty {
            AccountInfoRow(title: "In, last 12 months") {
                AmountText(summary.moneyIn)
            }
            AccountInfoRow(title: "Out, last 12 months") {
                AmountText(summary.moneyOut)
            }
            let months = summary.months.count
            Text(verbatim: "\(Wording.count(months, "month")) recorded, in "
                + "\(summary.currency.rawValue).")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
        }
        if !summary.isComplete {
            Text(verbatim: "Values without an exchange rate to \(summary.currency.rawValue) are left out.")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
        }
    }
}

/// Kind, institution, country, currency, when plans can draw on it, its tax on
/// withdrawals, what it counts in, dates, where the money went, tags and notes.
private struct AccountInfoRows: View {
    let account: Account
    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            AccountInfoRow(title: "Kind", text: account.kind.displayName)
            if let institution = account.institution {
                AccountInfoRow(title: "Institution") {
                    Text(institution)
                        .privacySensitiveInFeedback()
                }
            }
            if let country = account.country {
                AccountInfoRow(title: "Country", text: CountryChoices.name(of: country, locale: locale))
            }
            AccountInfoRow(title: "Currency", text: CurrencyChoices.name(of: account.currency, locale: locale))
            AccountInfoRow(title: "Plans can draw on it") {
                Text(availability)
                    .privacySensitiveInFeedback()
            }
            if account.includedInPlan, !account.kind.isLiability, let rate = account.withdrawalTaxRate {
                AccountInfoRow(title: "Tax on withdrawals") {
                    Text(AmountFormat.percent(rate, locale: locale))
                        .privacySensitiveInFeedback()
                }
            }
            AccountInfoRow(title: "Recorded as", text: recordedAs)
            if let mix = assetMix {
                AccountInfoRow(title: "Asset mix") {
                    Text(mix)
                        .privacySensitiveInFeedback()
                }
            }
        }
        Group {
            AccountInfoRow(title: "In net worth", text: account.includedInNetWorth ? "Yes" : "No")
            AccountInfoRow(title: "In plans", text: account.includedInPlan ? "Yes" : "No")
            if account.kind.recordsMoneyInOut {
                AccountMoneyInOutRows(account: account)
            }
            AccountInfoRow(title: "Opened") {
                Text(AmountFormat.mediumDate(account.opened, locale: locale))
                    .privacySensitiveInFeedback()
            }
            if let closed = account.closed {
                AccountInfoRow(title: "Closed") {
                    Text(AmountFormat.mediumDate(closed, locale: locale))
                        .privacySensitiveInFeedback()
                }
            }
            if let successor = account.successor {
                AccountInfoRow(title: "Money went to") {
                    Text(library.account(successor)?.name ?? successor.rawValue)
                        .privacySensitiveInFeedback()
                }
            }
            if !predecessors.isEmpty {
                AccountInfoRow(title: "Took over from") {
                    Text(predecessors.joined(separator: ", "))
                        .privacySensitiveInFeedback()
                }
            }
            if !account.tags.isEmpty {
                AccountInfoRow(title: "Tags") {
                    Text(account.tags.joined(separator: ", "))
                        .privacySensitiveInFeedback()
                }
            }
            if let notes = account.notes {
                AccountInfoRow(title: "Notes") {
                    Text(notes)
                        .privacySensitiveInFeedback()
                }
            }
        }
    }

    /// "From 67", "At any age".
    private var availability: String {
        account.availableFromAge.map { "From \($0)" } ?? "At any age"
    }

    /// "Trade history", "A balance".
    private var recordedAs: String {
        switch account.valuationMode {
        case .trades: "Trade history"
        case .balance: "A balance"
        default: account.valuationMode.rawValue
        }
    }

    /// Closed accounts whose money went to this one.
    private var predecessors: [String] {
        library.library.accounts.values.filter { $0.successor == account.id }.map(\.name).sorted()
    }

    /// "60% equity, 40% bonds" for a balance account; "(default)" when it
    /// comes from the kind.
    private var assetMix: String? {
        guard !account.kind.isLiability, let mix = account.effectiveAssetClasses, mix.total > 0
        else { return nil }
        let parts = BreakdownKey.assetClassOrder.filter { mix[$0] != 0 }.map { assetClass in
            "\(AmountFormat.percent(mix[assetClass], digits: 0, locale: locale)) "
                + BreakdownKey.assetClass(assetClass).description.lowercased()
        }
        return parts.joined(separator: ", ") + (account.assetClasses == nil ? " (default)" : "")
    }
}

#Preview("Brokerage with trades") {
    NavigationStack {
        AccountDetailScreen(accountID: "directa")
            .appDestinations()
    }
    .previewEnvironment()
}

#Preview("Trades with a mismatch") {
    NavigationStack {
        AccountDetailScreen(accountID: "directa")
            .appDestinations()
    }
    .previewEnvironment(PreviewLibrary.withStatementMismatch)
}

#Preview("Gold coins (paid from outside)") {
    NavigationStack {
        AccountDetailScreen(accountID: "gold-coins")
            .appDestinations()
    }
    .previewEnvironment()
}

#Preview("Dollar account without past rates") {
    // Dollars from 2018, emptied in 2022, no USD rate before October 2025.
    NavigationStack {
        AccountDetailScreen(accountID: PreviewLibrary.foreignAccount)
            .appDestinations()
    }
    .previewEnvironment(PreviewLibrary.withForeignAccount)
}

#Preview("Current account with money in and out") {
    NavigationStack {
        AccountDetailScreen(accountID: "conto-fineco")
    }
    .previewEnvironment()
}

#Preview("Savings with interest") {
    NavigationStack {
        AccountDetailScreen(accountID: "conto-deposito")
    }
    .previewEnvironment()
}

#Preview("Pension fund") {
    NavigationStack {
        AccountDetailScreen(accountID: "fondo-pensione")
    }
    .previewEnvironment()
}

#Preview("Home with typed values") {
    NavigationStack {
        AccountDetailScreen(accountID: "casa")
    }
    .previewEnvironment()
}

#Preview("Closed") {
    NavigationStack {
        AccountDetailScreen(accountID: "old-bank")
    }
    .previewEnvironment()
}
