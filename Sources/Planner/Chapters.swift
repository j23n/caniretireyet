import Foundation
import Model

/// A plan's years split into chapters (PLANNER.md, "Chapters"): stretches of
/// calendar years in which the same things pay for your life. A chapter
/// starts in the year the work phase you're in changes, work stops, the
/// first pension is paid or retirement spending moves to another phase.
/// Everything else the plan says (another pension, other income, a
/// contribution, an event, a change of target mix) is an item of the chapter
/// it starts or happens in.
public struct PlanChapters: Hashable, Sendable {
    /// The chapters in order. Together they cover every calendar year the
    /// plan simulates, from the check-in's to the one it reaches its end age in.
    public var chapters: [PlanChapter]
    /// Inputs that apply in none of the plan's years, such as an event after
    /// its end, a work phase over before it starts or a pension without an
    /// age; in the order of ``PlanChapter/Item``.
    public var outside: [PlanChapter.Item]
    /// The year the person was born: during a calendar year they reach the
    /// age `year - birthYear`.
    public var birthYear: Int
    /// The retirement age the chapters are for.
    public var retirementAge: Int
    /// The year work stops: the year that age is reached, or the check-in's
    /// when it has passed.
    public var retirementYear: Int

    /// The chapters of `plan` when work stops at `retirementAge`, for a
    /// person born in `birthYear`, with the plan starting from the check-in
    /// on `start`. An age already passed stops work at the start.
    public init(plan: PlanDocument, birthYear: Int, start: CalendarDate, retirementAge: Int) {
        let builder = ChapterBuilder(plan: plan, birthYear: birthYear, start: start, retirementAge: retirementAge)
        let built = builder.build()
        chapters = built.chapters
        outside = built.outside
        self.birthYear = birthYear
        self.retirementAge = retirementAge
        retirementYear = builder.retirementYear
    }

    /// The index of the chapter covering `year`.
    public func chapterIndex(containing year: Int) -> Int? {
        chapters.firstIndex { $0.years.contains(year) }
    }
}

/// One chapter of a plan (``PlanChapters``).
public struct PlanChapter: Hashable, Sendable {
    /// What pays for your life during a chapter.
    public enum Kind: Hashable, Sendable {
        /// Before retirement, while a work phase pays: its index in
        /// ``PlanDocument/work``.
        case working(phase: Int)
        /// Before retirement with no work phase: you live on your savings,
        /// still spending what you do while working.
        case betweenWork
        /// Retired, before any pension is paid: you live on your savings.
        case bridge
        /// Retired, with at least one pension paid.
        case pensions
    }

    /// An input of the plan, by where it is in ``PlanDocument``. Within a
    /// chapter, inputs starting in the same year are listed in this order.
    public enum Item: Hashable, Sendable {
        /// When work stops (``PlanDocument/retirement``).
        case retirement
        /// Spending while working (``PlanSpending/working``).
        case workingSpending
        /// Spending in retirement (``PlanSpending/retired``), with its
        /// flexible rule.
        case retiredSpending
        /// A later phase of retirement spending: an index into
        /// ``PlanSpending/phases``.
        case spendingPhase(Int)
        /// An index into ``PlanDocument/work``.
        case work(Int)
        /// An index into ``PlanDocument/pensions``.
        case pension(Int)
        /// An index into ``PlanDocument/income``.
        case income(Int)
        /// An index into ``PlanDocument/contributions``.
        case contribution(Int)
        /// An index into ``PlanDocument/events``.
        case event(Int)
        /// The target mix from the start (``PlanPortfolio/targetMix``, or
        /// the starting mix when the plan has none).
        case targetMix
        /// A change of the target mix with age: an index into
        /// ``PlanPortfolio/targetMixByAge``.
        case targetMixStep(Int)
        /// The age the plan runs to (``PlanDocument/endAge``).
        case end
    }

