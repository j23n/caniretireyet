import Model
import SwiftUI
import Tracker

// The pieces of a trades account's detail (UI.md, "Account detail" for
// trades accounts): the holdings card, the trades list (a Table on the
// Mac), the income and gains by year, and the issue banners. The data is
// in `TradeListData.swift`.

// MARK: - Amounts

/// A signed amount without colour: "−1.025,95 €", "+200,60 €". A trade's
/// cash going down isn't bad news, so it isn't red. Hidden with the eye button.
struct TradeAmountText: View {
    let amount: Decimal
    var currency: CurrencyCode?
    var precision: AmountPrecision = .cents

    @Environment(\.baseCurrency) private var baseCurrency
    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale

    init(_ amount: Decimal, currency: CurrencyCode? = nil, precision: AmountPrecision = .cents) {
        self.amount = amount
        self.currency = currency
        self.precision = precision
    }

    var body: some View {
        let text = hidesAmounts
            ? AmountFormat.hidden
            : AmountFormat.signedAmount(amount, currency: currency ?? baseCurrency, precision: precision, locale: locale)
        Text(verbatim: text)
            .monospacedDigit()
            .privacySensitive()
            .accessibilityLabel(hidesAmounts ? Text("Amount hidden") : Text(verbatim: text))
    }
}

/// A trade type's icon, in the accent colour.
struct TradeTypeIcon: View {
    let type: TradeType

    var body: some View {
        Image(systemName: TradeTypeDisplay.systemImage(type))
            .foregroundStyle(Palette.accent)
            .frame(width: 24)
            .accessibilityHidden(true)
    }
}

// MARK: - Holdings

/// A trades account's holdings in the iPhone list: each position with its
/// quantity × price, average cost, unrealised gain and share, then the
/// cash and the total.
struct TradeHoldingsRows: View {
    let holdings: TradeHoldings
    let currency: CurrencyCode

    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale

    var body: some View {
        if holdings.rows.isEmpty {
            Text("No positions: the trades leave only cash.")
                .foregroundStyle(Palette.secondaryInk)
        }
        ForEach(holdings.rows) { row in
            NavigationLink {
                InstrumentEditor(instrumentID: row.instrument)
            } label: {
                positionRow(row)
            }
        }
        if let cash = holdings.cash {
            HStack {
                Text("Cash")
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: Metrics.s)
                if let share = holdings.cashShare {
                    Text(verbatim: AmountFormat.percent(share, digits: 0, locale: locale))
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
                AmountText(cash, currency: currency, precision: .cents)
                    .foregroundStyle(Palette.ink)
            }
        }
        HStack {
            Text("Total")
                .fontWeight(.semibold)
            Spacer(minLength: Metrics.s)
            AmountText(holdings.total, currency: currency, precision: .cents)
                .fontWeight(.semibold)
        }
        if let gain = holdings.totalGain {
            HStack {
                Text("Unrealised gain")
                    .foregroundStyle(Palette.secondaryInk)
                Spacer(minLength: Metrics.s)
                DeltaText(gain, currency: currency)
                if let fraction = holdings.totalGainFraction {
                    DeltaText(percent: fraction, showsArrow: false)
                }
            }
            .font(.footnote)
        }
    }

    /// "Bitcoin   7.661,78 €" / "0,10383916 BTC × 73.785,11 €   95 % of the
    /// account" / "Average cost 101.437,74 €   ▼ −2.871 € −27,3 %". Lines
    /// that don't fit break between their parts, never inside a label.
    private func positionRow(_ row: AccountHoldingRow) -> some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            AccountPositionNameLine(row: row, currency: currency)
            AccountPositionQuantityLine(row: row) {
                if let share = AccountPositionText.share(row, locale: locale) {
                    Text(verbatim: share)
                        .lineLimit(1)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                    averageCost(row)
                        .lineLimit(1)
                    Spacer(minLength: Metrics.s)
                    gain(row)
                }
                VStack(alignment: .leading, spacing: 2) {
                    averageCost(row)
                    gain(row)
                }
            }
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
        }
        .padding(.vertical, 2)
    }

    /// "Average cost 101.437,74 €", label and value in one text.
    private func averageCost(_ row: AccountHoldingRow) -> some View {
        Text(verbatim: AccountPositionText.averageCost(row, currency: currency, hidesAmounts: hidesAmounts,
                                                       locale: locale))
            .privacySensitive()
    }

    @ViewBuilder
    private func gain(_ row: AccountHoldingRow) -> some View {
        if let gain = row.gain {
            AccountPositionGain(gain: gain, fraction: row.gainFraction, currency: currency)
        }
    }
}

