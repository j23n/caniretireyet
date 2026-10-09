import Model
import SwiftUI

/// The app's colours (UI.md, "Design system"), from the dataviz reference
/// palette. Each has a light and a dark variant, defined as colour sets in
/// `App/Resources/Assets.xcassets`. The widgets compile this file too, so
/// they draw in the same colours.
///
/// - **Asset classes** have fixed colours everywhere; their order (cash,
///   bonds, equity, gold, crypto, real estate, other, debt) is also the
///   stacking order, bottom to top, and passes colour-blindness checks
///   between neighbouring bands.
/// - **Lines, edges and small marks** (legend swatches, dots, thin bars)
///   use ``stroke(for:)``: in light mode orange, aqua, yellow and magenta
///   have a darker step of the same hue there, so every mark reaches 3:1 on
///   the card and on the page. Washes keep the lighter step (``color(for:)``).
/// - **Everything else** is one hue, ``accent`` (blue), with labels.
/// - **Actual history** is drawn in ``ink``, never a series colour.
/// - **Changes** use ``positive`` and ``negative`` text (``change(_:)``),
///   always with a sign and an arrow (see `DeltaText`); **status** colours
///   always come with an icon and a label (see `StatusBanner`).
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

    // MARK: Line steps
    //
    // Charts sit on the card (#fcfcfb) or, like the Overview's history, on
    // the page (#f4f4f1). On the card aqua, yellow and magenta reach only
    // 2.7, 2.1 and 2.6:1, and on the page orange only 2.9:1 too, so their
    // lines take a darker step of the same hue: orange, aqua and magenta
    // the palette's dark-mode steps (3.5, 3.1 and 3.6:1 on the page);
    // yellow, whose dark-mode step falls short (2.8:1), a step darker (3.1:1).
    // Validated as a set on both surfaces: every slot reaches 3:1, worst
    // neighbouring pair CVD ΔE 9.2, normal vision 18.2. In dark mode every
    // slot already reaches 3:1 on both, and the line step is the slot's colour.

    static let orangeStroke = Color("SeriesOrangeStroke")
    static let aquaStroke = Color("SeriesAquaStroke")
    static let yellowStroke = Color("SeriesYellowStroke")
    static let magentaStroke = Color("SeriesMagentaStroke")

    /// The categorical slots' line steps, in the order of ``series``: for
    /// lines, the edges along stacked areas, and small marks.
    static let seriesStroke: [Color] = [blue, orangeStroke, aquaStroke, yellowStroke, magentaStroke, green, violet, red]

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
    static let critical = Color("StatusCritical")

    // MARK: Surfaces

    /// Behind cards on the Overview and other scrolling pages.
    static let page = Color("SurfacePage")
    /// Cards and charts: content sits on plain surfaces.
    static let card = Color("SurfaceCard")
    /// The hairline around a card.
    static let border = Color("SurfaceBorder")

    // MARK: Lookups

    /// An asset class's slot in ``series``: cash blue, bonds orange, equity
    /// aqua, gold yellow, crypto magenta, real estate green, other violet.
    /// Classes this version doesn't know are "other".
    static func slot(for assetClass: AssetClass) -> Int {
        switch assetClass {
        case .cash: 0
        case .bonds: 1
        case .equity: 2
        case .gold: 3
        case .crypto: 4
        case .realEstate: 5
        default: 6
        }
    }

    /// An asset class's fixed colour.
    static func color(for assetClass: AssetClass) -> Color {
        series[slot(for: assetClass)]
    }

    /// An asset class's line step (``seriesStroke``): for a line, the edge
    /// along a stacked area, or a small mark. Chart colour roles
    /// (`ChartColor`) resolve in the app's `ChartSupport.swift`.
    static func stroke(for assetClass: AssetClass) -> Color {
        seriesStroke[slot(for: assetClass)]
    }

    /// A change's colour by its direction (1 up, −1 down): ``positive``,
    /// ``negative``, or ``secondaryInk`` for none.
    static func change(_ direction: Int) -> Color {
        direction > 0 ? positive : direction < 0 ? negative : secondaryInk
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
