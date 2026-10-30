import Foundation
import Importer
import Model
import SwiftUI

/// *How It's Read* (UI.md, "Import"): how one bank statement is read, for
/// a bank the app doesn't know or a file it read wrongly. Its dates,
/// numbers and what splits its columns, each a picker shown by an
/// example; the file's first rows with a menu over each column saying
/// what it holds; and a line saying what was read. The rest of the format
/// (encoding, header row, rows left out, month-only dates, empty cells) is
/// behind *More Options…*. It edits the import as you go: *Cancel* puts it
/// back as it was when the sheet opened, *Use* keeps it.
///
/// On iPhone it says what it recognized ("6 columns recognized", what they
/// are and how dates and numbers read) over the first three lines as read;
/// the pickers and the columns show after *Change…*, or at once when the
/// reading needs work (`ImportFlow.readingNeedsChanges(today:)`).
struct ImportReadingSheet: View {
    let model: ImportController
    @Environment(\.pageLayout) private var layout
    private var isCompact: Bool { !layout.isWide }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(LibraryStore.self) private var library
    /// The import as the sheet opened it, for *Cancel*.
    @State private var saved: ImportFlow?
    @State private var showsMoreOptions = false
    /// iPhone: whether the pickers and columns show, after *Change…*.
    @State private var changes = false

    var body: some View {
        Group {
            if isCompact {
                compact
            } else {
                regular
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            if saved == nil { saved = model.flow }
        }
        .sheet(isPresented: $showsMoreOptions) {
            NavigationStack {
                ImportFormatStep(model: model)
                    .sheetTitle("More Options") { showsMoreOptions = false }
            }
            #if os(macOS)
            .frame(minWidth: 640, idealWidth: 720, minHeight: 600, idealHeight: 700)
            #endif
        }
    }

    /// Puts the import back as it was when the sheet opened, then closes.
    /// The library may have changed meanwhile: the import follows it again.
    private func cancel() {
        if let saved {
            model.flow = saved
            model.libraryChanged(library.library)
        }
        dismiss()
    }

    // MARK: Mac and iPad

    private var regular: some View {
        let flow = model.flow
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Metrics.xs) {
                Text(flow.readingTitle)
                    .font(.title3.bold())
                    .privacySensitiveInFeedback()
                Text(flow.readingSubtitle)
                    .foregroundStyle(Palette.secondaryInk)
                    .privacySensitiveInFeedback(flow.shownFileBank != nil)
            }
            .padding(.horizontal, Metrics.xl)
            .padding(.top, 22)
            .padding(.bottom, 14)

            HStack(spacing: 18) {
                ImportReadingFormatPickers(model: model)
                Spacer(minLength: Metrics.s)
                Button("More Options…") {
                    showsMoreOptions = true
                }
            }
            .padding(.horizontal, Metrics.xl)
            .padding(.bottom, 14)

            if let problem = flow.problem {
                StatusBanner(.error, "That setting doesn't work for this file", message: problem, personal: .message)
                    .padding(.horizontal, Metrics.xl)
                    .padding(.bottom, Metrics.s)
            }

            ImportReadingGrid(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 0.5)
                }
                .padding(.horizontal, Metrics.xl)

            ImportReadingStatusLine(status: flow.readingStatus())
                .padding(.horizontal, Metrics.xl)
                .padding(.vertical, Metrics.m)

