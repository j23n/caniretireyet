import Foundation
import Model

/// The statement layout (docs/IMPORT.md, "Bank statements"): the lines of
/// one cash or savings account's statement, classified, become the
/// account's values with a balance and money in and out.
extension PreviewBuilder {
    /// How many days apart a line and a trade moving the same amount can be
    /// to be one transfer.
    static let transferDays = 4

    /// A line as the file gives it, before it's classified.
    private struct ReadLine {
        var row: Int
        var date: CalendarDate
        var amount: Decimal
        var text: String
        var sender: String
        var balance: Decimal?
        var cells: [ImportCellRef]
    }

    /// Reads the lines, classifies them (``statementLines``) and works out
    /// the account's values: one at each of its values in the file's span,
    /// and one at each month end of a month that has none.
    mutating func statementRecords(dateColumn: Int, dates: DateParser) -> [ImportRecordKey: Accumulator] {
        guard let id = profile.constants.account else {
            issues.append(ImportIssue(kind: .missingField(.account)))
            return [:]
        }
        guard let account = library.accounts[id] else {
            issues.append(ImportIssue(kind: .unknownAccount(id)))
            return [:]
        }
        guard account.kind.recordsMoneyInOut, !account.recordsTrades else {
            issues.append(ImportIssue(kind: .noMoneyInOut(id)))
            return [:]
        }
        let read = readStatementLines(dateColumn: dateColumn, dates: dates)
        guard !read.isEmpty else { return [:] }
        var lines = classify(read, account: account)
        var records = statementValues(&lines, read: read, account: account)
        records.merge(statementAssetRecords(&lines, read: read, account: account)) { $1 }
        statementLines = lines
        return records
    }

    // MARK: - Reading

    /// The file's lines in date order: a file that lists the newest first
    /// is read backwards, so lines on one day keep the order they happened in.
    private mutating func readStatementLines(dateColumn: Int, dates: DateParser) -> [ReadLine] {
        var single: [ImportField: Int] = [:]
        var texts: [Int] = []
        var counterparties: [Int] = []
        for (column, index) in bindings.columns.sorted(by: { $0.key < $1.key }) {
            guard let field = profile.columns[index].field else { continue }
            switch field {
            case .description: texts.append(column)
            case .counterparty:
                texts.append(column)
                counterparties.append(column)
            case .amount, .credit, .debit, .balance: if single[field] == nil { single[field] = column }
            default: continue
            }
        }
        let amountColumns = [ImportField.amount, .credit, .debit].compactMap { single[$0] }
        guard !amountColumns.isEmpty else {
            issues.append(ImportIssue(kind: .missingField(.amount)))
            return []
        }
        let parsers = Dictionary(uniqueKeysWithValues: single.map { field, column in
            (field, NumberParser(format: session.effectiveFormat(forColumn: column).number ?? ImportNumberFormat()))
        })

        var lines: [ReadLine] = []
        rows: for row in table.rows {
            guard amountColumns.contains(where: { !row[$0].isEmpty }) else { continue }
            let dateText = row[dateColumn]
            guard !dateText.isEmpty else {
                fail(row.number, dateColumn, dateText, .missingDate)
                continue
            }
            guard let date = parseDate(dateText, row: row.number, column: dateColumn, with: dates) else { continue }
            var amount: Decimal = 0
            var cells: [ImportCellRef] = []
            var balance: Decimal?
            for field in [ImportField.amount, .credit, .debit, .balance] {
                guard let column = single[field], let parser = parsers[field] else { continue }
                let text = row[column]
                guard !text.isEmpty else { continue }
                guard let number = parseNumber(text, row: row.number, column: column, with: parser, empty: .skip)
                else { continue rows }
                switch field {
                case .amount: amount += number.value
                case .credit: amount += abs(number.value)
                case .debit: amount -= abs(number.value)
                default: balance = number.value
                }
                cells.append(ImportCellRef(row: row.number, column: column))
            }
            let text = texts.map { row[$0] }.filter { !$0.isEmpty }.joined(separator: " · ")
            let counterparty = StatementWords.sender(of: counterparties.map { row[$0] }.joined(separator: " "))
            lines.append(ReadLine(row: row.number, date: date, amount: amount, text: text,
                                  sender: counterparty.isEmpty ? StatementWords.sender(of: text) : counterparty,
                                  balance: balance, cells: cells))
        }
        if let first = lines.first, let last = lines.last, first.date > last.date { lines.reverse() }
        // A stable sort: lines on one day keep their order.
        return lines.enumerated().sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
            .map(\.element)
    }

