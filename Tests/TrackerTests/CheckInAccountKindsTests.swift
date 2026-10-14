import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// What a check-in asks for and writes per account kind (docs/ACCOUNTS.md,
/// "Decisions"): money in and out, interest, the worked-out new money and
/// what moved between your own accounts.
struct CheckInAccountKindsTests {
    /// Made-up accounts of each kind, valued on 2026-01-31: a current
    /// account, a savings account, a broker recording trades, a pension
    /// fund, a credit card and a mortgage, and a loan with no value yet.
    let library: Library = {
        var library = Library(settings: LibrarySettings(baseCurrency: .eur))
        let accounts = [
            Account(id: "bank", name: "Bank", kind: .cash, currency: .eur, opened: "2026-01-01"),
            Account(id: "deposit", name: "Deposit", kind: .savings, currency: .eur, opened: "2026-01-01"),
            Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur, opened: "2026-01-01",
                    valuation: .trades),
            Account(id: "fondo", name: "Fondo", kind: .pensionFund, currency: .eur, opened: "2026-01-01"),
            Account(id: "card", name: "Card", kind: .creditCard, currency: .eur, opened: "2026-01-01"),
            Account(id: "mortgage", name: "Mortgage", kind: .mortgage, currency: .eur, opened: "2026-01-01"),
            Account(id: "loan", name: "Loan", kind: .loan, currency: .eur, opened: "2026-02-15"),
        ]
        for account in accounts { library.accounts[account.id] = account }
        library.upsert(Trade(account: "broker", date: "2026-01-15", id: "dep1", type: .deposit, amount: 1000))
        library.upsert(Valuation(account: "bank", date: "2026-01-31", balance: 5000, flow: 5000))
        library.upsert(Valuation(account: "deposit", date: "2026-01-31", balance: 20000, flow: 20000))
        library.upsert(Valuation(account: "broker", date: "2026-01-31", cash: 1000, flow: 1000))
        library.upsert(Valuation(account: "fondo", date: "2026-01-31", balance: 10000))
        library.upsert(Valuation(account: "card", date: "2026-01-31", balance: -200, flow: -200))
        library.upsert(Valuation(account: "mortgage", date: "2026-01-31", balance: -100_000, flow: -100_000))
        return library
    }()

    private func february(_ library: Library? = nil) -> CheckInDraft {
        CheckInDraft(date: "2026-02-28", library: library ?? self.library)
    }

    private func written(_ draft: CheckInDraft, _ account: AccountID, in library: Library? = nil) -> Valuation? {
        draft.review(in: library ?? self.library).row(for: account)?.valuation
    }

    /// A cash account that records trades says what came in and went out
    /// with its deposits and withdrawals, so it asks for neither.
    @Test func aCashAccountRecordingTradesAsksForNoMoneyInOut() throws {
        var library = self.library
        library.accounts["bank"]?.valuation = .trades
        var draft = february(library)
        #expect(draft["bank"]?.asksMoneyInOut == false)
        #expect(draft["bank"]?.canEnterFlow == true)
        // Reviewed, it writes no money in and out, from a statement's cash or with No Trades.
        draft["bank"]?.setCash(5200)
        let fromStatement = try #require(written(draft, "bank", in: library))
        #expect(fromStatement.moneyIn == nil && fromStatement.moneyOut == nil)
        draft["bank"]?.setCash(nil)
        draft["bank"]?.markUnchanged()
        let noTrades = try #require(written(draft, "bank", in: library))
        #expect(noTrades.moneyIn == nil && noTrades.moneyOut == nil)
    }

    /// docs/ACCOUNTS.md, "Pre-filled values".
    @Test func eachKindsPrefilledValues() throws {
        var draft = february()
        draft["bank"]?.setBalance(4800)
        draft["deposit"]?.setBalance(20500)
        draft["card"]?.setBalance(-250)
        draft["mortgage"]?.setBalance(-99_350)
        draft["fondo"]?.setBalance(10300)
        // Cash: money in 0 until typed, money out what that and the change suggest, so moved starts at 0.
        #expect(written(draft, "bank") == Valuation(account: "bank", date: "2026-02-28", balance: 4800, flow: -200,
                                                    moneyIn: 0, moneyOut: 200))
        draft["bank"]?.setMoneyIn(3000)
        #expect(written(draft, "bank")?.moneyOut == 3200)
        // Savings: 0 and 0, interest empty, so moved starts at the whole change.
        #expect(written(draft, "deposit") == Valuation(account: "deposit", date: "2026-02-28", balance: 20500,
                                                       flow: 500, moneyIn: 0, moneyOut: 0))
        // Debts record what's owed; their new money is the whole change, and they don't record money in and out.
        #expect(written(draft, "card") == Valuation(account: "card", date: "2026-02-28", balance: -250, flow: -50))
        #expect(written(draft, "mortgage") == Valuation(account: "mortgage", date: "2026-02-28", balance: -99_350,
                                                        flow: 650))
        // A pension fund's new money is asked for.
        #expect(written(draft, "fondo")?.flow == nil)
        #expect(draft.review(in: library).warnings == [.unknownFlow(account: "fondo")])
        // A trades account with no trades since its previous value waits for a trade or No Trades.
        #expect(draft["broker"]?.state == .notReviewed)
        #expect(written(draft, "broker") == nil)

        // Unchanged: 0 and 0 for either kind.
        draft["bank"]?.markUnchanged()
        draft["deposit"]?.markUnchanged()
        #expect(written(draft, "bank") == Valuation(account: "bank", date: "2026-02-28", balance: 5000, flow: 0,
                                                    moneyIn: 0, moneyOut: 0))
        #expect(written(draft, "deposit") == Valuation(account: "deposit", date: "2026-02-28", balance: 20000,
                                                       flow: 0, moneyIn: 0, moneyOut: 0))
    }

    /// docs/ACCOUNTS.md, "New money": never typed for cash and savings.
    @Test func newMoneyIsWorkedOutAndInterestCountsAsMarket() throws {
        var draft = february()
        draft["deposit"]?.setBalance(20030)
        draft["deposit"]?.setInterest(30)
        // The change less the interest.
        #expect(written(draft, "deposit") == Valuation(account: "deposit", date: "2026-02-28", balance: 20030,
                                                       flow: 0, moneyIn: 0, moneyOut: 0, interest: 30))
        #expect(draft.review(in: library).row(for: "deposit")?.defaultFlow == 0)
        // Typing new money does nothing on cash and savings, nor does interest on a current account.
        draft["deposit"]?.setFlow(999)
        draft["bank"]?.setBalance(5010)
        draft["bank"]?.setFlow(999)
        draft["bank"]?.setInterest(10)
        #expect(draft["deposit"]?.isFlowEdited == false)
        #expect(draft["bank"]?.interest == nil)
        #expect(written(draft, "deposit")?.flow == 0)
        #expect(written(draft, "bank")?.flow == 10)
        #expect(written(draft, "bank")?.interest == nil)

        // Saved, the interest splits the change: 30 market, nothing new.
        draft.markRestUnchanged()
        var saved = library
        draft.apply(to: &saved)
        let change = try #require(Valuator(library: saved).change(from: "2026-01-31", to: "2026-02-28").accounts
            .first { $0.account == "deposit" })
        #expect(change.change.newMoney == 0)
        #expect(change.change.market == 30)

        // A corrected value before it: the flow follows, the interest stays.
        var january = try #require(saved.valuations(for: "deposit").first)
        january.balance = 20100
        saved.saveValue(january, replacing: january.key)
        #expect(saved.valuations(for: "deposit").last?.flow == -100)
        #expect(saved.valuations(for: "deposit").last?.interest == 30)
    }

    /// docs/ACCOUNTS.md, "Moved between your accounts".
    @Test func eachRowsPartInWhatMoved() throws {
        var draft = february()
        draft["bank"]?.setBalance(4800)
        draft["bank"]?.setMoneyIn(3000)
        draft["bank"]?.setMoneyOut(2700)
        draft["deposit"]?.setBalance(20530)
        draft["deposit"]?.setInterest(30)
        draft["card"]?.setBalance(-300)
        draft["mortgage"]?.setBalance(-99_350)
        draft["fondo"]?.setBalance(10300)
        draft["fondo"]?.setFlow(300)
        draft["broker"]?.markUnchanged()
        draft["loan"]?.setBalance(-10_000)
        let review = draft.review(in: library)
        let moved = { (account: AccountID) in review.row(for: account)?.moved }
        // Flow − money in + money out: −200 − 3,000 + 2,700.
        #expect(moved("bank") == -500)
        #expect(Valuation(account: "bank", date: "2026-02-28", flow: -200, moneyIn: 3000, moneyOut: 2700).moved == -500)
        #expect(moved("deposit") == 500)
        // A trades account's part is its flow: nothing since January.
        #expect(moved("broker") == 0)
        // A loan paid out is in the sum, a repayment isn't.
        #expect(moved("loan") == -10_000)
        #expect(moved("mortgage") == 0)
        // Credit cards and pension funds aren't in the sum.
        #expect(moved("card") == nil)
        #expect(moved("fondo") == nil)
        #expect(review.moved == -10_000)
        #expect(review.movedNotCancelledOut == -10_000)
        // Nothing written, nothing moved.
        draft["bank"]?.skip()
        #expect(draft.review(in: library).row(for: "bank")?.moved == nil)
    }

    @Test func aTransferFromTheBankToTheBrokerCancelsOut() throws {
        var library = self.library
        library.upsert(Trade(account: "broker", date: "2026-02-10", id: "dep2", type: .deposit, amount: 500))
        var draft = february(library)
        // The deposit is a trade since its previous value: the row is done, as its trades say.
        #expect(draft["broker"]?.state == .unchanged)
        draft["bank"]?.setBalance(4500)
        // Money out is first what the change suggests, as if the 500 were spent.
        #expect(draft.review(in: library).movedNotCancelledOut == 500)
        // It moved to the broker: nothing went out.
        draft["bank"]?.setMoneyOut(0)
        let review = draft.review(in: library)
        #expect(review.row(for: "bank")?.moved == -500)
        #expect(review.row(for: "broker")?.moved == 500)
        #expect(review.moved == 0)
        #expect(review.movedNotCancelledOut == nil)
    }

    @Test func aLoanPaidOutIntoTheBankCancelsOut() throws {
        var draft = february()
        draft["loan"]?.setBalance(-10_000)
        draft["bank"]?.setBalance(15_000)
        let review = draft.review(in: library)
        #expect(review.row(for: "bank")?.valuation?.moneyOut == 0)
        #expect(review.row(for: "bank")?.moved == 10_000)
        #expect(review.row(for: "loan")?.moved == -10_000)
        #expect(review.moved == 0)
        #expect(review.movedNotCancelledOut == nil)
    }

    @Test func aCardGrowingFromPurchasesAddsNothing() throws {
        var draft = february()
        // 500 spent on the card; 200 of it paid from the bank, which is money out.
        draft["card"]?.setBalance(-500)
        draft["bank"]?.setBalance(4800)
        // The mortgage's 650 repaid from the deposit is money out too.
        draft["mortgage"]?.setBalance(-99_350)
        draft["deposit"]?.setBalance(19_350)
        draft["deposit"]?.setMoneyOut(650)
        let review = draft.review(in: library)
        #expect(review.row(for: "card")?.valuation?.flow == -300)
        #expect(review.row(for: "bank")?.valuation?.moneyOut == 200)
        #expect(review.moved == 0)
        #expect(review.movedNotCancelledOut == nil)
        // Less than 1 either way cancels out.
        draft["bank"]?.setMoneyOut(d("199.5"))
        #expect(draft.review(in: library).moved == d("-0.5"))
        #expect(draft.review(in: library).movedNotCancelledOut == nil)
    }

    @Test func movedIsSummedInTheBaseCurrency() throws {
        var library = self.library
        library.accounts["usd-bank"] = Account(id: "usd-bank", name: "USD bank", kind: .cash, currency: .usd,
                                               opened: "2026-01-01")
        library.upsert(Valuation(account: "usd-bank", date: "2026-01-31", balance: 1000, flow: 1000))
        library.upsert(FXRecord(base: .eur, quote: .usd, date: "2026-02-28", rate: d("1.25")))
        var draft = february(library)
        // 250 USD moved in, 200 EUR moved out of the bank.
        draft["usd-bank"]?.setBalance(1250)
        draft["bank"]?.setBalance(4800)
        draft["bank"]?.setMoneyOut(0)
        let review = draft.review(in: library)
        #expect(review.row(for: "usd-bank")?.moved == 250)
        #expect(review.moved == 0)
    }

    /// A draft kept on the device before this change: snapshot rows with
    /// what was paid, and rows without their kind or `hasNewTrades`.
    @Test func aDraftSavedBeforeThisChangeStillDecodes() throws {
        var library = self.library
        library.accounts["coins"] = Account(id: "coins", name: "Coins", kind: .metals, currency: .eur,
                                            opened: "2026-01-01", valuation: .holdings)
        library.instruments["gold"] = Instrument(id: "gold", name: "Gold", kind: .metal, currency: .eur, unit: .gram,
                                                 assetClasses: .single(.gold))
        library.upsert(PriceRecord(instrument: "gold", date: "2026-01-31", price: 60, currency: .eur))
        library.upsert(Valuation(account: "coins", date: "2026-01-31",
                                 positions: [Position(instrument: "gold", quantity: 10, costBasis: 600)]))
        let json = """
            {
              "date": "2026-02-28",
              "rows": [
                { "account": "bank", "state": "updated", "mode": "balance",
                  "previous": { "account": "bank", "date": "2026-01-31", "balance": "5000", "flow": "5000" },
                  "balance": "4800", "isFlowEdited": true, "enteredFlow": "-150", "moneyIn": "3000",
                  "isEdited": true, "resetsFlowOnEdit": false },
                { "account": "broker", "state": "unchanged", "mode": "trades", "isTrades": true,
                  "previous": { "account": "broker", "date": "2026-01-31", "cash": "1000", "flow": "1000" },
                  "derived": { "account": "broker", "date": "2026-02-28", "cash": "1000" },
                  "cash": "1000", "isFlowEdited": false, "isEdited": false, "resetsFlowOnEdit": false },
                { "account": "coins", "state": "updated", "mode": "holdings",
                  "previous": { "account": "coins", "date": "2026-01-31",
                                "positions": [{ "instrument": "gold", "quantity": "10", "costBasis": "600" }] },
                  "cash": "0",
                  "positions": [{ "instrument": "gold", "previousQuantity": "10", "previousCostBasis": "600",
                                  "quantity": "15", "paid": "320" }],
                  "isFlowEdited": false, "isEdited": true, "resetsFlowOnEdit": false }
              ],
              "prices": [],
              "fxRates": []
            }
            """
        var old = try JSONDecoder().decode(CheckInDraft.self, from: Data(json.utf8))
        // The snapshot row keeps nothing; the trades row is no longer done as its trades said.
        #expect(old["coins"]?.state == .notReviewed)
        #expect(old["coins"]?.mode == .balance)
        #expect(old["coins"]?.positions.isEmpty == true)
        #expect(old["broker"]?.state == .notReviewed)
        #expect(old["bank"]?.state == .updated)
        #expect(old["bank"]?.moneyIn == 3000)

        // Rebasing fills them in again: the kind comes back, what was typed stays, and a typed flow goes.
        old.rebase(onto: library)
        #expect(old["bank"]?.kind == .cash)
        #expect(old["bank"]?.balance == 4800)
        #expect(old["bank"]?.isFlowEdited == false)
        #expect(written(old, "bank") == Valuation(account: "bank", date: "2026-02-28", balance: 4800, flow: -200,
                                                  moneyIn: 3000, moneyOut: 3200))
        #expect(old["broker"]?.kind == .brokerage)
        #expect(old["broker"]?.hasNewTrades == false)
        #expect(old["broker"]?.state == .notReviewed)
        #expect(old["coins"]?.kind == .metals)
        #expect(old["coins"]?.state == .notReviewed)
        #expect(written(old, "coins") == nil)
    }
}
