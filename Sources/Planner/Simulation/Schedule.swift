import Foundation
import Model
import TaxKit

/// Everything about one retirement age that doesn't depend on the markets,
/// computed once and shared by every run: each year's prepared tax year
/// (per combination of uncertain windfalls that occurs), cash flows, pension
/// claims, and whether each bucket can be drawn from.
struct AgeSchedule: Sendable {
    let retirementAge: Int
    let retirementDate: CalendarDate
    var years: [ScheduledYear]
    /// Each pension's claim, by pension index; `nil` if it's never claimed.
    let claims: [PensionClaim?]
    /// What the tax systems were asked to prepare in the deterministic run,
    /// per year: the input to their year-by-year validation.
    let fixedYears: [FixedYear]
    /// The engine's own warnings about this age, e.g. a pension claimed later
    /// than asked. The tax systems' come from ``PlanModel/yearIssues(for:)``.
    let issues: [PlanIssue]
    /// Whether each bucket can be drawn from, per year: `year * buckets + bucket`.
    var access: [WrapperAccess] = []
    /// `access` as plain flags, for the simulation's inner loop.
    var accessible: [Bool] = []
    /// Whole years of membership of each bucket's wrapper at the end of each
    /// year: `year * buckets + bucket`.
    var membership: [Int] = []
    var bucketCount = 0

    @inline(__always)
    func isAccessible(year: Int, bucket: Int) -> Bool {
        accessible[year * bucketCount + bucket]
    }

    @inline(__always)
    func membershipYears(year: Int, bucket: Int) -> Int {
        membership[year * bucketCount + bucket]
    }

    /// The first age at or after `year` at which `bucket` can be drawn from.
    func accessibleFromAge(bucket: Int, after year: Int) -> Int? {
        for t in year..<years.count where isAccessible(year: t, bucket: bucket) {
            return years[t].age
        }
        return nil
    }
}

/// A pension claim decided in the schedule.
struct PensionClaim: Sendable {
    let pension: Int
    let year: Int
    /// Age when payments start.
    let age: Int
    let option: ClaimOption

    /// The gross amount of a whole year at `age`: in the year payments start,
    /// the rate they start at for twelve months, rather than the months paid.
    func yearlyAmount(atAge age: Int) -> Double {
        age <= option.age ? option.yearlyAmount : option.annualAmount(atAge: age)
    }
}

/// An amount going into a wrapper's bucket.
struct WrapperAmount: Sendable {
    let wrapper: String
    /// Resolved once the portfolio is final.
    var bucket: Int = -1
    let amount: Double
    /// What produced it, for credits: a work phase ID.
    var source: String?
}

/// An uncertain one-off amount.
struct UncertainAmount: Sendable {
    let bit: Int
    let amount: Double
}

/// One year of an ``AgeSchedule``.
struct ScheduledYear: Sendable {
    let year: Int
    let age: Int
    /// The simulated share of the year.
    let fraction: Double
    /// The share of the simulated part before retirement.
    let workingShare: Double
    /// Spending while working, in the simulated part.
    let workingSpending: Double
    /// Retirement spending per euro of yearly retirement spending: the
    /// phase factor times the retired share of the year.
    let retiredUnit: Double
    let certainExpenses: Double
    let uncertainExpenses: [UncertainAmount]
    /// The bits of this year's uncertain windfalls, in local-mask order.
    let windfallBits: [Int]
    var variants: [YearVariant]
    /// The variant for each local mask (`-1` where none was prepared).
    let variantIndex: [Int]
    let expectedVariant: Int
    /// Planned contributions into accounts, in the simulated part.
    var contributions: [WrapperAmount]
    let contributionTotal: Double
    /// Work and pension income in the simulated part, for reports.
    let income: [IncomeItem]
    /// Access context inputs.
    let contributionYears: Double
    let yearsSinceWorkStopped: Int?
    let oldAgePensionAge: Int?
    /// The tax state the year was prepared with (the deterministic run's).
    let taxState: TaxState
    /// Buckets paid out in full this year because a job ends (severance pay
    /// such as Italy's TFR); set once the portfolio is final.
    var severance: [Int] = []

