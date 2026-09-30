import Foundation
import Observation

/// Hiding amounts (UI.md, "Privacy").
///
/// ``hidesAmounts`` is what the eye button and ⌘⇧H toggle; the root view
/// passes it to every `AmountText` through the environment, so amounts show
/// as `•••••` while charts keep their shape. The other two are settings of
/// this device.
@Observable @MainActor
final class PrivacySettings {
    /// Whether amounts are hidden right now.
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
        hideAmountsOnLaunch = defaults.bool(forKey: Keys.hideAmountsOnLaunch)
        hideInAppSwitcher = defaults.bool(forKey: Keys.hideInAppSwitcher)
        hidesAmounts = defaults.bool(forKey: Keys.hideAmountsOnLaunch)
    }

    func toggleHidesAmounts() {
        hidesAmounts.toggle()
    }

    private enum Keys {
        static let hideAmountsOnLaunch = "privacy.hideAmountsOnLaunch"
        static let hideInAppSwitcher = "privacy.hideInAppSwitcher"
    }
}
