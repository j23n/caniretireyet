import Foundation
import Model
import Planner

/// The chapters of the plan on screen (UI.md, "Chapters"; PLANNER.md,
/// "Chapters"): its years cut where what pays for your life changes, each
/// input in the chapter it starts in, and, once the plan has results, where
/// the money stands at the end of each.
///
/// The chapters follow the plan as shown, so an edit moves them at once.
/// They're cut at the retirement age the charts are for (``AgeSource``).
/// Where the money stands comes from the results shown, which can be out of
/// date; the views dim it then, as they dim the results.
struct PlanChaptersModel {
    /// Where the retirement age the chapters are cut at comes from, first
    /// match first.
    enum AgeSource: Hashable, Sendable {
        /// An age chosen on the success curve for the charts.
        case chosen
        /// The what-if's retirement age.
        case whatIf
        /// The plan's own age.
        case plan
        /// The age the results shown are for: the earliest age they found.
        case results
        /// The earliest age recorded at the last check-in, before any results.
        case recorded
        /// A stand-in until the plan finds its earliest age (``assumedAge``).
        case assumed
    }

    /// Where the money stands at the end of a chapter.
    struct Outcome: Hashable, Sendable {
        /// The chapter's last year, and the age reached in it.
        var year: Int
        var age: Int
        /// Plan assets at that year's end, in today's money: 1 in 10
        /// futures below `low`, half below `median`, 1 in 10 above `high`.
        var low: Double
        var median: Double
        var high: Double
        /// The futures whose money runs out during the chapter; `nil` when
        /// the results don't say (the preview engine).
        var failures: Int?
        /// Every future simulated.
        var runs: Int

        /// `failures / runs`.
        var failureShare: Double? {
            failures.map { runs > 0 ? Double($0) / Double(runs) : 0 }
        }
    }

    let plan: PlanDocument
    let chapters: PlanChapters
    let ageSource: AgeSource
    /// The day the plan starts from: the latest check-in, or its own start date.
    let start: CalendarDate
    /// By chapter index; empty without results.
    let outcomes: [Int: Outcome]
    /// The accounts' names, for contributions.
    private let accountNames: [AccountID: String]

    /// The age a plan asking for the earliest age is cut at before it has
    /// found one.
    static let assumedAge = 65

    /// The chapters of `plan` as shown; `nil` without a birth date.
    ///
    /// - Parameters:
    ///   - results: The results shown, for the outcomes.
    ///   - chosenAge: An age chosen for the charts (``PlanSession/focusAge``).
    ///   - whatIfAge: The what-if's retirement age, while one is in use.
    ///   - recordedAge: The earliest age recorded at the last check-in.
    init?(plan: PlanDocument, library: Library, results: PlanResults?, chosenAge: Int? = nil,
          whatIfAge: Int? = nil, recordedAge: Int? = nil, today: CalendarDate = .today()) {
        guard let birthDate = library.settings.person?.birthDate else { return nil }
        let start: CalendarDate = switch plan.portfolio.effectiveStart {
        case .date(let date): date
        case .latestCheckIn: library.latestCheckInDate ?? today
        }
        let resultsAge = results?.details?.focus.age ?? results?.headline.earliestAge
        let (age, source) = Self.retirementAge(
            plan: plan, chosenAge: chosenAge, whatIfAge: whatIfAge, resultsAge: resultsAge, recordedAge: recordedAge,
            currentAge: start.year - birthDate.year)
        guard let chapters = Planner.chapters(plan: plan, library: library, retirementAge: age, today: today) else {
            return nil
        }
        self.plan = plan
        self.chapters = chapters
        ageSource = source
        self.start = start
        outcomes = results.map { Self.outcomes(of: chapters, results: $0) } ?? [:]
        accountNames = library.accounts.mapValues(\.name)
    }

    /// The age the chapters are cut at, and where it comes from (``AgeSource``).
    static func retirementAge(plan: PlanDocument, chosenAge: Int?, whatIfAge: Int?, resultsAge: Int?,
                              recordedAge: Int?, currentAge: Int) -> (Int, AgeSource) {
        if let chosenAge { return (chosenAge, .chosen) }
        if let whatIfAge { return (whatIfAge, .whatIf) }
        if let age = plan.retirement.age.age { return (age, .plan) }
        if let resultsAge { return (resultsAge, .results) }
        if let recordedAge { return (recordedAge, .recorded) }
        return (min(max(assumedAge, currentAge), plan.effectiveEndAge), .assumed)
    }

