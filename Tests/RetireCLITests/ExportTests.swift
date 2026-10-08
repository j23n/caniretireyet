import Foundation
import Testing
import TestSupport

struct ExportTests {
    @Test func exportWritesTheCSVFilesAndLeavesTheLibraryAlone() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let output = try TemporaryFolder()
        let before = try library.text("history/2026/2026-09.json")
        let run = await retire(["export", "csv", "--library", library.path, "--date", "2026-09-30"],
                               currentDirectory: output.url)
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.hasPrefix("Wrote 10 CSV files to csv: net-worth.csv, account-values.csv, accounts.csv,"))
        let netWorth = try output.text("csv/net-worth.csv")
        #expect(netWorth.hasPrefix("date,currency,net_worth,plan_assets,complete\r\n"))
        let last = try #require(netWorth.components(separatedBy: "\r\n").dropLast().last)
        #expect(last.hasPrefix("2026-09-30,EUR,332455.49,"))  // as `retire networth` says
        #expect(last.hasSuffix(",yes"))
        #expect(try output.text("csv/accounts.csv").contains("\r\nfondo-pensione,Fondo pensione,pensionFund,EUR,"))
        for name in ["account-values", "instruments", "valuations", "positions", "trades", "prices", "fx",
                     "inflation"] {
            #expect(output.exists("csv/\(name).csv"), "\(name)")
        }
        #expect(try library.text("history/2026/2026-09.json") == before)
        #expect(!library.exists("backups"))
    }

    @Test func aBadDateIsRefused() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["export", "out", "--library", library.path, "--date", "30/09/2026"])
        #expect(run.status != 0)
        #expect(run.errors.contains("--date"))
    }
}