    // MARK: - Classifying

    /// Each line's class and why: chosen for the line, a rule, a trade of
    /// another account moving the same amount, a line of another account's
    /// statement imported with it moving it the other way, another account named in
    /// the text, the usual words; for money in, a sender paid before or a
    /// recurring one; else the sign. Then the money in that needs an answer.
    private func classify(_ read: [ReadLine], account: Account) -> [StatementLine] {
        let names = accountNames(excluding: account)
        let answered = answeredAssets(read, account: account)
        let open = read.indices.filter { index in
            session.statementLineClasses[read[index].row] == nil && session.statementRule(for: read[index].text) == nil
                && answered[read[index].row] == nil && session.statementPairs[read[index].row] == nil
        }
        let trades = matchTrades(read, lines: open, excluding: account.id)
        var lines = read.indices.map { index in
            let line = read[index]
            let chosen: (StatementClass, StatementLine.Source)
            if answered[line.row] != nil {
                // A purchase or a sale moves money between your accounts.
                chosen = (.transfer, .chosen)
            } else if let statementClass = session.statementLineClasses[line.row] {
                chosen = (statementClass, .chosen)
            } else if let rule = session.statementRule(for: line.text) {
                chosen = (rule.statementClass, .rule(rule.match))
            } else if let trade = trades[index] {
                chosen = (.transfer, .trade(trade))
            } else if let other = session.statementPairs[line.row] {
                chosen = (.transfer, .paired(other))
            } else if let named = Self.namedAccount(in: line.text, names: names) {
                // Paying a debt is spending; a loan paid out into the account is moved between accounts.
                chosen = (named.isLiability && line.amount < 0 ? .spending : .transfer, .account(named.id))
            } else if let suggested = StatementWords.suggestion(for: line.text, amount: line.amount) {
                chosen = (suggested, .words)
            } else if line.amount > 0, Self.paidBefore(line, in: read) {
                chosen = (.paidBack, .paidBefore)
            } else {
                chosen = (line.amount >= 0 ? .paidBack : .spending, .sign)
            }
            return StatementLine(row: line.row, date: line.date, amount: line.amount, text: line.text,
                                 sender: line.sender, balance: line.balance, statementClass: chosen.0,
                                 source: chosen.1)
        }
        Self.markRecurring(&lines)
        Self.markQuestions(&lines)
        let firstDate = read.first?.date
        let history = library.valuations(for: account.id).filter { date in firstDate.map { date.date < $0 } ?? false }
            .suffix(12).compactMap(\.moneyOut)
        Self.markPurchaseQuestions(&lines, history: history)
        return lines
    }

    /// How many days before money in a payment to its sender can be for
    /// the money in to be paid back.
    static let paidBackDays = 90

    /// Whether the file paid at least `line`'s amount to its sender in the
    /// days before it: a refund, or a share of a bill paid back.
    private static func paidBefore(_ line: ReadLine, in read: [ReadLine]) -> Bool {
        guard !line.sender.isEmpty else { return false }
        let since = line.date.adding(days: -paidBackDays)
        return read.contains { out in
            out.amount <= -line.amount && out.date >= since && out.date <= line.date
                && TextTools.words(out.sender) == TextTools.words(line.sender)
        }
    }

