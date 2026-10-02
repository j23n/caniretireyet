import Model
import SwiftUI

extension EnvironmentValues {
    /// The library's base currency, for `AmountText` and charts. Set by the
    /// root view from `library.json` once the library is loaded
    /// (`LibraryStore.shownCurrency`); until then no currency, since nothing
    /// shows amounts before.
    @Entry var baseCurrency: CurrencyCode = .noCurrency

    /// Whether amounts are hidden (the eye button, ⌘⇧H). Set by the root
    /// view from `PrivacySettings`; `AmountText` reads it.
    @Entry var hidesAmounts: Bool = false

    /// The surface a chart sits on, in which it draws the gaps between its
    /// stacked areas: a card's by default. A chart placed straight on the
    /// page (the Overview's history) sets `Palette.page`.
    @Entry var chartSurface: Color = Palette.card
}

extension View {
    /// Injects every store of `model` into the environment. Each scene (the
    /// main window, the Mac's Settings window, extra windows) applies it.
    func appEnvironment(_ model: AppModel) -> some View {
        modifier(AppEnvironmentModifier(model: model))
    }
}

private struct AppEnvironmentModifier: ViewModifier {
    let model: AppModel

    func body(content: Content) -> some View {
        content
            .environment(model.preferences)
            .environment(model.privacy)
            .environment(model.navigation)
            .environment(model.library)
            .environment(model.prices)
            .environment(model.plans)
            .environment(model.checkIn)
            .environment(\.baseCurrency, model.library.shownCurrency)
            .environment(\.hidesAmounts, model.privacy.hidesAmounts)
    }
}
