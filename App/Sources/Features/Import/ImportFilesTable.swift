import Foundation
import Importer
import Model
import SwiftUI

// MARK: - Mac and iPad

/// The Files step of bank statements on the Mac and iPad (UI.md, "Import"):
/// "Your statements" with what the files are, the table of files, a zone
/// to drop more, and what's between the files. One file looks the same.
struct ImportFilesPage: View {
    let model: ImportController
    let kind: Binding<ImportFilesKind>
    let isTargeted: Bool
    let showReading: (Int) -> Void
    let showDays: (Int) -> Void

    var body: some View {
        let flow = model.flow
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ImportFilesHeader(kind: kind)
                ImportFilesTable(model: model, rows: flow.fileRows(), showReading: showReading, showDays: showDays)
                ImportDropMoreZone(isTargeted: isTargeted)
                ImportBetweenFiles(model: model)
                ImportFirstCheckInCard(model: model)
            }
            .padding(.horizontal, 48)
            .padding(.top, 28)
            .padding(.bottom, Metrics.xl)
        }
    }
}

/// "Your statements", what it's for, and "These files are" with the switch.
private struct ImportFilesHeader: View {
    let kind: Binding<ImportFilesKind>

    var body: some View {
        HStack(alignment: .bottom, spacing: Metrics.xl) {
            VStack(alignment: .leading, spacing: Metrics.xs) {
                Text("Your statements")
                    .font(.title2.bold())
                Text("Every account's CSV at once: a month's or ten years' worth. "
                    + "Each file's account is found for you.")
                    .foregroundStyle(Palette.secondaryInk)
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Text("These files are")
                    .foregroundStyle(Palette.secondaryInk)
                ImportFilesKindPicker(kind: kind, short: false)
                    .fixedSize()
            }
        }
    }
}

/// Bank Statements | Brokerage Transactions.
struct ImportFilesKindPicker: View {
    let kind: Binding<ImportFilesKind>
    /// The iPhone's shorter names.
    let short: Bool

