import CloudSync
import Model
import Storage
import SwiftUI

/// Library → Sync & backups (PLAN.md, "Resolving conflicts": merges are
/// listed so you can check them). Where the library is, whether it's
/// saving or syncing, the conflicts merged since launch, files that
/// couldn't be read, and the backups in `backups/`, each of which can be
/// restored.
struct SyncScreen: View {
    @Environment(LibraryStore.self) private var library
    @State private var backups: [Backup] = []
    /// The backup *Restore…* asks about.
    @State private var restoring: Backup?
    @State private var isRestoring = false
    /// What the last restore did, or why it failed.
    @State private var restoreNote: String?
    @State private var restoreFailed = false

    init() {}

    var body: some View {
        Form {
            Section("Library") {
                LibraryLocationRows()
                LabeledContent("Status", value: statusText)
                if let saved = library.lastSavedAt {
                    LabeledContent("Last saved") {
                        Text(saved, format: .dateTime.day().month().hour().minute())
                    }
                }
                if let synced = library.lastSyncedAt {
                    LabeledContent("Last change from elsewhere") {
                        Text(synced, format: .dateTime.day().month().hour().minute())
                    }
                }
                if let reason = library.readOnlyReason {
                    Text(LibraryStoreError.readOnly(reason).message)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }

            Section {
                if library.mergedConflicts.isEmpty && library.conflictFailures.isEmpty && library.saveNotices.isEmpty {
                    Text("No sync conflicts since the app opened.")
                        .foregroundStyle(Palette.secondaryInk)
                }
                ForEach(library.saveNotices) { notice in
                    Label {
                        VStack(alignment: .leading, spacing: Metrics.xs) {
                            Text(notice.path).font(.callout.monospaced())
                            Text(notice.summary).font(.footnote).foregroundStyle(Palette.secondaryInk)
                            Text(notice.date, format: .dateTime.day().month().hour().minute())
                                .font(.caption)
                                .foregroundStyle(Palette.mutedInk)
                        }
                    } icon: {
                        Image(systemName: "doc.on.doc").foregroundStyle(Palette.warning)
                    }
                }
                ForEach(library.mergedConflicts) { conflict in
                    VStack(alignment: .leading, spacing: Metrics.xs) {
                        Text(conflict.path).font(.callout.monospaced())
                        Text(conflict.summary).font(.footnote).foregroundStyle(Palette.secondaryInk)
                        Text(conflict.resolvedAt, format: .dateTime.day().month().hour().minute())
                            .font(.caption)
                            .foregroundStyle(Palette.mutedInk)
                    }
                }
                ForEach(library.conflictFailures) { failure in
                    Label {
                        VStack(alignment: .leading) {
                            Text(failure.path).font(.callout.monospaced())
                            Text(failure.message).font(.footnote).foregroundStyle(Palette.secondaryInk)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(Palette.warning)
                    }
                }
                if !library.mergedConflicts.isEmpty || !library.conflictFailures.isEmpty || !library.saveNotices.isEmpty {
                    Button("Clear this list") { library.dismissMergedConflicts() }
                }
            } header: {
                Text("Sync conflicts")
            } footer: {
                Text("When two devices change the same file before it syncs, the app merges them record by record. "
                    + "History keeps every record; for other files the newest version wins. When the app saves a "
                    + "file that was changed elsewhere, it merges history record by record, and copies any other "
                    + "file to backups before replacing it.")
            }

            Section("Files with problems") {
                if library.loadIssues.isEmpty {
                    Text("Every file was read without problems.")
                        .foregroundStyle(Palette.secondaryInk)
                }
                ForEach(Array(library.loadIssues.enumerated()), id: \.offset) { _, issue in
                    Label {
                        VStack(alignment: .leading) {
                            Text(issue.path).font(.callout.monospaced())
                            Text(issue.message).font(.footnote).foregroundStyle(Palette.secondaryInk)
                        }
                    } icon: {
                        Image(systemName: issue.severity == .error ? "xmark.octagon" : "exclamationmark.triangle")
                            .foregroundStyle(issue.severity == .error ? Palette.critical : Palette.warning)
                    }
                }
            }

            Section {
                if backups.isEmpty {
                    Text("No backups yet. The app makes one before an import or an upgrade.")
                        .foregroundStyle(Palette.secondaryInk)
                }
                ForEach(backups.reversed(), id: \.name) { backup in
                    LabeledContent {
                        HStack(spacing: Metrics.s) {
                            Text(backup.created, format: .dateTime.day().month().year().hour().minute())
                            Button("Restore…") { restoring = backup }
                                .buttonStyle(.borderless)
                                .disabled(isRestoring)
                        }
                    } label: {
                        Text(backup.label)
                    }
                }
                if let restoreNote {
                    Text(restoreNote)
                        .font(.footnote)
                        .foregroundStyle(restoreFailed ? Palette.critical : Palette.secondaryInk)
                }
            } header: {
                Text("Backups")
            } footer: {
                Text("Copies in the library's backups folder. Restoring one puts its files back as they were, after "
                    + "copying them as they are now to a new backup. Safe to delete.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Sync & backups")
        .task(id: library.revision) {
            backups = await library.backups()
        }
        .refreshable {
            await library.reloadAll()
        }
        .confirmationDialog("Restore this backup?", isPresented: isConfirmingRestore, titleVisibility: .visible,
                            presenting: restoring) { backup in
            Button("Restore", role: .destructive) {
                Task { await restore(backup) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { backup in
            Text(Self.restoreQuestion(for: backup))
        }
    }

    private var isConfirmingRestore: Binding<Bool> {
        Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } })
    }

    /// Restores `backup` (``LibraryStore/restore(_:)``) and says how it went.
    private func restore(_ backup: Backup) async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await library.restore(backup)
            restoreFailed = false
            restoreNote = "Restored the \(backup.label) backup of \(Self.dateText(backup.created)): "
                + "\(Wording.count(backup.files.count, "file")) put back."
        } catch {
            restoreFailed = true
            restoreNote = "The backup couldn't be restored. \(LibraryStore.describe(error))"
        }
        backups = await library.backups()
    }

    /// What restoring `backup` does, in the confirmation.
    static func restoreQuestion(for backup: Backup) -> String {
        let date = dateText(backup.created)
        var sentences: [String] = []
        switch backup.files.count {
        case 0: break
        case 1: sentences.append("Its file goes back to how it was on \(date), over any changes made to it since.")
        default:
            sentences.append("Its \(backup.files.count) files go back to how they were on \(date), over any changes "
                + "made to them since.")
        }
        if !backup.absentFiles.isEmpty {
            sentences.append("\(Wording.count(backup.absentFiles.count, "file")) it didn't have will be deleted.")
        }
        sentences.append("The files as they are now are copied to a new backup first.")
        return sentences.joined(separator: " ")
    }

    private static func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.day().month().year().hour().minute())
    }

