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
        navigation.libraryChanged(library, today: PreviewLibrary.latestCheckIn)
        #expect(navigation.sidebarSelection == .accounts)
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
