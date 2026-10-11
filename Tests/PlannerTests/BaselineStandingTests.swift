import Foundation
import Model
import Planner
import Testing
import TestSupport

/// Whether you're ahead of, on or behind plan (PROGRESS.md, "On track"),
/// against the example's baseline: it starts on 2025-12-31 at 121,834.6,
/// and 2026's year-end p10…p90 are 133,445, 138,468, 142,485, 148,512 and
/// 153,534. The values between were worked out by hand.
struct BaselineStandingTests {
    private func baseline() throws -> Baseline {
        let library = try Fixtures.exampleLibrary()
        return try #require(library.baselines(for: "base").first)
    }

    /// How far `bands` are from `expected` at most; infinite without them.
    private func distance(_ bands: [Double]?, from expected: [Double]) -> Double {
        guard let bands, bands.count == expected.count else { return .infinity }
        return zip(bands, expected).map { abs($0 - $1) }.max() ?? 0
    }

    @Test func theStartAndTheYearEndsAreTheirOwn() throws {
        let baseline = try baseline()
        #expect(distance(baseline.percentiles(on: "2025-12-31"), from: Array(repeating: 121_834.6, count: 5)) < 0.01)
        #expect(distance(baseline.percentiles(on: "2026-12-31"), from: [133_445, 138_468, 142_485, 148_512, 153_534])
            < 0.01)
        #expect(baseline.percentiles(on: "2025-12-30") == nil)
        #expect(baseline.percentiles(on: "2300-01-01") == nil)
    }

    /// A month in, the median is 31/365 of the way to the year-end's, and
    /// each percentile's distance from it √(31/365) of the year-end's: p25
    /// is 4,017 × 0.2914 below it, not 4,017 × 0.0849.
    @Test func theSpreadGrowsWithTheSquareRootOfTime() throws {
        let bands = try baseline().percentiles(on: "2026-01-31")
        #expect(distance(bands, from: [120_953.94, 122_417.79, 123_588.47, 125_344.92, 126_808.48]) < 0.01)
    }

    /// Between two year-ends, the squares of the distances from the median
    /// are interpolated: halfway through 2027 (183 of 365 days), p25's is
    /// √(4,017² × 182/365 + 6,565² × 183/365) = 5,445.61.
    @Test func betweenYearEndsTheSquaresAreInterpolated() throws {
        let bands = try baseline().percentiles(on: "2027-07-02")
        #expect(distance(bands, from: [141_095.56, 147_903.07, 153_348.68, 161_517.95, 168_325.09]) < 0.01)
    }

    /// On 2026-01-31, 125,000 is 1.1% over the median and at the 70th
    /// percentile, on plan; with the band interpolated linearly it would be
    /// over the 90th, ahead.
    @Test func earlyInTheYearTheBandIsWideEnough() throws {
        let bands = try #require(try baseline().percentiles(on: "2026-01-31"))
        let percentile = try #require(BaselineStanding.percentile(of: 125_000, in: bands))
        #expect(abs(percentile - 70.09) < 0.01)
        #expect(BaselineStanding(of: 125_000, in: bands) == .onPlan)
        #expect(BaselineStanding(of: 122_000, in: bands) == .behind)
        #expect(BaselineStanding(of: 127_000, in: bands) == .ahead)
        #expect(BaselineStanding(of: 120_000, in: bands) == .behind)
    }

    /// The percentile is compared as it's said, in whole numbers: "more than
    /// in 25 of its 100 futures" is on plan.
    @Test func comparesThePercentileAsItIsSaid() {
        let bands: [Double] = [10_000, 25_000, 50_000, 75_000, 90_000]
        #expect(BaselineStanding(of: 24_600, in: bands) == .onPlan)
        #expect(BaselineStanding(of: 24_400, in: bands) == .behind)
        #expect(BaselineStanding(of: 75_400, in: bands) == .onPlan)
        #expect(BaselineStanding(of: 75_600, in: bands) == .ahead)
        #expect(BaselineStanding.percentile(of: 9_999, in: bands) == nil)
        #expect(BaselineStanding.percentile(of: 90_001, in: bands) == nil)
    }

    /// A plan without volatility has one future: on it is the 50th
    /// percentile, and within 1% of it is on plan.
    @Test func equalPercentilesAreOnPlan() {
        let bands = Array(repeating: 100_000.0, count: 5)
        #expect(BaselineStanding.percentile(of: 100_000, in: bands) == 50)
        #expect(BaselineStanding(of: 100_000, in: bands) == .onPlan)
        #expect(BaselineStanding(of: 99_100, in: bands) == .onPlan)
        #expect(BaselineStanding(of: 100_900, in: bands) == .onPlan)
        #expect(BaselineStanding(of: 98_900, in: bands) == .behind)
        #expect(BaselineStanding(of: 101_100, in: bands) == .ahead)
        // On p10 and p25 when they're equal: between the 10th and the 25th.
        #expect(BaselineStanding.percentile(of: 100, in: [100, 100, 200, 300, 400]) == 17.5)
    }
}
