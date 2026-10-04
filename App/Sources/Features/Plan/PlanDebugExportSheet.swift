import Model
import Planner
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// *Export…* from the plan debugger (UI.md, "Calculations (plan
/// debugger)"): **Anonymize** (on by default, with its rounding), Markdown
/// or JSON, then the file to share (`ShareLink`), on the Mac also to save
/// (a save panel), and *Copy as Markdown*. The file is written to a
/// temporary folder whenever the options change (`PlanDebugModel.prepareExport()`).
struct PlanDebugExportSheet: View {
    @Bindable var model: PlanDebugModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.hidesAmounts) private var hidesAmounts
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Toggle("Anonymize", isOn: $model.export.anonymizes)
                if model.export.anonymizes {
                    Picker("Round amounts to", selection: $model.export.rounding) {
                        ForEach(PlanDebugExportSettings.roundings, id: \.self) { rounding in
                            Text(PlanDebugText.title(rounding)).tag(rounding)
                        }
                    }
                }
            } footer: {
                Text(model.export.anonymizes ? PlanDebugText.anonymizeNote
                    : "Keeps every name, ID and the birth date, with exact amounts: for yourself.")
            }
            Section {
                Picker("Format", selection: $model.export.format) {
                    ForEach(PlanDebugExportFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(model.export.format.explanation)
            }
            Section {
                fileRow
                Button {
                    copy()
                } label: {
                    Label("Copy as Markdown", systemImage: "doc.on.doc")
                }
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
            } footer: {
                if hidesAmounts {
                    Text(PlanDebugText.hiddenAmountsNote)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Export Calculations")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task(id: model.export) {
            message = nil
            await model.prepareExport()
        }
    }

    /// The file, once written: share it (and on the Mac, save it).
    @ViewBuilder
    private var fileRow: some View {
        if let file = model.readyExportFile {
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
        } else if let error = model.exportError {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(Palette.warning)
        } else {
            HStack(spacing: Metrics.s) {
                ProgressView()
                    .controlSize(.small)
                Text("Preparing the file…")
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }

    private func copy() {
        let anonymized = model.export.anonymizes
        Task {
            guard let text = await model.markdown() else { return }
            PlanDebugPasteboard.copy(text)
            message = anonymized ? "Copied the anonymized Markdown." : "Copied the Markdown."
        }
    }

    #if os(macOS)
    /// A save panel for the file, then a copy of it where it says.
    private func save(_ file: PlanDebugExportFile) {
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
