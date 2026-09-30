import Foundation
import Importer
import Model
import SwiftUI

/// Step 1, File: a drop zone and a file importer, what was read, and the
/// mapping to read it with: a saved profile or a proposed one. On iPhone
/// this is "Import with profile…", with a way into every step.
struct ImportFileStep: View {
    let model: ImportController
    let chooseFile: () -> Void
    let openFile: (URL) -> Void
    /// Reads several files dropped at once (journals); `nil` reads the first.
    var openFiles: (([URL]) -> Void)?

    @Environment(LibraryStore.self) private var library
    @State private var isTargeted = false

    var body: some View {
        let flow = model.flow
        Form {
            Section {
                ImportDropZone(fileName: flow.fileName, isTargeted: isTargeted, chooseFile: chooseFile)
            } footer: {
                Text("A CSV or TSV file, as Excel, Numbers or a bank exports it: any delimiter, encoding, date and "
                    + "number format. Or ledger-cli and hledger journals: choose one or several.")
            }

            if let problem = flow.problem, !flow.hasFile {
                Section {
                    StatusBanner(.error, "The file can't be read", message: problem)
                }
            }

            if flow.hasFile {
                Section("File") {
                    LabeledContent("Name", value: flow.fileName ?? "")
                    LabeledContent("Read as", value: flow.tableSummary)
                    if let first = flow.preview?.firstDate, let last = flow.preview?.lastDate {
                        LabeledContent("Dates",
                                       value: "\(AmountFormat.mediumDate(first)) – \(AmountFormat.mediumDate(last))")
                    }
                }
                mappingSection(flow)
            }

            if flow.isGuided {
                Section {
                    Button("Set Up the Columns Step by Step") {
                        model.flow.setGuided(false)
                    }
                } footer: {
                    Text("For a file no saved profile fits. There's more room for the table on a Mac or an iPad, "
                        + "and you can save the mapping as a profile at the end.")
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
            guard let url = urls.first else { return false }
            if let openFiles { openFiles(urls) } else { openFile(url) }
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }

    /// The saved profiles, best fit first, and (except on iPhone's "Import
    /// with profile…") a mapping the importer proposes.
    private func mappingSection(_ flow: ImportFlow) -> some View {
        Section {
            if !flow.isGuided {
                ImportChoiceRow(title: "Propose a new mapping",
                                detail: "The importer reads the headers and values; check them step by step.",
                                isSelected: flow.source == .proposed) {
                    model.flow.useProfile(nil)
                }
            }
            ForEach(flow.profileFits) { fit in
                ImportChoiceRow(title: fit.profile.name, detail: fit.summary,
                                isSelected: flow.source == .profile(fit.profile.id)) {
                    model.flow.useProfile(fit.profile.id)
                }
            }
            if flow.isGuided && flow.profileFits.isEmpty {
                Text("There are no saved profiles yet. Set up this file step by step, and save the mapping as a "
                    + "profile at the end.")
                    .foregroundStyle(Palette.secondaryInk)
            }
        } header: {
            Text(flow.isGuided ? "Import with profile" : "Read it with")
        } footer: {
            Text("A profile is a saved mapping: the next file of the same shape imports in one step.")
        }
    }
}

/// A selectable row: a circle (filled when selected), a title and a detail line.
struct ImportChoiceRow: View {
    let title: String
    let detail: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Palette.accent : Palette.mutedInk)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(Palette.ink)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Where to drop a file, with a button to choose one.
private struct ImportDropZone: View {
    let fileName: String?
    let isTargeted: Bool
    let chooseFile: () -> Void

    var body: some View {
        VStack(spacing: Metrics.m) {
            Image(systemName: fileName == nil ? "square.and.arrow.down" : "doc.text")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
            Text(fileName ?? "Drop a spreadsheet export here")
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            Button(fileName == nil ? "Choose File…" : "Choose Another File…", action: chooseFile)
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

#Preview("File") {
    NavigationStack {
        ImportPreviewHost(step: .file)
    }
    .previewEnvironment()
}

#Preview("Import with profile") {
    NavigationStack {
        ImportPreviewHost(step: .file, guided: true)
    }
    .previewEnvironment()
}