    private var statusText: String {
        switch library.activity {
        case .idle: library.lastError == nil ? "Up to date" : "Last save failed"
        case .loading: "Loading…"
        case .saving: "Saving…"
        case .syncing: "Merging changes…"
        case .moving: "Moving to iCloud Drive…"
        }
    }
}

/// Where the library is kept, with the actions that go with it: show it in
/// Files or Finder, and for a library on this device, move it into iCloud
/// Drive or switch to the library already there. Used by Settings and the
/// Sync screen.
struct LibraryLocationRows: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.openURL) private var openURL
    @State private var isMoving = false
    @State private var isSwitching = false
    @State private var moveError: String?

    init() {}

    var body: some View {
        LabeledContent("Location", value: library.location?.kind.description ?? "Not open")
        if let url = library.location?.url {
            Button(showInFilesTitle) { show(url) }
        }
        if library.location?.kind == .local && library.isICloudAvailable {
            Button {
                Task {
                    isMoving = true
                    defer { isMoving = false }
                    do {
                        try await library.moveToICloud()
                    } catch {
                        moveError = LibraryStore.describe(error)
                    }
                }
            } label: {
                if isMoving {
                    ProgressView()
                } else {
                    Text("Move to iCloud Drive")
                }
            }
            .disabled(isMoving || isSwitching)
            Button {
                Task {
                    isSwitching = true
                    defer { isSwitching = false }
                    moveError = nil
                    do {
                        try await library.useICloudLibrary()
                    } catch {
                        moveError = LibraryStore.describe(error)
                    }
                }
            } label: {
                if isSwitching {
                    ProgressView()
                } else {
                    Text("Use the iCloud Drive Library")
                }
            }
            .disabled(isMoving || isSwitching)
            Text("Moving puts this library in iCloud Drive. If iCloud Drive already has one, use that instead: "
                + "this one then stays on this device.")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
        }
        if let moveError {
            Text(moveError).font(.footnote).foregroundStyle(Palette.critical)
        }
    }

    private var showInFilesTitle: String {
        #if os(macOS)
        return "Show in Finder"
        #else
        return "Show in Files"
        #endif
    }

    private func show(_ folder: URL) {
        #if os(macOS)
        openURL(folder)
        #else
        // The Files app opens a folder given as a shareddocuments:// URL.
        if let files = URL(string: "shareddocuments://" + folder.path) {
            openURL(files)
        }
        #endif
    }
}

#Preview("Sync") {
    NavigationStack {
        SyncScreen()
    }
    .previewEnvironment()
}
