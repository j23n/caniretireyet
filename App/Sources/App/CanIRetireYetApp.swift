import SwiftUI

/// The app, shared by iPhone, iPad and Mac.
///
/// One `AppModel` holds every store; each scene injects them with
/// `.appEnvironment(model)`. The Mac also gets the Settings window (⌘,),
/// and every platform gets the menu commands (UI.md, "Menu commands").
///
/// **The Mac window** opens at 1200 × 800 and can be made as small as
/// 900 × 600. A window can't be smaller than the minimum size of its
/// content, so every page's content scrolls, or is pinned and short, and
/// the root asks for no more than that minimum: a page that didn't scroll
/// would otherwise make the window taller than the screen.
@main
struct CanIRetireYetApp: App {
    @State private var model = AppModel.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .appEnvironment(model)
                .task { await model.start() }
                #if os(macOS)
                .frame(minWidth: 900, minHeight: 600)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1_200, height: 800)
        .windowResizability(.contentMinSize)
        #endif
        .commands {
            AppCommands(privacy: model.privacy, navigation: model.navigation)
        }

        #if os(macOS)
        Settings {
            NavigationStack {
                SettingsScreen()
            }
            .appEnvironment(model)
            .frame(minWidth: 480, idealWidth: 560, minHeight: 420, idealHeight: 620)
        }
        #endif
    }
}
