import Foundation
import Model
import Planner

// The words of the plan's chapters (UI.md, "The plan"): their names, spans
// and lengths, the inputs in them, and when work stops; and the inputs a
// chapter adds. What the chapters are is the Planner's `PlanChaptersModel`.

extension PlanChaptersModel {
    /// "Employee", "Working", "Not working", "Bridge", "Pensions", "Slowing down".
    func title(of chapter: PlanChapter) -> String {
        switch style(of: chapter) {
        case .working:
            guard case .working(let phase) = chapter.kind, plan.work.indices.contains(phase) else { return "Working" }
            if let name = plan.work[phase].name { return name }
            return plan.work.count > 1 ? "Working, phase \(phase + 1)" : "Working"
        case .notWorking:
            return "Not working"
        case .bridge:
            return hasPensions ? "Bridge" : "Retired"
        case .pensions:
            return plan.pensions.count == 1 ? "Pension" : "Pensions"
        case .later:
            return (chapter.spendingFactor ?? 1) > 1 ? "Spending more" : "Slowing down"
        }
    }

    /// "Now to 55 · 2026 to 2043": the ages and the years it runs between.
    func span(ofChapterAt index: Int) -> String {
        let all = chapters.chapters
        guard all.indices.contains(index) else { return "" }
        let chapter = all[index]
        let next = all.indices.contains(index + 1) ? all[index + 1] : nil
        let fromAge = index == 0 ? "Now" : "\(chapter.ages.lowerBound)"
        let toAge = next.map { "\($0.ages.lowerBound)" } ?? "\(chapter.ages.upperBound)"
        let toYear = next?.years.lowerBound ?? chapter.years.upperBound
        return "\(fromAge) to \(toAge) · \(chapter.years.lowerBound) to \(toYear)"
    }

    /// "now to 41", "41 to 55", "67 on": the ages it runs between, the last
    /// chapter's from its first; "from now" for a plan of one chapter.
    func ages(ofChapterAt index: Int) -> String {
        let all = chapters.chapters
        guard all.indices.contains(index) else { return "" }
        let from = index == 0 ? "now" : "\(all[index].ages.lowerBound)"
        guard all.indices.contains(index + 1) else { return index == 0 ? "from now" : "\(from) on" }
        return "\(from) to \(all[index + 1].ages.lowerBound)"
    }

    /// "41 to 55, 2029 to 2043": the ages and the years it runs between.
    func agesAndYears(ofChapterAt index: Int) -> String {
        let all = chapters.chapters
        guard all.indices.contains(index) else { return "" }
        let chapter = all[index]
        let next = all.indices.contains(index + 1) ? all[index + 1] : nil
        let fromAge = index == 0 ? "Now" : "\(chapter.ages.lowerBound)"
        let toAge = next.map { "\($0.ages.lowerBound)" } ?? "\(chapter.ages.upperBound)"
        let toYear = next?.years.lowerBound ?? chapter.years.upperBound
        return "\(fromAge) to \(toAge), \(chapter.years.lowerBound) to \(toYear)"
    }

    /// "16½ years", to the nearest half year.
    func length(ofChapterAt index: Int) -> String {
        let halves = Int(halfYears(ofChapterAt: index) * 2)
        let whole = halves / 2
        let half = halves % 2 == 1 ? "½" : ""
        if whole == 0 { return half.isEmpty ? "Under half a year" : "½ year" }
        return "\(whole)\(half) " + (whole == 1 && half.isEmpty ? "year" : "years")
    }

    // MARK: Inputs in words

    /// An input's name, for the "Continuing" line and the inputs outside
    /// the plan's years.
    func name(of item: PlanChapter.Item) -> String {
        switch item {
        case .retirement:
            return "Work stops"
        case .workingSpending:
            return "Spending while working"
        case .retiredSpending:
            return "Spending in retirement"
        case .spendingPhase(let index):
            guard plan.spending.phases.indices.contains(index) else { return "Later spending" }
            return "Spending from \(plan.spending.phases[index].fromAge)"
        case .work(let index):
            guard plan.work.indices.contains(index) else { return "Work" }
            return plan.workName(index)
        case .pension(let index):
            guard plan.pensions.indices.contains(index) else { return "Pension" }
            return plan.pensionName(index)
        case .income(let index):
            guard plan.income.indices.contains(index) else { return "Other income" }
            return plan.incomeName(index)
        case .contribution(let index):
            guard plan.contributions.indices.contains(index) else { return "Contribution" }
            return "Saving into \(accountName(plan.contributions[index].account))"
        case .event(let index):
            guard plan.events.indices.contains(index) else { return "Event" }
            return plan.events[index].name
        case .targetMix:
            return "Target mix"
        case .targetMixStep(let index):
            let steps = plan.portfolio.targetMixByAge
            guard steps.indices.contains(index) else { return "Target mix" }
            return "Target mix " + PlanTargetMixModel.title(of: steps[index].fromAge).lowercased()
        case .end:
            return "The plan's end"
        }
    }

