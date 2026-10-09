import Foundation
import Model
import Planner

/// Plan issues in words for the screens. The planner's messages are written
/// for the plan file and name IDs and keys (an account's ID,
/// `portfolio.unrealizedGainShare`); here they name what you see in the
/// app. Issues the app doesn't know keep the planner's message.
enum PlanIssueText {
    /// `issues` with their messages for the screens, in the same order.
    static func humanized(_ issues: [PlanIssue], plan: PlanDocument?, library: Library) -> [PlanIssue] {
        issues.map { issue in
            var issue = issue
            issue.message = message(for: issue, plan: plan, library: library)
            return issue
        }
    }

    /// The message to show for `issue`.
    static func message(for issue: PlanIssue, plan: PlanDocument?, library: Library) -> String {
        switch issue.code {
        case "planner.noNetIncome":
            if let index = issue.index, let plan, plan.work.indices.contains(index) {
                return "\(plan.workName(index)): enter the income after tax."
            }
        case "planner.unknownCostBasis":
            return issue.message.replacingOccurrences(
                of: "in the plan (portfolio.unrealizedGainShare)", with: "under Assumptions (Unrealised gains, estimate)")
        case "planner.investmentRate" where plan?.tax.investmentRate == nil:
            return "Set the tax rate on investments under Taxes: the plan taxes the gains on what you sell and the "
                + "income your investments pay with it (0% if they aren't taxed)."
    case "planner.lowMedianReturn":
            if let option = issue.option,
               let assumption = (plan?.assumptions ?? PlanAssumptions()).returnAssumption(for: AssetClass(option)) {
                let median = AmountFormat.percent(assumption.medianReturn, digits: 0)
                let mean = AmountFormat.percent(assumption.meanReturn, digits: 1)
                return "\(assetClassName(option))'s returns give a typical year of \(median) (an average of \(mean) at "
                    + "\(AmountFormat.percent(assumption.volatility, digits: 0)) volatility): holding it and "
                    + "rebalancing back into it every year shrinks your portfolio. Check its return under Assumptions."
            }
        case "planner.noAssetMix":
            if let id = issue.account, let account = library.accounts[id] {
                return "\(account.name) counts as cash: it has no mix of investments set."
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
        return withNames(issue.message, issue: issue, library: library)
    }

    /// `message` with the issue's account's ID replaced by its name.
    static func withNames(_ message: String, issue: PlanIssue, library: Library) -> String {
        var text = message
        if let id = issue.account, let account = library.accounts[id] {
            text = replacing(id.rawValue, with: account.name, in: text)
        }
        return text
    }

    /// An asset class as the assumptions editor names it: "Crypto", "Real estate".
    static func assetClassName(_ rawValue: String) -> String {
        if rawValue == AssetClass.realEstate.rawValue { return "Real estate" }
        return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    /// `text` with each whole `word` replaced: not part of a longer ID
    /// (`fondo` in `fondo-pensione`), though a full stop may follow it.
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

    /// Letters, digits and the characters IDs use (`-`, `_`, `.`).
    private static func isIDCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "-" || character == "_" || character == "."
    }
}
