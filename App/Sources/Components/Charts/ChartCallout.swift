import Model
import SwiftUI

// A chart's callout, where the finger or the pointer reads it (UI.md,
// "History chart"): the date first, in caption 2 and secondary ink, then the
// headline amount, then the other amounts in rows, a label on the left and
// its amount on the right, all short, then what's marked there, each with
// its icon. The net-worth chart and the strips'
// read-outs on Plan and Progress build theirs from these parts, so the two
// read alike.

/// A chart's callout: its parts one under another, with `Metrics.s` of
/// padding on the callout's surface (``SwiftUI/View/calloutBackground()``),
/// up to `maxWidth` wide.
///
///     ChartCallout {
///         ChartCalloutDate(fan.date, precision: .month)
///         ChartCalloutProjection(fan: fan)
///     }
///     ChartCallout {
///         ChartCalloutDate(point.date)
///         ChartCalloutTotal(point.value)
///         ChartCalloutRow("Equity", swatch: color, amount: equity)
///     }
struct ChartCallout<Content: View>: View {
    var maxWidth: CGFloat = ChartStyle.calloutWidth
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            content
        }
        .padding(Metrics.s)
        .frame(maxWidth: maxWidth, alignment: .leading)
        .calloutBackground()
    }
}

/// A callout's first line: the date, "Mar 2034" over a projection, "31 Mar
/// 2026" over history, and after it what else says where the point is
/// ("Mar 2034 · 48", "31 Mar 2026 · check-in").
struct ChartCalloutDate: View {
    enum Precision {
        /// "Mar 2034": a projected date.
        case month
        /// "31 Mar 2026": a date in history.
        case day
    }

    let date: Date
    var precision: Precision = .day
    var detail: String?

    @Environment(\.locale) private var locale

    init(_ date: Date, precision: Precision = .day, detail: String? = nil) {
        self.date = date
        self.precision = precision
        self.detail = detail
    }

    var body: some View {
        Text(verbatim: text)
            .font(.caption2)
            .foregroundStyle(Palette.secondaryInk)
    }

    private var text: String {
        let format: Date.FormatStyle = switch precision {
        case .month: .dateTime.month(.abbreviated).year()
        case .day: .dateTime.day().month(.abbreviated).year()
        }
        let day = date.formatted(format.locale(locale))
        return detail.map { "\(day) · \($0)" } ?? day
    }
}

/// A callout's headline amount, short (`300.000 €`, `12,3M €`): the total,
/// or over a projection its median, after a small `label` ("Median") so it
/// doesn't read as an actual total.
struct ChartCalloutTotal: View {
    let amount: Double
    var label: String?
    /// `nil` for the base currency.
    var currency: CurrencyCode?

    init(_ amount: Double, label: String? = nil, currency: CurrencyCode? = nil) {
        self.amount = amount
        self.label = label
        self.currency = currency
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let label {
                Text(label).font(.caption2).foregroundStyle(Palette.secondaryInk)
            }
            AmountText(Decimal(wholeNumber: amount), currency: currency, short: true)
                .font(.caption.weight(.semibold))
        }
    }
}

/// An amount in a callout, in caption 2: its swatch, when it has one, and
/// its label on the left in secondary ink, the amount on the right, short
/// ("Equity 212.000 €", "Top 10% 1,23M €"); the amount under its label when
/// the two don't fit side by side.
struct ChartCalloutRow: View {
    let title: String
    var swatch: Color?
    let amount: Double
    /// `nil` for the base currency.
    var currency: CurrencyCode?

    init(_ title: String, swatch: Color? = nil, amount: Double, currency: CurrencyCode? = nil) {
        self.title = title
        self.swatch = swatch
        self.amount = amount
        self.currency = currency
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                label
                Spacer(minLength: 4)
                value
            }
            VStack(alignment: .leading, spacing: 0) {
                label
                value
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .font(.caption2)
    }

    private var label: some View {
        HStack(spacing: 4) {
            if let swatch {
                Circle().fill(swatch).frame(width: 6, height: 6)
            }
            Text(title).foregroundStyle(Palette.secondaryInk)
        }
    }

    private var value: some View {
        AmountText(Decimal(wholeNumber: amount), currency: currency, short: true)
    }
}

/// A projection read at a date, under the callout's date: "Median" and the
/// median as the headline, then *Top 10%* (the 90th percentile) and *Bottom
/// 10%* (the 10th), each with the 10–90% band's swatch.
struct ChartCalloutProjection: View {
    let fan: FanPoint
    /// `nil` for the base currency.
    var currency: CurrencyCode?

    var body: some View {
        let band = Palette.accent.opacity(ProjectionLegend.outerBand)
        VStack(alignment: .leading, spacing: 2) {
            ChartCalloutTotal(fan.p50, label: "Median", currency: currency)
            ChartCalloutRow("Top 10%", swatch: band, amount: fan.p90, currency: currency)
            ChartCalloutRow("Bottom 10%", swatch: band, amount: fan.p10, currency: currency)
        }
    }
}

/// Something marked where a callout reads, at its bottom: a marker's label
/// with its icon, a milestone with its flag, an event with its dot, and a
/// line under it when it says more ("Typically by mid 2034").
struct ChartCalloutMarker<Icon: View>: View {
    let title: String
    var detail: String?
    let icon: Icon

    init(_ title: String, detail: String? = nil, @ViewBuilder icon: () -> Icon) {
        self.title = title
        self.detail = detail
        self.icon = icon()
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                if let detail {
                    Text(detail)
                }
            }
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            icon
        }
        .font(.caption2)
        .foregroundStyle(Palette.secondaryInk)
    }
}

extension ChartCalloutMarker where Icon == Image {
    /// A marker with a symbol: "Retire at 50" with its walking figure.
    init(_ title: String, detail: String? = nil, systemImage: String) {
        self.init(title, detail: detail) { Image(systemName: systemImage) }
    }
}
