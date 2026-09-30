// Validation shared by tax systems: residence options, the regimes work
// phases choose, overlays, pension schemes, parameter overrides, and the
// year-by-year eligibility checks that need the plan's amounts.

extension TaxSystem {
    /// Whether `id` belongs to this system, i.e. starts with `<system id>.`.
    public func owns(_ id: String) -> Bool {
        id.hasPrefix(self.id + ".")
    }

    /// The regime a work phase of `kind` is taxed under in this system: its
    /// own choice when that's one of this system's earned-income regimes for
    /// `kind`, otherwise the default for `kind` (`nil` for kinds the system
    /// doesn't tax, such as `net`).
    public func effectiveRegime(for chosen: String?, kind: EarnedIncomeKind) -> String? {
        if let chosen, let descriptor = regime(chosen), descriptor.scope.applies(to: kind) {
            return chosen
        }
        return defaultRegime(for: kind)
    }

    /// The years in which `plan` makes this system the residence, as closed
    /// ranges; an open-ended last period ends at `Int.max`.
    public func residencePeriods(in plan: TaxPlan) -> [ClosedRange<Int>] {
        let entries = plan.residence.sorted { $0.from < $1.from }
        var periods: [ClosedRange<Int>] = []
        for (index, entry) in entries.enumerated() where entry.system == id {
            let end = index + 1 < entries.count ? entries[index + 1].from - 1 : Int.max
            if end >= entry.from { periods.append(entry.from...end) }
        }
        return periods
    }

    /// The years from `from` to `until` (open-ended when `nil`) in which this
    /// system is the residence, as closed ranges. Empty when `until` is
    /// before `from`.
    public func residenceYears(in plan: TaxPlan, from: Int, until: Int?) -> [ClosedRange<Int>] {
        let last = until ?? Int.max
        guard from <= last else { return [] }
        let span = from...last
        return residencePeriods(in: plan).compactMap { period in
            let lower = max(period.lowerBound, span.lowerBound)
            let upper = min(period.upperBound, span.upperBound)
            return lower <= upper ? lower...upper : nil
        }
    }

    /// The checks every system needs, with codes prefixed by the system's ID:
    ///
    /// - residence options (`<id>.options.*`);
    /// - work phases while resident here: unknown regimes (`unknownRegime`,
    ///   error), regimes of another system (`foreignRegime`, warning: the
    ///   default applies), overlays or regimes for another kind of work
    ///   (`regimeScope`, error), regimes outside their years (`regimeYears`,
    ///   warning) and their options;
    /// - this system's overlays: unknown (`unknownOverlay`), not an overlay
    ///   (`regimeScope`), and their options;
    /// - pensions with an unknown scheme of this system (`unknownPensionScheme`)
    ///   and their options;
    /// - overrides of parameters that don't exist (`unknownOverride`,
    ///   warning). `overridableLeaves` are keys a system reads although the
    ///   file doesn't write them, such as a schedule's `rates`.
    ///
    /// Exclusions between regimes are left to each system, which knows the
    /// years they cover.
    public func commonIssues(for plan: TaxPlan, overridableLeaves: Set<String> = ["rates", "limits"]) -> [TaxIssue] {
        var issues: [TaxIssue] = []
        for entry in plan.residence where entry.system == id {
            issues += entry.options.issues(against: options, codePrefix: "\(id).options", year: entry.from)
        }
        for phase in plan.work {
            let years = residenceYears(in: plan, from: phase.fromYear, until: phase.untilYear)
            guard let first = years.first else { continue }
            issues += workPhaseIssues(phase, years: years, firstYear: first.lowerBound)
        }
        for overlay in plan.overlays where owns(overlay.regime) {
            guard let descriptor = regime(overlay.regime) else {
                issues.append(.error("\(id).unknownOverlay", "Unknown special regime \"\(overlay.regime)\".",
                                     regime: overlay.regime))
                continue
            }
            guard descriptor.scope == .overlay else {
                issues.append(.error("\(id).regimeScope",
                                     "\(descriptor.name) is chosen per work phase, not as a special regime.",
                                     regime: overlay.regime))
                continue
            }
            issues += overlay.options.issues(against: descriptor.options, codePrefix: "\(id).options",
                                             regime: overlay.regime)
        }
        for pension in plan.pensions where owns(pension.scheme) {
            guard let scheme = pensionScheme(pension.scheme) else {
                issues.append(.error("\(id).unknownPensionScheme", "Unknown pension scheme \"\(pension.scheme)\".",
                                     regime: pension.scheme))
                continue
            }
            issues += pension.options.issues(against: scheme.options, codePrefix: "\(id).options", regime: pension.scheme)
        }
        issues += overrideIssues(plan.overrides, overridableLeaves: overridableLeaves)
        return issues
    }

