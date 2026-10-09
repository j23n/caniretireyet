import Foundation
import Model
import Planner

/// A chapter in words (UI.md, "Plan"): what happens in it, its values
/// marked; what a month looks like; and, once calculated, what can go
/// wrong. Amounts are a month's, in today's money, from the plan's yearly ones.
struct PlanChapterStory: Hashable, Sendable {
    /// A piece of a sentence: words, or a value, which reads in bold.
    enum Run: Hashable, Sendable {
        case text(String)
        case value(String)
    }

    /// A month's money in a chapter, as one bar of parts.
    struct Bar: Hashable, Sendable {
        enum Role: Hashable, Sendable {
            /// Pay that's spent.
            case spent
            /// Pay that's saved.
            case saved
            /// Pay, all spent.
            case pay
            /// What comes from savings.
            case fromSavings
            /// The tax on what's sold.
            case tax
            /// What pensions pay.
            case pensions
            /// Pensions beyond what's spent.
            case spare
        }

        struct Segment: Hashable, Sendable {
            var value: Double
            var role: Role
        }

        var segments: [Segment]
        /// The words under it: "Pay 4.500 € · spend 3.000 €" on the left,
        /// "save 1.500 €" on the right in the colour of `trailingRole`.
        var leading: String
        var trailing: String
        var trailingRole: Role?
        /// What it shows, for VoiceOver.
        var label: String

        var total: Double { segments.reduce(0) { $0 + $1.value } }
    }

    var story: [Run]
    var bar: Bar?
    /// What can go wrong in it, once calculated: sentences.
    var risks: [String]
}

extension PlanChapterStory {
    /// The words for the chapter at `index` of `model`. `results` add the
    /// tax on what's sold to retirement's bar, what an uncertain windfall
    /// is worth to the answer, and where and when futures run out.
    init(chapterAt index: Int, in model: PlanChaptersModel, results: PlanResults?, words: PlanWords) {
        let chapter = model.chapters.chapters[index]
        story = Self.sentences(chapter, model: model, words: words, results: results).enumerated()
            .flatMap { offset, sentence in offset == 0 ? sentence : [Run.text(" ")] + sentence }
        bar = Self.bar(chapter, model: model, results: results, words: words)
        risks = Self.risks(chapter, details: results?.details)
    }

    // MARK: What happens

