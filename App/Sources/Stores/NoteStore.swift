import Foundation
import Glance
import Model
import Observation

/// The notes this device shows (UI.md, "Notifications"): works them out
/// from the widgets' snapshot (`NotePlanner`) and schedules them as local
/// notifications (``NoteScheduler``), again at launch, whenever the
/// snapshot's inputs change (a check-in, an answer) and when the settings
/// change. A tapped note's link waits in ``pendingLink`` for the root view
/// to open.
@Observable @MainActor
final class NoteStore {
    /// Where a tapped note goes; the root view opens it and clears it.
    var pendingLink: GlanceLink?

    @ObservationIgnored private let preferences: AppPreferences
    @ObservationIgnored private let widgets: WidgetStore
    /// Whether this model schedules notes: not in previews and screen tests.
    @ObservationIgnored private let schedules: Bool
    /// What opens tapped notes: kept here, as the notification center doesn't keep it.
    @ObservationIgnored private var delegate: AnyObject?

    init(preferences: AppPreferences, widgets: WidgetStore, schedules: Bool) {
        self.preferences = preferences
        self.widgets = widgets
        self.schedules = schedules
        #if canImport(UserNotifications)
        if schedules {
            delegate = NoteScheduler.listen { [weak self] link in self?.pendingLink = link }
        }
        #endif
    }

    /// Turns `settings` on, asking for permission first when they turn a
    /// note on, and schedules them. When notes aren't allowed, nothing
    /// changes and it returns `false`, so Settings doesn't show notes that
    /// never come. Turning notes off or changing their time never asks.
    @discardableResult
    func apply(_ settings: NoteSettings) async -> Bool {
        #if canImport(UserNotifications)
        if settings.turnsOnNote(from: preferences.notes) && schedules {
            guard await NoteScheduler.requestAuthorization() else { return false }
        }
        #endif
        preferences.notes = settings
        await reschedule()
        return true
    }

    /// Schedules the notes for the library as it is, replacing those
    /// scheduled before. Nothing happens until the library is loaded.
    func reschedule() async {
        #if canImport(UserNotifications)
        guard schedules else { return }
        let settings = preferences.notes
        guard settings.isAnyOn else {
            await NoteScheduler.schedule([], chart: nil)
            return
        }
        guard let snapshot = widgets.snapshot() else { return }
        let notes = NotePlanner.notes(for: snapshot, settings: settings, now: .now())
        let chart = notes.contains(where: \.showsChart) ? NoteChartView.png(for: snapshot) : nil
        await NoteScheduler.schedule(notes, chart: chart)
        #endif
    }
}

extension NoteTime {
    /// The moment it is now, in this device's time zone.
    static func now(_ date: Date = Date(), calendar: Calendar = .current) -> NoteTime {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return NoteTime(date: CalendarDate(date, in: calendar.timeZone), hour: parts.hour ?? 0,
                        minute: parts.minute ?? 0)
    }
}
