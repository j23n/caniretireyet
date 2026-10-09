import Foundation
import Glance
import Model
import Tracker

/// Where the monthly check-in stands, for the tab bar accessory, the
/// sidebar's dot and reminders (UI.md, "Navigation").
struct CheckInStatus: Hashable, Sendable {
    /// The date of the latest check-in, if any.
    var lastCheckIn: CalendarDate?
    /// The month end the next check-in is for; today before the first one.
    var nextCheckIn: CalendarDate
    /// Days from today to ``nextCheckIn``; negative when it has passed.
    var daysUntilDue: Int
    /// Whether it's time to check in: the next check-in is within a few days,
    /// or has passed, or there hasn't been one.
    var isDue: Bool
    /// The date of an unfinished check-in on this device, if any.
    var draftDate: CalendarDate?
    /// Rows reviewed in the draft ("7 of 9 reviewed").
    var draftReviewed = 0
    /// Rows in the draft.
    var draftTotal = 0

    var hasDraft: Bool { draftDate != nil }

    /// Whether a check-in is due or under way: the tab bar's accessory and
    /// the sidebar's dot show, and *Check In* leaves the Overview's toolbar.
    var isActive: Bool { isDue || hasDraft }

    /// One line for the accessory: "Continue check-in · 7 of 9 reviewed",
    /// "October check-in · due in 3 days", "Last check-in 30 Sep · next 31 Oct".
    func summary(locale: Locale = .current) -> String {
        if hasDraft {
            return "Continue check-in · \(draftReviewed) of \(draftTotal) reviewed"
        }
        let month = AmountFormat.monthName(nextCheckIn, locale: locale)
        guard let lastCheckIn else { return "First check-in · ready when you are" }
        if isDue {
            switch daysUntilDue {
            case 1...: return "\(month) check-in · due in \(Wording.count(daysUntilDue, "day"))"
            case 0: return "\(month) check-in · due today"
            default: return "\(month) check-in · ready to start"
            }
        }
        return "Last check-in \(AmountFormat.shortDate(lastCheckIn, locale: locale)) · next "
            + AmountFormat.shortDate(nextCheckIn, locale: locale)
    }
}

/// When check-ins are due: once a month, at the month's end, as the widgets
/// have it (Glance's `CheckInGlance`).
enum CheckInSchedule {
    /// The status on `today`, given the latest check-in and a draft.
    static func status(today: CalendarDate, lastCheckIn: CalendarDate?, draft: CheckInDraft? = nil) -> CheckInStatus {
        let schedule = CheckInGlance(last: lastCheckIn, today: today)
        return CheckInStatus(
            lastCheckIn: lastCheckIn, nextCheckIn: schedule.next, daysUntilDue: schedule.daysUntilDue(on: today),
            isDue: schedule.isDue(on: today), draftDate: draft?.date,
            draftReviewed: draft?.reviewedCount ?? 0, draftTotal: draft?.progressTotal ?? 0)
    }
}
