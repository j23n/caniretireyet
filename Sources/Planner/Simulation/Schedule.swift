import Foundation
import Model

/// Everything about the years that depends on the retirement age but not on
/// markets: income, spending, contributions, when locked money opens and
/// the target mix in force. Built once per retirement age; every run at that
/// age reads it. Amounts are for the simulated part of each year.
struct AgeSchedule: Sendable {
    /// One contribution in a year.
    struct Contribution: Sendable {
        let bucket: Int
        let amount: Double
    }

    let retirementAge: Int
    /// The day work stops.
    let retirementDate: CalendarDate
    /// Per year: income from work, pensions and other income, by item.
    let income: [[IncomeItem]]
    /// Per year: their total.
    let regularIncome: [Double]
    /// Per year: spending while working (the plan's, for the working days).
    let workingSpending: [Double]
    /// Per year: the plan's retirement spending at 100% is multiplied by
    /// this: the retired share of the year times the phase factor.
    let retiredUnit: [Double]
    /// Per year: whether work has stopped before the simulated part starts.
    let fullyRetired: [Bool]
    /// Per year: the share of the simulated part spent working.
    let workingShare: [Double]
    let contributions: [[Contribution]]
    /// Per year: the buckets that join the money you can draw at its start.
    let opens: [[Int]]
    /// Per year: the target mix of the money you can draw, as shares by class.
    let accessibleMix: [[Double]]
    /// Per year: the indices into ``PlanModel/events`` of the year's events.
    let events: [[Int]]

    init(model: PlanModel, age: Int) {
        retirementAge = age
        let retiring = model.retirementDate(forAge: age)
        retirementDate = retiring
        let classes = model.portfolio.classes
        let fallbackMix = model.portfolio.accessibleShares
            ?? Self.shares(of: model.portfolio.buckets.reduce(into: Array(repeating: 0.0, count: classes.count)) {
                for c in classes.indices { $0[c] += $1.values[c] }
            })
            ?? classes.map { $0 == .cash ? 1 : 0 }

        var income: [[IncomeItem]] = []
        var regular: [Double] = []
        var working: [Double] = []
        var retired: [Double] = []
        var fully: [Bool] = []
        var workingShare: [Double] = []
        var contributions: [[Contribution]] = []
        var opens: [[Int]] = []
        var mixes: [[Double]] = []
        var events: [[Int]] = []
        let dayBefore = retiring.adding(days: -1)

        for frame in model.frames {
            var items: [IncomeItem] = []
            for phase in model.work {
                let share = frame.share(from: phase.from, until: phase.lastDay(retiring: retiring))
                guard share > 0 else { continue }
                items.append(IncomeItem(kind: .work, id: phase.id, label: phase.label,
                                        amount: phase.net * phase.growth(in: frame.year) * share))
            }
            for pension in model.pensions {
                let share = frame.share(from: model.birthDate.adding(years: pension.fromAge), until: frame.lastDay)
                guard share > 0, pension.perYear > 0 else { continue }
                items.append(IncomeItem(kind: .pension, id: pension.id, label: pension.name,
                                        amount: pension.perYear * share))
            }
            for other in model.income {
                let share = frame.share(from: other.firstDay(birthDate: model.birthDate, retiring: retiring),
                                        until: other.lastDay(birthDate: model.birthDate) ?? frame.lastDay)
                guard share > 0, other.perYear > 0 else { continue }
                items.append(IncomeItem(kind: .other, id: other.id, label: other.name, amount: other.perYear * share))
            }
            income.append(items)
            regular.append(items.reduce(0) { $0 + $1.amount })

            let workShare = frame.share(from: frame.simulatedFrom, until: dayBefore)
            let retiredShare = frame.share(from: retiring, until: frame.lastDay)
            working.append(model.spending.working * workShare)
            retired.append(retiredShare * model.spending.factor(atAge: frame.age))
            fully.append(retiring <= frame.simulatedFrom)
            workingShare.append(frame.fraction > 0 ? min(1, workShare / frame.fraction) : 0)

            var paid: [Contribution] = []
            for contribution in model.contributions {
                if let oneOff = contribution.oneOff {
                    if oneOff.year == frame.year, oneOff.amount > 0 {
                        paid.append(Contribution(bucket: contribution.bucket, amount: oneOff.amount))
                    }
                    continue
                }
                let until = min(contribution.until ?? dayBefore, dayBefore)
                let share = frame.share(from: frame.simulatedFrom, until: until)
                if share > 0, contribution.perYear > 0 {
                    paid.append(Contribution(bucket: contribution.bucket, amount: contribution.perYear * share))
                }
            }
            contributions.append(paid)

            opens.append(model.portfolio.buckets.indices.dropFirst().filter { b in
                guard let age = model.portfolio.buckets[b].opensAtAge else { return false }
                let first = model.firstYear(atAge: age)
                return first == frame.year || (frame.index == 0 && first < frame.year)
            })

            let target = model.plan.portfolio.targetMix(atAge: frame.age, retiringAt: age)
                .flatMap { Portfolio.shares($0) }
                .map { mix in classes.map { mix[$0] ?? 0 } }
            mixes.append(target ?? fallbackMix)
            events.append(model.events.indices.filter { model.events[$0].year == frame.year })
        }
        self.income = income
        regularIncome = regular
        workingSpending = working
        retiredUnit = retired
        fullyRetired = fully
        self.workingShare = workingShare
        self.contributions = contributions
        self.opens = opens
        accessibleMix = mixes
        self.events = events
    }

    /// The years with retirement spending.
    var retirementYears: Int { retiredUnit.filter { $0 > 0 }.count }

    /// `values` as shares summing to 1, or `nil` when they sum to nothing.
    static func shares(of values: [Double]) -> [Double]? {
        let total = values.reduce(0) { $0 + max(0, $1) }
        guard total > 0 else { return nil }
        return values.map { max(0, $0) / total }
    }
}