            Divider()
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Use") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .frame(height: 56)
        }
        .background(Palette.card)
        #if os(macOS)
        .frame(minWidth: 900, idealWidth: 1000, minHeight: 640, idealHeight: 760)
        #else
        .presentationSizing(.page)
        #endif
    }

    // MARK: iPhone

    private var compact: some View {
        let flow = model.flow
        let needsChanges = flow.readingNeedsChanges()
        return NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: Metrics.xs) {
                        Label(flow.recognizedTitle, systemImage: needsChanges ? "exclamationmark.triangle.fill"
                            : "checkmark.circle.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(needsChanges ? Palette.warning : Palette.positive)
                        Text(flow.recognizedSummary)
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !changes {
                        Button("Change…") { changes = true }
                    }
                } header: {
                    Text("How is it read?")
                }
                if changes {
                    changeSections(flow)
                }
                if !flow.statementLines.isEmpty {
                    Section("Read as") {
                        ForEach(flow.statementLines.prefix(3)) { line in
                            readLine(line)
                        }
                    }
                }
                Section {
                    ImportReadingStatusLine(status: flow.readingStatus())
                }
            }
            .formStyle(.grouped)
            // Opened because the reading needs work, the menus stay open once it works.
            .onChange(of: needsChanges, initial: true) { _, needs in
                if needs { changes = true }
            }
            .personalNavigationTitle(flow.readingTitle, hidden: "How It's Read")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") {
                        dismiss()
                    }
                }
            }
        }
    }

    /// "1 Oct · Rossi Immobiliare   −950,00": a line as it's read.
    private func readLine(_ line: StatementLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Text(verbatim: "\(AmountFormat.shortDate(line.date, locale: locale)) · \(line.text)")
                .lineLimit(1)
                .privacySensitiveInFeedback()
            Spacer(minLength: Metrics.s)
            AmountText(line.amount, currency: model.flow.statementAccount?.currency, precision: .cents,
                       signed: true)
        }
    }

    /// iPhone, after *Change…* or when the reading needs work: the
    /// pickers, *More Options…* and what each column holds.
    @ViewBuilder
    private func changeSections(_ flow: ImportFlow) -> some View {
        Section {
            Text(flow.readingSubtitle)
                .foregroundStyle(Palette.secondaryInk)
                .privacySensitiveInFeedback(flow.shownFileBank != nil)
            ImportReadingFormatPickers(model: model)
            Button("More Options…") {
                showsMoreOptions = true
            }
        }
        if let problem = flow.problem {
            Section {
                StatusBanner(.error, "That setting doesn't work for this file", message: problem,
                             personal: .message)
            }
        }
        Section("Columns") {
            ForEach(flow.columnRows) { row in
                LabeledContent {
                    ImportColumnUseMenu(model: model, row: row)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        ImportColumnTitle(row: row)
                        Text(row.samples.prefix(3).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                            .privacySensitiveInFeedback()
                    }
                }
            }
        }
    }
}

/// Dates, Numbers and Columns split by, each a menu of examples, with a
/// ring on one whose guess is still to confirm.
private struct ImportReadingFormatPickers: View {
    let model: ImportController

