import Model
import Prices
import SwiftUI
import Tracker

/// The monthly check-in (UI.md, "Check-in"): the flow that has to be fast.
///
/// - **iPhone** (a full-screen cover, in a NavigationStack) and iPad: one
///   scrolling page (``CheckInList``), with Review pushed on top.
/// - **Mac** (the sidebar's Check-in page): a table (``CheckInTable``) with
///   the date and prices in the toolbar; Review opens as a sheet (⌘↩).
///
/// An unfinished check-in is a draft in `CheckInStore`, kept on this device
/// and resumed here; Cancel asks whether to keep it or throw it away. After
/// saving, the confirmation ends with this month's answer. Close with
/// `navigation.finishCheckIn()`, which works in both layouts.
struct CheckInScreen: View {
    @Environment(CheckInStore.self) private var checkIn
    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.locale) private var locale
    @State private var session = CheckInSession()

    init() {}

    var body: some View {
        content
            .confirmationDialog("Start over?", isPresented: $session.showsStartOverDialog,
                                titleVisibility: .visible) {
                Button("Start over", role: .destructive) { session.startOver(checkIn: checkIn) }
                Button("Keep what I entered", role: .cancel) {}
            } message: {
                Text("What you entered in this check-in is thrown away, and a new one starts on the suggested date.")
            }
            .navigationTitle("Check-in")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #else
            .navigationSubtitle(subtitle)
            #endif
            .toolbar { toolbar }
            .onAppear { session.appear(checkIn: checkIn, library: library) }
            .confirmationDialog("Keep this check-in for later?", isPresented: $session.showsCancelDialog,
                                titleVisibility: .visible) {
                Button("Keep for later") {
                    session.keepForLater(checkIn: checkIn)
                    close()
                }
                Button("Discard", role: .destructive) {
                    session.discard(checkIn: checkIn)
                    close()
                }
                Button("Continue the check-in", role: .cancel) {}
            } message: {
                Text("A draft stays on this device, and nothing is written to your library until you save.")
            }
            #if os(iOS)
            .navigationDestination(item: $session.page) { page in
                destination(page)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: session.saved)
            #else
            .sheet(item: $session.page) { page in
                NavigationStack {
                    destination(page, isSheet: true)
                }
                .frame(minWidth: 560, minHeight: 620)
            }
            #endif
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let saved = session.saved {
            CheckInConfirmationView(result: saved) { close() }
        } else if session.isSaving {
            VStack(spacing: Metrics.m) {
                ProgressView()
                Text(verbatim: CheckInWording.savingMessage(date: checkIn.draft?.date, in: library.library))
                    .foregroundStyle(Palette.secondaryInk)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.page)
        } else if let draft = checkIn.draft {
            editor(draft)
        } else {
            CheckInStartView(session: session) { close() }
        }
    }

    @ViewBuilder
    private func editor(_ draft: CheckInDraft) -> some View {
        #if os(macOS)
        CheckInTable(draft: draft, session: session)
        #else
        CheckInList(draft: draft, session: session)
        #endif
    }

    @ViewBuilder
    private func destination(_ page: CheckInSession.Page, isSheet: Bool = false) -> some View {
        switch page {
        case .review:
            CheckInReviewView(session: session, isSheet: isSheet)
        case .prices:
            CheckInPriceListView(isSheet: isSheet)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .cancellationAction) {
            cancelButton
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Review") { session.page = .review }
                .fontWeight(.semibold)
                .disabled(checkIn.draft == nil || session.isSaving || session.saved != nil)
        }
        #else
        // On the Mac, primary actions sit after the title: the date and the
        // prices, as in the mockup; Cancel goes to the trailing end.
        ToolbarItemGroup(placement: .primaryAction) {
            if let draft = checkIn.draft, session.saved == nil, !session.isSaving {
                dateButton(draft)
                pricesButton(draft)
            }
        }
        ToolbarItem(placement: .automatic) {
            cancelButton
        }
        #endif
    }

    private var cancelButton: some View {
        Button {
            cancel()
        } label: {
            Text(verbatim: session.saved == nil ? "Cancel" : "Close")
        }
        .disabled(session.isSaving)
    }

    #if os(macOS)
    /// "📅 30 September 2026", opening the date panel.
    private func dateButton(_ draft: CheckInDraft) -> some View {
        Button {
            session.showsDatePicker = true
        } label: {
            Label(AmountFormat.longDate(draft.date, locale: locale), systemImage: "calendar")
        }
        .labelStyle(.titleAndIcon)
        .help("Change the check-in's date")
        .popover(isPresented: $session.showsDatePicker) {
            CheckInDatePanel(date: draft.date, suggested: suggestedDate) { date in
                checkIn.changeDate(to: date)
            }
        }
    }

    /// "✓ Prices and FX updated (4)", opening the price list.
    private func pricesButton(_ draft: CheckInDraft) -> some View {
        let list = CheckInPriceList.make(draft: draft, fetched: checkIn.priceList, library: library.library,
                                       locale: locale)
        let summary = CheckInPriceStatus.make(list, isFetching: checkIn.isFetchingPrices, locale: locale)
        return Button {
            session.page = .prices
        } label: {
            Label {
                Text(verbatim: summary?.title ?? "Prices")
            } icon: {
                CheckInPriceStatusIcon(kind: summary?.kind ?? .updated)
            }
        }
        .labelStyle(.titleAndIcon)
        .help(summary?.subtitle ?? "The prices and exchange rates this check-in uses")
    }

    /// "Draft · kept on this Mac · 7 of 9 reviewed".
    private var subtitle: String {
        guard let draft = checkIn.draft, session.saved == nil else { return "" }
        return "Draft · kept on this Mac · " + CheckInWording.reviewed(draft)
    }
    #endif

    private var suggestedDate: CalendarDate {
        CheckInDraft.suggestedDate(today: .today(), lastCheckIn: library.latestCheckIn)
    }

    // MARK: Actions

    /// Cancel: closes at once when nothing was entered (throwing the empty
    /// draft away), otherwise asks whether to keep the draft for later.
    private func cancel() {
        if session.saved != nil {
            close()
            return
        }
        switch session.cancelOutcome(for: checkIn.draft) {
        case .close:
            if checkIn.draft != nil { session.discard(checkIn: checkIn) }
            close()
        case .ask:
            session.showsCancelDialog = true
        }
    }

    private func close() {
        navigation.finishCheckIn()
    }
}

