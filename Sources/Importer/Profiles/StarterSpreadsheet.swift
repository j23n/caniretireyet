import Foundation
import Model

/// The starter spreadsheet first launch offers for what has no export to
/// import (UI.md, "Empty states and first launch"): a home, its mortgage, a
/// pension. A CSV in the wide layout (IMPORT.md, "Layouts"): a *Date*
/// column, then one column per account, named so the import proposes each
/// as a new account of the right kind, with a first row on the day it's
/// made. Fill in a row per date and import it.
public enum StarterSpreadsheet {
    /// What the file is called when it's saved.
    public static let fileName = "Starter spreadsheet.csv"

    /// The accounts it has a column for, in order.
    public static let accounts = ["Home", "Mortgage", "Pension"]

    /// The CSV: a header, then a row on `date` with each account's amount
    /// from `amounts` (by name), or empty. Amounts are written in their
    /// shortest exact form ("150000"), dates as `YYYY-MM-DD`.
    public static func csv(on date: CalendarDate, amounts: [String: Decimal] = [:]) -> String {
        let header = (["Date"] + accounts).joined(separator: ",")
        let row = [date.description] + accounts.map { name in amounts[name].map { $0.fileString } ?? "" }
        return header + "\n" + row.joined(separator: ",") + "\n"
    }
}
