import Glance
import Model
import SwiftUI

/// An amount of money, formatted for the locale and the base currency
/// (UI.md, "Numbers" and "Privacy").
///
/// - Tabular figures by default, so columns line up; pass `tabular: false`
///   for a large standalone number (the hero figure).
/// - With `signed`, its sign is always shown, without colour: a trade's
///   cash going down isn't bad news (`AmountFormat.signedAmount`).
/// - With `short`, at most 6 digits, for a narrow place like a chart's
///   callout: `300.000 €`, `3.000k €` (Glance's `ShortAmount`). It's a
///   whole number, and takes the place of `precision` and `signed`.
/// - Shows `•••••` while amounts are hidden (`\.hidesAmounts`), and is
///   marked `.privacySensitive()`, so widgets and the app switcher redact it
///   when the device is locked.
/// - With `animatesChanges`, a new value rolls in
///   (`.contentTransition(.numericText())`), unless Reduce Motion is on.
///
///     AmountText(netWorth.total)
///     AmountText(balance, currency: account.currency, precision: .cents)
///     AmountText(trade.amount, currency: account.currency, precision: .cents, signed: true)
///     AmountText(total, tabular: false, animatesChanges: true).font(.largeTitle.bold())
///     AmountText(median, short: true)
struct AmountText: View {
    let amount: Decimal
    /// `nil` for the base currency.
    var currency: CurrencyCode?
    var precision: AmountPrecision = .whole
    var signed = false
    var short = false
    var tabular = true
    var animatesChanges = false

    @Environment(\.baseCurrency) private var baseCurrency
    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ amount: Decimal, currency: CurrencyCode? = nil, precision: AmountPrecision = .whole, signed: Bool = false,
         short: Bool = false, tabular: Bool = true, animatesChanges: Bool = false) {
        self.amount = amount
        self.currency = currency
        self.precision = precision
        self.signed = signed
        self.short = short
        self.tabular = tabular
        self.animatesChanges = animatesChanges
    }

    var body: some View {
        let text = hidesAmounts ? AmountFormat.hidden : formatted
        // Tabular figures (`.monospacedDigit()`) line up in columns; large
        // standalone numbers keep proportional figures.
        let label = Text(verbatim: text)
        (tabular ? label.monospacedDigit() : label)
            .privacySensitive()
            .contentTransition(animatesChanges && !reduceMotion && !hidesAmounts
                ? .numericText(value: amount.doubleValue) : .identity)
            .animation(animatesChanges && !reduceMotion ? .default : nil, value: amount)
            .accessibilityLabel(hidesAmounts ? Text("Amount hidden") : Text(verbatim: text))
    }

    private var formatted: String {
        let code = currency ?? baseCurrency
        if short {
            return ShortAmount.text(amount, currency: code, locale: locale)
        }
        return signed
            ? AmountFormat.signedAmount(amount, currency: code, precision: precision, locale: locale)
            : AmountFormat.amount(amount, currency: code, precision: precision, locale: locale)
    }
}

/// A change with a sign, an arrow and colour, never colour alone (UI.md,
/// "Changes"): `▲ +4.210 €` in the success green, `▼ −240 €` in red. A
/// change that shows as zero has neither arrow nor sign: `0 €`, in grey
/// (``DeltaFormat``).
///
///     DeltaText(change.change)
///     DeltaText(percent: 0.142)            // ▲ +14,2%
struct DeltaText: View {
    enum Value: Hashable {
        case amount(Decimal, CurrencyCode?)
        case percent(Double)
    }

    let value: Value
    var precision: AmountPrecision = .whole
    /// Hides the arrow (the sign stays).
    var showsArrow = true

    @Environment(\.baseCurrency) private var baseCurrency
    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale

    /// A change in money; `currency` defaults to the base currency.
    init(_ amount: Decimal, currency: CurrencyCode? = nil, precision: AmountPrecision = .whole,
         showsArrow: Bool = true) {
        value = .amount(amount, currency)
        self.precision = precision
        self.showsArrow = showsArrow
    }

    /// A change as a fraction: 0.142 is +14,2%. Shown even while amounts are hidden.
    init(percent fraction: Double, showsArrow: Bool = true) {
        value = .percent(fraction)
        self.showsArrow = showsArrow
    }

    /// 1, −1, or 0 for a change that shows as zero (no arrow, no sign).
    private var sign: Int {
        switch value {
        case .amount(let amount, _): DeltaFormat.direction(of: amount, precision: precision)
        case .percent(let fraction): DeltaFormat.direction(ofFraction: fraction)
        }
    }

    private var number: String {
        switch value {
        case .amount(let amount, let currency):
            hidesAmounts
                ? AmountFormat.hidden
                : AmountFormat.signedAmount(amount, currency: currency ?? baseCurrency, precision: precision,
                                            locale: locale)
        case .percent(let fraction):
            AmountFormat.percent(fraction, signed: true, locale: locale)
        }
    }

    var body: some View {
        Text(verbatim: DeltaFormat.text(number, direction: sign, showsArrow: showsArrow))
            .monospacedDigit()
            .foregroundStyle(Palette.change(sign))
            .privacySensitive()
            .accessibilityLabel(Text(verbatim: accessibilityText))
    }

    private var accessibilityText: String {
        let direction = sign > 0 ? "up" : sign < 0 ? "down" : "unchanged"
        return hidesAmounts && !isPercent ? "\(direction), amount hidden" : "\(direction) \(number)"
    }

    private var isPercent: Bool {
        if case .percent = value { true } else { false }
    }
}

#Preview("Amounts") {
    VStack(alignment: .leading, spacing: 8) {
        AmountText(Decimal(string: "312480.55")!, tabular: false).font(.largeTitle.bold())
        AmountText(Decimal(string: "4210.55")!, precision: .cents)
        AmountText(Decimal(string: "-1025.95")!, precision: .cents, signed: true)
        AmountText(Decimal(12_345_678), short: true)
        DeltaText(Decimal(4210))
        DeltaText(Decimal(-240))
        DeltaText(Decimal(string: "-0.001")!, precision: .cents)
        DeltaText(percent: 0.142)
        AmountText(Decimal(312_480)).environment(\.hidesAmounts, true)
    }
    .padding()
}
