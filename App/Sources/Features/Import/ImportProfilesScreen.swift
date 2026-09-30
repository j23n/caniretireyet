import Foundation
import Model
import SwiftUI

/// The library's saved import profiles (`imports/<id>.json`), to rename
/// or delete. Reached from the Import screen's first step.
struct ImportProfilesScreen: View {
    @Environment(LibraryStore.self) private var library
    @State private var renaming: ImportProfile?
    @State private var newName = ""
    @State private var deleting: ImportProfile?
    @State private var errorMessage: String?

    init() {}

    var body: some View {
        let profiles = library.library.importProfiles.values.sorted {
            ($0.name.lowercased(), $0.id) < ($1.name.lowercased(), $1.id)
        }
        List {
            if profiles.isEmpty {
                ContentUnavailableView(
                    "No saved profiles", systemImage: "tray",
                    description: Text("Save one at the end of an import, and the next file of the same shape "
                        + "imports in one step."))
            }
            ForEach(profiles) { profile in
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .foregroundStyle(Palette.ink)
                    Text(profile.importSummary)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                }
                .contextMenu {
                    Button("Rename…") { startRenaming(profile) }
                    Button("Delete…", role: .destructive) { deleting = profile }
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", role: .destructive) { deleting = profile }
                    Button("Rename") { startRenaming(profile) }
                }
            }
        }
        .navigationTitle("Import Profiles")
        .alert("Rename Profile", isPresented: isRenaming, presenting: renaming) { profile in
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { rename(profile) }
        } message: { profile in
            Text("Its ID, \(profile.id.rawValue), stays the same.")
        }
        .confirmationDialog("Delete this profile?", isPresented: isDeleting, titleVisibility: .visible,
                            presenting: deleting) { profile in
            Button("Delete “\(profile.name)”", role: .destructive) { delete(profile) }
        } message: { profile in
            Text("imports/\(profile.id.rawValue).json is deleted. What was imported with it stays.")
        }
        .alert("Something went wrong", isPresented: isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var isRenaming: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private var isDeleting: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    private var isShowingError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func startRenaming(_ profile: ImportProfile) {
        newName = profile.name
        renaming = profile
    }

    private func rename(_ profile: ImportProfile) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != profile.name else { return }
        do {
            try library.update { $0.importProfiles[profile.id]?.name = name }
        } catch {
            errorMessage = LibraryStore.describe(error)
        }
    }

    private func delete(_ profile: ImportProfile) {
        do {
            try library.update { $0.importProfiles[profile.id] = nil }
        } catch {
            errorMessage = LibraryStore.describe(error)
        }
    }
}

#Preview("Import profiles") {
    NavigationStack {
        ImportProfilesScreen()
    }
    .previewEnvironment()
}

#Preview("Import profiles · none") {
    NavigationStack {
        ImportProfilesScreen()
    }
    .previewEnvironment(PreviewLibrary.empty)
}
