import Foundation
import Model
import Tracker

/// What `retire audit --explain <date>` prints: one check-in's numbers
/// account by account, to compare with bank and broker statements. Each
/// account's change since the check-in before (start, saved, markets,
/// other, lost, end) in the base currency, and in its own when that's
/// another; *What moved it*; and the pay: each cash and savings account's
/// money in and out and tax, what went into pension funds and TFR, and
/// what that leaves spent and saved.
struct AuditExplainReport: CommandReport {
    let date: CalendarDate
    /// The check-in before; `nil` for the first.
    let previous: CalendarDate?
    let currency: CurrencyCode
    /// Each account in net worth: its value on the date, or since the
    /// check-in before its change.
    let accounts: [AccountChange]
    /// The same accounts in their own currencies, those not in the base currency.
    let ownCurrency: [(account: AccountChange, currency: CurrencyCode)]
    /// What the accounts whose records start in the days started with, and
    /// what of their first amount counts as saved; and, for an account
    /// whose records started earlier (`isNew` false), what money moved in
    /// the days paid for of what it started with, below zero.
    let firsts: [(account: AccountID, saved: Decimal, startedWith: Decimal, isNew: Bool)]
    let moved: WhatMoved?
    /// Each cash and savings account's money in and out over the days.
    let money: [(account: AccountID, summary: MoneyInOutSummary)]
    /// What each pension fund and TFR saved, at least zero.
    let pensions: [(account: AccountID, amount: Decimal)]
    /// What moved into tax pots outside net worth.
    let taxSetAside: Decimal

    /// The check-in on `date`, which must be one: a date with a value of an account.
    init(library: Library, date: CalendarDate) throws {
        let valuator = Valuator(library: library)
        let dates = valuator.checkInDates()
        guard dates.contains(date) else {
            let before = dates.last { $0 < date }.map { "the one before is \($0)" }
            let after = dates.first { $0 > date }.map { "the one after is \($0)" }
            let near = [before, after].compactMap { $0 }.joined(separator: " and ")
            throw CLIError("There's no check-in on \(date)" + (near.isEmpty ? "." : ": \(near)."))
        }
        self.date = date
        currency = library.settings.baseCurrency
        previous = valuator.previousCheckIn(before: date)
        guard let previous else {
            // The first check-in: each account's value, with nothing to compare it with.
            let report = valuator.change(from: date, to: date)
            accounts = report.accounts
            ownCurrency = []
            firsts = []
            moved = nil
            money = []
            pensions = []
            taxSetAside = 0
            return
        }
        let report = valuator.change(from: previous, to: date)
        accounts = report.accounts
        let base = currency
        ownCurrency = report.accounts.compactMap { change in
            guard let account = library.accounts[change.account], account.currency != base,
                  let own = valuator.change(of: change.account, from: previous, to: date, in: .account)
            else { return nil }
            return (own, account.currency)
        }
        let stretches = valuator.savedStretches(
            between: valuator.savedCuts(after: previous, through: date, in: .netWorth), in: .netWorth)
        var started: [AccountID: Decimal] = [:]
        var saved: [AccountID: Decimal] = [:]
        for stretch in stretches {
            started.merge(stretch.startedWith, uniquingKeysWith: +)
            saved.merge(stretch.saved, uniquingKeysWith: +)
        }
        firsts = started.keys.sorted().map { id in
            (id, saved[id] ?? 0, started[id] ?? 0, valuator.firstRecordDate(of: id).map { $0 > previous } ?? false)
        }
        let moved = valuator.whatMoved(report)
        self.moved = moved
        let cash = valuator.cameInAccounts.sorted()
        money = cash.compactMap { id in
            let summary = valuator.moneyInOut(from: previous.adding(days: 1), through: date, accounts: [id])
            return summary.isEmpty ? nil : (id, summary)
        }
        pensions = saved.keys.sorted().compactMap { id in
            guard let kind = library.accounts[id]?.kind, SavingsRate.pensionKinds.contains(kind) else { return nil }
            return (id, max(saved[id] ?? 0, 0))
        }
        taxSetAside = valuator.taxSetAside(after: previous, through: date).amount
    }

