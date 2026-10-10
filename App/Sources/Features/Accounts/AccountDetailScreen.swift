import Model
import SwiftUI
import Tracker

/// One account (UI.md, "Account detail"): its value and change, a history
/// chart with new-money ticks, the positions of a holdings account, the
/// editable list of valuations with *Add Past Value…* to fill in history,
/// the details, and closing, reopening and deleting. On the Mac the
/// valuations are a table.
///
/// An account that records trades shows, instead of positions, its
/// holdings with average cost and share, its trades by month (a table on
/// the Mac) with *Add Trade…*, its income and gains by year, and what's
/// wrong with its trades. *Switch to Trade History…* and *Switch to
/// Snapshots…* convert an account between the two (docs/TRADES.md).
///
/// Pushing an `AccountID` onto any navigation stack shows it.
struct AccountDetailScreen: View {
    let accountID: AccountID

    @Environment(LibraryStore.self) private var library
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var action: AccountAction?
    @State private var editing: AccountValuationTarget?
    @State private var confirmsDelete = false
    @State private var deletingValuation: ValuationKey?
    @State private var confirmsValuationDelete = false
    @State private var errorMessage = ""
    @State private var showsError = false
    @State private var fillsPastPrices = false
    @State private var tradeTarget: TradeEditorTarget?
    @State private var tradeFilter = TradeListFilter()
    @State private var deletingTrade: TradeKey?
    @State private var confirmsTradeDelete = false
    @State private var conversion: AccountConversionDirection?

    init(accountID: AccountID) {
        self.accountID = accountID
    }

    // The words the iPhone and Mac layouts share.
    private static let incomeNote =
        "Realised gains use the average cost. Dividends and interest are before tax withheld."
    private static let noValues = "No values yet. Update the value, or record one in a check-in."
    private static let noTrades =
        "No trades yet. Add the account's buys, sells and dividends, or its opening positions."

