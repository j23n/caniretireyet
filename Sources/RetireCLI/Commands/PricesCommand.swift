import ArgumentParser
import Foundation
import Model
import Prices

/// `retire prices`: fetches what a check-in needs and optionally records it.
struct PricesCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "prices",
        abstract: "Fetch the prices, FX rates and inflation figures a check-in needs.",
        discussion: """
            Works out what a check-in on the date needs: a price for every instrument held, \
            an FX rate for every other currency (those of accounts and instruments), and the \
            months missing of the library's inflation index (by default the tax residence's \
            HICP or CPI: see retire settings). It fetches them (Yahoo Finance, also for crypto, \
            gold-api.com, the ECB through Frankfurter, and Eurostat, the BLS or the ONS) and prints \
            the price list with sources and failures. Only symbols, currencies and dates are sent. \
            With --apply, the fetched records are written to the library, after a backup. Exits with \
            status 1 when something couldn't be fetched.

            With --fill-history, it fills in the past instead: every date the library values \
            a position on without a price for that day (valuations, and the month ends they \
            carry over to), the FX rates those dates need and the missing inflation months. \
            Each instrument's whole range is one request (gold's past prices from Yahoo \
            Finance's GC=F futures), then one per currency and index. The records are written after a backup, never replacing one \
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

    func run(in context: CLIContext) async throws {
        if fillHistory {
            try await runFillHistory(in: context)
            return
        }
        let loaded = try options.load(in: context)
        let date = try parseDate(date, option: "--date") ?? context.today
        let today = context.today
        let service = PriceService.standard(client: context.httpClient, today: { today })
        let needs = service.needs(for: loaded.library, on: date)
        let fetched = await service.fetch(needs, in: loaded.library)
        var report = Report(library: loaded.library, needs: needs, fetched: fetched)
        if apply {
            report.applied = try write(fetched, loaded: loaded, context: context)
        }
        try context.console.print(report, json: json)
        if !fetched.failures.isEmpty { throw ExitCode.failure }
    }

    /// Adds the fetched records to the library: new ones, and different ones
    /// only with `--overwrite`. Backs up the month files first, and records
    /// the result in the backup.
    private func write(_ fetched: FetchedPrices, loaded: LoadedLibrary, context: CLIContext) throws -> Applied {
        var library = loaded.library
        let merge = fetched.merge(into: &library, policy: overwrite ? .replaceAll : .keepExisting)
        var applied = Applied(added: merge.added, replaced: merge.replaced, kept: merge.kept,
                              identical: merge.identical)
        let saved = try loaded.save(library, backupLabel: "prices", in: context)
        applied.written = saved.written
        applied.backup = saved.backup
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
    struct Report: CommandReport {
        let library: Library
        let needs: PriceNeeds
        let fetched: FetchedPrices
        var applied: Applied?

        var date: CalendarDate { needs.date }

        func needsLines() -> [String] {
            var parts: [String] = []
            let instruments = (needs.instruments + needs.manualInstruments).map(\.instrument.rawValue)
            if !instruments.isEmpty {
                parts.append(Wording.count(instruments.count, "price")
                    + " (\(instruments.sorted().joined(separator: ", ")))")
            }
            if !needs.rates.isEmpty {
                parts.append(Wording.count(needs.rates.count, "FX rate") + " ("
                    + needs.rates.map { "\(needs.baseCurrency)/\($0.quote)" }.joined(separator: ", ") + ")")
            }
            for index in needs.indices {
                let months = index.months
                parts.append("\(index.index) for \(Format.range(months[0], months[months.count - 1]))")
            }
            guard !parts.isEmpty else { return ["A check-in on \(date) needs nothing fetched."] }
            return ["A check-in on \(date) needs " + Wording.list(parts) + "."]
        }

        func lines() -> [String] {
            var lines = needsLines()
            guard !fetched.results.isEmpty else { return lines }
            lines.append("")
            lines.append("Price list")
            var table = TextTable([.left("Item"), .right("Value"), .left("Per"), .left("Source"), .left("Symbol"),
                                   .left("As of"), .left("Status")])
            for result in fetched.results {
                let (value, per) = valueText(result)
                let origin = result.shownOrigin
                // A stand-in for a date the source has no price for: "GC=F (history)".
                let symbol = origin.map { origin in origin.note.map { "\(origin.symbol) (\($0))" } ?? origin.symbol } ?? ""
                table.add([result.item.description, value, per, origin?.source.rawValue ?? "", symbol,
                           result.asOf?.description ?? "", status(result)])
            }
            lines += table.lines()

            let failures = fetched.failures
            if !failures.isEmpty {
                lines.append("")
                lines.append("Couldn't fetch (enter these by hand in the check-in)")
                lines += failures.map { "  \($0.item): \($0.reason ?? "")" }
            }
            if let applied {
                lines.append("")
                lines += appliedLines(applied)
            } else if fetched.recordCount > 0 {
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
                lines.append("Recorded \(Wording.count(applied.added, "new record"))"
                    + (applied.replaced > 0 ? ", replaced \(applied.replaced)" : "") + " in "
                    + Wording.list(applied.written) + ".")
            }
            if applied.kept > 0 {
                lines.append("Kept \(Wording.count(applied.kept, "record")) the library already has with other values; "
                    + "pass --overwrite to replace them.")
            }
            if let backup = applied.backup { lines.append("Backed up the files it changed to \(backup).") }
            return lines
        }

        /// The fetched value and what it's per: `138.42` `EUR/share`, `1.1398` `USD per EUR`.
        private func valueText(_ result: PriceResult) -> (String, String) {
            switch result.item {
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

        private func status(_ result: PriceResult) -> String {
            if result.status == .manual { return "enter by hand (no price source)" }
            if result.isFailure { return "failed" }
            if case .index(let index) = result.item, !fetched.indices.contains(where: { $0.index == index }) {
                return "not published yet"
            }
            if case .instrument(let id) = result.item, let quote = result.quotes[date],
               let instrument = library.instruments[id],
               quote.currency != instrument.currency || (quote.unit.map { $0 != instrument.unit } ?? false) {
                return "converted from \(Format.exact(quote.price)) \(quote.currency)/\(quote.unit?.rawValue ?? "")"
            }
            return "fetched"
        }

        // MARK: JSON

        var json: JSON {
            JSON(
                date: date.description, baseCurrency: needs.baseCurrency.rawValue,
                needs: JSON.Needs(
                    instruments: needs.instruments.map(\.instrument.rawValue),
                    manual: needs.manualInstruments.map(\.instrument.rawValue),
                    unknown: needs.unknownInstruments.map(\.instrument.rawValue),
                    currencies: needs.rates.map(\.quote.rawValue),
                    indices: needs.indices.map {
                        JSON.IndexNeed(index: $0.index.rawValue, months: $0.months.map(\.description))
                    }),
                entries: fetched.results.map { result in
                    let status = result.status == .manual ? "manual" : result.isFailure ? "failed" : "fetched"
                    let origin = result.shownOrigin
                    return JSON.Entry(item: result.item.description, source: origin?.source.rawValue,
                                      symbol: origin?.symbol, note: origin?.note, status: status,
                                      observedOn: result.asOf?.description, reason: result.failureReason)
                },
                prices: fetched.prices, fx: fetched.fx, indices: fetched.indices,
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
                /// `history` for a stand-in source, e.g. gold's futures on a past date.
                var note: String?
                var status: String
                var observedOn: String?
                var reason: String?
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
            /// The fetched records, as in the library's month files.
            var prices: [PriceRecord]
            var fx: [FXRecord]
            var indices: [IndexRecord]
            var applied: Applied?
        }
    }
}