// MARK: - Start

/// Before a check-in is started: when the last one was recent (it isn't due
/// yet), the library is read-only, or there are no accounts. One clear next
/// step each time.
struct CheckInStartView: View {
    let session: CheckInSession
    let close: () -> Void

    @Environment(CheckInStore.self) private var checkIn
    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.locale) private var locale

    init(session: CheckInSession, close: @escaping () -> Void) {
        self.session = session
        self.close = close
    }

    var body: some View {
        if library.hasNoAccounts {
            ContentUnavailableView {
                Label("No accounts yet", systemImage: AppSymbol.accounts)
            } description: {
                Text("A check-in updates your accounts' values. Add an account or import a spreadsheet first.")
            } actions: {
                Button("Add an account") { addAccount() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!library.canEdit)
                Button("Import a spreadsheet") { importSpreadsheet() }
                    .disabled(!library.canEdit)
            }
            .background(Palette.page)
        } else {
            ScrollView {
                VStack(spacing: Metrics.l) {
                    LibraryStatusBanners()
                    Image(systemName: "calendar")
                        .font(.system(size: 40))
                        .foregroundStyle(Palette.accent)
                        .accessibilityHidden(true)
                    Text(verbatim: title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text(verbatim: message)
                        .foregroundStyle(Palette.secondaryInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        session.start(checkIn: checkIn)
                    } label: {
                        Text("Start a check-in")
                            .fontWeight(.semibold)
                            .frame(maxWidth: 280)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!library.canEdit)
                    if let last = checkIn.status.lastCheckIn {
                        Button {
                            session.start(on: last, checkIn: checkIn)
                        } label: {
                            Text(verbatim: "Update the check-in of " + AmountFormat.shortDate(last, locale: locale))
                        }
                        .buttonStyle(.borderless)
                        .disabled(!library.canEdit)
                    }
                }
                .padding(Metrics.xl)
                .frame(maxWidth: Metrics.readableWidth)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.page)
        }
    }

    private var title: String {
        let status = checkIn.status
        guard let last = status.lastCheckIn else { return "Your first check-in" }
        if status.isDue { return AmountFormat.monthName(status.nextCheckIn, locale: locale) + " check-in" }
        return "You checked in on " + AmountFormat.longDate(last, locale: locale)
    }

    private var message: String {
        let status = checkIn.status
        guard status.lastCheckIn != nil else {
            return "Enter what each account is worth today. It takes a few minutes, and every check-in after it is quicker."
        }
        if status.isDue { return "It's time for this month's check-in: a few minutes, mostly confirming values." }
        return "The next one is on \(AmountFormat.longDate(status.nextCheckIn, locale: locale)). "
            + "Start one now if something changed, or update the last one."
    }

    /// Closes the check-in, then opens the add-account sheet.
    private func addAccount() {
        let navigation = self.navigation
        close()
        Task { @MainActor in
            // On iPhone the check-in is a full-screen cover: let it close first.
            try? await Task.sleep(for: .milliseconds(350))
            navigation.newAccount()
        }
    }

    /// Closes the check-in, then starts an import.
    private func importSpreadsheet() {
        let navigation = self.navigation
        close()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            navigation.startImport()
        }
    }
}

#Preview("Check-in") {
    NavigationStack {
        CheckInScreen()
    }
    .previewEnvironment(model: CheckInPreviewData.model())
}

#Preview("All reviewed") {
    NavigationStack {
        CheckInScreen()
    }
    .previewEnvironment(model: CheckInPreviewData.model(reviewedAll: true))
}

#Preview("Not due") {
    NavigationStack {
        CheckInScreen()
    }
    .previewEnvironment()
}

#Preview("No accounts") {
    NavigationStack {
        CheckInScreen()
    }
    .previewEnvironment(PreviewLibrary.empty)
}
