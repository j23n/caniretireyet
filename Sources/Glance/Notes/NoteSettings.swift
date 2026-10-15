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
    /// The monthly note's day of the month: one of ``days`` counted from
    /// the start, ``lastDay``, or 1 to 6 days before the last as -1 to -6;
    /// ``effectiveDay`` is the one used.
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

    /// The days the monthly note can be on, counted from the month's start.
    /// A check-in in a month's last 7 days is for that month, and one
    /// before them for the month before (``CheckInGlance``). Days 1 to 21
    /// are before them in every month; later days are counted back from
    /// the last (``daysBeforeLast``), so a note never skips a month.
    public static let days = Array(1...21)

    /// How many days before the month's last day the note can be on.
    public static let daysBeforeLast = Array(1...6)

    /// ``day`` as one of the choices: a day saved past ``days`` counts as
    /// that many days before the last of a 30-day month, at most 6.
    public var effectiveDay: Int {
        get {
            if day > Self.days.count { return -min(Self.daysBeforeLast.count, max(0, 30 - day)) }
            return max(day, -Self.daysBeforeLast.count)
        }
        set { day = newValue }
    }

    /// The monthly note's day in `month`.
    public func date(in month: YearMonth) -> CalendarDate {
        let day = effectiveDay
        guard day > 0, let date = CalendarDate(year: month.year, month: month.month, day: day)
        else { return month.lastDay.adding(days: day) }
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