    static func sentences(_ chapter: PlanChapter, model: PlanChaptersModel, words: PlanWords,
                          results: PlanResults?) -> [[Run]] {
        let plan = model.plan
        var sentences: [[Run]] = []
        switch chapter.kind {
        case .working(let index) where plan.work.indices.contains(index):
            let phase = plan.work[index]
            if let net = phase.netIncome {
                let spend = plan.spending.working
                var sentence: [Run] = [.text("You take home "), .value(words.monthly(net)),
                                       .text(" a month and spend "), .value(words.monthly(spend))]
                let saving = net - spend
                if saving > 0 {
                    sentence.append(.text(", so you save about \(words.monthly(saving))."))
                } else if saving < 0 {
                    sentence.append(.text(", so about \(words.monthly(-saving)) a month comes from your savings."))
                } else {
                    sentence.append(.text(", so you save nothing."))
                }
                sentences.append(sentence)
            } else {
                let name = plan.workName(index)
                sentences.append([.text("Your pay after tax as "), .value(name), .text(" isn't set yet.")])
            }
        case .working:
            break
        case .betweenWork:
            sentences.append([.text("You don't work in these years, and spend "),
                              .value(words.monthly(plan.spending.working)),
                              .text(" a month from your savings.")])
        case .bridge, .pensions:
            if chapter.items.contains(.retirement) {
                var sentence: [Run] = [.text("You stop working ")]
                if plan.retirement.age == .earliest {
                    sentence += [.value("as early as you can"),
                                 .text(", at \(model.retirementAge) in \(model.retirementYear),")]
                } else {
                    sentence += [.value("at \(model.retirementAge)"),
                                 .text(", in \(model.retirementYear),")]
                }
                let otherIncome = otherIncomePaid(at: chapter.years.lowerBound, retirementYear: model.retirementYear,
                                                  plan: plan, birthYear: model.chapters.birthYear)
                let allFromSavings = chapter.kind == .bridge && otherIncome == 0
                sentence += [.text(" and spend "), .value(words.monthly(plan.spending.retired)),
                             .text(allFromSavings ? " a month, all from your savings." : " a month.")]
                sentences.append(sentence)
            }
            for case .spendingPhase(let index) in chapter.items where plan.spending.phases.indices.contains(index) {
                let phase = plan.spending.phases[index]
                sentences.append([.text("From \(phase.fromAge) you spend "),
                                  .value(words.percent(phase.factor)),
                                  .text(" of that: \(words.monthly(plan.spending.retired * phase.factor)) a month.")])
            }
            for case .pension(let index) in chapter.items where plan.pensions.indices.contains(index) {
                let pension = plan.pensions[index]
                let name = plan.pensionName(index)
                let amount = pension.perYear.map { words.monthly($0) } ?? "an amount to enter"
                let age = pension.fromAge.map { "\($0)" } ?? "an age to enter"
                sentences.append([.value(name), .text(" pays "), .value(amount), .text(" a month from "), .value(age),
                                  .text(".")])
            }
        }
        for case .income(let index) in chapter.items where plan.income.indices.contains(index) {
            sentences.append(incomeSentence(plan.income[index], name: plan.incomeName(index), words: words))
        }
        if !chapter.isRetired {
            for case .contribution(let index) in chapter.items + chapter.continuing
                where plan.contributions.indices.contains(index) && !plan.contributions[index].isOneOff {
                let contribution = plan.contributions[index]
                sentences.append([.value(words.monthly(contribution.perYear)), .text(" a month goes into "),
                                  .value(model.accountName(contribution.account)), .text(".")])
            }
        }
        for case .contribution(let index) in chapter.items
            where plan.contributions.indices.contains(index) && plan.contributions[index].isOneOff {
            let contribution = plan.contributions[index]
            sentences.append([.text("In \(contribution.year ?? chapter.years.lowerBound) you put "),
                              .value(words.amount(contribution.amount ?? 0)),
                              .text(" into "), .value(model.accountName(contribution.account)), .text(".")])
        }
        for case .event(let index) in chapter.items where plan.events.indices.contains(index) {
            sentences.append(eventSentence(plan.events[index], words: words,
                                           without: results?.details?.agesWithout.withoutWindfall(index),
                                           earliest: results?.headline.earliestAge))
        }
        if chapter.items.contains(.end) {
            sentences.append([.text("The plan ends at "), .value("\(plan.effectiveEndAge)"), .text(".")])
        }
        if sentences.isEmpty {
            sentences.append([.text(chapter.isRetired ? "Your pensions keep paying, and your savings cover the rest."
                                                      : "Your work keeps paying.")])
        }
        return sentences
    }

    /// "[Rent] pays [800 €] a month from 57 until 65.", "[Part-time] pays
    /// [1.500 €] a month from when you stop working until 60."
    static func incomeSentence(_ income: PlanIncome, name: String, words: PlanWords) -> [Run] {
        let amount = income.perYear.map { words.monthly($0) } ?? "an amount to enter"
        let from: String = switch income.from {
        case .age(let age): " a month from \(age)"
        case .retirement: " a month from when you stop working"
        case nil: " a month"
        }
        let until = income.untilAge.map { " until \($0)" } ?? ""
        return [.value(name), .text(" pays "), .value(amount), .text(from + until + ".")]
    }

    /// "In [2031] you spend [25.000 €] on [New car].", "At [62] you may
    /// receive [150.000 €] from [Inheritance], [80%] likely; without it,
    /// your earliest age would be 56."
    ///
    /// - Parameters:
    ///   - without: the earliest age if an uncertain windfall never came.
    ///   - earliest: the plan's own earliest age.
    static func eventSentence(_ event: PlanEvent, words: PlanWords, without: AgeWithout?, earliest: Int?) -> [Run] {
        var sentence: [Run]
        switch event.timing {
        case .year(let year): sentence = [.text("In "), .value("\(year)")]
        case .age(let age): sentence = [.text("At "), .value("\(age)")]
        }
        let likely = event.effectiveProbability < 1
        if event.amount < 0 {
            sentence += [.text(" you spend "), .value(words.amount(-event.amount)), .text(" on "), .value(event.name)]
        } else {
            sentence += [.text(likely ? " you may receive " : " you receive "), .value(words.amount(event.amount)),
                         .text(" from "), .value(event.name)]
        }
        if likely {
            sentence += [.text(", "), .value(words.percent(event.effectiveProbability)), .text(" likely")]
            if event.amount > 0, let without, earliest != nil {
                sentence.append(.text("; " + withoutSentence(without, earliest: earliest)))
            }
        }
        sentence.append(.text("."))
        return sentence
    }

