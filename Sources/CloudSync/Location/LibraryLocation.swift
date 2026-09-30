import Foundation

/// Where a library folder is kept.
public enum LibraryLocationKind: String, Hashable, Sendable, Codable, CaseIterable, CustomStringConvertible {
    /// The `Documents/` folder of the app's iCloud container, shown as
    /// "Can I Retire Yet" in iCloud Drive. Synced between devices.
    case iCloud
    /// A folder in the app's Application Support on this device. Not synced;
    /// it can be moved to iCloud later.
    case local

    /// "iCloud Drive" or "This device".
    public var description: String {
        switch self {
        case .iCloud: "iCloud Drive"
        case .local: "This device"
        }
    }
}

/// A library folder and where it is kept.
public struct LibraryLocation: Hashable, Sendable {
    public var kind: LibraryLocationKind
    /// The library folder: the one holding `library.json`.
    public var url: URL

    public init(kind: LibraryLocationKind, url: URL) {
        self.kind = kind
        self.url = url
    }

    /// Whether the folder is synced through iCloud Drive.
    public var isUbiquitous: Bool { kind == .iCloud }
}
