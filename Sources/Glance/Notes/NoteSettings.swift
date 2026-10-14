import Foundation
import Model

/// Which notes you get and when (UI.md, "Notifications"): the monthly note
/// on a day and at a time you choose, and the yearly ones. Kept on the
/// device that shows them, not in the library, so you aren't told twice.
public struct NoteSettings: Hashable, Sendable, Codable {
    /// The ``day`` that stands for each month's last day.
    public static let lastDay = 0

    /// The monthly note: once a month, the answer and the ask to check in.
    public var monthly: Bool
    /// The monthly note's day of the month, 1 to 28, or ``lastDay``.
    public var day: Int
    public var hour: Int
    public var minute: Int
    /// *Your year*, on 3 January.
    public var yourYear: Bool
    /// On your birthday.
    public var birthday: Bool
    /// On the anniversary of your first record.
    public var recordsAnniversary: Bool
    /// A year after the main plan last changed.
    public var planCheckUp: Bool

    public init(monthly: Bool, day: Int = NoteSettings.lastDay, hour: Int = 19, minute: Int = 0,
                yourYear: Bool = true, birthday: Bool = false, recordsAnniversary: Bool = false,
                planCheckUp: Bool = false) {
        self.monthly = monthly
        self.day = day
        self.hour = hour
        self.minute = minute
        self.yourYear = yourYear
        self.birthday = birthday
        self.recordsAnniversary = recordsAnniversary
        self.planCheckUp = planCheckUp
    }

    /// The notes turned on as the app suggests: the monthly note on the
    /// last day at 19:00, and *Your year*.
    public static let standard = NoteSettings(monthly: true)

    /// No notes at all.
    public static let off = NoteSettings(monthly: false, yourYear: false)

    /// Whether any note is on.
    public var isAnyOn: Bool {
        monthly || yourYear || birthday || recordsAnniversary || planCheckUp
    }

    /// Whether these settings turn on a note that `old` has off: only then
    /// is permission asked for.
    public func turnsOnNote(from old: NoteSettings) -> Bool {
        (monthly && !old.monthly) || (yourYear && !old.yourYear) || (birthday && !old.birthday)
            || (recordsAnniversary && !old.recordsAnniversary) || (planCheckUp && !old.planCheckUp)
    }

    /// The monthly note's day in `month`: its ``day``, or the month's last
    /// when that's ``lastDay`` or past the month's end.
    public func date(in month: YearMonth) -> CalendarDate {
        guard day > 0, day <= month.numberOfDays, let date = CalendarDate(year: month.year, month: month.month, day: day)
        else { return month.lastDay }
        return date
    }
}

/// A day and a time of day, in the device's time zone, when a note shows.
public struct NoteTime: Hashable, Sendable, Comparable {
    public var date: CalendarDate
    public var hour: Int
    public var minute: Int

    public init(date: CalendarDate, hour: Int, minute: Int) {
        self.date = date
        self.hour = hour
        self.minute = minute
    }

    public static func < (lhs: NoteTime, rhs: NoteTime) -> Bool {
        (lhs.date, lhs.hour, lhs.minute) < (rhs.date, rhs.hour, rhs.minute)
    }
}
