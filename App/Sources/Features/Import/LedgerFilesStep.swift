import Foundation
import Importer
import Model
import SwiftUI
import UniformTypeIdentifiers

/// Step 1 of a journal import, Files: what was read (files, transactions,
/// dates), includes the app couldn't read with "Choose the Journal's
/// Folder…", problems in the journal, and the mapping to read it with: a
/// saved ledger profile or a proposed one.
struct LedgerFilesStep: View {
    let model: ImportController
    /// Shows the file importer.
    let chooseFiles: () -> Void
    /// Reads files dropped on the step.
    let openFiles: ([URL]) -> Void

    @Environment(LibraryStore.self) private var library
    @State private var isChoosingFolder = false
    @State private var isTargeted = false

    /// Problems listed, at most.
    private static let limit = 100

    var body: some View {
        let flow = model.flow
        Form {
            Section {
                LedgerDropZone(title: flow.fileName ?? "Drop journal files here", isTargeted: isTargeted,
                               chooseFiles: chooseFiles)
            } footer: {
                Text("ledger-cli or hledger journals (.ledger, .journal, .hledger, .j, .dat). Choose several at once, "
                    + "e.g. one per year; the files they include are read too.")
            }

            if let ledger = flow.ledger {
                journalSection(ledger)
                if !ledger.journal.missingIncludes.isEmpty {
                    missingIncludesSection(ledger)
                }
                if !ledger.journal.diagnostics.isEmpty {
                    problemsSection(ledger)
                }
                mappingSection(flow)
            }

            if flow.isGuided {
                Section {
                    Button("Set Up the Accounts Step by Step") {
                        model.flow.setGuided(false)
                    }
                } footer: {
                    Text("For a journal no saved profile fits. There's more room on a Mac or an iPad, and you can "
                        + "save the mapping as a profile at the end.")
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
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let folder):
                Task { await model.grantLedgerFolder(folder) }
            case .failure(let error):
                model.errorMessage = error.localizedDescription
            }
        }
    }

    private func journalSection(_ ledger: LedgerImportState) -> some View {
        Section {
            LabeledContent("Read", value: ledger.summary())
            LabeledContent("Prices", value: ledger.journal.prices.count == 1 ? "1 P directive"
                : "\(ledger.journal.prices.count) P directives")
            ForEach(ledger.journal.files, id: \.url) { file in
                LabeledContent {
                    Text(file.transactions == 1 ? "1 transaction" : "\(file.transactions) transactions")
                        .monospacedDigit()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(file.name, systemImage: "doc.text")
                        if let include = file.includedFrom {
                            Text("Included from \(include.description)")
                                .font(.caption)
                                .foregroundStyle(Palette.secondaryInk)
                        }
                    }
                }
            }
        } header: {
            Text("Journal")
        }
    }

    private func missingIncludesSection(_ ledger: LedgerImportState) -> some View {
        Section {
            ForEach(Array(ledger.journal.missingIncludes.enumerated()), id: \.offset) { _, include in
                VStack(alignment: .leading, spacing: 2) {
                    Label(include.path, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Palette.ink)
                    Text("\(include.location.description): \(include.reason)")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            Button("Choose the Journal's Folder…") {
                isChoosingFolder = true
            }
        } header: {
            Text("Included files that can't be read")
        } footer: {
            Text("The app may only read the files you chose. Choose the folder that holds the journal and the files "
                + "it includes, and it's read again.")
        }
    }

    private func problemsSection(_ ledger: LedgerImportState) -> some View {
        let diagnostics = ledger.journal.diagnostics
        return Section {
            ForEach(Array(diagnostics.prefix(Self.limit).enumerated()), id: \.offset) { _, diagnostic in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(diagnostic.message)
                        if let location = diagnostic.location {
                            Text(location.description)
                                .font(.caption)
                                .foregroundStyle(Palette.secondaryInk)
                        }
                    }
                } icon: {
                    Image(systemName: diagnostic.severity == .error ? "xmark.octagon" : "exclamationmark.triangle")
                        .foregroundStyle(diagnostic.severity == .error ? Palette.critical : Palette.warning)
                }
            }
            if diagnostics.count > Self.limit {
                Text("And \(diagnostics.count - Self.limit) more.")
                    .foregroundStyle(Palette.secondaryInk)
            }
        } header: {
            Text("Problems in the journal")
        } footer: {
            Text("Transactions with an error are left out; the rest of the journal is read. A failed balance "
                + "assertion is only a warning.")
        }
    }

    /// The saved ledger profiles, best fit first, and a proposed mapping.
    private func mappingSection(_ flow: ImportFlow) -> some View {
        Section {
            if !flow.isGuided {
                ImportChoiceRow(title: "Propose a new mapping",
                                detail: "Accounts and commodities are matched to the library by name; check them in "
                                    + "the next steps.",
                                isSelected: flow.source == .proposed) {
                    model.flow.useLedgerProfile(nil)
                }
            }
            ForEach(flow.ledgerProfileFits) { fit in
                ImportChoiceRow(title: fit.profile.name, detail: fit.summary,
                                isSelected: flow.source == .profile(fit.profile.id)) {
                    model.flow.useLedgerProfile(fit.profile.id)
                }
            }
            if flow.isGuided && flow.ledgerProfileFits.isEmpty {
                Text("There are no saved ledger profiles yet. Set up this journal step by step, and save the "
                    + "mapping as a profile at the end.")
                    .foregroundStyle(Palette.secondaryInk)
            }
        } header: {
            Text(flow.isGuided ? "Import with profile" : "Read it with")
        } footer: {
            Text("A profile remembers where each ledger account and commodity goes, so next month's import is one "
                + "step.")
        }
    }
}

/// Where to drop journal files, with a button to choose them.
private struct LedgerDropZone: View {
    let title: String
    let isTargeted: Bool
    let chooseFiles: () -> Void

    var body: some View {
        VStack(spacing: Metrics.m) {
            Image(systemName: "book.closed")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            Button("Choose Other Files…", action: chooseFiles)
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

/// The file types the Import screen accepts for journals.
enum LedgerFileTypes {
    /// The journal type declared in Info.plist, and the extensions as a fallback.
    static let contentTypes: [UTType] = {
        var types = [UTType(importedAs: "org.ledger-cli.journal", conformingTo: .plainText)]
        for fileExtension in LedgerFiles.extensions.sorted() {
            if let type = UTType(filenameExtension: fileExtension), !types.contains(type) { types.append(type) }
        }
        return types
    }()
}

/// What the journal import couldn't value or convert, for the Preview step.
struct LedgerNotesCard: View {
    let notes: [String]

    /// Notes listed, at most.
    private static let limit = 50

    var body: some View {
        if !notes.isEmpty {
            Card(notes.count == 1 ? "1 note" : "\(notes.count) notes", systemImage: "info.circle") {
                ForEach(Array(notes.prefix(Self.limit).enumerated()), id: \.offset) { _, note in
                    Text(note)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if notes.count > Self.limit {
                    Text("And \(notes.count - Self.limit) more.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
                Text("A flow that can't be valued is left unknown; you can enter it later in the account's history.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
