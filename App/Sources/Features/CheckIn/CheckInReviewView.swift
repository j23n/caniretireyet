import Model
import SwiftUI
import Tracker

/// The review before saving (UI.md, "Review screen"): the new net worth and
/// the waterfall since the last check-in (markets, new money, other), the
/// accounts that changed, the accounts whose opening date moves back,
/// anything unusual, then Save. Accounts not reviewed yet are asked about:
/// mark them unchanged, or skip them.
///
/// Pushed on iPhone; a sheet on the Mac, where ⌘↩ saves.
struct CheckInReviewView: View {
    @Bindable var session: CheckInSession
    /// Shown in a sheet (Mac): adds a Back button.
    var isSheet = false

    @Environment(CheckInStore.self) private var checkIn
    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale

    init(session: CheckInSession, isSheet: Bool = false) {
        _session = Bindable(session)
        self.isSheet = isSheet
    }

    var body: some View {
        content
            .navigationTitle("Review")
            .toolbar {
                if isSheet {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back") { session.page = nil }
                            .disabled(session.isSaving)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .confirmationDialog(restTitle, isPresented: $session.showsRestDialog, titleVisibility: .visible) {
                Button("Mark them unchanged and save") { save(rest: .markUnchanged) }
                Button("Skip them and save") { save(rest: .skip) }
                Button("Keep reviewing", role: .cancel) {}
            } message: {
                Text("Unchanged keeps their last values, so they don't go stale. Skipped accounts get no value this time.")
            }
    }

    @ViewBuilder
    private var content: some View {
        if session.isSaving {
            VStack(spacing: Metrics.m) {
                ProgressView()
                Text(verbatim: CheckInWording.savingMessage(date: checkIn.draft?.date, in: library.library))
                    .foregroundStyle(Palette.secondaryInk)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.page)
        } else if let draft = checkIn.draft {
            ScrollView {
                CheckInReviewContent(draft: draft, review: draft.review(in: library.library), session: session) {
                    save()
                }
                .padding(Metrics.l)
                .frame(maxWidth: Metrics.readableWidth)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.page)
        } else {
            ContentUnavailableView("Nothing to review", systemImage: AppSymbol.checkIn,
                                   description: Text("There's no check-in in progress."))
        }
    }

    private var canSave: Bool {
        checkIn.draft != nil && library.canEdit && !session.isSaving
    }

    /// "2 accounts not reviewed".
    private var restTitle: String {
        let count = checkIn.draft?.notReviewed.count ?? 0
        return count == 1 ? "1 account not reviewed" : "\(count) accounts not reviewed"
    }

    /// Saves, first asking about accounts not reviewed yet.
    private func save(rest: CheckInSession.Rest? = nil) {
        guard let draft = checkIn.draft, canSave else { return }
        if rest == nil && !draft.isReadyToSave {
            session.showsRestDialog = true
            return
        }
        Task {
            await session.save(checkIn: checkIn, library: library, rest: rest)
        }
    }
}

/// The review's cards.
private struct CheckInReviewContent: View {
    let draft: CheckInDraft
    let review: CheckInReview
    let session: CheckInSession
    let onSave: () -> Void

    @Environment(CheckInStore.self) private var checkIn
    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.l) {
            LibraryStatusBanners()
            if let error = session.saveError {
                StatusBanner(.error, "Couldn't save the check-in", message: error)
            }
            if !draft.conflicts.isEmpty {
                conflictsCard
            }
            if !draft.isReadyToSave {
                notReviewedCard
            }
            totalCard
            if let change = review.change {
                Card(sinceTitle(change.from)) {
                    WaterfallChart(steps: WaterfallStep.steps(
                        for: change.total, startLabel: AmountFormat.shortDate(change.from, locale: locale),
                        endLabel: AmountFormat.shortDate(change.to, locale: locale)))
                    if !change.unknownFlowAccounts.isEmpty {
                        Text("Accounts with unknown new money count their whole change as \u{201C}other\u{201D}.")
                            .font(.footnote)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                }
            }
            changedCard
            if let note = CheckInWording.openingMovesNote(review.openingMoves, date: draft.date, in: library.library,
                                                          locale: locale) {
                Card("Opening dates") {
                    Label {
                        Text(verbatim: note)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(Palette.accent)
                    }
                }
            }
            if !review.warnings.isEmpty {
                warningsCard
            }
            Button {
                onSave()
            } label: {
                Text("Save check-in")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!library.canEdit || session.isSaving)
        }
    }

    private func sinceTitle(_ date: CalendarDate) -> String {
        "Since " + AmountFormat.shortDate(date, locale: locale)
    }

    // MARK: Cards

    /// Accounts that got a value for this date on another device while the
    /// check-in was open: keep that value, or use the one entered here.
    private var conflictsCard: some View {
        Card("Saved on another device") {
            VStack(alignment: .leading, spacing: Metrics.m) {
                Text("These accounts got a value for this date on another device while this check-in was open. "
                    + "Choose which to keep. Until you do, the saved value stays and yours isn't written.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(draft.conflicts) { row in
                    CheckInConflictRow(row: row, mine: review.row(for: row.account)?.value?.knownValue,
                                       session: session)
                }
            }
        }
    }

    private var notReviewedCard: some View {
        let names = draft.notReviewed.map { library.account($0)?.name ?? $0.rawValue }
        return Card {
            VStack(alignment: .leading, spacing: Metrics.s) {
                Label {
                    Text(verbatim: names.count == 1 ? "1 account not reviewed" : "\(names.count) accounts not reviewed")
                        .font(.headline)
                } icon: {
                    CheckInStateIndicator(state: .notReviewed, size: 18)
                }
                Text(verbatim: names.joined(separator: ", "))
                    .foregroundStyle(Palette.secondaryInk)
                Text("Mark them unchanged to keep their last values, or skip them: then nothing is written and they'll show as stale.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Metrics.s) {
                    Button("Mark unchanged") { session.markRestUnchanged(checkIn: checkIn) }
                        .buttonStyle(.borderedProminent)
                    Button("Skip them") { checkIn.update { CheckInEditing.skipRest(&$0) } }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private var totalCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Metrics.xs) {
                Text("New net worth")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                AmountText(review.netWorth.total, tabular: false, animatesChanges: true)
                    .font(.largeTitle.bold())
                if let change = review.change {
                    HStack(spacing: Metrics.xs) {
                        DeltaText(change.total.change)
                        Text(verbatim: "since " + AmountFormat.shortDate(change.from, locale: locale))
                            .foregroundStyle(Palette.secondaryInk)
                    }
                    .font(.subheadline)
                } else {
                    Text("Your first check-in: the waterfall starts with the next one.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                }
                Text(verbatim: CheckInWording.stateCounts(draft))
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                if CheckInStore.laterCheckIn(than: draft.date, in: library.library) != nil {
                    Text("A past check-in: values saved after it stay as they are, and no answer is recorded for it.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !review.netWorth.isComplete {
                    Label("Some values are missing a price or a rate; see below.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Palette.warning)
                }
            }
        }
    }

    private var changedCard: some View {
        // Rows in conflict write nothing yet: they're in their own card.
        let changed = review.rows.filter { $0.state == .updated && $0.valuation != nil }
        return Card("Changed accounts") {
            if changed.isEmpty {
                Text("No values changed: every account reviewed is unchanged or skipped.")
                    .foregroundStyle(Palette.secondaryInk)
            } else {
                VStack(spacing: Metrics.m) {
                    ForEach(changed) { row in
                        CheckInReviewRow(row: row)
                    }
                }
            }
        }
    }

    private var warningsCard: some View {
        Card("Worth a look") {
            VStack(alignment: .leading, spacing: Metrics.m) {
                ForEach(review.warnings, id: \.self) { warning in
                    CheckInWarningRow(text: CheckInWarningText.make(warning, library: library.library, locale: locale),
                                      session: session)
                }
            }
        }
    }
}

/// An account in conflict: the value saved on the other device and the one
/// entered here, with the choice between them.
private struct CheckInConflictRow: View {
    let row: CheckInRow
    /// The value entered here, in the base currency.
    let mine: Decimal?
    let session: CheckInSession

    @Environment(CheckInStore.self) private var checkIn
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let saved = row.conflict.flatMap { library.valuator.value(of: $0, on: $0.date)?.knownValue }
        VStack(alignment: .leading, spacing: Metrics.xs) {
            Text(verbatim: library.account(row.account)?.name ?? row.account.rawValue)
                .font(.subheadline.weight(.semibold))
            HStack {
                Text("Saved on the other device")
                Spacer(minLength: Metrics.s)
                if let saved {
                    AmountText(saved, precision: .cents)
                }
            }
            .font(.footnote)
            HStack {
                Text("Entered here")
                Spacer(minLength: Metrics.s)
                if let mine {
                    AmountText(mine, precision: .cents)
                }
            }
            .font(.footnote)
            HStack(spacing: Metrics.s) {
                Button("Keep saved") {
                    session.resolveConflict(of: row.account, keepingSaved: true, checkIn: checkIn)
                }
                .buttonStyle(.borderedProminent)
                Button("Use mine") {
                    session.resolveConflict(of: row.account, keepingSaved: false, checkIn: checkIn)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

/// A changed account: its name and new money, its new value and change.
private struct CheckInReviewRow: View {
    let row: CheckInRowReview

    @Environment(LibraryStore.self) private var library

    var body: some View {
        let account = library.account(row.account)
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: account?.name ?? row.account.rawValue)
                HStack(spacing: Metrics.xs) {
                    Text(verbatim: flowTitle(account))
                    if let flow = row.flow {
                        AmountText(flow, currency: account?.currency, precision: .automatic)
                    } else {
                        Text("unknown")
                    }
                }
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
            }
            Spacer(minLength: Metrics.s)
            VStack(alignment: .trailing, spacing: 2) {
                if let value = row.value?.knownValue {
                    AmountText(value)
                }
                if let value = row.value?.knownValue, let previous = row.previousValue {
                    DeltaText(value - previous)
                        .font(.footnote)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func flowTitle(_ account: Account?) -> String {
        let isPension = account?.kind == .pensionFund || account?.kind == .tfr
        return isPension ? "Contributions" : "New money"
    }
}

/// A warning: what's unusual, in calm words, and a way to look at it.
private struct CheckInWarningRow: View {
    let text: CheckInWarningText
    let session: CheckInSession

    @Environment(CheckInStore.self) private var checkIn

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Palette.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Metrics.xs) {
                Text(verbatim: text.title)
                    .font(.subheadline.weight(.semibold))
                Text(verbatim: text.message)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                if let action = text.action, let title = text.actionTitle {
                    actionButton(action, title: title)
                        .font(.footnote.weight(.semibold))
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func actionButton(_ action: CheckInWarningText.Action, title: String) -> some View {
        switch action {
        case .enterFlow(let account):
            Button(title) {
                session.showRow(account, field: .flow(account), opensLater: checkIn.draft?[account]?.opensLater ?? false)
            }
            .buttonStyle(.borderless)
        case .showRow(let account):
            Button(title) {
                let row = checkIn.draft?[account]
                session.showRow(account, field: row.map { CheckInField.primary(for: $0) },
                                opensLater: row?.opensLater ?? false)
            }
            .buttonStyle(.borderless)
        case .openPrices:
            NavigationLink(title) {
                CheckInPriceListView()
            }
            .buttonStyle(.borderless)
        }
    }
}

#Preview("Review") {
    NavigationStack {
        CheckInReviewView(session: CheckInSession())
    }
    .previewEnvironment(model: CheckInPreviewData.model())
}
