import Foundation
import Model
import Planner

/// A value in the plan's words that can be changed where it reads (UI.md,
/// "Plan"): tapping it opens a small editor, or the item's own sheet.
enum PlanToken: Hashable, Sendable, Identifiable {
    case workIncome(Int)
    case workGrowth(Int)
    case workingSpending
    case retiredSpending
    case retirementAge
    case pensionAmount(Int)
    case pensionAge(Int)
    case contributionAmount(Int)
    case eventAmount(Int)
    case eventWhen(Int)
    case eventProbability(Int)
    case spendingPhase(Int)
    case endAge
    case flexibleSpending
    case inflation
    case equityReturn
    case bondsReturn
    case investmentTax
    case wealthTax
    case confidence
    /// The target mix and its changes with age, in a sheet of their own.
    case targetMix
    /// An item in its sheet: a work phase, a pension, a contribution, an event.
    case work(Int)
    case pension(Int)
    case contribution(Int)
    case event(Int)

    /// Letters, digits and hyphens, so it can be a link's address.
    var id: String {
        switch self {
        case .workIncome(let index): "work-income-\(index)"
        case .workGrowth(let index): "work-growth-\(index)"
        case .workingSpending: "working-spending"
        case .retiredSpending: "retired-spending"
        case .retirementAge: "retirement-age"
        case .pensionAmount(let index): "pension-amount-\(index)"
        case .pensionAge(let index): "pension-age-\(index)"
        case .contributionAmount(let index): "contribution-amount-\(index)"
        case .eventAmount(let index): "event-amount-\(index)"
        case .eventWhen(let index): "event-when-\(index)"
        case .eventProbability(let index): "event-probability-\(index)"
        case .spendingPhase(let index): "spending-phase-\(index)"
        case .endAge: "end-age"
        case .flexibleSpending: "flexible-spending"
        case .inflation: "inflation"
        case .equityReturn: "equity-return"
        case .bondsReturn: "bonds-return"
        case .investmentTax: "investment-tax"
        case .wealthTax: "wealth-tax"
        case .confidence: "confidence"
        case .targetMix: "target-mix"
        case .work(let index): "work-\(index)"
        case .pension(let index): "pension-\(index)"
        case .contribution(let index): "contribution-\(index)"
        case .event(let index): "event-\(index)"
        }
    }

    /// Whether it opens the item's sheet (or the target mix's) rather than a small editor.
    var opensSheet: Bool {
        switch self {
        case .work, .pension, .contribution, .event, .targetMix: true
        default: false
        }
    }
}

/// A chapter in words (UI.md, "Plan"): what happens in it, its values
/// marked; what a month looks like; and, once calculated, what can go
/// wrong. Amounts are a month's, in today's money, from the plan's yearly ones.
struct PlanChapterStory: Hashable, Sendable {
    /// A piece of a sentence: words, or a value to change.
    enum Run: Hashable, Sendable {
        case text(String)
        case token(String, PlanToken)
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
                          results: PlanResults? = nil) -> [[Run]] {
        let plan = model.plan
        var sentences: [[Run]] = []
        switch chapter.kind {
        case .working(let index) where plan.work.indices.contains(index):
            let phase = plan.work[index]
            if let net = phase.netIncome {
                let spend = plan.spending.working
                var sentence: [Run] = [.text("You take home "), .token(words.monthly(net), .workIncome(index)),
                                       .text(" a month and spend "), .token(words.monthly(spend), .workingSpending)]
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
                let name = PlanWorkText.title(of: phase, index: index, of: plan.work.count)
                sentences.append([.text("Your pay after tax as "), .token(name, .work(index)), .text(" isn't set yet.")])
            }
        case .working:
            break
        case .betweenWork:
            sentences.append([.text("You don't work in these years, and spend "),
                              .token(words.monthly(plan.spending.working), .workingSpending),
                              .text(" a month from your savings.")])
        case .bridge, .pensions:
            if chapter.items.contains(.retirement) {
                var sentence: [Run] = [.text("You stop working ")]
                if plan.retirement.age == .earliest {
                    sentence += [.token("as early as you can", .retirementAge),
                                 .text(", at \(model.retirementAge) in \(model.retirementYear),")]
                } else {
                    sentence += [.token("at \(model.retirementAge)", .retirementAge),
                                 .text(", in \(model.retirementYear),")]
                }
                sentence += [.text(" and spend "), .token(words.monthly(plan.spending.retired), .retiredSpending),
                             .text(chapter.kind == .bridge ? " a month, all from your savings." : " a month.")]
                sentences.append(sentence)
            }
            for case .spendingPhase(let index) in chapter.items where plan.spending.phases.indices.contains(index) {
                let phase = plan.spending.phases[index]
                sentences.append([.text("From \(phase.fromAge) you spend "),
                                  .token(words.percent(phase.factor), .spendingPhase(index)),
                                  .text(" of that: \(words.monthly(plan.spending.retired * phase.factor)) a month.")])
            }
            for case .pension(let index) in chapter.items where plan.pensions.indices.contains(index) {
                let pension = plan.pensions[index]
                let name = PlanResultsMapping.pensionName(pension, index: index, of: plan.pensions.count)
                let amount = pension.perYear.map { words.monthly($0) } ?? "an amount to enter"
                let age = pension.fromAge.map { "\($0)" } ?? "an age to enter"
                sentences.append([.token(name, .pension(index)), .text(" pays "), .token(amount, .pensionAmount(index)),
                                  .text(" a month from "), .token(age, .pensionAge(index)), .text(".")])
            }
        }
        if !chapter.isRetired {
            for case .contribution(let index) in chapter.items + chapter.continuing
                where plan.contributions.indices.contains(index) && !plan.contributions[index].isOneOff {
                let contribution = plan.contributions[index]
                sentences.append([.token(words.monthly(contribution.perYear), .contributionAmount(index)),
                                  .text(" a month goes into "),
                                  .token(model.accountName(contribution.account), .contribution(index)), .text(".")])
            }
        }
        for case .contribution(let index) in chapter.items
            where plan.contributions.indices.contains(index) && plan.contributions[index].isOneOff {
            let contribution = plan.contributions[index]
            sentences.append([.text("In \(contribution.year ?? chapter.years.lowerBound) you put "),
                              .token(words.amount(contribution.amount ?? 0), .contributionAmount(index)),
                              .text(" into "), .token(model.accountName(contribution.account), .contribution(index)),
                              .text(".")])
        }
        for case .event(let index) in chapter.items where plan.events.indices.contains(index) {
            sentences.append(eventSentence(plan.events[index], index: index, words: words,
                                           without: results?.details?.withoutWindfall(index),
                                           earliest: results?.headline.earliestAge))
        }
        if chapter.items.contains(.end) {
            sentences.append([.text("The plan ends at "), .token("\(plan.effectiveEndAge)", .endAge), .text(".")])
        }
        if sentences.isEmpty {
            sentences.append([.text(chapter.isRetired ? "Your pensions keep paying, and your savings cover the rest."
                                                      : "Your work keeps paying.")])
        }
        return sentences
    }

