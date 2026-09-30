import SwiftUI

/// The menu commands and their shortcuts (UI.md, "Menu commands"). On the
/// Mac they're in the menu bar; on iPad, in the menu and the shortcut list.
///
/// | Command | Shortcut |
/// | --- | --- |
/// | New Account | ⌘N |
/// | New Check-in | ⌘K |
/// | Import… | ⌘⇧I |
/// | Save Baseline | ⌘⇧B |
/// | Hide Amounts | ⌘⇧H |
/// | Show Future | ⌘⇧F |
/// | Duplicate Plan | ⌘D |
/// | Compare Plans | ⌘⌥C |
///
/// The plan commands act on the plan on screen, which publishes them with
/// `.focusedSceneValue(\.planActions, …)`; they're disabled otherwise.
struct AppCommands: Commands {
    @Bindable var privacy: PrivacySettings
    @Bindable var navigation: AppNavigation
    @FocusedValue(\.planActions) var planActions

    init(privacy: PrivacySettings, navigation: AppNavigation) {
        _privacy = Bindable(privacy)
        _navigation = Bindable(navigation)
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Account") { navigation.newAccount() }
                .keyboardShortcut("n", modifiers: .command)
            Button("New Check-in") { navigation.startCheckIn() }
                .keyboardShortcut("k", modifiers: .command)
            Divider()
            Button("Import…") { navigation.startImport() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
        }

        CommandGroup(after: .toolbar) {
            Toggle("Hide Amounts", isOn: $privacy.hidesAmounts)
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Toggle("Show Future", isOn: $navigation.showsFuture)
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Divider()
        }

        CommandMenu("Plan") {
            Button("Save Baseline…") { planActions?.saveBaseline() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(planActions == nil)
            Button("Duplicate Plan") { planActions?.duplicate() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(planActions == nil)
            Button("Compare Plans") { planActions?.compare() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(planActions == nil)
        }
    }
}

/// What the plan menu commands do for the plan on screen. The Plan screen
/// publishes it with `.focusedSceneValue(\.planActions, PlanCommandActions(…))`.
struct PlanCommandActions {
    /// Save Baseline… (⌘⇧B): ask for a label and save one.
    var saveBaseline: @MainActor () -> Void
    /// Duplicate Plan (⌘D).
    var duplicate: @MainActor () -> Void
    /// Compare Plans (⌘⌥C).
    var compare: @MainActor () -> Void
}

extension FocusedValues {
    /// The plan commands for the plan on screen.
    @Entry var planActions: PlanCommandActions?
}
