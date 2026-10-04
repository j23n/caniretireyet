import Foundation
#if os(iOS)
import UIKit
#endif

/// Work that should finish even if the app leaves the foreground meanwhile,
/// e.g. recording the month's answer after a check-in, which the
/// confirmation says can be left to finish: on iOS it asks for background
/// time (`UIApplication.beginBackgroundTask`) until ``end()``, or until iOS
/// says the time is up. Elsewhere it does nothing. Call ``end()`` once the
/// work is done; calling it again does nothing.
@MainActor
final class BackgroundActivity {
    #if os(iOS)
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    #endif

    /// Starts asking for background time, under `name` (for the debugger).
    init(named name: String) {
        #if os(iOS)
        // The handler holds the activity until the time is up or it ends,
        // so the background task is always ended.
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) {
            self.end()
        }
        #endif
    }

    /// The work is done (or iOS's time is up): background time is no
    /// longer needed.
    func end() {
        #if os(iOS)
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
        #endif
    }
}
