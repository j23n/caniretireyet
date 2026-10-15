import Foundation
import Importer
import Model
import Planner
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// *Save Starter Spreadsheet…* (UI.md, "Empty states and first launch"):
/// the Importer's `StarterSpreadsheet`, a CSV with a column each for a
/// home, a mortgage and a pension, headed with today's row and the
/// pension estimate's amount, to fill in and import. The home's column
/// starts empty: it's the home's value, with the mortgage beside it, and
/// the tour's home estimate is the two together. On the iPhone and
/// iPad it's shared (*Save to Files*); on the Mac it's saved where you
/// choose.
struct StarterSpreadsheetButton: View {
    @Environment(LibraryStore.self) private var library
    @State private var file: URL?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            if let file {
                #if os(macOS)
                Button {
                    save(file)
                } label: {
                    Label("Save Starter Spreadsheet…", systemImage: "tablecells")
                }
                #else
                ShareLink(item: file) {
                    Label("Save Starter Spreadsheet…", systemImage: "tablecells")
                }
                #endif
            }
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .task(id: library.revision) { file = write() }
    }

    /// The CSV with today's row and the open pension estimate's amount.
    static func csv(for library: Library, on date: CalendarDate) -> String {
        var amounts: [String: Decimal] = [:]
        for estimate in library.openStartingEstimates where estimate.kind == .pensionFund {
            if let balance = library.valuations(for: estimate.id).last?.balance { amounts["Pension"] = balance }
        }
        return StarterSpreadsheet.csv(on: date, amounts: amounts)
    }

    /// Writes the spreadsheet to a folder of its own in the temporary
    /// directory; `nil` when it can't be written.
    private func write() -> URL? {
        let text = Self.csv(for: library.library, on: .today())
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Starter spreadsheet", isDirectory: true)
        let url = folder.appendingPathComponent(StarterSpreadsheet.fileName)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url, options: .atomic)
            return url
        } catch {
            message = "The spreadsheet couldn't be written: \(error.localizedDescription)"
            return nil
        }
    }

    #if os(macOS)
    private func save(_ file: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.lastPathComponent
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let manager = FileManager.default
            if manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
            try manager.copyItem(at: file, to: url)
            message = "Saved \(url.lastPathComponent). Fill in a row per date, then import it."
        } catch {
            message = "The spreadsheet couldn't be saved: \(error.localizedDescription)"
        }
    }
    #endif
}
