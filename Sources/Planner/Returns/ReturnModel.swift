import Foundation
import Model

/// The return assumptions as the simulation uses them: for each asset class
/// the portfolio holds, the log-normal parameters of the yearly real return,
/// plus the Cholesky factor of the correlation matrix.
///
/// Draws are generated for a fixed, canonical list of asset classes (every
/// known class, then any others the plan mentions), so a class always gets
/// the same draws whatever else the portfolio holds.
struct ReturnModel: Sendable {
    /// The classes draws are generated for, in canonical order.
    let drawClasses: [AssetClass]
    /// The classes the portfolio holds, in the order lots refer to them.
    let classes: [AssetClass]
    /// For each held class, its index in `drawClasses`.
    let drawIndex: [Int]
    /// Expected (arithmetic) yearly real return per held class.
    let expected: [Double]
    /// Yearly volatility per held class.
    let volatility: [Double]
    /// Mean and standard deviation of the log return per held class.
    let logMean: [Double]
    let logSD: [Double]
    /// Lower-triangular Cholesky factor over `drawClasses`.
    let cholesky: [[Double]]

    /// Builds the model from the plan's assumptions. `issues` receives
    /// warnings for classes without an assumption and for a correlation
    /// matrix that had to be repaired.
    init(assumptions: PlanAssumptions, heldClasses: [AssetClass], issues: inout [PlanIssue]) {
        var extra = Set(heldClasses)
        extra.formUnion(assumptions.returns.keys)
        if let table = assumptions.correlations {
            for (a, row) in table.values {
                extra.insert(a)
                extra.formUnion(row.keys)
            }
        }
        extra.subtract(AssetClass.knownValues)
        let drawClasses = AssetClass.knownValues + extra.sorted()
        self.drawClasses = drawClasses
        classes = heldClasses
        drawIndex = heldClasses.map { held in drawClasses.firstIndex(of: held)! }

        // A file that writes both the mean and the median gets the mean.
        for (assetClass, assumption) in assumptions.returns.sorted(by: { $0.key < $1.key })
            where assumption.setsMeanAndMedian {
            issues.append(.warning(
                "planner.meanAndMedian",
                "\(Self.name(assetClass))'s return assumption sets both real (the mean, "
                    + "\(Self.percent(assumption.realAsWritten?.doubleValue ?? 0))) and medianReal; the plan uses real "
                    + "and ignores medianReal.",
                section: .assumptions, option: assetClass.rawValue))
        }

        var expected: [Double] = []
        var volatility: [Double] = []
        for assetClass in heldClasses {
            if let assumption = assumptions.returnAssumption(for: assetClass) {
                let sd = max(0, assumption.volatility.doubleValue)
                expected.append(assumption.meanReturn)
                volatility.append(sd)
            } else {
                issues.append(.warning(
                    "planner.noReturnAssumption",
                    "There is no return assumption for \(assetClass.rawValue); the plan assumes 0% real with no volatility.",
                    section: .assumptions))
                expected.append(0)
                volatility.append(0)
            }
        }
        self.expected = expected
        self.volatility = volatility
        let logSD = zip(expected, volatility).map { mean, sd in
            (log(1 + sd * sd / ((1 + mean) * (1 + mean)))).squareRoot()
        }
        self.logSD = logSD
        logMean = zip(expected, logSD).map { mean, s in log(1 + mean) - s * s / 2 }

        // A class whose typical year loses value drags a rebalanced portfolio down.
        for (index, assetClass) in heldClasses.enumerated() where expected[index] > -1 {
            let median = exp(logMean[index]) - 1
            guard median < Self.lowMedian - 1e-12 else { continue }
            issues.append(.warning(
                "planner.lowMedianReturn",
                "\(Self.name(assetClass))'s assumptions give a median of \(Self.percent(median)) a year: holding and "
                    + "rebalancing into it shrinks the portfolio. Check the assumption.",
                section: .assumptions, option: assetClass.rawValue))
        }

        var matrix = drawClasses.map { a in
            drawClasses.map { b in min(1, max(-1, assumptions.correlation(a, b).doubleValue)) }
        }
        if let factor = Self.choleskyFactor(matrix) {
            cholesky = factor
        } else {
            issues.append(.warning(
                "planner.correlationsRepaired",
                "The correlations between asset classes aren't consistent; the plan uses slightly weaker ones.",
                section: .assumptions))
            var repaired: [[Double]]?
            for _ in 0..<200 where repaired == nil {
                for i in matrix.indices {
                    for j in matrix.indices where i != j { matrix[i][j] *= 0.95 }
                }
                repaired = Self.choleskyFactor(matrix)
            }
            cholesky = repaired ?? drawClasses.indices.map { i in drawClasses.indices.map { $0 == i ? 1 : 0 } }
        }
    }

    /// The median yearly real return below which a held class gets a
    /// warning (`planner.lowMedianReturn`): −2%.
    static let lowMedian = -0.02

    /// "Crypto", "Real estate": an asset class in words, for messages.
    static func name(_ assetClass: AssetClass) -> String {
        switch assetClass {
        case .realEstate: return "Real estate"
        default:
            let raw = assetClass.rawValue
            return raw.prefix(1).uppercased() + raw.dropFirst()
        }
    }

