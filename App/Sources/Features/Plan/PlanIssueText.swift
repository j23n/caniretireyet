import Foundation
import Model
import Planner
import TaxKit

/// Plan issues in words for the screens. The planner's messages are written
/// for the plan file and name IDs (`ch.bvg`, an account's ID, a claim
/// route's ID, `startingBalance`); here they name what you see in the app:
/// the scheme's, account's and route's names. Issues the app doesn't know
/// keep the planner's or the tax system's message.
enum PlanIssueText {
    /// `issues` with their messages for the screens, in the same order.
    static func humanized(_ issues: [PlanIssue], plan: PlanDocument?, library: Library,
                          registry: TaxRegistry = AppTaxRegistry.standard, today: CalendarDate = .today())
        -> [PlanIssue] {
        issues.map { issue in
            var issue = issue
            issue.message = message(for: issue, plan: plan, library: library, registry: registry, today: today)
            return issue
        }
    }

    /// The message to show for `issue`.
    static func message(for issue: PlanIssue, plan: PlanDocument?, library: Library,
                        registry: TaxRegistry = AppTaxRegistry.standard, today: CalendarDate = .today()) -> String {
        let contribution = issue.section == .contributions ? issue.index.flatMap { plan?.contributions[planIndex: $0] } : nil
        let pension = issue.section == .pensions ? issue.index.flatMap { plan?.pensions[planIndex: $0] } : nil
        switch issue.code {
        case "planner.contributionTarget":
            return "This contribution names both an account and a pension scheme: choose one."
        case "planner.contributionAmount":
            return "This contribution is set to be paid every year and once: choose one."
        case "planner.contributionYear":
            return "A one-off contribution needs an amount and a year."
        case "planner.contributionScheme":
            if let scheme = contribution?.pension {
                return "None of the tax systems here has a pension scheme “\(scheme)”, so this contribution stays in "
                    + "your savings."
            }
        case "planner.contributionWithoutPension":
            if let scheme = contribution?.pension {
                let name = schemeName(scheme.rawValue, registry: registry)
                return "This contribution goes into \(name), but the plan has no \(name) pension to pay it out: "
                    + "add one under Pensions."
            }
        case "planner.claimRoute":
            if let pension, let route = pension.claimRoute {
                let routes = PlanPensionChoices.claimRoutes(for: pension, birthDate: library.settings.person?.birthDate,
                                                            today: today, registry: registry)
                let name = PlanResultsMapping.shortName(PlanResultsMapping.pensionName(pension, registry: registry))
                return "\(name) never offers “\(PlanPensionChoices.routeName(route, among: routes))” in the plan's "
                    + "years, so it isn't paid. Choose another way to claim it."
            }
        case "planner.seedReplaced":
            if let pension {
                let name = PlanResultsMapping.shortName(PlanResultsMapping.pensionName(pension, registry: registry))
                return "\(name) has a starting balance in the plan, so the value of "
                    + accountNames(in: issue.message, library: library) + " isn't used."
            }
        case "planner.lowMedianReturn":
            if let option = issue.option,
               let assumption = (plan?.assumptions ?? PlanAssumptions()).returnAssumption(for: AssetClass(option)) {
                let median = AmountFormat.percent(assumption.medianReturn, digits: 0)
                let mean = AmountFormat.percent(assumption.meanReturn, digits: 1)
                return "\(assetClassName(option))'s returns give a typical year of \(median) (an average of \(mean) at "
                    + "\(AmountFormat.percent(assumption.volatility, digits: 0)) volatility): holding it and "
                    + "rebalancing back into it every year shrinks your portfolio. Check its return under Assumptions."
            }
        case "planner.meanAndMedian":
            if let option = issue.option, let assumption = plan?.assumptions.returns[AssetClass(option)] {
                return "\(assetClassName(option))'s return has both an average (mean) and a typical (median) value in "
                    + "the plan file: the plan uses the average, \(AmountFormat.percent(assumption.real, digits: 1)). "
                    + "Enter one of them under Assumptions."
            }
        default:
            break
        }
        return withNames(issue.message, issue: issue, library: library, registry: registry)
    }

    /// `message` with the IDs of the pension schemes the registry knows,
    /// and of the issue's account, replaced by their names.
    static func withNames(_ message: String, issue: PlanIssue, library: Library, registry: TaxRegistry) -> String {
        var text = message
        for system in registry.systems {
            for scheme in system.pensionSchemes where scheme.id.contains(".") {
                text = replacing(scheme.id, with: PlanResultsMapping.shortName(scheme.name), in: text)
            }
        }
        if let id = issue.account, let account = library.accounts[id] {
            text = replacing(id.rawValue, with: account.name, in: text)
        }
        return text
    }

    /// The names of the library's accounts whose IDs `message` mentions,
    /// "A, B and C"; "the accounts" when it mentions none.
    static func accountNames(in message: String, library: Library) -> String {
        let names = library.accounts.values.sorted { $0.id < $1.id }
            .filter { containsWord($0.id.rawValue, in: message) }
            .map(\.name)
        return names.isEmpty ? "the accounts" : PlanResultsText.list(names)
    }

    /// An asset class as the assumptions editor names it: "Crypto", "Real estate".
    static func assetClassName(_ rawValue: String) -> String {
        if rawValue == AssetClass.realEstate.rawValue { return "Real estate" }
        return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    /// A pension scheme's name without the explanation in brackets: "BVG".
    static func schemeName(_ id: String, registry: TaxRegistry) -> String {
        PlanResultsMapping.shortName(registry.pensionScheme(id)?.name ?? id)
    }

    /// `text` with each whole `word` replaced: not part of a longer ID
    /// (`ch.bvg` in `ch.bvg.capital`), though a full stop may follow it.
    static func replacing(_ word: String, with replacement: String, in text: String) -> String {
        guard !word.isEmpty, text.contains(word) else { return text }
        var result = ""
        var index = text.startIndex
        while let range = text.range(of: word, range: index..<text.endIndex) {
            let previous = range.lowerBound > text.startIndex ? text[text.index(before: range.lowerBound)] : nil
            let startsWord = previous.map { !isIDCharacter($0) } ?? true
            var endsWord = true
            if range.upperBound < text.endIndex {
                let next = text[range.upperBound]
                if next == "." {
                    let after = text.index(after: range.upperBound)
                    endsWord = after == text.endIndex || text[after].isWhitespace
                } else {
                    endsWord = !isIDCharacter(next)
                }
            }
            result += text[index..<range.lowerBound]
            result += startsWord && endsWord ? replacement : String(text[range])
            index = range.upperBound
        }
        return result + text[index...]
    }

    /// Whether `text` mentions `word` as a whole (see ``replacing(_:with:in:)``).
    static func containsWord(_ word: String, in text: String) -> Bool {
        replacing(word, with: "\u{1}", in: text) != text
    }

    /// Letters, digits and the characters IDs use (`-`, `_`, `.`).
    private static func isIDCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "-" || character == "_" || character == "."
    }
}

extension Array {
    /// The element at `index`, or `nil` past the end.
    subscript(planIndex index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
