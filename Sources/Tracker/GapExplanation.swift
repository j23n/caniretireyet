import Foundation
import Model

/// Why you're ahead of or behind a baseline over a stretch of time
/// (PROGRESS.md, "Actual vs. a baseline", *Why*): how the gap between your
/// money and what the baseline expected moved, split into what you saved
/// against what it planned, what markets did against what it expected,
/// what inflation took, and the rest. All in the baseline's money: its
/// currency, and money of its start when the actual values are adjusted
/// for inflation.
///
/// The parts add up to the gap at the end exactly:
/// `start + saving + markets + (inflation ?? 0) + other == end`. The split
/// is an approximation, since the parts affect each other; it answers the
/// useful question: behind because you saved less, or because markets
/// were bad?
public struct GapExplanation: Hashable, Sendable {
    /// The gap at the stretch's start, your money less what was expected:
    /// carried in from before, or at the baseline's own start, your money
    /// then as the library values it now against the value the baseline
    /// started from (they differ when past values changed since).
    public var start: Decimal
    /// What you saved (new money) less what the baseline planned to save.
    public var saving: Decimal
    /// What markets did less what the baseline expected them to: its
    /// expected change less its planned saving.
    public var markets: Decimal
    /// What inflation took from your money's worth in the baseline's money:
    /// its change in money of the baseline's start less its change as it
    /// happened. `nil` when the actual values aren't adjusted for inflation
    /// (then it's part of ``other``, and close to nothing).
    public var inflation: Decimal?
    /// The rest: changes of balance accounts without a recorded flow, and
    /// exchange rates.
    public var other: Decimal

    /// Your money at the stretch's start, and what the baseline expected
    /// then (at its own start, the value it started from): the two the
    /// ``start`` gap is between.
    public var actualStart: Decimal
    public var expectedStart: Decimal

    /// The baseline's planned saving over the stretch.
    public var plannedSaving: Decimal
    /// Your new money over the stretch.
    public var newMoney: Decimal
    /// What markets did to your money over the stretch.
    public var market: Decimal
    /// What markets were expected to do: the expected change less the planned saving.
    public var expectedMarket: Decimal

    /// The gap at the end: your money less what was expected.
    public var end: Decimal {
        start + saving + markets + (inflation ?? 0) + other
    }

    /// - Parameters:
    ///   - actual: your money at the stretch's start and end, in the
    ///     baseline's money.
    ///   - expected: what the baseline expected then (its median; at its
    ///     own start, the value it started from).
    ///   - plannedSaving: what it planned you'd save over the stretch.
    ///   - change: how your money changed over the stretch, as it happened,
    ///     in the baseline's currency: its new money and what markets did
    ///     (``ValueChange``).
    ///   - asItWas: your money at the stretch's start and end in the
    ///     baseline's currency, not adjusted for inflation, when `actual` is
    ///     in money of the baseline's start; `nil` when it isn't.
    public init(actual: (start: Decimal, end: Decimal), expected: (start: Decimal, end: Decimal),
                plannedSaving: Decimal, change: ValueChange, asItWas: (start: Decimal, end: Decimal)?) {
        let expectedChange = expected.end - expected.start
        start = actual.start - expected.start
        actualStart = actual.start
        expectedStart = expected.start
        self.plannedSaving = plannedSaving
        newMoney = change.newMoney
        market = change.market
        expectedMarket = expectedChange - plannedSaving
        saving = change.newMoney - plannedSaving
        markets = change.market - expectedMarket
        inflation = asItWas.map { (actual.end - $0.end) - (actual.start - $0.start) }
        // What's left of the change as it happened.
        let nominal = asItWas ?? actual
        other = nominal.end - nominal.start - change.newMoney - change.market
    }
}
