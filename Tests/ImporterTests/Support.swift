import Foundation
@testable import Importer
import Model
import TestSupport

/// The made-up sample files in `Samples/`:
///
/// | File | What it covers |
/// | --- | --- |
/// | `italian-excel-1252.csv` | Windows-1252, `;`, `1.234,56`, CRLF, a quoted `;`, a "Totale" row |
/// | `us-export.csv` | UTF-8 with BOM, `,`, `$1,234.56`, `(negatives)`, `MM/dd/yyyy`, an FX column |
/// | `numbers-export.csv` | a table-name title row, `31 gen 2026`, NBSP thousands, `€` after amounts, `%` |
/// | `titles-totals-utf16.tsv` | UTF-16 LE, tabs, title and empty rows, "Totale" and "TOTAL GENERALE" rows |
/// | `month-only.csv` | `|`, `gennaio 2026` month-only dates |
/// | `excel-serial.csv` | Excel serial dates, an account that stops early, a negative mortgage |
/// | `long-format.csv` | long layout, names in other cases and accents, a date-time |
/// | `positions.csv` | long layout with quantity, price and purchase cost per row, `31-gen-26` |
/// | `broken-rows.csv` | bad dates, bad numbers, a missing date, a quote that never closes |
/// | `positive-debts.csv` | a mortgage and a loan written as positive amounts, a card written negative |
/// | `trades/directa.csv` | a Directa-like movements export: title rows, UTF-8 with BOM, `;`, `1.234,56`, signed amounts, a sell as a negative quantity, a dividend and its tax on two rows, two identical buys, an unmapped type (`Giroconto`) |
/// | `trades/fineco.csv` | a Fineco-like export: Windows-1252, `Compravendita acquisto`, gross values without signs (`Controvalore`) with fees and tax columns, no account column |
/// | `trades/degiro.csv` | a Degiro-like transactions export in English: no type column, sells as negative quantities, buys as negative amounts, a price in dollars, `dd-MM-yyyy` |
/// | `trades/ibkr.csv` | an IBKR-like flex export: camel-case headers, an account column, `Deposits/Withdrawals` both ways, dividends, withholding tax, interest, fees |
enum Samples {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: "Samples/\(name)", withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }

    static func session(_ name: String) throws -> ImportSession {
        try ImportSession(data: data(name))
    }
}

/// A date from a string variable (not a literal).
func date(_ string: String) -> CalendarDate {
    CalendarDate(string)!
}

/// A small library for tests: two accounts and an instrument.
func smallLibrary() -> Library {
    var library = Library(
        accounts: [
            Account(id: "conto-fineco", name: "Conto Fineco", kind: .cash, currency: .eur, opened: "2020-01-01"),
            Account(id: "fondo-pensione", name: "Fondo pensione", kind: .pensionFund, currency: .eur,
                    opened: "2022-01-01"),
            Account(id: "directa", name: "Directa", kind: .brokerage, currency: .eur, opened: "2021-03-01"),
        ],
        instruments: [
            Instrument(id: "vwce", name: "Vanguard FTSE All-World", kind: .etf, currency: .eur, unit: .share,
                       assetClasses: .single(.equity), ticker: "VWCE"),
        ])
    library.upsert(Valuation(account: "conto-fineco", date: "2026-01-31", balance: d("5210.85")))
    library.upsert(Valuation(account: "fondo-pensione", date: "2026-01-31", balance: d("17000")))
    return library
}

extension ImportPreview {
    /// The record with this key.
    func record(_ key: ImportRecordKey) -> ImportRecordPreview? {
        records.first { $0.imported.key == key }
    }

    /// The statuses of all records, by key description.
    var statuses: [String: ImportRecordStatus] {
        Dictionary(uniqueKeysWithValues: records.map { ($0.imported.key.description, $0.status) })
    }
}

extension ImportRecordKey {
    static func valuation(_ account: AccountID, _ date: CalendarDate) -> ImportRecordKey {
        .valuation(ValuationKey(account: account, date: date))
    }

    static func price(_ instrument: InstrumentID, _ date: CalendarDate) -> ImportRecordKey {
        .price(PriceKey(instrument: instrument, date: date))
    }
}
