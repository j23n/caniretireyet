import ArgumentParser
import Foundation
import Model
import Storage

/// `retire init <path>`: creates a new, empty library folder.
struct InitCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Create a new, empty library folder.",
        discussion: """
            Writes library.json with your settings, a README, and the empty folders \
            accounts/, instruments/, history/ and plans/. The folder is created if needed; \
            it must be new or empty.
            """)

    @Argument(help: ArgumentHelp("The folder to create the library in. Default: --library or $RETIRE_LIBRARY.",
                                 valueName: "path"))
    var path: String?

    @OptionGroup var options: LibraryOptions

    @Option(help: ArgumentHelp("Your birth date, YYYY-MM-DD. Plans use it for ages.", valueName: "date"))
    var birthDate: String?

    @Option(help: "Your name, as the library's owner.")
    var name: String?

    @Option(help: ArgumentHelp("The currency net worth is reported in.", valueName: "code"))
    var currency = "EUR"

    @Option(help: ArgumentHelp("Your country of tax residence today, e.g. IT.", valueName: "country"))
    var residence: String?

    func validate() throws {
        _ = try settings()
    }

    /// The settings to write, from the options.
    func settings() throws -> LibrarySettings {
        let birth = try parseDate(birthDate, option: "--birth-date")
        let currency = CurrencyCode(currency.uppercased())
        guard currency.isWellFormed else {
            throw ValidationError("--currency must be an ISO 4217 code such as EUR, not “\(self.currency)”.")
        }
        let country = residence.map { CountryCode($0.uppercased()) }
        if let country, !country.isWellFormed {
            throw ValidationError("--residence must be a two-letter country code such as IT, not “\(residence!)”.")
        }
        let trimmedName = name?.trimmingCharacters(in: .whitespaces)
        let person = birth != nil || trimmedName?.isEmpty == false
            ? Person(name: trimmedName?.isEmpty == false ? trimmedName : nil, birthDate: birth) : nil
        return LibrarySettings(baseCurrency: currency, person: person, taxResidence: country)
    }

    mutating func run() async throws {
        try await run(in: .live())
    }

    func run(in context: CLIContext) async throws {
        guard let target = path ?? options.givenPath(in: context) else {
            throw CLIError("Say where to create the library: retire init <path>.")
        }
        let folder = LibraryFolder(root: context.url(forPath: target))
        if folder.containsLibrary { throw StorageError.libraryAlreadyExists(path: folder.root.path) }
        if !(try folder.files.listFiles(in: folder.root)).isEmpty {
            throw CLIError("\(folder.root.path) isn't empty. Choose a new or empty folder for the library.")
        }
        let settings = try settings()
        try folder.createLibrary(settings: settings)

        let console = context.console
        console.print("Created a new library in \(folder.root.path)")
        var table = TextTable([.left(""), .left("")], showsHeader: false)
        table.add(["Base currency", settings.baseCurrency.rawValue])
        table.add(["Tax residence", settings.taxResidence?.rawValue ?? "not set"])
        table.add(["Birth date", settings.person?.birthDate?.description ?? "not set (plans need it)"])
        if let name = settings.person?.name { table.add(["Name", name]) }
        console.print(lines: table.lines())
        console.print()
        console.print("Next: add accounts in the app, or import your spreadsheet:")
        console.print("  retire import <file> --library \(Self.quoted(folder.root.path))")
    }

    private static func quoted(_ path: String) -> String {
        path.contains(" ") ? "\"\(path)\"" : path
    }
}
