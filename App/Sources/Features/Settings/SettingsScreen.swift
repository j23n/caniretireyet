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
            Section("About") {
                LabeledContent("Version", value: Self.version)
                LabeledContent("Library format", value: "\(library.settings.schemaVersion)")
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

/// Name, birth date, base currency and tax residence, saved in `library.json`.
private struct YouSection: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale
    @State private var name = ""
    @State private var birthDate = Date()
    @State private var hasBirthDate = false
    @State private var currency: CurrencyCode = .eur
    @State private var residence: CountryCode = .it
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        Section {
            TextField("Name", text: $name)
                .onSubmit(save)
            Toggle("Birth date", isOn: $hasBirthDate)
            if hasBirthDate {
                DatePicker("Born", selection: $birthDate, in: ...Date(), displayedComponents: .date)
            }
            Picker("Base currency", selection: $currency) {
                ForEach(options(CurrencyChoices.common, current: currency), id: \.self) { code in
                    Text(CurrencyChoices.name(of: code, locale: locale)).tag(code)
                }
            }
            Picker("Tax residence", selection: $residence) {
                ForEach(options(CountryChoices.common, current: residence), id: \.self) { code in
                    Text(CountryChoices.name(of: code, locale: locale)).tag(code)
                }
            }
            if let error {
                Text(error).font(.footnote).foregroundStyle(Palette.critical)
            }
        } header: {
            Text("You")
        } footer: {
            Text("Plans use your birth date for ages. The tax residence is the default for new plans.")
        }
        .disabled(!library.canEdit)
        .onAppear(perform: load)
        .onDisappear(perform: save)
        .onChange(of: birthDate) { save() }
        .onChange(of: hasBirthDate) { save() }
        .onChange(of: currency) { save() }
        .onChange(of: residence) { save() }
    }

    private func options<Code: Hashable>(_ common: [Code], current: Code) -> [Code] {
        common.contains(current) ? common : [current] + common
    }

    private func load() {
        let settings = library.settings
        name = settings.person?.name ?? ""
        hasBirthDate = settings.person?.birthDate != nil
        birthDate = settings.person?.birthDate?.dateValue ?? Calendar.current.date(byAdding: .year, value: -35, to: Date())
            ?? Date()
        currency = settings.baseCurrency
        residence = settings.taxResidence ?? .it
        loaded = true
    }

    private func save() {
        guard loaded, library.canEdit else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let birth = hasBirthDate ? CalendarDate(birthDate, in: .current) : nil
        do {
            try library.updateSettings { settings in
                var person = settings.person ?? Person()
                person.name = trimmed.isEmpty ? nil : trimmed
                person.birthDate = birth
                settings.person = person.name == nil && person.birthDate == nil ? nil : person
                settings.baseCurrency = currency
                settings.taxResidence = residence
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
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
            LabeledContent("Inflation (Italy)", value: "Eurostat HICP")
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

/// The monthly check-in reminder: this device only.
private struct ReminderSection: View {
    @Environment(AppPreferences.self) private var preferences
    @State private var isOn = false
    @State private var day = CheckInReminder.lastDay
    @State private var time = Date()
    @State private var loaded = false
    @State private var notAllowed = false

    var body: some View {
        Section {
            Toggle("Remind me each month", isOn: $isOn)
            if isOn {
                Picker("Day", selection: $day) {
                    Text("Last day of the month").tag(CheckInReminder.lastDay)
                    ForEach(1...28, id: \.self) { day in
                        Text("Day \(day)").tag(day)
                    }
                }
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
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
        .onAppear(perform: load)
        .onChange(of: isOn) { apply() }
        .onChange(of: day) { apply() }
        .onChange(of: time) { apply() }
    }

    private func load() {
        if let reminder = preferences.reminder {
            isOn = true
            day = reminder.day
            time = Calendar.current.date(bySettingHour: reminder.hour, minute: reminder.minute, second: 0, of: Date())
                ?? Date()
        } else {
            time = Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: Date()) ?? Date()
        }
        loaded = true
    }

    private func apply() {
        guard loaded else { return }
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        let reminder = isOn
            ? CheckInReminder(day: day, hour: components.hour ?? 19, minute: components.minute ?? 0) : nil
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