    public var kind: Kind
    /// The calendar years the chapter covers. The plan's first year is
    /// simulated from the day after the check-in.
    public var years: ClosedRange<Int>
    /// The ages reached in its first and its last year.
    public var ages: ClosedRange<Int>
    /// In retirement, the factor on retirement spending in force (1 before
    /// any phase); `nil` before retirement.
    public var spendingFactor: Decimal?
    /// The inputs that start or happen in the chapter, by the year they do.
    public var items: [Item] = []
    /// The inputs still in force from an earlier chapter.
    public var continuing: [Item] = []

    /// Whether work has stopped.
    public var isRetired: Bool {
        switch kind {
        case .bridge, .pensions: true
        case .working, .betweenWork: false
        }
    }

    /// The year a point on the chapter's time axis stands for: the year of
    /// `date`, within the chapter's years. The axis starts on 31 December of
    /// the year before the chapter's first, and that point counts as its
    /// first year.
    public func year(on date: CalendarDate) -> Int {
        min(max(date.year, years.lowerBound), years.upperBound)
    }

    /// The age at a point on the chapter's time axis: the age reached during
    /// ``year(on:)``, as ``ages`` counts them, whatever the birthday.
    public func age(on date: CalendarDate) -> Int {
        ages.lowerBound + year(on: date) - years.lowerBound
    }
}

extension Planner {
    /// The chapters of `plan` as a run reads it from `library`
    /// (``PlanChapters``): from the day it starts (its own start date, else
    /// the latest check-in, else `today`) to its end age, with work stopping
    /// at `retirementAge`, or at the plan's own age when that's `nil`.
    ///
    /// `nil` when the library's settings have no birth date, or when the plan
    /// asks for the earliest age and no `retirementAge` is given: pass the
    /// age a result found, or the one recorded at the last check-in.
    public static func chapters(plan: PlanDocument, library: Library, retirementAge: Int? = nil,
                                today: CalendarDate? = nil) -> PlanChapters? {
        guard let birthDate = library.settings.person?.birthDate,
              let age = retirementAge ?? plan.retirement.age.age else { return nil }
        return PlanChapters(plan: plan, birthYear: birthDate.year, start: plan.startDate(in: library, today: today),
                            retirementAge: age)
    }
}

extension PlanChapter.Item {
    /// Inputs starting in the same year are listed by kind, then in the
    /// plan's order.
    fileprivate var order: (Int, Int) {
        switch self {
        case .retirement: (0, 0)
        case .workingSpending: (1, 0)
        case .retiredSpending: (1, 1)
        case .spendingPhase(let index): (2, index)
        case .work(let index): (3, index)
        case .pension(let index): (4, index)
        case .income(let index): (5, index)
        case .contribution(let index): (6, index)
        case .event(let index): (7, index)
        case .targetMix: (8, -1)
        case .targetMixStep(let index): (8, index)
        case .end: (9, 0)
        }
    }
}

/// Works out the chapters: what pays for your life at the end of each year,
/// a chapter for each stretch of years where that stays the same, then each
/// input placed by the years it's in force.
private struct ChapterBuilder {
    typealias Item = PlanChapter.Item

    /// What pays for your life at the end of a year.
    enum State: Equatable {
        case working(phase: Int?)
        case retired(pensions: Bool, factor: Decimal)
    }

    let plan: PlanDocument
    let birthYear: Int
    /// The check-in's year.
    let startYear: Int
    /// The first and the last calendar year simulated.
    let first: Int
    let last: Int
    let retirementAge: Int
    /// The year work stops (the check-in's when the age has passed): it and
    /// every later year count as retired.
    let retirementYear: Int

    init(plan: PlanDocument, birthYear: Int, start: CalendarDate, retirementAge: Int) {
        self.plan = plan
        self.birthYear = birthYear
        startYear = start.year
        first = start.adding(days: 1).year
        last = birthYear + plan.effectiveEndAge
        self.retirementAge = retirementAge
        retirementYear = max(birthYear + retirementAge, start.year)
    }

