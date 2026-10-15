import Foundation

/// Where tapping a widget or a note goes in the app, as a URL the app opens
/// (`caniretireyet://check-in`).
public enum GlanceLink: String, Hashable, Sendable, CaseIterable {
    /// Net worth: the Overview.
    case overview
    /// The answer: the main plan.
    case plan
    /// The check-in.
    case checkIn = "check-in"
    /// Your year: the year in review (UI.md, "Your year").
    case yourYear = "your-year"

    /// The app's URL scheme (CFBundleURLTypes in App/Config/Info.plist).
    public static let scheme = "caniretireyet"

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = rawValue
        return components.url!
    }

    /// The link a URL stands for; `nil` for any other URL, such as a file.
    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == Self.scheme, let host = components.host?.lowercased()
        else { return nil }
        self.init(rawValue: host)
    }
}
