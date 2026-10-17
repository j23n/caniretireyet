import Foundation
import Model
import Tracker

/// The chapters of the plan on screen (UI.md, "The plan"; PLANNER.md,
/// "Chapters"): its years cut where what pays for your life changes, each
/// input in the chapter it starts in, and, once the plan has results, where
/// the money stands at the end of each.
///
/// The chapters follow the plan as shown, so an edit moves them at once.
/// They're cut at the retirement age the charts are for (``AgeSource``).
/// Where the money stands comes from the results shown, which can be out of
/// date; the views dim it then, as they dim the results.
public struct PlanChaptersModel: Sendable {
    /// Where the retirement age the chapters are cut at comes from, first
    /// match first.
    public enum AgeSource: Hashable, Sendable {
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
    public struct Outcome: Hashable, Sendable {
        /// The age reached in the chapter's last year.
        public var age: Int
        /// Plan assets at that year's end, in today's money: 1 in 10
        /// futures below `low`, half below `median`, 1 in 10 above `high`.
        public var low: Double
        public var median: Double
        public var high: Double
        /// The share of futures whose money runs out during the chapter.
        public var failureShare: Double

        public init(age: Int, low: Double, median: Double, high: Double, failureShare: Double) {
            self.age = age
            self.low = low
            self.median = median
            self.high = high
            self.failureShare = failureShare
        }
    }

    public let plan: PlanDocument
    public let chapters: PlanChapters
    public let ageSource: AgeSource
    /// The day the plan starts from: the latest check-in, or its own start date.
    public let start: CalendarDate
    /// By chapter index; empty without results.
    public let outcomes: [Int: Outcome]
    /// The accounts' names, for contributions.
    public let accountNames: [AccountID: String]

    /// The age a plan asking for the earliest age is cut at before it has
    /// found one.
    public static let assumedAge = 65

    /// The chapters of `plan` as shown; `nil` without a birth date.
    ///
    /// - Parameters:
    ///   - results: The results shown, for the outcomes.
    ///   - chosenAge: An age chosen for the charts (the plan screen's focus age).
    ///   - whatIfAge: The what-if's retirement age, while one is in use.
    ///   - recordedAge: The earliest age recorded at the last check-in.
    public init?(plan: PlanDocument, library: Library, results: PlanResults?,
                 chosenAge: Int? = nil, whatIfAge: Int? = nil, recordedAge: Int? = nil,
                 today: CalendarDate = .today()) {
        guard let birthDate = library.settings.person?.birthDate else { return nil }
        let start = plan.startDate(in: library, today: today)
        let resultsAge = results?.details.focus.age ?? results?.headline.earliestAge
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
    public static func retirementAge(plan: PlanDocument, chosenAge: Int?, whatIfAge: Int?, resultsAge: Int?,
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
    public static func outcomes(of chapters: PlanChapters, results: PlanResults) -> [Int: Outcome] {
        var yearEnds: [Int: FanPoint] = [:]
        for point in results.portfolio {
            let date = CalendarDate(point.date, in: .current)
            if date.month == 12, date.day == 31 { yearEnds[date.year] = point }
        }
        let failures = results.details.focus.failuresByAge
        let runs = Double(results.runs)
        var outcomes: [Int: Outcome] = [:]
        for (index, chapter) in chapters.chapters.enumerated() {
            guard let end = yearEnds[chapter.years.upperBound] else { continue }
            let failing = failures.filter { chapter.ages.contains($0.age) }.reduce(0) { $0 + $1.count }
            outcomes[index] = Outcome(age: chapter.ages.upperBound, low: end.p10, median: end.p50, high: end.p90,
                                      failureShare: runs > 0 ? Double(failing) / runs : 0)
        }
        return outcomes
    }

    public var retirementAge: Int { chapters.retirementAge }

    /// The year work stops (the plan's first, when the age has passed).
    public var retirementYear: Int { chapters.retirementYear }

    /// The index of the chapter `year` is in, or the nearest one.
    public func chapterIndex(nearest year: Int) -> Int? {
        if let index = chapters.chapterIndex(containing: year) { return index }
        guard let first = chapters.chapters.first, let last = chapters.chapters.last else { return nil }
        return year < first.years.lowerBound ? 0 : year > last.years.upperBound ? chapters.chapters.count - 1 : nil
    }

    // MARK: What a chapter is

    /// What a chapter is, for its name and colour on the strip.
    public enum Style: Hashable, Sendable {
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

    public func style(of chapter: PlanChapter) -> Style {
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

    /// When a chapter runs on a time axis: from the end of the year before
    /// it (the plan's start, for the first) to the end of its last year.
    public func dates(ofChapterAt index: Int) -> ClosedRange<Date> {
        let all = chapters.chapters
        guard all.indices.contains(index) else { return start.dateValue...start.dateValue }
        let chapter = all[index]
        let from = index == 0 ? start : Self.lastDay(of: chapter.years.lowerBound - 1)
        let to = Self.lastDay(of: chapter.years.upperBound)
        return from.dateValue...max(from.dateValue, to.dateValue)
    }

    /// The first day of a work phase added in `chapter`: the chapter's first
    /// day, unless a phase starts then; else 1 January of its middle year
    /// (1 July in a chapter of one year), which splits the chapter's phase.
    /// Two phases starting the same day overlap, which
    /// ``PlanDocument/work(adding:)`` can't undo.
    public func newWorkPhaseStart(in chapter: PlanChapter) -> CalendarDate {
        let first = max(start.adding(days: 1), Self.lastDay(of: chapter.years.lowerBound - 1).adding(days: 1))
        let starts = Set(plan.work.map(\.from))
        guard starts.contains(first) else { return first }
        let years = chapter.years
        let split = years.count > 1
            ? Self.lastDay(of: years.lowerBound + years.count / 2 - 1).adding(days: 1)
            : CalendarDate(year: years.lowerBound, month: 7, day: 1) ?? first
        return split > first && !starts.contains(split) ? split : first.adding(days: 1)
    }

    /// 31 December of `year`.
    public static func lastDay(of year: Int) -> CalendarDate {
        CalendarDate(year: year, month: 12, day: 31) ?? .today()
    }

    /// Whether any pension is ever paid.
    public var hasPensions: Bool {
        plan.pensions.contains { $0.fromAge != nil && ($0.perYear ?? 0) > 0 }
    }

    /// The chapter's length in years, to the nearest half year: 16.5.
    public func halfYears(ofChapterAt index: Int) -> Double {
        let dates = self.dates(ofChapterAt: index)
        let years = dates.upperBound.timeIntervalSince(dates.lowerBound) / (365.25 * 86_400)
        return (years * 2).rounded() / 2
    }

    /// The account a contribution goes into, by name.
    public func accountName(_ id: AccountID) -> String {
        accountNames[id] ?? id.rawValue
    }
}
