import Model
import Prices
import SwiftUI
import Tracker

/// The monthly check-in (UI.md, "Check-in"). It's import-led: this
/// month's files are imported, each written with its own backup, and the
/// page shows what they did. Accounts that take typed values are listed
/// apart, each with *Update* to type its balance on the check-in's date.
/// Then *Save* writes the prices fetched for the date and records this
/// month's answer.
///
/// - **iPhone** a full-screen cover, in a NavigationStack, with the price
///   list pushed on top.
/// - **iPad and Mac** the sidebar's Check-in page, with the price list in a
///   sheet.
///
/// The import opens in a sheet for the check-in's date (`ImportScreen`).
/// After saving, the confirmation ends with this month's answer. Close with
/// `navigation.finishCheckIn()`, which works in both layouts.
struct CheckInScreen: View {
    @Environment(CheckInStore.self) private var checkIn
    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigation.self) private var navigation
    @State private var hasAppeared = false
    @State private var showsImport = false
    @State private var showsPrices = false
    @State private var showsDatePicker = false
    @State private var isSaving = false
    @State private var saved: CheckInSaveResult?
    @State private var saveError: String?

    init() {}

    var body: some View {
        content
            .navigationTitle("Check-in")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showsPrices) {
                CheckInPriceListView()
            }
            .sensoryFeedback(.impact(weight: .light), trigger: saved)
            #else
            .sheet(isPresented: $showsPrices) {
                NavigationStack {
                    CheckInPriceListView(isSheet: true)
                }
                .frame(minWidth: 560, minHeight: 620)
            }
            #endif
            .toolbar { toolbar }
            .onAppear(perform: appear)
            .sheet(isPresented: $showsImport, onDismiss: { checkIn.begin() }) {
                if let date = checkIn.date {
                    NavigationStack {
                        ImportScreen(checkIn: date) { showsImport = false }
                    }
                    #if os(macOS)
                    .frame(minWidth: 900, minHeight: 640)
                    #endif
                }
            }
            .sheet(isPresented: $showsDatePicker) {
                if let date = checkIn.date {
                    CheckInDatePanel(date: date, suggested: checkIn.suggestedDate) { picked in
                        checkIn.begin(on: picked)
                    }
                    .presentationDetents([.medium, .large])
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let saved {
            CheckInConfirmationView(result: saved) { close() }
        } else if isSaving {
            CheckInSavingView()
        } else if let summary = checkIn.summary {
            CheckInPage(summary: summary, saveError: $saveError, showsImport: $showsImport,
                        showsPrices: $showsPrices, showsDatePicker: $showsDatePicker)
        } else {
            CheckInStartView { date in start(on: date) }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(saved == nil ? "Cancel" : "Close") { cancel() }
                .disabled(isSaving)
        }
        if saved == nil, checkIn.date != nil {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(isSaving || !library.canEdit)
            }
        }
    }

    // MARK: Actions

    /// The first appearance opens the check-in that's open, fetching its
    /// prices again, or a new one when it's due.
    private func appear() {
        guard !hasAppeared else { return }
        hasAppeared = true
        guard library.canEdit, !library.hasNoAccounts else { return }
        if checkIn.date != nil || checkIn.status.isDue { checkIn.begin() }
    }

    private func start(on date: CalendarDate?) {
        saved = nil
        saveError = nil
        checkIn.begin(on: date)
    }

    private func save() {
        isSaving = true
        saveError = nil
        Task {
            do {
                saved = try await checkIn.save()
            } catch {
                saveError = error.localizedDescription
            }
            isSaving = false
        }
    }

    /// Closes the check-in. What its imports wrote stays; only the fetched
    /// prices are dropped.
    private func cancel() {
        if saved == nil { checkIn.cancel() }
        navigation.finishCheckIn()
    }

    private func close() {
        navigation.finishCheckIn()
    }
}

// MARK: - The page

/// The open check-in: its date, the way to this month's files, the prices,
/// net worth with the change since the previous check-in, the accounts
/// whose values you type, with *Update*, and the other accounts, those
/// this month's files updated and those they didn't.
struct CheckInPage: View {
    let summary: CheckInSummary
    @Binding var saveError: String?
    @Binding var showsImport: Bool
    @Binding var showsPrices: Bool
    @Binding var showsDatePicker: Bool

    @Environment(CheckInStore.self) private var checkIn
    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale

    /// *Update Value* for one of the typed accounts, open in a sheet.
    @State private var typing: AccountAction?

