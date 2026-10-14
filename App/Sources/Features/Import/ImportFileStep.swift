import Foundation
import Importer
import Model
import SwiftUI

/// Step 1, Files (UI.md, "Import"). Bank statements, one or many, are a
/// table on the Mac and iPad (`ImportFilesPage`) and a list on iPhone
/// (`ImportFilesList`): each file's bank, what it covers, whether its
/// balance adds up and its account, a menu to remove it, give its days or
/// see how it's read, a zone to drop more, and what's between the files.
/// Another kind of file (a spreadsheet, a broker's transactions, read one
/// at a time) shows what was read and the mapping to read it with: a saved
/// profile or a proposed one. Files dropped or added join those listed.
struct ImportFileStep: View {
    let model: ImportController
    let isCompact: Bool
    /// Shows the file importer, which adds files.
    let chooseFile: () -> Void
    /// Adds files dropped on the step.
    let addFiles: ([URL]) -> Void
    /// What the files are before any is read.
    var kindBeforeFiles: Binding<ImportFilesKind> = .constant(.statements)

    @Environment(LibraryStore.self) private var library
    @State private var isTargeted = false
    @State private var sheet: ImportFileSheet?

    var body: some View {
        content
            .dropDestination(for: URL.self) { urls, _ in
                guard !urls.isEmpty else { return false }
                addFiles(urls)
                return true
            } isTargeted: { targeted in
                isTargeted = targeted
            }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .reading:
                    ImportReadingSheet(model: model, isCompact: isCompact)
                case .days:
                    ImportFileDaysSheet(model: model)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if model.flow.isBatch {
            if isCompact {
                ImportFilesList(model: model, kind: kind, addFiles: chooseFile, showReading: showReading,
                                showDays: showDays)
            } else {
                ImportFilesPage(model: model, kind: kind, isTargeted: isTargeted, showReading: showReading,
                                showDays: showDays)
            }
        } else {
            oneFileForm
        }
    }

    /// What the files are: the open files' kind, or before any is read the
    /// one chosen. Choosing reads the files given again as that kind.
    private var kind: Binding<ImportFilesKind> {
        Binding(get: { model.flow.filesKind ?? kindBeforeFiles.wrappedValue }, set: { kind in
            kindBeforeFiles.wrappedValue = kind
            if model.flow.hasFile, model.flow.filesKind != nil {
                model.flow.setFilesKind(kind)
            }
        })
    }

    private func showReading(_ id: Int) {
        model.flow.showBatchFile(id)
        sheet = .reading(id)
    }

    private func showDays(_ id: Int) {
        model.flow.showBatchFile(id)
        sheet = .days(id)
    }

    // MARK: Another kind of file, or none yet

    /// Before a file is read, and for a spreadsheet or a broker's
    /// transactions: what the files are, a drop zone, what was read, and
    /// the mapping to read it with.
    private var oneFileForm: some View {
        let flow = model.flow
        return Form {
            if !flow.hasFile || flow.filesKind != nil {
                Section {
                    ImportFilesKindPicker(kind: kind, short: isCompact)
                } header: {
                    Text("These files are")
                } footer: {
                    if flow.filesKind == .brokerage, flow.givenFileNames.count > 1 {
                        Text("Brokerage transactions are read one file at a time. Import this one, then choose the "
                            + "next.")
                    }
                }
                if flow.filesKind == .brokerage, flow.givenFileNames.count > 1 {
                    Section {
                        Picker("File", selection: Binding(get: { flow.shownGivenFile ?? 0 }, set: { index in
                            model.flow.readGivenFile(index)
                        })) {
                            ForEach(Array(flow.givenFileNames.enumerated()), id: \.offset) { index, name in
                                Text(verbatim: name).tag(index)
                            }
                        }
                        .pickerStyle(.menu)
                        .personalControl()
                    }
                }
            }

            Section {
                ImportDropZone(fileName: flow.fileName, kind: kind.wrappedValue, isTargeted: isTargeted,
                               chooseFile: chooseFile)
            } footer: {
                Text("A CSV or TSV file, as Excel, Numbers or a bank exports it, in any delimiter, encoding, "
                    + "date and number format. Several bank statements, of one account or many, import together.")
            }

            if let problem = flow.problem, !flow.hasFile {
                Section {
                    StatusBanner(.error, "The file can't be read", message: problem, personal: .message)
                }
            }

            if flow.hasFile {
                Section("File") {
                    LabeledContent("Name", value: flow.fileName ?? "")
                        .privacySensitiveInFeedback()
                    LabeledContent("Read as", value: flow.tableSummary)
                    if let first = flow.preview?.firstDate, let last = flow.preview?.lastDate {
                        LabeledContent("Dates",
                                       value: "\(AmountFormat.mediumDate(first)) – \(AmountFormat.mediumDate(last))")
                            .privacySensitiveInFeedback()
                    }
                }
                mappingSection(flow)
            }

            Section {
                NavigationLink {
                    ImportProfilesScreen()
                } label: {
                    LabeledContent("Saved profiles", value: "\(library.library.importProfiles.count)")
                }
            }
        }
        .formStyle(.grouped)
    }

