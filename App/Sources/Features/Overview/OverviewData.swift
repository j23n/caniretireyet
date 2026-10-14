import Foundation
import Glance
import Model
import Planner
import Tracker

// The Overview's words and what needs attention. Its numbers come from the
// package: the history chart (Tracker's `HistoryChartData`), the answer
// (the Planner's `LatestAnswer`) and *On track?* (the Planner's
// `PlanOnTrack`). The views in this folder only lay them out.

extension HistoryRange {
    /// The label on the picker.
    var title: String { rawValue }

    /// How VoiceOver reads the label.
    var spokenTitle: String {
        switch self {
        case .oneYear: "1 year"
        case .threeYears: "3 years"
        case .fiveYears: "5 years"
        case .all: "All"
        }
    }
}

/// What the Overview's allocation bars group by (UI.md, "Allocation"),
/// remembered by its raw value.
extension BreakdownDimension {
    var title: String {
        switch self {
        case .assetClass: "Asset class"
        case .accountGroup: "Account group"
        case .currency: "Currency"
        case .institution: "Institution"
        case .liquidity: "Liquid vs locked"
        }
    }

    /// At most this many bars; the rest fold into "Other".
    var limit: Int? {
        switch self {
        case .institution, .currency: 7
        default: nil
        }
    }
}

// MARK: - Hero and change

// The hero number and the *Net worth* tile, net worth today with the change
// between the last two check-ins and since the end of last year, are
// Glance's `NetWorthGlance`, as the widgets have it. *This year* splits that
// change since the end of last year into markets, new money and other with
// Tracker's `Valuator.changeThisYear(asOf:)`, from the same 31 December
// (tested in TrackerTests, and against the hero in GlanceTests). The answer's
// headline counts the time to go with Glance's `RetirementCountdown`, and its
// ring shows Glance's `ReadinessFigure` (GlanceTests).

// MARK: - This year

/// The words of the Overview's *This year* card (UI.md, "This year").
enum OverviewYearText {
    /// "Savings rate 17%: you saved 1.956 € of the 11.525 € that came in
    /// since 30 Jun, 1.325 € of it paid into pensions, and spent 9.569 €."
    /// With tax recorded, from a current account or a tax pot, what came in
    /// is after it: "… that came in since 30 Jun after 3.000 € in tax, …".
    /// When more was saved than came in, it says some income may not be
    /// recorded. The amounts hide with the eye; the rate stays. `nil` when
    /// nothing came in.
    static func savings(_ savings: SavingsRate, today: CalendarDate, locale: Locale) -> AmountSentence? {
        guard let rate = savings.rate else { return nil }
        let percent = AmountFormat.percent(rate, digits: 0, locale: locale)
        let since = AmountFormat.shortDate(savings.from, relativeTo: today, locale: locale)
        let currency = savings.moneyInOut.currency
        func amount(_ value: Decimal) -> AmountSentence {
            .amount(AmountFormat.amount(value, currency: currency, locale: locale))
        }
        var text: AmountSentence = "Savings rate \(percent): you saved \(amount(savings.saved)) of the "
        text += "\(amount(savings.income)) that came in since \(since)"
        if savings.tax > 0 {
            text += " after \(amount(savings.tax)) in tax"
        }
        if savings.pensionContributions > 0 {
            text += ", \(amount(savings.pensionContributions)) of it paid into pensions"
        }
        guard savings.spent >= 0 else {
            return text + ". More was saved than came in: some income may not be recorded."
        }
        return text + ", and spent \(amount(savings.spent))."
    }
}

// MARK: - Can I retire yet?

/// The main plan's answer in the Overview's header (UI.md, "Can I retire
/// yet?"): the headline, what its ⓘ says, and what VoiceOver reads.
struct OverviewAnswerText {
    var headline: RetirementAnswer
    /// When the earliest age is reached: the headline's date, or for an
    /// answer recorded at a check-in the birthday of that age; `nil`
    /// without a birth date.
    var earliestDate: CalendarDate?
    /// The day the Overview reports on.
    var today: CalendarDate
    var locale: Locale = .current

    /// How long until the earliest age (Glance's ``RetirementCountdown``);
    /// `nil` when you could retire today, no age works out, there's no date,
    /// or its month has passed.
    var countdown: RetirementCountdown? {
        guard !headline.canRetireNow, headline.earliestAge != nil, let earliestDate else { return nil }
        return RetirementCountdown(from: today, to: earliestDate)
    }