    /// The variant for a run's event mask.
    func variant(for mask: UInt64) -> Int {
        guard !windfallBits.isEmpty else { return 0 }
        var local = 0
        for (position, bit) in windfallBits.enumerated() where mask & (1 << UInt64(bit)) != 0 {
            local |= 1 << position
        }
        let index = variantIndex[local]
        return index >= 0 ? index : expectedVariant
    }

    /// Expenses in a run with `mask`.
    func expenses(for mask: UInt64) -> Double {
        var total = certainExpenses
        for expense in uncertainExpenses where mask & (1 << UInt64(expense.bit)) != 0 {
            total += expense.amount
        }
        return total
    }
}

/// One prepared version of a year: the tax system's view with a given set
/// of windfalls.
struct YearVariant: Sendable {
    let prepared: any PreparedTaxYear
    /// The fixed assessment as the system returned it (for the whole year).
    let fixed: TaxAssessment
    /// `fixed`'s taxes plus contributions: subtracted from each path's
    /// assessment to leave the market-dependent part.
    let fixedTotal: Double
    /// Money in during the simulated part: work, pensions and windfalls,
    /// minus the taxes and contributions due on them.
    let netCash: Double
    /// Credits into wrappers, such as TFR.
    var accruals: [WrapperAmount]
    /// Windfalls received, for reports.
    let windfalls: [IncomeItem]
    /// The fixed taxes and contributions of the simulated part, for reports.
    let taxes: [AmountItem]
    let contributions: [AmountItem]
}

// MARK: - Building

