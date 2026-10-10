import Foundation
import Model

/// "You" in `library.json` (UI.md, "Settings"; the plan's *You* card),
/// changed one field at a time. Screens write a field from its control's own
/// setter, only when you change it: opening a screen writes nothing, and
/// nothing is made up. A birth date or country that isn't set shows as
/// "Not set" until you choose one.
enum YouSettings {
    /// `settings` with `name`, trimmed; an empty name removes it.
    static func setting(name: String, in settings: LibrarySettings) -> LibrarySettings {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return setting(\.name, to: trimmed.isEmpty ? nil : trimmed, in: settings)
    }

    /// `settings` with `birthDate`; `nil` removes it.
    static func setting(birthDate: CalendarDate?, in settings: LibrarySettings) -> LibrarySettings {
        setting(\.birthDate, to: birthDate, in: settings)
    }

    /// Whether `name` typed in the field differs from the saved name, so
    /// there's something to write.
    static func isNameChanged(_ name: String, in settings: LibrarySettings) -> Bool {
        setting(name: name, in: settings) != settings
    }

    /// Where the birth date picker starts when no birth date is set. It's
    /// only shown; nothing is saved until a date is picked.
    static func suggestedBirthDate(today: CalendarDate = .today()) -> CalendarDate {
        CalendarDate(year: today.year - 40, month: 1, day: 1) ?? today
    }

    // MARK: Inflation

    /// The line under the inflation picker.
    static let inflationExplanation = "Inflation puts amounts in today's money: automatically with the consumer "
        + "prices of the country you live in, else of your base currency."

    /// The index the library uses when none is chosen
    /// (`Library.effectiveInflationIndex` without the setting); `nil` when
    /// there's none, e.g. for a library in dollars.
    static func automaticInflationIndex(in library: Library) -> IndexID? {
        var library = library
        library.settings.inflationIndex = nil
        return library.effectiveInflationIndex
    }

    /// The indices the picker offers besides automatic: the euro area's,
    /// then every country's by its name (its HICP, or the US and UK CPI),
    /// and the chosen one first when it's none of those.
    static func inflationChoices(in settings: LibrarySettings, locale: Locale = .current) -> [IndexID] {
        let countries = IndexID.consumerPriceCountries.compactMap(IndexID.consumerPrices)
            .sorted { InflationIndexText.choice($0, locale: locale) < InflationIndexText.choice($1, locale: locale) }
        let choices = [IndexID.hicpEA] + countries
        guard let chosen = settings.inflationIndex, !choices.contains(chosen) else { return choices }
        return [chosen] + choices
    }

    /// `settings` with `index` as the inflation index; `nil` goes back to
    /// automatic and leaves the key out.
    static func setting(inflationIndex index: IndexID?, in settings: LibrarySettings) -> LibrarySettings {
        var settings = settings
        settings.inflationIndex = index
        return settings
    }

    /// Sets one field of the person, leaving the person out when it has none.
    private static func setting<Value>(_ field: WritableKeyPath<Person, Value?>, to value: Value?,
                                       in settings: LibrarySettings) -> LibrarySettings {
        var settings = settings
        var person = settings.person ?? Person()
        person[keyPath: field] = value
        settings.person = person == Person() ? nil : person
        return settings
    }
}
