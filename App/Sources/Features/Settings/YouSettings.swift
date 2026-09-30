import Foundation
import Model

/// "You" in `library.json` (UI.md, "Settings"; the plan's *You* card),
/// changed one field at a time. Screens write a field from its control's own
/// setter, only when you change it: opening a screen writes nothing, and
/// nothing is made up. A birth date or tax residence that isn't set shows as
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
