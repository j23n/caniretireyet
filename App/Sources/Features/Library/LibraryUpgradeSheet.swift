import SwiftUI

/// What upgrading the library's format did (``LibraryUpgrade``), from the
/// banner that says it was upgraded: each step, the notes on what to check,
/// and where the copy from before is. Closing it dismisses the banner.
struct LibraryUpgradeSheet: View {
    let upgrade: LibraryUpgrade

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(upgrade.steps, id: \.self) { step in
                        Text(step)
                    }
                } header: {
                    Text("What changed")
                } footer: {
                    Text("From format version \(upgrade.fromVersion) to \(upgrade.toVersion).")
                }
                if !upgrade.notes.isEmpty {
                    Section {
                        ForEach(upgrade.notes, id: \.self) { note in
                            Text(note)
                                .privacySensitiveInFeedback()
                        }
                    } header: {
                        Text("What to check")
                    }
                }
                Section {
                    Text(upgrade.backupNote)
                        .foregroundStyle(Palette.secondaryInk)
                        .privacySensitiveInFeedback()
                }
            }
            .formStyle(.grouped)
            .sheetTitle("Library Upgraded") { dismiss() }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 360)
        #endif
    }
}

#Preview("Library upgraded") {
    LibraryUpgradeSheet(upgrade: .example)
        .previewEnvironment()
}
