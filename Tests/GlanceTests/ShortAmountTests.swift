import Foundation
import Glance
import Model
import Testing

struct ShortAmountTests {
    let us = Locale(identifier: "en_US")
    let germany = Locale(identifier: "de_DE")
    let dollars = CurrencyCode.usd
    let euros = CurrencyCode.eur

    /// In full below a million, then three significant digits in millions or
    /// billions, the step and decimals chosen from the rounded amount.
    @Test(arguments: [
        ("0", "$0"), ("1234.5", "$1,235"), ("999999", "$999,999"),
        ("999999.6", "$1.00M"), ("2345000", "$2.35M"), ("9996000", "$10.0M"), ("12345678", "$12.3M"),
        ("99960000", "$100M"), ("999499999", "$999M"),
        ("999999600", "$1.00B"), ("9996000000", "$10.0B"), ("12345678901", "$12.3B"), ("999000000000", "$999B"),
        ("999999600000", "$1,000B"), ("1234000000000", "$1,234B"),
    ])
    func shortensByTheRoundedAmount(value: String, text: String) throws {
        let amount = try #require(Decimal(string: value))
        #expect(ShortAmount.text(amount, currency: dollars, locale: us) == text)
    }

    @Test func aNegativeAmountHasTheTypographicMinus() {
        #expect(ShortAmount.text(-300_000, currency: dollars, locale: us) == "\u{2212}$300,000")
        #expect(ShortAmount.text(-12_345_678, currency: dollars, locale: us) == "\u{2212}$12.3M")
        #expect(ShortAmount.text(-2_500_000_000, currency: dollars, locale: us) == "\u{2212}$2.50B")
        #expect(ShortAmount.text(Decimal(string: "-0.4")!, currency: dollars, locale: us) == "$0")
    }

    @Test func followsTheLocalesSeparatorsAndCurrency() {
        let space = "\u{00A0}"
        #expect(ShortAmount.text(300_000, currency: euros, locale: germany) == "300.000\(space)€")
        #expect(ShortAmount.text(12_345_678, currency: euros, locale: germany) == "12,3M\(space)€")
        #expect(ShortAmount.text(-12_345_678, currency: euros, locale: germany) == "\u{2212}12,3M\(space)€")
        #expect(ShortAmount.text(1_234_567_890, currency: euros, locale: germany) == "1,23B\(space)€")
        #expect(ShortAmount.text(1_234_000_000_000, currency: euros, locale: germany) == "1.234B\(space)€")
    }
}