    /// Money in classified by its sign alone from a sender who pays similar
    /// amounts (within a quarter of their median) in at least 3 of the
    /// file's months is income: those lines and any smaller ones (pay before
    /// a raise, a partial month). A larger line from the sender keeps its
    /// sign's class and needs an answer, whatever its size.
    private static func markRecurring(_ lines: inout [StatementLine]) {
        let open = lines.indices.filter { index in
            lines[index].source == .sign && lines[index].amount > 0 && !lines[index].sender.isEmpty
        }
        let senders = Dictionary(grouping: open) { TextTools.words(lines[$0].sender) }
        for indices in senders.values {
            let amounts = indices.map { lines[$0].amount }.sorted()
            let median = amounts[amounts.count / 2]
            let similar = indices.filter { abs(lines[$0].amount - median) <= median / 4 }
            guard Set(similar.map { lines[$0].date.yearMonth }).count >= 3 else { continue }
            for index in indices {
                if lines[index].amount > median + median / 4 {
                    lines[index].needsAnswer = true
                } else {
                    lines[index].statementClass = .income
                    lines[index].source = .recurring
                }
            }
        }
    }

    /// Money in classified by its sign alone that is more than a typical
    /// month's spending in the file (the median of its months' money out)
    /// needs an answer: income, a one-off or paid back.
    private static func markQuestions(_ lines: inout [StatementLine]) {
        let spending = lines.filter { $0.amount < 0 && $0.statementClass == .spending }
        let months = Dictionary(grouping: spending, by: \.date.yearMonth).values
            .map { $0.reduce(Decimal(0)) { $0 - $1.amount } }.sorted()
        guard !months.isEmpty else { return }
        let typical = months[months.count / 2]
        for index in lines.indices where lines[index].source == .sign && lines[index].amount > typical {
            lines[index].needsAnswer = true
        }
    }

    /// Money out classified by its sign alone that is more than a typical
    /// month's spending needs an answer: spending, or a purchase you keep.
    /// The typical month is the median of the file's months' money out
    /// without the line itself, and of `history`, the money out of the
    /// account's last 12 values before the file; a month whose only
    /// spending is the line doesn't count.
    private static func markPurchaseQuestions(_ lines: inout [StatementLine], history: [Decimal]) {
        let spending = lines.indices.filter { lines[$0].amount < 0 && lines[$0].statementClass == .spending }
        var months: [YearMonth: (total: Decimal, count: Int)] = [:]
        for index in spending {
            let month = months[lines[index].date.yearMonth] ?? (0, 0)
            months[lines[index].date.yearMonth] = (month.total - lines[index].amount, month.count + 1)
        }
        for index in spending where lines[index].source == .sign {
            let own = lines[index].date.yearMonth
            var totals = history
            for (month, spent) in months {
                if month != own {
                    totals.append(spent.total)
                } else if spent.count > 1 {
                    totals.append(spent.total + lines[index].amount)
                }
            }
            guard !totals.isEmpty else { continue }
            totals.sort()
            if -lines[index].amount > totals[totals.count / 2] { lines[index].needsAnswer = true }
        }
    }

    /// The library's trades of other accounts that move money from or to a
    /// bank account: deposits and withdrawals, and buys, sales, fees and
    /// taxes paid from outside their account, each with the amount it puts
    /// on the bank's statement (a deposit of 500 is −500 there).
    private func transferTrades(excluding account: AccountID) -> [(trade: Trade, amount: Decimal)] {
        library.allTrades.compactMap { trade in
            guard trade.account != account, let amount = trade.amount else { return nil }
            if trade.type == .deposit || trade.type == .withdrawal { return (trade, -amount) }
            if trade.isSettledExternally, [.buy, .sell, .fee, .tax].contains(trade.type) { return (trade, amount) }
            return nil
        }
    }