    /// "In 15 years", "In 18 months", "Yes", "Not yet" when no age works
    /// out, or "At 54" without a time to go.
    var title: String {
        if headline.canRetireNow { return "Yes" }
        guard let age = headline.earliestAge else { return "Not yet" }
        return countdown?.headlineText ?? "At \(age)"
    }

    /// "At 54, in March 2042, in 9 of 10 futures"; "You could retire today,
    /// in at least 9 of 10 futures"; "No age works in 9 of 10 futures yet".
    var when: String {
        whenWords.capitalizedFirst
    }

    private var whenWords: String {
        let futures = GlanceText.futures(headline.confidence)
        if headline.canRetireNow { return "you could retire today, in at least \(futures) futures" }
        guard let age = headline.earliestAge else { return "no age works in \(futures) futures yet" }
        var parts = ["at \(age)"]
        if let earliestDate {
            parts.append("in \(GlanceText.monthAndYear(earliestDate, locale: locale))")
        }
        parts.append("in \(futures) futures")
        return parts.joined(separator: ", ")
    }

    /// The line under the headline in the *Can I retire yet?* tile: when
    /// ("At 54 · March 2042"; "March 2042" when the headline is "At 54";
    /// "Today" when you could retire today, "No age works" when none does).
    /// `nil` when the headline already says all of it.
    var whenLine: String? {
        if headline.canRetireNow { return "Today" }
        guard let age = headline.earliestAge else { return "No age works" }
        var parts: [String] = []
        if countdown != nil { parts.append("At \(age)") }
        if let earliestDate { parts.append(GlanceText.monthAndYear(earliestDate, locale: locale)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// How sure, under ``whenLine``: "in 9 of 10 futures", "in at least 9 of
    /// 10 futures" when you could retire today, "in 9 of 10 futures yet"
    /// when no age works out.
    var futuresLine: String {
        let futures = GlanceText.futures(headline.confidence)
        if headline.canRetireNow { return "in at least \(futures) futures" }
        return headline.earliestAge == nil ? "in \(futures) futures yet" : "in \(futures) futures"
    }

    /// What the headline and the ring say to VoiceOver: "Not yet. In about
    /// 15 years, at 54, in March 2042, in 9 of 10 futures. 58% of what
    /// you'd need to retire today."
    var spoken: String {
        var text: String
        if headline.canRetireNow {
            text = "Yes. \(when)."
        } else if let countdown {
            text = "Not yet. \(countdown.spokenHeadlineText), \(whenWords)."
        } else {
            text = "Not yet. \(when)."
        }
        if let readiness = PlanResultsText.readiness(headline, locale: locale) {
            text += " \(readiness)."
        }
        return text
    }

    /// The ⓘ's paragraphs: when and how sure, the readiness and what it
    /// compares, that the results are out of date, and the disclaimer.
    func explanation(isOutOfDate: Bool) -> [String] {
        var paragraphs = [when + "."]
        if let readiness = PlanResultsText.readiness(headline, locale: locale) {
            paragraphs.append(readiness + ". "
                + PlanResultsText.readinessExplanation(confidence: headline.confidence, locale: locale))
        }
        if isOutOfDate {
            paragraphs.append("Calculated before your latest changes.")
        }
        paragraphs.append(AboutText.disclaimer)
        return paragraphs
    }
}

// MARK: - On track?

/// The Overview's *On track?* (UI.md, "On track?") in words: the Planner's
/// `PlanOnTrack`, with its baseline named as Progress's years name it.
struct OverviewOnTrack {
    /// Where the latest check-in stands; `nil` without a baseline to
    /// measure it against ("Not measured yet").
    var position: PlanBaselineComparison.Position?
    /// What the baseline is in words, as Progress's years name it:
    /// "January", "October", "your 2021 plan".
    var expectation = "January"
    /// The coast age (PLANNER.md, "Ages without") while it's at or under
    /// the age the first pension starts, as Progress's Milestones card has
    /// it (``MilestoneLadder/isPastCoastPoint(_:plan:)``); `nil` otherwise,
    /// and when you could retire today.
    var coastAge: Int?

    /// - Parameter results: the main plan's latest results, for the coast
    ///   age; without them, the one the latest check-in recorded.
    init(plan: PlanDocument, library: Library, valuator: Valuator, asOf: CalendarDate, results: PlanResults?,
         canRetireNow: Bool, locale: Locale = .current) {
        let onTrack = PlanOnTrack(plan: plan, library: library, valuator: valuator, asOf: asOf, results: results,
                                  canRetireNow: canRetireNow)
        position = onTrack.position
        if let entry = onTrack.baseline, let checkIn = onTrack.checkIn {
            expectation = PlanProgressYear.expectation(entry.baseline, year: checkIn.year, locale: locale)
        }
        coastAge = onTrack.coastAge
    }

    /// "Past the coast point: 63 without saving".
    static func coastLine(_ age: Int) -> String {
        "Past the coast point: \(age) without saving"
    }

    /// The coast point line for VoiceOver, in full.
    static func spokenCoastLine(_ age: Int) -> String {
        "You're past the coast point: saving nothing more, you could still retire at \(age)."
    }
}

// MARK: - Needs attention

/// One thing on the Overview that needs you (UI.md, "Needs attention").
struct OverviewAttentionItem: Hashable, Sendable, Identifiable {
    /// Where tapping the item goes.
    enum Target: Hashable, Sendable {
        case account(AccountID)
        case instrument(InstrumentID)
        case checkIn
        case plan
        /// *Fill In Past Prices* (Instruments), for past prices and rates.
        case fillPastPrices
    }

    var id: String
    var systemImage: String
    var title: String
    var detail: String
    var target: Target
}

/// Finds what needs attention in the library's data: stale accounts,
/// accounts with problems in their trades, missing and outdated prices,
/// missing exchange rates, and past prices and rates the net-worth history
/// is missing (with *Fill In Past Prices*). The screen adds the library's
/// own state (sync conflicts, save errors) and plan warnings.
enum OverviewAttention {
    static func items(library: Library, valuator: Valuator, on today: CalendarDate, stalenessThreshold: Int,
                      locale: Locale = .current) -> [OverviewAttentionItem] {
        func accountName(_ id: AccountID) -> String { library.accounts[id]?.name ?? id.rawValue }
        func instrumentName(_ id: InstrumentID) -> String { library.instruments[id]?.name ?? id.rawValue }

        var items: [OverviewAttentionItem] = []

        // An account that holds nothing has nothing to check in (AccountStaleness).
        for stale in valuator.staleAccounts(on: today, threshold: stalenessThreshold, in: .netWorth)
        where valuator.emptySince(of: stale.account, on: today) == nil {
            let name = accountName(stale.account)
            if let last = stale.lastValuation {
                items.append(OverviewAttentionItem(
                    id: "stale.\(stale.account)", systemImage: "clock.badge.exclamationmark",
                    title: "\(name): last value \(GlanceText.month(last, relativeTo: today, locale: locale))",
                    detail: "Update it in your next check-in", target: .account(stale.account)))
            } else {
                items.append(OverviewAttentionItem(
                    id: "stale.\(stale.account)", systemImage: "clock.badge.exclamationmark",
                    title: "\(name): no value yet", detail: "Add its first value in a check-in",
                    target: .account(stale.account)))
            }
        }
        items += tradeProblems(library: library, valuator: valuator, locale: locale)

        // Today's missing prices, then rates; an account without a value is stale above.
        let gaps = MissingValues(valuator.netWorth(on: today).accounts)?.gaps ?? []
        var missingPrices: Set<InstrumentID> = []
        for gap in gaps {
            guard case .price(let instrument) = gap.item else { continue }
            missingPrices.insert(instrument)
            items.append(OverviewAttentionItem(
                id: "price.\(instrument)", systemImage: "tag.slash",
                title: "No price for \(instrumentName(instrument))",
                detail: "\(Wording.names(gap.accounts.map(accountName))) "
                    + "\(gap.accounts.count == 1 ? "leaves" : "leave") it out of your net worth. Type in a price at "
                    + "your next check-in.",
                target: .instrument(instrument)))
        }
        for gap in gaps {
            guard case .rate(let from, let to) = gap.item else { continue }
            items.append(OverviewAttentionItem(
                id: "fx.\(from)-\(to)", systemImage: "arrow.left.arrow.right",
                title: "No \(from) to \(to) exchange rate",
                detail: "\(Wording.names(gap.accounts.map(accountName))) "
                    + "\(gap.accounts.count == 1 ? "isn't" : "aren't") fully counted. Type in a rate at your next "
                    + "check-in.",
                target: .checkIn))
        }

        for (instrument, date) in valuator.outdatedPrices(in: library, asOf: today)
        where !missingPrices.contains(instrument) {
            items.append(OverviewAttentionItem(
                id: "outdated.\(instrument)", systemImage: "tag",
                title: "\(instrumentName(instrument)): last price \(AmountFormat.shortDate(date, locale: locale))",
                detail: "Older than the account's latest value. Fetch or type in a price at your next check-in.",
                target: .instrument(instrument)))
        }
        items += pastGaps(library: library, valuator: valuator, asOf: today, locale: locale)
        return items
    }

    /// An item per account whose trades have problems, opening the account:
    /// "Directa: 2 problems with trades", then "More sold than held · VWCE
    /// differs from the statement. Open the account to fix them." The
    /// problems are the ones the account's page lists
    /// (``TradeIssueNote/notes(for:library:valuator:locale:)``): more sold
    /// than held, an opening without a cost, a statement that differs from
    /// the trades, and the rest. Sorted by account name.
    static func tradeProblems(library: Library, valuator: Valuator,
                              locale: Locale = .current) -> [OverviewAttentionItem] {
        let affected = Set(valuator.tradeIssues().map(\.account)).compactMap { library.accounts[$0] }
        return affected.sorted { ($0.name, $0.id.rawValue) < ($1.name, $1.id.rawValue) }.compactMap { account in
            let notes = TradeIssueNote.notes(for: account.id, library: library, valuator: valuator, locale: locale)
            guard !notes.isEmpty else { return nil }
            var kinds: [String] = []
            for note in notes where !kinds.contains(note.title) {
                kinds.append(note.title)
            }
            let shown = kinds.prefix(2).joined(separator: " · ")
            let more = kinds.count > 2 ? " · \(kinds.count - 2) more" : ""
            return OverviewAttentionItem(
                id: "trades.\(account.id)", systemImage: "exclamationmark.triangle",
                title: "\(account.name): \(Wording.count(notes.count, "problem")) with trades",
                detail: "\(shown)\(more). Open the account to fix \(notes.count == 1 ? "it" : "them").",
                target: .account(account.id))
        }
    }

    /// Prices and exchange rates missing on month ends before `asOf`, which
    /// leave accounts out of the net-worth history, with *Fill In Past
    /// Prices*: an item per currency, and per instrument for one or two
    /// (more are one item, so they don't crowd the card). The latest
    /// check-in's own gaps are the items above, typed in at the next check-in.
    static func pastGaps(library: Library, valuator: Valuator, asOf: CalendarDate,
                         locale: Locale = .current) -> [OverviewAttentionItem] {
        let dates = valuator.dates(.monthEnds, in: .netWorth, through: asOf).filter { $0 < asOf }
        guard let missing = valuator.missingValues(in: .netWorth, on: dates)?.filter({ $0.item.isPriceOrRate })
        else { return [] }
        func counted(_ accounts: [AccountID], _ dates: [CalendarDate]) -> String {
            let names = Set(accounts).map { library.accounts[$0]?.name ?? $0.rawValue }.sorted()
            return "\(MissingValueNote.shortList(names)) \(names.count == 1 ? "isn't" : "aren't") fully counted in "
                + "your net worth \(MissingValueNote.when(dates, locale: locale))"
        }
        var items: [OverviewAttentionItem] = []
        var prices: [(InstrumentID, MissingValues.Gap)] = []
        for gap in missing.gaps {
            switch gap.item {
            case .rate(let from, let to):
                items.append(OverviewAttentionItem(
                    id: "past.fx.\(from)-\(to)", systemImage: "arrow.left.arrow.right",
                    title: "Past exchange rates for \(AmountFormat.symbol(for: from, locale: locale)) are missing",
                    detail: counted(gap.accounts, gap.dates) + ". Fill in past prices to fetch them.",
                    target: .fillPastPrices))
            case .price(let instrument):
                prices.append((instrument, gap))
            case .noValuation:
                break
            }
        }
        func name(_ id: InstrumentID) -> String { library.instruments[id]?.name ?? id.rawValue }
        let fetchOrType = ". Fill in past prices to fetch them, or type them in."
        if prices.count > 2 {
            let gaps = prices.map(\.1)
            items.append(OverviewAttentionItem(
                id: "past.prices", systemImage: "tag.slash",
                title: "Past prices for \(prices.count) instruments are missing",
                detail: "\(MissingValueNote.shortList(prices.map { name($0.0) })): "
                    + counted(gaps.flatMap(\.accounts), Set(gaps.flatMap(\.dates)).sorted()) + fetchOrType,
                target: .fillPastPrices))
        } else {
            for (instrument, gap) in prices {
                items.append(OverviewAttentionItem(
                    id: "past.price.\(instrument)", systemImage: "tag.slash",
                    title: "Past prices for \(name(instrument)) are missing",
                    detail: counted(gap.accounts, gap.dates) + fetchOrType, target: .fillPastPrices))
            }
        }
        return items
    }
}
