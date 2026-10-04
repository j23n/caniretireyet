import Foundation
import Model

/// The instants a provider's timestamps may give: from 1970-01-01 through
/// two days after today. Anything else is a broken answer (milliseconds
/// where seconds are expected, say), and turning it into a calendar date
/// would trap beyond year 9999, so providers drop such points before
/// converting them.
enum ProviderInstants {
    /// Whether `instant` is between 1970-01-01 and the end of the day two
    /// days after `today` (UTC, wide enough for any exchange's time zone).
    static func isPlausible(_ instant: Date, today: CalendarDate) -> Bool {
        guard instant.timeIntervalSince1970.isFinite, instant.timeIntervalSince1970 >= 0 else { return false }
        let latest = TimeInterval(today.adding(days: 3).daysSinceEpoch) * 86_400
        return instant.timeIntervalSince1970 < latest
    }
}
