/// The decisions of the iCloud library probe (`ICloudLibraryProbe`, Apple
/// platforms only), without the query and the timers, so they're tested
/// everywhere.
///
/// The probe answers exactly once: `true` as soon as iCloud reports
/// `library.json`; `false` a grace period after the query's first results
/// came without it, when the timeout fires, when the query can't start, or
/// when the caller is cancelled. Every event after the answer is ignored.
struct LibraryProbeState: Hashable, Sendable {
    /// What the probe does next.
    enum Action: Hashable, Sendable {
        /// Keep listening.
        case wait
        /// The first results came without the file: start the grace period.
        case startGrace
        /// Answer, stop the query and the timers. Returned once.
        case finish(Bool)
    }

    /// The answer, once there is one.
    private(set) var answer: Bool?
    private var graceStarted = false

    var isFinished: Bool { answer != nil }

    /// The query reported results: whether they hold `library.json`, and
    /// whether they're its first (gathering finished).
    mutating func received(found: Bool, gathered: Bool) -> Action {
        guard !isFinished else { return .wait }
        if found { return finish(true) }
        if gathered, !graceStarted {
            graceStarted = true
            return .startGrace
        }
        return .wait
    }

    /// The grace period after the first results is over.
    mutating func graceEnded() -> Action { finish(false) }

    /// The overall timeout fired.
    mutating func timedOut() -> Action { finish(false) }

    /// The query couldn't start.
    mutating func failedToStart() -> Action { finish(false) }

    /// The task waiting for the answer was cancelled.
    mutating func cancelled() -> Action { finish(false) }

    private mutating func finish(_ found: Bool) -> Action {
        guard !isFinished else { return .wait }
        answer = found
        return .finish(found)
    }
}