    var body: some View {
        Picker("These files are", selection: kind) {
            ForEach(ImportFilesKind.allCases, id: \.self) { kind in
                Text(short ? kind.shortTitle : kind.title).tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

/// The columns of the files table, as shares of its width: File, Covers,
/// Balance, Account.
private let importFileColumnWeights: [CGFloat] = [2.4, 1.3, 1.3, 2]

/// The files: a card with a line of column titles, then a line per file,
/// and a line per file that can't be read.
private struct ImportFilesTable: View {
    let model: ImportController
    let rows: [ImportFileRow]
    let showReading: (Int) -> Void
    let showDays: (Int) -> Void

    var body: some View {
        let unreadable = model.flow.unreadableFiles
        VStack(spacing: 0) {
            ImportWeightedColumns(weights: importFileColumnWeights) {
                Text("File")
                Text("Covers")
                Text("Balance")
                Text("Account")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.secondaryInk)
            .padding(.horizontal, 18)
            .padding(.vertical, Metrics.s)
            .background(Palette.page.opacity(0.5))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Divider()
            LazyVStack(spacing: 0) {
                ForEach(rows) { row in
                    ImportFileTableRow(model: model, row: row, showReading: showReading, showDays: showDays)
                    if row.id != rows.last?.id || !unreadable.isEmpty {
                        Divider()
                    }
                }
                ForEach(Array(unreadable.enumerated()), id: \.offset) { index, file in
                    ImportUnreadableFileRow(name: file.name, reason: file.reason)
                    if index < unreadable.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        }
    }
}

/// One file: its icon, name, bank and lines (and *How It's Read…* for a
/// bank that isn't known); what it covers; its balance; its account and
/// how it was found, or the question while it has none, tinted; and its menu.
private struct ImportFileTableRow: View {
    let model: ImportController
    let row: ImportFileRow
    let showReading: (Int) -> Void
    let showDays: (Int) -> Void

    var body: some View {
        ImportWeightedColumns(weights: importFileColumnWeights) {
            fileCell
            Text(row.covers ?? "—")
                .foregroundStyle(row.covers == nil ? Palette.mutedInk : Palette.ink)
                .privacySensitiveInFeedback()
            ImportFileBalanceLabel(balance: row.balance)
            accountCell
        }
        .padding(.horizontal, 18)
        .padding(.vertical, Metrics.m)
        .background(row.needsAccount ? Palette.warning.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .contextMenu {
            ImportFileMenuItems(model: model, row: row, showReading: showReading, showDays: showDays)
        }
    }

    private var fileCell: some View {
        HStack(spacing: Metrics.m) {
            ImportCSVIcon()
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.name)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .privacySensitiveInFeedback()
                Text(row.detail)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .privacySensitiveInFeedback()
            }
        }
    }

    private var accountCell: some View {
        let flow = model.flow
        return HStack(alignment: .top, spacing: Metrics.s) {
            VStack(alignment: .leading, spacing: 3) {
                Picker("Account of \(row.name)", selection: Binding(get: { row.account }, set: { account in
                    model.flow.setBatchAccount(account, forFile: row.id)
                })) {
                    Text("Choose…").tag(AccountID?.none)
                    ForEach(flow.statementAccountChoices) { account in
                        Text(account.name).tag(AccountID?.some(account.id))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(minWidth: 150, alignment: .leading)
                .fixedSize()
                .overlay {
                    if row.needsAccount {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Palette.warning, lineWidth: 1)
                            .padding(-1)
                            .background {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(Palette.warning.opacity(0.35), lineWidth: 3)
                                    .padding(-2.5)
                            }
                            .allowsHitTesting(false)
                    }
                }
                .personalControl()
                if row.needsAccount {
                    Text("Which account is this a statement of?")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.warning)
                } else if let source = row.accountSource {
                    Text(source)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                        .privacySensitiveInFeedback()
                }
            }
            Spacer(minLength: 0)
            Menu {
                ImportFileMenuItems(model: model, row: row, showReading: showReading, showDays: showDays)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(Palette.secondaryInk)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More for \(row.name)")
        }
    }
}

/// A file that can't be read: its name and why, across the table.
private struct ImportUnreadableFileRow: View {
    let name: String
    let reason: String

    var body: some View {
        HStack(spacing: Metrics.m) {
            ImportCSVIcon()
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Label("Can't be read: \(reason)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Palette.warning)
                    .lineLimit(2)
            }
            .privacySensitiveInFeedback()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, Metrics.m)
    }
}

/// The Balance cell: "Adds up" with a check, a warning when it doesn't,
/// or "No balance column".
private struct ImportFileBalanceLabel: View {
    let balance: ImportFileBalance?

    var body: some View {
        switch balance {
        case .addsUp?:
            Label {
                Text(ImportFileBalance.addsUp.text)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Palette.positive)
            }
        case .breaks?:
            Label {
                Text(balance?.text ?? "")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(Palette.warning)
        case .noColumn?:
            Text(ImportFileBalance.noColumn.text)
                .foregroundStyle(Palette.secondaryInk)
        case nil:
            Text(verbatim: "—")
                .foregroundStyle(Palette.mutedInk)
        }
    }
}

/// A file's menu: *How It's Read…*, *Days…*, and *Remove*.
struct ImportFileMenuItems: View {
    let model: ImportController
    let row: ImportFileRow
    let showReading: (Int) -> Void
    let showDays: (Int) -> Void

    var body: some View {
        Button("How It's Read…") {
            showReading(row.id)
        }
        Button("Days…") {
            showDays(row.id)
        }
        .disabled(!row.offersDays)
        Divider()
        Button("Remove", role: .destructive) {
            model.flow.remove(file: row.id)
        }
    }
}

/// A page with a folded corner and a green "CSV" badge.
private struct ImportCSVIcon: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Image(systemName: "doc")
                .font(.system(size: 28, weight: .ultraLight))
                .foregroundStyle(Palette.mutedInk)
            Text(verbatim: "CSV")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 2)
                .background(Palette.good, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
                .padding(.bottom, 6)
        }
        .frame(width: 28, height: 34)
        .accessibilityHidden(true)
    }
}

/// Where to drop more statements, under the table.
private struct ImportDropMoreZone: View {
    let isTargeted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.and.arrow.down")
                .accessibilityHidden(true)
            Text("Drop more statements here")
        }
        .foregroundStyle(isTargeted ? Palette.accent : Palette.secondaryInk)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isTargeted ? Palette.accent : Palette.border,
                              style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.5, dash: [6, 4]))
        }
    }
}

