import Glance
import Model
import SwiftUI

/// The yearly notes offered once on the Overview, after the first answer,
/// while any of them is off (UI.md, "Overview", "Keep your goal in view").
/// It lists only the ones that are off; *Turn On* asks for permission and
/// turns on the ones ticked. Either button puts the card away for good.
struct NotesOfferCard: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(NoteStore.self) private var notes
    @State private var yourYear = true
    @State private var birthday = true
    @State private var recordsAnniversary = true
    @State private var planCheckUp = true

    var body: some View {
        let settings = preferences.notes
        if !preferences.notesOffered && !(settings.yourYear && settings.birthday && settings.recordsAnniversary
                                          && settings.planCheckUp) {
            Card {
                VStack(alignment: .leading, spacing: Metrics.m) {
                    Text("Retiring is years away. A few times a year, a short note can show how far you've come. "
                         + "Never amounts, never about markets.")
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: Metrics.s) {
                        if !settings.yourYear {
                            choice("Your year", detail: "Early January", isOn: $yourYear)
                        }
                        if !settings.birthday {
                            choice("Birthday", detail: "How far your last Monday is", isOn: $birthday)
                        }
                        if !settings.recordsAnniversary {
                            choice("Records anniversary", detail: "How far you've come since you started",
                                   isOn: $recordsAnniversary)
                        }
                        if !settings.planCheckUp {
                            choice("Plan check-up", detail: "A year after your plan last changed", isOn: $planCheckUp)
                        }
                    }
                    HStack(spacing: Metrics.m) {
                        Button("Turn On") { turnOn() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!turnsOnAny(settings))
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

    /// Whether a note that is off is ticked.
    private func turnsOnAny(_ settings: NoteSettings) -> Bool {
        (!settings.yourYear && yourYear) || (!settings.birthday && birthday)
            || (!settings.recordsAnniversary && recordsAnniversary) || (!settings.planCheckUp && planCheckUp)
    }

    /// Turns on the ones ticked, leaving those already on.
    private func turnOn() {
        var settings = preferences.notes
        settings.yourYear = settings.yourYear || yourYear
        settings.birthday = settings.birthday || birthday
        settings.recordsAnniversary = settings.recordsAnniversary || recordsAnniversary
        settings.planCheckUp = settings.planCheckUp || planCheckUp
        preferences.notesOffered = true
        Task { await notes.apply(settings) }
    }
}
