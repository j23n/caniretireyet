import Foundation
import Glance
import Model
import Planner

/// The plan as a strip of chapters (UI.md, "Plan"): a card per chapter, as
/// wide as its years, with the money through it on one scale every card
/// shares, so the graph runs on from card to card; the ages along each
/// card's bottom, what happens in it, and where the money stands at its end.
struct PlanTimeline {
    /// Something that happens on a date within a chapter, marked on its card.
    struct Event: Hashable, Sendable, Identifiable {
        enum Kind: Hashable, Sendable {
            case expense
            case windfall
            case pension
            case spending
            case saving
        }

        var id: String
        var date: Date
        var kind: Kind
        /// "New car, 25.000 €".
        var title: String
        /// "in 2031", "80% likely".
        var detail: String
    }

    /// An age marked along a card's bottom, on the birthday it's reached.
    struct Tick: Hashable, Sendable, Identifiable {
        var age: Int
        var date: Date
        var id: Int { age }
    }

    /// One chapter's card.
    struct Card: Identifiable {
        let index: Int
        let style: PlanChaptersModel.Style
        /// "Bridge".
        let title: String
        /// "55 to 67 · 2043 to 2055".
        let span: String
        /// From the end of the year before it (the plan's start, for the
        /// first) to the end of its last year.
        let start: Date
        let end: Date
        /// The fan at its start and at each year-end in it; empty without results.
        let fan: [FanPoint]
        /// "Now", or the age it starts at, under its left edge.
        let startLabel: String
        /// The age the plan ends at, under the last card's right edge.
        let endLabel: String?
        let ticks: [Tick]
        let events: [Event]
        /// The milestones the median future reaches in it (PROGRESS.md, "Milestones").
        let milestones: [ProjectedMilestone]
        let outcome: PlanChaptersModel.Outcome?
        /// Your birth date, for the age on a date.
        let birthDate: CalendarDate

        var id: Int { index }

        /// Its length in years.
        var years: Double {
            max(0, end.timeIntervalSince(start)) / PlanTimeline.secondsPerYear
        }

        /// The fan on `date`, each percentile between the fan's points.
        func fan(on date: Date) -> FanPoint? {
            guard let first = fan.first, let last = fan.last else { return nil }
            func point(_ value: (KeyPath<FanPoint, Double>) -> Double) -> FanPoint {
                FanPoint(date: date, p10: value(\.p10), p25: value(\.p25), p50: value(\.p50), p75: value(\.p75),
                         p90: value(\.p90))
            }
            if date <= first.date { return point { first[keyPath: $0] } }
            for (from, to) in zip(fan, fan.dropFirst()) where date <= to.date {
                let span = to.date.timeIntervalSince(from.date)
                let t = span > 0 ? date.timeIntervalSince(from.date) / span : 1
                return point { from[keyPath: $0] + (to[keyPath: $0] - from[keyPath: $0]) * t }
            }
            return point { last[keyPath: $0] }
        }

        /// Your age on `date`.
        func age(on date: Date) -> Int {
            birthDate.wholeYears(to: CalendarDate(date, in: .current))
        }
    }

    static let secondsPerYear = 365.25 * 86_400

    let cards: [Card]
    /// The money scale every card shares. It fits the medians and the
    /// middle half of futures, so the outer band may run off the top.
    /// `nil` before the plan has results.
    let scale: AmountScale?

