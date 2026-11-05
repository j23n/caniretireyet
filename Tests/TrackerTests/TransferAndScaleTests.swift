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
    /// `date`, arriving on `arrival` (`date` when `nil`), recorded on both
    /// sides: each balance after it changed by the amount, or for an
    /// account that records trades, a deposit or a withdrawal and the cash
    /// it records after it. Money in and out stay: a transfer between
    /// tracked accounts is in neither.
    private func moving(_ amount: Decimal, from source: AccountID, to destination: AccountID, on sent: CalendarDate,
                        arriving arrival: CalendarDate? = nil, in library: Library) -> Library {
        var library = library
        for (account, sign) in [(source, Decimal(-1)), (destination, Decimal(1))] {
            guard let details = library.accounts[account] else { continue }
            let date = sign > 0 ? arrival ?? sent : sent
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

    /// `library` with 1,000 dollars moved from the dollar bank to the dollar
    /// broker on 18 March, and the bank's statement line that moved it.
    private func dollarTransfer(in library: Library) -> Library {
        var library = moving(1000, from: "usd-bank", to: "usd-broker", on: "2026-03-18", in: library)
        library.upsert(BankLine(account: "usd-bank", date: "2026-03-18", id: "to-broker", amount: -1000,
                                statementClass: .transfer, otherAccount: "usd-broker"))
        return library
    }

    /// A transfer between two dollar accounts in a euro library, with the
    /// bank's statement line that moved it. The bank's side, a value, is
    /// converted at the rate of the value's day (31 March); the broker's
    /// deposit on 18 March, which the line shows came from the bank, at the
    /// rate of the bank's value that covers it, the same 31 March
    /// (docs/TRADES.md, "Flows"). So in euros the two sides cancel too.
    @Test func aTransferInAnotherCurrencyMovesNothing() throws {
        let library = try InvariantLibrary.foreignCurrency.library()
        let before = Valuator(library: library)
        let after = Valuator(library: dollarTransfer(in: library))
        #expect(Readings.differences(Readings.money(after), Readings.money(before)) == [])
        #expect(Readings.differences(Readings.rates(after), Readings.rates(before)) == [])
    }

    /// The same transfer with the savings account valued on 25 March,
    /// between the transfer and the bank's value. The deposit converts at
    /// the bank's value that covers it, 31 March, not at the next value of
    /// any account, whose rate (February's, 1.07) the bank's side doesn't
    /// use: over the bank's month, and the year, the two sides cancel. (On
    /// 25 March itself the money shows on both sides, since the bank's
    /// balance carries forward until its next value.)
    @Test func aTransferCountsAtTheOtherAccountsValue() throws {
        var library = try InvariantLibrary.foreignCurrency.library()
        library.upsert(Valuation(account: "savings", date: "2026-03-25", balance: 11021, moneyIn: 0, moneyOut: 0))
        let before = Valuator(library: library)
        let after = Valuator(library: dollarTransfer(in: library))
        let windows: [(CalendarDate, CalendarDate)] = [("2026-02-28", "2026-03-31"), ("2025-12-31", "2026-04-30")]
        for (from, to) in windows {
            let was = before.change(from: from, to: to).total
            let now = after.change(from: from, to: to).total
            #expect(same(now.saved, was.saved), "\(from)…\(to)")
            #expect(same(now.market, was.market), "\(from)…\(to)")
            #expect(same(now.end, was.end), "\(from)…\(to)")
        }
    }

    /// A transfer whose two sides fall on either side of the bank's value
    /// of 31 March: the bank's line on 30 March and the broker's deposit on
    /// 1 April, or the broker's withdrawal on 30 March and the bank's line
    /// on 1 April. The broker's side converts at the bank's value that
    /// covers the line (31 March, 1.12, or 30 April, 1.09), where the
    /// bank's side lands, not at the one that covers its own date: over the
    /// year the two sides cancel.
    @Test(arguments: [true, false])
    func aTransferAcrossTheOtherAccountsValueCountsAtTheLines(toTheBroker: Bool) throws {
        var library = try InvariantLibrary.foreignCurrency.library()
        let before = Valuator(library: library)
        let (source, destination): (AccountID, AccountID) = toTheBroker ? ("usd-bank", "usd-broker")
            : ("usd-broker", "usd-bank")
        library = moving(1000, from: source, to: destination, on: "2026-03-30", arriving: "2026-04-01", in: library)
        library.upsert(BankLine(account: "usd-bank", date: toTheBroker ? "2026-03-30" : "2026-04-01", id: "moved",
                                amount: toTheBroker ? -1000 : 1000, statementClass: .transfer,
                                otherAccount: "usd-broker"))
        let after = Valuator(library: library)
        let was = before.change(from: "2025-12-31", to: "2026-04-30").total
        let now = after.change(from: "2025-12-31", to: "2026-04-30").total
        #expect(same(now.saved, was.saved))
        #expect(same(now.market, was.market))
        #expect(same(now.end, was.end))
    }

    /// The same transfer without the bank's line. Without the other side's
    /// line, the move can't be told from money sent in from outside, or
    /// dollars bought with euros, which count at their own date: the
    /// deposit converts at 18 March's rate (February's, 1.07), the bank's
    /// side at 31 March's (1.12). The gap, 41.72 €, shows as saved, and as
    /// that much less markets; net worth is the same.
    @Test func aTransferWithoutTheOtherSidesLineSavesTheRateGap() throws {
        let library = try InvariantLibrary.foreignCurrency.library()
        let before = Valuator(library: library).change(from: "2026-02-28", to: "2026-03-31").total
        let after = Valuator(library: moving(1000, from: "usd-bank", to: "usd-broker", on: "2026-03-18",
                                             in: library)).change(from: "2026-02-28", to: "2026-03-31").total
        let gap = Decimal(1000) / d("1.07") - Decimal(1000) / d("1.12")
        #expect(gap.rounded(scale: 2) == d("41.72"))
        #expect(same(after.saved - before.saved, gap))
        #expect(same(after.market - before.market, -gap))
        #expect(same(after.end, before.end))
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
