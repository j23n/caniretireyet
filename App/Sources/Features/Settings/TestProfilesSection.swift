import SwiftUI

/// Settings' Test profiles section (UI.md, "Settings"; App/README.md, "Test
/// profiles"): the real library and each test profile, with the one open
/// ticked, and making, starting over and deleting profiles. Debug and
/// TestFlight builds show it once the version has been tapped seven times.
struct TestProfilesSection: View {
    let session: AppSession
    let profiles: TestProfiles
    @State private var isNaming = false
    @State private var typedName = ""
    @State private var confirmsStartOver = false
    @State private var error: String?

    var body: some View {
        Section {
            row(nil, title: "Your library")
            ForEach(profiles.all) { profile in
                row(profile, title: profile.name)
                    .contextMenu {
                        if profile != profiles.active {
                            Button("Delete", systemImage: "trash", role: .destructive) { delete(profile) }
                        }
                    }
            }
            Button("New Profile…") {
                typedName = ""
                isNaming = true
            }
            if let active = profiles.active {
                Button("Start “\(active.name)” Over…", role: .destructive) { confirmsStartOver = true }
            } else {
                Button("Hide This Section") { profiles.isRevealed = false }
            }
            if let error {
                Text(error).font(.footnote).foregroundStyle(Palette.critical)
            }
        } header: {
            Text("Test profiles")
        } footer: {
            Text("For testing. A profile has a library on this device and settings of its own, and starts at "
                + "first launch. Your library, the widgets and the notes stay as they are. Touch and hold "
                + "(on the Mac, Control-click) a profile to delete it.")
        }
        .disabled(session.isSwitching)
        .alert("New Test Profile", isPresented: $isNaming) {
            TextField("Name", text: $typedName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { create() }
        } message: {
            Text("It opens at first launch.")
        }
        .confirmationDialog("Start “\(profiles.active?.name ?? "")” over?", isPresented: $confirmsStartOver,
                            titleVisibility: .visible) {
            Button("Start Over", role: .destructive) { startOver() }
        } message: {
            Text("Its library and settings are deleted, and it opens at first launch.")
        }
    }

    /// A row that opens `profile` (the real library for `nil`), ticked while it's open.
    private func row(_ profile: TestProfile?, title: String) -> some View {
        Button {
            error = nil
            Task { await session.switchTo(profile) }
        } label: {
            HStack {
                Text(title).foregroundStyle(Palette.ink)
                Spacer()
                if profiles.active == profile {
                    Image(systemName: "checkmark").foregroundStyle(Palette.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func create() {
        error = nil
        let typed = typedName
        Task {
            do {
                try await session.createAndSwitch(typed: typed)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func startOver() {
        error = nil
        Task {
            do {
                try await session.startOver()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func delete(_ profile: TestProfile) {
        do {
            try session.delete(profile)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
