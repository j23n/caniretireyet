import Foundation
import Observation
import SwiftUI

/// The app's model, and switching it to a test profile and back
/// (``TestProfiles``, App/README.md, "Test profiles"). The app holds one
/// session; each scene injects its model's stores
/// (`.appEnvironment(session.model)`) and the session, which Settings'
/// Test profiles section and the profile's banner read.
@Observable @MainActor
final class AppSession {
    /// Every store the app has, for the library in use.
    private(set) var model: AppModel
    /// Goes up each time ``model`` is replaced: the window's content is
    /// rebuilt for the new one.
    private(set) var generation = 0
    /// The test profiles; `nil` for a made-up library (``ScreenLaunch``).
    let profiles: TestProfiles?
    /// Whether ``model`` is being replaced.
    private(set) var isSwitching = false

    init(model: AppModel, profiles: TestProfiles?) {
        self.model = model
        self.profiles = profiles
    }

    /// The session at launch. In a Debug build launched with
    /// `-screenLibrary`, a made-up library (``ScreenLaunch``); else the test
    /// profile in use, or the real app. In a Debug build,
    /// `-testProfile <name>` switches to that profile first, making it if
    /// it's new.
    static func atLaunch() -> AppSession {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let launch = ScreenLaunch(arguments: arguments) {
            return AppSession(model: launch.model(), profiles: nil)
        }
        #endif
        let profiles = TestProfiles.standard()
        #if DEBUG
        if let index = arguments.firstIndex(of: "-testProfile"), arguments.indices.contains(index + 1),
           let profile = TestProfile(name: arguments[index + 1]), (try? profiles.create(profile)) != nil {
            profiles.activate(profile)
        }
        #endif
        return AppSession(model: makeModel(for: profiles), profiles: profiles)
    }

    /// Opens `profile`, or the real library for `nil`.
    func switchTo(_ profile: TestProfile?) async {
        guard let profiles, profile != profiles.active else { return }
        try? await replaceModel { profiles.activate(profile) }
    }

    /// Goes back to the real library when a profile is open in a build that
    /// turns out not to have test profiles: an App Store build that
    /// replaced a TestFlight one keeps the app's data, the profile in use
    /// with it. Asks the App Store only while a profile is open.
    func leaveProfileIfUnavailable() async {
        guard let profiles, profiles.active != nil else { return }
        await profiles.checkAvailability()
        if !profiles.isAvailable {
            await switchTo(nil)
        }
    }

    /// Makes a profile named from `typed` and opens it, at first launch.
    func createAndSwitch(typed: String) async throws {
        guard let profiles else { return }
        guard let profile = TestProfile(typed: typed) else { throw TestProfileError.invalidName }
        guard !profiles.all.contains(profile) else { throw TestProfileError.exists(profile.name) }
        try profiles.create(profile)
        await switchTo(profile)
    }

    /// Erases the profile in use and opens it again, at first launch.
    func startOver() async throws {
        guard let profiles, let profile = profiles.active else { return }
        try await replaceModel { try self.erase(profile, keepsFolder: true) }
    }

    /// Deletes `profile`, unless it's in use.
    func delete(_ profile: TestProfile) throws {
        guard let profiles, profile != profiles.active else { return }
        try erase(profile, keepsFolder: false)
    }

    /// Deletes a profile's library, its settings and its plans' kept results.
    private func erase(_ profile: TestProfile, keepsFolder: Bool) throws {
        guard let profiles else { return }
        if let archive = PlanResultsArchive.standard() {
            let results = archive.folder(forLibraryAt: profile.libraryFolder(in: profiles.root))
            try? FileManager.default.removeItem(at: results)
        }
        try profiles.erase(profile, keepsFolder: keepsFolder)
    }

    /// Lets the model in use finish its saves and let go of its folder,
    /// runs `change`, then opens the profile in use (or the real library).
    /// A new model opens even when `change` fails.
    private func replaceModel(_ change: () throws -> Void) async throws {
        guard let profiles, !isSwitching else { return }
        isSwitching = true
        defer { isSwitching = false }
        await model.library.waitForPendingWrites()
        model.library.close()
        var failure: (any Error)?
        do {
            try change()
        } catch {
            failure = error
        }
        model = Self.makeModel(for: profiles)
        generation += 1
        if let failure { throw failure }
    }

    private static func makeModel(for profiles: TestProfiles) -> AppModel {
        profiles.active.map { AppModel.live(in: $0, root: profiles.root) } ?? AppModel.live()
    }
}

/// Why a test profile couldn't be made.
enum TestProfileError: LocalizedError, Equatable {
    case invalidName
    case exists(String)

    var errorDescription: String? {
        switch self {
        case .invalidName: "Use letters and digits for the profile's name."
        case let .exists(name): "There's a profile named “\(name)” already."
        }
    }
}

/// The strip over the window while a test profile is open, so it's never
/// taken for the real library, with *Leave* to go back to it. On iPhone and
/// iPad it sits above the content, so navigation bars and their toolbars
/// start below it; on the Mac it's an inset under the window's toolbar.
struct TestProfileBanner: ViewModifier {
    @Environment(AppSession.self) private var session: AppSession?

    func body(content: Content) -> some View {
        #if os(iOS)
        VStack(spacing: 0) {
            strip
            content
        }
        #else
        content.safeAreaInset(edge: .top, spacing: 0) { strip }
        #endif
    }

    @ViewBuilder
    private var strip: some View {
        if let session, let profile = session.profiles?.active {
            HStack(spacing: Metrics.s) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                Text("Test profile “\(profile.name)”")
                    .font(.footnote.weight(.semibold))
                Spacer(minLength: Metrics.s)
                Button("Leave") {
                    Task { await session.switchTo(nil) }
                }
                .font(.footnote.weight(.semibold))
                .disabled(session.isSwitching)
            }
            .padding(.horizontal, Metrics.l)
            .padding(.vertical, Metrics.xs)
            .foregroundStyle(Palette.ink)
            .background(Palette.warning.opacity(0.35))
        }
    }
}

extension View {
    /// ``TestProfileBanner``: a strip over the window while a test profile is open.
    func testProfileBanner() -> some View {
        modifier(TestProfileBanner())
    }
}
