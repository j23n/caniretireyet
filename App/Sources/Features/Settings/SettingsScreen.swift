import CloudSync
#if FEEDBACK
import FeedbackKit
#endif
import Model
import Prices
import Storage
import SwiftUI

/// Settings (UI.md, "Settings"): the library, you, prices, the check-in
/// reminder and privacy. The Mac shows it in the Settings window (⌘,);
/// iPhone and iPad in a sheet from the Overview's gear.
///
/// "You" is saved in the library (`library.json`); everything else belongs
/// to this device. Present it inside a `NavigationStack`.
struct SettingsScreen: View {
    @Environment(LibraryStore.self) private var library
    @State private var csvExport: LibraryCSVExport?

    init() {}

    var body: some View {
        Form {
            Section {
                LibraryLocationRows()
                NavigationLink("Sync & backups") { SyncScreen() }
                NavigationLink("About the library's files") { LibraryFilesHelp() }
                Button("Export as CSV…") {
                    csvExport = LibraryCSVExport(library: library.library, asOf: library.asOfDate)
                }
                .disabled(library.hasNoAccounts)
            } header: {
                Text("Library")
            } footer: {
                Text(syncSummary)
            }
            YouSection()
            PricesSection()
            ReminderSection()
            PrivacySection()
            #if FEEDBACK
            FeedbackSection()
            #endif
            Section {
                LabeledContent("Version", value: Self.version)
                LabeledContent("Library format", value: "\(library.settings.schemaVersion)")
            } header: {
                Text("About")
            } footer: {
                Text(AboutText.about)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .sheet(item: $csvExport) { LibraryCSVExportSheet(export: $0) }
    }

    private var syncSummary: String {
        switch library.location?.kind {
        case .iCloud?: "Synced with your other devices through iCloud Drive."
        case .local?: "Kept on this device only."
        case nil: ""
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

/// Name, birth date, base currency, country and inflation index, saved
/// in `library.json`.
///
/// Each control writes its own field from its binding's setter, only when
/// you change it (`YouSettings`): opening Settings writes nothing, and a
/// birth date or country that isn't set stays "Not set".
private struct YouSection: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale
    /// The name as typed; `nil` until the field is edited.
    @State private var typedName: String?
    /// Whether the birth date picker is shown before a date is picked.
    @State private var addsBirthDate = false
    @State private var error: String?

    var body: some View {
        let settings = library.settings
        let birthDate = settings.person?.birthDate
        Section {
            TextField("Name", text: nameBinding)
                .onSubmit(saveName)
            Toggle("Birth date", isOn: hasBirthDateBinding)
            if birthDate != nil || addsBirthDate {
                DatePicker("Born", selection: birthDateBinding, in: ...Date(), displayedComponents: .date)
                if birthDate == nil {
                    Text("Not set yet: pick the date to save it.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            Picker("Base currency", selection: currencyBinding) {
                ForEach(CurrencyChoices.common.including(settings.baseCurrency), id: \.self) { code in
                    Text(CurrencyChoices.name(of: code, locale: locale)).tag(code)
                }
            }
            Picker("Country", selection: residenceBinding) {
                Text("Not set").tag(CountryCode?.none)
                ForEach(CountryChoices.common.including(settings.taxResidence), id: \.self) { code in
                    Text(CountryChoices.name(of: code, locale: locale)).tag(Optional(code))
                }
            }
            Picker("Inflation", selection: inflationBinding) {
                Text(InflationIndexText.automaticChoice(YouSettings.automaticInflationIndex(in: library.library),
                                                        locale: locale))
                    .tag(IndexID?.none)
                ForEach(YouSettings.inflationChoices(in: settings, locale: locale), id: \.self) { index in
                    Text(InflationIndexText.choice(index, locale: locale)).tag(Optional(index))
                }
            }
            if let error {
                Text(error).font(.footnote).foregroundStyle(Palette.critical)
            }
        } header: {
            Text("You")
        } footer: {
            Text("Plans use your birth date for ages. The country you live in is the default for new accounts. "
                + YouSettings.inflationExplanation)
        }
        .disabled(!library.canEdit)
        .onDisappear(perform: saveName)
    }

    // MARK: Bindings that write what you change

    private var nameBinding: Binding<String> {
        Binding(get: { typedName ?? library.settings.person?.name ?? "" }, set: { typedName = $0 })
    }

    private var hasBirthDateBinding: Binding<Bool> {
        Binding(
            get: { library.settings.person?.birthDate != nil || addsBirthDate },
            set: { isOn in
                addsBirthDate = isOn
                if !isOn, library.settings.person?.birthDate != nil {
                    write { YouSettings.setting(birthDate: nil, in: $0) }
                }
            })
    }

    private var birthDateBinding: Binding<Date> {
        Binding(
            get: { (library.settings.person?.birthDate ?? YouSettings.suggestedBirthDate()).dateValue },
            set: { date in
                let birth = CalendarDate(date, in: .current)
                guard birth != library.settings.person?.birthDate else { return }
                write { YouSettings.setting(birthDate: birth, in: $0) }
            })
    }

    private var currencyBinding: Binding<CurrencyCode> {
        Binding(
            get: { library.settings.baseCurrency },
            set: { code in
                guard code != library.settings.baseCurrency else { return }
                write { settings in
                    var settings = settings
                    settings.baseCurrency = code
                    return settings
                }
            })
    }

    private var residenceBinding: Binding<CountryCode?> {
        Binding(
            get: { library.settings.taxResidence },
            set: { code in
                guard code != library.settings.taxResidence else { return }
                write { settings in
                    var settings = settings
                    settings.taxResidence = code
                    return settings
                }
            })
    }

    private var inflationBinding: Binding<IndexID?> {
        Binding(
            get: { library.settings.inflationIndex },
            set: { index in
                guard index != library.settings.inflationIndex else { return }
                write { YouSettings.setting(inflationIndex: index, in: $0) }
            })
    }

    /// Writes the typed name, if it was edited and differs from the saved one.
    private func saveName() {
        guard let typedName, library.canEdit, YouSettings.isNameChanged(typedName, in: library.settings) else { return }
        write { YouSettings.setting(name: typedName, in: $0) }
    }

    private func write(_ change: (LibrarySettings) -> LibrarySettings) {
        guard library.canEdit else { return }
        do {
            try library.updateSettings { $0 = change($0) }
            error = nil
        } catch {
            self.error = LibraryStore.describe(error)
        }
    }
}

/// Where prices come from, fetching at check-in, and API keys (in the Keychain).
private struct PricesSection: View {
    @Environment(AppPreferences.self) private var preferences
    @State private var coinGeckoKey = ""
    @State private var keySaved = false

    private static let coinGecko = URL(string: "https://www.coingecko.com")!

    var body: some View {
        @Bindable var preferences = preferences
        Section {
            Toggle("Fetch prices when a check-in opens", isOn: $preferences.fetchPricesOnCheckIn)
            LabeledContent("ETFs and stocks", value: InstrumentForm.name(of: PriceProvider.yahoo))
            LabeledContent("Crypto", value: InstrumentForm.name(of: PriceProvider.coingecko))
            // CoinGecko's free and Demo plans ask for this attribution, linked to its site.
            Link("Powered by CoinGecko", destination: Self.coinGecko)
            LabeledContent("Gold and silver", value: InstrumentForm.name(of: PriceProvider.goldAPI))
            LabeledContent("Exchange rates", value: "ECB, via Frankfurter")
            LabeledContent("Inflation", value: "Eurostat HICP")
            #if canImport(Security)
            SecureField("CoinGecko API key (optional)", text: $coinGeckoKey)
                .onSubmit(saveKey)
            if keySaved {
                Text("Saved in the Keychain on this device.").font(.footnote).foregroundStyle(Palette.secondaryInk)
            }
            #endif
        } header: {
            Text("Prices")
        } footer: {
            Text("Each instrument names its own price source. Only symbols and dates leave this device; any price can be typed in by hand. "
                + "Yahoo Finance has no official interface for apps, so its prices may stop working without notice.")
        }
        #if canImport(Security)
        .onAppear { coinGeckoKey = KeychainCredentials.read(.coingecko) ?? "" }
        .onDisappear(perform: saveKey)
        #endif
    }

    private func saveKey() {
        #if canImport(Security)
        let trimmed = coinGeckoKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (KeychainCredentials.read(.coingecko) ?? "") else { return }
        KeychainCredentials.write(trimmed, for: .coingecko)
        keySaved = !trimmed.isEmpty
        #endif
    }
}

/// The monthly check-in reminder: this device only. Like "You", each control
/// changes the reminder from its own setter, so opening Settings changes
/// nothing.
private struct ReminderSection: View {
    @Environment(AppPreferences.self) private var preferences
    @State private var notAllowed = false

    var body: some View {
        Section {
            Toggle("Remind me each month", isOn: isOnBinding)
            if preferences.reminder != nil {
                Picker("Day", selection: dayBinding) {
                    Text("Last day of the month").tag(CheckInReminder.lastDay)
                    ForEach(1...28, id: \.self) { day in
                        Text("Day \(day)").tag(day)
                    }
                }
                DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
            }
            if notAllowed {
                Text("Notifications are off for this app. Turn them on in the system settings to get reminders.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
        } header: {
            Text("Check-in reminder")
        } footer: {
            Text("Only on this device, so you aren't reminded twice.")
        }
    }

    private var isOnBinding: Binding<Bool> {
        Binding(get: { preferences.reminder != nil }, set: { apply($0 ? CheckInReminder.standard : nil) })
    }

    private var dayBinding: Binding<Int> {
        Binding(
            get: { preferences.reminder?.day ?? CheckInReminder.lastDay },
            set: { day in
                var reminder = preferences.reminder ?? CheckInReminder.standard
                reminder.day = day
                apply(reminder)
            })
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                let reminder = preferences.reminder ?? CheckInReminder.standard
                return Calendar.current.date(bySettingHour: reminder.hour, minute: reminder.minute, second: 0, of: Date())
                    ?? Date()
            },
            set: { time in
                let components = Calendar.current.dateComponents([.hour, .minute], from: time)
                var reminder = preferences.reminder ?? CheckInReminder.standard
                reminder.hour = components.hour ?? CheckInReminder.standard.hour
                reminder.minute = components.minute ?? CheckInReminder.standard.minute
                apply(reminder)
            })
    }

    private func apply(_ reminder: CheckInReminder?) {
        guard reminder != preferences.reminder else { return }
        preferences.reminder = reminder
        #if canImport(UserNotifications)
        Task {
            let scheduled = await ReminderScheduler.apply(reminder)
            notAllowed = reminder != nil && !scheduled
        }
        #endif
    }
}

/// Hiding amounts.
private struct PrivacySection: View {
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences
        Section {
            Toggle("Hide amounts", isOn: $preferences.hidesAmounts)
            Toggle("Hide amounts when the app opens", isOn: $preferences.hideAmountsOnLaunch)
            #if os(iOS)
            Toggle("Cover the app in the app switcher", isOn: $preferences.hideInAppSwitcher)
            #endif
        } header: {
            Text("Privacy")
        } footer: {
            Text(Self.footer)
        }
    }

    /// What each toggle does; covering the app is only offered on iPhone and iPad.
    private static var footer: String {
        #if os(iOS)
        return "Hidden amounts show as •••••; charts keep their shape. Covering the app hides the whole screen "
            + "while the app isn't active, as in the app switcher."
        #else
        return "Hidden amounts show as •••••; charts keep their shape."
        #endif
    }
}

#if FEEDBACK
/// Sending feedback from the app, in Debug builds (`Feedback.swift`): on or off, the gestures,
/// the token and what's waiting to be sent. Previews have no feedback center.
private struct FeedbackSection: View {
    @Environment(FeedbackCenter.self) private var feedback: FeedbackCenter?

    var body: some View {
        if let feedback {
            FeedbackSettingsSection(center: feedback)
        }
    }
}
#endif

/// What the library folder is and how its files are organised: the README
/// the app writes into it.
private struct LibraryFilesHelp: View {
    var body: some View {
        ScrollView {
            Text(LibraryFolder.readme)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("The library's files")
    }
}

#Preview("Settings") {
    NavigationStack {
        SettingsScreen()
    }
    .previewEnvironment()
}