    /// The trades that the `lines` (indices into `read`) are, by line:
    /// trades moving a line's amount within ``transferDays``, each matching
    /// one line, the nearest pairs first.
    private func matchTrades(_ read: [ReadLine], lines: [Int], excluding account: AccountID) -> [Int: TradeKey] {
        let trades = transferTrades(excluding: account)
        var pairs: [(line: Int, trade: Int, days: Int)] = []
        for line in lines {
            for (index, trade) in trades.enumerated() where trade.amount == read[line].amount {
                let days = abs(trade.trade.date.days(to: read[line].date))
                if days <= Self.transferDays { pairs.append((line, index, days)) }
            }
        }
        var matched: [Int: TradeKey] = [:]
        var used = Set<Int>()
        for pair in pairs.sorted(by: { ($0.days, $0.line, $0.trade) < ($1.days, $1.line, $1.trade) })
        where matched[pair.line] == nil && !used.contains(pair.trade) {
            matched[pair.line] = trades[pair.trade].trade.key
            used.insert(pair.trade)
        }
        return matched
    }

    /// The names that stand for the library's other accounts in a line's
    /// text: each account's name, and its institution when it isn't this
    /// account's bank. Names of four letters or fewer, and names made only
    /// of words any account could have (`Conto corrente`, `Savings`,
    /// `Credit card`), say too little.
    private func accountNames(excluding account: Account) -> [(phrase: String, id: AccountID, isLiability: Bool)] {
        let generic = Set(Keywords.genericAccountWords)
        let ownBank = account.institution.map(TextTools.words)
        var names: [(phrase: String, id: AccountID, isLiability: Bool)] = []
        for other in library.accounts.values.sorted(by: { $0.id < $1.id }) where other.id != account.id {
            var candidates = [TextTools.words(other.name)]
            if let institution = other.institution.map(TextTools.words), institution != ownBank {
                candidates.append(institution)
            }
            for words in candidates where words.joined().count > 4 && !words.allSatisfy(generic.contains) {
                names.append((words.joined(separator: " "), other.id, other.kind.isLiability))
            }
        }
        return names
    }

    /// The account whose name is the longest one the text has.
    private static func namedAccount(in text: String, names: [(phrase: String, id: AccountID, isLiability: Bool)])
        -> (id: AccountID, isLiability: Bool)? {
        let words = TextTools.words(text)
        return names.filter { TextTools.contains(words, anyOf: [$0.phrase]) }
            .max { $0.phrase.count < $1.phrase.count }.map { ($0.id, $0.isLiability) }
    }

    // MARK: - Purchases and sales

    /// The session's answers as a purchase or a sale that the import can
    /// record, by row (docs/IMPORT.md, "Purchases and sales"): a purchase
    /// of money out, of a kind it can start; a sale of money in, of an
    /// account other than `account` that can be sold from a statement
    /// (``Model/Account/canBeSoldFromStatement``), in its currency, with no
    /// values after the line, the first sale of it in the file; or one
    /// this sale already closed (``soldBefore(_:on:)``).
    private func answeredAssets(_ read: [ReadLine], account: Account) -> [Int: StatementAsset] {
        var answered: [Int: StatementAsset] = [:]
        var sold = Set<AccountID>()
        for line in read {
            guard let asset = session.statementAssets[line.row], asset.fits(line.amount) else { continue }
            switch asset {
            case .purchase(_, let kind):
                guard StatementAsset.purchaseKinds.contains(kind) else { continue }
            case .sale(let id):
                guard id != account.id, let other = library.accounts[id], other.currency == account.currency,
                      other.opened <= line.date, !sold.contains(id)
                else { continue }
                let unsold = other.canBeSoldFromStatement
                    && !library.valuations(for: id).contains(where: { $0.date > line.date })
                guard unsold || soldBefore(other, on: line.date) else { continue }
                sold.insert(id)
            }
            answered[line.row] = asset
        }
        return answered
    }