    /// "In [2031] you spend [25.000 €] on [New car].", "At [62] you may
    /// receive [150.000 €] from [Inheritance], [80%] likely; without it,
    /// your earliest age would be 56."
    ///
    /// - Parameters:
    ///   - without: the earliest age if an uncertain windfall never came.
    ///   - earliest: the plan's own earliest age.
    static func eventSentence(_ event: PlanEvent, index: Int, words: PlanWords, without: AgeWithout? = nil,
                              earliest: Int? = nil) -> [Run] {
        var sentence: [Run]
        switch event.timing {
        case .year(let year): sentence = [.text("In "), .token("\(year)", .eventWhen(index))]
        case .age(let age): sentence = [.text("At "), .token("\(age)", .eventWhen(index))]
        }
        let likely = event.effectiveProbability < 1
        if event.amount < 0 {
            sentence += [.text(" you spend "), .token(words.amount(-event.amount), .eventAmount(index)), .text(" on "),
                         .token(event.name, .event(index))]
        } else {
            sentence += [.text(likely ? " you may receive " : " you receive "),
                         .token(words.amount(event.amount), .eventAmount(index)), .text(" from "),
                         .token(event.name, .event(index))]
        }
        if likely {
            sentence += [.text(", "), .token(words.percent(event.effectiveProbability), .eventProbability(index)),
                         .text(" likely")]
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
            let pensions = pensionsPaid(at: chapter.years.lowerBound, plan: plan, birthYear: model.chapters.birthYear)
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
                           leading: "Pensions \(words.monthly(pensions))",
                           trailing: "\(words.monthly(pensions - spend)) to spare", trailingRole: .spare,
                           label: "Pensions pay \(words.monthly(pensions)) a month, \(words.monthly(pensions - spend)) "
                               + "more than you spend")
            }
            return Bar(segments: [Bar.Segment(value: paid, role: .pensions),
                                  Bar.Segment(value: spent - paid, role: .fromSavings)],
                       leading: "Pensions \(words.monthly(pensions))",
                       trailing: "\(words.monthly(spend - pensions)) from savings", trailingRole: .fromSavings,
                       label: "Of the \(words.monthly(spend)) you spend a month, pensions pay \(words.monthly(pensions)) "
                           + "and your savings \(words.monthly(spend - pensions))")
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
        guard let mix, PlanTargetMixModel.total(mix) > 0 else { return "as they are today" }
        let equity = (mix.shares[.equity] ?? 0) / PlanTargetMixModel.total(mix)
        guard equity > 0 else { return PlanTargetMixModel.mixSummary(mix, locale: words.locale).lowercased() }
        return "\(words.percent(equity)) in shares"
    }
}
