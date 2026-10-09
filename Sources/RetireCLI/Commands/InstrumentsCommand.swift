import ArgumentParser
import Foundation
import Model
import Storage

/// `retire instruments`: the library's instruments.
struct InstrumentsGroupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "instruments",
        abstract: "List the library's instruments.",
        subcommands: [InstrumentsListCommand.self],
        defaultSubcommand: InstrumentsListCommand.self)
}

/// `retire instruments list`.
struct InstrumentsListCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List the instruments: kind, currency, asset mix and price source (the default).")

    @OptionGroup var options: LibraryOptions

    @Flag(help: "Print JSON.")
    var json = false

    func run(in context: CLIContext) async throws {
        let loaded = try options.load(in: context)
        let instruments = loaded.library.instruments.values.sorted { $0.id < $1.id }
        if json {
            struct Row: Encodable {
                var id: String
                var name: String
                var kind: String
                var currency: String
                var assetClasses: [String: String]
                var priceSource: String?
            }
            context.console.print(try JSONOutput.string(instruments.map { instrument in
                Row(id: instrument.id.rawValue, name: instrument.name, kind: instrument.kind.rawValue,
                    currency: instrument.currency.rawValue,
                    assetClasses: Dictionary(uniqueKeysWithValues: instrument.assetClasses.shares.map {
                        ($0.key.rawValue, $0.value.fileString)
                    }),
                    priceSource: instrument.priceSource.map { "\($0.provider.rawValue):\($0.symbol)" })
            }))
            return
        }
        guard !instruments.isEmpty else {
            context.console.print("The library has no instruments yet.")
            return
        }
        var table = TextTable([.left("ID"), .left("Name"), .left("Kind"), .left("Currency"), .left("Asset mix"),
                               .left("Price source")])
        for instrument in instruments {
            let mix = instrument.assetClasses.assetClasses.map { assetClass in
                "\(assetClass) \(Format.percent(instrument.assetClasses[assetClass], places: 0))"
            }.joined(separator: ", ")
            table.add([instrument.id.rawValue, instrument.name, instrument.kind.rawValue,
                       instrument.currency.rawValue, mix,
                       instrument.priceSource.map { "\($0.provider.rawValue) · \($0.symbol)" } ?? "by hand"])
        }
        context.console.print(lines: table.lines(indent: 0))
    }
}
