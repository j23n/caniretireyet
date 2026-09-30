import SwiftUI

/// The app, shared by iPhone, iPad and Mac.
///
/// One `AppModel` holds every store; each scene injects them with
/// `.appEnvironment(model)`. The Mac also gets the Settings window (⌘,),
/// and every platform gets the menu commands (UI.md, "Menu commands").
@main
struct CanIRetireYetApp: App {
    @State private var model = AppModel.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .appEnvironment(model)
                .task { await model.start() }
        }
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