    private func workPhaseIssues(_ phase: TaxPlan.WorkPhase, years: [ClosedRange<Int>], firstYear: Int) -> [TaxIssue] {
        guard let chosen = phase.regime else {
            if defaultRegime(for: phase.kind) == nil && phase.kind != .net {
                return [.error("\(id).noRegime", "\(name) has no regime for \(phase.kind.rawValue) work; choose one.",
                               year: firstYear)]
            }
            return []
        }
        guard owns(chosen) else {
            let fallback = defaultRegime(for: phase.kind).flatMap { regime($0)?.name } ?? "no regime"
            if chosen.contains(".") {
                return [.warning("\(id).foreignRegime",
                                 "\(chosen) doesn't exist in \(name); from \(firstYear) this work is taxed as "
                                     + "\(fallback).",
                                 year: firstYear, regime: chosen)]
            }
            return [.error("\(id).unknownRegime", "Unknown regime \"\(chosen)\".", year: firstYear, regime: chosen)]
        }
        guard let descriptor = regime(chosen) else {
            return [.error("\(id).unknownRegime", "Unknown regime \"\(chosen)\".", year: firstYear, regime: chosen)]
        }
        guard descriptor.scope.applies(to: phase.kind) else {
            let reason = descriptor.scope == .overlay
                ? "\(descriptor.name) is a special regime; add it to the plan's overlays instead."
                : "\(descriptor.name) doesn't apply to \(phase.kind.rawValue) work."
            return [.error("\(id).regimeScope", reason, year: firstYear, regime: chosen)]
        }
        var issues = phase.options.issues(against: descriptor.options, codePrefix: "\(id).options", regime: chosen,
                                          year: firstYear)
        let outside = years.flatMap { range -> [Int] in
            var years: [Int] = []
            if let first = descriptor.firstYear, range.lowerBound < first { years.append(range.lowerBound) }
            if let last = descriptor.lastYear, range.upperBound > last { years.append(last + 1) }
            return years
        }
        if let year = outside.min() {
            issues.append(.warning("\(id).regimeYears", "\(descriptor.name) doesn't apply in \(year).", year: year,
                                   regime: chosen))
        }
        return issues
    }

    private func overrideIssues(_ overrides: OptionValues, overridableLeaves: Set<String>) -> [TaxIssue] {
        guard let latest = parameters.years.last, let set = try? parameters.parameters(for: latest) else { return [] }
        let prefix = id + "."
        return overrides.values.keys.sorted().compactMap { key in
            guard key.hasPrefix(prefix) else { return nil }
            let path = String(key.dropFirst(prefix.count))
            if set.value(at: path) != nil { return nil }
            let components = path.split(separator: ".").map(String.init)
            if let leaf = components.last, overridableLeaves.contains(leaf),
               set.value(at: components.dropLast().joined(separator: ".")) != nil {
                return nil
            }
            return .warning("\(id).unknownOverride", "The override \"\(key)\" doesn't match any tax parameter.",
                            option: key)
        }
    }

    /// Validates `plan`, then prepares `years` in order (threading each
    /// year's state into the next) and adds the issues found on the way,
    /// such as forfettario eligibility, which depends on each year's amounts.
    /// Only years in which this system is the residence are prepared.
    /// Duplicate issues are dropped.
    public func validate(_ plan: TaxPlan, years: [FixedYear], parameters: any ParameterStore) -> [TaxIssue] {
        var issues = validate(plan, parameters: parameters)
        var state = TaxState.empty
        for year in years.sorted(by: { $0.year < $1.year }) where plan.residence(in: year.year)?.system == id {
            guard let set = try? parameters.parameters(for: year.year) else { continue }
            let assessment = prepare(year, state: state, parameters: set).fixedAssessment
            issues += assessment.issues
            state = assessment.nextState
        }
        var seen: Set<TaxIssue> = []
        return issues.filter { seen.insert($0).inserted }
    }
}
