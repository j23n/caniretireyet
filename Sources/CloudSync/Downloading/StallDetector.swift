/// Tells when something that should be moving hasn't for a while: opening
/// the library shows "Still waiting for iCloud Drive" once nothing has
/// moved for ``threshold``.
///
/// Note progress with ``noteProgress(at:)``; ask ``isStalled(at:)``, or
/// wake up at ``deadline`` to ask.
public struct StallDetector: Hashable, Sendable {
    /// How long without progress counts as stalled.
    public var threshold: Duration
    /// When progress was last noted (or the detector made).
    public private(set) var lastProgress: ContinuousClock.Instant

    public init(threshold: Duration, now: ContinuousClock.Instant = .now) {
        self.threshold = threshold
        lastProgress = now
    }

    /// Something moved: the wait starts again.
    public mutating func noteProgress(at now: ContinuousClock.Instant = .now) {
        lastProgress = now
    }

    /// When it counts as stalled if nothing moves before.
    public var deadline: ContinuousClock.Instant { lastProgress + threshold }

    /// Whether nothing has moved for ``threshold``.
    public func isStalled(at now: ContinuousClock.Instant = .now) -> Bool {
        now >= deadline
    }
}
