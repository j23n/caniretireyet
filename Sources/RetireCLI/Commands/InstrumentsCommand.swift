import ArgumentParser
import Foundation
import Model
import Storage

/// `retire instruments`: the library's instruments and how plans tax them
/// (a fund's type, an ETC's delivery claim), as the app's instrument editor
/// shows them.
struct InstrumentsGroupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "instruments",
        abstract: "List instruments and how plans tax them, or set a fund's type or an ETC's delivery claim.",
        discussion: """
            retire instruments [list]                      each one's kind for taxes
            retire instruments set <id> --fund-type mixed  a fund's type, or automatic
            retire instruments set <id> --delivery-claim yes   an ETC's right to metal

            Some countries tax funds by what they invest in. Without a type, plans work it out from the \
            asset mix: more than half equity is an equity fund, more than half real estate a real-estate \
            fund, a quarter or more equity a mixed fund, and anything else another fund.
            """,
        subcommands: [InstrumentsListCommand.self, InstrumentsSetCommand.self],
        defaultSubcommand: InstrumentsListCommand.self)

    /// "equity fund (from its mix)", "real-estate fund", "ETC with a delivery claim", "stock": the
    /// planner's own reading (`Instrument.effectiveFundType`, `hasDeliveryClaim`).
    static func taxKind(of instrument: Instrument) -> String {
        if let type = instrument.effectiveFundType {
            return instrument.tax?.fundType == type ? name(of: type) : name(of: type) + " (from its mix)"
        }
        if instrument.kind == .etc { return instrument.hasDeliveryClaim ? "ETC with a delivery claim" : "ETC" }
        return instrument.kind.rawValue
    }

    static func name(of type: FundType) -> String {
        switch type {
        case .equity: "equity fund"
        case .mixed: "mixed fund"
        case .realEstate: "real-estate fund"
        case .foreignRealEstate: "foreign real-estate fund"
        case .other: "other fund"
        default: type.rawValue
        }
    }
}

/// `retire instruments list`.
struct InstrumentsListCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List the instruments, with their kind for taxes (the default).")

    @OptionGroup var options: LibraryOptions

    @Flag(help: "Print JSON.")
    var json = false

    mutating func run() async throws {
        try await run(in: .live())
    }

    func run(in context: CLIContext) async throws {
        let loaded = try options.load(in: context)
        let instruments = loaded.library.instruments.values.sorted { $0.id < $1.id }
        if json {
            struct Row: Encodable {
                var id: String
                var name: String
                var kind: String
                var currency: String
                var fundType: String?
                var automaticFundType: String?
                var deliveryClaim: Bool?
            }
            context.console.print(try JSONOutput.string(instruments.map { instrument in
                Row(id: instrument.id.rawValue, name: instrument.name, kind: instrument.kind.rawValue,
                    currency: instrument.currency.rawValue, fundType: instrument.tax?.fundType?.rawValue,
                    automaticFundType: instrument.kind.hasFundType
                        ? FundType.derived(from: instrument.assetClasses).rawValue : nil,
                    deliveryClaim: instrument.tax?.deliveryClaim)
            }))
            return
        }
        guard !instruments.isEmpty else {
            context.console.print("The library has no instruments yet.")
            return
        }
        var table = TextTable([.left("ID"), .left("Name"), .left("Kind"), .left("Currency"), .left("Asset mix"),
                               .left("For taxes")])
        for instrument in instruments {
            let mix = instrument.assetClasses.assetClasses.map { assetClass in
                "\(assetClass) \(Format.percent(instrument.assetClasses[assetClass], places: 0))"
            }.joined(separator: ", ")
            table.add([instrument.id.rawValue, instrument.name, instrument.kind.rawValue,
                       instrument.currency.rawValue, mix, InstrumentsGroupCommand.taxKind(of: instrument)])
        }
        context.console.print(lines: table.lines(indent: 0))
    }
}

/// `retire instruments set <id>`: a fund's type, an ETC's delivery claim.
struct InstrumentsSetCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Set an ETF's or fund's type, or whether an ETC gives a right to delivery of the metal.",
        discussion: """
            --fund-type is equity, mixed, realEstate, foreignRealEstate or other, or automatic to let plans \
            work it out from the asset mix. --delivery-claim yes marks an ETC whose holders can ask for the \
            metal itself, which some countries tax like the metal. Written to instruments/<id>.json after a \
            backup (--dry-run shows the change).
            """)

    @Argument(help: ArgumentHelp("The instrument's ID.", valueName: "id"))
    var id: String

    @OptionGroup var options: LibraryOptions

    @Option(help: ArgumentHelp("equity, mixed, realEstate, foreignRealEstate, other, or automatic.", valueName: "type"))
    var fundType: String?

    @Option(help: ArgumentHelp("yes or no.", valueName: "yes|no"))
    var deliveryClaim: String?

    @Flag(help: "Show what would change; write nothing.")
    var dryRun = false

    func validate() throws {
        guard fundType != nil || deliveryClaim != nil else {
            throw ValidationError("Say what to set: --fund-type or --delivery-claim.")
        }
        if let fundType, fundType != "automatic", !FundType.knownValues.contains(FundType(fundType)) {
            throw ValidationError("--fund-type must be one of "
                + FundType.knownValues.map(\.rawValue).joined(separator: ", ") + ", or automatic.")
        }
        if let deliveryClaim, !["yes", "no"].contains(deliveryClaim.lowercased()) {
            throw ValidationError("--delivery-claim must be yes or no.")
        }
    }

    mutating func run() async throws {
        try await run(in: .live())
    }

    func run(in context: CLIContext) async throws {
        let loaded = try options.load(in: context)
        guard var instrument = loaded.library.instruments[InstrumentID(id)] else {
            let known = loaded.library.instruments.keys.sorted().map(\.rawValue)
            throw CLIError("There's no instrument \"\(id)\". Instruments: \(known.joined(separator: ", ")).")
        }
        var tax = instrument.tax ?? InstrumentTax()
        if let fundType {
            guard instrument.kind.hasFundType else {
                throw CLIError("\(instrument.id) is \(instrument.kind == .etc ? "an" : "a") \(instrument.kind): only an "
                    + "ETF or a fund has a fund type.")
            }
            tax.fundType = fundType == "automatic" ? nil : FundType(fundType)
        }
        if let deliveryClaim {
            guard instrument.kind == .etc else {
                throw CLIError("\(instrument.id) is a \(instrument.kind): only an ETC has a delivery claim.")
            }
            tax.deliveryClaim = deliveryClaim.lowercased() == "yes" ? true : nil
        }
        instrument.tax = tax == InstrumentTax() ? nil : tax
        var library = loaded.library
        library.instruments[instrument.id] = instrument
        var lines = ["\(instrument.name) (\(instrument.id)): \(InstrumentsGroupCommand.taxKind(of: instrument))."]
        try LibraryEdit.write(library, over: loaded, label: "instruments", dryRun: dryRun, context: context,
                              lines: &lines)
        context.console.print(lines: lines)
    }
}