    var body: some View {
        if let account = library.account(accountID) {
            let data = AccountDetailData(account: account, library: library.library, valuator: library.valuator,
                                         today: .today(), stalenessThreshold: preferences.stalenessThreshold)
            let trades: TradeList? = account.recordsTrades
                ? TradeList(account: accountID, library: library.library, valuator: library.valuator,
                            filter: tradeFilter, locale: locale)
                : nil
            layout(data, trades: trades)
                .navigationTitle(account.name)
                .toolbar { toolbarContent(data) }
                .sheet(item: $action) { action in
                    AccountActionSheet(action: action)
                }
                .tradeEditorSheet($tradeTarget)
                .sheet(item: $conversion) { direction in
                    NavigationStack {
                        AccountConversionSheet(accountID: accountID, direction: direction)
                    }
                    #if os(macOS)
                    .frame(minWidth: 480, idealWidth: 560, minHeight: 480, idealHeight: 640)
                    #endif
                }
                .confirmationDialog("Delete this trade?", isPresented: $confirmsTradeDelete,
                                    titleVisibility: .visible, presenting: deletingTrade) { key in
                    Button("Delete Trade", role: .destructive) { removeTrade(key) }
                } message: { key in
                    Text(verbatim: TradeEditNotes.removal(of: key, in: library.library, locale: locale))
                }
                .pastPricesSheet(isPresented: $fillsPastPrices)
                .sheet(item: $editing) { target in
                    NavigationStack {
                        AccountValuationEditor(key: target.key)
                    }
                    #if os(macOS)
                    .frame(minWidth: 440, idealWidth: 500, minHeight: 420, idealHeight: 540)
                    #endif
                }
                .confirmationDialog("Delete \(account.name)?", isPresented: $confirmsDelete,
                                    titleVisibility: .visible) {
                    Button("Delete Account and Its History", role: .destructive) { delete(account) }
                } message: {
                    Text("This removes the account and all its values\(account.recordsTrades ? " and trades" : ""), "
                        + "as if it never existed. It's for mistakes: to stop tracking an account, close it instead.")
                }
                .confirmationDialog("Delete this value?", isPresented: $confirmsValuationDelete,
                                    titleVisibility: .visible, presenting: deletingValuation) { key in
                    Button("Delete Value", role: .destructive) { removeValuation(key) }
                } message: { _ in
                    Text("The account's value then carries forward from the value before it.")
                }
                .alert("Couldn't change the account", isPresented: $showsError) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(errorMessage)
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
        let currency = data.account.currency
        return List {
            Section {
                AccountDetailHeader(data: data)
                AccountHistoryChart(points: data.history, flows: data.flows, currency: currency)
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
            if !data.tradeIssues.isEmpty {
                Section {
                    TradeIssueBanners(notes: data.tradeIssues) { perform($0) }
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                }
            }
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
            if let trades {
                tradeSections(trades, currency: currency)
                if !data.incomeYears.isEmpty {
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
                }
            }
            if data.showsPositions {
                Section {
                    ForEach(data.holdings) { row in
                        NavigationLink {
                            InstrumentEditor(instrumentID: row.instrument)
                        } label: {
                            AccountPositionListRow(row: row, currency: currency)
                        }
                    }
                    if let cash = data.cash {
                        AccountInfoRow(title: "Cash") {
                            AmountText(cash, currency: currency, precision: .cents)
                        }
                    }
                    NavigationLink {
                        InstrumentsScreen()
                    } label: {
                        Label("Instruments", systemImage: AppSymbol.instruments)
                    }
                } header: {
                    Text("Positions")
                } footer: {
                    Text("Values at the latest prices. The gain is the value minus what you paid.")
                }
            }
            Section {
                if data.valuations.isEmpty {
                    Text(Self.noValues)
                        .foregroundStyle(Palette.secondaryInk)
                }
                Button {
                    addPastValue(data)
                } label: {
                    Label("Add Past Value…", systemImage: "calendar.badge.plus")
                }
                .disabled(!library.canEdit)
                ForEach(data.valuations) { row in
                    Button {
                        editing = AccountValuationTarget(key: row.id)
                    } label: {
                        AccountValuationListRow(row: row, currency: currency)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            deletingValuation = row.id
                            confirmsValuationDelete = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(Palette.critical)
                    }
                }
            } header: {
                Text(data.recordsTrades ? "Cash at check-ins" : "Values")
            } footer: {
                if data.recordsTrades {
                    Text("Each value records the account's cash on its date; its holdings come from the trades. A "
                        + "cash that differs from the trades counts as money added or taken out.")
                } else if !data.valuations.isEmpty {
                    Text("Tap a value to change its date, amount, new money or note. A value before the opening "
                        + "date moves it back.")
                }
            }
            Section {
                AccountInfoRows(account: data.account)
            } header: {
                Text("Details")
            }
            Section {
                lifecycleButtons(data)
                conversionButton(data)
            }
            Section {
                Button("Delete Account…", role: .destructive) {
                    confirmsDelete = true
                }
                .disabled(!library.canEdit)
            } footer: {
                Text("Deleting is for mistakes. To stop tracking an account, close it: it keeps its history.")
            }
        }
    }

    // MARK: Mac

    #if os(macOS)
    /// One scrolling page. Everything on it is as tall as its content, and
    /// nothing scrolls on its own: the values and trades are `PageTable`s,
    /// not `Table`s with a guessed height, and the income years aren't a
    /// lazy grid, so the page's height is exact and it scrolls to its last
    /// button.
    private func macLayout(_ data: AccountDetailData, trades: TradeList?) -> some View {
        let currency = data.account.currency
        return ScrollView {
            VStack(alignment: .leading, spacing: Metrics.l) {
                AccountDetailHeader(data: data)
                if let since = data.emptySince {
                    emptyAccountBanner(since)
                }
                Card {
                    AccountHistoryChart(points: data.history, flows: data.flows, currency: currency, height: 240)
                    chartNotes(data)
                }
                if !data.tradeIssues.isEmpty {
                    TradeIssueBanners(notes: data.tradeIssues) { perform($0) }
                }
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
                if let trades {
                    macTradesCard(trades, currency: currency)
                    if !data.incomeYears.isEmpty {
                        Card("Income & gains") {
                            TradeIncomeColumns(years: data.incomeYears, currency: currency)
                            Text(Self.incomeNote)
                                .font(.caption)
                                .foregroundStyle(Palette.mutedInk)
                        }
                    }
                }
                if data.showsPositions {
                    Card("Positions") {
                        AccountPositionsGrid(rows: data.holdings, cash: data.cash, currency: currency)
                    }
                }
                Card {
                    if data.valuations.isEmpty {
                        Text(Self.noValues)
                            .foregroundStyle(Palette.secondaryInk)
                    } else {
                        AccountValuationsTable(
                            rows: data.valuations, currency: currency,
                            edit: { key in editing = AccountValuationTarget(key: key) },
                            delete: { key in
                                deletingValuation = key
                                confirmsValuationDelete = true
                            })
                    }
                } header: {
                    SectionHeader(data.recordsTrades ? "Cash at check-ins" : "Values") {
                        HStack(spacing: Metrics.m) {
                            Text("Double-click a value to edit it")
                                .font(.caption)
                                .foregroundStyle(Palette.mutedInk)
                            Button("Add Past Value…") { addPastValue(data) }
                                .controlSize(.small)
                                .disabled(!library.canEdit)
                                .help("Adds a value on an earlier date. Before the opening date, it moves it back.")
                        }
                    }
                }
                Card("Details") {
                    VStack(alignment: .leading, spacing: Metrics.s) {
                        AccountInfoRows(account: data.account)
                    }
                }
                HStack(spacing: Metrics.m) {
                    lifecycleButtons(data)
                    conversionButton(data)
                    Spacer()
                    Button("Delete Account…", role: .destructive) {
                        confirmsDelete = true
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

    /// The trades as a table, with the filter and *Add Trade…*.
    private func macTradesCard(_ trades: TradeList, currency: CurrencyCode) -> some View {
        Card {
            if trades.isEmpty {
                Text(Self.noTrades)
                    .foregroundStyle(Palette.secondaryInk)
            } else if trades.shownCount == 0 {
                Text("No trades match the filter.")
                    .foregroundStyle(Palette.secondaryInk)
            } else {
                TradesTable(
                    items: trades.items, currency: currency,
                    edit: { key in tradeTarget = .editing(key) },
                    delete: { key in confirmDeleting(key) })
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
                    Button("Add Trade…") { tradeTarget = TradeEditorTarget(account: accountID) }
                        .controlSize(.small)
                        .disabled(!library.canEdit)
                }
            }
        }
    }
    #endif

    // MARK: Trades

    /// *Add Trade…* and the filter, then a section per month, newest first.
    /// Tap a trade to edit it; swipe or long-press to delete it.
    @ViewBuilder
    private func tradeSections(_ trades: TradeList, currency: CurrencyCode) -> some View {
        Section {
            Button {
                tradeTarget = TradeEditorTarget(account: accountID)
            } label: {
                Label("Add Trade…", systemImage: "plus.circle")
            }
            .disabled(!library.canEdit)
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
                    Button {
                        tradeTarget = .editing(item.id)
                    } label: {
                        TradeListRowView(item: item, currency: currency)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            confirmDeleting(item.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(Palette.critical)
                    }
                    .contextMenu {
                        Button {
                            tradeTarget = .editing(item.id)
                        } label: {
                            Label("Edit Trade…", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            confirmDeleting(item.id)
                        } label: {
                            Label("Delete Trade…", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text(verbatim: month.title(locale: locale))
            }
        }
    }

    /// "24 trades", or "3 of 24 trades" with a filter.
    private func tradeCountText(_ trades: TradeList) -> String {
        let total = trades.totalCount == 1 ? "1 trade" : "\(trades.totalCount) trades"
        return trades.shownCount == trades.totalCount ? total : "\(trades.shownCount) of \(total)"
    }

    /// *Switch to Trade History…* for an account that records positions,
    /// *Switch to Snapshots…* for one that records trades.
    @ViewBuilder
    private func conversionButton(_ data: AccountDetailData) -> some View {
        if data.canSwitchToTrades {
            Button("Switch to Trade History…") { conversion = .toTrades }
                .disabled(!library.canEdit)
        } else if data.canSwitchToSnapshots {
            Button("Switch to Snapshots…") { conversion = .toSnapshots }
                .disabled(!library.canEdit)
        }
    }

    // MARK: Shared

    /// An open account that's held nothing for a while: offered to be
    /// closed on the day it emptied, instead of being called stale.
    private func emptyAccountBanner(_ since: CalendarDate) -> some View {
        StatusBanner(
            .info, "This account has been empty since \(AmountFormat.mediumDate(since, locale: locale)). Close it?",
            message: "Closing keeps its history: it stays in every chart up to that day, and leaves check-ins.",
            actionTitle: library.canEdit ? "Close Account…" : nil,
            action: { action = AccountAction(.close, accountID, date: since) })
    }

    @ViewBuilder
    private func lifecycleButtons(_ data: AccountDetailData) -> some View {
        if data.account.isClosed {
            Button("Reopen Account") { reopen() }
                .disabled(!library.canEdit)
        } else {
            Button(data.recordsTrades ? "Update Cash…" : "Update Value…") {
                action = AccountAction(.updateValue, accountID)
            }
            .disabled(!library.canEdit)
            Button("Close Account…") { action = AccountAction(.close, accountID) }
                .disabled(!library.canEdit)
        }
        Button("Edit Account…") { action = AccountAction(.edit, accountID) }
            .disabled(!library.canEdit)
    }

    @ToolbarContentBuilder
    private func toolbarContent(_ data: AccountDetailData) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if data.recordsTrades {
                Button {
                    tradeTarget = TradeEditorTarget(account: accountID)
                } label: {
                    Label("Add Trade", systemImage: "plus")
                }
                .disabled(!library.canEdit)
            } else if !data.account.isClosed {
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

    private func delete(_ account: Account) {
        Task {
            do {
                try await library.deleteAccount(account.id)
                dismiss()
            } catch {
                show(error)
            }
        }
    }

    private func removeValuation(_ key: ValuationKey) {
        do {
            try library.removeValue(key)
        } catch {
            show(error)
        }
    }

    /// Opens *Update Value* on the month end before the first value.
    private func addPastValue(_ data: AccountDetailData) {
        action = AccountAction(.updateValue, accountID, date: data.pastValueDate)
    }

    /// Does what a trade issue's banner offers.
    private func perform(_ action: TradeIssueAction) {
        switch action {
        case .editTrade(let key): tradeTarget = .editing(key)
        case .addTrade(let target): tradeTarget = target
        case .editValuation(let key): editing = AccountValuationTarget(key: key)
        case .editAccount: self.action = AccountAction(.edit, accountID)
        case .switchToTrades: conversion = .toTrades
        }
    }

    private func confirmDeleting(_ key: TradeKey) {
        deletingTrade = key
        confirmsTradeDelete = true
    }

    private func removeTrade(_ key: TradeKey) {
        Task {
            do {
                try await library.removeTrade(key)
            } catch {
                show(error)
            }
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

    private func show(_ error: any Error) {
        errorMessage = LibraryStore.describe(error)
        showsError = true
    }
}

// MARK: - Header

/// The kind, institution, value and its change since the previous value,
/// split into markets, new money and other.
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
                }
                .font(.subheadline)
                let parts = self.parts(of: change)
                // One part alone repeats the change, unless it says it was new money (or other).
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
        [Part(name: "Markets", amount: change.market), Part(name: "New money", amount: change.newMoney),
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

/// One position in the iPhone list: name and value; quantity × price
/// (`AccountPositionText`, the price on a line of its own when both don't
/// fit) and the unrealised gain; the purchase cost.
private struct AccountPositionListRow: View {
    let row: AccountHoldingRow
    let currency: CurrencyCode
    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            AccountPositionNameLine(row: row, currency: currency)
            AccountPositionQuantityLine(row: row) {
                if let gain = row.gain {
                    AccountPositionGain(gain: gain, fraction: row.gainFraction, currency: currency)
                }
            }
            if let cost = AccountPositionText.purchaseCost(row, currency: currency, hidesAmounts: hidesAmounts,
                                                           locale: locale) {
                Text(verbatim: cost)
                    .privacySensitive()
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .padding(.vertical, 2)
    }
}

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

    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale

    var body: some View {
        let quantity = AccountPositionText.quantity(row, hidesAmounts: hidesAmounts, locale: locale)
        let price = AccountPositionText.price(row, locale: locale)
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                Text(verbatim: AccountPositionText.quantityAndPrice(row, hidesAmounts: hidesAmounts, locale: locale))
                    .privacySensitive()
                    .lineLimit(1)
                Spacer(minLength: Metrics.s)
                trailing()
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                    Text(verbatim: quantity)
                        .privacySensitive()
                        .lineLimit(1)
                    Spacer(minLength: Metrics.s)
                    trailing()
                }
                if let price {
                    Text(verbatim: price)
                        .lineLimit(1)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: quantity)
                    .privacySensitive()
                if let price {
                    Text(verbatim: price)
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

#if os(macOS)
/// The positions as a grid on the Mac: instrument, quantity, price, value,
/// purchase cost and unrealised gain.
private struct AccountPositionsGrid: View {
    let rows: [AccountHoldingRow]
    let cash: Decimal?
    let currency: CurrencyCode
    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale

    var body: some View {
        if rows.isEmpty && cash == nil {
            Text("No positions in the latest value.")
                .foregroundStyle(Palette.secondaryInk)
        } else {
            Grid(alignment: .trailing, horizontalSpacing: Metrics.l, verticalSpacing: Metrics.s) {
                GridRow {
                    Text("Instrument")
                        .gridColumnAlignment(.leading)
                    Text("Quantity")
                    Text("Price")
                    Text("Value")
                    Text("Purchase cost")
                    Text("Unrealised gain")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.secondaryInk)
                Divider()
                ForEach(rows) { row in
                    GridRow {
                        Text(row.name)
                            .lineLimit(1)
                        Text(hidesAmounts ? AmountFormat.hidden : QuantityFormat.quantity(row.quantity, locale: locale))
                            .monospacedDigit()
                            .privacySensitive()
                        Text(AccountPositionText.unitPrice(row, locale: locale))
                            .monospacedDigit()
                        if let amount = row.amount {
                            AmountText(amount, currency: currency, precision: .cents)
                        } else {
                            Text("No price").foregroundStyle(Palette.secondaryInk)
                        }
                        if let cost = row.costBasis {
                            AmountText(cost, currency: currency)
                        } else {
                            Text("–").foregroundStyle(Palette.mutedInk)
                        }
                        if let gain = row.gain {
                            DeltaText(gain, currency: currency)
                        } else {
                            Text("–").foregroundStyle(Palette.mutedInk)
                        }
                    }
                }
                if let cash {
                    GridRow {
                        Text("Cash")
                        Text("")
                        Text("")
                        AmountText(cash, currency: currency, precision: .cents)
                        Text("")
                        Text("")
                    }
                }
            }
        }
    }
}
#endif

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

/// One valuation in the iPhone list: date and note, value and new money.
private struct AccountValuationListRow: View {
    let row: AccountValuationRow
    let currency: CurrencyCode

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(AmountFormat.mediumDate(row.valuation.date))
                    .foregroundStyle(Palette.ink)
                if let note = row.valuation.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: Metrics.s)
            VStack(alignment: .trailing, spacing: 2) {
                AccountValuationValue(row: row, currency: currency)
                    .foregroundStyle(Palette.ink)
                flow
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var flow: some View {
        if let flow = row.valuation.flow {
            if flow != 0 {
                HStack(spacing: 4) {
                    Text("new money")
                        .foregroundStyle(Palette.secondaryInk)
                    DeltaText(flow, currency: currency, precision: .automatic, showsArrow: false)
                }
                .font(.caption)
            }
        } else {
            Text("new money unknown")
                .font(.caption)
                .foregroundStyle(Palette.mutedInk)
        }
    }
}

#if os(macOS)
/// The valuations as a table on the Mac: date, value, new money and note,
/// as tall as its lines, so the page scrolls them (`PageTable`).
/// Double-click (or the context menu) edits one.
private struct AccountValuationsTable: View {
    let rows: [AccountValuationRow]
    let currency: CurrencyCode
    let edit: (ValuationKey) -> Void
    let delete: (ValuationKey) -> Void

    private enum Columns {
        static let date = PageTableColumn(min: 84, max: 120)
        static let value = PageTableColumn(min: 100, max: 160, alignment: .trailing)
        static let flow = PageTableColumn(min: 90, max: 140, alignment: .trailing)
        static let note = PageTableColumn(min: 0, max: .infinity)
    }

    var body: some View {
        PageTable(rows, open: edit) {
            Text("Date").pageTableColumn(Columns.date)
            Text("Value").pageTableColumn(Columns.value)
            Text("New money").pageTableColumn(Columns.flow)
            Text("Note").pageTableColumn(Columns.note)
        } row: { row in
            Text(AmountFormat.mediumDate(row.valuation.date))
                .monospacedDigit()
                .pageTableColumn(Columns.date)
            AccountValuationValue(row: row, currency: currency)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .pageTableColumn(Columns.value)
            AccountValuationFlowCell(row: row, currency: currency)
                .pageTableColumn(Columns.flow)
            Text(row.valuation.note ?? "")
                .foregroundStyle(Palette.secondaryInk)
                .pageTableColumn(Columns.note)
        } menu: { row in
            Button("Edit Value…") { edit(row.id) }
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

private struct AccountValuationFlowCell: View {
    let row: AccountValuationRow
    let currency: CurrencyCode

    var body: some View {
        Group {
            if let flow = row.valuation.flow {
                DeltaText(flow, currency: currency, precision: .automatic, showsArrow: false)
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

/// Whether check-ins ask for the money in and out of a cash or savings
/// account, and what came in and went out over the last twelve months
/// (PROGRESS.md, "Money in and out").
private struct AccountMoneyInOutRows: View {
    let account: Account
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let summary = library.valuator.moneyInOut(overYearEndingOn: .today(), accounts: [account.id])
        AccountInfoRow(title: "Money in and out", text: account.tracksMoneyInOut ? "Asked at check-ins" : "Not tracked")
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
    }
}

/// Kind, institution, country, currency, when plans can draw on it, what it counts in,
/// dates, where the money went, tags and notes.
private struct AccountInfoRows: View {
    let account: Account
    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            AccountInfoRow(title: "Kind", text: account.kind.displayName)
            if let institution = account.institution {
                AccountInfoRow(title: "Institution", text: institution)
            }
            if let country = account.country {
                AccountInfoRow(title: "Country", text: CountryChoices.name(of: country, locale: locale))
            }
            AccountInfoRow(title: "Currency", text: CurrencyChoices.name(of: account.currency, locale: locale))
            AccountInfoRow(title: "Plans can draw on it", text: availability)
            AccountInfoRow(title: "Recorded as", text: recordedAs)
            if let mix = assetMix {
                AccountInfoRow(title: "Asset mix", text: mix)
            }
        }
        Group {
            AccountInfoRow(title: "In net worth", text: account.includedInNetWorth ? "Yes" : "No")
            AccountInfoRow(title: "In plans", text: account.includedInPlan ? "Yes" : "No")
            if account.kind.recordsMoneyInOut {
                AccountMoneyInOutRows(account: account)
            }
            AccountInfoRow(title: "Opened", text: AmountFormat.mediumDate(account.opened, locale: locale))
            if let closed = account.closed {
                AccountInfoRow(title: "Closed", text: AmountFormat.mediumDate(closed, locale: locale))
            }
            if let successor = account.successor {
                AccountInfoRow(title: "Money went to", text: library.account(successor)?.name ?? successor.rawValue)
            }
            if !predecessors.isEmpty {
                AccountInfoRow(title: "Took over from", text: predecessors.joined(separator: ", "))
            }
            if !account.tags.isEmpty {
                AccountInfoRow(title: "Tags", text: account.tags.joined(separator: ", "))
            }
            if let notes = account.notes {
                AccountInfoRow(title: "Notes", text: notes)
            }
        }
    }

    /// "From 67", "At any age".
    private var availability: String {
        account.availableFromAge.map { "From \($0)" } ?? "At any age"
    }

    /// "Trade history", "Monthly snapshots of positions", "A balance".
    private var recordedAs: String {
        switch account.valuationMode {
        case .trades: "Trade history"
        case .holdings: "Snapshots of positions"
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

#Preview("Gold coins (snapshots)") {
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

#Preview("Pension fund") {
    NavigationStack {
        AccountDetailScreen(accountID: "fondo-pensione")
    }
    .previewEnvironment()
}

#Preview("Closed") {
    NavigationStack {
        AccountDetailScreen(accountID: "old-bank")
    }
    .previewEnvironment()
}
