import Foundation
import Observation
#if canImport(StoreKit)
import StoreKit
#endif

/// A test profile: a library and device settings of its own, for trying
/// first launch and the rest of the app without touching the real library
/// (App/README.md, "Test profiles"). Its library is on this device only, in
/// `Application Support/<bundle id>/Profiles/<name>/Library`, and never
/// looks at iCloud Drive; its settings are in a `UserDefaults` suite of its
/// own. The widgets and the notes stay the real library's.
struct TestProfile: Hashable, Identifiable, Sendable {
    /// Lowercase letters, digits and hyphens: the folder's name.
    let name: String

    var id: String { name }

    /// `nil` for a name that isn't lowercase letters, digits and hyphens.
    init?(name: String) {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        guard !name.isEmpty, name.count <= 40, name.allSatisfy(allowed.contains),
              name.first != "-", name.last != "-"
        else { return nil }
        self.name = name
    }

    /// A name made from what was typed: lowercased, with spaces and other
    /// characters as hyphens ("Onboarding 2" → "onboarding-2"); `nil` when
    /// nothing is left.
    init?(typed: String) {
        var slug = ""
        for character in typed.lowercased() {
            if character.isASCII && (character.isLetter || character.isNumber) {
                slug.append(character)
            } else if !slug.isEmpty && slug.last != "-" {
                slug.append("-")
            }
        }
        slug = String(slug.prefix(40))
        while slug.last == "-" { slug.removeLast() }
        self.init(name: slug)
    }

    /// The profile's folder in `root` (``TestProfiles/root``).
    func folder(in root: URL) -> URL {
        root.appendingPathComponent(name, isDirectory: true)
    }

    /// The library's folder in `root`.
    func libraryFolder(in root: URL) -> URL {
        folder(in: root).appendingPathComponent("Library", isDirectory: true)
    }

    /// The name of its `UserDefaults` suite.
    var defaultsSuite: String {
        "\(Bundle.main.bundleIdentifier ?? "CanIRetireYet").profile.\(name)"
    }

    /// The settings its model keeps: this device's, for this profile.
    var defaults: UserDefaults {
        UserDefaults(suiteName: defaultsSuite) ?? .standard
    }
}

/// The test profiles on this device, and the one in use (``active``).
/// Shown in Debug and TestFlight builds only, in a section of Settings that
/// tapping the version seven times reveals (UI.md, "Settings").
@Observable @MainActor
final class TestProfiles {
    /// The profiles, by name.
    private(set) var all: [TestProfile] = []
    /// The profile in use; `nil` for the real library.
    private(set) var active: TestProfile? = nil
    /// Whether Settings shows the Test profiles section. Kept, so it stays
    /// until hidden again.
    var isRevealed: Bool {
        didSet { defaults.set(isRevealed, forKey: Keys.revealed) }
    }
    /// Whether this build may use test profiles: Debug and TestFlight
    /// builds, not the App Store's. Release builds find out in
    /// ``checkAvailability()``.
    private(set) var isAvailable: Bool

    /// Where the profiles' folders are.
    @ObservationIgnored let root: URL
    @ObservationIgnored private let defaults: UserDefaults

    /// The profiles in `root`, the one in use and the section's state kept
    /// in `defaults` (the app's own, not a profile's).
    init(root: URL, defaults: UserDefaults = .standard) {
        self.root = root
        self.defaults = defaults
        isRevealed = defaults.bool(forKey: Keys.revealed)
        #if DEBUG
        isAvailable = true
        #else
        isAvailable = false
        #endif
        active = defaults.string(forKey: Keys.active).flatMap(TestProfile.init(name:))
        reload()
        if let active, !all.contains(active) { self.active = nil }
    }

    /// The app's: `Application Support/<bundle id>/Profiles`.
    static func standard() -> TestProfiles {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return TestProfiles(root: support
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "CanIRetireYet", isDirectory: true)
            .appendingPathComponent("Profiles", isDirectory: true))
    }

    /// Reads the profiles' folders again.
    func reload() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        all = names.compactMap(TestProfile.init(name:))
            .filter { isDirectory($0.folder(in: root)) }
            .sorted { $0.name < $1.name }
    }

    /// Makes `profile`'s folder. A profile of that name that exists is kept.
    func create(_ profile: TestProfile) throws {
        try FileManager.default.createDirectory(at: profile.folder(in: root), withIntermediateDirectories: true)
        reload()
    }

    /// Remembers `profile` as the one in use (`nil`: the real library).
    func activate(_ profile: TestProfile?) {
        active = profile
        defaults.set(profile?.name, forKey: Keys.active)
    }

    /// Deletes `profile`'s library and settings. Its folder stays when
    /// `keepsFolder`, empty, so the profile starts over at first launch.
    func erase(_ profile: TestProfile, keepsFolder: Bool = false) throws {
        let folder = profile.folder(in: root)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
        if keepsFolder {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        UserDefaults().removePersistentDomain(forName: profile.defaultsSuite)
        reload()
    }

    /// Asks the App Store which build this is: a TestFlight build may use
    /// test profiles too.
    func checkAvailability() async {
        guard !isAvailable else { return }
        #if canImport(StoreKit)
        if case let .verified(transaction)? = try? await AppTransaction.shared,
           transaction.environment == .sandbox {
            isAvailable = true
        }
        #endif
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private enum Keys {
        static let active = "testProfiles.active"
        static let revealed = "testProfiles.revealed"
    }
}