#if os(macOS)
/// A trades account's holdings as a grid on the Mac: instrument, quantity,
/// average cost, price, value, unrealised gain and share; then cash and the total.
struct TradeHoldingsGrid: View {
    let holdings: TradeHoldings
    let currency: CurrencyCode

    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: Metrics.l, verticalSpacing: Metrics.s) {
            GridRow {
                Text("Instrument")
                    .gridColumnAlignment(.leading)
                Text("Quantity")
                Text("Average cost")
                Text("Price")
                Text("Value")
                Text("Unrealised gain")
                Text("Share")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.secondaryInk)
            Divider()
            ForEach(holdings.rows) { row in
                GridRow {
                    Text(row.name)
                        .lineLimit(1)
                    Text(hidesAmounts ? AmountFormat.hidden : QuantityFormat.quantity(row.quantity, locale: locale))
                        .monospacedDigit()
                        .privacySensitive()
                    if let average = row.averageCost {
                        Text(hidesAmounts ? AmountFormat.hidden
                            : QuantityFormat.unitPrice(average, currency: currency, locale: locale))
                            .monospacedDigit()
                            .privacySensitive()
                    } else {
                        Text("–").foregroundStyle(Palette.mutedInk)
                    }
                    Text(price(of: row))
                        .monospacedDigit()
                    if let amount = row.amount {
                        AmountText(amount, currency: currency, precision: .cents)
                    } else {
                        Text("No price").foregroundStyle(Palette.secondaryInk)
                    }
                    gainCell(row)
                    Text(row.share.map { AmountFormat.percent($0, digits: 0, locale: locale) } ?? "–")
                        .monospacedDigit()
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            if let cash = holdings.cash {
                GridRow {
                    Text("Cash")
                    Text("")
                    Text("")
                    Text("")
                    AmountText(cash, currency: currency, precision: .cents)
                    Text("")
                    Text(holdings.cashShare.map { AmountFormat.percent($0, digits: 0, locale: locale) } ?? "–")
                        .monospacedDigit()
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            Divider()
            GridRow {
                Text("Total")
                    .fontWeight(.semibold)
                Text("")
                Text("")
                Text("")
                AmountText(holdings.total, currency: currency, precision: .cents)
                    .fontWeight(.semibold)
                if let gain = holdings.totalGain {
                    DeltaText(gain, currency: currency)
                } else {
                    Text("–").foregroundStyle(Palette.mutedInk)
                }
                Text("")
            }
        }
    }

    @ViewBuilder
    private func gainCell(_ row: AccountHoldingRow) -> some View {
        if let gain = row.gain {
            HStack(spacing: Metrics.xs) {
                DeltaText(gain, currency: currency)
                if let fraction = row.gainFraction {
                    DeltaText(percent: fraction, showsArrow: false)
                        .font(.caption)
                }
            }
        } else {
            Text("–").foregroundStyle(Palette.mutedInk)
        }
    }

    private func price(of row: AccountHoldingRow) -> String {
        guard let price = row.price else { return "–" }
        return QuantityFormat.unitPrice(price.price, currency: price.currency, locale: locale)
    }
}
#endif

// MARK: - Trades list

/// One trade in the iPhone list: its type's icon, what it was ("Buy
/// 0,10383916 BTC") over its price, date and note ("at 101.437,76 € · 1 Oct
/// 2025"), and on the other side the cash it moved, marked "paid from
/// outside" for a trade paid from another account, with a sale's gain. At
/// the largest text sizes the amounts go under the description.
struct TradeListRowView: View {
    let item: TradeListItem
    let currency: CurrencyCode

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            TradeTypeIcon(type: item.type)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Metrics.xs) {
                    description
                    amounts(alignment: .leading)
                }
            } else {
                description
                Spacer(minLength: Metrics.s)
                amounts(alignment: .trailing)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// "Buy 0,10383916 BTC" over "at 101.437,76 € · 1 Oct 2025 · note".
    private var description: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: item.title)
                .foregroundStyle(Palette.ink)
                .privacySensitive()
            Text(verbatim: item.subtitle)
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(3)
        }
    }

    /// The cash it moved, "paid from outside", the gain, "Needs a look".
    private func amounts(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            if let amount = item.amount {
                TradeAmountText(amount, currency: currency)
                    .foregroundStyle(Palette.ink)
            } else {
                Text("Amount unknown")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
            if let label = item.settlementLabel {
                Text(verbatim: label)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
            }
            if let gain = item.realizedGain {
                HStack(spacing: 4) {
                    Text("gain")
                        .foregroundStyle(Palette.secondaryInk)
                    DeltaText(gain, currency: currency, precision: .automatic, showsArrow: false)
                }
                .font(.caption)
            }
            if item.hasIssue {
                Label("Needs a look", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Palette.warning)
            }
        }
        .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
    }
}

