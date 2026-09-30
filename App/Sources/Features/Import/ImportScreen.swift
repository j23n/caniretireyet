import Model
import SwiftUI

// PLACEHOLDER — Import feature engineer: replace this screen's content
// (UI.md, "Import": file, format, columns, accounts, preview, done; on
// iPhone "Import with profile…"). Keep the name `ImportScreen` and
// `init(file:)`: ⌘⇧I, the sidebar's Import… and dropping a CSV on the
// window create it, with the dropped file if there is one (the sidebar
// also leaves it in `navigation.pendingImport`; clear it with
// `navigation.takePendingImport()` once taken). Write through
// `LibraryStore` (`update(_:)`, `save(_ profile:)`); take a backup first
// with `LibraryFolder.backup(paths:label:)` so the import can be undone.

/// Importing a spreadsheet or CSV export (IMPORT.md).
struct ImportScreen: View {
    let file: URL?

    @Environment(LibraryStore.self) private var library

    init(file: URL? = nil) {
        self.file = file
    }

    var body: some View {
        Form {
            Section {
                if let file {
                    LabeledContent("File", value: file.lastPathComponent)
                } else {
                    Text("Drop a CSV file on the window, or choose one, to import it.")
                        .foregroundStyle(Palette.secondaryInk)
                }
                Text("The importer arrives with the Importer module.")
                    .font(.footnote)
                    .foregroundStyle(Palette.mutedInk)
            }
            Section("Saved profiles") {
                if library.library.importProfiles.isEmpty {
                    Text("None yet: save one at the end of an import.")
                        .foregroundStyle(Palette.secondaryInk)
                }
                ForEach(library.library.importProfiles.values.sorted { $0.name < $1.name }) { profile in
                    Text(profile.name)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Import")
    }
}

#Preview("Import") {
    NavigationStack {
        ImportScreen(file: URL(fileURLWithPath: "/tmp/net-worth.csv"))
    }
    .previewEnvironment()
}
