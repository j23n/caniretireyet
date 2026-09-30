#if canImport(UserNotifications)
import Foundation
import Model
import UserNotifications

/// Schedules the monthly check-in reminder as local notifications on this
/// device (UI.md, "Settings": this device only, so you aren't reminded
/// twice).
///
/// "The last day of the month" can't be a repeating calendar trigger, so
/// the next twelve reminders are scheduled one by one; the app refreshes
/// them at launch and whenever the setting changes.
enum ReminderScheduler {
    static let identifierPrefix = "check-in-reminder-"

    /// Replaces the scheduled reminders with those for `reminder` (none when
    /// it's `nil`). Asks for permission the first time. Returns whether
    /// reminders are scheduled.
    @discardableResult
    static func apply(_ reminder: CheckInReminder?) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
        guard let reminder else { return false }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return false }

        let now = Date()
        let calendar = Calendar.current
        let today = CalendarDate(now, in: .current)
        let minutesNow = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let timePassed = minutesNow >= reminder.hour * 60 + reminder.minute
        for date in reminder.upcomingDates(from: today, timePassed: timePassed) {
            let content = UNMutableNotificationContent()
            content.title = "Time for your check-in"
            content.body = "A few minutes to update your accounts and see this month's answer."
            content.sound = .default
            var components = DateComponents()
            components.year = date.year
            components.month = date.month
            components.day = date.day
            components.hour = reminder.hour
            components.minute = reminder.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: identifierPrefix + date.description, content: content,
                                                trigger: trigger)
            try? await center.add(request)
        }
        return true
    }
}
#endif
