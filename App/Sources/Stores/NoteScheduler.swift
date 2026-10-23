#if canImport(UserNotifications)
import Foundation
import Glance
import Model
import UserNotifications

/// Schedules the notes as local notifications on this device (UI.md,
/// "Notifications": this device only, so you aren't told twice).
///
/// "The last day of the month" can't be a repeating calendar trigger, and
/// each note's words depend on the library, so each note is scheduled on
/// its own; ``NoteStore`` replaces them whenever they may have changed.
enum NoteScheduler {
    static let identifierPrefix = "note-"
    /// The prefix of the monthly reminders scheduled before the notes.
    static let legacyPrefix = "check-in-reminder-"

    /// The notes that ask for a check-in: they offer *Import Files* and
    /// *Open Today* when touched and held.
    static let checkInCategory = "check-in"
    static let importAction = "import-files"
    static let overviewAction = "open-overview"
    /// The `userInfo` key of a note's link (``GlanceLink``).
    static let linkKey = "link"

    /// Asks for permission to show notes; `true` when allowed.
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Whether notes may show, without asking.
    static func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    /// Replaces the scheduled notes with `notes`. `chart` is the PNG the
    /// note that ``EngagementNote/showsChart`` carries.
    static func schedule(_ notes: [EngagementNote], chart: Data?) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: pending.filter {
            $0.hasPrefix(identifierPrefix) || $0.hasPrefix(legacyPrefix)
        })
        guard !notes.isEmpty, await isAuthorized() else { return }
        for note in notes {
            let content = UNMutableNotificationContent()
            content.title = note.title
            content.body = note.body
            content.sound = .default
            content.userInfo = [linkKey: note.link.rawValue]
            content.threadIdentifier = note.asksForCheckIn ? checkInCategory : note.kind.rawValue
            if note.asksForCheckIn { content.categoryIdentifier = checkInCategory }
            if note.showsChart, let chart, let attachment = attachment(chart, for: note) {
                content.attachments = [attachment]
            }
            var components = DateComponents()
            components.year = note.time.date.year
            components.month = note.time.date.month
            components.day = note.time.date.day
            components.hour = note.time.hour
            components.minute = note.time.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: identifierPrefix + note.id, content: content,
                                                trigger: trigger)
            try? await center.add(request)
        }
    }

    /// The chart as an attachment, from a file the system then moves into
    /// its own store. Its thumbnail is hidden: it shows when the note is
    /// touched and held.
    private static func attachment(_ png: Data, for note: EngagementNote) -> UNNotificationAttachment? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(identifierPrefix)\(note.id)-\(UUID().uuidString).png")
        do {
            try png.write(to: url)
            return try UNNotificationAttachment(identifier: "chart", url: url,
                                                options: [UNNotificationAttachmentOptionsThumbnailHiddenKey: true])
        } catch {
            return nil
        }
    }

    /// Registers the notes' actions and listens for taps, which go to
    /// `open`. Keep the delegate returned: the notification center doesn't.
    @MainActor
    static func listen(_ open: @escaping @MainActor @Sendable (GlanceLink) -> Void) -> NoteDelegate {
        let center = UNUserNotificationCenter.current()
        let delegate = NoteDelegate(open: open)
        center.delegate = delegate
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: checkInCategory,
                actions: [
                    UNNotificationAction(identifier: importAction, title: "Import Files", options: [.foreground]),
                    UNNotificationAction(identifier: overviewAction, title: "Open Today", options: [.foreground]),
                ],
                intentIdentifiers: [])
        ])
        return delegate
    }
}

/// Opens a tapped note's link, and shows notes while the app is open.
final class NoteDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    private let open: @MainActor @Sendable (GlanceLink) -> Void

    init(open: @escaping @MainActor @Sendable (GlanceLink) -> Void) {
        self.open = open
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let link: GlanceLink?
        switch response.actionIdentifier {
        case NoteScheduler.importAction:
            link = .checkIn
        case NoteScheduler.overviewAction:
            link = .today
        default:
            let raw = response.notification.request.content.userInfo[NoteScheduler.linkKey] as? String
            link = raw.flatMap(GlanceLink.init(rawValue:))
        }
        guard let link else { return }
        await open(link)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
#endif