extension AgeSchedule {
    /// Prepares every year for one retirement age.
    ///
    /// `neededMasks` lists, per year, the local windfall masks that occur in
    /// some run, so only those are prepared (the deterministic run's always
    /// is). The tax state carries from year to year along the deterministic run.
    init(model: PlanModel, age: Int, neededMasks: [[Int]], expectedMask: UInt64) {
        let retirementDate = model.retirementDate(forAge: age)
        let lastWorkDay = retirementDate.adding(days: -1)
        let birth = model.birthDate.birthDate
        var issues: [PlanIssue] = []
        var reportedIssues: Set<String> = []
        func report(_ issue: PlanIssue) {
            if reportedIssues.insert("\(issue.code)|\(issue.year ?? 0)|\(issue.message)").inserted {
                issues.append(issue)
            }
        }

        var state = TaxState.empty
        var records: [PensionRecord] = model.pensions.map { pension in
            pension.scheme.startingRecord(options: pension.options,
                                          year: model.frames.first?.year ?? model.startDate.year,
                                          parameters: pension.schemeParameters)
        }
        var claims: [PensionClaim?] = Array(repeating: nil, count: model.pensions.count)
        let schemeIDs = Set(model.pensions.map(\.schemeID))
        var years: [ScheduledYear] = []
        var fixedYears: [FixedYear] = []

        for frame in model.frames {
            let system = model.systems[frame.system].system
            let daysInYear = Double(frame.daysInYear)

            // Work.
            var workIncomes: [FixedYear.WorkIncome] = []
            var shares: [String: Double] = [:]
            var income: [IncomeItem] = []
            var cashIn = 0.0
            for phase in model.work {
                let last = phase.lastDay(retiring: retirementDate)
                let covered = frame.days(from: phase.from, until: last)
                guard covered > 0 else { continue }
                let share = Double(frame.simulatedDays(from: phase.from, until: last)) / Double(covered)
                let fraction = Double(covered) / daysInYear
                let scale = phase.growth(in: frame.year) * fraction
                let workIncome = FixedYear.WorkIncome(
                    phaseID: phase.id, kind: phase.kind, regime: phase.regime(in: system), options: phase.options,
                    gross: phase.gross * scale, costs: phase.costs * scale, net: phase.net.map { $0 * scale },
                    fractionOfYear: fraction)
                workIncomes.append(workIncome)
                shares[phase.id] = share
                let cash = (workIncome.net ?? workIncome.gross - workIncome.costs) * share
                cashIn += cash
                if share > 0 {
                    income.append(IncomeItem(kind: .work, id: phase.id, label: phase.label, amount: cash))
                }
            }

            // Pensions: claims use the record as it stood at the end of last year.
            var paid: [FixedYear.Pension] = []
            for (index, pension) in model.pensions.enumerated() {
                if claims[index] == nil,
                   let option = Self.claim(pension, record: records[index], frame: frame, birth: birth) {
                    claims[index] = PensionClaim(pension: index, year: frame.year, age: frame.age, option: option)
                    if case .age(let wanted) = pension.claim, frame.age > wanted {
                        report(.warning("planner.claimLater",
                                        "\(pension.name) can't be claimed at \(wanted); the plan claims it at \(frame.age).",
                                        section: .pensions, index: pension.index))
                    }
                }
                guard let claim = claims[index] else { continue }
                let amount = claim.option.annualAmount(atAge: frame.age)
                guard amount > 0 else { continue }
                paid.append(FixedYear.Pension(id: pension.id, scheme: pension.schemeID, amount: amount,
                                              taxedIn: pension.taxedIn))
                shares[pension.id] = frame.fraction
                cashIn += amount * frame.fraction
                income.append(IncomeItem(kind: .pension, id: pension.id, label: pension.name,
                                         amount: amount * frame.fraction))
            }

            // Taxes on total income, such as IRPEF, belong to no one subject:
            // their simulated share is each income's share weighted by the income.
            var incomeWeight = 0.0
            var simulatedIncome = 0.0
            for income in workIncomes where income.net == nil {
                let weight = max(0, income.gross - income.costs)
                incomeWeight += weight
                simulatedIncome += weight * (shares[income.phaseID] ?? frame.fraction)
            }
            for pension in paid {
                incomeWeight += max(0, pension.amount)
                simulatedIncome += max(0, pension.amount) * (shares[pension.id] ?? frame.fraction)
            }
            let incomeShare = incomeWeight > 0 ? simulatedIncome / incomeWeight : frame.fraction

            // Planned contributions, from the plan's start until they stop.
            var contributions: [WrapperAmount] = []
            var wrapperContributions: [FixedYear.WrapperContribution] = []
            for contribution in model.contributions {
                let last = contribution.until ?? lastWorkDay
                let whole = contribution.perYear * Double(frame.days(from: frame.firstDay, until: last)) / daysInYear
                let simulated = contribution.perYear
                    * Double(frame.simulatedDays(from: frame.simulatedFrom, until: last)) / daysInYear
                if whole > 0 {
                    wrapperContributions.append(FixedYear.WrapperContribution(wrapper: contribution.wrapper, amount: whole))
                }
                if simulated > 0 { contributions.append(WrapperAmount(wrapper: contribution.wrapper, amount: simulated)) }
            }

            // Events.
            let events = model.events.filter { $0.year == frame.year }
            let certainWindfalls = events.filter { $0.isWindfall && $0.bit == nil }
            let uncertainWindfalls = events.filter { $0.isWindfall && $0.bit != nil }
            let windfallBits = uncertainWindfalls.map { $0.bit! }
            let certainExpenses = events.filter { !$0.isWindfall && $0.bit == nil }.reduce(0) { $0 - $1.amount }
            let uncertainExpenses = events.filter { !$0.isWindfall && $0.bit != nil }
                .map { UncertainAmount(bit: $0.bit!, amount: -$0.amount) }

            // Prepare each needed combination of windfalls.
            var expectedLocal = 0
            for (position, bit) in windfallBits.enumerated() where expectedMask & (1 << UInt64(bit)) != 0 {
                expectedLocal |= 1 << position
            }
            var masks = windfallBits.isEmpty ? [0] : neededMasks[frame.index]
            if !masks.contains(expectedLocal) { masks.append(expectedLocal) }
            var variantIndex = [Int](repeating: -1, count: 1 << windfallBits.count)
            var variants: [YearVariant] = []
            let overlays = model.overlays.filter { system.regime($0.regime) != nil }
            for mask in masks {
                let windfalls = certainWindfalls + uncertainWindfalls.enumerated()
                    .filter { mask & (1 << $0.offset) != 0 }.map(\.element)
                let fixedYear = FixedYear(
                    year: frame.year, age: frame.age, systemOptions: frame.systemOptions, overlays: overlays,
                    work: workIncomes, pensions: paid, wrapperContributions: wrapperContributions,
                    windfalls: windfalls.map { FixedYear.Windfall(name: $0.name, kind: $0.kind, amount: $0.amount) },
                    inflationFactor: frame.inflationFactor, indexThresholds: model.indexThresholds)
                if mask == expectedLocal { fixedYears.append(fixedYear) }
                let prepared = system.prepare(fixedYear, state: state, parameters: frame.parameters)
                let fixed = prepared.fixedAssessment
                let windfallNames = Set(windfalls.map(\.name))
                let share: (String?) -> Double = { subject in
                    guard let subject else { return incomeShare }
                    // A windfall arrives in the simulated part, so all of its tax does too.
                    if windfallNames.contains(subject) { return 1 }
                    return shares[subject] ?? frame.fraction
                }
                let taxes = Self.scaled(fixed.lines, share: share)
                let socialContributions = Self.scaled(fixed.contributions, share: share)
                let windfallCash = windfalls.reduce(0) { $0 + $1.amount }
                let netCash = cashIn + windfallCash - taxes.reduce(0) { $0 + $1.amount }
                    - socialContributions.reduce(0) { $0 + $1.amount }
                let accruals = fixed.accruals.compactMap { accrual -> WrapperAmount? in
                    guard case .wrapper(let wrapper) = accrual.target else { return nil }
                    return WrapperAmount(wrapper: wrapper, amount: accrual.amount * share(accrual.source),
                                         source: accrual.source)
                }
                variantIndex[mask] = variants.count
                variants.append(YearVariant(
                    prepared: prepared, fixed: fixed, fixedTotal: fixed.totalTax + fixed.totalContributions,
                    netCash: netCash, accruals: accruals,
                    windfalls: windfalls.map { IncomeItem(kind: .windfall, id: $0.name, label: $0.name, amount: $0.amount) },
                    taxes: taxes, contributions: socialContributions))
            }
            let expected = variantIndex[expectedLocal]
            let expectedAssessment = variants[expected].fixed
            let yearState = state
            state = expectedAssessment.nextState

            // Access inputs, before this year's credits.
            let contributionYears = records.map(\.totalContributionYears).max() ?? 0
            let yearsSinceWorkStopped = retirementDate <= frame.lastDay
                ? retirementDate.wholeYears(to: frame.lastDay) : nil

            // Pension credits from the deterministic year.
            for (index, pension) in model.pensions.enumerated() {
                guard let parameters = try? pension.schemeParameters.parameters(for: frame.year) else {
                    // A fixed pension doesn't build up, so it needs no parameters.
                    if !pension.isFixed {
                        report(.warning("planner.noSchemeParameters",
                                        "\(pension.name) has no parameters for \(frame.year); its credits stop there.",
                                        section: .pensions, index: pension.index, year: frame.year))
                    }
                    continue
                }
                let scheme = pension.scheme
                let credits = expectedAssessment.accruals.compactMap { accrual -> Accrual? in
                    guard accrual.target == .pensionScheme(scheme.id) else { return nil }
                    let share = accrual.source.flatMap { shares[$0] } ?? frame.fraction
                    return Accrual(target: accrual.target, amount: accrual.amount * share,
                                   contributionMonths: Int((Double(accrual.contributionMonths) * share).rounded()),
                                   source: accrual.source)
                }
                scheme.accrue(credits, in: frame.year, to: &records[index], options: pension.options,
                              parameters: parameters)
            }
            for accrual in expectedAssessment.accruals {
                if case .pensionScheme(let scheme) = accrual.target, !schemeIDs.contains(scheme), accrual.amount > 0 {
                    report(.warning("planner.unclaimedScheme",
                                    "Work builds up a \(scheme) pension, but the plan has no \(scheme) pension to claim it.",
                                    section: .pensions))
                }
            }

            // Spending.
            let simulatedDays = frame.simulatedDays(from: frame.simulatedFrom, until: frame.lastDay)
            let workDays = frame.simulatedDays(from: frame.simulatedFrom, until: lastWorkDay)
            let retiredDays = simulatedDays - workDays
            years.append(ScheduledYear(
                year: frame.year, age: frame.age, fraction: frame.fraction,
                workingShare: simulatedDays > 0 ? Double(workDays) / Double(simulatedDays) : 0,
                workingSpending: model.spending.working * Double(workDays) / daysInYear,
                retiredUnit: model.spending.factor(atAge: frame.age) * Double(retiredDays) / daysInYear,
                certainExpenses: certainExpenses, uncertainExpenses: uncertainExpenses, windfallBits: windfallBits,
                variants: variants, variantIndex: variantIndex, expectedVariant: expected,
                contributions: contributions, contributionTotal: contributions.reduce(0) { $0 + $1.amount },
                income: income, contributionYears: contributionYears,
                yearsSinceWorkStopped: yearsSinceWorkStopped, oldAgePensionAge: model.oldAgePensionAges[frame.index],
                taxState: yearState))
        }

        self.retirementAge = age
        self.retirementDate = retirementDate
        self.years = years
        self.claims = claims
        self.fixedYears = fixedYears
        self.issues = issues
    }

