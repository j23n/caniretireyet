import SwiftUI

// MARK: - The type scale

extension Font {
    /// A text style of the app's one type scale (UI.md, "Type"). Every
    /// screen, card and tile takes its text from it, so the same kind of
    /// text is the same size everywhere.
    ///
    /// On iPhone and iPad it's the system's text style, which follows
    /// Dynamic Type. The Mac's own text styles are an iPad's at about three
    /// quarters (13 pt body, 10 pt captions), which reads small beside the
    /// app's tiles and charts, and don't follow Dynamic Type; there it's
    /// the iPad's sizes at about 90% (``AppType/macSize(of:)``).
    static func app(_ style: TextStyle) -> Font {
        #if os(macOS)
        let size = AppType.macSize(of: style)
        return style == .headline ? .system(size: size, weight: .semibold) : .system(size: size)
        #else
        return .system(style)
        #endif
    }

    // MARK: Roles

    /// A heading on the page, between cards ("Your life ahead").
    static var pageHeading: Font { .app(.title2).bold() }

    /// A card's title ("Your money to 95", "Net worth", "Needs attention").
    static var cardTitle: Font { .app(.headline) }

    /// A tile's or card's figure: an amount, a date, an age, a percentage
    /// or a few words ("30 Nov", "−6%", "63", "No age yet", "15 years of
    /// spending"). Every tile's figure is this size, so a row of tiles
    /// reads as one.
    static var figure: Font { .app(.title2).bold() }
}

/// The app's type scale on the Mac (``Font/app(_:)``).
enum AppType {
    /// The point size of `style` on the Mac: the iPad's at its default text
    /// size, at about 90%, and at least 11 points.
    static func macSize(of style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 30
        case .title: 25
        case .title2: 20
        case .title3: 18
        case .headline, .body: 15
        case .callout: 14
        case .subheadline: 13
        case .footnote: 12
        case .caption, .caption2: 11
        default: 15
        }
    }
}