    /// - Parameter milestones: the milestones ahead, each marked on the card it falls in.
    init(model: PlanChaptersModel, results: PlanResults?, birthDate: CalendarDate, currency: CurrencyCode,
         milestones: [ProjectedMilestone] = [], hidesAmounts: Bool = false, locale: Locale = .current) {
        let words = PlanWords(currency: currency, hidesAmounts: hidesAmounts, locale: locale)
        let points = results?.portfolio ?? []
        let slack: TimeInterval = 2 * 86_400
        let all = model.chapters.chapters
        cards = all.indices.map { index in
            let chapter = all[index]
            let dates = model.dates(ofChapterAt: index)
            let fan = points.filter { $0.date >= dates.lowerBound - slack && $0.date <= dates.upperBound + slack }
            // Ages on round numbers, kept clear of the edges' labels.
            let edge: TimeInterval = 120 * 86_400
            let ticks = chapter.ages.filter { $0 % 5 == 0 }.compactMap { age -> Tick? in
                let date = Self.birthday(birthDate, age: age)
                return date > dates.lowerBound + edge && date < dates.upperBound - edge ? Tick(age: age, date: date) : nil
            }
            return Card(
                index: index, style: model.style(of: chapter), title: model.title(of: chapter),
                span: model.span(ofChapterAt: index), start: dates.lowerBound, end: dates.upperBound, fan: fan,
                startLabel: index == 0 ? "Now" : "\(chapter.ages.lowerBound)",
                endLabel: index == all.count - 1 ? "\(chapter.ages.upperBound)" : nil, ticks: ticks,
                events: Self.events(in: chapter, plan: model.plan, birthDate: birthDate, dates: dates, words: words,
                                    model: model),
                milestones: milestones.filter {
                    $0.date.dateValue > dates.lowerBound && $0.date.dateValue <= dates.upperBound
                },
                outcome: model.outcomes[index], birthDate: birthDate)
        }
        if cards.contains(where: { !$0.fan.isEmpty }) {
            let values = cards.flatMap { card in card.fan.flatMap { point in [point.p25, point.p50, point.p75] } }
            scale = AmountScale(values: values + [0])
        } else {
            scale = nil
        }
    }

    /// What happens on a date in `chapter`: events, a pension or other income
    /// starting after its first year, a later phase of spending, a one-off
    /// saving. Dates fall inside the chapter's.
    static func events(in chapter: PlanChapter, plan: PlanDocument, birthDate: CalendarDate,
                       dates: ClosedRange<Date>, words: PlanWords, model: PlanChaptersModel) -> [Event] {
        let birthYear = birthDate.year
        func inside(_ date: Date) -> Date { min(max(date, dates.lowerBound), dates.upperBound) }
        var events: [Event] = []
        for item in chapter.items {
            switch item {
            case .event(let index) where plan.events.indices.contains(index):
                let event = plan.events[index]
                let date: Date
                let when: String
                switch event.timing {
                case .year(let year):
                    date = midYear(year)
                    when = "in \(year)"
                case .age(let age):
                    date = birthday(birthDate, age: age)
                    when = "at \(age)"
                }
                let likely = event.effectiveProbability < 1 ? "\(words.percent(event.effectiveProbability)) likely" : when
                events.append(Event(id: "event-\(index)", date: inside(date), kind: event.amount < 0 ? .expense : .windfall,
                                    title: "\(event.name), \(words.amount(abs(event.amount)))", detail: likely))
            case .pension(let index) where plan.pensions.indices.contains(index):
                let pension = plan.pensions[index]
                guard let age = pension.fromAge, birthYear + age > chapter.years.lowerBound else { continue }
                let name = plan.pensionName(index)
                events.append(Event(id: "pension-\(index)", date: inside(birthday(birthDate, age: age)), kind: .pension,
                                    title: name, detail: "from \(age)"))
            case .income(let index) where plan.income.indices.contains(index):
                let income = plan.income[index]
                guard let age = income.from?.age, birthYear + age > chapter.years.lowerBound else { continue }
                let name = plan.incomeName(index)
                events.append(Event(id: "income-\(index)", date: inside(birthday(birthDate, age: age)), kind: .pension,
                                    title: name, detail: "from \(age)"))
            case .spendingPhase(let index) where plan.spending.phases.indices.contains(index):
                let phase = plan.spending.phases[index]
                guard birthYear + phase.fromAge > chapter.years.lowerBound else { continue }
                events.append(Event(id: "spending-\(index)", date: inside(birthday(birthDate, age: phase.fromAge)),
                                    kind: .spending, title: "You spend \(words.percent(phase.factor))",
                                    detail: "from \(phase.fromAge)"))
            case .contribution(let index) where plan.contributions.indices.contains(index):
                let contribution = plan.contributions[index]
                guard contribution.isOneOff, let amount = contribution.amount else { continue }
                let year = contribution.year ?? chapter.years.lowerBound
                events.append(Event(id: "saving-\(index)", date: inside(midYear(year)), kind: .saving,
                                    title: "Into \(model.accountName(contribution.account)), \(words.amount(amount))",
                                    detail: "in \(year)"))
            default:
                continue
            }
        }
        return events.sorted { $0.date < $1.date }
    }

    /// The birthday at `age`, at noon.
    static func birthday(_ birthDate: CalendarDate, age: Int) -> Date {
        let day = CalendarDate(year: birthDate.year + age, month: birthDate.month, day: min(birthDate.day, 28))
        return day?.dateValue ?? midYear(birthDate.year + age)
    }

