import Foundation
import Importer
import Model
import Testing
import TestSupport

/// Checking a month's lines after the import (IMPORT.md, "Your months"):
/// the words a rule would match, the lines that have them, and remembering
/// a rule in the account's statement profile.
struct LineEditsTests {
    static func line(_ date: CalendarDate, _ id: BankLineID, _ amount: Decimal, _ text: String) -> BankLine {
        BankLine(account: "conto", date: date, id: id, amount: amount, text: text, statementClass: .spending)
    }

    static func library() -> Library {
        var library = Library(
            accounts: [
                Account(id: "conto", name: "Conto", kind: .cash, currency: .eur, opened: "2020-01-01"),
                Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur, opened: "2020-01-01"),
            ],
            importProfiles: [
                ImportProfile(id: "bank", name: "Bank", layout: .statement,
                              constants: ImportConstants(account: "conto"),
                              rules: [StatementRule(match: "Broker SIM", statementClass: .spending)]),
            ])
        for line in [
            line("2026-01-03", "a", -500, "Bonifico a favore di Broker SIM · Broker SIM"),
            line("2026-01-12", "b", -60, "Esselunga Milano 12/01 carta 1234"),
            line("2026-01-20", "c", -300, "BROKER sim, bonifico"),
            line("2026-02-03", "d", -500, "Bonifico a favore di Broker SIM"),
        ] {
            library.upsert(line)
        }
        return library
    }

    @Test func aLinesPhraseStopsAtItsFirstNumber() {
        #expect(Self.line("2026-01-12", "b", -60, "Esselunga Milano 12/01 carta 1234").suggestedPhrase
            == "Esselunga Milano")
        #expect(Self.line("2026-01-12", "b", -60, "Rent · Rossi").suggestedPhrase == "Rent")
        #expect(Self.line("2026-01-12", "b", -60, "1234 POS").suggestedPhrase == "1234 POS")
    }

    @Test func theMonthsLinesWithAPhrase() {
        let lines = Self.library().lines(of: "conto", matching: "broker sim", after: "2025-12-31",
                                         through: "2026-01-31")
        #expect(lines.map(\.id) == ["a", "c"])
        #expect(Self.library().lines(of: "conto", matching: " ", after: nil, through: "2026-12-31").isEmpty)
    }

    @Test func aRuleIsRememberedInTheAccountsProfile() throws {
        var library = Self.library()
        let remembered = library.rememberStatementRule(.transfer, other: "broker", for: "Broker SIM", account: "conto")
        #expect(remembered)
        let rules = try #require(library.importProfiles["bank"]?.rules)
        #expect(rules == [StatementRule(match: "Broker SIM", statementClass: .transfer, account: "broker")])

        // An account without a statement profile has nowhere to keep it.
        let elsewhere = library.rememberStatementRule(.spending, for: "Broker", account: "broker")
        #expect(!elsewhere)
    }
}
