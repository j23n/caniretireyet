import Foundation
import Model
import Tracker

/// What deleting a trade does besides removing it, in words.
enum TradeEditNotes {
    /// What deleting `key` does, for its confirmation: the holdings, cash
    /// and gains worked out again, and the problems it brings in (e.g. a
    /// later sale now taking away more than is held).
    static func removal(of key: TradeKey, in library: Library, locale: Locale = .current) -> String {
        var after = library
        let newIssues = after.removeTrade(key)
        var sentences = ["The account's holdings, cash and gains are worked out again without it."]
        for issue in newIssues where issue.kind != .reconciliation {
            if let note = TradeIssueNote.note(for: issue, library: after, locale: locale) {
                sentences.append(note.message)
            }
        }
        return sentences.joined(separator: " ")
    }
}
