import Glance
import Model
import SwiftUI

/// The app's root: launch, onboarding or the main navigation, which is a
/// tab bar in compact width (iPhone) and a sidebar in regular width (iPad)
/// and on the Mac (UI.md, "Navigation"). Screens don't know which one
/// they're in; they navigate through `AppNavigation`.
struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigation.self) private var navigation
    @Environment(AppPreferences.self) private var preferences
    @Environment(NoteStore.self) private var notes
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        content
            .overlay {
                if preferences.hideInAppSwitcher && scenePhase != .active {
                    PrivacyCover()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await library.refreshFromDisk() } }
            }
            .onChange(of: notes.pendingLink, initial: true) { _, link in
                // A tapped note (UI.md, "Notifications").
                guard let link else { return }
                notes.pendingLink = nil
                open(link)
            }
            .onOpenURL { url in
                if let link = GlanceLink(url: url) {
                    open(link)
                } else {
                    openFile(url)
                }
            }
            .modifier(LayoutFromSizeClass())
    }

    /// A widget or a note was tapped: net worth and the date open Today,
    /// the answer the main plan, the check-in the check-in, *Your year* last
    /// year on the Timeline.
    private func open(_ link: GlanceLink) {
        adoptLaunchLayout()
        switch link {
        case .today: navigation.showToday()
        case .plan: navigation.showPlan()
        case .checkIn: navigation.startCheckIn()
        case .yourYear: navigation.showTimeline(.year, year: CalendarDate.today().year - 1)
        }
    }

    /// A CSV or TSV file opened from Files or Finder starts an import (on
    /// iPhone, "Import with profile…").
    private func openFile(_ url: URL) {
        guard ["csv", "tsv", "txt"].contains(url.pathExtension.lowercased()) else { return }
        adoptLaunchLayout()
        navigation.startImport(url)
    }

    /// At launch the layout may not be set yet, so on iPhone it's set here,
    /// as `LayoutFromSizeClass` would, before a link or a file is opened.
    private func adoptLaunchLayout() {
        #if os(iOS)
        if horizontalSizeClass == .compact { navigation.layout = .tabs }
        #endif
    }

    /// Onboarding's state is `OnboardingModel`, in the app model, so its
    /// steps keep their answers while *See My Answer* opens the library.
    @ViewBuilder
    private var content: some View {
        if showsOnboarding {
            OnboardingScreen()
        } else {
            switch library.phase {
            case .starting, .needsSetup:
                LibraryOpeningView()
            case .failed(let message):
                LibraryUnavailableView(message: message)
            case .ready:
                mainNavigation
                    .modifier(AppPresentation())
            }
        }
    }

    /// Onboarding shows while there's no library, and once *See My Answer*
    /// has opened the new one, until its last step's *Start*
    /// (`AppNavigation.finishesOnboarding`). While the library waits for
    /// iCloud Drive (`.starting`), the opening screen shows the progress,
    /// and onboarding comes back on the step it was on; when opening
    /// fails, the failure shows.
    private var showsOnboarding: Bool {
        switch library.phase {
        case .needsSetup: true
        case .ready: navigation.finishesOnboarding
        case .starting, .failed: false
        }
    }

    @ViewBuilder
    private var mainNavigation: some View {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            TabRoot()
        } else {
            SidebarRoot()
        }
        #else
        SidebarRoot()
        #endif
    }
}

/// Sets `AppNavigation.layout` from the width, for everything the root
/// shows: the tour and the import it pushes lay out as the main navigation
/// will, tabs in compact width and a sidebar otherwise.
private struct LayoutFromSizeClass: ViewModifier {
    @Environment(AppNavigation.self) private var navigation
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .onChange(of: horizontalSizeClass, initial: true) { _, sizeClass in
                navigation.layout = sizeClass == .compact ? .tabs : .sidebar
            }
        #else
        content
            .onAppear { navigation.layout = .sidebar }
        #endif
    }
}

/// Sheets and covers over the whole app, and dropping a CSV file anywhere
/// to import it.
private struct AppPresentation: ViewModifier {
    @Environment(AppNavigation.self) private var navigation
    @Environment(LibraryStore.self) private var library

    /// Whether the library has an error to show (a failed save, which is
    /// undone, shows wherever the user is); dismissing clears it, also from
    /// the banners that show it (`LibraryStatusBanners`).
    @MainActor private var showsLibraryError: Binding<Bool> {
        Binding(get: { library.lastError != nil }, set: { if !$0 { library.dismissError() } })
    }

    func body(content: Content) -> some View {
        @Bindable var navigation = navigation
        content
            .alert("Something went wrong with the library", isPresented: showsLibraryError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(library.lastError ?? "")
            }
            .sheet(item: $navigation.sheet) { sheet in
                AppSheetView(sheet: sheet)
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $navigation.isCheckInPresented) {
                NavigationStack {
                    CheckInScreen()
                }
            }
            #endif
            .dropDestination(for: URL.self) { urls, _ in
                guard let file = urls.first(where: { $0.pathExtension.lowercased() == "csv" }) else { return false }
                navigation.startImport(file)
                return true
            }
    }
}

/// The content of an app-wide sheet.
private struct AppSheetView: View {
    let sheet: AppSheet
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var navigation = navigation
        switch sheet {
        case .settings:
            NavigationStack {
                SettingsScreen()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }
                        }
                    }
                    // Sync & backups, pushed when a banner shows it (AppNavigation.show(_:)).
                    .navigationDestination(isPresented: $navigation.showsSyncInSheet) {
                        SyncScreen()
                    }
            }
        case .newAccount:
            NavigationStack {
                NewAccountScreen()
            }
        case .importFile(let file):
            NavigationStack {
                ImportScreen(file: file)
                    // Sync & backups, pushed over the import when one of its
                    // banners shows it: the import stays as it was under it.
                    .navigationDestination(isPresented: $navigation.showsSyncInSheet) {
                        SyncScreen()
                    }
            }
        }
    }
}

/// Shown when the library can't be opened, with a way forward. Starting a
/// library on this device is offered only when iCloud Drive isn't
/// available, not for a passing failure: it would leave the library in
/// iCloud Drive behind (Settings → Library switches back to it).
private struct LibraryUnavailableView: View {
    let message: String
    @Environment(LibraryStore.self) private var library

    var body: some View {
        ContentUnavailableView {
            Label("Can't open your library", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text(message)
                .privacySensitiveInFeedback()
        } actions: {
            Button("Try again") {
                Task { await library.start() }
            }
            .buttonStyle(.borderedProminent)
            if library.openingFailedWithoutICloud {
                Button("Start a New Library on This Device") {
                    Task { await library.useLibraryOnThisDevice() }
                }
            }
        }
        .background(Palette.page)
    }
}

/// Covers the app while it isn't active, if the user asked for it (UI.md,
/// "Privacy": hide amounts in the app switcher).
private struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Palette.page.ignoresSafeArea()
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundStyle(Palette.mutedInk)
                .accessibilityLabel("Hidden")
        }
    }
}

#Preview("Root") {
    RootView()
        .previewEnvironment()
}