/// "Between these files": the transfers paired, with *Show* listing them,
/// and the gaps and overlaps between an account's files, or none.
private struct ImportBetweenFiles: View {
    let model: ImportController

    @State private var showsTransfers = false

    var body: some View {
        let notes = model.flow.betweenFilesNotes()
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.s) {
                Text("Between these files")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.secondaryInk)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(notes) { note in
                        noteRow(note)
                        if case .transfers = note.kind, showsTransfers {
                            ImportPairedTransfersList(transfers: model.flow.pairedTransfers())
                        }
                        if note.id != notes.last?.id {
                            Divider()
                        }
                    }
                }
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 0.5)
                }
            }
        }
    }

    private func noteRow(_ note: ImportBetweenNote) -> some View {
        HStack(spacing: 10) {
            ImportBetweenNoteIcon(note: note, compact: false)
            Group {
                if case .transfers(let count) = note.kind {
                    let transfers = Text(Wording.count(count, "transfer")).fontWeight(.semibold)
                    Text("\(transfers) found in both files and paired: neither spent nor came in.")
                } else {
                    Text(note.text)
                        .foregroundStyle(note.isProblem ? Palette.warning : Palette.ink)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .privacySensitiveInFeedback(note.isProblem)
            if case .transfers = note.kind {
                Button(showsTransfers ? "Hide" : "Show") {
                    withAnimation { showsTransfers.toggle() }
                }
                .importLinkStyle()
            }
        }
        .padding(.horizontal, Metrics.l)
        .padding(.vertical, 10)
    }
}

/// The transfers paired between the files: each one's day, the account it
/// left and the one it reached, and the amount.
private struct ImportPairedTransfersList: View {
    let transfers: [ImportPairedTransfer]

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            ForEach(transfers) { transfer in
                HStack(spacing: Metrics.m) {
                    Text(AmountFormat.mediumDate(transfer.date))
                        .frame(minWidth: 96, alignment: .leading)
                        .privacySensitiveInFeedback()
                    Text("\(transfer.from) → \(transfer.to)")
                        .lineLimit(1)
                        .privacySensitiveInFeedback()
                    Spacer(minLength: Metrics.s)
                    AmountText(transfer.amount, currency: transfer.currency, precision: .cents)
                }
                .font(.callout)
                .foregroundStyle(Palette.secondaryInk)
            }
        }
        .padding(.leading, 42)
        .padding(.trailing, Metrics.l)
        .padding(.bottom, 10)
    }
}

/// A note's icon: the transfer arrows on the Mac (a check on the iPhone),
/// a check when there are no gaps, a warning for a gap or overlap.
private struct ImportBetweenNoteIcon: View {
    let note: ImportBetweenNote
    let compact: Bool

