import Foundation
import Importer
import Model
import SwiftUI

/// Bank statements' Review (UI.md, "Import"): "Does this look right?" over
/// every file together. What still stops the import comes first, when
/// something does: the library's banners, what's in the way, formats to
/// confirm, a file's balance before its first line, problems reading it.
/// Then what came in and was spent this year, an account's balance against
/// its values (not on the iPhone), a banner for each value the files
/// disagree with, and the accounts the import changes.
struct ImportStatementReview: View {
    let model: ImportController

    @Environment(\.pageLayout) private var layout

    private var isCompact: Bool { !layout.isWide }

    var body: some View {
        let flow = model.flow
        ScrollView {
            VStack(alignment: .leading, spacing: isCompact ? Metrics.s : Metrics.l) {
                header(flow)
                LibraryStatusBanners()
                let batchBlockers = flow.batchBlockers
                ForEach(flow.blockers, id: \.self) { blocker in
                    // Another file's reasons name it.
                    StatusBanner(.info, blocker, personal: batchBlockers.contains(blocker) ? .title : [])
                }
                if !flow.ambiguities.isEmpty {
                    Card("To confirm", systemImage: "questionmark.circle") {
                        ForEach(Array(flow.ambiguities.enumerated()), id: \.offset) { _, ambiguity in
                            ImportAmbiguityRow(model: model, ambiguity: ambiguity)
                        }
                    }
                }
                ForEach(flow.reviewOpeningBalances) { asked in
                    ImportReviewOpeningBalanceCard(model: model, asked: asked)
                }
                ForEach(flow.previewIssues, id: \.self) { issue in
                    StatusBanner(.warning, issue, personal: .title)
                }
                ForEach(flow.debtNotes, id: \.self) { note in
                    StatusBanner(.info, note, message: "Kept as written? Change it under Accounts, “Debts”.",
                                 personal: .title)
                }
                if let charts = flow.statementCharts {
                    ImportStatementChartsCards(charts: charts)
                }
                ImportReviewConflicts(model: model)
                ImportReviewAccounts(flow: flow)
                ImportCellErrorsCard(errors: flow.reviewPreviews.flatMap(\.preview.cellErrors), isStatement: true)
            }
            .padding(.horizontal, isCompact ? Metrics.l : Metrics.xl)
            .padding(.vertical, Metrics.l)
        }
        .background(Palette.page)
    }

    /// "Does this look right?" and what the import does, on the Mac and
    /// iPad; the iPhone's title is the step's, so only the sentence.
    @ViewBuilder
    private func header(_ flow: ImportFlow) -> some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            if !isCompact {
                Text("Does this look right?")
                    .font(.title2.bold())
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(flow.reviewSubtitle(compact: isCompact))
                .font(isCompact ? .subheadline : .callout)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .privacySensitiveInFeedback()
        }
        .padding(.bottom, isCompact ? Metrics.xs : 0)
    }
}

// MARK: - Balance before the first line

/// A statement whose balances need the balance before its first line, or
/// that was given one, with its field.
private struct ImportReviewOpeningBalanceCard: View {
    let model: ImportController
    let asked: ImportReviewOpeningBalance

    var body: some View {
        Card("Balance before the first line", systemImage: asked.isNeeded ? "exclamationmark.triangle" : "banknote") {
            Text(asked.explanation)
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .privacySensitiveInFeedback()
            ImportReviewOpeningBalanceField(model: model, asked: asked)
        }
    }
}

/// The balance typed in, used on Return or with *Use*.
private struct ImportReviewOpeningBalanceField: View {
    let model: ImportController
    let asked: ImportReviewOpeningBalance

    @State private var text = ""

    var body: some View {
        LabeledContent("Balance before the first line") {
            HStack(spacing: Metrics.s) {
                TextField("Balance", text: $text)
                    .multilineTextAlignment(.trailing)
                    .onSubmit(apply)
                Button("Use", action: apply)
                    .disabled(AmountInput.parse(text).value == asked.balance)
            }
        }
        .onAppear {
            text = asked.balance.map { AmountInput.text(for: $0) } ?? ""
        }
    }

    private func apply() {
        switch AmountInput.parse(text) {
        case .empty: model.flow.setStatementOpeningBalance(nil, forFile: asked.file)
        case .value(let value): model.flow.setStatementOpeningBalance(value, forFile: asked.file)
        case .unreadable: break
        }
    }
}

// MARK: - Values that disagree

