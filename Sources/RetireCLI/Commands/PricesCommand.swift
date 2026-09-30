import ArgumentParser
import Foundation
import Model
import Prices
import Storage

/// `retire prices`: fetches what a check-in needs and optionally records it.
struct PricesCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "prices",
        abstract: "Fetch the prices, FX rates and inflation figures a check-in needs.",
        discussion: """
            Works out what a check-in on the date needs: a price for every instrument held, \
            an FX rate for every other currency, and the inflation-index months the library is \
            missing. It fetches them (Yahoo Finance, CoinGecko, gold-api.com, the ECB through \
            Frankfurter, Eurostat) and prints the price list with sources and failures. Only \
            symbols, currencies and dates are sent. With --apply, the fetched records are \
            written to the library, after a backup. Set \(CLIContext.coinGeckoKeyVariable) to \
            use a CoinGecko demo API key. Exits with status 1 when something couldn't be fetched.

            With --fill-history, it fills in the past instead: every date the library values \
            a position on without a price for that day (valuations, and the month ends they \
            carry over to), the FX rates those dates need and the missing inflation months. \
            Each instrument's whole range is one request (gold from Yahoo Finance's GC=F \
            futures, crypto older than CoinGecko's free year from Yahoo's pairs), then one per \
            currency and index. The records are written after a backup, never replacing one \
            the library has; --dry-run fetches and shows what would be written. Exits with \
            status 1 when a price or rate with a source couldn't be filled.
            """)

    @OptionGroup var options: LibraryOptions

    @Option(help: ArgumentHelp("The check-in date, YYYY-MM-DD. Default: today.", valueName: "date"))
    var date: String?

    @Flag(help: "Write the fetched records into the library.")
    var apply = false

    @Flag(help: "With --apply, replace records the library already has for the date with different values.")
    var overwrite = false

    @Flag(help: "Fill in the prices, FX rates and inflation months missing on past dates, and write them.")
    var fillHistory = false

    @Flag(help: "With --fill-history, fetch and show what would be written, but write nothing.")
    var dryRun = false

    @Flag(help: "Print JSON.")
    var json = false

    func validate() throws {
        _ = try parseDate(date, option: "--date")
        if fillHistory {
            if date != nil { throw ValidationError("--fill-history fills every past date; it takes no --date.") }
            if apply {
                throw ValidationError("--fill-history writes unless you pass --dry-run; it takes no --apply.")
            }
            if overwrite { throw ValidationError("--fill-history never replaces a record; it takes no --overwrite.") }
        } else {
            if overwrite, !apply { throw ValidationError("--overwrite needs --apply.") }
            if dryRun { throw ValidationError("--dry-run goes with --fill-history.") }
        }
    }

    mutating func run() async throws {
        try await run(in: .live())
    }

    func run(in context: CLIContext) async throws {
        if fillHistory {
            try await runFillHistory(in: context)
            return
        }
        let loaded = try options.load(in: context)
        let date = try parseDate(date, option: "--date") ?? context.today
        let today = context.today
        let service = PriceService.standard(client: context.httpClient, credentials: context.credentials,
                                            today: { today })
        let needs = service.needs(for: loaded.library, on: date)
        let fetched = await service.fetch(needs)
        var report = Report(library: loaded.library, needs: needs, fetched: fetched)
        if apply {
            report.applied = try write(fetched, loaded: loaded, context: context)
        }
        if json {
            context.console.print(try JSONOutput.string(report.json))
        } else {
            context.console.print(lines: report.lines())
        }
        if !fetched.failures.isEmpty { throw ExitCode.failure }
    }

    /// Adds the fetched records to the library: new ones, and different ones
    /// only with `--overwrite`. Backs up the month files first.
    private func write(_ fetched: CheckInPrices, loaded: LoadedLibrary, context: CLIContext) throws -> Applied {
        var library = loaded.library
        var applied = Applied()
        func consider<Record: Equatable>(_ record: Record, existing: Record?, upsert: (Record) -> Void) {
            guard let existing else {
                applied.added += 1
                upsert(record)
                return
            }
            if existing == record {
                applied.identical += 1
            } else if overwrite {
                applied.replaced += 1
                upsert(record)
            } else {
                applied.kept += 1
            }
        }
        for price in fetched.prices {
            consider(price, existing: library.months[price.date.yearMonth]?.prices.first { $0.key == price.key }) {
                library.upsert($0)
            }
        }
        for rate in fetched.fx {
            consider(rate, existing: library.months[rate.date.yearMonth]?.fx.first { $0.key == rate.key }) {
                library.upsert($0)
            }
        }
        for value in fetched.indices {
            consider(value, existing: library.months[value.date.yearMonth]?.indices.first { $0.key == value.key }) {
                library.upsert($0)
            }
        }
        let changed = Set(library.months.keys).filter { library.months[$0] != loaded.library.months[$0] }.sorted()
        guard !changed.isEmpty else { return applied }
        try loaded.checkWritable()
        let backup = try loaded.folder.backup(paths: changed.map { LibraryFile.month($0).path }, label: "prices",
                                              date: context.now())
        applied.backup = backup.path
        applied.written = try loaded.folder.save(library, previous: loaded.library).written
        return applied
    }

    /// What `--apply` wrote.
    struct Applied {
        var added = 0
        var replaced = 0
        /// Records the library has with other values, kept without `--overwrite`.
        var kept = 0
        var identical = 0
        var written: [String] = []
        var backup: String?
    }

    /// The price list and what was written.
    struct Report {
        let library: Library
        let needs: CheckInPriceNeeds
        let fetched: CheckInPrices
        var applied: Applied?

        var date: CalendarDate { needs.date }

        func needsLines() -> [String] {
            var parts: [String] = []
            let instruments = needs.instruments.map(\.id.rawValue) + needs.manualInstruments.map(\.rawValue)
            if !instruments.isEmpty {
                parts.append(Format.count(instruments.count, "price") + " (\(instruments.sorted().joined(separator: ", ")))")
            }
            if !needs.currencies.isEmpty {
                parts.append(Format.count(needs.currencies.count, "FX rate") + " ("
                    + needs.currencies.map { "\(needs.baseCurrency)/\($0)" }.joined(separator: ", ") + ")")
            }
            for index in needs.indices where !index.months.isEmpty {
                let months = index.months
                let range = months.count == 1 ? "\(months[0])" : "\(months[0]) to \(months[months.count - 1])"
                parts.append("\(index.index) for \(range)")
            }
            guard !parts.isEmpty else { return ["A check-in on \(date) needs nothing fetched."] }
            return ["A check-in on \(date) needs " + Format.list(parts) + "."]
        }

        func lines() -> [String] {
            var lines = needsLines()
            guard !fetched.entries.isEmpty else { return lines }
            lines.append("")
            lines.append("Price list")
            var table = TextTable([.left("Item"), .right("Value"), .left("Per"), .left("Source"), .left("Symbol"),
                                   .left("As of"), .left("Status")])
            for entry in fetched.entries {
                let (value, per) = valueText(entry)
                table.add([entry.item.description, value, per, entry.source?.rawValue ?? "", entry.symbol ?? "",
                           entry.details?.observedOn?.description ?? "", status(entry)])
            }
            lines += table.lines()

            let failures = fetched.failures
            if !failures.isEmpty {
                lines.append("")
                lines.append("Couldn't fetch (enter these by hand in the check-in)")
                lines += failures.map { "  \($0.item): \($0.failureReason ?? "")" }
            }
            if let applied {
                lines.append("")
                lines += appliedLines(applied)
            } else if !fetched.prices.isEmpty || !fetched.fx.isEmpty || !fetched.indices.isEmpty {
                lines.append("")
                lines.append("Nothing was written. To record these in the library, run again with --apply.")
            }
            return lines
        }

        private func appliedLines(_ applied: Applied) -> [String] {
            var lines: [String] = []
            if applied.added + applied.replaced + applied.kept + applied.identical == 0 {
                lines.append("Nothing was fetched, so nothing was written.")
            } else if applied.written.isEmpty {
                lines.append(applied.kept > 0 ? "Nothing was written."
                    : "The library already has these records; nothing was written.")
            } else {
                lines.append("Recorded \(Format.count(applied.added, "new record"))"
                    + (applied.replaced > 0 ? ", replaced \(applied.replaced)" : "") + " in "
                    + Format.list(applied.written) + ".")
            }
            if applied.kept > 0 {
                lines.append("Kept \(Format.count(applied.kept, "record")) the library already has with other values; "
                    + "pass --overwrite to replace them.")
            }
            if let backup = applied.backup { lines.append("Backed up the files it changed to \(backup).") }
            return lines
        }

        /// The fetched value and what it's per: `138.42` `EUR/share`, `1.1398` `USD per EUR`.
        private func valueText(_ entry: PriceListEntry) -> (String, String) {
            switch entry.item {
            case .instrument(let id):
                guard let price = fetched.prices.first(where: { $0.instrument == id }) else { return ("", "") }
                let unit = library.instruments[id]?.unit.rawValue ?? ""
                return (Format.exact(price.price), "\(price.currency)/\(unit)")
            case .fx(let base, let quote):
                guard let rate = fetched.fx.first(where: { $0.base == base && $0.quote == quote }) else { return ("", "") }
                return (Format.exact(rate.rate), "\(quote) per \(base)")
            case .index(let index):
                let values = fetched.indices.filter { $0.index == index }
                guard let last = values.last else { return ("", "") }
                return (Format.exact(last.value), values.count == 1 ? "\(last.date.yearMonth)"
                            : "\(last.date.yearMonth), \(values.count) months")
            }
        }

        private func status(_ entry: PriceListEntry) -> String {
            switch entry.outcome {
            case .fetched(let details):
                if case .index(let index) = entry.item, !fetched.indices.contains(where: { $0.index == index }) {
                    return "not published yet"
                }
                if let quote = details.quote, case .instrument(let id) = entry.item,
                   let instrument = library.instruments[id],
                   quote.currency != instrument.currency || (quote.unit.map { $0 != instrument.unit } ?? false) {
                    return "converted from \(Format.exact(quote.price)) \(quote.currency)/\(quote.unit?.rawValue ?? "")"
                }
                return "fetched"
            case .manual: return "enter by hand (no price source)"
            case .failed: return "failed"
            }
        }

        // MARK: JSON

        var json: JSON {
            JSON(
                date: date.description, baseCurrency: needs.baseCurrency.rawValue,
                needs: JSON.Needs(
                    instruments: needs.instruments.map(\.id.rawValue), manual: needs.manualInstruments.map(\.rawValue),
                    unknown: needs.unknownInstruments.map(\.rawValue), currencies: needs.currencies.map(\.rawValue),
                    indices: needs.indices.filter { !$0.months.isEmpty }.map {
                        JSON.IndexNeed(index: $0.index.rawValue, months: $0.months.map(\.description))
                    }),
                entries: fetched.entries.map { entry in
                    let status: String = switch entry.outcome {
                    case .fetched: "fetched"
                    case .manual: "manual"
                    case .failed: "failed"
                    }
                    return JSON.Entry(item: entry.item.description, source: entry.source?.rawValue,
                                      symbol: entry.symbol, status: status,
                                      observedOn: entry.details?.observedOn?.description,
                                      reason: entry.failureReason)
                },
                prices: fetched.prices.map {
                    JSON.Price(instrument: $0.instrument.rawValue, date: $0.date.description, price: $0.price.fileString,
                               currency: $0.currency.rawValue, source: $0.source?.rawValue)
                },
                fx: fetched.fx.map {
                    JSON.Rate(base: $0.base.rawValue, quote: $0.quote.rawValue, date: $0.date.description,
                              rate: $0.rate.fileString, source: $0.source?.rawValue)
                },
                indices: fetched.indices.map {
                    JSON.IndexValue(index: $0.index.rawValue, date: $0.date.description, value: $0.value.fileString,
                                    source: $0.source?.rawValue)
                },
                applied: applied.map {
                    JSON.Applied(added: $0.added, replaced: $0.replaced, kept: $0.kept, identical: $0.identical,
                                 written: $0.written, backup: $0.backup)
                })
        }

        struct JSON: Encodable {
            struct IndexNeed: Encodable {
                var index: String
                var months: [String]
            }

            struct Needs: Encodable {
                var instruments: [String]
                var manual: [String]
                var unknown: [String]
                var currencies: [String]
                var indices: [IndexNeed]
            }

            struct Entry: Encodable {
                var item: String
                var source: String?
                var symbol: String?
                var status: String
                var observedOn: String?
                var reason: String?
            }

            struct Price: Encodable {
                var instrument: String
                var date: String
                var price: String
                var currency: String
                var source: String?
            }

            struct Rate: Encodable {
                var base: String
                var quote: String
                var date: String
                var rate: String
                var source: String?
            }

            struct IndexValue: Encodable {
                var index: String
                var date: String
                var value: String
                var source: String?
            }

            struct Applied: Encodable {
                var added: Int
                var replaced: Int
                var kept: Int
                var identical: Int
                var written: [String]
                var backup: String?
            }

            var date: String
            var baseCurrency: String
            var needs: Needs
            var entries: [Entry]
            var prices: [Price]
            var fx: [Rate]
            var indices: [IndexValue]
            var applied: Applied?
        }
    }
}
