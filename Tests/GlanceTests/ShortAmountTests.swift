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

    @Test func showsAMillionAndMoreInThousands() {
        #expect(ShortAmount.text(1_000_000, currency: dollars, locale: us) == "$1,000k")
        #expect(ShortAmount.text(3_000_000, currency: dollars, locale: us) == "$3,000k")
        #expect(ShortAmount.text(12_345_678, currency: dollars, locale: us) == "$12,346k")
        #expect(ShortAmount.text(999_999_499, currency: dollars, locale: us) == "$999,999k")
    }

    @Test func showsABillionAndMoreInMillions() {
        #expect(ShortAmount.text(1_000_000_000, currency: dollars, locale: us) == "$1,000M")
        #expect(ShortAmount.text(1_234_567_890, currency: dollars, locale: us) == "$1,235M")
    }

    @Test func choosesTheStepFromTheRoundedAmount() {
        // Both would read with 7 digits in the smaller step.
        #expect(ShortAmount.text(Decimal(string: "999999.6")!, currency: dollars, locale: us) == "$1,000k")
        #expect(ShortAmount.text(999_999_500, currency: dollars, locale: us) == "$1,000M")
    }

    @Test func neverShowsMoreThanSixDigits() {
        for value: Decimal in [999_999, 1_000_000, 9_999_999, 123_456_789, 999_999_999, 12_345_678_901] {
            let digits = ShortAmount.text(value, currency: dollars, locale: us).filter(\.isNumber).count
            #expect(digits <= ShortAmount.maxDigits, "\(value)")
        }
    }

    @Test func aNegativeAmountHasTheTypographicMinus() {
        #expect(ShortAmount.text(-300_000, currency: dollars, locale: us) == "\u{2212}$300,000")
        #expect(ShortAmount.text(-3_000_000, currency: dollars, locale: us) == "\u{2212}$3,000k")
        #expect(ShortAmount.text(-2_500_000_000, currency: dollars, locale: us) == "\u{2212}$2,500M")
        #expect(ShortAmount.text(Decimal(string: "-0.4")!, currency: dollars, locale: us) == "$0")
    }

    @Test func followsTheLocalesGroupingAndCurrency() {
        let space = "\u{00A0}"
        #expect(ShortAmount.text(300_000, currency: euros, locale: germany) == "300.000\(space)€")
        #expect(ShortAmount.text(3_000_000, currency: euros, locale: germany) == "3.000k\(space)€")
        #expect(ShortAmount.text(-12_345_678, currency: euros, locale: germany) == "\u{2212}12.346k\(space)€")
        #expect(ShortAmount.text(1_234_567_890, currency: euros, locale: germany) == "1.235M\(space)€")
    }

    @Test func scalesWithItsSuffix() {
        let full = ShortAmount.scaled(300_000)
        #expect(full.value == 300_000 && full.suffix == "")
        let thousands = ShortAmount.scaled(-3_000_000)
        #expect(thousands.value == -3_000 && thousands.suffix == "k")
        let millions = ShortAmount.scaled(1_234_567_890)
        #expect(millions.value == 1_235 && millions.suffix == "M")
    }
}
