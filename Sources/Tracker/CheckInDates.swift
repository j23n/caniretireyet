import Model

/// The dates of the monthly check-in (UI.md, "Check-in").
public enum CheckInDates {
    /// The date to suggest for a new check-in on `today`: the end of the
    /// previous month during the first 7 days of a month, unless that month
    /// end already has a check-in; otherwise today.
    public static func suggested(today: CalendarDate, lastCheckIn: CalendarDate? = nil) -> CalendarDate {
        let monthEnd = today.startOfMonth.adding(days: -1)
        guard today.day <= 7, lastCheckIn.map({ $0 < monthEnd }) ?? true else { return today }
        return monthEnd
    }
}