    var body: some View {
        let typed = summary.typedAccounts(in: library.library)
        let notUpdated = summary.notUpdated.filter { !typed.contains($0) }
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.l) {
                banners
                dateAndFiles
                prices
                netWorth
                if !typed.isEmpty {
                    typedAccounts(typed)
                }
                accounts(summary.updated.filter { !typed.contains($0) }, title: "Updated",
                         empty: "No file imported for this month yet.")
                if !notUpdated.isEmpty {
                    accounts(notUpdated, title: "Not updated",
                             footer: "No file this month covered these accounts: they keep their last values.")
                }
            }
            .padding(Metrics.l)
            .frame(maxWidth: Metrics.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.page)
        .sheet(item: $typing) { action in
            AccountActionSheet(action: action)
        }
    }

    @ViewBuilder
    private var banners: some View {
        LibraryStatusBanners()
        if let error = saveError {
            StatusBanner(.error, "Couldn't save the check-in", message: error, personal: .message,
                         actionTitle: "Dismiss") {
                saveError = nil
            }
        }
        if let note = CheckInWording.pastCheckInNote(on: summary.date, in: library.library, locale: locale) {
            StatusBanner(.info, "A past check-in", message: note, personal: .message)
        }
    }

    /// "31 October 2026 · Change", and *Import Files…*.
    private var dateAndFiles: some View {
        Card {
            HStack {
                Text(verbatim: AmountFormat.longDate(summary.date, locale: locale))
                    .font(.headline)
                    .privacySensitiveInFeedback()
                Spacer()
                Button("Change Date") { showsDatePicker = true }
                    .buttonStyle(.borderless)
            }
            Text("Import this month's statements and exports. Each import is saved with a backup, and can be undone from the import.")
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showsImport = true
            } label: {
                Label("Import Files…", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!library.canEdit)
        }
    }

    /// "✓ Prices and FX updated (4)", opening the price list.
    @ViewBuilder
    private var prices: some View {
        let list = CheckInPriceList.make(date: summary.date, fetched: checkIn.priceList, library: library.library,
                                         locale: locale)
        if let status = CheckInPriceStatus.make(list, isFetching: checkIn.isFetchingPrices, locale: locale) {
            Button {
                showsPrices = true
            } label: {
                Card {
                    HStack(spacing: Metrics.s) {
                        CheckInPriceStatusIcon(kind: status.kind)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: status.title)
                                .foregroundStyle(Palette.ink)
                            if let subtitle = status.subtitle {
                                Text(verbatim: subtitle)
                                    .font(.footnote)
                                    .foregroundStyle(Palette.secondaryInk)
                                    .lineLimit(2)
                                    .privacySensitiveInFeedback()
                            }
                        }
                        Spacer(minLength: Metrics.s)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.mutedInk)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the prices and exchange rates")
        }
    }

    /// Net worth on the date, and its change since the previous check-in.
    private var netWorth: some View {
        Card("Net worth") {
            AmountText(summary.netWorth.total, tabular: false)
                .font(.largeTitle.bold())
            if let change = summary.change {
                WaterfallChart(change: change.total, from: AmountFormat.shortDate(change.from, locale: locale),
                               to: AmountFormat.shortDate(change.to, locale: locale))
            }
        }
    }

    private func accounts(_ ids: [AccountID], title: String, empty: String? = nil, footer: String? = nil)
        -> some View {
        Card {
            if ids.isEmpty, let empty {
                Text(verbatim: empty)
                    .foregroundStyle(Palette.secondaryInk)
            }
            ForEach(ids, id: \.self) { id in
                HStack {
                    Text(verbatim: library.library.accounts[id]?.name ?? id.rawValue)
                        .lineLimit(1)
                        .privacySensitiveInFeedback()
                    Spacer(minLength: Metrics.s)
                    AmountText(value(of: id))
                }
            }
            if let footer {
                Text(verbatim: footer)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SectionHeader(ids.isEmpty ? title : "\(title) (\(ids.count))")
        }
    }

    /// The accounts whose values you type, each with the date of its
    /// latest value, its value on the date and *Update*, which types its
    /// balance on the check-in's date.
    private func typedAccounts(_ ids: [AccountID]) -> some View {
        Card {
            ForEach(ids, id: \.self) { id in
                HStack(spacing: Metrics.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: library.library.accounts[id]?.name ?? id.rawValue)
                            .lineLimit(1)
                            .privacySensitiveInFeedback()
                        if let latest = library.valuator.latestValuation(for: id, onOrBefore: summary.date) {
                            Text(verbatim: "Last value " + AmountFormat.shortDate(latest.date, locale: locale))
                                .font(.footnote)
                                .foregroundStyle(Palette.secondaryInk)
                                .privacySensitiveInFeedback()
                        }
                    }
                    Spacer(minLength: Metrics.s)
                    AmountText(value(of: id))
                    Button("Update") {
                        typing = AccountAction(.updateValue, id, date: summary.date)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!library.canEdit)
                }
            }
            Text("You type these accounts' values. Update one when its value changed.")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            SectionHeader("Typed by you (\(ids.count))")
        }
    }

    /// What an account is worth on the date, in the base currency.
    private func value(of account: AccountID) -> Decimal {
        summary.netWorth.accounts.first { $0.account == account }?.knownValue ?? 0
    }
}

// MARK: - Start

/// Before a check-in is started: when the last one was recent (it isn't due
/// yet), the library is read-only, or there are no accounts. One clear next
/// step each time.
struct CheckInStartView: View {
    /// Starts a check-in on the date, or the suggested one for `nil`.
    let start: (CalendarDate?) -> Void

    @Environment(CheckInStore.self) private var checkIn
    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.locale) private var locale

    init(start: @escaping (CalendarDate?) -> Void) {
        self.start = start
    }

    var body: some View {
        if library.hasNoAccounts {
            ContentUnavailableView {
                Label("No accounts yet", systemImage: AppSymbol.accounts)
            } description: {
                Text("A check-in imports this month's files into your accounts. Add an account or import a spreadsheet first.")
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
                        start(nil)
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
                            start(last)
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
            return "Import your accounts' statements and exports for this month, then save."
        }
        if status.isDue { return "It's time for this month's check-in: import this month's files, then save." }
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
