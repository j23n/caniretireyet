import Foundation
import Importer
import Model
import SwiftUI

/// Step 2, Format: how the file is read and how its values are written,
/// each a picker with a live sample, and the guesses to confirm.
struct ImportFormatStep: View {
    let model: ImportController

    @State private var footerRule = ""
    @State private var customPattern = ""

    var body: some View {
        let flow = model.flow
        Form {
            if let problem = flow.problem {
                Section {
                    StatusBanner(.error, "That setting doesn't work for this file", message: problem)
                }
            }
            if !flow.ambiguities.isEmpty {
                Section {
                    ForEach(Array(flow.ambiguities.enumerated()), id: \.offset) { _, ambiguity in
                        ImportAmbiguityRow(model: model, ambiguity: ambiguity)
                    }
                } header: {
                    Text("To confirm")
                } footer: {
                    Text("The file could be read more than one way. Until you choose, the first reading is used.")
                }
            }
            fileSection(flow)
            numbersSection(flow)
            datesSection(flow)
            emptyCellsSection(flow)
        }
        .formStyle(.grouped)
        .onAppear {
            footerRule = flow.excludedRows.joined(separator: ", ")
        }
    }

    // MARK: Reading the file

    private func fileSection(_ flow: ImportFlow) -> some View {
        Section {
            Picker("Encoding", selection: Binding(get: { model.flow.encoding },
                                                  set: { model.flow.setEncoding($0) })) {
                Text("Detected: \(flow.encodingInUse.map(ImportChoices.encodingName) ?? "—")")
                    .tag(TextEncodingName?.none)
                ForEach(ImportChoices.encodings, id: \.self) { encoding in
                    Text(ImportChoices.encodingName(encoding)).tag(TextEncodingName?.some(encoding))
                }
            }
            Picker("Delimiter", selection: Binding(get: { model.flow.delimiter },
                                                   set: { model.flow.setDelimiter($0) })) {
                Text("Detected: \(flow.delimiterInUse.map(ImportChoices.delimiterName) ?? "—")")
                    .tag(String?.none)
                ForEach(ImportChoices.delimiters, id: \.self) { delimiter in
                    Text(ImportChoices.delimiterName(delimiter)).tag(String?.some(delimiter))
                }
            }
            Picker("Header row", selection: Binding(get: { model.flow.headerRow },
                                                    set: { model.flow.setHeaderRow($0) })) {
                Text("Detected: \(Self.headerRowName(flow.headerRowInUse))").tag(Int?.none)
                Text("None").tag(Int?.some(0))
                ForEach(flow.headerRowChoices, id: \.self) { row in
                    Text("Row \(row)").tag(Int?.some(row))
                }
            }
            ImportSampleCells(title: flow.headerRowInUse == 0 ? "First row" : "Headers", cells: flow.headerSample)
            ImportSampleCells(title: "First values", cells: flow.firstRowSample)
            TextField("Leave out rows starting with", text: $footerRule)
                .autocorrectionDisabled()
                .onSubmit {
                    model.flow.setExcludedRows(footerRule)
                    footerRule = model.flow.excludedRows.joined(separator: ", ")
                }
        } header: {
            Text("Reading the file")
        } footer: {
            Text("\(flow.tableSummary). Letters such as à or € that look wrong mean another encoding. Rows starting "
                + "with the words above (e.g. totals) are left out; separate them with commas and press Return. "
                + "Leave it empty to keep every row.")
        }
    }

    private static func headerRowName(_ row: Int?) -> String {
        guard let row else { return "—" }
        return row == 0 ? "none" : "row \(row)"
    }

    // MARK: Numbers

    private func numbersSection(_ flow: ImportFlow) -> some View {
        Section {
            Picker("Decimal separator", selection: Binding(get: { model.flow.decimal },
                                                           set: { model.flow.setDecimal($0) })) {
                Text("Detected per column (mostly \(flow.detectedDecimal))").tag(String?.none)
                ForEach(ImportChoices.decimals, id: \.self) { separator in
                    Text(ImportChoices.decimalName(separator)).tag(String?.some(separator))
                }
            }
            Picker("Thousands separator", selection: Binding(get: { model.flow.thousands },
                                                             set: { model.flow.setThousands($0) })) {
                Text("Detected per column").tag(String?.none)
                ForEach(ImportChoices.thousands, id: \.self) { separator in
                    Text(ImportChoices.thousandsName(separator)).tag(String?.some(separator))
                }
            }
            ImportSampleList(samples: flow.numberSamples(), emptyText: "No column is imported as amounts yet.")
        } header: {
            Text("Numbers")
        } footer: {
            Text("Currency signs and codes (€, EUR, $) are ignored. Negatives can be written −1, (1) or 1−. "
                + "A column can have its own separators in Columns.")
        }
    }

    // MARK: Dates

