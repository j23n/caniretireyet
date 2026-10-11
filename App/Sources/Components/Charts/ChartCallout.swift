import Model
import SwiftUI

// A chart's callout, where the finger or the pointer reads it (UI.md,
// "Charts"): the date first, in caption 2 and secondary ink, then the values
// in rows, a label on the left and its value on the right, then what's
// marked there, each with its icon. The net-worth chart and the strips'
// read-outs on Plan and Progress build theirs from these parts, so the two
// read alike.

/// A chart's callout: its parts one under another, with `Metrics.s` of
/// padding on the callout's surface (``SwiftUI/View/calloutBackground()``),
/// up to `maxWidth` wide.
///
///     ChartCallout {
///         ChartCalloutDate(fan.date, precision: .month)
///         ChartCalloutRow("Median") { AmountText(median) }
///         ChartCalloutRow("25–75%") { ChartCalloutRange(low: fan.p25, high: fan.p75) }
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

/// A value in a callout: its label on the left in secondary ink, the value
/// on the right, in caption 2 ("Median 640.000 €"); the value under its
/// label when the two don't fit side by side.
struct ChartCalloutRow<Value: View>: View {
    let title: String
    let value: Value

    init(_ title: String, @ViewBuilder value: () -> Value) {
        self.title = title
        self.value = value()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Metrics.s) {
                label
                Spacer(minLength: Metrics.s)
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
        Text(title)
            .foregroundStyle(Palette.secondaryInk)
    }
}

/// A band's range in a callout's row, in full amounts: "410.000 € –
/// 980.000 €". Hidden with the eye, as every ``AmountText`` is.
struct ChartCalloutRange: View {
    let low: Double
    let high: Double
    /// `nil` for the base currency.
    var currency: CurrencyCode?

    var body: some View {
        HStack(spacing: 2) {
            AmountText(Decimal(wholeNumber: low), currency: currency)
            Text(verbatim: "–")
            AmountText(Decimal(wholeNumber: high), currency: currency)
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
