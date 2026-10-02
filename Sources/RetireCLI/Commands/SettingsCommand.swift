import ArgumentParser
import Foundation
import Model
import Storage

/// `retire settings`: the library's settings (`library.json`), and the
/// person's citizenships, which treaties can decide by.
struct SettingsCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "settings",
        abstract: "Show the library's settings, or set your citizenships.",
        discussion: """
            Prints the base currency, the tax residence (and the tax system plans use for it), \
            the birth date, the citizenships and the main plan. --citizenship IT --citizenship DE \
            sets every citizenship you hold, in place of the ones recorded; --no-citizenships \
            removes them. Some tax treaties decide by citizenship which country taxes a pension. \
            Changes are written after a backup of library.json (--dry-run shows them).
            """)

    @OptionGroup var options: LibraryOptions

    @Option(help: ArgumentHelp("A citizenship you hold, e.g. DE; repeat it for each.", valueName: "country"))
    var citizenship: [String] = []

    @Flag(help: "Remove the citizenships.")
    var noCitizenships = false

    @Flag(help: "Show what would change; write nothing.")
    var dryRun = false

    @Flag(help: "Print JSON.")
    var json = false

    func validate() throws {
        if noCitizenships, !citizenship.isEmpty {
            throw ValidationError("--citizenship and --no-citizenships don't go together.")
        }
        for code in citizenship { _ = try Self.country(code) }
    }

    static func country(_ text: String) throws -> CountryCode {
        let code = CountryCode(text.trimmingCharacters(in: .whitespaces).uppercased())
        guard code.isWellFormed else {
            throw ValidationError("--citizenship must be a two-letter country code such as DE, not “\(text)”.")
        }
        return code
    }

    /// `settings` with `codes` as the citizenships, each once, in order; a
    /// person left with nothing goes.
    static func setting(citizenships codes: [CountryCode], in settings: LibrarySettings) -> LibrarySettings {
        var seen: Set<CountryCode> = []
        var settings = settings
        var person = settings.person ?? Person()
        person.citizenships = codes.filter { seen.insert($0).inserted }
        settings.person = person == Person() ? nil : person
        return settings
    }

    mutating func run() async throws {
        try await run(in: .live())
    }

    func run(in context: CLIContext) async throws {
        let loaded = try options.load(in: context)
        var lines: [String] = []
        var library = loaded.library
        if noCitizenships || !citizenship.isEmpty {
            let codes = try citizenship.map(Self.country)
            library.settings = Self.setting(citizenships: codes, in: library.settings)
            let now = library.settings.person?.citizenships ?? []
            lines.append("Citizenships: " + (now.isEmpty ? "none" : now.map(\.rawValue).joined(separator: ", ")) + ".")
            try LibraryEdit.write(library, over: loaded, label: "settings", dryRun: dryRun, context: context,
                                  lines: &lines)
            lines.append("")
        }
        let settings = library.settings
        let system = TaxSystems.residenceSystem(for: settings, registry: TaxSystems.registry())
        if json {
            struct JSON: Encodable {
                var baseCurrency: String
                var taxResidence: String?
                var defaultTaxSystem: String?
                var birthDate: String?
                var name: String?
                var citizenships: [String]
                var mainPlan: String?
            }
            context.console.print(try JSONOutput.string(JSON(
                baseCurrency: settings.baseCurrency.rawValue, taxResidence: settings.taxResidence?.rawValue,
                defaultTaxSystem: system?.id, birthDate: settings.person?.birthDate?.description,
                name: settings.person?.name, citizenships: (settings.person?.citizenships ?? []).map(\.rawValue),
                mainPlan: settings.mainPlan?.rawValue)))
            return
        }
        var table = TextTable([.left(""), .left("")], showsHeader: false)
        table.add(["Base currency", settings.baseCurrency.rawValue])
        let residence = settings.taxResidence?.rawValue ?? "not set"
        table.add(["Tax residence", residence + (system.map { " (plans use \($0.id): \($0.name))" } ?? "")])
        table.add(["Birth date", settings.person?.birthDate?.description ?? "not set (plans need it)"])
        let citizenships = settings.person?.citizenships ?? []
        table.add(["Citizenships", citizenships.isEmpty ? "none" : citizenships.map(\.rawValue).joined(separator: ", ")])
        if let name = settings.person?.name { table.add(["Name", name]) }
        table.add(["Main plan", settings.mainPlan?.rawValue ?? "not set"])
        lines += table.lines(indent: 0)
        context.console.print(lines: lines)
    }
}