    /// "without it, your earliest age would be 56", "without it, your
    /// earliest age stays 54", "without it, no age reaches your bar".
    static func withoutSentence(_ without: AgeWithout, earliest: Int?) -> String {
        guard let age = without.earliestAge else { return "without it, no age reaches your bar" }
        return age == earliest ? "without it, your earliest age stays \(age)"
            : "without it, your earliest age would be \(age)"
    }

    // MARK: What can go wrong

    /// Where and when futures run out in the chapter, from the results: the
    /// money you can draw running out before a locked account opens (in the
    /// bridge), and the age by which most of the chapter's failures happen.
    static func risks(_ chapter: PlanChapter, details: PlanResultDetails?) -> [String] {
        guard let details, chapter.isRetired else { return [] }
        var sentences: [String] = []
        if chapter.kind == .bridge {
            let locked = details.focus.bridges.filter { bridge in
                bridge.share > 0 && (bridge.accessibleFromAge.map { $0 > chapter.ages.lowerBound } ?? false)
            }
            if let bridge = locked.max(by: { $0.share < $1.share }), let age = bridge.accessibleFromAge {
                let perHundred = Int(wholeNumber: bridge.share * 100)
                let often = perHundred < 1 ? "fewer than 1 in 100 futures" : "\(perHundred) in 100 futures"
                sentences.append("In \(often), the money you can draw runs out before \(bridge.name) opens at "
                    + "\(age).")
            }
        }
        let failing = details.focus.failuresByAge.filter { chapter.ages.contains($0.age) && $0.count > 0 }
        let total = failing.reduce(0) { $0 + $1.count }
        if total > 0, chapter.ages.count > 4 {
            var counted = 0
            for failure in failing.sorted(by: { $0.age < $1.age }) {
                counted += failure.count
                if counted * 2 >= total {
                    if failure.age < chapter.ages.upperBound {
                        sentences.append("Most of the futures that run out here do so before \(failure.age + 1).")
                    }
                    break
                }
            }
        }
        return sentences
    }

    // MARK: Each month

    /// A month's money at the chapter's start: pay spent and saved while
    /// working; what comes from savings (and its tax) and what pensions pay
    /// once retired. `nil` without pay to show.
    static func bar(_ chapter: PlanChapter, model: PlanChaptersModel, results: PlanResults?,
                    words: PlanWords) -> Bar? {
        let plan = model.plan
        switch chapter.kind {
        case .working(let index):
            guard plan.work.indices.contains(index), let net = plan.work[index].netIncome else { return nil }
            let spend = plan.spending.working
            let pay = words.monthlyValue(net)
            let spent = words.monthlyValue(spend)
            if net >= spend {
                return Bar(segments: [Bar.Segment(value: spent, role: .spent), Bar.Segment(value: pay - spent, role: .saved)],
                           leading: "Pay \(words.monthly(net)) · spend \(words.monthly(spend))",
                           trailing: "save \(words.monthly(net - spend))", trailingRole: .saved,
                           label: "Pay of \(words.monthly(net)) a month: \(words.monthly(spend)) spent, "
                               + "\(words.monthly(net - spend)) saved")
            }
            return Bar(segments: [Bar.Segment(value: pay, role: .pay), Bar.Segment(value: spent - pay, role: .fromSavings)],
                       leading: "Spend \(words.monthly(spend)) · pay \(words.monthly(net))",
                       trailing: "\(words.monthly(spend - net)) from savings", trailingRole: .fromSavings,
                       label: "You spend \(words.monthly(spend)) a month: your pay covers \(words.monthly(net)), "
                           + "your savings \(words.monthly(spend - net))")
        case .betweenWork:
            let spend = plan.spending.working
            return Bar(segments: [Bar.Segment(value: words.monthlyValue(spend), role: .fromSavings)],
                       leading: "Spend \(words.monthly(spend))", trailing: "all from savings", trailingRole: .fromSavings,
                       label: "\(words.monthly(spend)) a month, all from your savings")
        case .bridge, .pensions:
            let spend = plan.spending.retired * (chapter.spendingFactor ?? 1)
            let paidPensions = pensionsPaid(at: chapter.years.lowerBound, plan: plan,
                                            birthYear: model.chapters.birthYear)
            let other = otherIncomePaid(at: chapter.years.lowerBound, retirementYear: model.retirementYear,
                                        plan: plan, birthYear: model.chapters.birthYear)
            // What pensions and other income pay, named by what's in it.
            let pensions = paidPensions + other
            let source = other == 0 ? "Pensions" : paidPensions == 0 ? "Other income" : "Income"
            let pays = other == 0 ? "pay" : "pays"
            if pensions == 0 {
                let fromSavings = words.monthlyValue(spend)
                let tax = monthlyTax(in: chapter, results: results)
                guard let tax, tax >= 1 else {
                    return Bar(segments: [Bar.Segment(value: fromSavings, role: .fromSavings)],
                               leading: "\(words.monthly(spend)) from savings", trailing: "", trailingRole: nil,
                               label: "\(words.monthly(spend)) a month from your savings")
                }
                return Bar(segments: [Bar.Segment(value: fromSavings, role: .fromSavings),
                                      Bar.Segment(value: tax, role: .tax)],
                           leading: "\(words.amount(monthly: fromSavings + tax)) from savings",
                           trailing: "\(words.amount(monthly: tax)) of it tax", trailingRole: .tax,
                           label: "\(words.amount(monthly: fromSavings + tax)) a month from your savings: "
                               + "\(words.monthly(spend)) to spend and \(words.amount(monthly: tax)) of tax")
            }
            let paid = words.monthlyValue(pensions)
            let spent = words.monthlyValue(spend)
            if pensions >= spend {
                return Bar(segments: [Bar.Segment(value: spent, role: .pensions),
                                      Bar.Segment(value: paid - spent, role: .spare)],
                           leading: "\(source) \(words.monthly(pensions))",
                           trailing: "\(words.monthly(pensions - spend)) to spare", trailingRole: .spare,
                           label: "\(source) \(pays) \(words.monthly(pensions)) a month, "
                               + "\(words.monthly(pensions - spend)) more than you spend")
            }
            return Bar(segments: [Bar.Segment(value: paid, role: .pensions),
                                  Bar.Segment(value: spent - paid, role: .fromSavings)],
                       leading: "\(source) \(words.monthly(pensions))",
                       trailing: "\(words.monthly(spend - pensions)) from savings", trailingRole: .fromSavings,
                       label: "Of the \(words.monthly(spend)) you spend a month, \(source.lowercased()) \(pays) "
                           + "\(words.monthly(pensions)) and your savings \(words.monthly(spend - pensions))")
        }
    }

