import Model
import SwiftUI

/// The app's colours (UI.md, "Design system"), from the dataviz reference
/// palette. Each has a light and a dark variant, defined as colour sets in
/// `App/Resources/Assets.xcassets`.
///
/// - **Asset classes** have fixed colours everywhere; their order (cash,
///   bonds, equity, gold, crypto, real estate, other, debt) is also the
///   stacking order, bottom to top, and passes colour-blindness checks
///   between neighbouring bands.
/// - **Everything else** is one hue, ``accent`` (blue), with labels.
/// - **Actual history** is drawn in ``ink``, never a series colour.
/// - **Changes** use ``positive`` and ``negative`` text, always with a sign
///   and an arrow (see `DeltaText`); **status** colours always come with an
///   icon and a label (see `StatusBanner`).
enum Palette {
    // MARK: Categorical slots, in fixed order

    static let blue = Color("SeriesBlue")
    static let orange = Color("SeriesOrange")
    static let aqua = Color("SeriesAqua")
    static let yellow = Color("SeriesYellow")
    static let magenta = Color("SeriesMagenta")
    static let green = Color("SeriesGreen")
    static let violet = Color("SeriesViolet")
    static let red = Color("SeriesRed")

    /// The categorical slots in order. A ninth series folds into "Other";
    /// colours are never cycled.
    static let series: [Color] = [blue, orange, aqua, yellow, magenta, green, violet, red]

    // MARK: Roles

    /// The one hue for single-series charts, fan charts and success curves.
    static let accent = blue
    /// Actual history, and primary text.
    static let ink = Color("InkPrimary")
    static let secondaryInk = Color("InkSecondary")
    /// Axis labels and captions.
    static let mutedInk = Color("InkMuted")
    /// Chart gridlines: hairline and recessive.
    static let gridline = Color("ChartGridline")
    /// Chart baselines and axes.
    static let axis = Color("ChartAxis")
    /// A good change (▲), as text.
    static let positive = Color("DeltaUp")
    /// A bad change (▼), as text.
    static let negative = Color("DeltaDown")
    /// Debts, in the asset-class breakdown.
    static let debt = red

    // MARK: Status (always with an icon and a label)

    static let good = Color("StatusGood")
    static let warning = Color("StatusWarning")
    static let serious = Color("StatusSerious")
    static let critical = Color("StatusCritical")

    // MARK: Surfaces

    /// Behind cards on the Overview and other scrolling pages.
    static let page = Color("SurfacePage")
    /// Cards and charts: content sits on plain surfaces.
    static let card = Color("SurfaceCard")
    /// The hairline around a card.
    static let border = Color("SurfaceBorder")

    // MARK: Lookups

    /// An asset class's fixed colour. Classes this version doesn't know are "other".
    static func color(for assetClass: AssetClass) -> Color {
        switch assetClass {
        case .cash: blue
        case .bonds: orange
        case .equity: aqua
        case .gold: yellow
        case .crypto: magenta
        case .realEstate: green
        default: violet
        }
    }

    /// The colour for a chart colour role.
    static func color(for role: ChartColor) -> Color {
        switch role {
        case .assetClass(let assetClass): color(for: assetClass)
        case .debt: debt
        case .series(let index): series[min(max(index, 0), series.count - 1)]
        case .accent: accent
        case .ink: ink
        case .neutral: mutedInk
        case .positive: positive
        case .negative: negative
        }
    }
}

/// Spacing and shapes, so screens line up.
enum Metrics {
    /// 4 pt.
    static let xs: CGFloat = 4
    /// 8 pt.
    static let s: CGFloat = 8
    /// 12 pt.
    static let m: CGFloat = 12
    /// 16 pt: card padding and the gap between cards.
    static let l: CGFloat = 16
    /// 24 pt.
    static let xl: CGFloat = 24
    /// Card corners.
    static let cardRadius: CGFloat = 16
    /// Chart lines (UI.md: 2 pt).
    static let lineWidth: CGFloat = 2
    /// Rounded bar ends.
    static let barRadius: CGFloat = 4
    /// The largest a readable page gets on a wide window.
    static let readableWidth: CGFloat = 760
}
