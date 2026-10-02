@testable import CloudSync
import Testing

/// The iCloud library probe answers exactly once, whatever happens after.
struct LibraryProbeStateTests {
    @Test func answersYesAsSoonAsTheFileIsReported() {
        var state = LibraryProbeState()
        #expect(state.received(found: true, gathered: true) == .finish(true))
        #expect(state.answer == true)
        #expect(state.timedOut() == .wait)
        #expect(state.graceEnded() == .wait)
        #expect(state.cancelled() == .wait)
        #expect(state.received(found: true, gathered: false) == .wait)
        #expect(state.answer == true)
    }

    @Test func waitsAGracePeriodAfterTheFirstResultsWithoutIt() {
        var state = LibraryProbeState()
        #expect(state.received(found: false, gathered: false) == .wait)
        #expect(state.received(found: false, gathered: true) == .startGrace)
        // The grace period starts once.
        #expect(state.received(found: false, gathered: true) == .wait)
        #expect(state.received(found: false, gathered: false) == .wait)
        // The file turns up during the grace period.
        #expect(state.received(found: true, gathered: false) == .finish(true))
        #expect(state.graceEnded() == .wait)
    }

    @Test func answersNoWhenTheGracePeriodEnds() {
        var state = LibraryProbeState()
        #expect(state.received(found: false, gathered: true) == .startGrace)
        #expect(state.graceEnded() == .finish(false))
        #expect(state.timedOut() == .wait)
        #expect(state.received(found: true, gathered: false) == .wait)
        #expect(state.answer == false)
    }

    @Test func answersNoOnTimeoutFailureOrCancellation() {
        var timedOut = LibraryProbeState()
        #expect(timedOut.timedOut() == .finish(false))
        #expect(timedOut.isFinished)

        var failed = LibraryProbeState()
        #expect(failed.failedToStart() == .finish(false))
        #expect(failed.timedOut() == .wait)

        var cancelled = LibraryProbeState()
        #expect(cancelled.received(found: false, gathered: true) == .startGrace)
        #expect(cancelled.cancelled() == .finish(false))
        #expect(cancelled.received(found: true, gathered: false) == .wait)
        #expect(cancelled.answer == false)
    }
}