    /// "Continuing: Spending while working · Saving into Fondo pensione ·
    /// Target mix"; `nil` when nothing carries on into the chapter.
    func continuing(in chapter: PlanChapter) -> String? {
        guard !chapter.continuing.isEmpty else { return nil }
        return "Continuing: " + chapter.continuing.map { name(of: $0) }.joined(separator: " · ")
    }

    /// When work stops, in words, by where the age comes from: "Work stops
    /// at 55, in 2043.", "… the earliest age the plan found.", "Until the
    /// plan is calculated, its chapters assume work stops at 65."
    var retirementNote: String {
        let passed = chapters.birthYear + retirementAge < start.year
        let when = passed ? "Work stops at the start: you're past \(retirementAge)."
            : "Work stops at \(retirementAge), in \(retirementYear)."
        switch ageSource {
        case .chosen:
            return "The chapters and charts are for retiring at \(retirementAge), chosen under \"If you stopped at another age\"."
        case .whatIf:
            return "The chapters follow the what-if: retiring at \(retirementAge)."
        case .plan:
            return when
        case .results:
            return "\(when) It's the earliest age the plan found."
        case .recorded:
            return "\(when) It's the earliest age recorded at your last check-in; calculate for today's."
        case .assumed:
            return "Until the plan is calculated, its chapters assume work stops at \(retirementAge)."
        }
    }

    // MARK: New inputs for a chapter

    /// A work phase in the chapter until retirement, from
    /// ``newWorkPhaseStart(in:)``.
    func newWorkPhase(in chapter: PlanChapter) -> WorkPhase {
        var phase = PlanEditing.newWorkPhase(in: plan, asOf: start)
        phase.from = newWorkPhaseStart(in: chapter)
        phase.until = .retirement
        return phase
    }

    /// A pension from the chapter's first age.
    func newPension(in chapter: PlanChapter) -> PlanPension {
        var pension = PlanEditing.newPension()
        pension.fromAge = chapter.ages.lowerBound
        return pension
    }

    /// Other income from when work stops in the chapter it stops in, else
    /// from the chapter's first age; its amount still to fill in.
    func newIncome(in chapter: PlanChapter) -> PlanIncome {
        let from: AgeOrRetirement = chapter.items.contains(.retirement) ? .retirement : .age(chapter.ages.lowerBound)
        return PlanIncome(name: "Other income", from: from, perYear: nil)
    }

    /// In the first chapter, a yearly contribution until retirement; in a
    /// later one, a one-off in its first year, so it lands in the chapter.
    func newContribution(in chapter: PlanChapter, library: Library) -> PlanContribution? {
        guard var contribution = PlanEditing.newContribution(in: library, plan: plan) else { return nil }
        if chapter.years.lowerBound > (chapters.chapters.first?.years.lowerBound ?? start.year) {
            contribution = PlanContribution(account: contribution.account, amount: contribution.perYear,
                                            year: chapter.years.lowerBound)
        }
        return contribution
    }

    /// An expense in the chapter's first year.
    func newEvent(in chapter: PlanChapter) -> PlanEvent {
        var event = PlanEditing.newEvent(in: plan, asOf: start)
        event.timing = .year(chapter.years.lowerBound)
        return event
    }

    /// A later phase of retirement spending from the middle of a retired
    /// chapter, or the next age no phase starts at.
    func newSpendingPhase(in chapter: PlanChapter) -> SpendingPhase {
        var phase = PlanEditing.newSpendingPhase(in: plan)
        let taken = Set(plan.spending.phases.map(\.fromAge))
        phase.fromAge = chapter.ages.lowerBound + chapter.ages.count / 2
        while taken.contains(phase.fromAge) { phase.fromAge += 1 }
        return phase
    }
}