/// A banner for each value of the library the files disagree with, with
/// *Use the File's* or *Keep Mine*. Past three, the rest fold away, with a
/// choice for all of them.
private struct ImportReviewConflicts: View {
    let model: ImportController

    @State private var showsAll = false

    /// Banners shown before the rest fold away.
    private static let folded = 3

    var body: some View {
        let conflicts = model.flow.reviewConflicts()
        let shown = showsAll ? conflicts : Array(conflicts.prefix(Self.folded))
        ForEach(shown) { conflict in
            ImportConflictBanner(model: model, conflict: conflict)
        }
        if conflicts.count > shown.count {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Metrics.m) { more(conflicts.count - shown.count) }
                VStack(alignment: .leading, spacing: Metrics.s) { more(conflicts.count - shown.count) }
            }
        }
    }

    @ViewBuilder
    private func more(_ count: Int) -> some View {
        Text(count == 1 ? "And 1 more value differs." : "And \(count) more values differ.")
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
        Button("Show All") { showsAll = true }
            .buttonStyle(.borderless)
        Button("Use the File's for All") { model.flow.setConflictPolicy(.overwrite) }
            .buttonStyle(.borderless)
        Button("Keep Mine for All") { model.flow.setConflictPolicy(.keep) }
            .buttonStyle(.borderless)
    }
}

/// One value the files disagree with: the account and day, both balances,
/// and which to keep. On the iPhone, the title over a sentence, and the
/// choice below at full width.
private struct ImportConflictBanner: View {
    let model: ImportController
    let conflict: ImportReviewConflict
    @Environment(\.pageLayout) private var layout
    private var isCompact: Bool { !layout.isWide }

    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if isCompact {
                VStack(alignment: .leading, spacing: Metrics.s) {
                    HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                        icon
                        VStack(alignment: .leading, spacing: 2) {
                            Text(conflict.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                                .privacySensitiveInFeedback()
                            AmountSentenceText(conflict.compactSentence(locale: locale))
                                .font(.footnote)
                                .foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    choice
                        .frame(maxWidth: .infinity)
                }
            } else {
                HStack(alignment: .center, spacing: Metrics.m) {
                    icon
                    VStack(alignment: .leading, spacing: 2) {
                        AmountSentenceText(conflict.headline(locale: locale))
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let detail = conflict.detail(locale: locale) {
                            AmountSentenceText(detail)
                                .font(.footnote)
                                .foregroundStyle(Palette.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: Metrics.s)
                    choice
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, isCompact ? Metrics.m : Metrics.l)
        .padding(.vertical, Metrics.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.warning.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: Metrics.cardRadius / 1.5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius / 1.5, style: .continuous)
                .strokeBorder(Palette.warning.opacity(0.35), lineWidth: 1)
        }
    }

    private var icon: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(Palette.warning)
            .accessibilityHidden(true)
    }

    private var choice: some View {
        Picker("Which to keep", selection: Binding(get: { conflict.usesFile }, set: { usesFile in
            model.flow.setReviewResolution(usesFile: usesFile, for: conflict.key)
        })) {
            Text("Use the File's").tag(true)
            Text("Keep Mine").tag(false)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

// MARK: - Accounts

/// The accounts the import changes: on the Mac and iPad a table of each
/// one's months, its balance on the files' last day and its change since
/// the year began; on the iPhone a list of the balance over the change.
private struct ImportReviewAccounts: View {
    let flow: ImportFlow
    @Environment(\.pageLayout) private var layout
    private var isCompact: Bool { !layout.isWide }

    var body: some View {
        let accounts = flow.reviewAccounts
        if !accounts.isEmpty {
            if isCompact {
                compact(accounts)
            } else {
                table(accounts)
            }
        }
    }

    private func table(_ accounts: [ImportReviewAccount]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: Metrics.m, verticalSpacing: 0) {
            GridRow {
                Text("Account")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Months")
                    .frame(minWidth: 120, alignment: .leading)
                Text(flow.reviewBalanceHeader())
                    .frame(minWidth: 120, alignment: .trailing)
                    .gridColumnAlignment(.trailing)
                    .privacySensitiveInFeedback()
                Text(flow.reviewSinceHeader())
                    .frame(minWidth: 120, alignment: .trailing)
                    .gridColumnAlignment(.trailing)
                    .privacySensitiveInFeedback()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.secondaryInk)
            .padding(.vertical, Metrics.s)
            ForEach(accounts) { account in
                Divider()
                    .gridCellUnsizedAxes(.horizontal)
                GridRow {
                    HStack(spacing: Metrics.s) {
                        Text(account.name)
                            .fontWeight(.semibold)
                            .foregroundStyle(Palette.ink)
                            .privacySensitiveInFeedback()
                        if account.isNew {
                            ImportNewBadge()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(account.monthsText)
                        .foregroundStyle(Palette.secondaryInk)
                        .privacySensitiveInFeedback()
                    amount(account.balance, account.currency)
                    change(account.change, account.currency)
                }
                .font(.callout)
                .padding(.vertical, Metrics.s)
            }
        }
        .padding(.horizontal, Metrics.l)
        .padding(.vertical, Metrics.xs)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1)
        }
    }

    private func compact(_ accounts: [ImportReviewAccount]) -> some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Text(flow.reviewAccountsHeader().uppercased())
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .padding(.horizontal, Metrics.l)
                .padding(.top, Metrics.s)
                .privacySensitiveInFeedback()
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                    if index > 0 {
                        Divider()
                            .padding(.leading, Metrics.l)
                    }
                    HStack(alignment: .center, spacing: Metrics.s) {
                        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                            Text(account.name)
                                .foregroundStyle(Palette.ink)
                                .privacySensitiveInFeedback()
                            if account.isNew {
                                ImportNewBadge()
                            }
                        }
                        Spacer(minLength: Metrics.s)
                        VStack(alignment: .trailing, spacing: 2) {
                            amount(account.balance, account.currency)
                            change(account.change, account.currency)
                                .font(.caption)
                        }
                    }
                    .padding(.horizontal, Metrics.l)
                    .padding(.vertical, Metrics.s + 2)
                }
            }
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    @ViewBuilder
    private func amount(_ value: Decimal?, _ currency: CurrencyCode) -> some View {
        if let value {
            AmountText(value, currency: currency, precision: .cents)
                .foregroundStyle(Palette.ink)
        } else {
            Text(verbatim: "—")
                .foregroundStyle(Palette.mutedInk)
        }
    }

    @ViewBuilder
    private func change(_ value: Decimal?, _ currency: CurrencyCode) -> some View {
        if let value {
            DeltaText(value, currency: currency, precision: .cents)
        } else {
            Text(verbatim: "—")
                .foregroundStyle(Palette.mutedInk)
        }
    }
}

/// "New" after an account the import creates, or gives its first values:
/// a pill on the Mac, accent text on the iPhone.
private struct ImportNewBadge: View {
    @Environment(\.pageLayout) private var layout
    private var isCompact: Bool { !layout.isWide }

