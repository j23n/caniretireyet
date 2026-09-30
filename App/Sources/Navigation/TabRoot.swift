#if os(iOS)
import SwiftUI

/// iPhone (and iPad in compact width): three tabs, with the check-in in the
/// tab bar's bottom accessory so it's one tap from anywhere (UI.md,
/// "Navigation"). Settings opens from the gear in the Overview's toolbar.
struct TabRoot: View {
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        TabView(selection: $navigation.tab) {
            Tab("Overview", systemImage: AppSymbol.overview, value: AppTab.overview) {
                NavigationStack {
                    OverviewScreen()
                        .overviewToolbar()
                        .appDestinations()
                }
            }
            Tab("Accounts", systemImage: AppSymbol.accounts, value: AppTab.accounts) {
                NavigationStack(path: $navigation.accountsPath) {
                    AccountsScreen()
                        .appDestinations()
                }
            }
            Tab("Plan", systemImage: AppSymbol.plan, value: AppTab.plan) {
                NavigationStack {
                    PlanScreen(planID: navigation.selectedPlan)
                        .appDestinations()
                }
            }
        }
        // iOS 26: the check-in lives in the tab bar's accessory. If this API
        // ever needs replacing, a prominent toolbar button calling
        // `navigation.startCheckIn()` on each tab is the fallback.
        .tabViewBottomAccessory {
            CheckInAccessory()
        }
    }
}

#Preview("Tabs") {
    TabRoot()
        .previewEnvironment()
}
#endif
