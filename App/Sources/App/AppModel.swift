import CloudSync
import Foundation
import Model
import Prices

/// Every store the app has, created once and injected into each scene's
/// environment (`.appEnvironment(model)`). Screens read the stores from the
/// environment, never from here.
@MainActor
final class AppModel {
    let preferences: AppPreferences
    let privacy: PrivacySettings
    let navigation: AppNavigation
    let library: LibraryStore
    let prices: PriceStore
    let plans: PlanStore
    let checkIn: CheckInStore

    init(preferences: AppPreferences, privacy: PrivacySettings, library: LibraryStore, prices: PriceStore,
         planEngine: any PlanEngine, draftURL: URL?) {
        self.preferences = preferences
        self.privacy = privacy
        navigation = AppNavigation()
        self.library = library
        self.prices = prices
        plans = PlanStore(library: library, engine: planEngine)
        checkIn = CheckInStore(library: library, prices: prices, plans: plans, preferences: preferences,
                               draftURL: draftURL)
    }

    /// The real app: the library in iCloud Drive or on this device, prices
    /// from the network with API keys from the Keychain.
    static func live() -> AppModel {
        let preferences = AppPreferences()
        #if canImport(Security)
        let credentials: any CredentialsProvider = KeychainCredentials()
        #else
        let credentials: any CredentialsProvider = StaticCredentials()
        #endif
        return AppModel(
            preferences: preferences, privacy: PrivacySettings(),
            library: LibraryStore(locator: LibraryLocator(), preferences: preferences),
            prices: PriceStore(service: .standard(credentials: credentials)),
            planEngine: PlannerPlanEngine(),
            draftURL: CheckInStore.defaultDraftURL())
    }

    /// Previews: `library` in memory (by default the made-up example
    /// library), no network, no files, and made-up plan results.
    static func preview(_ library: Library = PreviewLibrary.library, planEngine: any PlanEngine = PreviewPlanEngine())
        -> AppModel {
        let defaults = UserDefaults(suiteName: "preview") ?? .standard
        return AppModel(
            preferences: AppPreferences(defaults: defaults), privacy: PrivacySettings(defaults: defaults),
            library: .inMemory(library), prices: PriceStore(service: nil), planEngine: planEngine, draftURL: nil)
    }

    /// Launch work: find and load the library, restore an unfinished
    /// check-in, and refresh the reminders scheduled on this device.
    func start() async {
        checkIn.restoreDraft()
        #if canImport(UserNotifications)
        if let reminder = preferences.reminder {
            Task { await ReminderScheduler.apply(reminder) }
        }
        #endif
        guard library.phase == .starting else { return }
        await library.start()
    }
}
