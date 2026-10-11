#if FEEDBACK
import FeedbackKit
import Foundation

/// In-app feedback, in Debug builds only (the `FEEDBACK` condition, project.yml): a shake, a
/// screenshot, Help › Send Feedback… or Settings › Feedback opens FeedbackKit's form, and the
/// report goes to the owner's private inbox, j23n/feedback (App/README.md, "Feedback").
///
/// The screenshot hides the person's data and keeps the app's own text: for the capture,
/// FeedbackKit's `.privacySensitiveViews` redaction redacts each window for privacy
/// (`AppEnvironment`), which draws placeholders for the views marked `.privacySensitive()`
/// (amounts, names, record dates, notes; charts' text), and paints over the text in text fields.
/// Labels, headers, footers, buttons and empty states stay readable. Titles and controls UIKit
/// and AppKit draw with the person's data use `personalNavigationTitle(_:hidden:)` and
/// `personalControl()` (`PersonalData.swift`).
extension FeedbackCenter {
    static func caniretireyet(navigation: AppNavigation) -> FeedbackCenter {
        let center = FeedbackCenter(configuration: FeedbackConfiguration(
            inbox: GitHubRepository(owner: "j23n", name: "feedback"),
            app: "caniretireyet",
            redaction: .privacySensitiveViews
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
