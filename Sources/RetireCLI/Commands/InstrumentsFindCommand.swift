import ArgumentParser
import Foundation
import Model
import Prices

/// `retire instruments find <instrument>`: searches Yahoo Finance for
/// listings of the instrument, and with `--set` makes one its price source.
struct InstrumentsFindCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "find",
        abstract: "Find Yahoo Finance listings to price an instrument from, and set one as its price source.",
        discussion: """
            Searches Yahoo Finance by the instrument's ISIN, else its ticker, else its name (or by \
            --query), and lists what it finds: symbol, exchange, kind, currency and name. The one \
            marked * is the first in the instrument's currency, which the app preselects. Only the \
            query leaves this device. --set <symbol> makes a listing found the instrument's price \
            source (yahoo); the instrument's file is written after a backup (--dry-run shows the \
            change). Then `retire prices` fetches its price.
            """)

    @Argument(help: ArgumentHelp("The instrument's ID.", valueName: "instrument"))
    var instrument: String

    @OptionGroup var options: LibraryOptions

    @Option(help: ArgumentHelp("Search for this instead of the ISIN, ticker or name.", valueName: "text"))
    var query: String?

    @Option(name: .customLong("set"),
            help: ArgumentHelp("Make this listing's symbol the price source.", valueName: "symbol"))
    var setSymbol: String?

    @Flag(help: "With --set, show what would change; write nothing.")
    var dryRun = false

    @Flag(help: "Print JSON.")
    var json = false

    func validate() throws {
        if dryRun, setSymbol == nil { throw ValidationError("--dry-run goes with --set.") }
        if let query, query.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("--query can't be empty.")
        }
    }

    func run(in context: CLIContext) async throws {
        let loaded = try options.load(in: context)
        guard let found = loaded.library.instruments[InstrumentID(instrument)] else {
            let known = loaded.library.instruments.keys.map(\.rawValue).sorted()
            throw CLIError("There's no instrument \"\(instrument)\"."
                + (known.isEmpty ? "" : " Instruments: \(known.joined(separator: ", ")).")))
        }
        guard let query = query?.trimmingCharacters(in: .whitespaces) ?? YahooSymbolSearch.query(for: found) else {
            throw CLIError("\(found.id) has no ISIN, ticker or name to search for: pass --query <text>.")
        }
        let candidates: [SymbolCandidate]
        do {
            candidates = try await YahooSymbolSearch(client: context.httpClient).search(query)
        } catch let error as PriceFetchError {
            throw CLIError(error.description)
        }
        var report = Report(instrument: found, query: query, candidates: candidates,
                            preferred: SymbolCandidate.preferred(among: candidates, currency: found.currency))
        if let setSymbol {
            let wanted = setSymbol.trimmingCharacters(in: .whitespaces)
            guard let chosen = candidates.first(where: { $0.symbol.caseInsensitiveCompare(wanted) == .orderedSame })
            else {
                throw CLIError("\"\(wanted)\" isn't among the listings found for \"\(query)\". "
                    + "To search for it, pass --query \(wanted).")
            }
            var library = loaded.library
            library.instruments[found.id]?.priceSource = chosen.priceSource
            let saved = try loaded.save(library, backupLabel: "instruments", dryRun: dryRun, in: context)
            report.change = Report.Change(source: chosen.priceSource, dryRun: dryRun, saved: saved)
        }
        try context.console.print(report, json: json)
    }

    /// The listings found and, with `--set`, what was written.
    struct Report: CommandReport {
        /// The price source set, and the files written or with `--dry-run`
        /// that would be.
        struct Change {
            var source: PriceSource
            var dryRun: Bool
            var saved: SavedChanges
        }

        let instrument: Instrument
        let query: String
        let candidates: [SymbolCandidate]
        let preferred: SymbolCandidate?
        var change: Change?

        static func sourceText(_ source: PriceSource?) -> String {
            source.map { "\($0.provider.rawValue) · \($0.symbol)" } ?? "none (prices are typed in by hand)"
        }

        func lines() -> [String] {
            var lines = ["\(instrument.id): \(instrument.name), in \(instrument.currency)",
                         "Price source: \(Self.sourceText(instrument.priceSource))", ""]
            guard !candidates.isEmpty else {
                lines.append("Yahoo Finance found nothing for \"\(query)\". Try --query with its ticker or name.")
                return lines
            }
            lines.append("Yahoo Finance listings for \"\(query)\"")
            var table = TextTable([.left(""), .left("Symbol"), .left("Exchange"), .left("Kind"), .left("Currency"),
                                   .left("Name")])
            for candidate in candidates {
                table.add([candidate == preferred ? "*" : "", candidate.symbol, candidate.exchangeName ?? "",
                           candidate.quoteTypeName ?? "", candidate.likelyCurrency?.rawValue ?? "",
                           candidate.name ?? ""])
            }
            lines += table.lines()
            lines.append("")
            if preferred != nil {
                lines.append("* The first in \(instrument.currency).")
            } else {
                lines.append("None is known to trade in \(instrument.currency).")
            }
            guard let change else {
                lines.append("To price it from one, run again with --set <symbol>.")
                return lines
            }
            lines.append("")
            lines.append("New price source: \(Self.sourceText(change.source)).")
            if change.dryRun {
                lines.append("Dry run: nothing was written" + (change.saved.changed.isEmpty ? "."
                    : " (\(Wording.count(change.saved.changed.count, "file")) would change)."))
            } else if let backup = change.saved.backup {
                lines.append("Wrote \(Wording.count(change.saved.written.count, "file")): "
                    + change.saved.written.joined(separator: ", ") + ".")
                lines.append("Backed up the files it changed to \(backup).")
            } else {
                lines.append("Nothing changed.")
            }
            return lines
        }

        var json: JSON {
            JSON(instrument: instrument.id.rawValue, currency: instrument.currency.rawValue, query: query,
                 candidates: candidates.map { candidate in
                     JSON.Candidate(symbol: candidate.symbol, name: candidate.name, exchange: candidate.exchange,
                                    exchangeName: candidate.exchangeName, quoteType: candidate.quoteType,
                                    currency: candidate.likelyCurrency?.rawValue, preferred: candidate == preferred)
                 },
                 priceSource: (change?.source ?? instrument.priceSource).map { "\($0.provider.rawValue):\($0.symbol)" },
                 written: change.map { $0.dryRun ? [] : $0.saved.written },
                 dryRun: change?.dryRun)
        }

        struct JSON: Encodable {
            struct Candidate: Encodable {
                var symbol: String
                var name: String?
                var exchange: String?
                var exchangeName: String?
                var quoteType: String?
                /// The currency it most likely trades in.
                var currency: String?
                var preferred: Bool
            }

            var instrument: String
            var currency: String
            var query: String
            var candidates: [Candidate]
            /// The price source after `--set`, else the instrument's.
            var priceSource: String?
            /// With `--set`, the files written.
            var written: [String]?
            var dryRun: Bool?
        }
    }
}