    /// Decides whether a pension is claimed in `frame`'s year, and how: the
    /// latest of its scheme's claim options at or below the age that year,
    /// once the age the plan asks for is reached.
    private static func claim(_ pension: PensionSpec, record: PensionRecord, frame: YearFrame,
                              birth: BirthDate) -> ClaimOption? {
        if case .age(let wanted) = pension.claim, frame.age < wanted { return nil }
        let context = ClaimContext(year: frame.year, birthDate: birth, options: pension.options)
        return pension.scheme.claimOptions(for: record, context: context, parameters: pension.schemeParameters)
            .filter { $0.age <= frame.age }
            .max { $0.age < $1.age }
    }

    /// Tax or contribution lines summed by ID, each scaled by the share of
    /// its subject that falls in the simulated part of the year: a work
    /// phase's or pension's simulated share, 1 for a windfall's, and for a
    /// line without a subject (a tax on total income) the income-weighted
    /// share of the year's work and pensions.
    private static func scaled(_ lines: [TaxLine], share: (String?) -> Double) -> [AmountItem] {
        var result: [AmountItem] = []
        for line in lines {
            let amount = line.amount * share(line.subject)
            guard amount != 0 else { continue }
            if let index = result.firstIndex(where: { $0.id == line.id }) {
                result[index].amount += amount
            } else {
                result.append(AmountItem(id: line.id, label: line.label, amount: amount))
            }
        }
        return result
    }

