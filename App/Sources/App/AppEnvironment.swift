#if FEEDBACK
import FeedbackKit
#endif
import Model
import SwiftUI

extension EnvironmentValues {
    /// The library's base currency, for `AmountText` and charts. Set by the
    /// root view from `library.json` once the library is loaded
    /// (`LibraryStore.shownCurrency`); until then no currency, since nothing
    /// shows amounts before.
    @Entry var baseCurrency: CurrencyCode = .noCurrency

    /// The surface a chart sits on, in which it draws the gaps between its
    /// stacked areas: a card's by default. A chart placed straight on the
    /// page (the Overview's history) sets `Palette.page`.
    @Entry var chartSurface: Color = Palette.card
}

extension View {
    /// Injects every store of `model` into the environment. Each scene (the
    /// main window, the Mac's Settings window, extra windows) applies it.
    ///
    /// It sets the pages' layout from the navigation's (``PageLayout``).
    ///
    /// It also hides amounts (UI.md, "Privacy"): while the eye is on, the
    /// scene is redacted for `.privacy`, so every view marked
    /// `.privacySensitive()` draws as a placeholder, and views read
    /// `redactionReasons.hidesAmounts` (AmountRedaction.swift). In Debug
    /// builds it hides the person's data in a feedback screenshot: FeedbackKit
    /// redacts the scene for `.privacy` while capturing, and
    /// `hidesPersonalData` redacts the views with the rest of the person's
    /// data (PersonalDataRedaction.swift, Feedback.swift).
    func appEnvironment(_ model: AppModel) -> some View {
        modifier(AppEnvironmentModifier(model: model))
    }
}

private struct AppEnvironmentModifier: ViewModifier {
    let model: AppModel

    func body(content: Content) -> some View {
        content
            .environment(model.preferences)
            .environment(model.navigation)
            .environment(model.library)
            .environment(model.prices)
            .environment(model.plans)
            .environment(model.checkIn)
            .environment(model.widgets)
            .environment(\.baseCurrency, model.library.shownCurrency)
            .environment(\.pageLayout, PageLayout(isWide: model.navigation.layout == .sidebar))
            .redacted(reason: model.preferences.hidesAmounts ? .privacy : [])
            #if FEEDBACK
            // While a feedback screenshot is taken, FeedbackKit's `.privacySensitiveViews` redacts
            // the scene for `.privacy` itself, which hides amounts as the eye does; the rest of the
            // person's data is redacted only then (Feedback.swift).
            .environment(\.hidesPersonalData, model.feedback.isCapturing)
            .feedbackRedaction(model.feedback)
            .environment(model.feedback)
            #endif
    }
}
