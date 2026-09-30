import Foundation
import Importer
import Model
import SwiftUI

/// Step 5, Preview: nothing is written yet. What's in the way, the counts
/// (new, updated, identical, conflicting, skipped) and what importing
/// would do, the conflict policy (keep, overwrite, or decide one by one),
/// notes, the file as a grid with unreadable cells highlighted, and the
/// list of those cells.
struct ImportPreviewStep: View {
    let model: ImportController

    @State private var onlyProblems = false

    var body: some View {
        let flow = model.flow
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.l) {
                LibraryStatusBanners()
                ForEach(flow.blockers, id: \.self) { blocker in
                    StatusBanner(.info, blocker)
                }
                if !flow.ambiguities.isEmpty {
                    Card("To confirm", systemImage: "questionmark.circle") {
                        ForEach(Array(flow.ambiguities.enumerated()), id: \.offset) { _, ambiguity in
                            ImportAmbiguityRow(model: model, ambiguity: ambiguity)
                        }
                    }
                }
                ImportSummaryCard(flow: flow)
                if flow.isGuided {
                    ImportGuidedProposals(model: model)
                }
                ForEach(flow.mappingIssues, id: \.self) { issue in
                    StatusBanner(.warning, issue)
                }
                ForEach(flow.debtNotes, id: \.self) { note in
                    StatusBanner(.info, note, message: "Kept as written? Change it under Accounts, “Debts”.")
                }
                ImportConflictsCard(model: model)
                if flow.isLedger {
                    LedgerNotesCard(notes: flow.ledgerNotes)
                } else {
                    Card {
                        ImportGridView(grid: flow.grid(onlyProblems: onlyProblems))
                    } header: {
                        SectionHeader("The file", systemImage: "tablecells") {
                            Toggle("Only rows with problems", isOn: $onlyProblems)
                                .fixedSize()
                        }
                    }
                    ImportCellErrorsCard(errors: flow.preview?.cellErrors ?? [])
                }
            }
            .padding(Metrics.l)
        }
        .background(Palette.page)
    }
}

/// The counts, and a sentence on what importing would do.
private struct ImportSummaryCard: View {
    let flow: ImportFlow

    var body: some View {
        let summary = flow.preview?.summary ?? ImportSummary()
        Card("Summary", systemImage: "list.bullet.rectangle") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: Metrics.m)], alignment: .leading,
                      spacing: Metrics.m) {
                ImportCountTile(count: summary.newRecords, title: "New")
                ImportCountTile(count: summary.updatedRecords, title: "Updated")
                ImportCountTile(count: summary.identicalRecords, title: "Identical")
                ImportCountTile(count: summary.conflicts, title: "Conflicting")
                ImportCountTile(count: summary.skippedRows + flow.leftOutRecords, title: "Skipped")
                ImportCountTile(count: summary.cellErrors, title: "Can't be read", isProblem: summary.cellErrors > 0)
            }
            Text(flow.plannedSummary)
                .font(.callout)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Updated records get values the library lacks; nothing in them changes. Skipped: title and "
                + "total rows, and records of accounts or instruments you chose not to create.")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One count: a number over its label.
private struct ImportCountTile: View {
    let count: Int
    let title: String
    var isProblem = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Metrics.xs) {
                if isProblem {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Palette.critical)
                        .accessibilityHidden(true)
                }
                Text(verbatim: "\(count)")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
            }
            Text(title)
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// "Import with profile…" has no Accounts step: new accounts, instruments
/// and closings are accepted or rejected here.
private struct ImportGuidedProposals: View {
    let model: ImportController

    var body: some View {
        let preview = model.flow.preview
        let accounts = preview?.newAccounts ?? []
        let instruments = preview?.newInstruments ?? []
        let changes = preview?.accountChanges ?? []
        if !accounts.isEmpty || !instruments.isEmpty || !changes.isEmpty {
            Card("New accounts and changes", systemImage: AppSymbol.accounts) {
                ForEach(accounts, id: \.account.id) { proposal in
                    Toggle(isOn: Binding(get: { proposal.isAccepted }, set: { accepted in
                        model.flow.editNewAccount(proposal.account.id) { $0.isAccepted = accepted }
                    })) {
                        ImportProposalLabel(
                            title: "Create “\(proposal.account.name)”",
                            detail: "\(proposal.account.kind.displayName), \(proposal.account.currency.rawValue)")
                    }
                }
                ForEach(instruments, id: \.instrument.id) { proposal in
                    Toggle(isOn: Binding(get: { proposal.isAccepted }, set: { accepted in
                        model.flow.editNewInstrument(proposal.instrument.id) { $0.isAccepted = accepted }
                    })) {
                        ImportProposalLabel(
                            title: "Create “\(proposal.instrument.name)”",
                            detail: "\(ImportChoices.instrumentKindName(proposal.instrument.kind)), "
                                + proposal.instrument.currency.rawValue)
                    }
                }
                ImportAccountChangeToggles(model: model, changes: changes)
            }
        }
    }
}

private struct ImportProposalLabel: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
        }
    }
}

/// Records that differ from the library: the policy for all of them, and
/// while deciding one by one, each with both values.
private struct ImportConflictsCard: View {
    let model: ImportController

    /// Conflicts listed one by one, at most.
    private static let limit = 100