    /// Whether `account` is closed the day after its only value from `date`
    /// on, a value of 0: sold on `date` by importing this statement before,
    /// so importing it again with the same answer finds the same sale.
    private func soldBefore(_ account: Account, on date: CalendarDate) -> Bool {
        let after = library.valuations(for: account.id).filter { $0.date >= date }
        guard let closed = account.closed, after.count == 1, let zero = after.first, (zero.balance ?? 0) == 0 else {
            return false
        }
        return closed == zero.date.adding(days: 1) && !account.recordsTrades && !account.kind.recordsMoneyInOut
            && !account.kind.isLiability
    }

    /// The records of the lines answered as a purchase or a sale, at the
    /// file's value the line counts in (``StatementLine/period``), where
    /// the account's money moved. A purchase starts a new account (proposed,
    /// accepted), opened and worth 0 on the line's day (the day before,
    /// when that's the value's), then worth the line's amount, with the
    /// amount as its flow: its first value is 0, so the amount is new
    /// money moved from the account, not what it already held. A sale
    /// values the account sold at 0, with the amount as its flow out, and
    /// closes it the day after (proposed, accepted, unless this sale closed
    /// it already). Answers it can't record are issues: one that doesn't
    /// fit leaves the line classified as if it had none, and a line that
    /// counts in no value has no money in and out to move.
    private mutating func statementAssetRecords(_ lines: inout [StatementLine], read: [ReadLine],
                                                account: Account)
        -> [ImportRecordKey: Accumulator] {
        let answered = answeredAssets(read, account: account)
        var records: [ImportRecordKey: Accumulator] = [:]
        var taken = Set(library.accounts.keys.map(\.rawValue) + accountProposals.map(\.account.id.rawValue))
        var found = Set<AccountID>()
        for row in session.statementAssets.keys.sorted() {
            guard let index = lines.firstIndex(where: { $0.row == row }) else { continue }
            let line = lines[index]
            guard let asset = answered[row], let cut = line.period else {
                var account: AccountID?
                if case .sale(let id)? = session.statementAssets[row], answered[row] == nil,
                   session.statementAssets[row]?.fits(line.amount) == true { account = id }
                issues.append(ImportIssue(kind: .statementAssetLeftOut(row: row, account: account)))
                continue
            }
            let amount = -line.amount
            let id: AccountID
            switch asset {
            case .purchase(let name, let kind):
                let opened = min(line.date, cut.adding(days: -1))
                let started = library.accounts.values.sorted { $0.id < $1.id }.first { existing in
                    existing.name == name && existing.kind == kind && existing.opened == opened
                        && existing.currency == account.currency && !found.contains(existing.id)
                }
                if let started {
                    // Importing the file again with the same answer finds the account it started.
                    id = started.id
                    found.insert(id)
                } else {
                    id = AccountID(Slug.unique(Slug.make(from: name), among: taken))
                    taken.insert(id.rawValue)
                    let new = Account(id: id, name: name, kind: kind, currency: account.currency, opened: opened)
                    accountProposals.append(AccountProposal(account: new, names: [name], statementRow: row))
                }
                var start = ImportedRecord(key: .valuation(ValuationKey(account: id, date: opened)))
                start.balance = 0
                records[start.key] = Accumulator(record: start, cells: read.first { $0.row == row }?.cells ?? [])
            case .sale(let sold):
                id = sold
                if library.accounts[sold]?.closed != cut.adding(days: 1) {
                    statementCloses.append(AccountChangeProposal(account: sold,
                                                                 change: .close(on: cut.adding(days: 1)),
                                                                 statementRow: row))
                }
            }
            var record = ImportedRecord(key: .valuation(ValuationKey(account: id, date: cut)))
            record.balance = line.amount < 0 ? amount : 0
            record.flow = amount
            records[record.key] = Accumulator(record: record, cells: read.first { $0.row == row }?.cells ?? [])
            lines[index].asset = asset
            lines[index].assetAccount = id
        }
        return records
    }