    /// Resolves wrapper IDs to buckets once the portfolio is final, and fills
    /// in what depends on the buckets: membership, access and severance pay.
    mutating func resolve(for portfolio: Portfolio, model: PlanModel) {
        bucketCount = portfolio.buckets.count
        for t in years.indices {
            for index in years[t].contributions.indices {
                years[t].contributions[index].bucket =
                    portfolio.bucketIndex(wrapper: years[t].contributions[index].wrapper) ?? portfolio.primaryLiquid
            }
            for v in years[t].variants.indices {
                for index in years[t].variants[v].accruals.indices {
                    years[t].variants[v].accruals[index].bucket =
                        portfolio.bucketIndex(wrapper: years[t].variants[v].accruals[index].wrapper)
                            ?? portfolio.primaryLiquid
                }
            }
        }

        // Membership starts when an account joined the wrapper (or opened),
        // else with the first money paid in.
        var joined = portfolio.buckets.map(\.joined)
        for t in years.indices {
            let paidIn = years[t].contributions.filter { $0.amount > 0 }.map(\.bucket)
                + years[t].variants.flatMap { $0.accruals.filter { $0.amount > 0 }.map(\.bucket) }
            for bucket in paidIn where joined[bucket] == nil { joined[bucket] = model.frames[t].simulatedFrom }
        }

        access = []
        membership = []
        access.reserveCapacity(years.count * bucketCount)
        membership.reserveCapacity(years.count * bucketCount)
        for t in years.indices {
            let lastDay = CalendarDate.lastDay(of: years[t].year)
            for (b, bucket) in portfolio.buckets.enumerated() {
                let members = joined[b].map { max(0, $0.wholeYears(to: lastDay)) } ?? 0
                membership.append(members)
                guard let rule = bucket.rule else {
                    access.append(.accessible(route: nil))
                    continue
                }
                let context = WrapperAccessContext(
                    year: years[t].year, age: years[t].age, yearsSinceWorkStopped: years[t].yearsSinceWorkStopped,
                    oldAgePensionAge: years[t].oldAgePensionAge, contributionYears: years[t].contributionYears,
                    membershipYears: members)
                access.append(rule.access(in: context))
            }
        }
        accessible = access.map(\.isAccessible)
        scheduleSeverancePay(portfolio: portfolio, model: model)
    }

