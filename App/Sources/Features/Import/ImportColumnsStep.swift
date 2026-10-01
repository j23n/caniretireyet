import Foundation
import Importer
import Model
import SwiftUI

/// Step 3, Columns: the layout (a row per date or per record), the date
/// column, and a table of every column: its header, sample values, what it
/// imports as, what it belongs to, and its own format. A list of the same
/// on iPhone.
struct ImportColumnsStep: View {
    let model: ImportController
    let isCompact: Bool

    var body: some View {
        if isCompact {
            compactList
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // At most half the page, scrolling beyond: with many issues
                // the settings would otherwise push the table out, and make
                // the Mac window taller than the screen.
                OverflowScrollView(maxShare: 0.5) {
                    ImportColumnsSettings(model: model)
                        .padding(Metrics.l)
                }
                .layoutPriority(1)
                Divider()
                ImportColumnsTable(model: model)
            }
        }
    }

    /// iPhone: the settings, then a section per column.
    private var compactList: some View {
        let flow = model.flow
        return Form {
            Section {
                ImportLayoutPicker(model: model)
                ImportDateColumnPicker(model: model)
                if flow.layout.rowIsRecord {
                    ImportConstantsPickers(model: model)
                }
            } header: {
                Text("Layout")
            } footer: {
                Text(Self.layoutFooter(flow.layout))
            }
            let issues = flow.mappingIssues
            if !issues.isEmpty {
                Section {
                    ForEach(issues, id: \.self) { issue in
                        Label(issue, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Palette.warning)
                    }
                }
            }
            ForEach(flow.columnRows) { row in
                Section {
                    LabeledContent("Imports as") {
                        ImportUsePicker(model: model, row: row)
                    }
                    if row.isValue && !flow.layout.rowIsRecord {
                        LabeledContent("Of") {
                            ImportTargetMenu(model: model, row: row)
                        }
                    }
                    if row.isValue || row.use == .date {
                        LabeledContent("Format") {
                            ImportFormatMenu(model: model, row: row)
                        }
                    }
                    ForEach(row.problems, id: \.self) { problem in
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(Palette.warning)
                    }
                } header: {
                    ImportColumnTitle(row: row)
                } footer: {
                    Text(row.samples.prefix(3).joined(separator: " · "))
                }
            }
        }
        .formStyle(.grouped)
    }

    static func layoutFooter(_ layout: ImportLayout) -> String {
        switch layout {
        case .long: "Each row is one record, with its date, account or instrument, and value in columns."
        case .trades:
            "Each row is one trade from a broker's export: its date, type, instrument, quantity, price and amounts "
                + "in columns. The next step maps the file's words to trade types."
        default: "Each row is a date; each column an account, holding, price or rate, named by its header."
        }
    }
}

/// The Mac and iPad table of columns.
private struct ImportColumnsTable: View {
    let model: ImportController

    var body: some View {
        Table(model.flow.columnRows) {
            TableColumn("Column") { row in
                ImportColumnTitle(row: row)
            }
            .width(min: 110, ideal: 160)
            TableColumn("Samples") { row in
                Text(row.samples.prefix(3).joined(separator: " · "))
                    .font(.callout.monospaced())
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .help(row.samples.joined(separator: "\n"))
            }
            .width(min: 120, ideal: 220)
            TableColumn("Imports as") { row in
                ImportUsePicker(model: model, row: row)
            }
            .width(min: 140, ideal: 160)
            TableColumn("Of") { row in
                ImportTargetMenu(model: model, row: row)
            }
            .width(min: 140, ideal: 220)
            TableColumn("Format") { row in
                ImportFormatMenu(model: model, row: row)
            }
            .width(min: 110, ideal: 150)
        }
    }
}

/// The layout, the date column, the constants of a long file, and problems
/// with the mapping as a whole, above the table.
private struct ImportColumnsSettings: View {
    let model: ImportController

