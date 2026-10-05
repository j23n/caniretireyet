import ArgumentParser
import Foundation
import Model
import Tracker

/// `retire export`: the library as CSV files (FILE_FORMAT.md, "CSV export").
struct ExportCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Write the library as CSV files, for a spreadsheet or another app.",
        discussion: """
            Writes one CSV file per table into a folder: net worth and each account's value at every \
            month end (net-worth.csv, account-values.csv), and what's recorded: accounts, instruments, \
            valuations, positions, trades, prices, FX rates and inflation figures. The folder is made if \
            needed; files of the same names in it are replaced, other files are left alone. The library \
            isn't changed.
            """)

    @OptionGroup var options: LibraryOptions

    @Argument(help: ArgumentHelp("The folder to write the CSV files into.", valueName: "folder"))
    var folder: String

    @Option(help: ArgumentHelp("Values are worked out at each month end through this date, YYYY-MM-DD. "
                                   + "Default: today.", valueName: "date"))
    var date: String?

    func validate() throws {
        _ = try parseDate(date, option: "--date")
    }

    mutating func run() async throws {
        try await run(in: .live())
    }

    func run(in context: CLIContext) async throws {
        let loaded = try options.load(in: context)
        let date = try parseDate(date, option: "--date") ?? context.today
        let files = CSVExport.files(of: loaded.library, through: date)
        let destination = context.url(forPath: folder)
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            for file in files {
                try Data(file.text.utf8).write(to: destination.appendingPathComponent(file.name), options: .atomic)
            }
        } catch {
            throw CLIError("Couldn't write to \(folder): \(error.localizedDescription)")
        }
        context.console.print("Wrote \(files.count) CSV files to \(folder): \(files.map(\.name).joined(separator: ", ")).")
    }
}
