import Foundation
import Model
import Planner
import Testing
import TestSupport

/// The accounts your money is measured in against a baseline (PROGRESS.md,
/// "Actual vs. a baseline"): moving money to the account that replaced one,
/// or into a new one, isn't a loss.
struct BaselineAccountsTests {
    /// The example's baseline, as if saved on `start` counting `accounts`,
    /// with the copy of `plan` it was saved with.
    private func baseline(on start: CalendarDate, counting accounts: [AccountID], plan: PlanID = "base",
                          in library: Library) throws -> Baseline {
        var baseline = try #require(library.baselines(for: "base").first)
        baseline.start = BaselineStart(date: start, value: 100_000)
        baseline.accounts = accounts
        let document = try #require(library.plans[plan])
        baseline.plan = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(document))
        return baseline
    }

    /// From 2022, counting the old bank and Directa: Conto Fineco replaced
    /// the old bank, and the accounts opened since that plans count join;
    /// the home and its mortgage, which plans don't count, don't.
    @Test func theAccountsThatReplacedThemAndThoseOpenedSince() throws {
        let library = try Fixtures.exampleLibrary()
        let compared = try baseline(on: "2022-01-01", counting: ["old-bank", "directa"], in: library)
            .comparedAccounts(among: library.accounts)
        #expect(compared.isSuperset(of: ["old-bank", "directa", "conto-fineco", "conto-deposito", "gold-coins",
                                         "ledger-wallet", "fondo-pensione", "tfr"]))
        #expect(!compared.contains("casa"))
        #expect(!compared.contains("mutuo-casa"))
    }

    /// From 2025, counting the old bank only: Conto Fineco, opened in 2024,
    /// joins because it replaced the old bank; Directa, open before and not
    /// counted, stays out.
    @Test func aSuccessorOpenAtTheStartJoinsAndOthersStayOut() throws {
        let library = try Fixtures.exampleLibrary()
        let compared = try baseline(on: "2025-01-01", counting: ["old-bank"], in: library)
            .comparedAccounts(among: library.accounts)
        #expect(compared.contains("conto-fineco"))
        #expect(compared.contains("conto-deposito"))
        #expect(!compared.contains("directa"))
        #expect(!compared.contains("gold-coins"))
    }

    /// An account opened since that the baseline's plan leaves out (the
    /// part-time plan excludes the gold coins) stays out.
    @Test func anAccountItsPlanLeavesOutStaysOut() throws {
        let library = try Fixtures.exampleLibrary()
        let compared = try baseline(on: "2022-01-01", counting: ["old-bank"], plan: "part-time-from-50", in: library)
            .comparedAccounts(among: library.accounts)
        #expect(!compared.contains("gold-coins"))
        #expect(compared.contains("ledger-wallet"))
    }
}
