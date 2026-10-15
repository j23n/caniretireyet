#if FEEDBACK
import FeedbackKit
#endif
import SwiftUI

/// The app, shared by iPhone, iPad and Mac.
///
/// One `AppModel` holds every store; each scene injects them with
/// `.appEnvironment(model)`, and the `AppSession` that holds the model,
/// which replaces it when a test profile is opened or left. The Mac also
/// gets the Settings window (⌘,), and every platform gets the menu
/// commands (UI.md, "Menu commands").
///
/// **The Mac window** opens at 1200 × 800 and can be made as small as
/// 900 × 600. A window can't be smaller than the minimum size of its
/// content, so the root's minimum is fixed (``FixedMinimumSize``) rather
/// than measured through the pages, whose minimums move as they lay out
/// for a narrower width; every page's content scrolls, or is pinned and short.
@main
struct CanIRetireYetApp: App {
    @State private var session = AppSession.atLaunch()

    private var model: AppModel { session.model }

    var body: some Scene {
        WindowGroup {
            #if os(macOS)
            FixedMinimumSize(minWidth: 900, minHeight: 600) {
                root
            }
            #else
            root
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1_200, height: 800)
        .windowResizability(.contentMinSize)
        #endif
        .commands {
            AppCommands(preferences: model.preferences, navigation: model.navigation)
            #if FEEDBACK
            FeedbackCommands(center: model.feedback)
            #endif
        }

        #if os(macOS)
        Settings {
            NavigationStack {
                SettingsScreen()
            }
            .appEnvironment(model)
            .environment(session)
            .frame(minWidth: 480, idealWidth: 560, minHeight: 420, idealHeight: 620)
        }
        #endif
    }

    /// The window's content: the root view with every store, built again
    /// for each model the session opens.
    private var root: some View {
        RootView()
            .testProfileBanner()
            .appEnvironment(model)
            .environment(session)
            .task {
                await model.start()
                await session.leaveProfileIfUnavailable()
            }
            .id(session.generation)
    }
}
