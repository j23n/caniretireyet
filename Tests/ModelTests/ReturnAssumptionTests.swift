import Foundation
import Model
import Testing
import TestSupport

/// Return assumptions given by their mean (`real`) or their median
/// (`medianReal`, PLANNER.md, "Returns"), and the defaults. All made up.
struct ReturnAssumptionTests {
    // MARK: The file

    @Test func aReturnIsWrittenAsItsMeanOrItsMedian() throws {
        let median = #"{"medianReal":"0","volatility":"0.7"}"#
        let decoded = try decode(ReturnAssumption.self, median)
        #expect(decoded == ReturnAssumption(medianReal: 0, volatility: d("0.7")))
        #expect(decoded.isGivenByMedian && decoded.medianReal == 0 && decoded.realAsWritten == nil)
        // Written with the mean it implies too, for older versions that read only `real`…
        let withMean = #"{"medianReal":"0","real":"0.16629","volatility":"0.7"}"#
        #expect(try json(decoded) == withMean)
        // …which reads back as given by its median.
        let reread = try decode(ReturnAssumption.self, withMean)
        #expect(reread == decoded && reread.isGivenByMedian && !reread.setsMeanAndMedian)
        // A mean that doesn't match (an older version changed it): the mean wins.
        let changed = try decode(ReturnAssumption.self, #"{"medianReal":"0","real":"0.05","volatility":"0.7"}"#)
        #expect(changed.setsMeanAndMedian && !changed.isGivenByMedian && changed.real == d("0.05"))

        let mean = #"{"incomeYield":"0.02","real":"0.045","volatility":"0.17"}"#
        let byMean = try decode(ReturnAssumption.self, mean)
        #expect(!byMean.isGivenByMedian && byMean.medianReal == nil && byMean.realAsWritten == d("0.045"))
        #expect(try json(byMean) == mean)

        // Neither is an error; both are read and written back as they are, and the mean wins.
        #expect(throws: DecodingError.self) { try decode(ReturnAssumption.self, #"{"volatility":"0.1"}"#) }
        let both = #"{"medianReal":"0","real":"0.05","volatility":"0.7"}"#
        let conflicting = try decode(ReturnAssumption.self, both)
        #expect(conflicting.setsMeanAndMedian && !conflicting.isGivenByMedian)
        #expect(conflicting.real == d("0.05"))
        #expect(abs(conflicting.meanReturn - 0.05) < 1e-15)
        #expect(try json(conflicting) == both)
        #expect(ReturnAssumption.knownKeys == ["real", "medianReal", "volatility", "incomeYield"])
    }

    // MARK: Mean and median

    @Test func theMeanFollowsFromTheMedianUnderTheLogNormal() {
        // 0% median at 70%: (1 + A)² / √((1 + A)² + 0.49) = 1.
        let mean = ReturnAssumption.arithmeticMean(median: 0, volatility: 0.7)
        #expect(abs(mean - (((1 + 2.96.squareRoot()) / 2).squareRoot() - 1)) < 1e-12)
        #expect(abs(mean - 0.16629) < 1e-4)
        #expect(abs(ReturnAssumption.median(arithmeticMean: mean, volatility: 0.7)) < 1e-12)
        // The old crypto default: 0% mean at 70% is a median of −18% a year.
        #expect(abs(ReturnAssumption.median(arithmeticMean: 0, volatility: 0.7) - (1 / 1.49.squareRoot() - 1)) < 1e-12)
        // Inverse of each other, and equal without volatility.
        for (value, sigma) in [(0.045, 0.17), (-0.03, 0.4), (0.2, 0.05), (0.01, 0)] {
            #expect(abs(ReturnAssumption.median(
                arithmeticMean: ReturnAssumption.arithmeticMean(median: value, volatility: sigma),
                volatility: sigma) - value) < 1e-12)
        }
        #expect(ReturnAssumption.arithmeticMean(median: 0.03, volatility: 0) == 0.03)
    }

    @Test func settingTheMeanOrTheMedianReplacesTheOther() {
        var assumption = ReturnAssumption(medianReal: 0, volatility: d("0.7"))
        #expect(abs(assumption.meanReturn - 0.16629) < 1e-4)
        #expect(abs(NSDecimalNumber(decimal: assumption.real).doubleValue - assumption.meanReturn) < 1e-12)
        #expect(assumption.impliedMedianReal == 0 && assumption.medianReturn == 0)

        // The median keeps its value as the volatility changes, so the mean follows.
        assumption.volatility = d("0.3")
        #expect(assumption.medianReal == 0 && abs(assumption.meanReturn - 0.0407) < 1e-4)

        assumption.real = d("0.05")
        #expect(assumption.medianReal == nil && assumption.realAsWritten == d("0.05"))
        #expect(abs(assumption.medianReturn - ReturnAssumption.median(arithmeticMean: 0.05, volatility: 0.3)) < 1e-15)

        assumption.medianReal = d("0.01")
        #expect(assumption.isGivenByMedian && assumption.realAsWritten == nil)

        // Removing the median keeps the mean it gave.
        let mean = assumption.real
        assumption.medianReal = nil
        #expect(!assumption.isGivenByMedian && assumption.realAsWritten == mean)
    }

    // MARK: Defaults

    @Test func cryptoDefaultsToAZeroMedian() throws {
        let crypto = try #require(PlanAssumptions.defaultReturns[.crypto])
        #expect(crypto.isGivenByMedian && crypto.medianReal == 0 && crypto.volatility == d("0.7"))
        #expect(abs(crypto.meanReturn - 0.16629) < 1e-4)
    }

    /// The defaults are given by their median, long-run history rounded down
    /// to the half percent (PLANNER.md, "Returns"), with the means they imply.
    @Test func defaultsAreLongRunMedians() throws {
        let expected: [(AssetClass, median: String, volatility: String, mean: Double)] = [
            (.equity, "0.05", "0.17", 0.0633), (.bonds, "0.015", "0.06", 0.0168), (.cash, "0.005", "0.01", 0.0051),
            (.gold, "0.01", "0.15", 0.0208), (.crypto, "0", "0.7", 0.1663),
        ]
        #expect(Set(PlanAssumptions.defaultReturns.keys) == Set(expected.map { $0.0 }))
        for (assetClass, median, volatility, mean) in expected {
            let assumption = try #require(PlanAssumptions.defaultReturns[assetClass])
            #expect(assumption.isGivenByMedian && assumption.medianReal == d(median), "\(assetClass)")
            #expect(assumption.volatility == d(volatility) && assumption.incomeYield == nil, "\(assetClass)")
            #expect(abs(assumption.meanReturn - mean) < 0.0001, "\(assetClass): \(assumption.meanReturn)")
        }
    }

    // MARK: Previous defaults

    @Test func aPlanRepeatingAnEarlierDefaultIsRecognised() throws {
        // The defaults of earlier versions, by their mean; their medians as documented then.
        let medians: [AssetClass: Double] = [.equity: 0.0314, .bonds: 0.0082, .cash: -0.00005, .gold: -0.001,
                                             .crypto: -0.1808]
        for (assetClass, median) in medians {
            let previous = try #require(PlanAssumptions.previousDefaultReturns[assetClass])
            #expect(!previous.isGivenByMedian)
            #expect(abs(previous.medianReturn - median) < 0.0002, "\(assetClass): \(previous.medianReturn)")
            #expect(previous != PlanAssumptions.defaultReturns[assetClass])
        }

        // As an earlier version wrote them, one with an income yield of the plan's own.
        let written = #"{"returns":{"bonds":{"real":"0.010","volatility":"0.06"},"#
            + #""cash":{"real":"0","volatility":"0.02"},"crypto":{"real":"0","volatility":"0.70"},"#
            + #""equity":{"incomeYield":"0.02","real":"0.045","volatility":"0.17"},"#
            + #""gold":{"medianReal":"0.01","volatility":"0.15"}}}"#
        let assumptions = try decode(PlanAssumptions.self, written)
        #expect(assumptions.previousDefaultReturn(for: .equity)
            == ReturnAssumption(real: d("0.045"), volatility: d("0.17")))
        #expect(assumptions.previousDefaultReturn(for: .bonds) != nil)  // 0.010 is 0.01
        #expect(assumptions.previousDefaultReturn(for: .crypto) != nil)
        // Not the same: another volatility, a median instead of a mean, nothing set (the current default).
        #expect(assumptions.previousDefaultReturn(for: .cash) == nil)
        #expect(assumptions.previousDefaultReturn(for: .gold) == nil)
        #expect(PlanAssumptions().previousDefaultReturn(for: .equity) == nil)
        #expect(assumptions.previousDefaultReturn(for: .realEstate) == nil)
    }

    @Test func usingTheDefaultRemovesThePlansEntryButKeepsItsIncomeYield() throws {
        var assumptions = PlanAssumptions(returns: [
            .equity: ReturnAssumption(real: d("0.045"), volatility: d("0.17"), incomeYield: d("0.02")),
            .bonds: ReturnAssumption(real: d("0.01"), volatility: d("0.06")),
            .realEstate: ReturnAssumption(real: d("0.03"), volatility: d("0.1")),
        ])
        assumptions.useDefaultReturn(for: .bonds)
        #expect(assumptions.returns[.bonds] == nil)
        #expect(assumptions.returnAssumption(for: .bonds) == PlanAssumptions.defaultReturns[.bonds])

        // The income yield is the plan's own: kept, with the default's return.
        assumptions.useDefaultReturn(for: .equity)
        var equity = try #require(PlanAssumptions.defaultReturns[.equity])
        equity.incomeYield = d("0.02")
        #expect(assumptions.returns[.equity] == equity && assumptions.previousDefaultReturn(for: .equity) == nil)

        // A class without a default loses its entry.
        assumptions.useDefaultReturn(for: .realEstate)
        #expect(assumptions.returns.keys.sorted() == [.equity])
    }

    @Test func defaultsAreNotWrittenIntoThePlan() throws {
        var assumptions = PlanAssumptions()
        assumptions.setReturnAssumption(PlanAssumptions.defaultReturns[.crypto], for: .crypto)
        #expect(assumptions.returns.isEmpty && assumptions.isEmpty)

        var crypto = try #require(assumptions.returnAssumption(for: .crypto))
        crypto.volatility = d("0.5")
        assumptions.setReturnAssumption(crypto, for: .crypto)
        #expect(try json(assumptions) == #"{"returns":{"crypto":{"medianReal":"0","real":"0.098684","volatility":"0.5"}}}"#)

        // Back to the default: the entry goes.
        crypto.volatility = d("0.70")
        assumptions.setReturnAssumption(crypto, for: .crypto)
        #expect(assumptions.isEmpty)
        assumptions.setReturnAssumption(ReturnAssumption(real: 0, volatility: 0), for: .realEstate)
        #expect(assumptions.returns.keys.sorted() == [.realEstate])
        assumptions.setReturnAssumption(nil, for: .realEstate)
        #expect(assumptions.isEmpty)
    }
}
