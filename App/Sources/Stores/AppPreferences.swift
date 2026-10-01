import CloudSync
import Foundation
import Model
import Observation
import Tracker

/// Settings that belong to this device, not to the library (FILE_FORMAT.md:
/// "Settings that belong to one device … are stored on that device"). Kept
/// in `UserDefaults`.
@Observable @MainActor
final class AppPreferences {
    /// Where this device keeps the library; `nil` until it's been chosen or found.
    var libraryLocation: LibraryLocationKind? {
        didSet { defaults.set(libraryLocation?.rawValue, forKey: Keys.libraryLocation) }
    }

    /// Days after which an account's latest value counts as stale (default 45).
    var stalenessThreshold: Int {
        didSet { defaults.set(stalenessThreshold, forKey: Keys.stalenessThreshold) }
    }

    /// Whether prices and FX rates are fetched when a check-in opens.
    var fetchPricesOnCheckIn: Bool {
        didSet { defaults.set(fetchPricesOnCheckIn, forKey: Keys.fetchPricesOnCheckIn) }
    }

    /// The monthly check-in reminder, if it's on. This device only, so you
    /// aren't reminded twice.
    var reminder: CheckInReminder? {
        didSet {
            defaults.set(reminder != nil, forKey: Keys.reminderEnabled)
            if let reminder {
                defaults.set(reminder.day, forKey: Keys.reminderDay)
                defaults.set(reminder.hour, forKey: Keys.reminderHour)
                defaults.set(reminder.minute, forKey: Keys.reminderMinute)
            }
        }
    }

    /// The account groups (and *Closed*) that are collapsed on this device,
    /// in the sidebar and in the Accounts list alike
    /// (``SidebarAccountFolder/key``: a group's raw value, or `"closed"`).
    /// Until one is toggled, only *Closed* is collapsed
    /// (``defaultCollapsedAccountFolders``). Read and change it with
    /// `isExpanded(_:)` and `setExpanded(_:_:)`; the list reads it through
    /// ``AccountListExpansion``, which expands everything while searching.
    var collapsedAccountFolders: Set<String> {
        didSet { defaults.set(collapsedAccountFolders.sorted(), forKey: Keys.collapsedAccountFolders) }
    }

    /// The groups start expanded, *Closed* collapsed.
    static let defaultCollapsedAccountFolders: Set<String> = [SidebarAccountFolder.closed.key]

    /// How far ahead charts show a plan's projection: the Overview's net
    /// worth with *Future* on, and the plan's "Your money over time"
    /// (UI.md, "Charts"). Retirement and 15 years after it until changed.
    var futureHorizon: FutureHorizon {
        didSet { defaults.set(futureHorizon.rawValue, forKey: Keys.futureHorizon) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        libraryLocation = defaults.string(forKey: Keys.libraryLocation).flatMap(LibraryLocationKind.init(rawValue:))
        stalenessThreshold = defaults.object(forKey: Keys.stalenessThreshold) as? Int
            ?? Valuator.defaultStalenessThreshold
        fetchPricesOnCheckIn = defaults.object(forKey: Keys.fetchPricesOnCheckIn) as? Bool ?? true
        collapsedAccountFolders = defaults.stringArray(forKey: Keys.collapsedAccountFolders).map(Set.init)
            ?? Self.defaultCollapsedAccountFolders
        futureHorizon = defaults.string(forKey: Keys.futureHorizon).flatMap(FutureHorizon.init(rawValue:))
            ?? .standard
        if defaults.bool(forKey: Keys.reminderEnabled) {
            reminder = CheckInReminder(
                day: defaults.object(forKey: Keys.reminderDay) as? Int ?? CheckInReminder.lastDay,
                hour: defaults.object(forKey: Keys.reminderHour) as? Int ?? 19,
                minute: defaults.object(forKey: Keys.reminderMinute) as? Int ?? 0)
        } else {
            reminder = nil
        }
    }

    private enum Keys {
        static let libraryLocation = "libraryLocation"
        static let stalenessThreshold = "stalenessThreshold"
        static let fetchPricesOnCheckIn = "fetchPricesOnCheckIn"
        static let reminderEnabled = "checkInReminder.enabled"
        static let reminderDay = "checkInReminder.day"
        static let reminderHour = "checkInReminder.hour"
        static let reminderMinute = "checkInReminder.minute"
        static let collapsedAccountFolders = "sidebar.collapsedAccountFolders"
        static let futureHorizon = "charts.futureHorizon"
    }
}

/// When to remind about the monthly check-in.
struct CheckInReminder: Hashable, Sendable {
    /// Stands for the last day of the month.
    static let lastDay = 0

    /// Day of the month, 1...28, or ``lastDay``.
    var day: Int
    var hour: Int
    var minute: Int

    /// The reminder's date in `month`: the given day, or the month's last day.
    func date(in month: YearMonth) -> CalendarDate {
        guard day != Self.lastDay, let date = CalendarDate(year: month.year, month: month.month, day: min(day, 28))
        else { return month.lastDay }
        return date
    }

    /// The next `count` reminder dates from `today`, starting this month if
    /// its reminder is still ahead (today counts when `timePassed` is false).
    func upcomingDates(from today: CalendarDate, timePassed: Bool, count: Int = 12) -> [CalendarDate] {
        let thisMonth = date(in: today.yearMonth)
        let startsNextMonth = thisMonth < today || (thisMonth == today && timePassed)
        let first = startsNextMonth ? today.yearMonth.next : today.yearMonth
        return (0..<count).map { date(in: first.adding(months: $0)) }
    }
}
