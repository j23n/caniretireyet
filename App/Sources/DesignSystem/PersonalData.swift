#if FEEDBACK
import FeedbackKit
#endif
import SwiftUI

/// Marks for what shows the person's data, beyond `.privacySensitive()`
/// (App/README.md, "Feedback"). A feedback screenshot redacts the window
/// for privacy, which hides only the views marked `.privacySensitive()`;
/// these cover what SwiftUI's redaction doesn't reach: the titles and
/// controls UIKit and AppKit draw.
extension View {
    /// A navigation title, and on the Mac the window's title, that shows the
    /// person's data, such as an account's name. While the window is
    /// redacted for privacy (a feedback screenshot) it reads `hidden`.
    ///
    ///     .personalNavigationTitle(account.name, hidden: "Account")
    func personalNavigationTitle(_ title: String, hidden: LocalizedStringKey) -> some View {
        modifier(PersonalNavigationTitle(title: title, hidden: hidden))
    }

    #if os(macOS)
    /// The Mac's window subtitle, when it shows the person's data, such as
    /// a file's name: empty while the window is redacted for privacy.
    func personalNavigationSubtitle(_ subtitle: String) -> some View {
        modifier(PersonalNavigationSubtitle(subtitle: subtitle))
    }
    #endif

    /// A control UIKit or AppKit draws that shows the person's data: a
    /// picker whose choice is an account's or a plan's name, a date picker
    /// with a record's date or the birth date. It's marked
    /// `.privacySensitive()`, and painted over in a feedback screenshot
    /// (FeedbackKit's `feedbackHidden()`), since SwiftUI's redaction doesn't
    /// reach the text the system draws.
    ///
    ///     Picker("Account", selection: $accountID) { … }.personalControl()
    func personalControl() -> some View {
        #if FEEDBACK
        privacySensitive().feedbackHidden()
        #else
        privacySensitive()
        #endif
    }
}

private struct PersonalNavigationTitle: ViewModifier {
    let title: String
    let hidden: LocalizedStringKey

    @Environment(\.redactionReasons) private var redactionReasons

    func body(content: Content) -> some View {
        // One branch, so the screen keeps its state while a screenshot is taken.
        content.navigationTitle(redactionReasons.contains(.privacy) ? Text(hidden) : Text(verbatim: title))
    }
}

#if os(macOS)
private struct PersonalNavigationSubtitle: ViewModifier {
    let subtitle: String

    @Environment(\.redactionReasons) private var redactionReasons

    func body(content: Content) -> some View {
        content.navigationSubtitle(redactionReasons.contains(.privacy) ? Text(verbatim: "") : Text(verbatim: subtitle))
    }
}
#endif
