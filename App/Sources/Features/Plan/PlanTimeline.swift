import Foundation
import Glance
import Model
import Planner
import Tracker

/// The plan as a strip of chapters (UI.md, "Plan"): a card per chapter, as
/// wide as its years, with the money through it on a scale the cards on
/// screen share, so the graph runs on from card to card; the ages along
/// each card's bottom, what happens in it, and where the money stands at its
/// end.
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
        var title: AmountSentence
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
        /// The chapter, for the age and the year at a point.
        let chapter: PlanChapter

        var id: Int { index }

        /// Its length in years.
        var years: Double {
            max(0, end.timeIntervalSince(start)) / PlanTimeline.secondsPerYear
        }

        /// The fan on `date`, each percentile between the fan's points.
        func fan(on date: Date) -> FanPoint? {
            fan.point(on: date)
        }

        /// The year a point on the card stands for: its start counts as the
        /// chapter's first year (``PlanChapter/year(on:)``).
        func year(on date: Date) -> Int {
            chapter.year(on: CalendarDate(date, in: .current))
        }

        /// The age reached during that year, as the start label, the ticks
        /// and the end label count them (``PlanChapter/age(on:)``).
        func age(on date: Date) -> Int {
            chapter.age(on: CalendarDate(date, in: .current))
        }
    }

    static let secondsPerYear = 365.25 * 86_400

    let cards: [Card]

    /// - Parameters:
    ///   - valuator: converts results calculated before the base currency
    ///     changed into `currency` (``PlanResults/portfolio(in:valuator:)``).
    ///   - milestones: the milestones ahead, each marked on the card it falls in.
    init(model: PlanChaptersModel, results: PlanResults?, valuator: Valuator, birthDate: CalendarDate,
         currency: CurrencyCode, milestones: [ProjectedMilestone] = [], locale: Locale = .current) {
        let words = PlanWords(currency: currency, locale: locale)
        // In the currency the strip is labelled in, as the milestones on it are;
        // without the rate the cards have no money, as before the first results.
        let points = results?.portfolio(in: currency, valuator: valuator) ?? []
        let all = model.chapters.chapters
        cards = all.indices.map { index in
            let chapter = all[index]
            let dates = model.dates(ofChapterAt: index)
            return Card(
                index: index, style: model.style(of: chapter), title: model.title(of: chapter),
                span: model.span(ofChapterAt: index), start: dates.lowerBound, end: dates.upperBound,
                fan: model.fan(ofChapterAt: index, in: points),
                startLabel: index == 0 ? "Now" : "\(chapter.ages.lowerBound)",
                endLabel: index == all.count - 1 ? "\(chapter.ages.upperBound)" : nil,
                ticks: model.ageTicks(inChapterAt: index, birthDate: birthDate)
                    .map { Tick(age: $0.age, date: $0.date) },
                events: model.events(inChapterAt: index, birthDate: birthDate).compactMap {
                    Self.event($0, plan: model.plan, words: words, model: model)
                },
                milestones: milestones.filter {
                    $0.date.dateValue > dates.lowerBound && $0.date.dateValue <= dates.upperBound
                },
                outcome: model.outcomes[index], chapter: chapter)
        }
    }

    /// The money scale fitted to the money between the screen's edges
    /// (UI.md, "Plan"): the median and the middle half of futures, so the
    /// outer band may run off the top or the bottom. `nil` before the plan
    /// has results, or without the rate to show them in.
    func scale(fitting window: PlanStripWindow) -> PlanStripScale? {
        PlanStripScale(values: window.values(of: cards) { card, plot in
            let bands = [\FanPoint.p25, \.p50, \.p75]
            return StripFit.Card(plot: plot, start: card.start, end: card.end, lines: bands.map { band in
                card.fan.map { StripFit.Point(date: $0.date, value: $0[keyPath: band]) }
            })
        })
    }

    /// An event on a chapter's card in words: "New car, 25.000 €" "in
    /// 2031", "Pension" "from 67".
    static func event(_ event: PlanChapterEvent, plan: PlanDocument, words: PlanWords,
                      model: PlanChaptersModel) -> Event? {
        switch event.kind {
        case .event(let index):
            guard plan.events.indices.contains(index) else { return nil }
            let planned = plan.events[index]
            let when = switch planned.timing {
            case .year(let year): "in \(year)"
            case .age(let age): "at \(age)"
            }
            let likely = planned.effectiveProbability < 1
                ? "\(words.percent(planned.effectiveProbability)) likely" : when
            return Event(id: event.id, date: event.date, kind: planned.amount < 0 ? .expense : .windfall,
                         title: "\(planned.name), \(words.amount(abs(planned.amount)))", detail: likely)
        case let .pension(index, age):
            return Event(id: event.id, date: event.date, kind: .pension,
                         title: AmountSentence(plan.pensionName(index)), detail: "from \(age)")
        case let .income(index, age):
            return Event(id: event.id, date: event.date, kind: .pension,
                         title: AmountSentence(plan.incomeName(index)), detail: "from \(age)")
        case .spendingPhase(let index):
            guard plan.spending.phases.indices.contains(index) else { return nil }
            let phase = plan.spending.phases[index]
            return Event(id: event.id, date: event.date, kind: .spending,
                         title: "You spend \(words.percent(phase.factor))", detail: "from \(phase.fromAge)")
        case let .saving(index, year):
            guard plan.contributions.indices.contains(index), let amount = plan.contributions[index].amount
            else { return nil }
            let account = model.accountName(plan.contributions[index].account)
            return Event(id: event.id, date: event.date, kind: .saving,
                         title: "Into \(account), \(words.amount(amount))", detail: "in \(year)")
        }
    }
}

/// Amounts and shares as the plan's sentences write them. Amounts are
/// ``AmountSentence``s, so they hide with the eye.
struct PlanWords: Hashable, Sendable {
    var currency: CurrencyCode
    var locale: Locale = .current

    /// "3.000 €".
    func amount(_ value: Decimal) -> AmountSentence {
        .amount(AmountFormat.amount(value, currency: currency, locale: locale))
    }

    /// With its sign: "+150.000 €" for a windfall, "−25.000 €" for an expense.
    func signedAmount(_ value: Decimal) -> AmountSentence {
        .amount(AmountFormat.signedAmount(value, currency: currency, locale: locale))
    }

    /// A yearly amount a month: "3.000 €" for 36.000 a year.
    func monthly(_ yearly: Decimal) -> AmountSentence {
        amount(yearly / 12)
    }

    /// A yearly amount a month, as a number for a bar.
    func monthlyValue(_ yearly: Decimal) -> Double {
        (yearly / 12).doubleValue
    }

    /// A monthly amount, as words: "240 €".
    func amount(monthly value: Double) -> AmountSentence {
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
    static func headline(_ headline: RetirementAnswer, locale: Locale = .current) -> String {
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
    ///   - age: the age it's for.
    ///   - isPlanned: whether that's the plan's own retirement age.
    ///   - bar: the plan's confidence level.
    static func reason(_ success: Double, endAge: Int, age: Int, isPlanned: Bool, bar: Double) -> String {
        let inTenths = abs(bar * 10 - (bar * 10).rounded()) < 1e-6
        func share(_ value: Double) -> String {
            inTenths ? "\(Self.tenths(value)) in 10" : "\(Int((value * 100 + 1e-9).rounded(.down))) in 100"
        }
        let sentence = (isPlanned ? "At \(age), as planned, " : "If you stop at \(age), ")
            + "\(share(success)) futures last to \(endAge)"
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
