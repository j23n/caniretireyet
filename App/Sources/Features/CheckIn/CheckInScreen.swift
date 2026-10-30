import Model
import Prices
import SwiftUI
import Tracker

/// The monthly check-in (UI.md, "Check-in"). It's import-led: this
/// month's files are imported, each written with its own backup, and the
/// page shows what they did. Accounts that take typed values are listed
/// to confirm, each with its balance on the check-in's date in a field.
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
    @Environment(\.locale) private var locale
    @State private var hasAppeared = false
    @State private var showsImport = false
    @State private var showsPrices = false
    @State private var showsDatePicker = false
    @State private var isSaving = false
    @State private var saved: CheckInSaveResult?
    @State private var saveError: String?
    @State private var typedEdits = CheckInTypedEdits()

    init() {}

    var body: some View {
        content
            .environment(typedEdits)
            .personalNavigationTitle(title, hidden: "Check-in")
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
                    .presentationDetents([.large])
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
                        showsPrices: $showsPrices)
        } else {
            CheckInStartView { date in start(on: date) }
        }
    }

    /// "Check-in"; "October saved" once it's saved.
    private var title: String {
        guard let saved else { return "Check-in" }
        return "\(AmountFormat.monthName(saved.date, locale: locale)) saved"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(saved == nil ? "Cancel" : "Close") { cancel() }
                .disabled(isSaving)
        }
        if saved == nil, checkIn.summary != nil {
            ToolbarItem(placement: .principal) {
                CheckInTitle(date: checkIn.date) { showsDatePicker = true }
            }
        }
        if saved == nil, checkIn.date != nil {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .buttonStyle(.borderedProminent)
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
        navigation.isCheckInSaved = false
        saveError = nil
        checkIn.begin(on: date)
    }

    private func save() {
        // A typed balance that can't be saved stops here, with the page
        // and its fields as typed.
        do {
            _ = try typedEdits.valuations(today: .today(), locale: locale)
        } catch {
            saveError = error.localizedDescription
            return
        }
        isSaving = true
        saveError = nil
        Task {
            do {
                // The balances typed into fields first: tapping Save
                // doesn't end a field's editing.
                try await typedEdits.saveAll(to: library, locale: locale)
                saved = try await checkIn.save()
                navigation.isCheckInSaved = true
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

/// The check-in's title in the toolbar: "October check-in" over its date,
/// which opens the date picker.
private struct CheckInTitle: View {
    let date: CalendarDate?
    let changeDate: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        if let date {
            Button(action: changeDate) {
                VStack(spacing: 0) {
                    Text(verbatim: "\(AmountFormat.monthName(date, locale: locale)) check-in")
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                    HStack(spacing: 2) {
                        Text(verbatim: AmountFormat.mediumDate(date, locale: locale))
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                }
                .lineLimit(1)
                .privacySensitiveInFeedback()
            }
            .buttonStyle(.plain)
            .accessibilityHint("Changes the check-in's date")
        }
    }
}

/// The open check-in (UI.md, "Check-in"): *Import Files* and the prices
/// side by side, then the accounts by what each needs
/// (Tracker's `CheckInGroups`): the money accounts' months, imported or
/// typed; the trades accounts' months; the values you type, each in a
/// field; and the accounts valued from their files. The month so far
/// shows beside them on the Mac and iPad, above them on iPhone, and net
/// worth so far in a bar at the bottom.
struct CheckInPage: View {
    let summary: CheckInSummary
    @Binding var saveError: String?
    @Binding var showsImport: Bool
    @Binding var showsPrices: Bool

    @Environment(CheckInStore.self) private var checkIn
    @Environment(LibraryStore.self) private var library
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.pageLayout) private var layout
    @Environment(\.locale) private var locale

    /// *Update Value* for one of the typed accounts, open in a sheet.
    @State private var typing: AccountAction?
    /// A money account's month: its CSV to import, or its totals to type.
    @State private var importing: MonthRoute?
    @State private var typingTotals: MonthRoute?
    /// The month whose lines open after its CSV is imported.
    @State private var opened: MonthRoute?

    var body: some View {
        let groups = library.valuator.checkInGroups(on: summary.date, in: library.library)
        let split = summary.change.map { library.valuator.savedSplit(of: $0) }
        let soFar = CheckInSoFar(rate: savingsRate(groups), split: split)
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.l) {
                banners
                actions
                if layout.isRoomy {
                    HStack(alignment: .top, spacing: Metrics.xl) {
                        sections(groups)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        CheckInSoFarCard(soFar: soFar, date: summary.date)
                            .frame(width: 300)
                    }
                } else {
                    CheckInSoFarChips(soFar: soFar, groups: groups)
                    sections(groups)
                }
            }
            .padding(Metrics.l)
            .frame(maxWidth: layout.isRoomy ? Metrics.wideReadableWidth : Metrics.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.page)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            netWorthBar(soFar)
        }
        .sheet(item: $typing) { action in
            AccountActionSheet(action: action)
        }
        .sheet(item: $importing, onDismiss: { checkIn.begin() }) { route in
            MonthImportSheet(route: route) { opened = route }
        }
        .sheet(item: $typingTotals) { route in
            MonthTypedTotalsSheet(route: route)
        }
        .navigationDestination(for: MonthRoute.self) { route in
            MonthLinesScreen(route: route)
        }
        .navigationDestination(for: BrokerageRoute.self) { route in
            BrokerageMonthScreen(route: route)
        }
        .navigationDestination(item: $opened) { route in
            MonthLinesScreen(route: route)
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
        // Worked out when the check-in began: the values it saves on its date make it a saved one.
        let kind = checkIn.dateKind ?? CheckInDateMenu.kind(of: summary.date, in: library.library)
        if let banner = CheckInDateMenu.banner(for: kind, on: summary.date, latest: library.latestCheckIn,
                                               locale: locale) {
            StatusBanner(.info, banner.title, message: banner.message, personal: [.title, .message])
        }
    }

    /// What the month did so far: from the check-in before through this
    /// one's date.
    private func savingsRate(_ groups: CheckInGroups) -> SavingsRate? {
        guard let from = groups.from else { return nil }
        return library.valuator.savingsRate(from: from.adding(days: 1), through: summary.date)
    }

    // MARK: Files and prices

    /// *Import Files* and the prices' status, side by side.
    private var actions: some View {
        let list = CheckInPriceList.make(date: summary.date, fetched: checkIn.priceList, library: library.library,
                                         locale: locale)
        let status = CheckInPriceStatus.make(list, isFetching: checkIn.isFetchingPrices, locale: locale)
        return HStack(spacing: Metrics.m) {
            Button {
                showsImport = true
            } label: {
                Label("Import Files", systemImage: AppSymbol.importData)
                    .foregroundStyle(Palette.accent)
                    .checkInActionSurface()
            }
            .buttonStyle(.plain)
            .disabled(!library.canEdit)
            .accessibilityHint("Imports this month's statements and exports, each with a backup")
            if let status {
                Button {
                    showsPrices = true
                } label: {
                    Label {
                        Text(verbatim: status.shortTitle)
                            .foregroundStyle(status.kind == .updated ? Palette.good : Palette.ink)
                    } icon: {
                        CheckInPriceStatusIcon(kind: status.kind)
                    }
                    .checkInActionSurface()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: status.title))
                .accessibilityHint("Opens the prices and exchange rates")
            }
        }
    }

    // MARK: Accounts

    /// The accounts by what each needs, under how many are done.
    private func sections(_ groups: CheckInGroups) -> some View {
        VStack(alignment: .leading, spacing: Metrics.l) {
            if groups.count > 0 {
                Text(verbatim: CheckInWording.doneCount(groups))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(groups.doneCount == groups.count ? Palette.good : Palette.secondaryInk)
            }
            if !groups.money.isEmpty {
                CheckInSection(title: "Money in and out", footer: "Import a CSV, or type the month's totals.") {
                    ForEach(groups.money) { month in
                        let route = MonthRoute(account: month.account, through: month.through)
                        MonthAccountRow(month: month, importCSV: { importing = route },
                                        typeTotals: { typingTotals = route })
                    }
                }
            }
            if !groups.investments.isEmpty {
                CheckInSection(title: "Investments", footer: "Import the broker's trades, or add them by hand.") {
                    ForEach(groups.investments) { month in
                        BrokerageMonthRow(month: month)
                    }
                }
            }
            if !groups.typed.isEmpty {
                CheckInSection(title: "Values you type",
                               footer: "Type what the statement says, or your estimate.") {
                    ForEach(groups.typed) { typed in
                        if let account = library.library.accounts[typed.account] {
                            CheckInTypedRow(account: account, date: summary.date,
                                            lastValue: lastValue(of: typed.account),
                                            isStale: isStale(typed.account), typed: typed)
                                .contextMenu {
                                    Button("Update Value…") {
                                        typing = AccountAction(.updateValue, typed.account, date: summary.date)
                                    }
                                    .disabled(!library.canEdit)
                                }
                        }
                    }
                }
            }
            if !groups.others.isEmpty {
                CheckInSection(title: "Other accounts",
                               footer: "Valued from their files: Import Files updates them. Those without a "
                                   + "file this month keep their last values.") {
                    ForEach(groups.others, id: \.self) { id in
                        let isUpdated = summary.updated.contains(id)
                        CheckInAccountRow(name: name(of: id), value: value(of: id),
                                          lastValue: isUpdated ? nil : lastValue(of: id),
                                          isStale: !isUpdated && isStale(id), dimmed: !isUpdated)
                    }
                }
            }
        }
    }

    /// "Net worth so far 336.850 € ▲ +4.395 €", and under it what moved
    /// it: "saved 983,69 € · markets +1.307,15 € · lost value −230,00 €".
    /// Pinned to the bottom.
    private func netWorthBar(_ soFar: CheckInSoFar) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                Text("Net worth so far")
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                Spacer(minLength: Metrics.s)
                AmountText(summary.netWorth.total, tabular: false)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .fixedSize()
                if let change = summary.change {
                    DeltaText(change.total.change)
                        .font(.subheadline)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            if summary.change != nil {
                AmountSentenceText(soFar.split(currency: library.baseCurrency, locale: locale))
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, Metrics.xl)
        .padding(.vertical, Metrics.m)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Helpers

    private func name(of account: AccountID) -> String {
        library.library.accounts[account]?.name ?? account.rawValue
    }

    /// What an account is worth on the date, in the base currency.
    private func value(of account: AccountID) -> Decimal {
        summary.netWorth.accounts.first { $0.account == account }?.knownValue ?? 0
    }

    /// "Last value 30 Jun": the date of the account's latest value on or
    /// before the check-in's date.
    private func lastValue(of account: AccountID) -> String? {
        library.valuator.latestValuation(for: account, onOrBefore: summary.date).map { latest in
            "Last value " + AmountFormat.shortDate(latest.date, locale: locale)
        }
    }

    private func isStale(_ account: AccountID) -> Bool {
        AccountStaleness.stale(account, valuator: library.valuator, on: summary.date,
                               threshold: preferences.stalenessThreshold) != nil
    }
}

/// A titled card of the check-in: its title in small capitals above the
/// card, the rows with a hairline between them, and a footnote under it.
private struct CheckInSection<Rows: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder var rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: title)
                .font(.footnote)
                .textCase(.uppercase)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
                .padding(.horizontal, Metrics.xs)
                .accessibilityAddTraits(.isHeader)
            CardRows {
                rows
            }
            if let footer {
                Text(verbatim: footer)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Metrics.xs)
            }
        }
    }
}

/// An account in the check-in: its name over when its last value was (in
/// the warning color when it's stale), and its value on the right, in gray
/// when it only keeps its last value.
private struct CheckInAccountRow: View {
    let name: String
    let value: Decimal
    var lastValue: String?
    var isStale = false
    var dimmed = false

    var body: some View {
        HStack(alignment: .center, spacing: Metrics.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .privacySensitiveInFeedback()
                if let lastValue {
                    Text(verbatim: lastValue)
                        .font(.subheadline)
                        .foregroundStyle(isStale ? Palette.warning : Palette.secondaryInk)
                        .lineLimit(1)
                        .privacySensitiveInFeedback()
                }
            }
            Spacer(minLength: Metrics.s)
            AmountText(value)
                .foregroundStyle(dimmed ? Palette.secondaryInk : Palette.ink)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)
        }
        .padding(.vertical, Metrics.m)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// The surface of the check-in's two buttons at the top: a white card,
    /// half the width each.
    fileprivate func checkInActionSurface() -> some View {
        lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, Metrics.s)
            .padding(.horizontal, Metrics.m)
            .cardSurface()
            .contentShape(Rectangle())
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
