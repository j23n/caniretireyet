import Foundation
import Testing
@testable import CanIRetireYet

/// A chart's value axis while amounts are hidden (UI.md, "Privacy"):
/// multiples of a base (`relativeTicks(base:)`), the labels `amountAxis`
/// shows, and which of them stay readable in the redaction.
struct AmountAxisTicksTests {
    private let locale = Locale(identifier: "en_US")

    /// Ticks at 0, 100.000, 200.000 and 300.000.
    private let scale = AmountScale(values: [0, 300_000])

    @Test func theScaleHasTicksEvery100000() {
        #expect(scale.ticks == [0, 100_000, 200_000, 300_000])
    }

    @Test func relativeTicksAreMultiplesOfTheBase() {
        let ticks = scale.relativeTicks(base: 100_000, locale: locale)
        #expect(ticks.map(\.label) == ["0", "1×", "2×", "3×"])
        #expect(ticks.map(\.value) == [0, 100_000, 200_000, 300_000])
    }

    @Test func relativeTicksStepInHalvesWhenTheBaseIsLarge() {
        let ticks = scale.relativeTicks(base: 200_000, locale: locale)
        #expect(ticks.map(\.label) == ["0", "0.5×", "1×", "1.5×"])
        #expect(ticks.map(\.value) == [0, 100_000, 200_000, 300_000])
    }

    @Test(arguments: [0.0, -5_000, Double.infinity])
    func noRelativeTicksWithoutAPositiveBase(base: Double) {
        #expect(scale.relativeTicks(base: base, locale: locale).isEmpty)
    }

    @Test func amountsShowAsAmounts() {
        let axis = AmountAxisTicks(scale: scale, hidesAmounts: false, relativeTo: 100_000, locale: locale)
        #expect(!axis.isRelative)
        #expect(axis.values == scale.ticks)
        #expect(axis.ticks.map(\.label) == scale.ticks.map { scale.label($0, locale: locale) })
    }

    /// While amounts are hidden the labels are multiples of the base: the
    /// one chart label left unredacted.
    @Test func hiddenAmountsShowMultiplesOfTheBase() {
        let axis = AmountAxisTicks(scale: scale, hidesAmounts: true, relativeTo: 100_000, locale: locale)
        #expect(axis.isRelative)
        #expect(axis.ticks.map(\.label) == ["0", "1×", "2×", "3×"])
        #expect(axis.label(for: 200_000) == "2×")
        #expect(axis.label(for: 150_000) == "")
    }

    /// Without a base nothing is relative: the amounts stay, and draw as
    /// placeholders.
    @Test(arguments: [nil, 0.0] as [Double?])
    func hiddenAmountsWithoutABaseKeepTheAmounts(base: Double?) {
        let axis = AmountAxisTicks(scale: scale, hidesAmounts: true, relativeTo: base, locale: locale)
        #expect(!axis.isRelative)
        #expect(axis.values == scale.ticks)
        #expect(axis.label(for: 100_000) == scale.label(100_000, locale: locale))
    }
}
