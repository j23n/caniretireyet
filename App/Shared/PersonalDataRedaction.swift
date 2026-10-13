#if FEEDBACK
import FeedbackKit
#endif
import SwiftUI

// Hiding the person's data in a feedback screenshot (App/README.md,
// "Feedback"), with the same redaction that hides amounts
// (AmountRedaction.swift). While a screenshot is taken, FeedbackKit redacts
// the window for `.privacy`, as the eye does, and `appEnvironment` sets
// `hidesPersonalData`. Amounts are `.privacySensitive()` already; the rest of
// the person's data (names, their records' dates, notes, the plan's ages, a
// chart's text) is redacted only then, so the eye keeps hiding amounts alone
// (UI.md, "Privacy"). Both marks only ever add hiding: the eye hides an
// amount inside a view marked for feedback too. Compiled into the app and
// the widgets, which never set it.

extension EnvironmentValues {
    /// Whether the person's data is hidden, beyond amounts: a feedback
    /// screenshot is being taken (`appEnvironment`, Debug builds only).
    @Entry var hidesPersonalData = false
}

extension View {
    /// A view that shows the person's data and isn't an amount: a name they
    /// chose or imported, a record's date, a note, an age from the plan, a
    /// chart. It draws as a placeholder while a feedback screenshot is taken
    /// (`hidesPersonalData`); the eye leaves it readable, and still hides
    /// the amounts inside it. An amount is ``privacySensitiveAmount()``
    /// instead. `sensitive` is false for a view that only sometimes shows
    /// such data.
    ///
    ///     Text(verbatim: account.name).privacySensitiveInFeedback()
    func privacySensitiveInFeedback(_ sensitive: Bool = true) -> some View {
        modifier(PrivacySensitiveInFeedback(sensitive: sensitive))
    }

    /// A navigation title, and on the Mac the window's title, that shows the
    /// person's data, such as an account's name. It reads `hidden` while a
    /// feedback screenshot is taken: SwiftUI's redaction doesn't reach the
    /// titles UIKit and AppKit draw.
    ///
    ///     .personalNavigationTitle(account.name, hidden: "Account")
    func personalNavigationTitle(_ title: String, hidden: LocalizedStringKey) -> some View {
        modifier(PersonalNavigationTitle(title: title, hidden: hidden))
    }

    #if os(macOS)
    /// The Mac's window subtitle, when it shows the person's data, such as a
    /// file's name: empty while a feedback screenshot is taken.
    func personalNavigationSubtitle(_ subtitle: String) -> some View {
        modifier(PersonalNavigationSubtitle(subtitle: subtitle))
    }
    #endif

    /// A control UIKit or AppKit draws that shows the person's data: a picker
    /// whose choice is an account's or a plan's name, a date picker with a
    /// record's date or the birth date. It's ``privacySensitiveInFeedback()``,
    /// and FeedbackKit paints over it in a screenshot (`feedbackHidden()`),
    /// since SwiftUI's redaction doesn't reach the text the system draws.
    ///
    ///     Picker("Account", selection: $accountID) { … }.personalControl()
    func personalControl() -> some View {
        #if FEEDBACK
        privacySensitiveInFeedback().feedbackHidden()
        #else
        privacySensitiveInFeedback()
        #endif
    }
}

private struct PrivacySensitiveInFeedback: ViewModifier {
    let sensitive: Bool

    @Environment(\.hidesPersonalData) private var hidesPersonalData

    func body(content: Content) -> some View {
        // Not `.privacySensitive(false)` outside a screenshot: that would keep the amounts inside
        // readable under the eye, whatever they're marked. Redaction reasons add up, so no reason
        // leaves the eye's `.privacy` in place. One modifier either way, so the view keeps its
        // state while a screenshot is taken.
        content.redacted(reason: sensitive && hidesPersonalData ? .placeholder : [])
    }
}

private struct PersonalNavigationTitle: ViewModifier {
    let title: String
    let hidden: LocalizedStringKey

    @Environment(\.hidesPersonalData) private var hidesPersonalData

    func body(content: Content) -> some View {
        content.navigationTitle(hidesPersonalData ? Text(hidden) : Text(verbatim: title))
    }
}

#if os(macOS)
private struct PersonalNavigationSubtitle: ViewModifier {
    let subtitle: String

    @Environment(\.hidesPersonalData) private var hidesPersonalData

    func body(content: Content) -> some View {
        content.navigationSubtitle(hidesPersonalData ? Text(verbatim: "") : Text(verbatim: subtitle))
    }
}
#endif