    // MARK: - Values

    /// The account's values over the days the file covers (unless the
    /// session gives them, from its first month's first day to its last
    /// month's last day, or today in the month that isn't over): one at
    /// each of the account's values in the span, one at the end of each
    /// month without one, and one on the last day the session gives. Each has the balance, and
    /// when the file covers its whole period, from the value before it,
    /// money in and out (and interest) and the flow. Sets each line's
    /// ``StatementLine/period``.
    private mutating func statementValues(_ lines: inout [StatementLine], read: [ReadLine],
                                          account: Account) -> [ImportRecordKey: Accumulator] {
        guard let firstDate = lines.first?.date, let lastDate = lines.last?.date else { return [:] }
        let start = session.statementFrom ?? firstDate.startOfMonth
        let end = session.statementThrough ?? max(lastDate, min(lastDate.endOfMonth, today))
        if let through = session.statementThrough, through > today {
            issues.append(ImportIssue(kind: .statementThroughAfterToday(through)))
            return [:]
        }
        let outside = lines.filter { $0.date < start || $0.date > end }.count
        guard outside == 0 else {
            issues.append(ImportIssue(kind: .linesOutsidePeriod(count: outside, from: start, through: end)))
            return [:]
        }
        issues.append(ImportIssue(kind: .statementPeriod(from: start, through: end)))
        let valuations = library.valuations(for: account.id)
        let anchor = valuations.last { $0.date < start }
        var cuts = Set(valuations.map(\.date).filter { $0 >= start && $0 <= end })
        var month = start.yearMonth
        while month <= end.yearMonth {
            if month.lastDay <= end, !cuts.contains(where: { month.contains($0) }) { cuts.insert(month.lastDay) }
            month = month.next
        }
        // A file said to end on a day has a value on that day, which the next file follows on from.
        if session.statementThrough != nil { cuts.insert(end) }
        let balances = RunningBalances(lines)
        if balances.breaks > 0 { issues.append(ImportIssue(kind: .runningBalanceBreaks(count: balances.breaks))) }
        let fromFile = balances.opening
        let adjacent = anchor.map { $0.date >= start.adding(days: -1) } ?? false
        let opening = fromFile ?? session.statementOpeningBalance ?? (adjacent ? anchor?.balance : nil)
        // The file follows on from the value before it when that value is on the day before it, unless the
        // balance before the file's first line, from the file or given, isn't that value's balance; or
        // across a gap when the file's balance column says it is.
        let firstCovered = anchor.map { anchor in
            if let fromFile { return fromFile == anchor.balance }
            return adjacent && (session.statementOpeningBalance.map { $0 == anchor.balance } ?? true)
        } ?? false
        guard opening != nil || balances.hasBalances else {
            issues.append(ImportIssue(kind: .needsOpeningBalance(account.id)))
            return [:]
        }

        var records: [ImportRecordKey: Accumulator] = [:]
        let sortedCuts = cuts.sorted()
        var previous: (date: CalendarDate, balance: Decimal?)? = anchor.map { ($0.date, $0.balance) }
        for (index, cut) in sortedCuts.enumerated() {
            let covered = index > 0 || firstCovered
            let inPeriod = lines.indices.filter { index in
                lines[index].date <= cut && previous.map { lines[index].date > $0.date } ?? true
            }
            let balance = balances.balance(on: cut, opening: opening)
            defer { previous = (cut, balance) }
            guard let balance else { continue }
            var record = ImportedRecord(key: .valuation(ValuationKey(account: account.id, date: cut)))
            record.balance = balance
            var cells = inPeriod.flatMap { read[$0].cells }
            if covered, previous != nil {
                var total = StatementLine.Counted()
                for index in inPeriod {
                    lines[index].period = cut
                    let counted = lines[index].counted(recordsInterest: account.kind.recordsInterest)
                    total.moneyIn += counted.moneyIn
                    total.moneyOut += counted.moneyOut
                    total.oneOff += counted.oneOff
                    total.interest += counted.interest
                }
                let interest = total.interest
                record.moneyIn = total.moneyIn
                // More paid back than spent in a period leaves money out at 0, and the rest counts as moved.
                record.moneyOut = max(total.moneyOut, 0)
                if total.oneOff != 0 { record.oneOff = total.oneOff }
                record.countsMoneyInOutFromLines = true
                if interest != 0 { record.interest = interest }
                if let previousBalance = previous?.balance {
                    record.flow = balance - previousBalance - (account.kind.recordsInterest ? interest : 0)
                }
            }
            cells.sort()
            records[record.key] = Accumulator(record: record, cells: cells)
        }
        if !firstCovered, let first = sortedCuts.first {
            issues.append(ImportIssue(kind: .moneyInOutFrom(account.id, value: first, previous: anchor?.date)))
        }
        // Only a last value with money in and out of its own counts twice with a later value's.
        if let last = sortedCuts.last, !valuations.contains(where: { $0.date == last }),
           let record = records[.valuation(ValuationKey(account: account.id, date: last))]?.record,
           record.moneyIn != nil || record.moneyOut != nil,
           let later = valuations.first(where: { $0.date > end }), later.moneyIn != nil || later.moneyOut != nil {
            let since = valuations.last { $0.date < later.date }?.date
            issues.append(ImportIssue(kind: .laterMoneyInOut(account.id, value: later.date, since: since)))
        }
        let after = lines.filter { line in sortedCuts.last.map { line.date > $0 } ?? true }
        if !after.isEmpty {
            issues.append(ImportIssue(kind: .linesAfterLastValue(count: after.count, after: sortedCuts.last)))
        }
        return records
    }
}

