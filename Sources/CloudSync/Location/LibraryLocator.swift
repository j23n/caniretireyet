import Foundation

/// Finds the library folder: the `Documents/` folder of the app's iCloud
/// container, or a local folder in Application Support.
///
/// Looking up the iCloud container can take a while the first time (it may
/// set the container up), so ``iCloudLibraryURL()`` does it off the calling
/// thread. Nothing here creates a library; see `LibraryFolder.createLibrary`.
public struct LibraryLocator: Sendable {
    /// The iCloud container, e.g. `iCloud.com.example.caniretireyet`; `nil`
    /// for the first container in the app's entitlements.
    public var containerIdentifier: String?
    /// The folder a local library lives in. `nil` for
    /// `Application Support/<bundle id>/Library`.
    public var localFolder: URL?

    public init(containerIdentifier: String? = nil, localFolder: URL? = nil) {
        self.containerIdentifier = containerIdentifier
        self.localFolder = localFolder
    }

    /// The folder name of the library inside the iCloud container.
    public static let iCloudFolderName = "Documents"
    /// The folder name of a local library inside Application Support.
    public static let localFolderName = "Library"

    /// Whether the user is signed in to iCloud with iCloud Drive on. A quick
    /// check that doesn't touch the container.
    public var isICloudAvailable: Bool {
        #if canImport(Darwin)
        FileManager.default.ubiquityIdentityToken != nil
        #else
        false
        #endif
    }

    /// The library folder in the iCloud container (`…/Documents`), or `nil`
    /// when iCloud isn't available. Runs off the calling thread, as Apple
    /// requires. The folder may not exist yet.
    public func iCloudLibraryURL() async -> URL? {
        #if canImport(Darwin)
        guard isICloudAvailable else {
            LibraryLog.notice("iCloud Drive: not signed in, or iCloud Drive is off")
            return nil
        }
        let identifier = containerIdentifier
        let started = ContinuousClock.now
        let url = await Task.detached(priority: .userInitiated) {
            FileManager.default.url(forUbiquityContainerIdentifier: identifier)?
                .appendingPathComponent(Self.iCloudFolderName, isDirectory: true)
        }.value
        LibraryLog.notice("iCloud Drive: container \(url == nil ? "not available" : "found") after \(LibraryLog.seconds(.now - started))")
        return url
        #else
        return nil
        #endif
    }

    /// The local library folder, `Application Support/<bundle id>/Library`
    /// (or ``localFolder``). The folder may not exist yet.
    public func localLibraryURL() throws -> URL {
        if let localFolder { return localFolder }
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let bundle = Bundle.main.bundleIdentifier ?? "CanIRetireYet"
        return support
            .appendingPathComponent(bundle, isDirectory: true)
            .appendingPathComponent(Self.localFolderName, isDirectory: true)
    }

    /// The location of `kind`, or `nil` for iCloud when it isn't available.
    public func location(_ kind: LibraryLocationKind) async throws -> LibraryLocation? {
        switch kind {
        case .iCloud:
            return await iCloudLibraryURL().map { LibraryLocation(kind: .iCloud, url: $0) }
        case .local:
            return LibraryLocation(kind: .local, url: try localLibraryURL())
        }
    }
}