    private func datesSection(_ flow: ImportFlow) -> some View {
        Section {
            Picker("Date format", selection: Binding(get: { model.flow.datePattern },
                                                     set: { model.flow.setDatePattern($0) })) {
                Text("Detected: \(flow.detectedDatePattern ?? "none")").tag(String?.none)
                ForEach(Self.patternChoices(flow), id: \.self) { pattern in
                    Text(ImportChoices.datePatternTitle(pattern)).tag(String?.some(pattern))
                }
            }
            HStack {
                TextField("Other pattern, e.g. d.M.yy", text: $customPattern)
                    .autocorrectionDisabled()
                    .onSubmit { useCustomPattern() }
                Button("Use") { useCustomPattern() }
                    .disabled(customPattern.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Picker("Month-only dates", selection: Binding(get: { model.flow.monthOnly },
                                                          set: { model.flow.setMonthOnly($0) })) {
                ForEach(MonthOnlyDate.knownValues, id: \.self) { value in
                    Text(ImportChoices.monthOnlyName(value)).tag(value)
                }
            }
            ImportSampleList(samples: flow.dateSamples(), emptyText: "No column holds the dates yet.")
        } header: {
            Text("Dates")
        } footer: {
            Text("In a pattern, d is the day, M the month (MMM its name, in English or Italian) and y the year. "
                + "Month-only dates such as 01/2026 land on the day you choose.")
        }
    }

    /// The patterns offered: the detected ones, and the one in use if it's another.
    private static func patternChoices(_ flow: ImportFlow) -> [String] {
        let patterns = ImportChoices.datePatterns
        guard let chosen = flow.datePattern, !patterns.contains(chosen) else { return patterns }
        return [chosen] + patterns
    }

    private func useCustomPattern() {
        let pattern = customPattern.trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty else { return }
        model.flow.setDatePattern(pattern)
        customPattern = ""
    }

    // MARK: Empty cells

    private func emptyCellsSection(_ flow: ImportFlow) -> some View {
        Section {
            Picker("Empty cells", selection: Binding(get: { model.flow.emptyCells },
                                                     set: { model.flow.setEmptyCells($0) })) {
                ForEach(EmptyCellPolicy.knownValues, id: \.self) { policy in
                    Text(ImportChoices.emptyCellsName(policy)).tag(policy)
                }
            }
        } header: {
            Text("Empty cells")
        } footer: {
            Text(Self.emptyCellsText(count: flow.emptyValueCells, policy: flow.emptyCells, layout: flow.layout))
        }
    }

    /// What the empty cells in the columns of numbers become. In a trades
    /// file a row is one trade, which an empty cell never leaves out: the
    /// trade has no such value, and read as zero only an amount is 0, since
    /// zero is no quantity, price, fee, tax or ratio (IMPORT.md, "Empty cells").
    private static func emptyCellsText(count: Int, policy: EmptyCellPolicy, layout: ImportLayout) -> String {
        let cells = count == 1 ? "1 empty cell" : "\(count) empty cells"
        if count == 0 { return "The columns of numbers have no empty cells." }
        if layout == .trades {
            return policy == .zero
                ? "\(cells) in the columns of numbers will be read as 0 in Amount (net) and Gross amount, and "
                    + "skipped in the others, as 0 is no quantity, price, fee, tax or ratio. Each row is still a trade."
                : "\(cells) in the columns of numbers will be skipped: each row is still a trade, recorded without "
                    + "that value."
        }
        return policy == .zero
            ? "\(cells) in the columns of numbers will be recorded as 0."
            : "\(cells) in the columns of numbers will be skipped: nothing is recorded for that date."
    }
}

/// A guess to confirm: what's unclear, and a button per reading.
struct ImportAmbiguityRow: View {
    let model: ImportController
    let ambiguity: ImportAmbiguity

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Label {
                Text(ambiguity.description)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(Palette.warning)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Metrics.s) { options }
                VStack(alignment: .leading, spacing: Metrics.s) { options }
            }
        }
        .padding(.vertical, Metrics.xs)
    }

    @ViewBuilder
    private var options: some View {
        let titles = ImportFlow.optionTitles(of: ambiguity)
        ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
            Button(index == 0 ? "\(title) (in use)" : title) {
                model.flow.choose(index, for: ambiguity)
            }
            .buttonStyle(.bordered)
        }
    }
}

/// A row of cells as read, e.g. the headers.
struct ImportSampleCells: View {
    let title: String
    let cells: [String]

    var body: some View {
        LabeledContent(title) {
            Text(cells.prefix(8).map { $0.isEmpty ? "·" : $0 }.joined(separator: "  │  "))
                .font(.callout.monospaced())
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Values from the file and how they read now; problems in red with an icon.
struct ImportSampleList: View {
    let samples: [ImportSample]
    let emptyText: String

    var body: some View {
        if samples.isEmpty {
            Text(emptyText)
                .font(.callout)
                .foregroundStyle(Palette.secondaryInk)
        } else {
            ForEach(samples) { sample in
                HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                    Text(sample.raw)
                        .font(.callout.monospaced())
                        .foregroundStyle(Palette.secondaryInk)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(Palette.mutedInk)
                        .accessibilityHidden(true)
                    if sample.isProblem {
                        Label(sample.reading, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Palette.critical)
                    } else {
                        Text(sample.reading)
                            .foregroundStyle(Palette.ink)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 0)
                }
                .font(.callout)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

#Preview("Format") {
    NavigationStack {
        ImportPreviewHost(step: .format)
    }
    .previewEnvironment()
}