/// The balances a statement's balance column gives: the balance at the end
/// of each day that has one, and the balance before the first line.
private struct RunningBalances {
    private var lines: [StatementLine]
    /// The balance at the end of each day with a balance.
    private var dayEnds: [(date: CalendarDate, balance: Decimal)] = []
    /// The balance before the file's first line, worked out from the first balance.
    private(set) var opening: Decimal?
    /// Days whose balance doesn't follow from the day before and its lines.
    private(set) var breaks = 0

    var hasBalances: Bool { !dayEnds.isEmpty }

    /// Of a day's balances, the end of the day is the one that follows from
    /// the day before and the day's lines, since a day's lines can be
    /// listed in any order; else the last one.
    init(_ lines: [StatementLine]) {
        self.lines = lines
        let days = Dictionary(grouping: lines, by: \.date)
        var previous: Decimal?
        for date in days.keys.sorted() {
            let day = days[date] ?? []
            let candidates = day.compactMap(\.balance)
            let sum = day.reduce(Decimal(0)) { $0 + $1.amount }
            guard let last = candidates.last else {
                previous = previous.map { $0 + sum }
                continue
            }
            let expected = previous.map { $0 + sum }
            let end = expected.flatMap { expected in candidates.first { $0 == expected } } ?? last
            if let expected, end != expected { breaks += 1 }
            if dayEnds.isEmpty {
                opening = end - lines.filter { $0.date <= date }.reduce(Decimal(0)) { $0 + $1.amount }
            }
            dayEnds.append((date, end))
            previous = end
        }
    }

    /// The balance at the end of `date`: from the latest day with a balance
    /// on or before it, else from `opening`, plus the lines after it.
    func balance(on date: CalendarDate, opening: Decimal?) -> Decimal? {
        let known = dayEnds.last { $0.date <= date }
        guard let base = known?.balance ?? opening else { return nil }
        return base + lines.filter { line in line.date <= date && known.map { line.date > $0.date } ?? true }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }
}