    func build() -> (chapters: [PlanChapter], outside: [Item]) {
        var chapters = spans()
        var starting = Array(repeating: [(item: Item, year: Int)](), count: chapters.count)
        var continuing = Array(repeating: [Item](), count: chapters.count)
        var outside: [Item] = []
        for placement in placements() {
            guard let years = placement.years,
                  let home = chapters.firstIndex(where: { $0.years.contains(years.lowerBound) }) else {
                outside.append(placement.item)
                continue
            }
            starting[home].append((placement.item, years.lowerBound))
            for index in chapters.indices where index > home && chapters[index].years.overlaps(years) {
                continuing[index].append(placement.item)
            }
        }
        for index in chapters.indices {
            chapters[index].items = starting[index]
                .sorted { ($0.year, $0.item.order.0, $0.item.order.1) < ($1.year, $1.item.order.0, $1.item.order.1) }
                .map { $0.item }
            chapters[index].continuing = continuing[index].sorted { $0.order < $1.order }
        }
        return (chapters, outside.sorted { $0.order < $1.order })
    }

    /// A chapter, without its inputs yet, for each stretch of years with the
    /// same ``State``.
    func spans() -> [PlanChapter] {
        guard first <= last else { return [] }
        var runs: [(state: State, years: ClosedRange<Int>)] = []
        for year in first...last {
            let current = state(in: year)
            if let previous = runs.last, previous.state == current {
                runs[runs.count - 1].years = previous.years.lowerBound...year
            } else {
                runs.append((state: current, years: year...year))
            }
        }
        return runs.map { run -> PlanChapter in
            let ages = (run.years.lowerBound - birthYear)...(run.years.upperBound - birthYear)
            switch run.state {
            case .working(let phase):
                let kind = phase.map { PlanChapter.Kind.working(phase: $0) } ?? PlanChapter.Kind.betweenWork
                return PlanChapter(kind: kind, years: run.years, ages: ages)
            case .retired(let pensions, let factor):
                return PlanChapter(kind: pensions ? .pensions : .bridge, years: run.years, ages: ages,
                                   spendingFactor: factor)
            }
        }
    }

    /// What pays for your life at the end of `year`.
    func state(in year: Int) -> State {
        guard year < retirementYear else {
            return .retired(pensions: pensionPaid(by: year), factor: plan.spending.factor(atAge: year - birthYear))
        }
        return .working(phase: workPhase(atEndOf: year))
    }

    /// Whether a pension is paid by the end of `year`: one starts on the
    /// birthday at its age.
    func pensionPaid(by year: Int) -> Bool {
        plan.pensions.contains { pension in
            guard let age = pension.fromAge, let perYear = pension.perYear, perYear > 0 else { return false }
            return birthYear + age <= year
        }
    }

    /// The work phase in force on 31 December of `year`, a year before work
    /// stops; of several, the one that started last.
    func workPhase(atEndOf year: Int) -> Int? {
        let day = CalendarDate.lastDay(ofYear: year)
        let work = plan.work
        return work.indices
            .filter { index in
                guard work[index].from <= day else { return false }
                guard let until = work[index].until.date else { return true }
                return until >= day
            }
            .max { a, b in (work[a].from, a) < (work[b].from, b) }
    }