    var body: some View {
        let flow = model.flow
        let rows = flow.conflictRows()
        if !rows.isEmpty {
            Card("Conflicts", systemImage: "arrow.triangle.branch") {
                Text(rows.count == 1 ? "1 record differs from the library."
                    : "\(rows.count) records differ from the library.")
                    .font(.callout)
                Picker("When a record differs", selection: Binding(get: { model.flow.conflictPolicy },
                                                                   set: { model.flow.setConflictPolicy($0) })) {
                    ForEach([ConflictPolicy.keep, .overwrite, .ask], id: \.self) { policy in
                        Text(ImportChoices.conflictPolicyName(policy)).tag(policy)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if flow.conflictPolicy == .ask {
                    ForEach(Array(rows.prefix(Self.limit))) { row in
                        ImportConflictRowView(model: model, row: row)
                    }
                    if rows.count > Self.limit {
                        Text("And \(rows.count - Self.limit) more.")
                            .font(.footnote)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                    Text("Conflicts left undecided keep the library's values.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
        }
    }
}

/// One conflict: the library's values, the file's, and the decision.
private struct ImportConflictRowView: View {
    let model: ImportController
    let row: ImportConflictRow

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Divider()
            Text(row.title)
                .font(.subheadline.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: Metrics.m, verticalSpacing: 2) {
                GridRow {
                    Text("Library")
                        .foregroundStyle(Palette.secondaryInk)
                    Text(row.existing)
                        .monospacedDigit()
                }
                GridRow {
                    Text("File")
                        .foregroundStyle(Palette.secondaryInk)
                    Text(row.incoming)
                        .monospacedDigit()
                }
            }
            .font(.callout)
            Picker("Decision", selection: Binding(get: { row.resolution }, set: { resolution in
                model.flow.setResolution(resolution, for: row.key)
            })) {
                Text("Undecided").tag(ConflictPolicy.ask)
                Text("Keep the library's").tag(ConflictPolicy.keep)
                Text("Use the file's").tag(ConflictPolicy.overwrite)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

/// The file's rows as a grid: each column's header and what it imports as,
/// ignored columns dimmed, unreadable cells highlighted with the reason.
struct ImportGridView: View {
    let grid: ImportGrid

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            if grid.rows.isEmpty {
                Text(grid.totalRows == 0 && grid.headers.isEmpty ? "No file yet." : "No rows to show.")
                    .foregroundStyle(Palette.secondaryInk)
            } else {
                ScrollView(.horizontal) {
                    Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                        GridRow {
                            Text("Row")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.mutedInk)
                                .padding(.horizontal, Metrics.s)
                            ForEach(Array(grid.headers.enumerated()), id: \.offset) { index, header in
                                ImportGridHeader(header: header, use: grid.uses[index],
                                                 isImported: grid.imported[index])
                            }
                        }
                        Divider()
                        ForEach(grid.rows) { row in
                            GridRow {
                                Text(verbatim: "\(row.number)")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(Palette.mutedInk)
                                    .padding(.horizontal, Metrics.s)
                                ForEach(row.cells) { cell in
                                    ImportGridCell(cell: cell)
                                }
                            }
                        }
                    }
                    .padding(.bottom, Metrics.s)
                }
            }
            if grid.rows.count < grid.totalRows {
                Text("Showing the first \(grid.rows.count) of \(grid.totalRows) rows.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }
}

private struct ImportGridHeader: View {
    let header: String
    let use: String
    let isImported: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(header)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isImported ? Palette.ink : Palette.mutedInk)
            Text(use)
                .font(.caption2)
                .foregroundStyle(isImported ? Palette.accent : Palette.mutedInk)
        }
        .lineLimit(1)
        .padding(.horizontal, Metrics.s)
        .padding(.vertical, Metrics.xs)
        .frame(minWidth: 96, maxWidth: 240, alignment: .leading)
    }
}

private struct ImportGridCell: View {
    let cell: ImportGrid.Cell

    var body: some View {
        HStack(spacing: Metrics.xs) {
            if cell.problem != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(Palette.critical)
            }
            Text(cell.text.isEmpty ? " " : cell.text)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(cell.isImported ? Palette.ink : Palette.mutedInk)
                .lineLimit(1)
        }
        .padding(.horizontal, Metrics.s)
        .padding(.vertical, 5)
        .frame(minWidth: 96, maxWidth: 240, alignment: .leading)
        .background(cell.problem != nil ? Palette.critical.opacity(0.12) : Color.clear)
        .help(cell.problem ?? "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityText))
    }

    private var accessibilityText: String {
        let text = cell.text.isEmpty ? "empty" : cell.text
        guard let problem = cell.problem else { return text }
        return "\(text), can't be read: \(problem)"
    }
}

/// Every cell that can't be read: row, column, what it says and why.
private struct ImportCellErrorsCard: View {
    let errors: [ImportCellError]

    /// Cells listed, at most.
    private static let limit = 200

    private static func columnName(of error: ImportCellError) -> String {
        if let header = error.header { return "“\(header)”" }
        return "column \(error.column)"
    }

    var body: some View {
        if !errors.isEmpty {
            Card(errors.count == 1 ? "1 cell can't be read" : "\(errors.count) cells can't be read",
                 systemImage: "exclamationmark.triangle") {
                ForEach(Array(errors.prefix(Self.limit).enumerated()), id: \.offset) { _, error in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "Row \(error.row) · " + Self.columnName(of: error))
                            .font(.caption)
                            .foregroundStyle(Palette.secondaryInk)
                        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                            Text(error.raw.isEmpty ? "(empty)" : "“\(error.raw)”")
                                .font(.callout.monospaced())
                            Label(error.problem.description, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundStyle(Palette.critical)
                        }
                    }
                }
                if errors.count > Self.limit {
                    Text("And \(errors.count - Self.limit) more.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
                Text("These cells are left out; the rest of their rows is imported. Change the formats in Format or "
                    + "Columns to read them.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview("Preview") {
    NavigationStack {
        ImportPreviewHost(step: .preview)
    }
    .previewEnvironment()
}

#Preview("Preview · with profile") {
    NavigationStack {
        ImportPreviewHost(step: .preview, guided: true)
    }
    .previewEnvironment()
}
