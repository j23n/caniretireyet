/// The keys of the tax state the Swiss system carries from one year to the
/// next. Everything in it depends only on the plan (never on the markets),
/// so the state from `fixedAssessment` and from `assess` is the same.
enum SwissStateKey {
    private static let buyInPrefix = "ch.bvg.buyIn."

    /// BVG buy-ins paid in `year`, in CHF, kept for the years a lump sum
    /// would reverse their deduction (`ch.bvg.buyIn.2030`).
    static func buyIn(_ year: Int) -> String {
        buyInPrefix + String(year)
    }

    static func isBuyIn(_ key: String) -> Bool {
        key.hasPrefix(buyInPrefix)
    }

    /// The year of a buy-in key.
    static func buyInYear(_ key: String) -> Int? {
        guard isBuyIn(key) else { return nil }
        return Int(key.dropFirst(buyInPrefix.count))
    }
}
