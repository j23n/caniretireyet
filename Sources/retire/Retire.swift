import ArgumentParser

/// `retire`: the command-line tool. Validates a library, imports files with
/// a saved profile, prints net worth, and runs plans.
///
/// The tax systems are registered in one place (`TaxRegistry`) once they exist.
@main
struct Retire: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "retire",
        abstract: "Can I Retire Yet? on the command line.",
        version: "0.1.0",
        subcommands: [Validate.self, Import.self, NetWorth.self, Plan.self]
    )
}

extension Retire {
    /// Checks every file in a library folder.
    struct Validate: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Check every file in a library folder.")

        @Argument(help: "The library folder.")
        var library: String = "."

        func run() throws {
            print("validate: not implemented yet")
        }
    }

    /// Imports a CSV file with a saved import profile.
    struct Import: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Import a CSV file with a saved import profile.")

        @Argument(help: "The file to import.")
        var file: String

        @Option(help: "The import profile's ID (imports/<id>.json).")
        var profile: String

        @Option(help: "The library folder.")
        var library: String = "."

        @Flag(help: "Show what would change without writing anything.")
        var dryRun = false

        func run() throws {
            print("import: not implemented yet")
        }
    }

    /// Prints net worth on a date.
    struct NetWorth: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "networth", abstract: "Print net worth on a date, by account.")

        @Option(help: "The date, as YYYY-MM-DD (default: today).")
        var date: String?

        @Option(help: "The library folder.")
        var library: String = "."

        func run() throws {
            print("networth: not implemented yet")
        }
    }

    /// Runs a plan and prints the headline.
    struct Plan: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Run a plan and print the answer.")

        @Argument(help: "The plan's ID (plans/<id>.json).")
        var plan: String

        @Option(help: "The library folder.")
        var library: String = "."

        func run() throws {
            print("plan: not implemented yet")
        }
    }
}
