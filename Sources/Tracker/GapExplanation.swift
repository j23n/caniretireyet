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
    /// zero from the baseline's own start, else carried in from before.
    public var start: Decimal
    /// What you saved (new money) less what the baseline planned to save.
    public var saving: Decimal
    /// What markets did less what the baseline expected them to: its
    /// expected change less its planned saving.
    public var markets: Decimal
    /// What inflation took from your money's worth in the baseline's money;
    /// `nil` when the actual values aren't adjusted for inflation (then it's
    /// part of ``other``, and close to nothing).
    public var inflation: Decimal?
    /// The rest: changes of balance accounts without a recorded flow, and
    /// exchange rates.
    public var other: Decimal

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
    ///   - expected: what the baseline expected then (its median).
    ///   - plannedSaving: what it planned you'd save over the stretch.
    ///   - change: how your money changed over the stretch, as it happened
    ///     (not adjusted for inflation), in the baseline's currency: new
    ///     money, market and other (``ValueChange``).
    ///   - isInflationAdjusted: whether `actual` is in money of the
    ///     baseline's start; the difference between its change and
    ///     `change`'s is then what inflation took.
    public init(actual: (start: Decimal, end: Decimal), expected: (start: Decimal, end: Decimal),
                plannedSaving: Decimal, change: ValueChange, isInflationAdjusted: Bool) {
        let actualChange = actual.end - actual.start
        let expectedChange = expected.end - expected.start
        start = actual.start - expected.start
        self.plannedSaving = plannedSaving
        newMoney = change.newMoney
        market = change.market
        expectedMarket = expectedChange - plannedSaving
        saving = change.newMoney - plannedSaving
        markets = change.market - expectedMarket
        let asItHappened = change.newMoney + change.market + change.other
        if isInflationAdjusted {
            inflation = actualChange - asItHappened
            other = change.other
        } else {
            inflation = nil
            other = actualChange - change.newMoney - change.market
        }
    }
}
