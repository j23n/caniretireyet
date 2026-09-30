import Foundation
import Importer
import Model
import SwiftUI

/// Step 6, Done: what the import did, Undo import (which puts the backup
/// back), and Save as profile, so the next file of the same shape imports
/// in one step.
struct ImportDoneStep: View {
    let model: ImportController

    @Environment(LibraryStore.self) private var library
    @State private var profileName = ""
    @State private var profileID = ""
    @State private var isIDEdited = false
    @State private var isConfirmingUndo = false

    var body: some View {
        Form {
            if let receipt = model.receipt {
                summarySection(receipt)
                if receipt.hasChanges {
                    undoSection(receipt)
                }
                profileSection(receipt)
            } else {
                Section {
                    Text("Nothing was imported.")
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { suggestProfile() }
        .onChange(of: profileName) { _, name in
            if !isIDEdited { profileID = model.flow.suggestedProfileID(for: name) }
        }
        .confirmationDialog("Undo this import?", isPresented: $isConfirmingUndo, titleVisibility: .visible) {
            Button("Undo Import", role: .destructive) {
                Task { await model.undoImport(in: library) }
            }
        } message: {
            Text("What it changed goes back to how it was before, and the files it created are deleted. Edits made "
                + "since the import stay. A copy of the files as they are now is kept in backups.")
        }
    }

    // MARK: Summary

    private func summarySection(_ receipt: ImportReceipt) -> some View {
        Section {
            if receipt.isUndone, !receipt.undoNotes.isEmpty {
                StatusBanner(.warning, "The import was undone, except for later changes",
                             message: receipt.undoNotes.joined(separator: "\n"))
            } else if receipt.isUndone {
                StatusBanner(.info, "The import was undone",
                             message: "The library's files are back to how they were before it.")
            } else if receipt.hasChanges {
                StatusBanner(.success, "Imported \(receipt.fileName)")
            } else {
                StatusBanner(.info, "Nothing to import", message: "The library already has everything in the file.")
            }
            countRow("Records added", receipt.added)
            countRow("Records filled in", receipt.updated)
            countRow("Conflicts overwritten", receipt.overwritten)
            countRow(receipt.undecided > 0 ? "Conflicts kept (\(receipt.undecided) undecided)" : "Conflicts kept",
                     receipt.kept)
            countRow("Already in the library", receipt.identical)
            countRow("Left out", receipt.skipped)
            countRow("Later new money worked out again", receipt.recomputedFlows)
            namesRow("New accounts", receipt.createdAccounts)
            namesRow("New instruments", receipt.createdInstruments)
            namesRow("Closed accounts", receipt.closedAccounts)
        } header: {
            Text("Summary")
        }
    }

    @ViewBuilder
    private func countRow(_ title: String, _ count: Int) -> some View {
        if count > 0 {
            LabeledContent(title) {
                Text(verbatim: "\(count)")
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private func namesRow(_ title: String, _ names: [String]) -> some View {
        if !names.isEmpty {
            LabeledContent(title, value: names.joined(separator: ", "))
        }
    }

    // MARK: Undo

    private func undoSection(_ receipt: ImportReceipt) -> some View {
        Section {
            Button("Undo Import", role: .destructive) {
                isConfirmingUndo = true
            }
            .disabled(!receipt.canUndo || model.isWorking || !library.canEdit)
        } header: {
            Text("Undo")
        } footer: {
            Text(Self.undoFooter(receipt))
        }
    }

    private static func undoFooter(_ receipt: ImportReceipt) -> String {
        let files = receipt.changedFiles.count == 1 ? "1 file" : "\(receipt.changedFiles.count) files"
        if receipt.isUndone, !receipt.undoNotes.isEmpty {
            return "Undone, except for what changed after the import, which was left in place."
        }
        if receipt.isUndone { return "Undone: the \(files) it wrote were put back." }
        if let backup = receipt.backup {
            return "The import wrote \(files). They were copied to \(backup.path) first; undoing puts back what the "
                + "import changed and leaves later edits alone."
        }
        return "The import wrote \(files)."
    }

    // MARK: Save as profile

    private func profileSection(_ receipt: ImportReceipt) -> some View {
        let problem = model.problemSaving(id: profileID, name: profileName)
        return Section {
            TextField("Name", text: $profileName)
            TextField("ID", text: Binding(get: { profileID }, set: { id in
                profileID = id
                isIDEdited = true
            }))
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Palette.warning)
            }
            Button(receipt.savedProfile == nil ? "Save Profile" : "Save Again") {
                _ = model.saveProfile(id: profileID, name: profileName, in: library)
            }
            .disabled(problem != nil || !library.canEdit)
            if let saved = receipt.savedProfile {
                Label("Saved as imports/\(saved.rawValue).json", systemImage: "checkmark.circle")
                    .foregroundStyle(Palette.good)
            }
        } header: {
            Text("Save as profile")
        } footer: {
            Text("The mapping, with every format written out, in the library's imports folder. The next file of the "
                + "same shape imports in one step, here, on your other devices, or with “\(cliCommand)”.")
        }
    }

    /// The CLI command that imports with the profile.
    private var cliCommand: String {
        let id = profileID.isEmpty ? "<id>" : profileID
        return model.flow.isLedger ? "retire import ledger <files> --profile \(id)" : "retire import --profile \(id)"
    }

    private func suggestProfile() {
        guard profileName.isEmpty else { return }
        profileName = model.flow.suggestedProfileName
        profileID = model.flow.suggestedProfileID(for: profileName)
    }
}

#Preview("Done") {
    NavigationStack {
        ImportPreviewHost(step: .done)
    }
    .previewEnvironment()
}
