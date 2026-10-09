import ArgumentParser
import Foundation
import Model
import Prices

// `retire prices --fill-history [--dry-run]`: fills in the prices, FX rates
// and inflation months the library is missing on past dates, a range per
// instrument at a time, and writes them without replacing any record.

extension PricesCommand {
    /// The backup label of a fill.
    static let fillBackupLabel = "fill-history"

    func runFillHistory(in context: CLIContext) async throws {
        let loaded = try options.load(in: context)
        let today = context.today
        let service = PriceService.standard(client: context.httpClient, credentials: context.credentials,
                                            today: { today })
        let needs = service.pastPriceNeeds(for: loaded.library)
        var report = FillReport(needs: needs, dryRun: dryRun)
        if !needs.isEmpty {
            let fill = await service.fillPastPrices(needs, in: loaded.library)
            report.fill = fill
            report.written = try writeFill(fill, loaded: loaded, context: context)
        }
        try context.console.print(report, json: json)
        if report.hasFailures { throw ExitCode.failure }
    }

    /// Adds the fetched records the library doesn't have (all of them, unless
    /// something arrived meanwhile), after backing up the month files they
    /// change, and records the result in the backup. With `--dry-run`, only
    /// says which files would change.
    private func writeFill(_ fill: PastPriceFill, loaded: LoadedLibrary,
                           context: CLIContext) throws -> FillReport.Written {
        var library = loaded.library
        let inserted = fill.insertMissing(into: &library)
        let saved = try loaded.save(library, backupLabel: Self.fillBackupLabel, dryRun: dryRun, in: context)
        let isWritten = saved.backup != nil
        return FillReport.Written(inserted: inserted, files: isWritten ? saved.written : saved.changed,
                                  backup: saved.backup, isWritten: isWritten)
    }

    /// What was missing, what was fetched from where, and what was written.
    struct FillReport: CommandReport {
        /// What was written, or with `--dry-run`, what would be.
        struct Written {
            var inserted: PastPriceInsertion
            /// The files changed, relative to the library folder.
            var files: [String]
            var backup: String?
            var isWritten = false
        }

        let needs: PastPriceNeeds
        let dryRun: Bool
        var fill: PastPriceFill?
        var written: Written?

        var base: CurrencyCode { needs.baseCurrency }

        /// Whether a price or rate that has a source couldn't be filled.
        /// (Prices typed in by hand, and index months not published yet,
        /// aren't failures.)
        var hasFailures: Bool {
            guard let fill else { return false }
            return fill.results.contains { result in
                switch result.item {
                case .instrument, .fx: result.status == .notFilled || result.status == .partlyFilled
                case .index: false
                }
            }
        }

        func lines() -> [String] {
            var lines = needsLines()
            guard let fill, !fill.results.isEmpty else { return lines }
            lines.append("")
            var table = TextTable([.left("Item"), .right("Needed"), .right("Filled"), .left("From"), .left("Dates"),
                                   .left("Status")])
            for result in fill.results {
                let runs = result.sources
                table.add([result.item.description, "\(result.needed.count)", "\(result.filled.count)",
                           runs.first.map { $0.origin.description } ?? "",
                           runs.first.map { Format.range($0.first, $0.last) } ?? "", Self.status(result)])
                for run in runs.dropFirst() {
                    table.add(["", "", "", run.origin.description, Format.range(run.first, run.last), ""])
                }
            }
            lines += table.lines()

            let unfilled = fill.results.filter { !$0.missing.isEmpty }
            if !unfilled.isEmpty {
                lines.append("")
                lines.append("Not filled (type these in, or give the instrument a price source)")
                for result in unfilled {
                    let missing = result.missing
                    let dates = missing.count == 1 ? "\(missing[0])"
                        : "\(missing.count) dates, \(Format.range(missing[0], missing[missing.count - 1]))"
                    lines.append("  \(result.item) (\(dates)): \(result.reason ?? "no value")")
                }
            }
            if let written {
                lines.append("")
                lines += writtenLines(written)
            }
            return lines
        }

