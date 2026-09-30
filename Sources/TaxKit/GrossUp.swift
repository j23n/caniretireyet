/// Solves "how much must I sell to receive `net` after tax?" numerically,
/// for systems whose ``PreparedTaxYear/grossUp(net:from:)`` returns `nil`
/// (e.g. where gains are taxed together with income, so the tax on a sale
/// depends on everything else in the year).
public enum NumericGrossUp {
    /// The gross amount whose net proceeds equal `net`, by bisection, or
    /// `nil` if even `upperBound` doesn't raise it.
    ///
    /// - Parameters:
    ///   - netProceeds: What selling a gross amount leaves after tax. It must
    ///     not fall as the gross amount rises.
    ///   - upperBound: The most that can be sold (e.g. the bucket's value);
    ///     without one, the search doubles its range until it finds enough.
    ///   - tolerance: How close the net proceeds must come to `net`, in euros.
    public static func solve(net: Double, upperBound: Double? = nil, tolerance: Double = 0.005,
                             maxIterations: Int = 200, netProceeds: (Double) -> Double) -> Double? {
        guard net > 0 else { return 0 }
        var low = 0.0
        var high: Double
        if let upperBound {
            guard upperBound > 0, netProceeds(upperBound) >= net - tolerance else { return nil }
            high = upperBound
        } else {
            high = max(net, 1)
            var doublings = 0
            while netProceeds(high) < net {
                low = high
                high *= 2
                doublings += 1
                if doublings > 60 { return nil }
            }
        }
        for _ in 0..<maxIterations {
            let mid = (low + high) / 2
            let proceeds = netProceeds(mid)
            if abs(proceeds - net) <= tolerance { return mid }
            if proceeds < net { low = mid } else { high = mid }
            if high - low <= tolerance * 1e-3 { break }
        }
        return high
    }
}

extension PreparedTaxYear {
    /// Gross-up by assessing: sells from `bucket` pro rata across its tax
    /// categories (at its average cost), on top of the year's other activity
    /// in `baseline`, and searches for the amount whose after-tax proceeds
    /// equal `net`. For engines to use when ``grossUp(net:from:)`` returns
    /// `nil`; `nil` when the bucket can't raise `net`.
    public func numericGrossUp(net: Double, from bucket: BucketSnapshot, alongside baseline: VariableYear = .empty,
                               tolerance: Double = 0.005) -> Double? {
        let baseTax = assess(baseline).totalTax
        let costShare = bucket.value > 0 ? bucket.costBasis / bucket.value : 0
        let total = bucket.categoryShares.values.reduce(0, +)
        let shares = total > 0 ? bucket.categoryShares.sorted { $0.key < $1.key } : [(key: TaxCategory.other, value: 1.0)]
        let scale = total > 0 ? total : 1
        return NumericGrossUp.solve(net: net, upperBound: bucket.value > 0 ? bucket.value : nil, tolerance: tolerance) {
            gross in
            var year = baseline
            for (category, share) in shares where share > 0 {
                let proceeds = gross * share / scale
                year.sales.append(.init(wrapper: bucket.wrapper, category: category, proceeds: proceeds,
                                        costBasis: proceeds * costShare))
            }
            return gross - (assess(year).totalTax - baseTax)
        }
    }
}
