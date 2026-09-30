import Model
import SwiftUI
import Tracker

/// One account (UI.md, "Account detail"): its value and change, a history
/// chart with new-money ticks, the positions of a holdings account, the
/// editable list of valuations, the details, and closing, reopening and
/// deleting. On the Mac the valuations are a table.
///
/// Pushing an `AccountID` onto any navigation stack shows it.
struct AccountDetailScreen: View {
    let accountID: AccountID

    @Environment(LibraryStore.self) private var library
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss

    @State private var action: AccountAction?
    @State private var editing: AccountValuationTarget?
    @State private var confirmsDelete = false
    @State private var deletingValuation: ValuationKey?
    @State private var confirmsValuationDelete = false
    @State private var errorMessage = ""
    @State private var showsError = false

    init(accountID: AccountID) {
        self.accountID = accountID
    }

    var body: some View {
        if let account = library.account(accountID) {
            let data = AccountDetailData(account: account, library: library.library, valuator: library.valuator,
                                         today: .today(), stalenessThreshold: preferences.stalenessThreshold)
            layout(data)
                .navigationTitle(account.name)
                .toolbar { toolbarContent(data) }
                .sheet(item: $action) { action in
                    AccountActionSheet(action: action)
                }
                .sheet(item: $editing) { target in
                    NavigationStack {
                        ValuationEditor(key: target.key)
                    }
                    #if os(macOS)
                    .frame(minWidth: 440, idealWidth: 500, minHeight: 420, idealHeight: 540)
                    #endif
                }
                .confirmationDialog("Delete \(account.name)?", isPresented: $confirmsDelete,
                                    titleVisibility: .visible) {
                    Button("Delete Account and Its History", role: .destructive) { delete(account) }
                } message: {
                    Text("This removes the account and all its values, as if it never existed. It's for mistakes: "
                        + "to stop tracking an account, close it instead.")
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
    private func layout(_ data: AccountDetailData) -> some View {
        #if os(macOS)
        macLayout(data)
        #else
        listLayout(data)
        #endif
    }

    // MARK: iPhone and iPad

    private func listLayout(_ data: AccountDetailData) -> some View {
        let currency = data.account.currency
        return List {
            Section {
                AccountDetailHeader(data: data)
                AccountHistoryChart(points: data.history, flows: data.flows, currency: currency)
                    .padding(.vertical, Metrics.xs)
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
                    Text("No values yet. Update the value, or record one in a check-in.")
                        .foregroundStyle(Palette.secondaryInk)
                }
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
                Text("Values")
            } footer: {
                if !data.valuations.isEmpty {
                    Text("Tap a value to change its date, amount, new money or note.")
                }
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
    private func macLayout(_ data: AccountDetailData) -> some View {
        let currency = data.account.currency
        return ScrollView {
            VStack(alignment: .leading, spacing: Metrics.l) {
                AccountDetailHeader(data: data)
                Card {
                    AccountHistoryChart(points: data.history, flows: data.flows, currency: currency, height: 240)
                }
                if data.showsPositions {
                    Card("Positions") {
                        AccountPositionsGrid(rows: data.holdings, cash: data.cash, currency: currency)
                    }
                }
                Card {
                    if data.valuations.isEmpty {
                        Text("No values yet. Update the value, or record one in a check-in.")
                            .foregroundStyle(Palette.secondaryInk)
                    } else {
                        AccountValuationsTable(
                            rows: data.valuations, currency: currency,
                            edit: { key in editing = AccountValuationTarget(key: key) },
                            delete: { key in
                                deletingValuation = key
                                confirmsValuationDelete = true
                            })
                            .frame(height: min(CGFloat(data.valuations.count) * 26 + 36, 380))
                    }
                } header: {
                    SectionHeader("Values") {
                        Text("Double-click a value to edit it")
                            .font(.caption)
                            .foregroundStyle(Palette.mutedInk)
                    }
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
    #endif

    // MARK: Shared

    @ViewBuilder
    private func lifecycleButtons(_ data: AccountDetailData) -> some View {
        if data.account.isClosed {
            Button("Reopen Account") { reopen() }
                .disabled(!library.canEdit)
        } else {
            Button("Update Value…") { action = AccountAction(.updateValue, accountID) }
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
            if !data.account.isClosed {
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
        do {
            try library.deleteAccount(account.id)
            dismiss()
        } catch {
            show(error)
        }
    }

    private func removeValuation(_ key: ValuationKey) {
        do {
            try library.removeValuation(key)
        } catch {
            show(error)
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
            AmountText(data.value, precision: .cents, tabular: false, animatesChanges: true)
                .font(.largeTitle.bold())
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            if let amount = data.amountInAccountCurrency {
                AmountText(amount, currency: data.account.currency, precision: .cents)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
            }
            if let change = data.change, let from = data.changeFrom {
                HStack(spacing: Metrics.xs) {
                    DeltaText(change.change, precision: .cents)
                    Text("since \(AmountFormat.shortDate(from, locale: locale))")
                        .foregroundStyle(Palette.secondaryInk)
                }
                .font(.subheadline)
                let parts = self.parts(of: change)
                if parts.count > 1 {
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

    private func parts(of change: ValueChange) -> [Part] {
        [Part(name: "Markets", amount: change.market), Part(name: "New money", amount: change.newMoney),
         Part(name: "Other", amount: change.other)].filter { $0.amount != 0 }
    }

    private func partViews(_ parts: [Part]) -> some View {
        ForEach(parts) { part in
            HStack(spacing: 4) {
                Text(part.name)
                    .foregroundStyle(Palette.secondaryInk)
                DeltaText(part.amount, showsArrow: false)
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

/// One position in the iPhone list: name and value, quantity × price and
/// the unrealised gain, and the purchase cost.
private struct AccountPositionListRow: View {
    let row: AccountHoldingRow
    let currency: CurrencyCode
    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                Text(row.name)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                Spacer(minLength: Metrics.s)
                if let amount = row.amount {
                    AmountText(amount, currency: currency, precision: .cents)
                        .foregroundStyle(Palette.ink)
                } else {
                    Text("No price")
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                Text(AccountPositionText.quantityAndPrice(row, hidesAmounts: hidesAmounts, locale: locale))
                    .privacySensitive()
                Spacer(minLength: Metrics.s)
                if let gain = row.gain {
                    DeltaText(gain, currency: currency)
                    if let fraction = row.gainFraction {
                        DeltaText(percent: fraction, showsArrow: false)
                    }
                }
            }
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
            if let cost = row.costBasis {
                HStack {
                    Text("Purchase cost")
                    Spacer()
                    AmountText(cost, currency: currency)
                }
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
            }
        }
        .padding(.vertical, 2)
    }
}

/// How a position's quantity and price read.
enum AccountPositionText {
    /// "412,5 sh × 138,42 EUR".
    static func quantityAndPrice(_ row: AccountHoldingRow, hidesAmounts: Bool, locale: Locale) -> String {
        let quantity = hidesAmounts ? AmountFormat.hidden : AmountFormat.number(row.quantity, locale: locale)
        let unit = row.unit.map { InstrumentForm.shortName(of: $0) } ?? ""
        guard let price = row.price else { return "\(quantity) \(unit)" }
        return "\(quantity) \(unit) × \(AmountFormat.number(price.price, maxDigits: 4, locale: locale)) \(price.currency)"
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
                        Text(hidesAmounts ? AmountFormat.hidden : AmountFormat.number(row.quantity, locale: locale))
                            .monospacedDigit()
                            .privacySensitive()
                        Text(price(of: row))
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

    private func price(of row: AccountHoldingRow) -> String {
        guard let price = row.price else { return "–" }
        return "\(AmountFormat.number(price.price, maxDigits: 4, locale: locale)) \(price.currency)"
    }
}
#endif

// MARK: - Valuations

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
                if let amount = row.amount {
                    AmountText(amount, currency: currency, precision: .cents)
                        .foregroundStyle(Palette.ink)
                } else {
                    AmountText(row.value, precision: .cents)
                        .foregroundStyle(Palette.ink)
                }
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
/// The valuations as a table on the Mac: date, value, new money and note.
/// Double-click (or the context menu) edits one.
private struct AccountValuationsTable: View {
    let rows: [AccountValuationRow]
    let currency: CurrencyCode
    let edit: (ValuationKey) -> Void
    let delete: (ValuationKey) -> Void

    @State private var selection: ValuationKey?

    var body: some View {
        Table(rows, selection: $selection) {
            TableColumn("Date") { (row: AccountValuationRow) in
                Text(AmountFormat.mediumDate(row.valuation.date))
                    .monospacedDigit()
            }
            .width(min: 90, ideal: 110)
            TableColumn("Value") { (row: AccountValuationRow) in
                AccountValuationValueCell(row: row, currency: currency)
            }
            .width(min: 110, ideal: 140)
            TableColumn("New money") { (row: AccountValuationRow) in
                AccountValuationFlowCell(row: row, currency: currency)
            }
            .width(min: 100, ideal: 130)
            TableColumn("Note") { (row: AccountValuationRow) in
                Text(row.valuation.note ?? "")
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
            }
        }
        .contextMenu(forSelectionType: ValuationKey.self) { keys in
            if let key = keys.first {
                Button("Edit Value…") { edit(key) }
                Button("Delete Value…", role: .destructive) { delete(key) }
            }
        } primaryAction: { keys in
            if let key = keys.first { edit(key) }
        }
    }
}

private struct AccountValuationValueCell: View {
    let row: AccountValuationRow
    let currency: CurrencyCode

    var body: some View {
        Group {
            if let amount = row.amount {
                AmountText(amount, currency: currency, precision: .cents)
            } else {
                AmountText(row.value, precision: .cents)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
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

/// Kind, institution, country, currency, tax wrapper, what it counts in,
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
            AccountInfoRow(title: "Tax wrapper", text: wrapperName)
            if let joined = account.tax?.joined {
                AccountInfoRow(title: "Joined", text: AmountFormat.mediumDate(joined, locale: locale))
            }
            AccountInfoRow(title: "Recorded as", text: account.valuationMode == .holdings ? "Positions" : "A balance")
            if let mix = assetMix {
                AccountInfoRow(title: "Asset mix", text: mix)
            }
        }
        Group {
            AccountInfoRow(title: "In net worth", text: account.includedInNetWorth ? "Yes" : "No")
            AccountInfoRow(title: "In plans", text: account.includedInPlan ? "Yes" : "No")
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

    private var wrapperName: String {
        account.wrapper.map { AccountWrapperDefaults.name(of: $0) } ?? "None"
    }

    /// Closed accounts whose money went to this one.
    private var predecessors: [String] {
        library.library.accounts.values.filter { $0.successor == account.id }.map(\.name).sorted()
    }

    /// "60% equity, 40% bonds" for a balance account; "(default)" when it
    /// comes from the kind.
    private var assetMix: String? {
        guard account.valuationMode == .balance, !account.kind.isLiability,
              let mix = account.effectiveAssetClasses, mix.total > 0
        else { return nil }
        let parts = BreakdownKey.assetClassOrder.filter { mix[$0] != 0 }.map { assetClass in
            "\(AmountFormat.percent(mix[assetClass], digits: 0, locale: locale)) "
                + BreakdownKey.assetClass(assetClass).description.lowercased()
        }
        return parts.joined(separator: ", ") + (account.assetClasses == nil ? " (default)" : "")
    }
}

#Preview("Brokerage") {
    NavigationStack {
        AccountDetailScreen(accountID: "directa")
            .appDestinations()
    }
    .previewEnvironment()
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