    /// "−18%", "−2.5%", "4.5%": a yearly rate for messages, whole from 10%.
    static func percent(_ value: Double) -> String {
        let percent = value * 100
        let text = abs(percent) >= 9.95 ? String(format: "%.0f", abs(percent)) : String(format: "%.1f", abs(percent))
        let trimmed = text.hasSuffix(".0") ? String(text.dropLast(2)) : text
        return (percent < 0 && trimmed != "0" ? "−" : "") + trimmed + "%"
    }

    /// The Cholesky factor of a symmetric matrix, or `nil` if it isn't
    /// positive definite.
    static func choleskyFactor(_ a: [[Double]]) -> [[Double]]? {
        let n = a.count
        var l = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
        for i in 0..<n {
            for j in 0...i {
                var sum = a[i][j]
                for k in 0..<j { sum -= l[i][k] * l[j][k] }
                if i == j {
                    guard sum > 1e-12 else { return nil }
                    l[i][i] = sum.squareRoot()
                } else {
                    l[i][j] = sum / l[j][j]
                }
            }
        }
        return l
    }

    /// The gross real return factor over `fraction` of a year for held class
    /// `index`, given a correlated standard normal draw.
    @inline(__always)
    func factor(index: Int, draw: Double, fraction: Double) -> Double {
        exp(logMean[index] * fraction + logSD[index] * fraction.squareRoot() * draw)
    }

    /// The deterministic factor: the median return (the typical year, a
    /// draw of zero), compounded over `fraction` of a year. Not the mean:
    /// compounding a volatile class's average year every year runs far
    /// ahead of what any typical future does (crypto at a 0% median and 70%
    /// volatility averages +16.6% a year). With no volatility the median is
    /// the mean, and this is computed exactly as such a draw is, so Monte
    /// Carlo with zero volatility reproduces the deterministic run bit for
    /// bit.
    func expectedFactor(index: Int, fraction: Double) -> Double {
        exp(logMean[index] * fraction)
    }
}

/// The random futures shared by every retirement age and every what-if
/// (common random numbers): yearly return factors per run, year and held
/// class, and which uncertain events happen in each run.
///
/// Run `r` always draws from its own seeded streams, so the first 200 runs
/// of a fast run are the first 200 runs of the full one.
struct MarketScenarios: Sendable {
    let runs: Int
    let years: Int
    let classes: Int
    /// Gross real return factors, indexed `(run * years + year) * classes + class`.
    let factors: [Double]
    /// The deterministic run's factors, indexed `year * classes + class`.
    let expectedFactors: [Double]
    /// Per run, a bit per uncertain event, set when it happens.
    let eventMasks: [UInt64]
    /// The deterministic run's events: those with a probability of at least 50%.
    let expectedEvents: UInt64

    init(model: ReturnModel, fractions: [Double], runs: Int, seed: UInt64, eventProbabilities: [Double]) {
        self.runs = runs
        years = fractions.count
        classes = model.classes.count
        let drawCount = model.drawClasses.count
        let rows = model.drawIndex.map { Array(model.cholesky[$0].prefix($0 + 1)) }

        var factors = [Double](repeating: 1, count: runs * years * classes)
        var z = [Double](repeating: 0, count: drawCount)
        for run in 0..<runs {
            var sampler = NormalSampler(Xoshiro256StarStar(seed: seed, stream: RandomStream.markets, index: run))
            for year in 0..<years {
                for k in 0..<drawCount { z[k] = sampler.next() }
                let base = (run * years + year) * classes
                for c in 0..<classes {
                    var x = 0.0
                    for (k, weight) in rows[c].enumerated() { x += weight * z[k] }
                    factors[base + c] = model.factor(index: c, draw: x, fraction: fractions[year])
                }
            }
        }
        self.factors = factors

        var expectedFactors = [Double](repeating: 1, count: years * classes)
        for year in 0..<years {
            for c in 0..<classes {
                expectedFactors[year * classes + c] = model.expectedFactor(index: c, fraction: fractions[year])
            }
        }
        self.expectedFactors = expectedFactors

        var masks = [UInt64](repeating: 0, count: runs)
        if !eventProbabilities.isEmpty {
            for run in 0..<runs {
                var generator = Xoshiro256StarStar(seed: seed, stream: RandomStream.events, index: run)
                var mask: UInt64 = 0
                for (bit, probability) in eventProbabilities.enumerated() where generator.nextUnit() < probability {
                    mask |= 1 << UInt64(bit)
                }
                masks[run] = mask
            }
        }
        eventMasks = masks
        var expectedEvents: UInt64 = 0
        for (bit, probability) in eventProbabilities.enumerated() where probability >= 0.5 {
            expectedEvents |= 1 << UInt64(bit)
        }
        self.expectedEvents = expectedEvents
    }

    /// Scenarios with the return factors given rather than drawn: `factors`
    /// indexed `(run * years + year) * classes + class`, the deterministic
    /// run's `year * classes + class`, and no uncertain events. For tests
    /// that need a market path chosen by hand, such as a crash in one year.
    init(factors: [Double], expectedFactors: [Double], runs: Int, years: Int, classes: Int) {
        precondition(factors.count == runs * years * classes && expectedFactors.count == years * classes)
        self.runs = runs
        self.years = years
        self.classes = classes
        self.factors = factors
        self.expectedFactors = expectedFactors
        eventMasks = Array(repeating: 0, count: runs)
        expectedEvents = 0
    }
}
