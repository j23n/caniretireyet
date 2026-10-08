import Foundation
import Model
@testable import Prices
import Testing
import TestSupport

struct PriceConversionTests {
    @Test func troyOuncesToGramsAndKilograms() throws {
        let perOunce = d("3110.34768")
        #expect(try PriceConversion.price(perOunce, per: .troyOunce, to: .gram) == 100)
        #expect(try PriceConversion.price(perOunce, per: .troyOunce, to: .kilogram) == 100_000)
        #expect(try PriceConversion.price(perOunce, per: .troyOunce, to: .troyOunce) == perOunce)
        #expect(try PriceConversion.price(100, per: .gram, to: .troyOunce) == perOunce)
        #expect(try PriceConversion.price(d("98.4"), per: "share", to: "share") == d("98.4"))
    }

    @Test func unitsThatArentMassesDontConvert() {
        #expect(throws: PriceFetchError.unsupportedUnit(from: .troyOunce, to: .share)) {
            try PriceConversion.price(1, per: .troyOunce, to: .share)
        }
        // "oz" is ambiguous (avoirdupois or troy), so it isn't guessed.
        #expect(throws: PriceFetchError.unsupportedUnit(from: .troyOunce, to: "oz")) {
            try PriceConversion.price(1, per: .troyOunce, to: "oz")
        }
    }

    @Test func currenciesConvertThroughTheBaseCurrency() throws {
        let rates: [CurrencyCode: Decimal] = [.usd: d("1.1398"), .chf: d("0.9312")]
        // USD → EUR: divide by EUR/USD.
        let eur = try PriceConversion.amount(d("3060.580803"), from: .usd, to: .eur, base: .eur) { rates[$0] }
        #expect(eur.rounded(scale: 2) == d("2685.19"))
        // EUR → USD: multiply.
        #expect(try PriceConversion.amount(100, from: .eur, to: .usd, base: .eur, rate: { rates[$0] }) == d("113.98"))
        // USD → CHF: crossed via EUR.
        let chf = try PriceConversion.amount(d("113.98"), from: .usd, to: .chf, base: .eur) { rates[$0] }
        #expect(chf.rounded(scale: 6) == d("93.12"))
        #expect(throws: PriceFetchError.missingFX(from: .gbp, to: .eur, reason: nil)) {
            try PriceConversion.amount(1, from: .gbp, to: .eur, base: .eur) { rates[$0] }
        }
    }

    @Test func goldInUSDPerOunceBecomesEURPerGram() throws {
        // 3,488.45 USD/ozt at 1 EUR = 1.1398 USD.
        let usd: [CurrencyCode: Decimal] = [.usd: d("1.1398")]
        let perGram = try PriceConversion.price(d("3488.45"), per: .troyOunce, to: .gram)
        let eur = try PriceConversion.amount(perGram, from: .usd, to: .eur, base: .eur) { usd[$0] }
        #expect(eur.rounded(significantDigits: 6) == d("98.4"))
        #expect(eur.rounded(scale: 8) == d("98.39995777"))
        // The same from the quote, kept to six significant digits.
        let quote = Quote(price: d("3488.45"), currency: .usd, unit: .troyOunce, observedOn: "2026-09-30")
        let gold = Instrument(id: "gold", name: "Gold", kind: .metal, currency: .eur, unit: .gram,
                              assetClasses: .single(.gold))
        #expect(try PriceConversion.price(of: quote, for: gold, base: .eur, rate: { usd[$0] }) == d("98.4"))
    }

    @Test func roundingToSignificantDigits() {
        #expect(d("98.39995777").rounded(significantDigits: 6) == d("98.4"))
        #expect(d("98399.95777").rounded(significantDigits: 6) == d("98400"))
        #expect(d("1.1643997353").rounded(significantDigits: 6) == d("1.1644"))
        #expect(d("0.000012345678").rounded(significantDigits: 6) == d("0.0000123457"))
        #expect(d("-2685.1934").rounded(significantDigits: 6) == d("-2685.19"))
        #expect(d("123456789").rounded(significantDigits: 6) == d("123457000"))
        #expect(Decimal(0).rounded(significantDigits: 6) == 0)
    }
}
