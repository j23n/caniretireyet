import Foundation
import Importer
import Model
import SwiftUI

/// Step 1, File: a drop zone and a file importer, what was read, and the
/// mapping to read it with: a saved profile or a proposed one. A bank
/// statement's account is asked here, before any other step, with its
/// format and columns in a sheet. Several statements dropped at once are
/// listed each with its account, the transfers paired between them, and
/// the gaps between an account's files. On iPhone this is "Import with
/// profile…", with a way into every step.
struct ImportFileStep: View {
    let model: ImportController
    let isCompact: Bool
    let chooseFile: () -> Void
    let openFiles: ([URL]) -> Void

    @Environment(LibraryStore.self) private var library
    @State private var isTargeted = false
    @State private var isShowingReading = false

    var body: some View {
        let flow = model.flow
        Form {
            Section {
                ImportDropZone(fileName: flow.displayName, isTargeted: isTargeted, chooseFile: chooseFile)
            } footer: {
                Text("A CSV or TSV file, as Excel, Numbers or a bank exports it, in any delimiter, encoding, "
                    + "date and number format. Several bank statements, of one account or many, import together.")
            }

            if let problem = flow.problem, !flow.hasFile {
                Section {
                    StatusBanner(.error, "The file can't be read", message: problem, personal: .message)
                }
            }

            if flow.isBatch {
                batchSections(flow)
            } else if flow.hasFile {
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
                if flow.layout == .statement {
                    statementSection(flow)
                }
                mappingSection(flow)
            }

            if flow.isGuided {
                Section {
                    Button("Set Up the Columns Step by Step") {
                        model.flow.setGuided(false)
                    }
                } footer: {
                    Text("For a file no saved profile fits. There's more room for the table on a Mac or an iPad, "
                        + "and you can save the mapping as a profile at the end.")
                }
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
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            openFiles(urls)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .sheet(isPresented: $isShowingReading) {
            ImportReadingSheet(model: model, isCompact: isCompact)
        }
    }

    /// A bank statement: the account it's of, which every later step needs,
    /// and how the file is read.
    private func statementSection(_ flow: ImportFlow) -> some View {
        Section {
            ImportStatementAccountPicker(model: model)
            Button("How It's Read…") {
                isShowingReading = true
            }
        } header: {
            Text("Bank statement")
        } footer: {
            if flow.needsStatementAccount {
                Text("Which account is this a statement of? A cash or savings account that doesn't record trades.")
                    .foregroundStyle(Palette.warning)
            } else if flow.source != .proposed {
                Text("Its format and columns come from the chosen profile. How It's Read… shows them, to correct.")
            } else {
                Text("Its format and columns were read from the file. How It's Read… shows them, to correct.")
            }
        }
    }

    /// Several statements: each file with what's in it, its account and
    /// how it was found, and how it's read; the files that can't be read;
    /// then the transfers paired and the gaps between an account's files.
    @ViewBuilder
    private func batchSections(_ flow: ImportFlow) -> some View {
        Section {
            ForEach(flow.batchFiles) { file in
                ImportBatchFileRow(model: model, file: file) {
                    model.flow.showBatchFile(file.id)
                    isShowingReading = true
                }
            }
        } header: {
            Text("Bank statements")
        } footer: {
            if let file = flow.batchFileWithoutAccount {
                Text("Which account is \(file.name) a statement of? A cash or savings account that doesn't record "
                    + "trades.")
                    .foregroundStyle(Palette.warning)
                    .privacySensitiveInFeedback()
            } else {
                Text("Each file's account was recognized or chosen. They're imported one after another, so each "
                    + "month follows on from the one before.")
            }
        }
        if let unreadable = flow.batch?.unreadable, !unreadable.isEmpty {
            Section("Can't be read") {
                ForEach(unreadable, id: \.name) { file in
                    StatusBanner(.warning, file.name, message: ImportFlow.describe(file.error), personal: .title)
                }
            }
        }
        let notes = flow.batchNotes
        if !notes.isEmpty {
            Section {
                ForEach(notes, id: \.self) { note in
                    Label {
                        Text(note.text)
                            .foregroundStyle(note.isProblem ? Palette.warning : Palette.ink)
                    } icon: {
                        Image(systemName: note.isProblem ? "exclamationmark.triangle" : "checkmark.circle")
                            .foregroundStyle(note.isProblem ? Palette.warning : Palette.positive)
                    }
                    .privacySensitiveInFeedback()
                }
            }
        }
    }

    /// The saved profiles, best fit first, and (except on iPhone's "Import
    /// with profile…") a mapping the importer proposes.
    private func mappingSection(_ flow: ImportFlow) -> some View {
        Section {
            if !flow.isGuided {
                ImportChoiceRow(title: "Propose a new mapping",
                                detail: flow.layout == .statement
                                    ? "The importer reads the headers and values; How It's Read… shows them."
                                    : "The importer reads the headers and values; check them step by step.",
                                isSelected: flow.source == .proposed) {
                    model.flow.useProfile(nil)
                }
            }
            ForEach(flow.profileFits) { fit in
                ImportChoiceRow(title: fit.profile.name, detail: fit.summary,
                                isSelected: flow.source == .profile(fit.profile.id)) {
                    model.flow.useProfile(fit.profile.id)
                }
                .privacySensitiveInFeedback()
            }
            if flow.isGuided && flow.profileFits.isEmpty {
                Text("There are no saved profiles yet. Set up this file step by step, and save the mapping as a "
                    + "profile at the end.")
                    .foregroundStyle(Palette.secondaryInk)
            }
        } header: {
            Text(flow.isGuided ? "Import with profile" : "Read it with")
        } footer: {
            Text("A profile is a saved mapping: the next file of the same shape imports in one step.")
        }
    }
}

/// How a bank statement is read: the Format and Columns steps in a sheet,
/// for a file the importer read wrongly (UI.md, "Import").
struct ImportReadingSheet: View {
    let model: ImportController
    let isCompact: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var page: ImportStep = .columns

    var body: some View {
        NavigationStack {
            Group {
                if page == .format {
                    ImportFormatStep(model: model)
                } else {
                    ImportColumnsStep(model: model, isCompact: isCompact)
                }
            }
            .navigationTitle("How It's Read")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Show", selection: $page) {
                        Text("Format").tag(ImportStep.format)
                        Text("Columns").tag(ImportStep.columns)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 820, idealWidth: 960, minHeight: 600, idealHeight: 720)
        #endif
    }
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

/// Where to drop a file, with a button to choose one.
private struct ImportDropZone: View {
    let fileName: String?
    let isTargeted: Bool
    let chooseFile: () -> Void

    var body: some View {
        VStack(spacing: Metrics.m) {
            Image(systemName: fileName == nil ? "square.and.arrow.down" : "doc.text")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
            Text(fileName ?? "Drop a spreadsheet export here")
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .privacySensitiveInFeedback(fileName != nil)
            Button(fileName == nil ? "Choose File…" : "Choose Another File…", action: chooseFile)
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

#Preview("File") {
    NavigationStack {
        ImportPreviewHost(step: .file)
    }
    .previewEnvironment()
}

#Preview("Import with profile") {
    NavigationStack {
        ImportPreviewHost(step: .file, guided: true)
    }
    .previewEnvironment()
}

/// One of several statements: its name, what's in it, its account (to
/// choose when nothing recognized it) and how it was found, and How It's
/// Read….
private struct ImportBatchFileRow: View {
    let model: ImportController
    let file: StatementBatch.File
    let showReading: () -> Void

    var body: some View {
        let flow = model.flow
        VStack(alignment: .leading, spacing: Metrics.xs) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: file.name)
                        .lineLimit(1)
                        .privacySensitiveInFeedback()
                    Text(flow.batchFileDetail(file))
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                        .privacySensitiveInFeedback()
                }
                Spacer(minLength: Metrics.s)
                Button("How It's Read…", action: showReading)
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            Picker("Account", selection: Binding(get: { file.account }, set: { account in
                model.flow.setBatchAccount(account, forFile: file.id)
            })) {
                Text("Choose…").tag(AccountID?.none)
                ForEach(flow.statementAccountChoices) { account in
                    Text(account.name).tag(AccountID?.some(account.id))
                }
            }
            .pickerStyle(.menu)
            .personalControl()
            if let found = flow.batchAccountSourceText(file) {
                Text(found)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .privacySensitiveInFeedback()
            }
        }
        .padding(.vertical, 2)
    }
}

/// Several statements: the file Income and Preview show, by name and
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
