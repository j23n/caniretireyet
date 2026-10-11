import Foundation

extension TemporaryFolder {
    /// A made-up library in format version 3, with one account for each rule
    /// of the upgrade to version 4 (docs/ACCOUNTS.md, "Migration"):
    ///
    /// - `bank`: a current account that opted in to money in and out;
    /// - `broker`: a brokerage account recorded as snapshots by default,
    ///   whose values hold positions, the first without a purchase cost;
    /// - `new-broker`: a brokerage account recorded as snapshots, with no values;
    /// - `exchange`: a crypto account recorded as a balance;
    /// - `wallet`: a crypto account recorded as snapshots by default, whose
    ///   values hold only balances;
    /// - `fund`: a pension fund recorded as snapshots, whose values hold only
    ///   balances.
    public static func version3Library() throws -> TemporaryFolder {
        let folder = try TemporaryFolder()
        try folder.write("library.json", """
            { "baseCurrency": "EUR", "schemaVersion": 3 }
            """)
        try folder.write("instruments/vwce.json", """
            { "assetClasses": { "equity": "1" }, "currency": "EUR", "id": "vwce", "kind": "etf", "name": "VWCE", "unit": "share" }
            """)
        let accounts = [
            "bank": #""kind": "cash", "moneyInOut": true, "name": "Bank""#,
            "broker": #""kind": "brokerage", "myNote": "kept", "name": "Broker""#,
            "new-broker": #""kind": "brokerage", "name": "New broker""#,
            "exchange": #""kind": "crypto", "name": "Exchange", "valuation": "balance""#,
            "wallet": #""kind": "crypto", "name": "Wallet""#,
            "fund": #""kind": "pensionFund", "name": "Fund", "valuation": "holdings""#,
        ]
        for (id, fields) in accounts {
            try folder.write("accounts/\(id).json", """
                { "currency": "EUR", "id": "\(id)", \(fields), "opened": "2026-01-01" }
                """)
        }
        try folder.write("history/2026/2026-01.json", """
            {
              "fx": [],
              "indices": [],
              "month": "2026-01",
              "prices": [{ "currency": "EUR", "date": "2026-01-31", "instrument": "vwce", "price": "100" }],
              "valuations": [
                { "account": "bank", "balance": "1000", "date": "2026-01-31" },
                { "account": "broker", "cash": "50", "date": "2026-01-31",
                  "positions": [{ "instrument": "vwce", "quantity": "10" }] },
                { "account": "exchange", "balance": "500", "date": "2026-01-31" },
                { "account": "fund", "balance": "3000", "date": "2026-01-31" },
                { "account": "wallet", "balance": "200", "date": "2026-01-31" }
              ]
            }
            """)
        try folder.write("history/2026/2026-02.json", """
            {
              "fx": [],
              "indices": [],
              "month": "2026-02",
              "prices": [{ "currency": "EUR", "date": "2026-02-28", "instrument": "vwce", "price": "110" }],
              "valuations": [
                { "account": "bank", "balance": "1200", "date": "2026-02-28", "flow": "200", "moneyIn": "2000",
                  "moneyOut": "1800" },
                { "account": "broker", "cash": "20", "date": "2026-02-28", "flow": "520",
                  "positions": [{ "costBasis": "1550", "instrument": "vwce", "quantity": "15" }] },
                { "account": "exchange", "balance": "550", "date": "2026-02-28", "flow": "0" },
                { "account": "fund", "balance": "3100", "date": "2026-02-28", "flow": "100" },
                { "account": "wallet", "balance": "210", "date": "2026-02-28", "flow": "0" }
              ]
            }
            """)
        return folder
    }
}
