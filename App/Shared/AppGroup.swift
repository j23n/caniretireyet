import Foundation
import Glance

/// The App Group the app shares with its widgets: the app writes the
/// widgets' snapshot (`Glance.GlanceFile`) into the group's container, and
/// the widget extension reads it there. Compiled into both targets.
///
/// The identifier is the Info.plist's `AppGroupIdentifier`, set from the
/// build setting `APP_GROUP_IDENTIFIER` (project.yml), which the
/// entitlements use too.
enum AppGroup {
    /// The group's identifier, e.g. `group.com.j23n.caniretireyet`.
    static var identifier: String? {
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String,
              !identifier.isEmpty, !identifier.contains("$(")
        else { return nil }
        return identifier
    }

    /// The widgets' snapshot in the group's container; `nil` when this build
    /// has no App Group.
    static var snapshotURL: URL? {
        #if canImport(Darwin)
        guard let identifier,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        else { return nil }
        return container.appendingPathComponent(GlanceFile.name)
        #else
        return nil
        #endif
    }
}
