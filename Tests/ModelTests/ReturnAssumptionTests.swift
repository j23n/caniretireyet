import Foundation
import Model
import Testing

/// Return assumptions given by their mean (`real`) or their median
/// (`medianReal`, PLANNER.md, "Returns"), and the defaults. All made up.
struct ReturnAssumptionTests {
    private static func d(_ string: String) -> Decimal { Decimal(fileString: string)! }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    // MARK: The file

    @Test func aReturnIsWrittenAsItsMeanOrItsMedian() throws {
        let median = #"{"medianReal":"0","volatility":"0.7"}"#
        let decoded = try decode(ReturnAssumption.self, median)
        #expect(decoded == ReturnAssumption(medianReal: 0, volatility: Self.d("0.7")))
        #expect(decoded.isGivenByMedian && decoded.medianReal == 0 && decoded.realAsWritten == nil)
        // Written with the mean it implies too, for older versions that read only `real`…
        let withMean = #"{"medianReal":"0","real":"0.16629","volatility":"0.7"}"#
        #expect(try json(decoded) == withMean)
        // …which reads back as given by its median.
        let reread = try decode(ReturnAssumption.self, withMean)
        #expect(reread == decoded && reread.isGivenByMedian && !reread.setsMeanAndMedian)
        // A mean that doesn't match (an older version changed it): the mean wins.
        let changed = try decode(ReturnAssumption.self, #"{"medianReal":"0","real":"0.05","volatility":"0.7"}"#)
        #expect(changed.setsMeanAndMedian && !changed.isGivenByMedian && changed.real == Self.d("0.05"))

        let mean = #"{"incomeYield":"0.02","real":"0.045","volatility":"0.17"}"#
        let byMean = try decode(ReturnAssumption.self, mean)
        #expect(!byMean.isGivenByMedian && byMean.medianReal == nil && byMean.realAsWritten == Self.d("0.045"))
        #expect(try json(byMean) == mean)

        // Neither is an error; both are read and written back as they are, and the mean wins.
        #expect(throws: DecodingError.self) { try decode(ReturnAssumption.self, #"{"volatility":"0.1"}"#) }
        let both = #"{"medianReal":"0","real":"0.05","volatility":"0.7"}"#
        let conflicting = try decode(ReturnAssumption.self, both)
        #expect(conflicting.setsMeanAndMedian && !conflicting.isGivenByMedian)
        #expect(conflicting.real == Self.d("0.05"))
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
        var assumption = ReturnAssumption(medianReal: 0, volatility: Self.d("0.7"))
        #expect(abs(assumption.meanReturn - 0.16629) < 1e-4)
        #expect(abs(NSDecimalNumber(decimal: assumption.real).doubleValue - assumption.meanReturn) < 1e-12)
        #expect(assumption.impliedMedianReal == 0 && assumption.medianReturn == 0)

        // The median keeps its value as the volatility changes, so the mean follows.
        assumption.volatility = Self.d("0.3")
        #expect(assumption.medianReal == 0 && abs(assumption.meanReturn - 0.0407) < 1e-4)

        assumption.real = Self.d("0.05")
        #expect(assumption.medianReal == nil && assumption.realAsWritten == Self.d("0.05"))
        #expect(abs(assumption.medianReturn - ReturnAssumption.median(arithmeticMean: 0.05, volatility: 0.3)) < 1e-15)

        assumption.medianReal = Self.d("0.01")
        #expect(assumption.isGivenByMedian && assumption.realAsWritten == nil)

        // Removing the median keeps the mean it gave.
        let mean = assumption.real
        assumption.medianReal = nil
        #expect(!assumption.isGivenByMedian && assumption.realAsWritten == mean)
    }

    // MARK: Defaults

    @Test func cryptoDefaultsToAZeroMedian() throws {
        let crypto = try #require(PlanAssumptions.defaultReturns[.crypto])
        #expect(crypto.isGivenByMedian && crypto.medianReal == 0 && crypto.volatility == Self.d("0.7"))
        #expect(abs(crypto.meanReturn - 0.16629) < 1e-4)
        // The others are given by their mean; their medians, as documented.
        let medians: [AssetClass: Double] = [.equity: 0.0314, .bonds: 0.0082, .cash: -0.00005, .gold: -0.001]
        for (assetClass, median) in medians {
            let assumption = try #require(PlanAssumptions.defaultReturns[assetClass])
            #expect(!assumption.isGivenByMedian)
            #expect(abs(assumption.medianReturn - median) < 0.0002, "\(assetClass): \(assumption.medianReturn)")
        }
    }

    @Test func defaultsAreNotWrittenIntoThePlan() throws {
        var assumptions = PlanAssumptions()
        assumptions.setReturnAssumption(PlanAssumptions.defaultReturns[.crypto], for: .crypto)
        #expect(assumptions.returns.isEmpty && assumptions.isEmpty)

        var crypto = try #require(assumptions.returnAssumption(for: .crypto))
        crypto.volatility = Self.d("0.5")
        assumptions.setReturnAssumption(crypto, for: .crypto)
        #expect(try json(assumptions) == #"{"returns":{"crypto":{"medianReal":"0","real":"0.098684","volatility":"0.5"}}}"#)

        // Back to the default: the entry goes.
        crypto.volatility = Self.d("0.70")
        assumptions.setReturnAssumption(crypto, for: .crypto)
        #expect(assumptions.isEmpty)
        assumptions.setReturnAssumption(ReturnAssumption(real: 0, volatility: 0), for: .realEstate)
        #expect(assumptions.returns.keys.sorted() == [.realEstate])
        assumptions.setReturnAssumption(nil, for: .realEstate)
        #expect(assumptions.isEmpty)
    }
}