    /// Where the money stands at each chapter's end: the fan at the end of
    /// its last year, and the futures failing at its ages.
    static func outcomes(of chapters: PlanChapters, results: PlanResults) -> [Int: Outcome] {
        var yearEnds: [Int: FanPoint] = [:]
        for point in results.portfolio {
            let date = CalendarDate(point.date, in: .current)
            if date.month == 12, date.day == 31 { yearEnds[date.year] = point }
        }
        let failures = results.details?.focus.failuresByAge
        var outcomes: [Int: Outcome] = [:]
        for (index, chapter) in chapters.chapters.enumerated() {
            guard let end = yearEnds[chapter.years.upperBound] else { continue }
            let failing = failures.map { counts in
                counts.filter { chapter.ages.contains($0.age) }.reduce(0) { $0 + $1.count }
            }
            outcomes[index] = Outcome(year: chapter.years.upperBound, age: chapter.ages.upperBound, low: end.p10,
                                      median: end.p50, high: end.p90, failures: failing, runs: results.runs)
        }
        return outcomes
    }

    var retirementAge: Int { chapters.retirementAge }

    /// The year work stops (the plan's first, when the age has passed).
    var retirementYear: Int {
        max(chapters.birthYear + chapters.retirementAge, start.year)
    }

    /// The index of the chapter `year` is in, or the nearest one.
    func chapterIndex(nearest year: Int) -> Int? {
        if let index = chapters.chapterIndex(containing: year) { return index }
        guard let first = chapters.chapters.first, let last = chapters.chapters.last else { return nil }
        return year < first.years.lowerBound ? 0 : year > last.years.upperBound ? chapters.chapters.count - 1 : nil
    }

    // MARK: Chapters in words

    /// "Employee", "Not working", "Retired, before pensions", "Retired,
    /// with pensions · spending 90%".
    func title(of chapter: PlanChapter) -> String {
        title(of: chapter.kind) + spendingSuffix(chapter, separator: " · spending ")
    }

    private func title(of kind: PlanChapter.Kind) -> String {
        switch kind {
        case .working(let phase):
            if plan.work.indices.contains(phase), let name = plan.work[phase].name { return name }
            return plan.work.count > 1 ? "Working, phase \(phase + 1)" : "Working"
        case .betweenWork:
            return "Not working"
        case .bridge:
            return hasPensions ? "Retired, before pensions" : "Retired"
        case .pensions:
            return plan.pensions.count == 1 ? "Retired, with a pension" : "Retired, with pensions"
        }
    }

    /// The strip's words when the title doesn't fit: "Work", "No work",
    /// "Retired", "Pensions 90%".
    func shortTitle(of chapter: PlanChapter) -> String {
        shortTitle(of: chapter.kind) + spendingSuffix(chapter, separator: " ")
    }

    private func shortTitle(of kind: PlanChapter.Kind) -> String {
        switch kind {
        case .working(let phase):
            if plan.work.indices.contains(phase), let name = plan.work[phase].name, name.count <= 12 { return name }
            return "Work"
        case .betweenWork:
            return "No work"
        case .bridge:
            return "Retired"
        case .pensions:
            return "Pensions"
        }
    }

    /// " · spending 90%" while retirement spending is a share of the plan's.
    private func spendingSuffix(_ chapter: PlanChapter, separator: String) -> String {
        guard let factor = chapter.spendingFactor, factor != 1 else { return "" }
        return separator + AmountFormat.percent(factor, digits: 0)
    }

    /// Whether any pension is ever paid.
    private var hasPensions: Bool {
        plan.pensions.contains { $0.fromAge != nil && ($0.perYear ?? 0) > 0 }
    }

    /// "2026–2028 · ages 38–40", "2031 · age 43".
    static func span(of chapter: PlanChapter) -> String {
        let years = chapter.years.count == 1 ? "\(chapter.years.lowerBound)"
            : "\(chapter.years.lowerBound)–\(chapter.years.upperBound)"
        let ages = chapter.ages.count == 1 ? "age \(chapter.ages.lowerBound)"
            : "ages \(chapter.ages.lowerBound)–\(chapter.ages.upperBound)"
        return "\(years) · \(ages)"
    }

