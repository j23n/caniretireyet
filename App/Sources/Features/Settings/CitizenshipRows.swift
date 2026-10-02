import Model
import SwiftUI

/// The citizenships (`person.citizenships` in `library.json`), next to the
/// birth date wherever the person is edited (Settings, the plan's *You*
/// card): each country with a button that removes it, then *Add
/// Citizenship* with the common countries not held yet. `update` applies a
/// change to the library's settings (`YouSettings`); nothing is written
/// until you add or remove one.
struct CitizenshipRows: View {
    let settings: LibrarySettings
    let update: ((LibrarySettings) -> LibrarySettings) -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        let held = settings.person?.citizenships ?? []
        ForEach(held, id: \.self) { code in
            HStack {
                Text("Citizen of \(CountryChoices.name(of: code, locale: locale))")
                Spacer()
                Button {
                    update { YouSettings.removing(citizenship: code, in: $0) }
                } label: {
                    Label("Remove", systemImage: "minus.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Remove \(CountryChoices.name(of: code, locale: locale))"))
            }
        }
        Menu {
            ForEach(YouSettings.citizenshipChoices(in: settings), id: \.self) { code in
                Button(CountryChoices.name(of: code, locale: locale)) {
                    update { YouSettings.adding(citizenship: code, in: $0) }
                }
            }
        } label: {
            Label(held.isEmpty ? "Add Citizenship" : "Add Another Citizenship", systemImage: "plus")
        }
    }
}

#Preview("Citizenships") {
    @Previewable @State var settings = LibrarySettings(baseCurrency: .eur,
                                                       person: Person(citizenships: ["IT", "DE"]))
    Form {
        Section {
            CitizenshipRows(settings: settings) { change in settings = change(settings) }
        } footer: {
            Text(YouSettings.citizenshipExplanation)
        }
    }
    .formStyle(.grouped)
    .previewEnvironment()
}
