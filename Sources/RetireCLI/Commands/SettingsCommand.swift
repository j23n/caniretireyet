import ArgumentParser
import Foundation
import Model
import Storage

/// `retire settings`: the library's settings (`library.json`) and the
/// inflation index.
struct SettingsCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "settings",
        abstract: "Show the library's settings, or set the inflation index.",
        discussion: """
            Prints the base currency, the country you live in, the inflation index, the birth \
            date and the main plan. --inflation-index hicp-ea picks the consumer price index \
            amounts are adjusted with (a country's HICP, hicp-<country>, or the euro area's, \
            hicp-ea); automatic goes back to the default: your country's HICP, else the base \
            currency's. Changes are written after a backup of library.json (--dry-run shows them).
            """)

    @OptionGroup var options: LibraryOptions

    @Option(help: ArgumentHelp("The inflation index, e.g. hicp-ea, or automatic.", valueName: "index"))
    var inflationIndex: String?

    @Flag(help: "Show what would change; write nothing.")
    var dryRun = false

    @Flag(help: "Print JSON.")
    var json = false

    func validate() throws {
        if let inflationIndex { _ = try Self.index(inflationIndex) }
    }

    /// The index `--inflation-index` names: an HICP, or `nil` for automatic.
    static func index(_ text: String) throws -> IndexID? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed == "automatic" { return nil }
        let index = IndexID(trimmed)
        guard index.hicpArea != nil else {
            throw ValidationError("--inflation-index must be an HICP such as hicp-de or hicp-ea, or automatic, "
                + "not “\(text)”.")
        }
        return index
    }

    /// "hicp-it (automatic)", "hicp-ea", or "none (…)" when no index applies.
    static func inflationText(_ library: Library) -> String {
        guard let index = library.effectiveInflationIndex else {
            return "none (set one to see amounts in today's money)"
        }
        return library.settings.inflationIndex == nil ? "\(index) (automatic)" : index.rawValue
    }

    func run(in context: CLIContext) async throws {
        let loaded = try options.load(in: context)
        var lines: [String] = []
        var library = loaded.library
        if let inflationIndex {
            library.settings.inflationIndex = try Self.index(inflationIndex)
            lines.append("Inflation index: \(Self.inflationText(library)).")
            try LibraryEdit.write(library, over: loaded, label: "settings", dryRun: dryRun, context: context,
                                  lines: &lines)
            lines.append("")
        }
        let settings = library.settings
        if json {
            struct JSON: Encodable {
                var baseCurrency: String
                var taxResidence: String?
                var inflationIndex: String?
                var inflationIndexSetting: String?
                var birthDate: String?
                var name: String?
                var mainPlan: String?
            }
            context.console.print(try JSONOutput.string(JSON(
                baseCurrency: settings.baseCurrency.rawValue, taxResidence: settings.taxResidence?.rawValue,
                inflationIndex: library.effectiveInflationIndex?.rawValue,
                inflationIndexSetting: settings.inflationIndex?.rawValue, birthDate: settings.person?.birthDate?.description,
                name: settings.person?.name, mainPlan: settings.mainPlan?.rawValue)))
            return
        }
        var table = TextTable([.left(""), .left("")], showsHeader: false)
        table.add(["Base currency", settings.baseCurrency.rawValue])
        table.add(["Country", settings.taxResidence?.rawValue ?? "not set"])
        table.add(["Inflation index", Self.inflationText(library)])
        table.add(["Birth date", settings.person?.birthDate?.description ?? "not set (plans need it)"])
        if let name = settings.person?.name { table.add(["Name", name]) }
        table.add(["Main plan", settings.mainPlan?.rawValue ?? "not set"])
        lines += table.lines(indent: 0)
        context.console.print(lines: lines)
    }
}
