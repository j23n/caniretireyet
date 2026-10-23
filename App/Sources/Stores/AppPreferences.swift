import CloudSync
import Foundation
import Glance
import Model
import Observation
import Tracker

/// Settings that belong to this device, not to the library (docs/schema,
/// library.schema.json: "Settings that belong to one device … are stored on that device"). Kept
/// in `UserDefaults`, except whether amounts are hidden right now.
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

    /// Which notes this device shows and when (UI.md, "Notifications").
    /// This device only, so you aren't told twice.
    var notes: NoteSettings {
        didSet {
            defaults.set(notes.monthly, forKey: Keys.reminderEnabled)
            defaults.set(notes.day, forKey: Keys.reminderDay)
            defaults.set(notes.hour, forKey: Keys.reminderHour)
            defaults.set(notes.minute, forKey: Keys.reminderMinute)
            defaults.set(notes.yourYear, forKey: Keys.notesYourYear)
            defaults.set(notes.birthday, forKey: Keys.notesBirthday)
            defaults.set(notes.recordsAnniversary, forKey: Keys.notesRecordsAnniversary)
            defaults.set(notes.planCheckUp, forKey: Keys.notesPlanCheckUp)
        }
    }

    /// Whether Today has offered the yearly notes once
    /// (UI.md, "Today", "Keep your goal in view").
    var notesOffered: Bool {
        didSet { defaults.set(notesOffered, forKey: Keys.notesOffered) }
    }

    /// The account groups (and *Closed*) that are collapsed on this device,
    /// in the sidebar and in the Accounts list alike
    /// (``SidebarAccountFolder/key``: a group's raw value, or `"closed"`).
    /// Until one is toggled, only *Closed* is collapsed
    /// (``defaultCollapsedAccountFolders``). Read and change it with
    /// `isExpanded(_:)` and `setExpanded(_:_:)`; the list expands everything
    /// while searching.
    var collapsedAccountFolders: Set<String> {
        didSet { defaults.set(collapsedAccountFolders.sorted(), forKey: Keys.collapsedAccountFolders) }
    }

    /// The groups start expanded, *Closed* collapsed.
    static let defaultCollapsedAccountFolders: Set<String> = [SidebarAccountFolder.closed.key]

    /// How far ahead charts show a plan's projection: Today's net
    /// worth with *Future* on, and the plan's "Your money over time"
    /// (UI.md, "Charts"). Retirement and 10 years after it until changed,
    /// or when the stored choice is no longer offered.
    var futureHorizon: FutureHorizon {
        didSet { defaults.set(futureHorizon.rawValue, forKey: Keys.futureHorizon) }
    }

    // MARK: Hiding amounts (UI.md, "Privacy")

    /// Whether amounts are hidden right now: what the eye button and ⌘⇧H
    /// toggle. `appEnvironment` redacts each scene for `.privacy` while it's
    /// on, so amounts show as placeholders while charts keep their shape.
    /// Not kept: each launch starts from ``hideAmountsOnLaunch``.
    var hidesAmounts: Bool

    /// Whether amounts start hidden when the app launches.
    var hideAmountsOnLaunch: Bool {
        didSet { defaults.set(hideAmountsOnLaunch, forKey: Keys.hideAmountsOnLaunch) }
    }

    /// Whether the app covers its content while it isn't active (the app
    /// switcher, a notification pulled down).
    var hideInAppSwitcher: Bool {
        didSet { defaults.set(hideInAppSwitcher, forKey: Keys.hideInAppSwitcher) }
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
        futureHorizon = FutureHorizon(stored: defaults.string(forKey: Keys.futureHorizon))
        let standard = NoteSettings.standard
        let monthly = defaults.bool(forKey: Keys.reminderEnabled)
        notes = NoteSettings(
            monthly: monthly,
            day: defaults.object(forKey: Keys.reminderDay) as? Int ?? standard.day,
            hour: defaults.object(forKey: Keys.reminderHour) as? Int ?? standard.hour,
            minute: defaults.object(forKey: Keys.reminderMinute) as? Int ?? standard.minute,
            // Until it's set, *Your year* is on when the monthly note is:
            // notes were allowed then.
            yourYear: defaults.object(forKey: Keys.notesYourYear) as? Bool ?? monthly,
            birthday: defaults.bool(forKey: Keys.notesBirthday),
            recordsAnniversary: defaults.bool(forKey: Keys.notesRecordsAnniversary),
            planCheckUp: defaults.bool(forKey: Keys.notesPlanCheckUp))
        notesOffered = defaults.bool(forKey: Keys.notesOffered)
        hideAmountsOnLaunch = defaults.bool(forKey: Keys.hideAmountsOnLaunch)
        hideInAppSwitcher = defaults.bool(forKey: Keys.hideInAppSwitcher)
        hidesAmounts = defaults.bool(forKey: Keys.hideAmountsOnLaunch)
    }

    func toggleHidesAmounts() {
        hidesAmounts.toggle()
    }

    private enum Keys {
        static let libraryLocation = "libraryLocation"
        static let stalenessThreshold = "stalenessThreshold"
        static let fetchPricesOnCheckIn = "fetchPricesOnCheckIn"
        static let reminderEnabled = "checkInReminder.enabled"
        static let reminderDay = "checkInReminder.day"
        static let reminderHour = "checkInReminder.hour"
        static let reminderMinute = "checkInReminder.minute"
        static let notesYourYear = "notes.yourYear"
        static let notesBirthday = "notes.birthday"
        static let notesRecordsAnniversary = "notes.recordsAnniversary"
        static let notesPlanCheckUp = "notes.planCheckUp"
        static let notesOffered = "notes.offered"
        static let collapsedAccountFolders = "sidebar.collapsedAccountFolders"
        static let futureHorizon = "charts.futureHorizon"
        static let hideAmountsOnLaunch = "privacy.hideAmountsOnLaunch"
        static let hideInAppSwitcher = "privacy.hideInAppSwitcher"
    }
}