    var body: some View {
        Group {
            switch note.kind {
            case .transfers where !compact:
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(Palette.accent)
            case .gap, .overlap:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.warning)
            default:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Palette.positive)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - iPhone

/// The Files step of bank statements on the iPhone: what the files are,
/// the files with their accounts, *Add Files…*, and what's between them.
struct ImportFilesList: View {
    let model: ImportController
    let kind: Binding<ImportFilesKind>
    let addFiles: () -> Void
    let showReading: (Int) -> Void
    let showDays: (Int) -> Void

    var body: some View {
        let flow = model.flow
        let rows = flow.fileRows()
        let notes = flow.betweenFilesNotes()
        Form {
            Section {
                ImportFilesKindPicker(kind: kind, short: true)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                ForEach(rows) { row in
                    ImportFileCompactRow(model: model, row: row, showReading: showReading)
                        .contextMenu {
                            ImportFileMenuItems(model: model, row: row, showReading: showReading, showDays: showDays)
                        }
                        .swipeActions {
                            Button("Remove", role: .destructive) {
                                model.flow.remove(file: row.id)
                            }
                        }
                }
            } header: {
                Text(flow.displayName ?? "")
            } footer: {
                if let file = flow.batchFileWithoutAccount {
                    Text("Which account is \(file.name) a statement of?")
                        .foregroundStyle(Palette.warning)
                        .privacySensitiveInFeedback()
                }
            }
            let unreadable = flow.unreadableFiles
            if !unreadable.isEmpty {
                Section("Can't be read") {
                    ForEach(Array(unreadable.enumerated()), id: \.offset) { _, file in
                        StatusBanner(.warning, file.name, message: file.reason, personal: .title)
                    }
                }
            }
            Section {
                Button(action: addFiles) {
                    Label("Add Files…", systemImage: "plus.circle.fill")
                }
            }
            if let first = flow.firstCheckIn {
                Section {
                    ImportFirstCheckInPicker(model: model, first: first)
                } header: {
                    Text(ImportFirstCheckInCard.title(first))
                        .privacySensitiveInFeedback()
                } footer: {
                    VStack(alignment: .leading, spacing: Metrics.xs) {
                        Text(verbatim: first.note)
                        if let summary = ImportCheckInCheck.summary(first.before) {
                            AmountSentenceText(summary)
                        }
                    }
                }
                if !first.after.isEmpty {
                    Section("After your first check-in") {
                        ImportAfterFirstCheckIn(checks: first.after)
                    }
                }
            }
            if !notes.isEmpty {
                Section("Between these files") {
                    ForEach(notes) { note in
                        Label {
                            Text(note.shortText)
                                .foregroundStyle(note.isProblem ? Palette.warning : Palette.ink)
                                .privacySensitiveInFeedback(note.isProblem)
                        } icon: {
                            ImportBetweenNoteIcon(note: note, compact: true)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// The statements' days before the library's first check-in (UI.md, "Add
/// past statements"): how often past check-ins are added there, monthly,
/// quarterly or once per file, and what that adds.
struct ImportFirstCheckInCard: View {
    let model: ImportController

    var body: some View {
        if let first = model.flow.firstCheckIn {
            VStack(alignment: .leading, spacing: Metrics.s) {
                HStack(alignment: .center, spacing: Metrics.l) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.title(first))
                            .font(.headline)
                            .privacySensitiveInFeedback()
                        Text("How often should past check-ins be added?")
                            .foregroundStyle(Palette.secondaryInk)
                    }
                    Spacer(minLength: Metrics.s)
                    ImportFirstCheckInPicker(model: model, first: first)
                        .fixedSize()
                }
                Text(verbatim: first.note)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                if !first.before.isEmpty {
                    ImportCheckInChecks(checks: first.before)
                }
                if !first.after.isEmpty {
                    Divider()
                        .padding(.vertical, Metrics.xs)
                    Text("After your first check-in")
                        .font(.headline)
                    ImportAfterFirstCheckIn(checks: first.after)
                }
            }
            .padding(Metrics.l)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 0.5)
            }
        }
    }

    /// "Before your first check-in (Jan 2024 – Jan 2026)", or "No
    /// check-ins yet" without one.
    static func title(_ first: ImportFirstCheckIn, locale: Locale = .current) -> String {
        guard let firstCheckIn = first.firstCheckIn else { return "No check-ins yet" }
        let from = first.from.dateValue.formatted(.dateTime.month(.abbreviated).year().locale(locale))
        let through = firstCheckIn.dateValue.formatted(.dateTime.month(.abbreviated).year().locale(locale))
        return "Before your first check-in (\(from) – \(through))"
    }
}

/// The check-ins the files add before the first, a row each, with how
/// many lines lead to it and whether they add up; then how many do.
private struct ImportCheckInChecks: View {
    let checks: [ImportCheckInCheck]

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            ForEach(checks) { check in
                HStack(spacing: Metrics.s) {
                    Image(systemName: check.off == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(check.off == nil ? Palette.good : Palette.warning)
                        .accessibilityHidden(true)
                    Text(verbatim: check.title(locale: locale))
                        .frame(minWidth: 80, alignment: .leading)
                        .privacySensitiveInFeedback()
                    AmountSentenceText(check.status(locale: locale))
                        .foregroundStyle(check.off == nil ? Palette.secondaryInk : Palette.warning)
                    Spacer(minLength: 0)
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
            }
            if let summary = ImportCheckInCheck.summary(checks, locale: locale) {
                AmountSentenceText(summary)
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, Metrics.xs)
            }
        }
    }
}

/// The library's check-ins the files reach: they stay as they are, the
/// lines fill them in, and how many add up.
private struct ImportAfterFirstCheckIn: View {
    let checks: [ImportCheckInCheck]

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            AmountSentenceText(intro)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            if let summary = ImportCheckInCheck.summary(checks, locale: locale) {
                AmountSentenceText(summary)
                    .foregroundStyle(checks.contains { $0.off != nil } ? Palette.warning : Palette.good)
            }
        }
    }

    /// "Feb – Sep 2026: your 8 check-ins stay as they are. …"
    private var intro: AmountSentence {
        let count = Wording.count(checks.count, "check-in")
        var sentence: AmountSentence = ""
        if let first = checks.first, let last = checks.last {
            sentence += "\(first.title(locale: locale)) – \(last.title(locale: locale)): "
        }
        sentence += "your \(count) stay as they are. The lines fill in what came in and went out between them."
        return sentence
    }
}

/// Monthly | Quarterly | Once per File.
private struct ImportFirstCheckInPicker: View {
    let model: ImportController
    let first: ImportFirstCheckIn

