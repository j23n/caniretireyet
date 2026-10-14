import Foundation
import Model

/// A sale, in one file of a batch, of what a purchase in another file of
/// the batch starts (IMPORT.md, "Several statements at once"). The
/// purchase's file records both, so it doesn't matter which file is
/// previewed first.
struct StatementSaleElsewhere: Hashable, Sendable {
    /// The sale's day.
    var date: CalendarDate
    /// The value of the sale's own file the line counts in.
    var cut: CalendarDate
    /// What it sold for: the line's amount, money in.
    var amount: Decimal
}

/// What one file's preview needs to know of the sales across the files of
/// its batch (``StatementBatch/salesAcrossFiles(_:library:)``).
struct StatementBatchSales: Hashable, Sendable {
    /// The rows of this file whose sale the purchase's file records.
    var recordedElsewhere: Set<Int> = []
    /// The sales in other files of what this file's purchases start, by
    /// the purchase's row.
    var ofPurchases: [Int: StatementSaleElsewhere] = [:]

    var isEmpty: Bool { recordedElsewhere.isEmpty && ofPurchases.isEmpty }
}

extension StatementBatch {
    /// The sales across files, by file, from previews made without them:
    /// a line in answered as the sale of the account a purchase in another
    /// file starts or finds, on or after the purchase's day, in the same
    /// currency, that counts in a value of its file; the first such sale of
    /// each account, and none of an account its own file sells.
    func salesAcrossFiles(_ previews: [(file: Int, preview: ImportPreview)],
                          library: Library) -> [Int: StatementBatchSales] {
        var purchases: [AccountID: (file: Int, row: Int, date: CalendarDate)] = [:]
        var soldInFile: [AccountID: Set<Int>] = [:]
        for (file, preview) in previews {
            for line in preview.statementLines {
                guard let id = line.assetAccount else { continue }
                switch line.asset {
                case .purchase?: if purchases[id] == nil { purchases[id] = (file, line.row, line.date) }
                case .sale?: soldInFile[id, default: []].insert(file)
                default: break
                }
            }
        }
        func currency(ofFile id: Int) -> CurrencyCode? {
            files.first { $0.id == id }?.account.flatMap { library.accounts[$0]?.currency }
        }
        var sales: [(account: AccountID, file: Int, line: StatementLine)] = []
        for (file, preview) in previews {
            guard let session = files.first(where: { $0.id == file })?.session else { continue }
            for line in preview.statementLines {
                guard case .sale(let id)? = session.statementAssets[line.row], let purchase = purchases[id],
                      purchase.file != file, soldInFile[id]?.contains(purchase.file) != true, line.amount > 0,
                      line.period != nil,
                      line.date >= purchase.date, currency(ofFile: file) == currency(ofFile: purchase.file)
                else { continue }
                sales.append((id, file, line))
            }
        }
        var byFile: [Int: StatementBatchSales] = [:]
        var sold = Set<AccountID>()
        for sale in sales.sorted(by: { ($0.line.date, $0.file, $0.line.row) < ($1.line.date, $1.file, $1.line.row) }) {
            guard let purchase = purchases[sale.account], let cut = sale.line.period,
                  sold.insert(sale.account).inserted else { continue }
            byFile[sale.file, default: StatementBatchSales()].recordedElsewhere.insert(sale.line.row)
            byFile[purchase.file, default: StatementBatchSales()].ofPurchases[purchase.row] =
                StatementSaleElsewhere(date: sale.line.date, cut: cut, amount: sale.line.amount)
        }
        return byFile
    }
}