    var body: some View {
        let flow = model.flow
        Picker("Dates", selection: Binding(get: { model.flow.datePattern }, set: { model.flow.useDatePattern($0) })) {
            Text(flow.dateDetectedTitle).tag(String?.none)
            ForEach(flow.datePatternChoices, id: \.self) { pattern in
                Text(ImportChoices.dateExample(of: pattern)).tag(String?.some(pattern))
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .modifier(ImportGuessRing(isShown: flow.dateAmbiguity != nil))
        Picker("Numbers", selection: Binding(get: { model.flow.numberStyle }, set: { model.flow.useNumberStyle($0) })) {
            Text(flow.numberDetectedTitle).tag(ImportNumberFormat?.none)
            ForEach(flow.numberStyleChoices, id: \.self) { style in
                Text(ImportChoices.numberExample(style)).tag(ImportNumberFormat?.some(style))
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .modifier(ImportGuessRing(isShown: flow.numberAmbiguity != nil))
        Picker("Columns split by", selection: Binding(get: { model.flow.delimiter },
                                                      set: { model.flow.useDelimiter($0) })) {
            Text(flow.delimiterDetectedTitle).tag(String?.none)
            ForEach(flow.delimiterChoices, id: \.self) { delimiter in
                Text(ImportChoices.delimiterWord(delimiter)).tag(String?.some(delimiter))
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .modifier(ImportGuessRing(isShown: flow.delimiterAmbiguity != nil))
    }
}

/// An orange ring around a picker whose guess is still to confirm, and
/// what to do about it for VoiceOver.
private struct ImportGuessRing: ViewModifier {
    let isShown: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                if isShown {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Palette.warning, lineWidth: 1)
                        .padding(-2)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityHint(isShown ? "A guess: choose the right one to confirm it." : "")
    }
}

/// The file's first rows as written, a column per file column, under a
/// header with the file's own heading and a menu of what the column holds.
private struct ImportReadingGrid: View {
    let model: ImportController

    var body: some View {
        let flow = model.flow
        let columns = flow.columnRows
        let rows = flow.sampleRows(limit: 50)
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(columns) { column in
                        VStack(alignment: .leading, spacing: 6) {
                            ImportColumnTitle(row: column)
                                .font(.caption)
                                .foregroundStyle(Palette.secondaryInk)
                            ImportColumnUseMenu(model: model, row: column)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, Metrics.s)
                        .frame(width: Self.width(of: column), alignment: .leading)
                        .background(Palette.page)
                    }
                }
                Divider()
                    .gridCellUnsizedAxes(.horizontal)
                ForEach(rows) { sample in
                    GridRow {
                        ForEach(columns) { column in
                            Text(verbatim: column.column <= sample.cells.count ? sample.cells[column.column - 1] : "")
                                .monospacedDigit()
                                .lineLimit(1)
                                .foregroundStyle(column.use == .ignore ? Palette.secondaryInk : Palette.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .frame(width: Self.width(of: column),
                                       alignment: Self.isAmount(column) ? .trailing : .leading)
                                .privacySensitiveInFeedback()
                        }
                    }
                    Divider()
                        .gridCellUnsizedAxes(.horizontal)
                }
            }
        }
    }

    /// Amounts and balances are right-aligned.
    private static func isAmount(_ column: ImportColumnRow) -> Bool {
        switch column.use {
        case .field(.amount), .field(.credit), .field(.debit), .field(.balance): true
        default: false
        }
    }

    /// Wide columns for text, narrower ones for dates and amounts.
    private static func width(of column: ImportColumnRow) -> CGFloat {
        switch column.use {
        case .field(.description), .field(.counterparty): 260
        case _ where isAmount(column): 120
        default: 110
        }
    }
}

/// What a column holds, as a menu in a tinted pill over the column
/// ("Date ⌄", "Money out ⌄"), grey while it's ignored.
struct ImportColumnUseMenu: View {
    let model: ImportController
    let row: ImportColumnRow

    var body: some View {
        let layout = model.flow.layout
        Menu {
            Picker("Imports as", selection: Binding(get: { row.use }, set: { use in
                model.flow.setUse(use, forColumn: row.column)
            })) {
                ForEach(ColumnUse.options(for: layout), id: \.self) { use in
                    Text(use.title(in: layout)).tag(use)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            PillLabel(row.use.title(in: layout), isMuted: row.use == .ignore)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("\(row.title) holds")
        .accessibilityValue(row.use.title(in: layout))
    }
}

/// The lines read and what the balance follows on from: a check in the
/// positive color, or a warning.
private struct ImportReadingStatusLine: View {
    let status: ImportReadingStatus

    var body: some View {
        Label {
            Text(status.text)
        } icon: {
            Image(systemName: status.isProblem ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
        }
        .foregroundStyle(status.isProblem ? Palette.warning : Palette.positive)
        .privacySensitiveInFeedback()
    }
}

#Preview("How it's read") {
    ImportReadingPreview()
        .previewEnvironment()
}

/// *How It's Read* over a made-up statement.
private struct ImportReadingPreview: View {
    @Environment(LibraryStore.self) private var library
    @State private var model: ImportController?

    var body: some View {
        Group {
            if let model {
                ImportReadingSheet(model: model)
            } else {
                ProgressView()
            }
        }
        .task {
            model = ImportPreviewData.controller(library: library.library, step: .file, file: .statement)
        }
    }
}