    func lines() -> [String] {
        let since = previous.map { ", since the check-in on \($0)" } ?? ", the first check-in"
        var lines = ["Check-in \(date)\(since), in \(currency.rawValue)", ""]
        lines += changeTable(accounts, withTotal: "Net worth")
        if !ownCurrency.isEmpty {
            lines.append("")
            lines.append("In each account's own currency")
            var table = Self.changeColumns()
            for (change, currency) in ownCurrency {
                table.add(Self.row("\(change.account) (\(currency.rawValue))", change.change, saved: change.saved))
            }
            lines += table.lines()
        }
        for first in firsts {
            if first.isNew {
                lines.append("\(first.account)'s records start since the check-in before: "
                    + "\(Format.amount(first.saved)) of its first amount counts as saved, "
                    + "\(Format.amount(first.startedWith)) as what it started with.")
            } else if first.startedWith < 0 {
                lines.append("\(first.account)'s records started in days a value on this date covers: money moved "
                    + "in them pays for \(Format.amount(-first.startedWith)) of what it started with, "
                    + "which counts as saved.")
            } else {
                lines.append("\(first.account)'s records started in days a value on this date covers: money moved "
                    + "in them pays for \(Format.amount(first.startedWith)) less of what it started with than "
                    + "the check-ins before counted as saved.")
            }
        }
        guard let moved else { return lines }

        lines.append("")
        lines.append("What moved it")
        var parts = TextTable([.left(""), .right("")], showsHeader: false)
        parts.add(["Saved", Format.signed(moved.saved)])
        parts.add(["Markets", Format.signed(moved.markets)])
        parts.add(["One-offs", Format.signed(moved.oneOffs)])
        parts.add(["Started with", Format.signed(moved.startedWith)])
        parts.add(["Lost", Format.signed(moved.lost)])
        parts.add(["Unexplained", Format.signed(moved.unexplained)])
        parts.add(["Change", Format.signed(moved.change)])
        lines += parts.lines()
        if !moved.isPriced { lines.append("A price or an exchange rate is missing: some parts may be wrong.") }

        guard let pay = moved.pay else {
            lines.append("")
            lines.append("No pay: no cash or savings account recorded money in and out since the check-in before.")
            return lines
        }
        lines.append("")
        lines.append("Your pay, \(previous.map { $0.adding(days: 1).description } ?? "") to \(date)")
        var table = TextTable([.left("Account"), .right("Money in"), .right("Money out"), .right("Tax"),
                               .right("One-off")])
        for (account, summary) in money {
            table.add([account.rawValue, Format.amount(summary.moneyIn), Format.amount(summary.moneyOut),
                       Format.amount(summary.taxes), Format.amount(summary.oneOffs)])
        }
        lines += table.lines()
        if !pensions.isEmpty {
            var paid = TextTable([.left("Pension"), .right("Paid in")])
            for (account, amount) in pensions { paid.add([account.rawValue, Format.amount(amount)]) }
            lines.append("")
            lines += paid.lines()
        }
        lines.append("")
        var totals = TextTable([.left(""), .right("")], showsHeader: false)
        totals.add(["Money in", Format.amount(pay.moneyIn)])
        totals.add(["Into pensions", Format.amount(pay.pension)])
        totals.add(["Came in", Format.amount(pay.cameIn)])
        if taxSetAside != 0 { totals.add(["Tax set aside", Format.amount(taxSetAside)]) }
        totals.add(["Tax", Format.amount(pay.tax)])
        totals.add(["After tax", Format.amount(pay.afterTax)])
        totals.add(["Saved", Format.amount(pay.saved)])
        totals.add(["Spent", Format.amount(pay.spent)])
        totals.add(["Savings rate", Format.percent(pay.savedShare)])
        lines += totals.lines()
        return lines
    }

    /// The columns of an account's change.
    static func changeColumns() -> TextTable {
        TextTable([.left("Account"), .right("Start"), .right("Saved"), .right("Markets"), .right("Other"),
                   .right("Lost"), .right("End")])
    }

    /// One account's change as a row; saved marked `?` when its values' isn't known.
    static func row(_ name: String, _ change: ValueChange, saved: Decimal?) -> [String] {
        [name, Format.amount(change.start), Format.signed(change.saved) + (saved == nil ? "?" : ""),
         Format.signed(change.market), Format.signed(change.other), Format.signed(change.lost),
         Format.amount(change.end)]
    }

    /// The accounts' changes as a table, with their total.
    func changeTable(_ changes: [AccountChange], withTotal total: String) -> [String] {
        var table = Self.changeColumns()
        for change in changes { table.add(Self.row(change.account.rawValue, change.change, saved: change.saved)) }
        let sum = changes.reduce(ValueChange.zero) { $0 + $1.change }
        table.add(Self.row(total, sum, saved: 0))
        var lines = table.lines()
        if changes.contains(where: { $0.saved == nil }) {
            lines.append("? what its values saved isn't known: its first value, a balance without its saved amount, "
                + "or a missing price or rate.")
        }
        return lines
    }

    var json: JSON {
        let exact: (Decimal) -> String = AuditNumber.exact
        return JSON(
            date: date.description, previous: previous?.description, currency: currency.rawValue,
            accounts: accounts.map { change in
                JSON.Account(account: change.account.rawValue, currency: nil, change: Audit.Change(change.change),
                             savedKnown: change.isSavedKnown)
            },
            ownCurrency: ownCurrency.isEmpty ? nil : ownCurrency.map { change, currency in
                JSON.Account(account: change.account.rawValue, currency: currency.rawValue,
                             change: Audit.Change(change.change), savedKnown: change.isSavedKnown)
            },
            startedWith: firsts.isEmpty ? nil : Dictionary(uniqueKeysWithValues: firsts.map {
                ($0.account.rawValue, exact($0.startedWith))
            }),
            whatMoved: moved.map(Audit.Moved.init),
            money: money.isEmpty ? nil : money.map { account, summary in
                JSON.Money(account: account.rawValue, moneyIn: exact(summary.moneyIn),
                           moneyOut: exact(summary.moneyOut), tax: exact(summary.taxes),
                           oneOff: exact(summary.oneOffs))
            },
            pensions: pensions.isEmpty ? nil : Dictionary(uniqueKeysWithValues: pensions.map {
                ($0.account.rawValue, exact($0.amount))
            }),
            taxSetAside: moved?.pay == nil ? nil : exact(taxSetAside))
    }

    struct JSON: Encodable {
        struct Account: Encodable {
            var account: String
            /// The account's own currency, in `ownCurrency`.
            var currency: String?
            var change: Audit.Change
            var savedKnown: Bool
        }

        struct Money: Encodable {
            var account: String
            var moneyIn: String
            var moneyOut: String
            var tax: String
            var oneOff: String
        }

        var date: String
        var previous: String?
        var currency: String
        var accounts: [Account]
        var ownCurrency: [Account]?
        var startedWith: [String: String]?
        var whatMoved: Audit.Moved?
        var money: [Money]?
        var pensions: [String: String]?
        var taxSetAside: String?
    }
}
