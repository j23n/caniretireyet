import Model
import SwiftUI
import Tracker

// Small form controls shared by the account and instrument sheets.

extension AccountsAssetMixForm {
    /// The typed percentage of one class, for a text field.
    subscript(text assetClass: AssetClass) -> String {
        get { percents[assetClass] ?? "" }
        set { percents[assetClass] = newValue }
    }
}

/// One row per asset class with its percentage, and what's wrong when the
/// percentages don't add up to 100%.
struct AccountsAssetMixFields: View {
    @Binding var mix: AccountsAssetMixForm
    @Environment(\.locale) private var locale

    var body: some View {
        ForEach(mix.shownClasses, id: \.self) { assetClass in
            FormNumberField(title: BreakdownKey.assetClass(assetClass).description,
                            text: $mix[text: assetClass], prompt: "0", suffix: "%", allowsNegative: false)
        }
        if let problem = mix.problem(required: false, locale: locale) {
            Label(problem, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .privacySensitiveInFeedback()
        }
    }
}

/// *Add Position*: a menu of the library's instruments not listed yet, by
/// name; nothing when every one is listed.
struct AccountsAddPositionMenu: View {
    /// The instruments already listed.
    let listed: Set<InstrumentID>
    let add: (InstrumentID) -> Void

    @Environment(LibraryStore.self) private var library

    var body: some View {
        let others = library.library.instruments.values
            .filter { !listed.contains($0.id) }
            .sorted { $0.name < $1.name }
        if !others.isEmpty {
            Menu {
                ForEach(others) { instrument in
                    Button(instrument.name) { add(instrument.id) }
                }
            } label: {
                Label("Add Position", systemImage: "plus.circle")
            }
        }
    }
}

/// A list of what must be fixed before saving, under a form.
struct AccountsProblemsSection: View {
    let problems: [String]

    var body: some View {
        if !problems.isEmpty {
            Section {
                ForEach(problems, id: \.self) { problem in
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
        }
    }
}

/// What stopped a save, under a form; nothing without a message.
struct AccountsErrorSection: View {
    let message: String?

    var body: some View {
        if let message {
            Section {
                Label(message, systemImage: "xmark.octagon")
                    .foregroundStyle(Palette.critical)
                    .privacySensitiveInFeedback()
            }
        }
    }
}

extension Account {
    /// The latest date a value or a trade of `account` can be on, for a
    /// date picker: its closing date, or a year from today. Any earlier
    /// date works: before the opening date, saving moves it.
    static func latestDate(of account: Account?) -> Date {
        (account?.closed ?? CalendarDate.today().adding(years: 1)).dateValue
    }
}

/// A note in a form: an icon and a footnote that wraps, e.g. "Saving moves
/// the opening date from 30 Sep 2026 to 31 Mar 2024."
struct AccountsFootnote: View {
    let text: String
    let systemImage: String

    init(_ text: String, systemImage: String) {
        self.text = text
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            Text(verbatim: text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Palette.accent)
        }
        .font(.footnote)
        .foregroundStyle(Palette.secondaryInk)
    }
}
