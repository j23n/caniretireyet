import Foundation
import Model
import Tracker

/// What deleting a value or a trade does to the account's other values, in
/// words, for its confirmation (UI.md, "Account detail"). Plain values, so
/// they can be checked on Linux.
enum AccountValueNotes {
    /// What an edit does to the new money of the account's other values:
    /// "Deleting it also works out again the new money of the value on 30
    /// Sep 2026." for automatic amounts, "The new money of the value on 30
    /// Sep 2026 was typed in, so it stays as it is." for typed ones. `action`
    /// is what does it. `nil` when no other value is concerned.
    static func flowFollowUp(_ flows: FlowFollowUp, by action: String = "Deleting it",
                             locale: Locale = .current) -> String? {
        var sentences: [String] = []
        let recomputed = flows.recomputed
        if !recomputed.isEmpty {
            sentences.append("\(action) also works out again the new money of the \(values(recomputed)) on "
                + "\(dates(recomputed, locale: locale)).")
        }
        let kept = flows.kept
        if !kept.isEmpty {
            sentences.append("The new money of the \(values(kept)) on \(dates(kept, locale: locale)) was typed "
                + "in, so it stays as it is.")
        }
        if let moneyInOut = moneyInOutCheck(flows, locale: locale) {
            sentences.append(moneyInOut)
        }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }

    /// "Check the money in and out of the value on 30 Sep 2026: they were
    /// for the days since another value.", for the values that record them
    /// whose value before is now on another date (`FlowFollowUp.moneyInOut`);
    /// `nil` when there are none.
    static func moneyInOutCheck(_ flows: FlowFollowUp, locale: Locale = .current) -> String? {
        let valuations = flows.moneyInOut
        guard !valuations.isEmpty else { return nil }
        return "Check the money in and out of the \(values(valuations)) on \(dates(valuations, locale: locale)): "
            + "they were for the days since another value."
    }

    /// The confirmation for deleting a value on the account's details
    /// (`flows` from `Library.previewRemovingValue(_:)`): what the values
    /// after it keep or have worked out again.
    static func deleteMessage(_ flows: FlowFollowUp, locale: Locale = .current) -> String {
        let followUp = flowFollowUp(flows, locale: locale).map { " " + $0 } ?? ""
        return "The account's value then carries forward from the value before it." + followUp
    }

    /// "value" or "values", for `valuations`.
    private static func values(_ valuations: [Valuation]) -> String {
        valuations.count == 1 ? "value" : "values"
    }

    /// The dates of `valuations`: "30 Sep 2026 and 31 Oct 2026".
    private static func dates(_ valuations: [Valuation], locale: Locale) -> String {
        Wording.list(valuations.map { AmountFormat.mediumDate($0.date, locale: locale) })
    }
}