    /// What pensions pay a year, after tax, by the start of `year`'s end:
    /// those whose age is reached by then.
    static func pensionsPaid(at year: Int, plan: PlanDocument, birthYear: Int) -> Decimal {
        plan.pensions.reduce(Decimal(0)) { total, pension in
            guard let age = pension.fromAge, let perYear = pension.perYear, birthYear + age <= year else { return total }
            return total + perYear
        }
    }

    /// What other income pays a year, after tax, at the end of `year`:
    /// what has started by then (from retirement, in the year work stops)
    /// and not stopped.
    static func otherIncomePaid(at year: Int, retirementYear: Int, plan: PlanDocument, birthYear: Int) -> Decimal {
        plan.income.reduce(Decimal(0)) { total, income in
            guard let from = income.from, let perYear = income.perYear else { return total }
            let first = from.age.map { birthYear + $0 } ?? retirementYear
            let stopped = income.untilAge.map { birthYear + $0 <= year } ?? false
            return first <= year && !stopped ? total + perYear : total
        }
    }

    /// The tax a month in the median run, in the chapter's first whole
    /// year of retirement; `nil` without results for it.
    static func monthlyTax(in chapter: PlanChapter, results: PlanResults?) -> Double? {
        guard let results else { return nil }
        let year = chapter.items.contains(.retirement) ? chapter.years.lowerBound + 1 : chapter.years.lowerBound
        guard chapter.years.contains(year) else { return nil }
        let taxes = results.taxes.filter { $0.year == year }
        guard !taxes.isEmpty else { return nil }
        return taxes.reduce(0) { $0 + $1.amount } / 12
    }

    // MARK: The target mix

    /// "80% in shares", or the mix in words without shares, or "as they are
    /// today" without a target mix.
    static func mixPhrase(_ item: PlanChapter.Item, plan: PlanDocument, words: PlanWords) -> String {
        var mix = plan.portfolio.targetMix
        if case .targetMixStep(let index) = item, plan.portfolio.targetMixByAge.indices.contains(index) {
            mix = plan.portfolio.targetMixByAge[index].mix
        }
        guard let mix, mix.total > 0 else { return "as they are today" }
        let equity = (mix.shares[.equity] ?? 0) / mix.total
        guard equity > 0 else { return PlanTargetMixModel.mixSummary(mix, locale: words.locale).lowercased() }
        return "\(words.percent(equity)) in shares"
    }
}