    var body: some View {
        let flow = model.flow
        VStack(alignment: .leading, spacing: Metrics.m) {
            HStack(spacing: Metrics.xl) {
                ImportLayoutPicker(model: model)
                    .fixedSize()
                ImportDateColumnPicker(model: model)
                    .fixedSize()
                Spacer(minLength: 0)
            }
            Text(ImportColumnsStep.layoutFooter(flow.layout))
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
            if flow.layout.rowIsRecord {
                HStack(spacing: Metrics.xl) {
                    ImportConstantsPickers(model: model)
                        .fixedSize()
                    Spacer(minLength: 0)
                }
            }
            ForEach(flow.mappingIssues, id: \.self) { issue in
                StatusBanner(.warning, issue)
            }
            if flow.unknownColumnCount > 0 {
                StatusBanner(.info, flow.unknownColumnCount == 1
                                 ? "A column isn't in the profile"
                                 : "\(flow.unknownColumnCount) columns aren't in the profile",
                             message: "They aren't imported until you say what they hold.")
            }
        }
    }
}

/// Wide (a row per date) or long (a row per record).
private struct ImportLayoutPicker: View {
    let model: ImportController

    var body: some View {
        Picker("Layout", selection: Binding(get: { model.flow.layout }, set: { model.flow.setLayout($0) })) {
            Text(ImportChoices.layoutName(.wide)).tag(ImportLayout.wide)
            Text(ImportChoices.layoutName(.long)).tag(ImportLayout.long)
            Text(ImportChoices.layoutName(.trades)).tag(ImportLayout.trades)
        }
        .pickerStyle(.segmented)
    }
}

/// The column holding the dates.
private struct ImportDateColumnPicker: View {
    let model: ImportController

    var body: some View {
        let flow = model.flow
        Picker("Date column", selection: Binding(get: { model.flow.dateColumn }, set: { column in
            if let column {
                model.flow.setDateColumn(column)
            } else if let current = model.flow.dateColumn {
                model.flow.setUse(.ignore, forColumn: current)
            }
        })) {
            Text("None").tag(Int?.none)
            ForEach(flow.columnRows) { row in
                Text(row.title).tag(Int?.some(row.column))
            }
        }
        .pickerStyle(.menu)
    }
}

/// Long layout: the account, instrument and currency of every row, when
/// the file has no column for them. Trades layout: the account.
private struct ImportConstantsPickers: View {
    let model: ImportController

    var body: some View {
        let flow = model.flow
        Picker("Account of every row", selection: Binding(get: { model.flow.constants.account }, set: { account in
            model.flow.setConstants { $0.account = account }
        })) {
            Text("From a column").tag(AccountID?.none)
            ForEach(flow.accountChoices) { account in
                Text(account.name).tag(AccountID?.some(account.id))
            }
        }
        .pickerStyle(.menu)
        if flow.layout != .trades {
            Picker("Instrument of every row", selection: Binding(get: { model.flow.constants.instrument },
                                                                 set: { instrument in
                model.flow.setConstants { $0.instrument = instrument }
            })) {
                Text("From a column").tag(InstrumentID?.none)
                ForEach(flow.instrumentChoices) { instrument in
                    Text(instrument.name).tag(InstrumentID?.some(instrument.id))
                }
            }
            .pickerStyle(.menu)
            Picker("Currency", selection: Binding(get: { model.flow.constants.currency }, set: { currency in
                model.flow.setConstants { $0.currency = currency }
            })) {
                Text("From the file").tag(CurrencyCode?.none)
                ForEach(CurrencyChoices.common, id: \.self) { code in
                    Text(code.rawValue).tag(CurrencyCode?.some(code))
                }
            }
            .pickerStyle(.menu)
        }
    }
}

/// A column's header, flagged when a profile doesn't know it or it has a problem.
struct ImportColumnTitle: View {
    let row: ImportColumnRow