/// The trades list's filter: by instrument and by type.
struct TradeFilterMenu: View {
    let list: TradeList
    @Binding var filter: TradeListFilter

    var body: some View {
        Menu {
            Picker("Instrument", selection: $filter.instrument) {
                Text("All instruments").tag(InstrumentID?.none)
                ForEach(list.instruments) { option in
                    Text(verbatim: option.name).tag(Optional(option.value))
                }
            }
            Picker("Type", selection: $filter.type) {
                Text("All types").tag(TradeType?.none)
                ForEach(list.types) { option in
                    Text(verbatim: option.name).tag(Optional(option.value))
                }
            }
            if filter.isActive {
                Button("Show All Trades") { filter = TradeListFilter() }
            }
        } label: {
            Label("Filter", systemImage: filter.isActive
                ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
    }
}

#if os(macOS)
/// The trades as a table on the Mac: date, type, instrument, quantity,
/// price, amount and note. Double-click (or the context menu) edits one.
/// It's as tall as its lines, so the account's page scrolls them with the
/// rest (`PageTable`).
struct TradesTable: View {
    let items: [TradeListItem]
    let currency: CurrencyCode
    let edit: (TradeKey) -> Void
    let delete: (TradeKey) -> Void

    private enum Columns {
        static let date = PageTableColumn(min: 80, max: 110)
        static let type = PageTableColumn(min: 80, max: 140)
        static let instrument = PageTableColumn(min: 50, max: 140)
        static let quantity = PageTableColumn(min: 64, max: 120, alignment: .trailing)
        static let price = PageTableColumn(min: 72, max: 130, alignment: .trailing)
        static let amount = PageTableColumn(min: 84, max: 140, alignment: .trailing)
        static let note = PageTableColumn(min: 0, max: .infinity)
    }

    var body: some View {
        PageTable(items, open: edit) {
            Text("Date").pageTableColumn(Columns.date)
            Text("Type").pageTableColumn(Columns.type)
            Text("Instrument").pageTableColumn(Columns.instrument)
            Text("Quantity").pageTableColumn(Columns.quantity)
            Text("Price").pageTableColumn(Columns.price)
            Text("Amount").pageTableColumn(Columns.amount)
            Text("Note").pageTableColumn(Columns.note)
        } row: { item in
            Text(AmountFormat.mediumDate(item.date))
                .monospacedDigit()
                .pageTableColumn(Columns.date)
            TradeTableTypeCell(item: item)
                .pageTableColumn(Columns.type)
            Text(item.instrumentLabel ?? "")
                .pageTableColumn(Columns.instrument)
            TradeTableQuantityCell(item: item)
                .pageTableColumn(Columns.quantity)
            Text(item.priceText ?? "")
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .pageTableColumn(Columns.price)
            TradeTableAmountCell(item: item, currency: currency)
                .pageTableColumn(Columns.amount)
            Text([item.settlementLabel, item.trade.note].compactMap { $0 }.joined(separator: " · "))
                .foregroundStyle(Palette.secondaryInk)
                .pageTableColumn(Columns.note)
        } menu: { item in
            Button("Edit Trade…") { edit(item.id) }
            Button("Delete Trade…", role: .destructive) { delete(item.id) }
        }
    }
}

private struct TradeTableTypeCell: View {
    let item: TradeListItem

    var body: some View {
        HStack(spacing: Metrics.xs) {
            Image(systemName: TradeTypeDisplay.systemImage(item.type))
                .foregroundStyle(Palette.accent)
            Text(verbatim: TradeTypeDisplay.name(item.type))
            if item.hasIssue {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Palette.warning)
                    .help("Needs a look: see the notes above the list.")
            }
        }
    }
}

/// A trade's quantity (``QuantityFormat``), or a split's ratio; hidden with the eye button.
private struct TradeTableQuantityCell: View {
    let item: TradeListItem

    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if let quantity = item.trade.quantity {
                Text(hidesAmounts ? AmountFormat.hidden : QuantityFormat.quantity(quantity, locale: locale))
                    .monospacedDigit()
                    .privacySensitive()
            } else if let ratio = item.trade.ratio {
                Text(verbatim: "× " + AmountFormat.number(ratio, maxDigits: 6, locale: locale))
                    .monospacedDigit()
            } else {
                Text("")
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct TradeTableAmountCell: View {
    let item: TradeListItem
    let currency: CurrencyCode

    var body: some View {
        Group {
            if let amount = item.amount {
                TradeAmountText(amount, currency: currency)
            } else {
                Text("Unknown")
                    .foregroundStyle(Palette.mutedInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
#endif

// MARK: - Income and gains

/// One year of income and gains: realised gains, dividends, interest, fees
/// and taxes, and the net.
struct TradeIncomeYearView: View {
    let year: TradeIncomeYear
    let currency: CurrencyCode

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            Text(verbatim: String(year.year))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
            ForEach(year.lines) { line in
                HStack {
                    Text(verbatim: line.name)
                        .foregroundStyle(Palette.secondaryInk)
                    Spacer(minLength: Metrics.s)
                    if line.isCharge {
                        TradeAmountText(line.amount, currency: currency)
                    } else {
                        DeltaText(line.amount, currency: currency, precision: .cents, showsArrow: false)
                    }
                }
                .font(.footnote)
            }
            HStack {
                Text("Net")
                    .fontWeight(.semibold)
                Spacer(minLength: Metrics.s)
                DeltaText(year.net, currency: currency, precision: .cents, showsArrow: false)
                    .fontWeight(.semibold)
            }
            .font(.footnote)
            if let note = year.unknownGainNote {
                Text(verbatim: note)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Issues

/// The notes about an account's trades as banners, each with its fix.
struct TradeIssueBanners: View {
    let notes: [TradeIssueNote]
    let perform: (TradeIssueAction) -> Void

    var body: some View {
        VStack(spacing: Metrics.s) {
            ForEach(notes) { note in
                if let action = note.action, let title = note.actionTitle {
                    StatusBanner(note.isError ? .warning : .info, note.title, message: note.message,
                                 actionTitle: title) { perform(action) }
                } else {
                    StatusBanner(note.isError ? .warning : .info, note.title, message: note.message)
                }
            }
        }
    }
}

/// The trades pieces of Directa in the preview library, in a list.
private struct TradesPiecesPreview: View {
    @Environment(\.locale) private var locale

    var body: some View {
        let library = PreviewLibrary.library
        let valuator = PreviewLibrary.valuator
        let list = TradeList(account: "directa", library: library, valuator: valuator, locale: locale)
        let data = AccountDetailData(account: library.accounts["directa"]!, library: library, valuator: valuator,
                                     today: PreviewLibrary.latestCheckIn, stalenessThreshold: 45)
        List {
            Section("Holdings") {
                if let holdings = data.tradeHoldings {
                    TradeHoldingsRows(holdings: holdings, currency: "EUR")
                }
            }
            Section("Trades") {
                ForEach(list.items.prefix(5)) { item in
                    TradeListRowView(item: item, currency: "EUR")
                }
            }
            Section("Income & gains") {
                ForEach(data.incomeYears) { year in
                    TradeIncomeYearView(year: year, currency: "EUR")
                }
            }
        }
    }
}

#Preview("Trades pieces") {
    TradesPiecesPreview()
        .previewEnvironment()
}

#Preview("Trades pieces, large text") {
    TradesPiecesPreview()
        .dynamicTypeSize(.accessibility2)
        .previewEnvironment()
}

#Preview("Trades pieces, German") {
    TradesPiecesPreview()
        .environment(\.locale, Locale(identifier: "de_DE"))
        .previewEnvironment()
}
