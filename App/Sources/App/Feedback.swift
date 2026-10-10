#if FEEDBACK
import FeedbackKit
import Foundation

/// In-app feedback, in Debug builds only (the `FEEDBACK` condition, project.yml): a shake, a
/// screenshot, Help › Send Feedback… or Settings › Feedback opens FeedbackKit's form, and the
/// report goes to the owner's private inbox, j23n/feedback (App/README.md, "Feedback").
///
/// Amounts are hidden for the capture as the eye button hides them, and anything else marked
/// `privacySensitive()` is redacted (`AppEnvironment`).
extension FeedbackCenter {
    static func caniretireyet(navigation: AppNavigation) -> FeedbackCenter {
        let center = FeedbackCenter(configuration: FeedbackConfiguration(
            inbox: GitHubRepository(owner: "j23n", name: "feedback"),
            app: "caniretireyet",
            redaction: .custom
        ))
        center.currentScreen = { navigation.feedbackScreen }
        return center
    }
}

extension AppNavigation {
    /// Where the app is, for a report: the tab or sidebar item, a sheet, the check-in. Without
    /// account or plan IDs, which are names the person chose.
    var feedbackScreen: String {
        var parts: [String]
        switch layout {
        case .tabs:
            parts = ["tab \(tab.rawValue)"]
            if tab == .accounts, !accountsPath.isEmpty { parts.append("account detail") }
        case .sidebar:
            parts = ["sidebar \(sidebarSelection.map(Self.feedbackName) ?? "nothing selected")"]
        }
        if let sheet {
            switch sheet {
            case .importFile: parts.append("sheet import")
            default: parts.append("sheet \(sheet.id)")
            }
        }
        if isCheckInPresented { parts.append("check-in") }
        return parts.joined(separator: ", ")
    }

    private static func feedbackName(_ item: SidebarItem) -> String {
        switch item {
        case .account: "account"
        case .plan: "plan"
        default: String(describing: item)
        }
    }
}
#endif
