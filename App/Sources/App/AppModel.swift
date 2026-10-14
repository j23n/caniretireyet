import CloudSync
#if FEEDBACK
import FeedbackKit
#endif
import Foundation
import Model
import Observation
import Prices

/// Every store the app has, created once and injected into each scene's
/// environment (`.appEnvironment(model)`). Screens read the stores from the
/// environment, never from here.
@MainActor
final class AppModel {
    let preferences: AppPreferences
    let navigation: AppNavigation
    let library: LibraryStore
    let prices: PriceStore
    let plans: PlanStore
    let checkIn: CheckInStore
    let widgets: WidgetStore
    let notes: NoteStore
    #if FEEDBACK
    /// In-app feedback, in Debug builds (`Feedback.swift`).
    let feedback: FeedbackCenter
    #endif

    init(preferences: AppPreferences, library: LibraryStore, prices: PriceStore, planEngine: any PlanEngine,
         planResults: PlanResultsArchive? = nil, widgetSnapshotURL: URL? = nil, schedulesNotes: Bool = false) {
        self.preferences = preferences
        navigation = AppNavigation()
        self.library = library
        self.prices = prices
        plans = PlanStore(library: library, engine: planEngine, archive: planResults)
        checkIn = CheckInStore(library: library, prices: prices, plans: plans, preferences: preferences)
        widgets = WidgetStore(library: library, plans: plans, snapshotURL: widgetSnapshotURL)
        notes = NoteStore(preferences: preferences, widgets: widgets, schedules: schedulesNotes)
        #if FEEDBACK
        feedback = .caniretireyet(navigation: navigation)
        #endif
    }

    /// The app's model at launch: ``live()``, or in a Debug build launched
    /// with `-screenLibrary`, a made-up library (``ScreenLaunch``).
    static func atLaunch() -> AppModel {
        #if DEBUG
        if let launch = ScreenLaunch(arguments: ProcessInfo.processInfo.arguments) {
            return launch.model()
        }
        #endif
        return live()
    }

    /// The real app: the library in iCloud Drive or on this device, prices
    /// from the network, each plan's latest results in the app's caches, and
    /// the widgets' snapshot in the App Group's container.
    static func live() -> AppModel {
        let preferences = AppPreferences()
        return AppModel(
            preferences: preferences,
            library: LibraryStore(locator: LibraryLocator(), preferences: preferences),
            prices: PriceStore(service: .standard()),
            planEngine: PlannerPlanEngine(),
            planResults: PlanResultsArchive.standard(),
            widgetSnapshotURL: AppGroup.snapshotURL, schedulesNotes: true)
    }

    /// Previews, the screen tests and ``ScreenLaunch``: `library` in memory (by default
    /// the made-up example library), no network, no files (not even the
    /// widgets' snapshot, nor the plans' results without `planResults`),
    /// plans run on `planEngine` (made-up results by default), and this
    /// device's settings in the `UserDefaults` suite named `defaults`.
    static func preview(_ library: Library = PreviewLibrary.library, planEngine: any PlanEngine = PreviewPlanEngine(),
                        planResults: PlanResultsArchive? = nil, defaults suite: String = "preview") -> AppModel {
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        return AppModel(
            preferences: AppPreferences(defaults: defaults), library: .inMemory(library),
            prices: PriceStore(service: nil), planEngine: planEngine, planResults: planResults)
    }

    /// Whether ``keepInStep()`` runs.
    private var keepsInStep = false
    /// Whether the library was open when ``keepInStep()`` last looked.
    private var wasReady = false
    /// The widgets' inputs their snapshot was last written for.
    private var widgetInputs: WidgetStore.Inputs?

    /// Launch work: find and load the library, and keep the stores in
    /// step from then on.
    func start() async {
        if !keepsInStep {
            keepsInStep = true
            keepInStep()
        }
        guard library.phase == .starting else { return }
        await library.start()
    }

    /// Keeps the stores in step for as long as the model lives, one step
    /// each time what they read changes. It holds the model only while a
    /// step runs, so a preview's or a test's model still goes away.
    private func keepInStep() {
        Task { [weak self] in
            while let changes = await self?.step() {
                for await _ in changes {}
            }
        }
    }

    /// One step: when the library has opened (again), the plans' results
    /// kept from the last launch, then a check-in's answer the app was
    /// closed before recording; when the widgets' inputs changed, their
    /// snapshot, a second later, so a burst of changes (a check-in's files,
    /// a sync) writes it once, and then the notes scheduled from it.
    /// Returns what finishes at the next change, one during the step too.
    private func step() async -> AsyncStream<Void> {
        let (changes, continuation) = AsyncStream<Void>.makeStream()
        withObservationTracking {
            _ = library.phase
            _ = widgets.inputs
        } onChange: {
            continuation.finish()
        }
        let isReady = library.phase == .ready
        if isReady && !wasReady {
            // First, so recording a missing answer finds results of exactly this library.
            await plans.restoreKeptResults()
            plans.recordMissingCheckInAnswer()
        }
        wasReady = isReady
        if widgets.inputs != widgetInputs {
            try? await Task.sleep(for: .seconds(1))
            widgetInputs = widgets.inputs
            await widgets.refresh()
            // The notes read the same snapshot (UI.md, "Notifications").
            await notes.reschedule()
        }
        return changes
    }
}
