import Foundation
import Model
import Testing
import Tracker
@testable import CanIRetireYet

/// The accounts in the sidebar layout (UI.md, "Navigation"), from the
/// example library (``PreviewLibrary``): a group's row lists that group's
/// accounts alone, and a selected group left without open accounts gives
/// way to *All Accounts*.
@MainActor
struct AccountsNavigationTests {
    private func list(_ library: Library = PreviewLibrary.library, group: AccountGroup? = nil) -> AccountList {
        AccountList(library: library, valuator: Valuator(library: library), group: group,
                    today: PreviewLibrary.latestCheckIn, stalenessThreshold: 45, includesSparklines: false)
    }

    @Test func aGroupListsOnlyItsAccounts() throws {
        let all = list()
        try #require(all.sections.count >= 2)
        for section in all.sections {
            let group = list(group: section.group)
            #expect(group.sections == [section])
            #expect(group.closed == all.closed.filter { $0.account.group == section.group })
        }
    }

    @Test func aGroupWithoutOpenAccountsGivesWayToAllAccounts() throws {
        var library = PreviewLibrary.library
        let group = try #require(list(library).sections.first).group
        let navigation = AppNavigation()
        navigation.sidebarSelection = .accountGroup(group)

        navigation.libraryChanged(library, today: PreviewLibrary.latestCheckIn)
        #expect(navigation.sidebarSelection == .accountGroup(group))

        for (id, account) in library.accounts where account.group == group {
            library.accounts[id]?.closed = PreviewLibrary.latestCheckIn.adding(days: -1)
        }
        navigation.accountsPath.append(try #require(library.accounts.values.first { $0.group == group }).id)
        navigation.libraryChanged(library, today: PreviewLibrary.latestCheckIn)
        #expect(navigation.sidebarSelection == .accounts)
        // The detail pushed over the group stays, over All Accounts.
        #expect(navigation.accountsPath.count == 1)
    }

    @Test func showingAnAccountPushesItOverAllAccounts() throws {
        let account = try #require(PreviewLibrary.library.accounts.keys.first)
        let navigation = AppNavigation()
        navigation.layout = .sidebar
        navigation.showAccount(account)
        #expect(navigation.sidebarSelection == .accounts)
        #expect(navigation.accountsPath.count == 1)

        navigation.sidebarSelection = .today
        #expect(navigation.accountsPath.isEmpty)
    }
}

/// The full-screen check-in on iPhone (UI.md, "Check-in"): it can only be
/// saved or cancelled, so a link or a widget opens nothing while it's open;
/// once it's saved, the saved page's tiles close it, then open their place.
@MainActor
struct CheckInNavigationTests {
    private func openCheckIn() -> AppNavigation {
        let navigation = AppNavigation()
        navigation.layout = .tabs
        navigation.startCheckIn()
        return navigation
    }

    @Test func anOpenCheckInKeepsLinksOut() {
        let navigation = openCheckIn()
        navigation.showPlan()
        navigation.showSoFar()
        navigation.showToday()
        #expect(navigation.isCheckInPresented)
        #expect(navigation.tab == .today)
        #expect(navigation.planRoute == nil)
    }

    @Test func aSavedCheckInClosesForALink() async throws {
        let navigation = openCheckIn()
        navigation.isCheckInSaved = true
        navigation.showPlan()
        #expect(!navigation.isCheckInPresented)
        #expect(!navigation.isCheckInSaved)
        try await Task.sleep(for: .milliseconds(500))
        #expect(navigation.tab == .ahead)
    }
}
