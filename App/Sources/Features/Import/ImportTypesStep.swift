import Foundation
import Importer
import Model
import SwiftUI

/// Step 4 of a broker's transactions (the trades layout), Types: each word
/// the file uses for a transaction ("Acquisto", "Dividend") and the trade
/// type its rows become, and how the file signs its amounts. Words the
/// importer doesn't know are left out until they're mapped.
struct ImportTypesStep: View {
    let model: ImportController

    var body: some View {
        let flow = model.flow
        let rows = flow.typeRows
        Form {
            Section {
                if !flow.hasTypeColumn {
                    Text("The file has no column of types: each row with a positive quantity is a buy, and one with "
                        + "a negative quantity a sell. If a column holds the types, choose “Trade type” for it in "
                        + "Columns.")
                        .foregroundStyle(Palette.secondaryInk)
                }
                ForEach(rows) { row in
                    ImportTypeRowView(model: model, row: row)
                }
            } header: {
                Text("Types in the file")
            } footer: {
                Text("Each word the file uses for a transaction becomes a trade type. Words the importer doesn't know "
                    + "are left out until you choose one: nothing is guessed. Choices are remembered in the profile, "
                    + "if you save one.")
            }

            Section {
                Picker("Amounts", selection: Binding(get: { model.flow.amountSign },
                                                     set: { model.flow.setAmountSign($0) })) {
                    ForEach(TradeAmountSign.knownValues, id: \.self) { sign in
                        Text(ImportFlow.amountSignName(sign)).tag(sign)
                    }
                }
                .pickerStyle(.menu)
                ForEach(flow.tradeSignNotes, id: \.self) { note in
                    Label(note, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
            } header: {
                Text("Signs")
            } footer: {
                Text("Quantities, fees and taxes are made positive: the type says the direction. An amount is the "
                    + "cash a trade moved, negative for buys, fees, taxes and withdrawals. Automatic keeps the signs "
                    + "of a column that writes any, and otherwise takes each one from its type.")
            }
        }
        .formStyle(.grouped)
    }
}

/// A type word of the file and the trade type its rows become.
private struct ImportTypeRowView: View {
    let model: ImportController
    let row: TradeTypeValue

    var body: some View {
        LabeledContent {
            Picker(row.value, selection: Binding(get: { row.type }, set: { type in
                model.flow.setTradeType(type, for: row.value)
            })) {
                if row.type == nil {
                    Text(ImportFlow.typeChoiceName(nil)).tag(TradeType?.none)
                }
                ForEach(ImportFlow.typeChoices, id: \.self) { type in
                    Text(ImportFlow.typeChoiceName(type)).tag(TradeType?.some(type))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label("“\(row.value)”", systemImage: row.type == nil ? "exclamationmark.triangle.fill"
                    : "arrow.right.circle")
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(row.type == nil ? Palette.warning : Palette.secondaryInk)
                if row.canReset, let suggestion = row.suggestion {
                    Button("Use \(TradeTypeDisplay.name(suggestion)), the usual meaning") {
                        model.flow.setTradeType(nil, for: row.value)
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    /// E.g. "3 rows · The usual word".
    private var detail: String {
        (row.count == 1 ? "1 row" : "\(row.count) rows") + " · " + row.sourceTitle
    }
}

#Preview("Types") {
    NavigationStack {
        ImportPreviewHost(step: .types, file: .trades)
    }
    .previewEnvironment()
}
