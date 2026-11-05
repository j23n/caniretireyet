import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// Invariants B5 and B6: a transfer between two tracked accounts moves
/// nothing, and neither the scale of the amounts nor the currency they're
/// counted in changes a rate.
struct TransferAndScaleTests {
    /// `library` with `amount` moved from `source` to `destination` on
    /// `date`, recorded on both sides: each balance after it changed by the
    /// amount, or for an account that records trades, a deposit or a
    /// withdrawal and the cash it records after it. Money in and out stay:
    /// a transfer between tracked accounts is in neither.
    private func moving(_ amount: Decimal, from source: AccountID, to destination: AccountID, on date: CalendarDate,
                        in library: Library) -> Library {
        var library = library
        for (account, sign) in [(source, Decimal(-1)), (destination, Decimal(1))] {
            guard let details = library.accounts[account] else { continue }
            if details.recordsTrades {
                library.upsert(Trade(account: account, date: date, id: TradeID("moved-\(date)"),
                                     type: sign > 0 ? .deposit : .withdrawal, amount: sign * amount))
            }
            for valuation in library.valuations(for: account) where valuation.date >= date {
                var valuation = valuation
                if valuation.balance != nil {
                    valuation.balance = (valuation.balance ?? 0) + sign * amount
                } else if valuation.cash != nil {
                    valuation.cash = (valuation.cash ?? 0) + sign * amount
                }
                library.upsert(valuation)
            }
        }
        return library
    }

    /// Each transfer falls between two check-ins of both its accounts: a
    /// value carries forward until the account's next one, so at a check-in
    /// of one side alone (the trades library's broker on 15 January) the
    /// money shows on one side only.
    static let transfers: [(InvariantLibrary, AccountID, AccountID, CalendarDate)] = [
        (.household, "bank", "savings", "2026-02-14"),
        (.trades, "bank", "broker", "2026-02-14"),
        (.trades, "savings", "broker", "2026-02-07"),
        (.newAccount, "bank", "old-savings", "2026-04-02"),
        (.example, "conto-fineco", "conto-deposito", "2026-08-12"),
        (.example, "conto-fineco", "directa", "2026-05-20"),
    ]

    @Test(arguments: transfers.indices)
    func aTransferMovesNothing(_ index: Int) throws {
        let (which, source, destination, date) = Self.transfers[index]
        let library = try which.library()
        let before = Valuator(library: library)
        let after = Valuator(library: moving(1000, from: source, to: destination, on: date, in: library))
        #expect(Readings.differences(Readings.money(after), Readings.money(before)) == [])
        #expect(Readings.differences(Readings.rates(after), Readings.rates(before)) == [])
    }

    /// A transfer between two dollar accounts in a euro library. The bank's
    /// side, a value, is converted at the rate of the value's day (31
    /// March); the broker's, a deposit, at the deposit's day (18 March,
    /// February's rate). In euros the two sides don't cancel: the 1,000
    /// dollars at the two rates differ by 41.72 euros, which shows as saved,
    /// and as that much less markets. Net worth is the same at every
    /// check-in.
    @Test func aTransferInAnotherCurrencyMovesNothing() throws {
        let library = try InvariantLibrary.foreignCurrency.library()
        let before = Valuator(library: library)
        let after = Valuator(library: moving(1000, from: "usd-bank", to: "usd-broker", on: "2026-03-18",
                                             in: library))
        let differences = Readings.differences(Readings.money(after), Readings.money(before))
        #expect(!differences.contains { $0.hasPrefix("net worth") || $0.hasPrefix("plan assets") })
        withKnownIssue("""
            A deposit's saved is converted at the deposit's rate, a balance's at its value's rate \
            (Valuator.change, recordedSaved), so a transfer between two accounts in another currency \
            saves the difference. Should both sides use one date's rate? Needs a decision.
            """) {
            #expect(differences == [])
        }
    }

    /// The exception PROGRESS.md states ("Savings rate"): a payment into a
    /// pension from a tracked account counts as came in twice, once as
    /// pay and once as the pension's contribution, and, once spent, as
    /// spent. What was saved stays.
    @Test func aPaymentIntoAPensionCountsAsCameInTwice() throws {
        var library = InvariantLibrary.household()
        let before = Valuator(library: library)
        library = moving(1000, from: "bank", to: "pension", on: "2026-02-14", in: library)
        // The pension asks for what was saved into it: 1,000 more in February.
        var february = try #require(library.valuations(for: "pension").first { $0.date == "2026-02-28" })
        february.saved = 1300
        library.upsert(february)
        let after = Valuator(library: library)
        let was = try #require(before.savingsRate(from: "2026-02-01", through: "2026-02-28"))
        let rate = try #require(after.savingsRate(from: "2026-02-01", through: "2026-02-28"))
        #expect(rate.saved == was.saved)
        #expect(rate.pensionContributions == was.pensionContributions + 1000)
        #expect(rate.income == was.income + 1000)
        #expect(rate.spent == was.spent + 1000)
    }

    @Test(arguments: InvariantLibrary.allCases)
    func scaleChangesNoRate(_ which: InvariantLibrary) throws {
        let library = try which.library()
        let factor: Decimal = 7
        let base = Valuator(library: library)
        let scaled = Valuator(library: InvariantLibrary.scaled(library, by: factor))
        // A depreciating balance is estimated between its values and rounded
        // to cents (`Account.estimated`), so 7 times the amount can round to
        // 7 times a value half a cent away; a reading takes at most two.
        let money = which == .depreciatingCar ? factor * d("0.01") : nil
        let rates = which == .depreciatingCar ? d("0.000001") : nil
        #expect(Readings.differences(Readings.money(scaled), Readings.money(base), factor: factor,
                                     tolerance: money) == [])
        #expect(Readings.differences(Readings.rates(scaled), Readings.rates(base), tolerance: rates) == [])
    }

    /// A library counted in US dollars at a constant rate of 1.25 a euro
    /// gives every amount 1.25 times as large as counted in euros at that
    /// rate, and the same rates.
    @Test(arguments: InvariantLibrary.allCases)
    func theBaseCurrencyChangesNoRate(_ which: InvariantLibrary) throws {
        let library = try which.library()
        let rate = d("1.25")
        let euros = Valuator(library: InvariantLibrary.constantDollar(library, rate: rate, base: .eur))
        let dollars = Valuator(library: InvariantLibrary.constantDollar(library, rate: rate, base: .usd))
        #expect(Readings.differences(Readings.money(dollars), Readings.money(euros), factor: rate) == [])
        #expect(Readings.differences(Readings.rates(dollars), Readings.rates(euros)) == [])
    }
}