    /// The span for VoiceOver: "2026 to 2028, ages 38 to 40".
    static func spokenSpan(of chapter: PlanChapter) -> String {
        let years = chapter.years.count == 1 ? "\(chapter.years.lowerBound)"
            : "\(chapter.years.lowerBound) to \(chapter.years.upperBound)"
        let ages = chapter.ages.count == 1 ? "age \(chapter.ages.lowerBound)"
            : "ages \(chapter.ages.lowerBound) to \(chapter.ages.upperBound)"
        return "\(years), \(ages)"
    }

    /// What pays for your life in the chapter, under its title.
    func subtitle(of chapter: PlanChapter) -> String {
        switch chapter.kind {
        case .working:
            return "Your work pays; what's left over is saved."
        case .betweenWork:
            return "No work: you spend what you do while working, from your savings."
        case .bridge:
            return hasPensions ? "You live on your savings until a pension starts." : "You live on your savings."
        case .pensions:
            return "Your pensions pay part; your savings the rest."
        }
    }

    /// The chapters as bands on the map: from the end of the year before
    /// each starts (the plan's start for the first) to the end of its last.
    var bands: [ChartBand] {
        chapters.chapters.enumerated().map { index, chapter in
            let from = index == 0 ? start : Self.lastDay(of: chapter.years.lowerBound - 1)
            let to = Self.lastDay(of: chapter.years.upperBound)
            return ChartBand(id: index, start: from.dateValue, end: to.dateValue, title: title(of: chapter),
                             shortTitle: shortTitle(of: chapter),
                             detail: "Chapter \(index + 1), " + Self.spokenSpan(of: chapter))
        }
    }

    /// The plan's years on the map: from its start to the end of its last chapter.
    var domain: ClosedRange<Date> {
        let end = chapters.chapters.last.map { Self.lastDay(of: $0.years.upperBound) } ?? start
        return start.dateValue...max(start.dateValue, end.dateValue)
    }

    /// 31 December of `year`.
    static func lastDay(of year: Int) -> CalendarDate {
        YearMonth(year: year, month: 12)?.lastDay ?? CalendarDate(year: year, month: 12, day: 31) ?? .today()
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
            return PlanWorkText.title(of: plan.work[index], index: index, of: plan.work.count)
        case .pension(let index):
            guard plan.pensions.indices.contains(index) else { return "Pension" }
            return PlanResultsMapping.pensionName(plan.pensions[index], index: index, of: plan.pensions.count)
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

    /// The account a contribution goes into, by name.
    func accountName(_ id: AccountID) -> String {
        accountNames[id] ?? id.rawValue
    }

    /// A target mix in words: "Equity 80% · bonds 20%", "Today's mix".
    func mixText(of item: PlanChapter.Item, locale: Locale = .current) -> String {
        if case .targetMixStep(let index) = item, plan.portfolio.targetMixByAge.indices.contains(index) {
            return PlanTargetMixModel.mixSummary(plan.portfolio.targetMixByAge[index].mix, locale: locale)
        }
        return PlanTargetMixModel.mixSummary(plan.portfolio.targetMix, locale: locale)
    }

    /// When work stops, in words, by where the age comes from: "Work stops
    /// at 55, in 2043.", "… the earliest age the plan found.", "Until the
    /// plan is calculated, its chapters assume work stops at 65."
    var retirementNote: String {
        let when = retirementYear <= start.year ? "Work stops at the start: you're past \(retirementAge)."
            : "Work stops at \(retirementAge), in \(retirementYear)."
        switch ageSource {
        case .chosen:
            return "The chapters and charts are for retiring at \(retirementAge), chosen in Results."
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

    /// A work phase from the chapter's first day until retirement.
    func newWorkPhase(in chapter: PlanChapter) -> WorkPhase {
        var phase = PlanEditing.newWorkPhase(in: plan, asOf: start)
        phase.from = max(start.adding(days: 1), Self.lastDay(of: chapter.years.lowerBound - 1).adding(days: 1))
        phase.until = .retirement
        return phase
    }

    /// A pension from the chapter's first age.
    func newPension(in chapter: PlanChapter) -> PlanPension {
        var pension = PlanEditing.newPension()
        pension.fromAge = chapter.ages.lowerBound
        return pension
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
    /// chapter.
    func newSpendingPhase(in chapter: PlanChapter) -> SpendingPhase {
        var phase = PlanEditing.newSpendingPhase(in: plan)
        phase.fromAge = chapter.ages.lowerBound + chapter.ages.count / 2
        return phase
    }
}
