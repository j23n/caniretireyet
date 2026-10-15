import Foundation
import Testing
@testable import CanIRetireYet

/// Test profiles' names, folders and settings (App/README.md, "Test profiles").
@MainActor
struct TestProfilesTests {
    @Test func namesAreFolderNames() {
        #expect(TestProfile(name: "onboarding")?.name == "onboarding")
        #expect(TestProfile(name: "day-2")?.name == "day-2")
        #expect(TestProfile(name: "") == nil)
        #expect(TestProfile(name: "Onboarding") == nil)
        #expect(TestProfile(name: "../real") == nil)
        #expect(TestProfile(name: "-x") == nil)
    }

    @Test func aTypedNameBecomesAFolderName() {
        #expect(TestProfile(typed: "Onboarding 2")?.name == "onboarding-2")
        #expect(TestProfile(typed: "  New / empty  ")?.name == "new-empty")
        #expect(TestProfile(typed: "Café")?.name == "caf")
        #expect(TestProfile(typed: "../") == nil)
        #expect(TestProfile(typed: " ") == nil)
    }

    /// Each profile has a library folder of its own under the root, and
    /// settings apart from the app's.
    @Test func aProfileKeepsItsOwnFolderAndSettings() throws {
        let root = URL(fileURLWithPath: "/tmp/Profiles", isDirectory: true)
        let profile = try #require(TestProfile(name: "onboarding"))
        #expect(profile.libraryFolder(in: root).path == "/tmp/Profiles/onboarding/Library")
        #expect(profile.defaultsSuite.hasSuffix(".profile.onboarding"))
        #expect(profile.defaultsSuite != Bundle.main.bundleIdentifier)
    }

    @Test func profilesAreMadeOpenedAndErased() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-profiles-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "test-profiles-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        let profiles = TestProfiles(root: root, defaults: defaults)
        #expect(profiles.all.isEmpty)
        #expect(profiles.active == nil)

        // Unique names: a profile's settings suite is the app's own.
        let unique = UUID().uuidString.lowercased()
        let first = try #require(TestProfile(name: "a-\(unique)"))
        let second = try #require(TestProfile(name: "b-\(unique)"))
        defer {
            UserDefaults().removePersistentDomain(forName: first.defaultsSuite)
            UserDefaults().removePersistentDomain(forName: second.defaultsSuite)
        }
        try profiles.create(second)
        try profiles.create(first)
        #expect(profiles.all == [first, second])

        profiles.activate(first)
        #expect(TestProfiles(root: root, defaults: defaults).active == first)

        // Starting over leaves an empty folder; deleting leaves none.
        try Data("{}".utf8).write(to: first.folder(in: root).appendingPathComponent("library.json"))
        first.defaults.set(true, forKey: "notes.offered")
        try profiles.erase(first, keepsFolder: true)
        #expect(profiles.all == [first, second])
        #expect(try FileManager.default.contentsOfDirectory(atPath: first.folder(in: root).path).isEmpty)
        #expect(!first.defaults.bool(forKey: "notes.offered"))

        try profiles.erase(second)
        #expect(profiles.all == [first])

        // A profile in use whose folder has gone opens the real library.
        try profiles.erase(first)
        #expect(TestProfiles(root: root, defaults: defaults).active == nil)
    }
}
