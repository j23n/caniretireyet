import Foundation
import Glance
import Model
import Testing

struct ShortAmountTests {
    let us = Locale(identifier: "en_US")
    let germany = Locale(identifier: "de_DE")
    let dollars = CurrencyCode.usd
    let euros = CurrencyCode.eur

    @Test func showsAnAmountBelowAMillionInFull() {
        #expect(ShortAmount.text(300_000, currency: dollars, locale: us) == "$300,000")
        #expect(ShortAmount.text(999_999, currency: dollars, locale: us) == "$999,999")
        #expect(ShortAmount.text(Decimal(string: "1234.5")!, currency: dollars, locale: us) == "$1,235")
        #expect(ShortAmount.text(0, currency: dollars, locale: us) == "$0")
    }

    @Test func showsAMillionAndMoreInMillions() {
        #expect(ShortAmount.text(1_000_000, currency: dollars, locale: us) == "$1.00M")
        #expect(ShortAmount.text(2_345_000, currency: dollars, locale: us) == "$2.35M")
        #expect(ShortAmount.text(12_345_678, currency: dollars, locale: us) == "$12.3M")
        #expect(ShortAmount.text(123_456_789, currency: dollars, locale: us) == "$123M")
        #expect(ShortAmount.text(999_499_999, currency: dollars, locale: us) == "$999M")
    }

    @Test func showsABillionAndMoreInBillions() {
        #expect(ShortAmount.text(1_000_000_000, currency: dollars, locale: us) == "$1.00B")
        #expect(ShortAmount.text(12_345_678_901, currency: dollars, locale: us) == "$12.3B")
        #expect(ShortAmount.text(999_000_000_000, currency: dollars, locale: us) == "$999B")
    }

    @Test func keepsBillionsPastAThousandOfThem() {
        #expect(ShortAmount.text(1_234_000_000_000, currency: dollars, locale: us) == "$1,234B")
        #expect(ShortAmount.text(Decimal(string: "999999600000")!, currency: dollars, locale: us) == "$1,000B")
    }

    @Test func choosesTheStepFromTheRoundedAmount() {
        // Each would read with one digit too many in the smaller step.
        #expect(ShortAmount.text(Decimal(string: "999999.6")!, currency: dollars, locale: us) == "$1.00M")
        #expect(ShortAmount.text(999_999_600, currency: dollars, locale: us) == "$1.00B")
    }

    @Test func choosesTheDecimalsFromTheRoundedAmount() {
        #expect(ShortAmount.text(9_996_000, currency: dollars, locale: us) == "$10.0M")
        #expect(ShortAmount.text(99_960_000, currency: dollars, locale: us) == "$100M")
        #expect(ShortAmount.text(9_996_000_000, currency: dollars, locale: us) == "$10.0B")
    }

    @Test func showsThreeSignificantDigitsFromAMillion() {
        let values: [Decimal] = [
            1_000_000, 9_999_999, 54_321_000, 123_456_789, 999_999_999, 12_345_678_901, 987_654_321_098,
        ]
        for value in values {
            let digits = ShortAmount.text(value, currency: dollars, locale: us).filter(\.isNumber).count
            #expect(digits == 3, "\(value)")
        }
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

    @Test func scalesWithItsDecimalsAndSuffix() {
        let full = ShortAmount.scaled(300_000)
        #expect(full.value == 300_000 && full.fractionDigits == 0 && full.suffix == "")
        let millions = ShortAmount.scaled(-12_345_678)
        #expect(millions.value == Decimal(string: "-12.3")! && millions.fractionDigits == 1 && millions.suffix == "M")
        let billions = ShortAmount.scaled(999_999_600)
        #expect(billions.value == 1 && billions.fractionDigits == 2 && billions.suffix == "B")
    }
}
