import Foundation
import Model
import Tracker

// The Accounts section of the Mac and iPad sidebar (UI.md, "Navigation"):
// its folders, their expanded state and the selection kept in view,
// computed without SwiftUI so it can be checked on Linux. The view is
// `SidebarAccountsSection` in SidebarRoot.swift; its rows, values,
// subtotals and staleness are the Accounts list's (``AccountList``), so the
// two always agree: an account that holds nothing gets no clock
// (``AccountStaleness``).

/// A collapsible group of accounts, or *Closed*: a row in the sidebar's
/// Accounts section, and a section of the Accounts list (`AccountsScreen`).
/// Both share its expanded state.
enum SidebarAccountFolder: Hashable, Sendable {
    case group(AccountGroup)
    case closed

    /// The name kept in ``AppPreferences/collapsedAccountFolders``: the
    /// group's raw value (`"cash"`, `"cryptoAndGold"`, …), or `"closed"`.
    var key: String {
        switch self {
        case .group(let group): group.rawValue
        case .closed: "closed"
        }
    }

    /// The folder `account` sits in on `today`: *Closed* once it has closed,
    /// otherwise its group (as in the Accounts list).
    init(_ account: Account, today: CalendarDate) {
        self = AccountList.listsAsClosed(account, today: today) ? .closed : .group(account.group)
    }
}

/// The selected account and the folder it sits in. The sidebar expands
/// the folder whenever either changes, so the selected row shows: when an
/// account is shown from elsewhere (``AppNavigation/showAccount(_:)``),
/// and when the selected account is closed (it moves under *Closed*) or
/// reopened. Collapsing the folder by hand afterwards is left alone.
struct SidebarAccountReveal: Hashable, Sendable {
    var account: AccountID
    var folder: SidebarAccountFolder

    /// `nil` unless `selection` is an account of `library`.
    init?(selection: SidebarItem?, library: Library, today: CalendarDate) {
        guard case .account(let id)? = selection, let account = library.accounts[id] else { return nil }
        self.account = id
        folder = SidebarAccountFolder(account, today: today)
    }
}

extension AppPreferences {
    /// Whether `folder` is expanded in the sidebar, and in the Accounts list
    /// when not searching, on this device. The groups start expanded,
    /// *Closed* collapsed.
    func isExpanded(_ folder: SidebarAccountFolder) -> Bool {
        !collapsedAccountFolders.contains(folder.key)
    }

    /// Expands or collapses `folder`, and remembers it on this device.
    func setExpanded(_ isExpanded: Bool, _ folder: SidebarAccountFolder) {
        guard self.isExpanded(folder) != isExpanded else { return }
        if isExpanded {
            collapsedAccountFolders.remove(folder.key)
        } else {
            collapsedAccountFolders.insert(folder.key)
        }
    }
}