    var body: some View {
        Picker("How often to add past check-ins", selection: Binding(get: { first.ends }, set: { ends in
            model.flow.setFirstCheckInEnds(ends)
        })) {
            Text("Monthly").tag(StatementCheckIns.Ends.months)
            Text("Quarterly").tag(StatementCheckIns.Ends.quarters)
            Text("Once per File").tag(StatementCheckIns.Ends.never)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .disabled(model.isWorking)
    }
}

/// One file on the iPhone: its name and account (or "Choose Account" in
/// the warning color), what it covers and how its account was found, and
/// *How It's Read…* for a bank that isn't known.
private struct ImportFileCompactRow: View {
    let model: ImportController
    let row: ImportFileRow
    let showReading: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Menu {
                Picker("Account of \(row.name)", selection: Binding(get: { row.account }, set: { account in
                    model.flow.setBatchAccount(account, forFile: row.id)
                })) {
                    Text("Choose…").tag(AccountID?.none)
                    ForEach(model.flow.statementAccountChoices) { account in
                        Text(account.name).tag(AccountID?.some(account.id))
                    }
                }
            } label: {
                HStack(spacing: Metrics.s) {
                    Text(verbatim: row.name)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: Metrics.s)
                    if row.needsAccount {
                        HStack(spacing: Metrics.xs) {
                            Text("Choose Account")
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                        }
                        .foregroundStyle(Palette.warning)
                    } else {
                        Text(verbatim: row.accountName ?? "")
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .personalControl()
            .accessibilityLabel(row.needsAccount ? "Choose the account of \(row.name)" : "Account of \(row.name)")
            Text(row.compactDetail)
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .privacySensitiveInFeedback()
            if row.showsReadingLink {
                Button("How It's Read…") {
                    showReading(row.id)
                }
                .buttonStyle(.borderless)
                .font(.subheadline)
                .padding(.top, Metrics.xs)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Layout

/// Its children side by side, each a share of the width by its weight,
/// centered on the row's height: the Files table's columns. Like
/// ``EqualColumns``, the columns never depend on what the children would
/// like to be.
struct ImportWeightedColumns: Layout {
    var weights: [CGFloat]
    var spacing: CGFloat = Metrics.l
    /// The width when the parent offers none.
    private static let fallbackWidth: CGFloat = 800

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? Self.fallbackWidth
        let widths = columnWidths(width, count: subviews.count)
        let height = zip(subviews, widths).map { subview, width in
            subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = columnWidths(bounds.width, count: subviews.count)
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths) {
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: width, height: nil))
            x += width + spacing
        }
    }

    private func columnWidths(_ width: CGFloat, count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        let used = (0..<count).map { $0 < weights.count ? weights[$0] : 1 }
        let total = used.reduce(0, +)
        let free = max(0, width - spacing * CGFloat(count - 1))
        return used.map { total > 0 ? free * $0 / total : 0 }
    }
}

extension View {
    /// A button that reads as a link: the Mac's link style, a borderless
    /// button on iPhone and iPad.
    func importLinkStyle() -> some View {
        #if os(macOS)
        buttonStyle(.link)
        #else
        buttonStyle(.borderless)
        #endif
    }
}
