import Glance
import Model
import SwiftUI

/// Settings › Notifications (UI.md, "Notifications"): the monthly note on a
/// day and at a time you choose, and the yearly notes. This device only.
/// Each control changes the settings from its own setter, so opening the
/// page changes nothing; turning a note on asks for permission first, and
/// when notifications aren't allowed, nothing turns on and the page says so.
struct NotificationsScreen: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(NoteStore.self) private var notes
    @State private var notAllowed = false

    var body: some View {
        Form {
            Section {
                Toggle("Monthly note", isOn: binding(\.monthly))
                if preferences.notes.monthly {
                    Picker("Day", selection: binding(\.day)) {
                        Text("Last day of the month").tag(NoteSettings.lastDay)
                        ForEach(1...28, id: \.self) { day in
                            Text("Day \(day)").tag(day)
                        }
                    }
                    DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Each month")
            } footer: {
                Text("When your check-in is due: where you stood at the last one, what's next, and the files to import.")
            }
            Section {
                yearly("Your year", detail: "Early January, your year in review", \.yourYear)
                yearly("Birthday", detail: "How far your last Monday is", \.birthday)
                yearly("Records anniversary", detail: "How far you've come since you started", \.recordsAnniversary)
                yearly("Plan check-up", detail: "A year after your plan last changed", \.planCheckUp)
            } header: {
                Text("Once a year")
            } footer: {
                VStack(alignment: .leading, spacing: Metrics.s) {
                    Text("Notes show ages, years and percentages, never amounts. On this device only, so you aren't told twice.")
                    if notAllowed {
                        Text("Notifications are off for this app. Turn them on in the system settings to get notes.")
                            .foregroundStyle(Palette.warning)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Notifications")
    }

    private func yearly(_ title: String, detail: String, _ keyPath: WritableKeyPath<NoteSettings, Bool>) -> some View {
        Toggle(isOn: binding(keyPath)) {
            Text(title)
            Text(detail)
        }
    }

    private func binding<Value: Equatable>(_ keyPath: WritableKeyPath<NoteSettings, Value>) -> Binding<Value> {
        Binding(
            get: { preferences.notes[keyPath: keyPath] },
            set: { value in
                var settings = preferences.notes
                settings[keyPath: keyPath] = value
                apply(settings)
            })
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                let settings = preferences.notes
                return Calendar.current.date(bySettingHour: settings.hour, minute: settings.minute, second: 0,
                                             of: Date()) ?? Date()
            },
            set: { time in
                let components = Calendar.current.dateComponents([.hour, .minute], from: time)
                var settings = preferences.notes
                settings.hour = components.hour ?? NoteSettings.standard.hour
                settings.minute = components.minute ?? NoteSettings.standard.minute
                apply(settings)
            })
    }

    private func apply(_ settings: NoteSettings) {
        guard settings != preferences.notes else { return }
        Task {
            notAllowed = !(await notes.apply(settings))
        }
    }

    /// What Settings shows next to *Notifications*: "Monthly and yearly",
    /// "Monthly", "Yearly" or "Off".
    nonisolated static func summary(_ settings: NoteSettings) -> String {
        let yearly = settings.yourYear || settings.birthday || settings.recordsAnniversary || settings.planCheckUp
        switch (settings.monthly, yearly) {
        case (true, true): return "Monthly and yearly"
        case (true, false): return "Monthly"
        case (false, true): return "Yearly"
        case (false, false): return "Off"
        }
    }
}
