import Foundation
import Model
import Planner

// The words of the Target mix card (UI.md, "Target mix"). What it shows is
// the Planner's `PlanTargetMixModel`.

extension PlanTargetMixModel.Row {
    /// "Equity", "Real estate".
    var name: String { PlanIssueText.assetClassName(assetClass.rawValue) }
}

extension PlanTargetMixModel {
    /// The line at the top of the card.
    static let explanation = "Each year the plan rebalances the money you can draw back to this mix: what you save "
        + "goes in at it, withdrawals sell every class alike, and rebalancing isn't taxed."

    /// Under "Today's mix".
    static let todaysMixExplanation = "The money you can draw is rebalanced back to its mix today, whatever it "
        + "holds, crypto included. Choose a mix to decide it yourself."

    /// The note under the card.
    static let wrappersNote = "Accounts available only from a later age, such as a pension fund, keep their own mix "
        + "until then."

    /// Under the table: what "Today" counts.
    static let todayNote = "Today: the share of the money you can draw, then of all the money in the plan."

    /// What a mix's total needs, or `nil` when it's 100%: "Adds up to 95%:
    /// add 5%.", "Adds up to 110%: take off 10%."
    static func problem(_ mix: AssetMix?, locale: Locale = .current) -> String? {
        let total = mix?.total ?? 0
        guard total != 1 else { return nil }
        let percent = { (share: Decimal) in AmountFormat.number(share * 100, maxDigits: 2, locale: locale) + "%" }
        return total < 1 ? "Adds up to \(percent(total)): add \(percent(1 - total)) to reach 100%."
            : "Adds up to \(percent(total)): take off \(percent(total - 1)) to reach 100%."
    }

    /// "Total 100%", "Total 95%".
    static func totalText(_ mix: AssetMix?, locale: Locale = .current) -> String {
        "Total " + AmountFormat.number((mix?.total ?? 0) * 100, maxDigits: 2, locale: locale) + "%"
    }

    /// "Grows at a median of 2.9% a year, rebalanced every year (today's mix: 1.9%)."
    func growthText(of mix: AssetMix?, comparedWithToday: Bool = false, locale: Locale = .current) -> String? {
        guard let mix, mix.total > 0 else { return nil }
        var text = "Grows at a median of " + AmountFormat.percent(growth(of: mix), locale: locale)
            + " a year, rebalanced every year"
        if comparedWithToday, let today = todaysGrowth {
            text += " (today's mix: \(AmountFormat.percent(today, locale: locale)))"
        }
        return text + "."
    }

    /// "From 55", "From retirement".
    static func title(of start: AgeOrRetirement) -> String {
        switch start {
        case .age(let age): "From \(age)"
        case .retirement: "From retirement"
        }
    }

    /// Under a step already in force: "You're 56: this already applies from the start."
    func startedNote(step index: Int) -> String? {
        guard hasStarted(step: index), let currentAge else { return nil }
        return "You're \(currentAge): this already applies from the start."
    }

    // MARK: Summary

    /// The card's one line: "Today's mix", "Equity 80% · bonds 20% ·
    /// changes at retirement and 75".
    static func summary(_ portfolio: PlanPortfolio, locale: Locale = .current) -> String {
        var parts = [mixSummary(portfolio.targetMix, locale: locale)]
        let steps = portfolio.targetMixByAge.map { step -> String in
            switch step.fromAge {
            case .age(let age): "\(age)"
            case .retirement: "retirement"
            }
        }
        if !steps.isEmpty { parts.append("changes at " + Wording.list(steps)) }
        return parts.joined(separator: " · ")
    }

    /// One mix in words, largest share first: "Equity 80% · bonds 20%";
    /// "Today's mix" without one (the plan keeps what you hold).
    static func mixSummary(_ mix: AssetMix?, locale: Locale = .current) -> String {
        guard let mix, mix.total > 0 else { return "Today's mix" }
        let classes = mix.shares.filter { $0.value != 0 }.sorted { ($1.value, $0.key) < ($0.value, $1.key) }
        return classes.enumerated().map { index, entry in
            let name = PlanIssueText.assetClassName(entry.key.rawValue)
            return "\(index == 0 ? name : name.lowercased()) "
                + AmountFormat.number(entry.value * 100, maxDigits: 1, locale: locale) + "%"
        }.joined(separator: " · ")
    }
}