        private func needsLines() -> [String] {
            var parts: [String] = []
            if needs.priceCount > 0 {
                parts.append(Format.count(needs.priceCount, "price") + " ("
                    + needs.instruments.map(\.instrument.rawValue).joined(separator: ", ") + ")")
            }
            if needs.rateCount > 0 {
                parts.append(Format.count(needs.rateCount, "FX rate") + " ("
                    + needs.rates.map { "\(base)/\($0.quote)" }.joined(separator: ", ") + ")")
            }
            for index in needs.indices {
                let months = index.months
                parts.append("\(index.index) for \(Format.range(months[0], months[months.count - 1]))")
            }
            let manual = needs.manualInstruments + needs.unknownInstruments
            guard !parts.isEmpty || !manual.isEmpty else {
                return ["Up to \(needs.today), the library has every past price, FX rate and index value it needs."]
            }
            var lines: [String] = []
            if !parts.isEmpty {
                lines.append("Up to \(needs.today), the library is missing " + Format.list(parts) + ".")
            }
            if !manual.isEmpty {
                lines.append("Without a price source: " + Format.count(needs.manualPriceCount, "price") + " ("
                    + manual.map(\.instrument.rawValue).joined(separator: ", ") + ").")
            }
            return lines
        }

        private func writtenLines(_ written: Written) -> [String] {
            let count = written.inserted.added
            guard count > 0 else {
                return [fill?.recordCount == 0 ? "Nothing was fetched, so nothing was written."
                    : "The library has these records by now; nothing was written."]
            }
            let records = Format.count(count, "record")
            let files = Self.files(written.files)
            var lines: [String] = []
            if written.isWritten {
                lines.append("Added \(records) to \(files).")
            } else {
                lines.append("Dry run: nothing was written. It would add \(records) to \(files). "
                    + "To write them, run again without --dry-run.")
            }
            if written.inserted.kept > 0 {
                lines.append("Kept \(Format.count(written.inserted.kept, "record")) the library had by then.")
            }
            if let backup = written.backup { lines.append("Backed up the files it changed to \(backup).") }
            return lines
        }

        /// "history/2025/2025-10.json", or the first three and how many more.
        static func files(_ files: [String]) -> String {
            guard files.count > 3 else { return Format.list(files) }
            return files.prefix(3).joined(separator: ", ") + " and \(files.count - 3) more files"
        }

        static func status(_ result: PastPriceResult) -> String {
            switch result.status {
            case .filled: "filled"
            case .partlyFilled: "partly filled"
            case .notFilled: "not filled"
            case .manual: "no price source"
            case .unknownInstrument: "unknown instrument"
            }
        }

        // MARK: JSON

        var json: JSON {
            JSON(
                today: needs.today.description, baseCurrency: base.rawValue, dryRun: dryRun,
                needs: JSON.Needs(prices: needs.priceCount, manualPrices: needs.manualPriceCount, rates: needs.rateCount,
                                  indexMonths: needs.indexMonthCount),
                results: (fill?.results ?? []).map { result in
                    JSON.Result(
                        item: result.item.description, status: Self.status(result), needed: result.needed.count,
                        filled: result.filled.count, missing: result.missing.map(\.description),
                        sources: result.sources.map {
                            JSON.Source(source: $0.origin.source.rawValue, service: $0.origin.service,
                                        symbol: $0.origin.symbol, note: $0.origin.note, first: $0.first.description,
                                        last: $0.last.description, count: $0.count)
                        },
                        observedEarlier: Dictionary(
                            result.observedOn.filter { $0.key != $0.value }.map { ($0.key.description, $0.value.description) },
                            uniquingKeysWith: { first, _ in first }),
                        reason: result.reason)
                },
                prices: fill?.prices ?? [], fx: fill?.fx ?? [], indices: fill?.indices ?? [],
                written: written.map {
                    JSON.Written(added: $0.inserted.added, kept: $0.inserted.kept, files: $0.files, backup: $0.backup,
                                 isWritten: $0.isWritten)
                })
        }

        struct JSON: Encodable {
            struct Needs: Encodable {
                var prices: Int
                var manualPrices: Int
                var rates: Int
                var indexMonths: Int
            }

            struct Source: Encodable {
                var source: String
                var service: String
                var symbol: String
                var note: String?
                var first: String
                var last: String
                var count: Int
            }

            struct Result: Encodable {
                var item: String
                var status: String
                var needed: Int
                var filled: Int
                var missing: [String]
                var sources: [Source]
                /// The dates whose value is from an earlier day, and that
                /// day: `{"2025-11-30": "2025-11-28"}`.
                var observedEarlier: [String: String]
                var reason: String?
            }

            struct Written: Encodable {
                var added: Int
                var kept: Int
                var files: [String]
                var backup: String?
                var isWritten: Bool
            }

            var today: String
            var baseCurrency: String
            var dryRun: Bool
            var needs: Needs
            var results: [Result]
            /// The fetched records, as in the library's month files.
            var prices: [PriceRecord]
            var fx: [FXRecord]
            var indices: [IndexRecord]
            var written: Written?
        }
    }
}
