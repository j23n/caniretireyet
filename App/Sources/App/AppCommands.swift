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
/// | Recalculate | ⌘R |
/// | Export Calculations… | — |
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
            Button("Recalculate") { planActions?.recalculate() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(planActions == nil)
            Divider()
            Button("Save Baseline…") { planActions?.saveBaseline() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(planActions == nil)
            Button("Duplicate Plan") { planActions?.duplicate() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(planActions == nil)
            Divider()
            Button("Export Calculations…") { planActions?.exportCalculations() }
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
    /// Recalculate (⌘R): calculate what's out of date on screen. Plans only
    /// run when asked.
    var recalculate: @MainActor () -> Void
    /// Export Calculations…: every calculation behind the plan on screen, as Markdown.
    var exportCalculations: @MainActor () -> Void
}

extension FocusedValues {
    /// The plan commands for the plan on screen.
    @Entry var planActions: PlanCommandActions?
}
