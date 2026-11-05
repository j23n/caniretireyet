import Foundation
import Importer
import Model
import Testing
import TestSupport
import Tracker

/// Invariant B8: the CSV export round-trips. What `retire export` writes
/// (`CSVExport.files(of:through:)`), read back into a fresh library, gives
/// the same export, net worth and account values included, and the same
/// savings rates and split of each check-in. The export says what's
/// recorded "field for field as in the library's files"
/// (docs/schema/README.md, "CSV export"), so a field that changes a value
/// and isn't exported shows here.
struct ExportRoundTripTests {
    /// One exported table, its rows by column name.
    private struct Table {
        let rows: [[String: String]]

        init(_ text: String) {
            let lines = CSVParser.parse(text, delimiter: ",").filter { $0 != [""] }
            let header = lines.first ?? []
            rows = lines.dropFirst().map { fields in
                Dictionary(zip(header, fields).map { ($0, $1) }, uniquingKeysWith: { first, _ in first })
            }
        }
    }

    /// A fresh library from the export's tables.
    private func library(from files: [CSVExport.File]) throws -> Library {
        var tables: [String: Table] = [:]
        for file in files { tables[file.name] = Table(file.text) }
        func table(_ name: String) throws -> [[String: String]] { try #require(tables[name], "\(name)").rows }
        func text(_ row: [String: String], _ column: String) -> String? {
            row[column].flatMap { $0.isEmpty ? nil : $0 }
        }
        func decimal(_ row: [String: String], _ column: String) -> Decimal? {
            text(row, column).flatMap { Decimal(fileString: $0) }
        }
        func date(_ row: [String: String], _ column: String) throws -> CalendarDate {
            try #require(text(row, column).flatMap { CalendarDate($0) }, "\(column)")
        }
        func mix(_ field: String?) -> AssetMix? {
            guard let field else { return nil }
            var shares: [AssetClass: Decimal] = [:]
            for part in field.components(separatedBy: "; ") {
                let pair = part.components(separatedBy: "=")
                if pair.count == 2, let share = Decimal(fileString: pair[1]) { shares[AssetClass(pair[0])] = share }
            }
            return AssetMix(shares)
        }

        let currency = try #require(try table("net-worth.csv").first.flatMap { text($0, "currency") })
        var library = Library(settings: LibrarySettings(baseCurrency: CurrencyCode(currency)))
        for row in try table("accounts.csv") {
            let account = Account(
                id: AccountID(try #require(text(row, "id"))), name: text(row, "name") ?? "",
                kind: AccountKind(try #require(text(row, "kind"))),
                currency: CurrencyCode(try #require(text(row, "currency"))), opened: try date(row, "opened"),
                closed: text(row, "closed").flatMap { CalendarDate($0) }, institution: text(row, "institution"),
                country: text(row, "country").map { CountryCode($0) },
                valuation: text(row, "valuation").map { ValuationMode($0) },
                assetClasses: mix(text(row, "asset_classes")),
                availableFromAge: text(row, "available_from_age").flatMap { Int($0) },
                includeIn: IncludeIn(netWorth: text(row, "in_net_worth") == "yes", plan: text(row, "in_plans") == "yes"),
                successor: text(row, "successor").map { AccountID($0) },
                tags: text(row, "tags")?.components(separatedBy: "; ") ?? [], notes: text(row, "notes"),
                depreciation: decimal(row, "depreciation"),
                withdrawalTaxRate: decimal(row, "withdrawal_tax_rate"))
            library.accounts[account.id] = account
        }
        for row in try table("instruments.csv") {
            let source = text(row, "price_provider").map {
                PriceSource(provider: PriceProvider($0), symbol: text(row, "price_symbol") ?? "")
            }
            let instrument = Instrument(
                id: InstrumentID(try #require(text(row, "id"))), name: text(row, "name") ?? "",
                kind: InstrumentKind(try #require(text(row, "kind"))),
                currency: CurrencyCode(try #require(text(row, "currency"))),
                unit: InstrumentUnit(try #require(text(row, "unit"))),
                assetClasses: mix(text(row, "asset_classes")) ?? AssetMix(), isin: text(row, "isin"),
                ticker: text(row, "ticker"), priceSource: source)
            library.instruments[instrument.id] = instrument
        }
        var positions: [ValuationKey: [Position]] = [:]
        for row in try table("positions.csv") {
            let key = ValuationKey(account: AccountID(try #require(text(row, "account"))), date: try date(row, "date"))
            positions[key, default: []].append(Position(
                instrument: InstrumentID(try #require(text(row, "instrument"))),
                quantity: try #require(decimal(row, "quantity")), costBasis: decimal(row, "cost_basis")))
        }
        for row in try table("valuations.csv") {
            let account = AccountID(try #require(text(row, "account")))
            let day = try date(row, "date")
            library.upsert(Valuation(
                account: account, date: day, balance: decimal(row, "balance"), cash: decimal(row, "cash"),
                positions: positions[ValuationKey(account: account, date: day)] ?? [], saved: decimal(row, "saved"),
                moneyIn: decimal(row, "money_in"), moneyOut: decimal(row, "money_out"),
                oneOff: decimal(row, "one_off"), tax: decimal(row, "tax"), interest: decimal(row, "interest"),
                note: text(row, "note"), source: text(row, "source").map { DataSource($0) }))
        }
        for row in try table("trades.csv") {
            library.upsert(Trade(
                account: AccountID(try #require(text(row, "account"))), date: try date(row, "date"),
                id: TradeID(try #require(text(row, "id"))), type: TradeType(try #require(text(row, "type"))),
                instrument: text(row, "instrument").map { InstrumentID($0) }, quantity: decimal(row, "quantity"),
                price: decimal(row, "price"), currency: text(row, "currency").map { CurrencyCode($0) },
                amount: decimal(row, "amount"), fees: decimal(row, "fees"), tax: decimal(row, "tax"),
                cost: decimal(row, "cost"), ratio: decimal(row, "ratio"), note: text(row, "note"),
                source: text(row, "source").map { DataSource($0) },
                settlement: text(row, "settlement").map { TradeSettlement($0) }))
        }
        for row in try table("lines.csv") {
            library.upsert(BankLine(
                account: AccountID(try #require(text(row, "account"))), date: try date(row, "date"),
                id: BankLineID(try #require(text(row, "id"))), amount: try #require(decimal(row, "amount")),
                text: text(row, "text") ?? "", statementClass: StatementClass(try #require(text(row, "class"))),
                otherAccount: text(row, "other_account").map { AccountID($0) }, note: text(row, "note"),
                removed: text(row, "removed") == "yes" ? true : nil,
                confirmed: text(row, "confirmed") == "yes" ? true : nil,
                source: text(row, "source").map { DataSource($0) }))
        }
        for row in try table("prices.csv") {
            library.upsert(PriceRecord(
                instrument: InstrumentID(try #require(text(row, "instrument"))), date: try date(row, "date"),
                price: try #require(decimal(row, "price")), currency: CurrencyCode(try #require(text(row, "currency"))),
                source: text(row, "source").map { DataSource($0) }))
        }
        for row in try table("fx.csv") {
            library.upsert(FXRecord(
                base: CurrencyCode(try #require(text(row, "base"))), quote: CurrencyCode(try #require(text(row, "quote"))),
                date: try date(row, "date"), rate: try #require(decimal(row, "rate")),
                source: text(row, "source").map { DataSource($0) }))
        }
        for row in try table("inflation.csv") {
            library.upsert(IndexRecord(
                index: IndexID(try #require(text(row, "index"))), date: try date(row, "date"),
                value: try #require(decimal(row, "value")), source: text(row, "source").map { DataSource($0) }))
        }
        return library
    }

    /// The savings rate of each month and year, and what each check-in saved.
    private func readings(_ library: Library) -> [String] {
        let valuator = Valuator(library: library)
        let dates = valuator.checkInDates(in: .netWorth)
        guard let end = dates.last else { return [] }
        var readings: [String] = []
        for grain in PeriodGrain.allCases {
            for period in valuator.moneyInOutSeries(grain, through: end).periods {
                readings.append("\(period.from) came in \(period.cameIn) saved \(period.saved) "
                    + "rate \(period.rate.map { "\($0)" } ?? "-")")
            }
        }
        for (from, to) in zip(dates, dates.dropFirst()) {
            let moved = valuator.whatMoved(valuator.change(from: from, to: to))
            readings.append("\(from)…\(to) saved \(moved.saved) markets \(moved.markets) other \(moved.other)")
        }
        return readings
    }

    @Test(arguments: InvariantLibrary.allCases)
    func theExportReadBackGivesTheSameNumbers(_ which: InvariantLibrary) throws {
        let library = try which.library()
        let end = try #require(Valuator(library: library).checkInDates().last)
        let files = CSVExport.files(of: library, through: end)
        let fresh = try self.library(from: files)
        let again = CSVExport.files(of: fresh, through: end)
        #expect(again.map(\.name) == files.map(\.name))
        for (file, read) in zip(files, again) {
            #expect(read.text == file.text, "\(file.name)")
        }
        #expect(readings(fresh) == readings(library))
    }
}
