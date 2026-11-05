import Foundation
@testable import Importer
import Model
import Testing
import TestSupport
import Tracker

/// Invariant B7: the order statements are imported in doesn't change the
/// library. A year of made-up monthly statements of a current account
/// and a savings account, each with a running balance, imported as one
/// batch, as one batch given the other way round, month by month, and
/// month by month from December back.
struct StatementOrderInvariantTests {
    static let today: CalendarDate = "2027-01-15"

    static func library() -> Library {
        var library = Library(accounts: [
            Account(id: "conto", name: "Conto corrente", kind: .cash, currency: .eur, opened: "2020-01-01",
                    institution: "Fineco"),
            Account(id: "risparmio", name: "Risparmio", kind: .savings, currency: .eur, opened: "2020-01-01",
                    institution: "Banca Esempio"),
        ])
        library.upsert(Valuation(account: "conto", date: "2025-12-31", balance: 5000))
        library.upsert(Valuation(account: "risparmio", date: "2025-12-31", balance: 10000))
        return library
    }

    /// One month's statement lines of an account: (day, amount, text).
    static func lines(of account: AccountID, in month: Int) -> [(Int, Decimal, String)] {
        switch account {
        case "conto":
            var lines: [(Int, Decimal, String)] = [
                (3, -900, "Affitto"),
                (8, -250, "Supermercato Esempio"),
                (15, -500, "Giroconto a Risparmio"),
                (18, Decimal(-300 - 10 * month), "Supermercato Esempio"),
                (22, -80, "Bolletta luce"),
                (27, 3000, "Stipendio ACME"),
            ]
            if month == 3 { lines.append((20, 40, "Rimborso Negozio")) }
            if month == 6 { lines.append((16, -1200, "F24 Agenzia delle Entrate")) }
            return lines.sorted { $0.0 < $1.0 }
        default:
            return [(15, 500, "Giroconto da Conto corrente"),
                    (YearMonth(year: 2026, month: month)?.numberOfDays ?? 28, Decimal(20 + month) / 10, "Interessi")]
        }
    }

    /// The statement of `account` for `month` of 2026, with its running
    /// balance from `opening`, and the balance it ends at.
    static func statement(of account: AccountID, month: Int, opening: Decimal) -> (text: String, closing: Decimal) {
        var balance = opening
        var rows = ["Data;Importo;Descrizione;Saldo"]
        func italian(_ amount: Decimal) -> String {
            amount.fileString.replacingOccurrences(of: ".", with: ",")
        }
        for (day, amount, text) in lines(of: account, in: month) {
            balance += amount
            rows.append(String(format: "%02d/%02d/2026", day, month) + ";\(italian(amount));\(text);\(italian(balance))")
        }
        return (rows.joined(separator: "\n"), balance)
    }

    /// Every month's two statements, January first: (month, account, name, text).
    static let files: [(month: Int, account: AccountID, name: String, text: String)] = {
        var files: [(month: Int, account: AccountID, name: String, text: String)] = []
        var balances: [AccountID: Decimal] = ["conto": 5000, "risparmio": 10000]
        for month in 1...12 {
            for account in ["conto", "risparmio"] as [AccountID] {
                let made = statement(of: account, month: month, opening: balances[account] ?? 0)
                balances[account] = made.closing
                files.append((month, account, "\(account)-2026-\(month).csv", made.text))
            }
        }
        return files
    }()

    /// `files` imported as one batch onto `library`, each file's account chosen.
    static func importing(_ files: [(month: Int, account: AccountID, name: String, text: String)],
                          into library: Library) -> Library {
        var batch = StatementBatch(files: files.map { (name: $0.name, data: Data($0.text.utf8)) }, library: library,
                                   today: today)
        for (index, file) in files.enumerated() {
            batch.setAccount(file.account, forFile: index, library: library, today: today)
        }
        let previews = batch.previews(against: library, today: today)
        return ImportPreview.apply(previews.map(\.preview), to: library).library
    }

    /// The months' files imported one month at a time, in `months`' order.
    static func monthByMonth(_ months: [Int]) -> Library {
        months.reduce(library()) { library, month in
            importing(files.filter { $0.month == month }, into: library)
        }
    }

    /// What the tracker reads from the two accounts: each value as
    /// recorded, the year's savings rate and each month's.
    static func readings(_ library: Library) -> [String] {
        var readings = library.months.values.flatMap(\.valuations).sortedByKey().map { value in
            "\(value.account) \(value.date) balance \(value.balance?.fileString ?? "-") in "
                + "\(value.moneyIn?.fileString ?? "-") out \(value.moneyOut?.fileString ?? "-") interest "
                + "\(value.interest?.fileString ?? "-") tax \(value.tax?.fileString ?? "-")"
        }
        let valuator = Valuator(library: library)
        let year = valuator.savingsRate(from: "2026-01-01", through: "2026-12-31")
        readings.append("2026 came in \(year?.income.fileString ?? "-") saved \(year?.saved.fileString ?? "-")")
        for month in 1...12 {
            guard let month = YearMonth(year: 2026, month: month) else { continue }
            let rate = valuator.savingsRate(from: month.firstDay, through: month.lastDay)
            readings.append("\(month) came in \(rate?.income.fileString ?? "-") spent \(rate?.spent.fileString ?? "-")")
        }
        return readings
    }

    @Test func oneBatchInEitherOrderGivesTheSameLibrary() {
        let forward = Self.readings(Self.importing(Self.files, into: Self.library()))
        let backward = Self.readings(Self.importing(Self.files.reversed(), into: Self.library()))
        #expect(backward == forward)
        // June: pay of 3,000; rent, groceries, the bill and the tax bill of 1,200 out.
        #expect(forward.contains("conto 2026-06-30 balance 9450 in 3000 out 2790 interest - tax 1200"))
        // 12 × 3,000 less the tax; 9,700 more in the current account and 12 × 500 moved to savings.
        #expect(forward.contains("2026 came in 34800 saved 15700"))
    }

    @Test func monthByMonthGivesWhatOneBatchGives() {
        let batch = Self.readings(Self.importing(Self.files, into: Self.library()))
        #expect(Self.readings(Self.monthByMonth(Array(1...12))) == batch)
    }

    /// From December back, each month's file finds no value the day before
    /// it, as the month before isn't imported yet, so its first value gets
    /// no money in and out (IMPORT.md, "Values"). Importing the month
    /// before adds the value the month after follows on from, and the
    /// month after's value then gets them from its lines.
    @Test func monthByMonthFromDecemberBackGivesWhatOneBatchGives() {
        let inOneBatch = Self.importing(Self.files, into: Self.library())
        let fromDecember = Self.monthByMonth(Array((1...12).reversed()))
        // The balances agree.
        for account in ["conto", "risparmio"] as [AccountID] {
            #expect(fromDecember.valuations(for: account).map { "\($0.date) \($0.balance ?? 0)" }
                == inOneBatch.valuations(for: account).map { "\($0.date) \($0.balance ?? 0)" })
        }
        let batch = Self.readings(inOneBatch)
        let backward = Self.readings(fromDecember)
        #expect(backward == batch)
    }
}
