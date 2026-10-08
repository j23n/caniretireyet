/// Lets at most a number of fetches run at once; the others wait their
/// turn, first come, first served. A ``PriceService`` shares one between
/// all its fetches (and its copies), so prices fetched for many instruments
/// at once, in one check-in, one call per instrument or while past prices
/// are filled in, don't hit a free API's rate limit.
actor FetchLimit {
    /// The most fetches that run at once.
    let limit: Int
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(_ limit: Int) {
        self.limit = max(1, limit)
    }

    /// Runs `operation` once fewer than ``limit`` others are running.
    nonisolated func run<T: Sendable>(_ operation: @Sendable () async throws -> T) async rethrows -> T {
        await acquire()
        do {
            let value = try await operation()
            await release()
            return value
        } catch {
            await release()
            throw error
        }
    }

    private func acquire() async {
        guard running >= limit else {
            running += 1
            return
        }
        // The slot is handed over by `release`, so `running` stays as it is.
        await withCheckedContinuation { waiting.append($0) }
    }

    private func release() {
        if waiting.isEmpty {
            running -= 1
        } else {
            waiting.removeFirst().resume()
        }
    }
}
