#if os(iOS)
import SwiftUI

/// iPhone (and iPad in compact width): three tabs, with the check-in in the
/// tab bar's bottom accessory while one is due or under way, so it's one
/// tap from anywhere (UI.md, "Navigation"). Settings opens from the gear in
/// the Overview's toolbar.
struct TabRoot: View {
    @Environment(AppNavigation.self) private var navigation
    @Environment(CheckInStore.self) private var checkIn

    var body: some View {
        let status = checkIn.status
        if #available(iOS 26.1, *) {
            tabs
                .tabViewBottomAccessory(isEnabled: status.isActive) {
                    CheckInAccessory()
                }
        } else {
            tabs
                .tabViewBottomAccessory {
                    CheckInAccessory()
                }
        }
    }

    private var tabs: some View {
        @Bindable var navigation = navigation
        return TabView(selection: $navigation.tab) {
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
        // iOS 26: the check-in lives in the tab bar's accessory (above). If
        // that API ever needs replacing, a prominent toolbar button calling
        // `navigation.startCheckIn()` on each tab is the fallback.
    }
}

#Preview("Tabs") {
    TabRoot()
        .previewEnvironment()
}
#endif
