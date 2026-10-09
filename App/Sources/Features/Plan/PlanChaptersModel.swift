import Foundation
import Model
import Planner

/// The chapters of the plan on screen (UI.md, "The plan"; PLANNER.md,
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
        let start = plan.startDate(in: library, today: today)
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
    var retirementYear: Int { chapters.retirementYear }

    /// The index of the chapter `year` is in, or the nearest one.
    func chapterIndex(nearest year: Int) -> Int? {
        if let index = chapters.chapterIndex(containing: year) { return index }
        guard let first = chapters.chapters.first, let last = chapters.chapters.last else { return nil }
        return year < first.years.lowerBound ? 0 : year > last.years.upperBound ? chapters.chapters.count - 1 : nil
    }

    // MARK: Chapters in words

    /// What a chapter is, for its name and colour on the strip.
    enum Style: Hashable, Sendable {
        /// A work phase pays.
        case working
        /// Before retirement, without work.
        case notWorking
        /// Retired, before a pension is paid (from the year work stops).
        case bridge
        /// Retired, from the year a pension starts.
        case pensions
        /// Retired, spending a share of what the plan spends.
        case later
    }

    func style(of chapter: PlanChapter) -> Style {
        switch chapter.kind {
        case .working:
            return .working
        case .betweenWork:
            return .notWorking
        case .bridge:
            return chapter.items.contains(.retirement) || (chapter.spendingFactor ?? 1) == 1 ? .bridge : .later
        case .pensions:
            let startsPension = chapter.items.contains { item in
                if case .pension = item { return true }
                return false
            }
            return startsPension || (chapter.spendingFactor ?? 1) == 1 ? .pensions : .later
        }
    }

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

    /// "16½ years", to the nearest half year.
    func length(ofChapterAt index: Int) -> String {
        let dates = self.dates(ofChapterAt: index)
        let years = dates.upperBound.timeIntervalSince(dates.lowerBound) / (365.25 * 86_400)
        let halves = Int((years * 2).rounded())
        let whole = halves / 2
        let half = halves % 2 == 1 ? "½" : ""
        if whole == 0 { return half.isEmpty ? "Under half a year" : "½ year" }
        return "\(whole)\(half) " + (whole == 1 && half.isEmpty ? "year" : "years")
    }

    /// Whether any pension is ever paid.
    private var hasPensions: Bool {
        plan.pensions.contains { $0.fromAge != nil && ($0.perYear ?? 0) > 0 }
    }

    /// When a chapter runs on a time axis: from the end of the year before
    /// it (the plan's start, for the first) to the end of its last year.
    func dates(ofChapterAt index: Int) -> ClosedRange<Date> {
        let all = chapters.chapters
        guard all.indices.contains(index) else { return start.dateValue...start.dateValue }
        let chapter = all[index]
        let from = index == 0 ? start : Self.lastDay(of: chapter.years.lowerBound - 1)
        let to = Self.lastDay(of: chapter.years.upperBound)
        return from.dateValue...max(from.dateValue, to.dateValue)
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

    /// The account a contribution goes into, by name.
    func accountName(_ id: AccountID) -> String {
        accountNames[id] ?? id.rawValue
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
            return "The chapters and charts are for retiring at \(retirementAge), chosen on the chance-by-age chart."
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
    /// chapter.
    func newSpendingPhase(in chapter: PlanChapter) -> SpendingPhase {
        var phase = PlanEditing.newSpendingPhase(in: plan)
        phase.fromAge = chapter.ages.lowerBound + chapter.ages.count / 2
        return phase
    }
}