    /// Every input with the years it's in force or happens in; `nil` when
    /// that's none of the plan's years.
    func placements() -> [(item: Item, years: ClosedRange<Int>?)] {
        let retired = max(retirementYear, first)
        var placed: [(item: Item, years: ClosedRange<Int>?)] = [
            (item: Item.retirement, years: span(retired, retired)),
            (item: Item.workingSpending, years: span(first, retirementYear - 1)),
            (item: Item.retiredSpending, years: span(retired, last)),
        ]
        for index in plan.spending.phases.indices {
            let years = range(from: retired, to: last, where: { spendingPhase(atAge: $0 - birthYear) == index })
            placed.append((item: Item.spendingPhase(index), years: years))
        }
        for index in plan.work.indices {
            placed.append((item: Item.work(index), years: workYears(index)))
        }
        for (index, pension) in plan.pensions.enumerated() {
            let years = pension.fromAge.flatMap { age in span(birthYear + age, last) }
            placed.append((item: Item.pension(index), years: years))
        }
        for (index, income) in plan.income.enumerated() {
            placed.append((item: Item.income(index), years: incomeYears(income, retired: retired)))
        }
        for (index, contribution) in plan.contributions.enumerated() {
            placed.append((item: Item.contribution(index), years: contributionYears(contribution)))
        }
        for (index, event) in plan.events.enumerated() {
            let happens: Int = switch event.timing {
            case .age(let age): birthYear + age
            case .year(let year): year
            }
            placed.append((item: Item.event(index), years: span(happens, happens)))
        }
        let base = range(from: first, to: last, where: { mixStep(in: $0) == nil }) ?? span(first, first)
        placed.append((item: Item.targetMix, years: base))
        for index in plan.portfolio.targetMixByAge.indices {
            let years = range(from: first, to: last, where: { mixStep(in: $0) == index })
            placed.append((item: Item.targetMixStep(index), years: years))
        }
        placed.append((item: Item.end, years: span(last, last)))
        return placed
    }

    /// A work phase's years: those it's in force at the end of, before work
    /// stops; or the year it starts, for one over within a year. `nil` when
    /// it pays in none of the plan's years.
    func workYears(_ index: Int) -> ClosedRange<Int>? {
        if let atYearEnd = range(from: first, to: retirementYear - 1, where: { workPhase(atEndOf: $0) == index }) {
            return atYearEnd
        }
        let phase = plan.work[index]
        guard phase.from.year <= retirementYear, (phase.until.date?.year ?? retirementYear) >= first else {
            return nil
        }
        let year = max(phase.from.year, first)
        return span(year, year)
    }

    /// Other income's years: from the year it starts (work stopping's, for
    /// one from retirement) to the one it stops in, or the plan's end.
    func incomeYears(_ income: PlanIncome, retired: Int) -> ClosedRange<Int>? {
        guard let from = income.from else { return nil }
        return span(from.age.map { birthYear + $0 } ?? retired, income.untilAge.map { birthYear + $0 } ?? last)
    }

    /// A contribution's years: a one-off's year, or every year from the
    /// start until it stops, at the latest when work does.
    func contributionYears(_ contribution: PlanContribution) -> ClosedRange<Int>? {
        if contribution.isOneOff {
            let year = contribution.year ?? startYear
            return span(year, year)
        }
        let until = contribution.effectiveUntil.date?.year ?? retirementYear - 1
        return span(first, min(until, retirementYear - 1))
    }

    /// The index of the spending phase in force at `age`, picked as
    /// ``PlanSpending/factor(atAge:)`` picks it.
    func spendingPhase(atAge age: Int) -> Int? {
        let phases = plan.spending.phases
        return phases.indices
            .filter { phases[$0].fromAge <= age }
            .max { phases[$0].fromAge < phases[$1].fromAge }
    }

    /// The index of the target mix step in force in `year`; `nil` while
    /// ``PlanPortfolio/targetMix`` is.
    func mixStep(in year: Int) -> Int? {
        plan.portfolio.targetMixStep(atAge: year - birthYear, retiringAt: retirementAge)
    }

    /// `from...to` within the plan's years; `nil` when that's no year.
    func span(_ from: Int, _ to: Int) -> ClosedRange<Int>? {
        let lower = max(from, first)
        let upper = min(to, last)
        return lower <= upper ? lower...upper : nil
    }

    /// From the first to the last year from `from` to `to`, within the
    /// plan's, for which `test` holds; `nil` when there's none.
    func range(from: Int, to: Int, where test: (Int) -> Bool) -> ClosedRange<Int>? {
        guard let all = span(from, to) else { return nil }
        let matching = all.filter(test)
        guard let lower = matching.first, let upper = matching.last else { return nil }
        return lower...upper
    }
}
