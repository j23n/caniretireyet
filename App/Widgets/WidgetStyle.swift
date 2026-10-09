import Glance
import Model
import SwiftUI
import WidgetKit

/// Amounts and changes worded as the app words them (`AmountFormat`,
/// `DeltaFormat`): `312.480 €`, `▲ +4.210 €`, `▲ +1,4%`.
struct WidgetMoney {
    var currency: CurrencyCode
    var locale: Locale

    func amount(_ value: Decimal) -> String {
        AmountFormat.amount(value, currency: currency, locale: locale)
    }

    /// A signed amount without an arrow, for a column: `+2.950 €`.
    func signed(_ value: Decimal) -> String {
        AmountFormat.signedAmount(value, currency: currency, locale: locale)
    }

    /// `▲ +4.210 €` and its direction.
    func change(_ value: Decimal) -> WidgetDelta {
        let direction = DeltaFormat.direction(of: value, precision: .whole)
        return WidgetDelta(text: DeltaFormat.text(signed(value), direction: direction, showsArrow: true),
                           direction: direction)
    }

    /// `▲ +1,4%` and its direction.
    func percentChange(_ fraction: Double) -> WidgetDelta {
        let direction = DeltaFormat.direction(ofFraction: fraction)
        let number = AmountFormat.percent(fraction, signed: true, locale: locale)
        return WidgetDelta(text: DeltaFormat.text(number, direction: direction, showsArrow: true),
                           direction: direction)
    }

    /// `58%`.
    func percent(_ fraction: Double) -> String {
        AmountFormat.percent(fraction, digits: 0, locale: locale)
    }
}

/// A change as text, with its direction for the colour.
struct WidgetDelta: Hashable {
    var text: String
    var direction: Int

    var color: Color { Palette.change(direction) }
}

/// The small label at a widget's top: an icon and a few words.
struct WidgetLabel: View {
    var title: String
    var systemImage: String
    var iconColor: Color = Palette.secondaryInk
    var textColor: Color = Palette.secondaryInk

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .foregroundStyle(iconColor)
            Text(title)
                .foregroundStyle(textColor)
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// What a widget shows when it has nothing to show yet: the app hasn't
/// written a snapshot, or the library has no check-in or no plan answer.
struct WidgetMessage: View {
    var title: String
    var systemImage: String
    var message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetLabel(title: title, systemImage: systemImage)
            Spacer(minLength: 0)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The words for the empty states.
enum WidgetEmpty {
    static let noSnapshot = "Open Can I Retire Yet? to see this here."
    static let noCheckIn = "Your net worth appears here after your first check-in."
    static let noAnswer = "Your main plan's answer appears here after your next check-in, or once you calculate it."
    static let noChange = "The change appears here after your second check-in."
}

extension View {
    /// The widget's background: the card's surface, as content sits on in the app.
    func cardBackground() -> some View {
        containerBackground(for: .widget) {
            Palette.card
        }
    }

    /// No background of its own: for the lock screen.
    func clearBackground() -> some View {
        containerBackground(for: .widget) {
            Color.clear
        }
    }
}

extension RedactionReasons {
    /// Whether the widget is drawn with amounts hidden: on a locked device,
    /// where WidgetKit asks for a private version. Amounts become `•••••`
    /// and changes show in per cent, as with the app's eye button.
    var hidesAmounts: Bool {
        contains(.privacy)
    }
}
