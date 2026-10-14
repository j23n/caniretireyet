import Glance
import Model
import SwiftUI

/// The yearly notes offered once on the Overview, after the first answer,
/// while none of them is on (UI.md, "Notifications", "The offer"). *Turn
/// On* asks for permission and turns on the ones ticked; either button
/// puts the card away for good.
struct NotesOfferCard: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(NoteStore.self) private var notes
    @State private var yourYear = true
    @State private var birthday = true
    @State private var recordsAnniversary = true
    @State private var planCheckUp = true

    var body: some View {
        if !preferences.notesOffered && !hasYearlyNotes {
            Card {
                VStack(alignment: .leading, spacing: Metrics.m) {
                    Text("Retiring is years away. A few times a year, a short note can show how far you've come. "
                         + "Never amounts, never about markets.")
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: Metrics.s) {
                        choice("Your year", detail: "Early January", isOn: $yourYear)
                        choice("Birthday", detail: "How far your last Monday is", isOn: $birthday)
                        choice("Records anniversary", detail: "How far you've come since you started",
                               isOn: $recordsAnniversary)
                        choice("Plan check-up", detail: "A year after your plan last changed", isOn: $planCheckUp)
                    }
                    HStack(spacing: Metrics.m) {
                        Button("Turn On") { turnOn() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!(yourYear || birthday || recordsAnniversary || planCheckUp))
                        Button("Not Now") { preferences.notesOffered = true }
                            .buttonStyle(.bordered)
                    }
                    Text("Shown once. Settings › Notifications changes them later.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
            } header: {
                SectionHeader("Keep your goal in view", systemImage: "bell")
            }
        }
    }

    private var hasYearlyNotes: Bool {
        let settings = preferences.notes
        return settings.yourYear || settings.birthday || settings.recordsAnniversary || settings.planCheckUp
    }

    private func choice(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        #if os(macOS)
        .toggleStyle(.checkbox)
        #endif
    }

    private func turnOn() {
        var settings = preferences.notes
        settings.yourYear = yourYear
        settings.birthday = birthday
        settings.recordsAnniversary = recordsAnniversary
        settings.planCheckUp = planCheckUp
        preferences.notesOffered = true
        Task { await notes.apply(settings) }
    }
}
