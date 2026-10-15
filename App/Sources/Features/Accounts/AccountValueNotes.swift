import Foundation
import Model

/// What deleting a value does to the account's other values, in words, for
/// its confirmation (UI.md, "Account detail"). Plain values, so they can be
/// checked on Linux.
enum AccountValueNotes {
    /// The confirmation for deleting the value `key` on the account's
    /// details: "The account's value then carries forward from the value
    /// before it.", and when the value after it records money in and out,
    /// "Check the money in and out of the value on 31 Oct 2026: they were
    /// for the days since this one."
    static func deleteMessage(removing key: ValuationKey, in library: Library, locale: Locale = .current) -> String {
        let text = "The account's value then carries forward from the value before it."
        guard let next = library.valuations(for: key.account).first(where: { $0.date > key.date }),
              next.hasMoneyInOut
        else { return text }
        return text + " Check the money in and out of the value on "
            + "\(AmountFormat.mediumDate(next.date, locale: locale)): they were for the days since this one."
    }
}