    /// A mapping the importer proposes, and the saved profiles, best fit first.
    private func mappingSection(_ flow: ImportFlow) -> some View {
        Section {
            ImportChoiceRow(title: "Propose a new mapping",
                            detail: "The importer reads the headers and values; check them step by step.",
                            isSelected: flow.source == .proposed) {
                model.flow.useProfile(nil)
            }
            ForEach(flow.profileFits) { fit in
                ImportChoiceRow(title: fit.profile.name, detail: fit.summary,
                                isSelected: flow.source == .profile(fit.profile.id)) {
                    model.flow.useProfile(fit.profile.id)
                }
                .privacySensitiveInFeedback()
            }
        } header: {
            Text("Read it with")
        } footer: {
            Text("A profile is a saved mapping: the next file of the same shape imports in one step.")
        }
    }
}

/// The sheets the Files step opens for one of its files.
private enum ImportFileSheet: Identifiable, Hashable {
    /// *How It's Read*.
    case reading(Int)
    /// *Days*.
    case days(Int)

    var id: Self { self }
}

/// A selectable row: a circle (filled when selected), a title and a detail line.
struct ImportChoiceRow: View {
    let title: String
    let detail: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Palette.accent : Palette.mutedInk)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(Palette.ink)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Where to drop files, with a button to add them.
private struct ImportDropZone: View {
    let fileName: String?
    let kind: ImportFilesKind
    let isTargeted: Bool
    let chooseFile: () -> Void

    var body: some View {
        VStack(spacing: Metrics.m) {
            Image(systemName: fileName == nil ? "square.and.arrow.down" : "doc.text")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
            Text(fileName ?? (kind == .brokerage ? "Drop brokerage transactions here" : "Drop statements here"))
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .privacySensitiveInFeedback(fileName != nil)
            Button("Add Files…", action: chooseFile)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Metrics.xl)
        .padding(.horizontal, Metrics.l)
        .background {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(isTargeted ? Palette.accent : Palette.border,
                              style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.5, dash: [6, 4]))
        }
    }
}

// MARK: - Days

/// The days one statement is read as covering (its *Days…*): whole months
/// unless it starts or ends on a day of its own. *Cancel* puts the import
/// back as it was; *Done* keeps the change.
struct ImportFileDaysSheet: View {
    let model: ImportController

    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var library
    /// The import as the sheet opened it, for *Cancel*.
    @State private var saved: ImportFlow?

    var body: some View {
        let flow = model.flow
        NavigationStack {
            Form {
                Section {
                    if let period = flow.shownFilePeriod() {
                        LabeledContent("Read as covering") {
                            Text(AmountFormat.mediumDate(period.from) + " – "
                                + AmountFormat.mediumDate(period.through))
                                .privacySensitiveInFeedback()
                        }
                    }
                    Toggle("Starts on a day of its own", isOn: Binding(get: { model.flow.statementFrom != nil },
                                                                        set: { on in
                        model.flow.setStatementFrom(on ? model.flow.shownFileFirstDay() : nil)
                    }))
                    if let from = flow.statementFrom {
                        DatePicker("First day", selection: Binding(get: { from.dateValue }, set: { date in
                            model.flow.setStatementFrom(CalendarDate(date, in: .current))
                        }), in: ...(flow.statementThrough?.dateValue ?? Date()), displayedComponents: .date)
                            .personalControl()
                    }
                    Toggle("Ends on a day of its own", isOn: Binding(get: { model.flow.statementThrough != nil },
                                                                      set: { on in
                        model.flow.setStatementThrough(on ? model.flow.shownFileLastDay() : nil)
                    }))
                    if let through = flow.statementThrough {
                        DatePicker("Last day", selection: Binding(get: { through.dateValue }, set: { date in
                            model.flow.setStatementThrough(CalendarDate(date, in: .current))
                        }), in: min(flow.statementFrom?.dateValue ?? .distantPast, Date())...Date(),
                                   displayedComponents: .date)
                            .personalControl()
                    }
                } footer: {
                    Text("A statement is read as whole months: from the first day of its first line's month to the "
                        + "last day of its last line's month, or today. A bank's export of the last 90 days, or one "
                        + "made in the middle of a month, covers less: give its first and last days. The last day "
                        + "gets a value of its own, which next month's file follows on from.")
                }
            }
            .formStyle(.grouped)
            .personalNavigationTitle("Days of \(flow.fileName ?? "the file")", hidden: "Days")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if let saved {
                            model.flow = saved
                            model.libraryChanged(library.library)
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            if saved == nil { saved = model.flow }
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 360, idealHeight: 420)
        #endif
    }
}

#Preview("Files") {
    NavigationStack {
        ImportPreviewHost(step: .file, file: .statement)
    }
    .previewEnvironment()
}

/// Several statements: the file Income and Review show, by name and
/// account, in the order they're imported.
struct ImportBatchFilePicker: View {
    let model: ImportController

    var body: some View {
        let flow = model.flow
        Picker("Statement", selection: Binding(get: { flow.batchFile ?? -1 }, set: { id in
            model.flow.showBatchFile(id)
        })) {
            ForEach(flow.batchFiles.filter { $0.account != nil }) { file in
                Text(verbatim: flow.batchFileTitle(file)).tag(file.id)
            }
        }
        .pickerStyle(.menu)
        .personalControl()
    }
}
