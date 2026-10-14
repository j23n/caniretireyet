import Model
import Prices
import SwiftUI
import Tracker
import UniformTypeIdentifiers

/// The monthly check-in (UI.md, "Check-in"): the flow that has to be fast.
///
/// - **iPhone** (a full-screen cover, in a NavigationStack) and iPad: one
///   scrolling page (``CheckInList``), with Review pushed on top.
/// - **Mac** (the sidebar's Check-in page): a table (``CheckInTable``) with
///   the date as the window's subtitle, whose title menu changes it or
///   cancels the check-in, and the prices in the middle of the toolbar;
///   Review opens as a sheet (⌘↩).
///
/// An unfinished check-in is a draft in `CheckInStore`, kept on this device
/// and resumed here; Cancel asks whether to keep it or throw it away. The
/// bank statements it holds (UI.md, "Statements first") open in a sheet
/// over it, on the import's steps, and are dropped on Cancel. After saving,
/// the confirmation ends with this month's answer. Close with
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
            .personalNavigationSubtitle(subtitle)
            .toolbarTitleMenu { titleMenu }
            .sheet(isPresented: $session.showsDatePicker) {
                if let draft = checkIn.draft {
                    CheckInDatePanel(date: draft.date, suggested: checkIn.suggestedDate) { date in
                        checkIn.changeDate(to: date)
                    }
                }
            }
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
                Text(verbatim: checkIn.statements == nil
                    ? "A draft stays on this device, and nothing is written to your library until you save."
                    : "A draft stays on this device without its statements, which you add again. Nothing is "
                        + "written to your library until you save.")
            }
            .fileImporter(isPresented: $session.choosesStatements, allowedContentTypes: ImportFileReader.contentTypes,
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    Task { await session.addStatements(from: urls, checkIn: checkIn) }
                case .failure(let error):
                    session.statementsError = error.localizedDescription
                }
            }
            .sheet(isPresented: $session.showsStatements, onDismiss: { checkIn.refresh() }) {
                if let held = checkIn.statements {
                    NavigationStack {
                        ImportScreen(statements: held) { session.showsStatements = false }
                    }
                    #if os(macOS)
                    .frame(minWidth: 900, minHeight: 640)
                    #endif
                }
            }
            .alert("Note", isPresented: showsNoteEditor) {
                TextField("Note", text: $session.noteText)
                Button("Save") { session.saveNote(checkIn: checkIn) }
                Button("Cancel", role: .cancel) { session.noteRequest = nil }
            } message: {
                Text("Saved with the account's value on this date.")
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
            CheckInSavingView()
        } else if let draft = checkIn.draft {
            editor(draft)
        } else {
            CheckInStartView(session: session)
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
                .disabled(checkIn.draft == nil || session.isSaving || session.saved != nil || asksForStatements)
        }
        #else
        // On the Mac, the prices sit in the middle; the date is the subtitle,
        // and the title menu changes it or cancels the check-in. The page is
        // left through the sidebar.
        ToolbarItem(placement: .principal) {
            if let draft = checkIn.draft, session.saved == nil, !session.isSaving {
                pricesButton(draft)
            }
        }
        #endif
    }

    #if os(iOS)
    /// Whether the card that asks for the statements shows: Review waits
    /// until they're added or the card is put away.
    private var asksForStatements: Bool {
        guard let draft = checkIn.draft, library.canEdit else { return false }
        return checkIn.heldStatements(for: draft).showsStart(dismissed: session.typesEveryValue)
    }
    #endif

    /// Shows the alert that writes a row's note.
    private var showsNoteEditor: Binding<Bool> {
        Binding {
            session.noteRequest != nil
        } set: { shows in
            if !shows { session.noteRequest = nil }
        }
    }

    #if os(iOS)
    private var cancelButton: some View {
        Button {
            cancel()
        } label: {
            Text(verbatim: session.saved == nil ? "Cancel" : "Close")
        }
        .disabled(session.isSaving)
    }
    #endif

    #if os(macOS)
    /// The title's menu: *Change Date…* and *Cancel Check-in…*.
    @ViewBuilder
    private var titleMenu: some View {
        if checkIn.draft != nil, session.saved == nil, !session.isSaving {
            Button("Change Date…") { session.showsDatePicker = true }
            Divider()
            Button("Cancel Check-in…") { cancel() }
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

    /// "30 September 2026", the check-in's date.
    private var subtitle: String {
        guard let draft = checkIn.draft, session.saved == nil else { return "" }
        return AmountFormat.longDate(draft.date, locale: locale)
    }
    #endif

    // MARK: Actions

    /// Cancel: closes at once when nothing was entered (throwing the empty
    /// draft away), otherwise asks whether to keep the draft for later.
    private func cancel() {
        if session.saved == nil, let draft = checkIn.draft {
            guard !CheckInEditing.hasEdits(draft, holdsStatements: checkIn.statements != nil) else {
                session.showsCancelDialog = true
                return
            }
            session.discard(checkIn: checkIn)
        }
        close()
    }

    private func close() {
        navigation.finishCheckIn()
    }
}

extension CheckInSession {
    /// Reads the files chosen with *Add Statements…* or dropped on the
    /// statements, and adds them to the check-in
    /// (``addStatements(_:failures:checkIn:)``). A file that can't be read
    /// is said so; the others are added.
    func addStatements(from urls: [URL], checkIn: CheckInStore) async {
        guard !urls.isEmpty else { return }
        var files: [(name: String, data: Data)] = []
        var failures: [String] = []
        for url in urls {
            do {
                let data = try await ImportFileReader.read(url)
                files.append((url.lastPathComponent, data))
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        addStatements(files, failures: failures, checkIn: checkIn)
    }
}

// MARK: - Start

/// Before a check-in is started: when the last one was recent (it isn't due
/// yet), the library is read-only, or there are no accounts. One clear next
/// step each time.
struct CheckInStartView: View {
    let session: CheckInSession

    @Environment(CheckInStore.self) private var checkIn
    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.locale) private var locale

    init(session: CheckInSession) {
        self.session = session
    }

    var body: some View {
        if library.hasNoAccounts {
            ContentUnavailableView {
                Label("No accounts yet", systemImage: AppSymbol.accounts)
            } description: {
                Text("A check-in updates your accounts' values. Add an account or import a spreadsheet first.")
            } actions: {
                Button("Add an account") { navigation.finishCheckIn { $0.newAccount() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!library.canEdit)
                Button("Import…") { navigation.finishCheckIn { $0.startImport() } }
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
                        .privacySensitiveInFeedback()
                    Text(verbatim: message)
                        .foregroundStyle(Palette.secondaryInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .privacySensitiveInFeedback()
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
                        .personalControl()
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
}

#Preview("Check-in") {
    NavigationStack {
        CheckInScreen()
    }
    .appEnvironment(CheckInPreviewData.model())
}

#Preview("All reviewed") {
    NavigationStack {
        CheckInScreen()
    }
    .appEnvironment(CheckInPreviewData.model(reviewedAll: true))
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

#Preview("With statements") {
    NavigationStack {
        CheckInScreen()
    }
    .appEnvironment(CheckInPreviewData.modelWithStatements())
}
