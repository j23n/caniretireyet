import SwiftUI
#if os(macOS)
import AppKit
#endif

/// *Export as CSV…*: what the export holds, then the zip to share (`ShareLink`),
/// on the Mac also to save. Written when the sheet opens
/// (``LibraryCSVExport/prepare()``).
struct LibraryCSVExportSheet: View {
    @State var export: LibraryCSVExport

    @Environment(\.dismiss) private var dismiss
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    fileRow
                    if let message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                } footer: {
                    Text(Self.contents)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Export as CSV")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await export.prepare() }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 300)
        #endif
    }

    /// The footer: what's in the zip.
    static let contents = "A zip of CSV files, for a spreadsheet or another app: net worth and each account's "
        + "value at every month end, and what's recorded (accounts, instruments, values, positions, trades, prices, "
        + "exchange rates and inflation). Dates are YYYY-MM-DD and numbers use a decimal point. Your plans aren't "
        + "included; their files in the library are plain JSON."

    /// The zip, once written: share it (and on the Mac, save it).
    @ViewBuilder
    private var fileRow: some View {
        if let file = export.file {
            ShareLink(item: file.url) {
                Label("Share \(file.name)…", systemImage: "square.and.arrow.up")
            }
            #if os(macOS)
            Button {
                save(file)
            } label: {
                Label("Save \(file.name)…", systemImage: "square.and.arrow.down")
            }
            #endif
        } else if let error = export.error {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(Palette.warning)
        } else {
            HStack(spacing: Metrics.s) {
                ProgressView()
                    .controlSize(.small)
                Text("Preparing…")
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }

    #if os(macOS)
    /// A save panel for the zip, then a copy of it where it says.
    private func save(_ file: LibraryCSVExport.File) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.name
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let manager = FileManager.default
            if manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
            try manager.copyItem(at: file.url, to: url)
            message = "Saved \(url.lastPathComponent)."
        } catch {
            message = "The file couldn't be saved: \(error.localizedDescription)"
        }
    }
    #endif
}
