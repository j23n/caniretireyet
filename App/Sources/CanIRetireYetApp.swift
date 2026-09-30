import Model
import SwiftUI

/// The app, shared by iPhone, iPad and Mac.
@main
struct CanIRetireYetApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Placeholder until the real screens exist (Overview, Accounts, Check-in,
/// Plan, Settings; see docs/PLAN.md, "App structure").
struct ContentView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Can I Retire Yet?", systemImage: "chart.line.uptrend.xyaxis")
            } description: {
                Text("Nothing here yet. Library format version \(LibrarySettings.currentSchemaVersion).")
            }
            .navigationTitle("Can I Retire Yet?")
        }
    }
}

#Preview {
    ContentView()
}