    /// Severance pay, such as Italy's TFR, is paid out in full when the job
    /// ends: credits at the end of the work phase that made them, and the
    /// balance at the start at the end of the employee phase running then
    /// (at once if none is). Retiring ends every phase.
    private mutating func scheduleSeverancePay(portfolio: Portfolio, model: PlanModel) {
        for t in years.indices { years[t].severance = [] }
        guard let firstYear = years.first?.year else { return }
        let firstDay = model.startDate.adding(days: 1)
        for (b, bucket) in portfolio.buckets.enumerated() where !bucket.isLiquid {
            guard let rule = bucket.rule, Self.isPaidWhenJobEnds(rule, year: firstYear) else { continue }
            var ends: Set<CalendarDate> = []
            let sources = Set(years.flatMap { year in
                year.variants.flatMap { $0.accruals.filter { $0.bucket == b && $0.amount > 0 }.compactMap(\.source) }
            })
            for phase in model.work where sources.contains(phase.id) {
                ends.insert(phase.lastDay(retiring: retirementDate))
            }
            if portfolio.lots[bucket.lots].contains(where: { $0.value > 0 }) {
                let running = model.work.filter { phase in
                    phase.kind == .employee && phase.from <= firstDay && phase.lastDay(retiring: retirementDate) >= firstDay
                }
                ends.insert(running.map { $0.lastDay(retiring: retirementDate) }.min() ?? firstDay)
            }
            for end in ends where end > model.startDate {
                guard let t = years.firstIndex(where: { $0.year == end.year }), !years[t].severance.contains(b)
                else { continue }
                years[t].severance.append(b)
            }
        }
    }

    /// Whether a wrapper is severance pay, paid out when a job ends: its rule
    /// keeps it locked while working and opens it as soon as work stops,
    /// whatever the age, membership and contributions (Italy's `it.tfr`).
    static func isPaidWhenJobEnds(_ rule: WrapperRule, year: Int) -> Bool {
        func opens(yearsSinceWorkStopped: Int?) -> Bool {
            rule.access(in: WrapperAccessContext(
                year: year, age: 0, yearsSinceWorkStopped: yearsSinceWorkStopped, oldAgePensionAge: nil,
                contributionYears: 0, membershipYears: 0)).isAccessible
        }
        return !opens(yearsSinceWorkStopped: nil) && opens(yearsSinceWorkStopped: 0)
    }
}

extension PlanModel {
    /// The tax systems' issues for the years of `schedule`: each system's
    /// `validate(_:years:parameters:)` over the deterministic years it's the
    /// residence for, which adds the checks that need each year's amounts
    /// (such as forfettario's revenue limits) to the plan's structural checks.
    func yearIssues(for schedule: AgeSchedule) -> [PlanIssue] {
        var issues: [PlanIssue] = []
        for (index, context) in systems.enumerated() {
            let years = zip(frames, schedule.fixedYears).filter { $0.0.system == index }.map(\.1)
            guard !years.isEmpty else { continue }
            for issue in context.system.validate(context.taxPlan, years: years, parameters: context.parameters) {
                issues.append(PlanIssue(issue, section: PlanInterpreter.section(of: issue, registry: registry)))
            }
        }
        return issues
    }
}
