import ArgumentParser
import Foundation

/// `retire`: Can I Retire Yet? on the command line. Creates and checks a
/// library folder, shows and sets its settings, prints net worth, imports
/// spreadsheets and broker exports, lists trades and instruments, fetches
/// prices, runs plans and exports CSV files.
///
/// The commands live in this library so they can be tested: the `retire`
/// executable runs ``RetireCLI/run(_:context:columns:)`` with
/// ``CLIContext/live()``, and tests with a ``CLIContext`` of their own.
struct Retire: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "retire",
        abstract: "Can I Retire Yet? on the command line.",
        discussion: """
            Every command works on a library folder: pass --library <path>, set \
            \(CLIContext.libraryVariable), or run it inside the folder.
            """,
        version: "0.2.0",
        subcommands: [
            InitCommand.self, ValidateCommand.self, SettingsCommand.self, NetWorthCommand.self,
            ImportGroupCommand.self, TradesGroupCommand.self, InstrumentsGroupCommand.self, PricesCommand.self,
            SpendingCommand.self, PlanGroupCommand.self, ExportCommand.self,
        ]
    )
}

/// A `retire` subcommand. Its work is in ``run(in:)``, so tests can give it
/// their own console, environment and HTTP client.
protocol RetireSubcommand: AsyncParsableCommand {
    func run(in context: CLIContext) async throws
}

/// Runs `retire`, for the executable and for tests.
public enum RetireCLI {
    /// Parses `arguments` (without the program name; `nil` for the
    /// process's), runs the command in `context` and returns its exit
    /// status. Help, errors and usage are written to the context's console,
    /// help wrapped at `columns` (`nil`: the terminal's width).
    public static func run(_ arguments: [String]? = nil, context: CLIContext, columns: Int? = nil) async -> Int32 {
        do {
            var command = try await Retire.asyncParseAsRoot(arguments)
            if let subcommand = command as? any RetireSubcommand {
                try await subcommand.run(in: context)
            } else if var asyncCommand = command as? any AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
            return ExitCode.success.rawValue
        } catch {
            let code = Retire.exitCode(for: error)
            let message = Retire.fullMessage(for: error, columns: columns)
            if !message.isEmpty {
                if code == .success { context.console.print(message) } else { context.console.error(message) }
            }
            return code.rawValue
        }
    }
}