    var body: some View {
        if isCompact {
            Text("New")
                .font(.caption)
                .foregroundStyle(Palette.accent)
        } else {
            Text("New")
                .font(.caption)
                .foregroundStyle(Palette.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Palette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
    }
}

// MARK: - The bar at the bottom

/// Review's bar for bank statements: *Remember these banks and senders*,
/// Back and Import on the Mac and iPad; on the iPhone the switch over a
/// wide Import, Back being in the navigation bar.
struct ImportReviewBottomBar: View {
    let model: ImportController
    @Environment(\.pageLayout) private var layout
    private var isCompact: Bool { !layout.isWide }

    @Environment(LibraryStore.self) private var library

    var body: some View {
        @Bindable var model = model
        let flow = model.flow
        let canImport = flow.blockers.isEmpty && !model.isWorking && library.canEdit
        if isCompact {
            VStack(spacing: Metrics.m) {
                Toggle("Remember banks and senders", isOn: $model.remembers)
                Button {
                    Task { await model.runImport(in: library) }
                } label: {
                    Group {
                        if model.isWorking {
                            ProgressView()
                        } else {
                            Text("Import")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canImport)
            }
            .padding(.horizontal, Metrics.l)
            .padding(.vertical, Metrics.m)
            .background(Palette.page)
        } else {
            HStack(spacing: Metrics.m) {
                Toggle("Remember these banks and senders for next time", isOn: $model.remembers)
                    #if os(macOS)
                    .toggleStyle(.checkbox)
                    #endif
                    .fixedSize()
                Spacer(minLength: Metrics.s)
                if model.isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
                if flow.previousStep != nil {
                    Button("Back") {
                        model.flow.goBack()
                    }
                    .disabled(model.isWorking)
                }
                Button("Import") {
                    Task { await model.runImport(in: library) }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canImport)
            }
            .padding(.horizontal, Metrics.l)
            .padding(.vertical, Metrics.m)
            .background(.bar)
        }
    }
}