    var body: some View {
        HStack(spacing: Metrics.xs) {
            if !row.problems.isEmpty || row.isUnknown {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.warning)
                    .accessibilityLabel(row.isUnknown ? "Not in the profile" : "Problem")
            }
            Text(row.title)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .help(helpText)
    }

    private var helpText: String {
        var lines = row.problems
        if row.isUnknown { lines.insert("Not in the profile: it isn't imported until you say what it holds.", at: 0) }
        return lines.joined(separator: "\n")
    }
}

/// "Imports as": the date, a balance, quantity, cost, cash, price or FX
/// rate (of what the column names), a field of a long file, or ignore.
struct ImportUsePicker: View {
    let model: ImportController
    let row: ImportColumnRow

    var body: some View {
        let layout = model.flow.layout
        Picker("Imports as", selection: Binding(get: { row.use }, set: { use in
            model.flow.setUse(use, forColumn: row.column)
        })) {
            ForEach(ColumnUse.options(for: layout), id: \.self) { use in
                Text(use.title(in: layout)).tag(use)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }
}

/// What a wide value column belongs to: its account and instrument, or the
/// pair of an FX column. Left empty, the header says.
struct ImportTargetMenu: View {
    let model: ImportController
    let row: ImportColumnRow

    var body: some View {
        let flow = model.flow
        if let target = row.target, !flow.layout.rowIsRecord {
            Menu {
                if target.needsAccount {
                    Picker("Account", selection: Binding(get: { row.account }, set: { account in
                        model.flow.setAccount(account, forColumn: row.column)
                    })) {
                        Text(headerChoice).tag(AccountID?.none)
                        ForEach(flow.accountChoices) { account in
                            Text(account.name).tag(AccountID?.some(account.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
                if target.needsInstrument {
                    Picker("Instrument", selection: Binding(get: { row.instrument }, set: { instrument in
                        model.flow.setInstrument(instrument, forColumn: row.column)
                    })) {
                        Text(headerChoice).tag(InstrumentID?.none)
                        ForEach(flow.instrumentChoices) { instrument in
                            Text(instrument.name).tag(InstrumentID?.some(instrument.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
                if target == .fx {
                    Picker("Base currency", selection: Binding(get: { row.base }, set: { base in
                        model.flow.setPair(base: base, quote: row.quote, forColumn: row.column)
                    })) {
                        Text(headerChoice).tag(CurrencyCode?.none)
                        ForEach(CurrencyChoices.common, id: \.self) { code in
                            Text(code.rawValue).tag(CurrencyCode?.some(code))
                        }
                    }
                    .pickerStyle(.menu)
                    Picker("Quote currency", selection: Binding(get: { row.quote }, set: { quote in
                        model.flow.setPair(base: row.base, quote: quote, forColumn: row.column)
                    })) {
                        Text(headerChoice).tag(CurrencyCode?.none)
                        ForEach(CurrencyChoices.common, id: \.self) { code in
                            Text(code.rawValue).tag(CurrencyCode?.some(code))
                        }
                    }
                    .pickerStyle(.menu)
                }
            } label: {
                Text(flow.targetSummary(of: row) ?? "—")
                    .lineLimit(1)
            }
            .help("Left as “from the header”, the column's header names it.")
        } else {
            Text(flow.layout.rowIsRecord && row.isValue ? "Per row" : "—")
                .foregroundStyle(Palette.mutedInk)
        }
    }

    private var headerChoice: String {
        if let header = row.header { return "From the header, “\(header)”" }
        return "From the header"
    }
}

/// A value column's own format: separators, percentages, empty cells and
/// the sign of debts. Left as the file's, the Format step's settings apply.
struct ImportFormatMenu: View {
    let model: ImportController
    let row: ImportColumnRow

    var body: some View {
        switch row.use {
        case _ where row.isValue:
            Menu {
                Picker("Decimal separator", selection: decimal) {
                    Text("The file's").tag(String?.none)
                    ForEach(ImportChoices.decimals, id: \.self) { separator in
                        Text(ImportChoices.decimalName(separator)).tag(String?.some(separator))
                    }
                }
                .pickerStyle(.menu)
                Picker("Thousands separator", selection: thousands) {
                    Text("The file's").tag(String?.none)
                    ForEach(ImportChoices.thousands, id: \.self) { separator in
                        Text(ImportChoices.thousandsName(separator)).tag(String?.some(separator))
                    }
                }
                .pickerStyle(.menu)
                Toggle("Percentages", isOn: percent)
                Picker("Empty cells", selection: empty) {
                    Text("The file's").tag(EmptyCellPolicy?.none)
                    ForEach(EmptyCellPolicy.knownValues, id: \.self) { policy in
                        Text(ImportChoices.emptyCellsName(policy)).tag(EmptyCellPolicy?.some(policy))
                    }
                }
                .pickerStyle(.menu)
                if row.target == .balance {
                    Picker("Debt balances", selection: liabilitySign) {
                        Text("The file's").tag(LiabilitySign?.none)
                        ForEach(LiabilitySign.knownValues, id: \.self) { sign in
                            Text(ImportChoices.liabilitySignName(sign)).tag(LiabilitySign?.some(sign))
                        }
                    }
                    .pickerStyle(.menu)
                }
                if row.use == .field(.amount) || row.use == .field(.gross) {
                    Picker("Amount signs", selection: amountSign) {
                        Text("The file's").tag(TradeAmountSign?.none)
                        ForEach(TradeAmountSign.knownValues, id: \.self) { sign in
                            Text(ImportFlow.amountSignName(sign)).tag(TradeAmountSign?.some(sign))
                        }
                    }
                    .pickerStyle(.menu)
                }
                Divider()
                Button("Use the File's Formats") {
                    model.flow.setFormat(ofColumn: row.column) { $0 = ImportFormat() }
                }
                .disabled(!row.hasOwnFormat)
            } label: {
                Text(row.hasOwnFormat ? "\(row.formatSummary) (own)" : row.formatSummary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        case .date:
            Text(row.formatSummary)
                .foregroundStyle(Palette.secondaryInk)
                .help("Set the date format in the Format step.")
        default:
            Text("—")
                .foregroundStyle(Palette.mutedInk)
        }
    }

    private var decimal: Binding<String?> {
        Binding(get: { row.format.number?.decimal }, set: { value in
            model.flow.setFormat(ofColumn: row.column) { format in
                var number = format.number ?? ImportNumberFormat()
                number.decimal = value
                if let value, number.thousands == value { number.thousands = value == "," ? "." : "," }
                format.number = number
            }
        })
    }

    private var thousands: Binding<String?> {
        Binding(get: { row.format.number?.thousands }, set: { value in
            model.flow.setFormat(ofColumn: row.column) { format in
                var number = format.number ?? ImportNumberFormat()
                number.thousands = value
                format.number = number
            }
        })
    }

    private var percent: Binding<Bool> {
        Binding(get: { row.format.number?.percent == true }, set: { value in
            model.flow.setFormat(ofColumn: row.column) { format in
                var number = format.number ?? ImportNumberFormat()
                number.percent = value ? true : nil
                format.number = number
            }
        })
    }

    private var empty: Binding<EmptyCellPolicy?> {
        Binding(get: { row.format.empty }, set: { value in
            model.flow.setFormat(ofColumn: row.column) { $0.empty = value }
        })
    }

    private var liabilitySign: Binding<LiabilitySign?> {
        Binding(get: { row.format.liabilitySign }, set: { value in
            model.flow.setFormat(ofColumn: row.column) { $0.liabilitySign = value }
        })
    }

    private var amountSign: Binding<TradeAmountSign?> {
        Binding(get: { row.format.amountSign }, set: { value in
            model.flow.setFormat(ofColumn: row.column) { $0.amountSign = value }
        })
    }
}

#Preview("Columns") {
    NavigationStack {
        ImportPreviewHost(step: .columns)
    }
    .previewEnvironment()
}
