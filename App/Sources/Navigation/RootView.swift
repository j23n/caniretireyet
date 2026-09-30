import SwiftUI

/// The app's root: launch, onboarding or the main navigation, which is a
/// tab bar in compact width (iPhone) and a sidebar in regular width (iPad)
/// and on the Mac (UI.md, "Navigation"). Screens don't know which one
/// they're in; they navigate through `AppNavigation`.
struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigation.self) private var navigation
    @Environment(CheckInStore.self) private var checkIn
    @Environment(PrivacySettings.self) private var privacy
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        content
            .overlay {
                if privacy.hideInAppSwitcher && scenePhase != .active {
                    PrivacyCover()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { checkIn.persistNow() }
                if phase == .active { Task { await library.refreshFromDisk() } }
            }
            .onOpenURL { url in
                openFile(url)
            }
    }

    /// A CSV or TSV file opened from Files or Finder starts an import (on
    /// iPhone, "Import with profile…"). At launch the layout isn't set yet,
    /// so on iPhone the import sheet is chosen here.
    private func openFile(_ url: URL) {
        guard ["csv", "tsv", "txt"].contains(url.pathExtension.lowercased()) else { return }
        #if os(iOS)
        if horizontalSizeClass == .compact {
            navigation.sheet = .importFile(url)
            return
        }
        #endif
        navigation.startImport(url)
    }

    @ViewBuilder
    private var content: some View {
        switch library.phase {
        case .starting:
            ProgressView("Opening your library…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.page)
        case .needsSetup:
            OnboardingScreen()
        case .failed(let message):
            LibraryUnavailableView(message: message)
        case .ready:
            mainNavigation
                .modifier(AppPresentation())
        }
    }

    @ViewBuilder
    private var mainNavigation: some View {
        #if os(iOS)
        Group {
            if horizontalSizeClass == .compact {
                TabRoot()
            } else {
                SidebarRoot()
            }
        }
        .onChange(of: horizontalSizeClass, initial: true) { _, sizeClass in
            navigation.layout = sizeClass == .compact ? .tabs : .sidebar
        }
        #else
        SidebarRoot()
            .onAppear { navigation.layout = .sidebar }
        #endif
    }
}

/// Sheets and covers over the whole app, and dropping a CSV file anywhere
/// to import it.
private struct AppPresentation: ViewModifier {
    @Environment(AppNavigation.self) private var navigation

    func body(content: Content) -> some View {
        @Bindable var navigation = navigation
        content
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        switch sheet {
        case .settings:
            NavigationStack {
                SettingsScreen()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }
                        }
                    }
            }
        case .newAccount:
            NavigationStack {
                NewAccountScreen()
            }
        case .importFile(let file):
            NavigationStack {
                ImportScreen(file: file)
            }
        case .welcome:
            NavigationStack {
                WelcomeNextStepsView()
            }
        }
    }
}

/// Shown when the library can't be opened, with a way forward.
private struct LibraryUnavailableView: View {
    let message: String
    @Environment(LibraryStore.self) private var library

    var body: some View {
        ContentUnavailableView {
            Label("Can't open your library", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try again") {
                Task { await library.start() }
            }
            .buttonStyle(.borderedProminent)
            Button("Keep the library on this device instead") {
                Task { await library.useLibraryOnThisDevice() }
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
