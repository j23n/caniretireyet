import Foundation
import Model
import Testing
import TestSupport
@testable import Tracker

/// The audit's consistency checks (``AuditChecks``): each rule found where
/// it's broken, and nowhere in a month whose numbers agree.
struct AuditChecksTests {
    /// The month of `WhatMovedTests`: pay of 4,000 into the current account,
    /// which pays rent and groceries, the card's bill, 1,000 to the broker
    /// and the mortgage (500 principal); 300 paid into the pension fund by
    /// the employer. It saves 1,450 of the 4,300 that came in.
    let month: Library = {
        var library = Library(settings: LibrarySettings(baseCurrency: .eur))
        let accounts = [
            Account(id: "bank", name: "Bank", kind: .cash, currency: .eur, opened: "2025-12-01"),
            Account(id: "card", name: "Card", kind: .creditCard, currency: .eur, opened: "2025-12-01"),
            Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur, opened: "2025-12-01",
                    valuation: .trades),
            Account(id: "fondo", name: "Fondo", kind: .pensionFund, currency: .eur, opened: "2025-12-01"),
            Account(id: "mortgage", name: "Mortgage", kind: .mortgage, currency: .eur, opened: "2025-12-01"),
        ]
        for account in accounts { library.accounts[account.id] = account }
        library.upsert(Valuation(account: "bank", date: "2025-12-31", balance: 10000, saved: 10000))
        library.upsert(Valuation(account: "card", date: "2025-12-31", balance: -300, saved: -300))
        library.upsert(Valuation(account: "broker", date: "2025-12-31", cash: 0, saved: 0))
        library.upsert(Valuation(account: "fondo", date: "2025-12-31", balance: 5000))
        library.upsert(Valuation(account: "mortgage", date: "2025-12-31", balance: -100_000))
        library.upsert(Trade(account: "broker", date: "2026-01-26", id: "dep1", type: .deposit, amount: 1000))
        library.upsert(Valuation(account: "bank", date: "2026-01-31", balance: 9450, saved: -550, moneyIn: 4000,
                                 moneyOut: 4550))
        library.upsert(Valuation(account: "card", date: "2026-01-31", balance: -100, saved: 200))
        library.upsert(Valuation(account: "broker", date: "2026-01-31", cash: 1000, saved: 1000))
        library.upsert(Valuation(account: "fondo", date: "2026-01-31", balance: 5300, saved: 300))
        library.upsert(Valuation(account: "mortgage", date: "2026-01-31", balance: -99500, saved: 500))
        return library
    }()

    /// The current account's lines for the month: pay, rent, the card's
    /// bill, the broker, the mortgage, adding up to its −550.
    func lines(_ amounts: [Decimal] = [4000, -1800, -1100, -1000, -650]) -> [BankLine] {
        amounts.enumerated().map { index, amount in
            BankLine(account: "bank", date: CalendarDate(year: 2026, month: 1, day: 5 + index) ?? "2026-01-05",
                     id: BankLineID(rawValue: "l\(index)"), amount: amount,
                     statementClass: amount > 0 ? .income : .spending)
        }
    }

    @Test func aMonthWhoseNumbersAgreeHasNoViolations() {
        var library = month
        for line in lines() { library.upsert(line) }
        let checks = AuditChecks(library: library)
        #expect(checks.violations().isEmpty)
        // It saved 1,450 of 4,300: a rate of about 34%.
        #expect(checks.valuator.savingsRate(from: "2026-01-01", through: "2026-01-31")?.rate
            == Decimal(1450) / 4300)
    }

    @Test func findsLinesThatDontAddUp() throws {
        var library = month
        // The mortgage's line is missing: the lines lead to 10,100, not 9,450.
        for line in lines([4000, -1800, -1100, -1000]) { library.upsert(line) }
        let violations = AuditChecks(library: library).violations()
        let violation = try #require(violations.first)
        #expect(violations.count == 1)
        #expect(violation.rule == .linesDontAddUp)
        #expect(violation.date == "2026-01-31" && violation.account == "bank")
        #expect(violation.amounts.first == AuditViolation.Amount("difference", -650))
        // A stretch after the last value has no balance to add up to.
        library.upsert(BankLine(account: "bank", date: "2026-02-03", id: "late", amount: -40,
                                statementClass: .spending))
        #expect(AuditChecks(library: library).lineStretches().count == 1)
        // Through a date before the value, there's nothing to check.
        #expect(AuditChecks(library: library).violations(through: "2026-01-30").isEmpty)
    }

    @Test func findsPositionsTheTradesDontGive() throws {
        var library = month
        library.upsert(Valuation(account: "broker", date: "2026-01-31", cash: 1000,
                                 positions: [Position(instrument: "vwce", quantity: 5)], saved: 1000))
        let violations = AuditChecks(library: library).violations()
        #expect(violations == [AuditViolation(rule: .positionMismatch, date: "2026-01-31", account: "broker",
                                              instrument: "vwce",
                                              amounts: [.init("listed", 5), .init("derived", 0)])])
    }

    @Test func findsAMonthSavingMoreThanCameIn() throws {
        var library = month
        // Only 100 recorded as money in: 1,450 saved of 400.
        library.upsert(Valuation(account: "bank", date: "2026-01-31", balance: 9450, saved: -550, moneyIn: 100,
                                 moneyOut: 4550))
        let violations = AuditChecks(library: library).violations()
        let violation = try #require(violations.first)
        #expect(violations.map(\.rule) == [.monthlyRateOutOfRange])
        #expect(violation.date == "2026-01-31" && violation.account == nil)
        #expect(violation.amounts.map(\.name) == ["rate", "savedFromPay", "cameIn"])
        #expect(violation.amounts[0].value == Decimal(1450) / 400)
        #expect(AuditChecks.plausibleMonthlyRates.contains(1) && !AuditChecks.plausibleMonthlyRates.contains(-0.51))
    }

    @Test func findsAnAccountThatStartedWithMoreThanCameIn() throws {
        var library = month
        // A savings account whose records start with 50,000 that nothing tracked paid for.
        library.accounts["savings"] = Account(id: "savings", name: "Savings", kind: .savings, currency: .eur,
                                              opened: "2026-01-01")
        library.upsert(Valuation(account: "savings", date: "2026-01-31", balance: 50000))
        let checks = AuditChecks(library: library)
        let violations = checks.violations()
        #expect(violations == [AuditViolation(rule: .startedWithAboveMoneyIn, date: "2026-01-31", account: "savings",
                                              amounts: [.init("startedWith", 50000), .init("moneyIn", 4000)])])
        // Its first value is what it started with, not unexplained.
        let moved = checks.valuator.whatMoved(checks.valuator.change(from: "2025-12-31", to: "2026-01-31"))
        #expect(moved.startedWith == 50000 && moved.unexplained == 0)

        // Below the month's money in, it's left alone.
        library.upsert(Valuation(account: "savings", date: "2026-01-31", balance: 3000))
        #expect(AuditChecks(library: library).violations().isEmpty)
    }

    @Test func anUnexplainedPartIsAViolationOnlyWhenEverythingIsKnown() throws {
        let checks = AuditChecks(library: month)
        let report = checks.valuator.change(from: "2025-12-31", to: "2026-01-31")
        let moved = checks.valuator.whatMoved(report)
        #expect(moved.unexplained == 0)
        // What moved it, with 25 of the change unexplained.
        let off = WhatMoved(from: moved.from, to: moved.to, start: moved.start, change: moved.change,
                            saved: moved.saved, markets: moved.markets - 25, pay: moved.pay)
        let violations = checks.unexplainedChanges([AuditChecks.Step(report: report, moved: off)])
        #expect(violations == [AuditViolation(rule: .unexplainedChange, date: "2026-01-31",
                                              amounts: [.init("unexplained", 25), .init("change", moved.change)])])
        // A remainder of the arithmetic's last digits is rounding.
        let rounding = WhatMoved(from: moved.from, to: moved.to, start: moved.start, change: moved.change,
                                 saved: moved.saved, markets: moved.markets - Decimal(string: "1e-30")!,
                                 pay: moved.pay)
        #expect(checks.unexplainedChanges([AuditChecks.Step(report: report, moved: rounding)]).isEmpty)

        // A pension fund valued without what was paid in: its change is
        // unexplained, as expected, and not a violation.
        var library = month
        library.upsert(Valuation(account: "fondo", date: "2026-01-31", balance: 5300))
        let unknown = AuditChecks(library: library)
        let step = try #require(unknown.checkInSteps(through: nil).first)
        #expect(step.moved.unexplained == 300)
        #expect(unknown.unexplainedChanges().isEmpty)
    }

    @Test func findsWhatMovedItAndTheBarsDisagreeing() {
        let checks = AuditChecks(library: month)
        let report = checks.valuator.change(from: "2025-12-31", to: "2026-01-31")
        let moved = checks.valuator.whatMoved(report)
        #expect(checks.savedDisagreements().isEmpty)
        let off = WhatMoved(from: moved.from, to: moved.to, start: moved.start, change: moved.change,
                            saved: moved.saved + 10, markets: moved.markets - 10, pay: moved.pay)
        #expect(checks.savedDisagreements([AuditChecks.Step(report: report, moved: off)])
            == [AuditViolation(rule: .savedDisagrees, date: "2026-01-31",
                               amounts: [.init("whatMoved", 1460), .init("savedSplit", 1450)])])
    }

    /// The made-up example library breaks none of the rules: its statement
    /// lines and broker quantities agree with its values, its months are
    /// plausible, and what's left unexplained where everything is known is
    /// rounding in the last of `Decimal`'s digits.
    @Test func theExampleLibrary() throws {
        let violations = AuditChecks(library: try Fixtures.exampleLibrary()).violations()
        #expect(violations.isEmpty, "\(violations)")
    }
}
