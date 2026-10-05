import ArgumentParser
import Foundation

/// `retire`: Can I Retire Yet? on the command line. Creates and checks a
/// library folder, shows and sets its settings, prints net worth, imports
/// spreadsheets and broker exports, lists and edits trades and
/// instruments' tax kinds, fetches prices, and runs and edits plans.
///
/// The commands live in this library so they can be tested; the `retire`
/// executable only calls ``Retire/main()``. Tests call ``RetireCLI/run(_:context:)``
/// with a ``CLIContext`` of their own.
public struct Retire: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
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
            PlanGroupCommand.self, ExportCommand.self,
        ]
    )

    public init() {}
}

/// A `retire` subcommand. Its work is in ``run(in:)``, so tests can give it
/// their own console, environment and HTTP client; `run()` uses the real ones.
protocol RetireSubcommand: AsyncParsableCommand {
    func run(in context: CLIContext) async throws
}

/// Runs `retire` in a given context, for tests and embedding.
public enum RetireCLI {
    /// Parses `arguments` (without the program name), runs the command and
    /// returns its exit status. Help, errors and usage are written to the
    /// context's console as the `retire` executable would print them.
    public static func run(_ arguments: [String], context: CLIContext) async -> Int32 {
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
            let message = Retire.fullMessage(for: error, columns: 100)
            if !message.isEmpty {
                if code == .success { context.console.print(message) } else { context.console.error(message) }
            }
            return code.rawValue
        }
    }
}
