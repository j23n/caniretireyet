import CloudSync
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

    init() {}

    var body: some View {
        Form {
            Section {
                LibraryLocationRows()
                NavigationLink("Sync & backups") { SyncScreen() }
                NavigationLink("About the library's files") { LibraryFilesHelp() }
            } header: {
                Text("Library")
            } footer: {
                Text(syncSummary)
            }
            YouSection()
            PricesSection()
            ReminderSection()
            PrivacySection()
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

/// Name, birth date, base currency, tax residence and inflation index, saved
/// in `library.json`.
///
/// Each control writes its own field from its binding's setter, only when
/// you change it (`YouSettings`): opening Settings writes nothing, and a
/// birth date or tax residence that isn't set stays "Not set".
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
            CitizenshipRows(settings: settings) { change in write(change) }
            Picker("Base currency", selection: currencyBinding) {
                ForEach(options(CurrencyChoices.common, current: settings.baseCurrency), id: \.self) { code in
                    Text(CurrencyChoices.name(of: code, locale: locale)).tag(code)
                }
            }
            Picker("Tax residence", selection: residenceBinding) {
                Text("Not set").tag(CountryCode?.none)
                ForEach(options(CountryChoices.common, current: settings.taxResidence), id: \.self) { code in
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
            Text("Plans use your birth date for ages. The tax residence is the default for new plans. "
                + YouSettings.citizenshipExplanation + " " + YouSettings.inflationExplanation)
        }
        .disabled(!library.canEdit)
        .onDisappear(perform: saveName)
    }

    private func options<Code: Hashable>(_ common: [Code], current: Code?) -> [Code] {
        guard let current, !common.contains(current) else { return common }
        return [current] + common
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

    var body: some View {
        @Bindable var preferences = preferences
        Section {
            Toggle("Fetch prices when a check-in opens", isOn: $preferences.fetchPricesOnCheckIn)
            LabeledContent("ETFs and stocks", value: "Yahoo Finance")
            LabeledContent("Crypto", value: "CoinGecko")
            LabeledContent("Gold and silver", value: "gold-api.com")
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
            Text("Each instrument names its own price source. Only symbols and dates leave this device; any price can be typed in by hand.")
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

    /// Without a reminder: the last day of the month at 19:00.
    private static let standard = CheckInReminder(day: CheckInReminder.lastDay, hour: 19, minute: 0)

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
        Binding(get: { preferences.reminder != nil }, set: { apply($0 ? Self.standard : nil) })
    }

    private var dayBinding: Binding<Int> {
        Binding(
            get: { preferences.reminder?.day ?? CheckInReminder.lastDay },
            set: { day in
                var reminder = preferences.reminder ?? Self.standard
                reminder.day = day
                apply(reminder)
            })
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                let reminder = preferences.reminder ?? Self.standard
                return Calendar.current.date(bySettingHour: reminder.hour, minute: reminder.minute, second: 0, of: Date())
                    ?? Date()
            },
            set: { time in
                let components = Calendar.current.dateComponents([.hour, .minute], from: time)
                var reminder = preferences.reminder ?? Self.standard
                reminder.hour = components.hour ?? 19
                reminder.minute = components.minute ?? 0
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
    @Environment(PrivacySettings.self) private var privacy

    var body: some View {
        @Bindable var privacy = privacy
        Section {
            Toggle("Hide amounts", isOn: $privacy.hidesAmounts)
            Toggle("Hide amounts when the app opens", isOn: $privacy.hideAmountsOnLaunch)
            #if os(iOS)
            Toggle("Cover the app in the app switcher", isOn: $privacy.hideInAppSwitcher)
            #endif
        } header: {
            Text("Privacy")
        } footer: {
            Text("Hidden amounts show as •••••; charts keep their shape. Widgets and the app switcher hide amounts while the device is locked.")
        }
    }
}

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
