import Model
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// *Export Calculations…*: **Anonymize** (on by default, with its
/// rounding), then the Markdown file to share (`ShareLink`), on the Mac
/// also to save. The file is written again whenever the options change
/// (``PlanCalculationsExport/prepare()``).
struct PlanCalculationsSheet: View {
    @Bindable var export: PlanCalculationsExport

    @Environment(\.dismiss) private var dismiss
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Anonymize", isOn: $export.anonymizes)
                    if export.anonymizes {
                        Picker("Round amounts to", selection: $export.rounding) {
                            ForEach(PlanCalculationsExport.roundings, id: \.self) { rounding in
                                Text(Self.title(rounding)).tag(rounding)
                            }
                        }
                    }
                } footer: {
                    Text(export.anonymizes ? PlanCalculationsExport.anonymizeNote : PlanCalculationsExport.exactNote)
                }
                Section {
                    fileRow
                    if let message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                } footer: {
                    Text("Markdown: the plan as read, the starting portfolio, the chance of success by retirement "
                        + "age, the expected and median runs year by year, and why runs fail.")
                }
            }
            .formStyle(.grouped)
            .sheetTitle("Export Calculations") { dismiss() }
            .task(id: export.options) {
                message = nil
                await export.prepare()
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 320)
        #endif
    }

    /// "1", "100", "1,000" in the plan's currency.
    private static func title(_ rounding: Double) -> String {
        rounding <= 1 ? "Whole amounts" : "The nearest \(Int(rounding).formatted())"
    }

    /// The file, once written: share it (and on the Mac, save it).
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
                Text("Calculating…")
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }

    #if os(macOS)
    /// A save panel for the file, then a copy of it where it says.
    private func save(_ file: PlanCalculationsExport.File) {
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