    /// 1 July of `year`, at noon.
    static func midYear(_ year: Int) -> Date {
        CalendarDate(year: year, month: 7, day: 1)?.dateValue ?? Date(timeIntervalSinceReferenceDate: 0)
    }
}

/// Amounts and shares as the plan's sentences write them, hidden with the
/// eye (`•••••`).
struct PlanWords: Hashable, Sendable {
    var currency: CurrencyCode
    var hidesAmounts = false
    var locale: Locale = .current

    /// "3.000 €".
    func amount(_ value: Decimal) -> String {
        hidesAmounts ? AmountFormat.hidden : AmountFormat.amount(value, currency: currency, locale: locale)
    }

    /// A yearly amount a month: "3.000 €" for 36.000 a year.
    func monthly(_ yearly: Decimal) -> String {
        amount(yearly / 12)
    }

    /// A yearly amount a month, as a number for a bar.
    func monthlyValue(_ yearly: Decimal) -> Double {
        (yearly / 12).doubleValue
    }

    /// A monthly amount, as words: "240 €".
    func amount(monthly value: Double) -> String {
        amount(Decimal(wholeNumber: value))
    }

    /// "90%", "4.5%": whole percentages without decimals, else to one decimal.
    func percent(_ share: Decimal) -> String {
        let scaled = share * 100
        return AmountFormat.percent(share, digits: scaled.rounded(scale: 0) == scaled ? 0 : 1, locale: locale)
    }
}

/// The plan's answer and the strip's words (UI.md, "Plan").
enum PlanTimelineText {
    /// "Not yet. Stop at 54, in March 2042.", "Yes. You could stop working today."
    static func headline(_ headline: PlanHeadline, locale: Locale = .current) -> String {
        if headline.canRetireNow { return "Yes. You could stop working today." }
        guard let age = headline.earliestAge else { return "Not yet. No age reaches your bar yet." }
        guard let date = headline.earliestDate else { return "Not yet. Stop at \(age)." }
        return "Not yet. Stop at \(age), in \(GlanceText.monthAndYear(date, locale: locale))."
    }

    /// How many futures in 10 last, at a chance of `success`: rounded down,
    /// so a plan short of a bar in tenths never reads as reaching it.
    static func tenths(_ success: Double) -> Int {
        min(10, max(0, Int((success * 10 + 1e-9).rounded(.down))))
    }

    /// Why the answer is what it is, at the age the plan is shown for
    /// (UI.md, "Plan"): "At 55, as planned, 4 in 10 futures last to 95.
    /// Your bar is 9 in 10.", "If you stop at 58, 9 in 10 futures last to
    /// 95. That meets your bar." In hundredths when the bar isn't a whole
    /// number of tenths (95 in 100).
    ///
    /// - Parameters:
    ///   - age: the age it's for; `nil` leaves it out.
    ///   - isPlanned: whether that's the plan's own retirement age.
    ///   - bar: the plan's confidence level.
    static func reason(_ success: Double, endAge: Int, age: Int?, isPlanned: Bool, bar: Double) -> String {
        let inTenths = abs(bar * 10 - (bar * 10).rounded()) < 1e-6
        func share(_ value: Double) -> String {
            inTenths ? "\(Self.tenths(value)) in 10" : "\(Int((value * 100 + 1e-9).rounded(.down))) in 100"
        }
        let futures = "\(share(success)) futures last to \(endAge)"
        let sentence: String = if let age {
            (isPlanned ? "At \(age), as planned, " : "If you stop at \(age), ") + futures
        } else {
            futures.prefix(1).uppercased() + futures.dropFirst()
        }
        return success >= bar ? "\(sentence). That meets your bar." : "\(sentence). Your bar is \(share(bar))."
    }

    /// "No futures run out here", "4 in 100 futures run out here", "Fewer
    /// than 1 in 100 run out here".
    static func runsOut(_ share: Double) -> String {
        guard share > 0 else { return "No futures run out here" }
        let perHundred = Int((share * 100).rounded())
        return perHundred < 1 ? "Fewer than 1 in 100 run out here" : "\(perHundred) in 100 futures run out here"
    }

    /// "Your life in four chapters", "Your life in 12 chapters".
    static func chapters(_ count: Int) -> String {
        let words = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        if count == 1 { return "Your life in one chapter" }
        return "Your life in \(words.indices.contains(count - 1) ? words[count - 1] : String(count)) chapters"
    }
}
