import Foundation

/// The threads planner runs compute on.
///
/// A run keeps every core busy for seconds. On Swift's cooperative thread
/// pool, which has one thread per core, that would stall every other async
/// task in the process until the run finished: price fetches, their
/// timeouts, timers, anything the app awaits. So ``Planner/run(plan:library:registry:options:)``
/// prefers this executor (`withTaskExecutorPreference`): the run and all its
/// child tasks execute on these threads, one per core, and the operating
/// system time-slices them with the cooperative pool, which stays free.
///
/// Jobs run in the order they're enqueued. The engine checks for
/// cancellation and yields between chunks of runs (``Engine/pause()``), so
/// concurrent runs, e.g. an outdated one being cancelled while a new one
/// starts, share the threads fairly.
final class PlannerExecutor: TaskExecutor, @unchecked Sendable {
    /// The executor every run uses, with a thread per active core.
    static let shared = PlannerExecutor(threads: ProcessInfo.processInfo.activeProcessorCount)

    /// How many jobs can run at once.
    let threadCount: Int
    private let condition = NSCondition()
    /// Waiting jobs; `queue[head...]` are pending.
    private var queue: [UnownedJob] = []
    private var head = 0

    /// Starts `threads` threads that live as long as the process.
    init(threads: Int) {
        threadCount = max(1, threads)
        for index in 0..<threadCount {
            let thread = Thread { self.work() }
            thread.name = "Planner \(index + 1)"
            thread.qualityOfService = .userInitiated
            thread.start()
        }
    }

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        condition.lock()
        queue.append(job)
        condition.signal()
        condition.unlock()
    }

    private func work() {
        while true {
            condition.lock()
            while head == queue.count { condition.wait() }
            let job = queue[head]
            head += 1
            if head == queue.count {
                queue.removeAll(keepingCapacity: true)
                head = 0
            } else if head >= 1024, head * 2 >= queue.count {
                queue.removeFirst(head)
                head = 0
            }
            condition.unlock()
            job.runSynchronously(on: asUnownedTaskExecutor())
        }
    }
}
