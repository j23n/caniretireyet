import Model

/// Work phases don't overlap (PLANNER.md, "Work, pensions and other
/// income"): at most one is in force on any day. The planner reports an
/// overlap as an error, and adding a phase ends its neighbors where it starts.
extension PlanDocument {
    /// The overlapping work phases, as pairs of indices: the one that starts
    /// first (of two starting the same day, the one listed first), then the
    /// other. A phase that ends before it starts overlaps nothing.
    public var overlappingWork: [(earlier: Int, later: Int)] {
        let phases = work.indices.filter { index in work[index].until.date.map { $0 >= work[index].from } ?? true }
            .sorted { (work[$0].from, $0) < (work[$1].from, $1) }
        var pairs: [(earlier: Int, later: Int)] = []
        for (position, earlier) in phases.enumerated() {
            for later in phases[(position + 1)...] where work[earlier].runs(on: work[later].from) {
                pairs.append((earlier: earlier, later: later))
            }
        }
        return pairs
    }

    /// `work` with `phase` added after the others, and without overlaps it
    /// would cause: a phase still running on its first day ends the day
    /// before, and it ends the day before the next phase starts. A phase
    /// starting the same day can't end before it, and one that runs past the
    /// new phase's end would lose its later years, so those two are left as
    /// they are and still overlap it.
    public func work(adding phase: WorkPhase) -> [WorkPhase] {
        var phase = phase
        if let next = work.map(\.from).filter({ $0 > phase.from }).min(), phase.runs(on: next) {
            phase.until = .date(next.adding(days: -1))
        }
        let dayBefore = phase.from.adding(days: -1)
        let dayAfter = phase.until.date?.adding(days: 1)
        return work.map { earlier in
            guard earlier.from <= dayBefore, earlier.runs(on: phase.from),
                  !(dayAfter.map(earlier.runs(on:)) ?? false) else { return earlier }
            var earlier = earlier
            earlier.until = .date(dayBefore)
            return earlier
        } + [phase]
    }
}

extension WorkPhase {
    /// Whether the phase has started by `day` and not ended before it; one
    /// until retirement runs on.
    func runs(on day: CalendarDate) -> Bool {
        from <= day && (until.date.map { $0 >= day } ?? true)
    }
}
