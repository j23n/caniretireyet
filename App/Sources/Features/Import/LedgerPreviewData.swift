import Foundation
import Importer
import Model

/// Made-up journals for the Import screen's previews: two files, one of them
/// including a price file, with a bank, a broker holding an ETF, a wallet,
/// a card, salary, a dividend and a fee.
enum LedgerPreviewData {
    static let files = InMemoryLedgerFiles([
        "/Preview/2026.journal": """
            commodity 1.000,00 EUR
            include prices.journal

            2026-07-01 * Opening balances
                Assets:Bank:Fineco           4.800,00 EUR
                Assets:Broker:Directa:Cash     500,00 EUR
                Equity:Opening balances

            2026-07-27 * Stipendio
                Assets:Bank:Fineco           2.600,00 EUR
                Income:Salary

            2026-08-03 * Buy VWCE
                Assets:Broker:Directa        5 "VWCE.MI" @ 136,00 EUR
                Expenses:Fees:Broker             2,95 EUR
                Assets:Broker:Directa:Cash

            2026-08-20 * Groceries
                Expenses:Food                   85,40 EUR
                Liabilities:CreditCard:Visa
            """,
        "/Preview/prices.journal": """
            P 2026-07-31 "VWCE.MI" 134,80 EUR
            P 2026-08-31 "VWCE.MI" 137,10 EUR
            P 2026-08-31 BTC 98.000,00 EUR
            """,
        "/Preview/2026-crypto.journal": """
            2026-08-12 * Bitcoin
                Assets:Crypto:Wallet     0,01 BTC @@ 950,00 EUR
                Assets:Bank:Fineco

            2026-09-05 * Dividend
                Assets:Broker:Directa:Cash      4,10 EUR
                Income:Dividends
            """,
    ])

    static let roots = [URL(fileURLWithPath: "/Preview/2026.journal"), URL(fileURLWithPath: "/Preview/2026-crypto.journal")]

    /// The journals read, with a proposed mapping.
    static func state() -> LedgerImportState {
        let journal = LedgerReader.read(roots, files: files)
        return LedgerImportState(roots: roots, grants: roots, journal: journal, profile: nil, until: "2026-09-30")
    }
}
