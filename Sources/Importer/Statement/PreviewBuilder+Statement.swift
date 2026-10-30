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
        /// The text's words, folded once (``TextTools/words(_:)``).
        var words: [String]
        var senderWords: [String]
        /// The profile's rule for the text (``ImportSession/statementRule(for:)``).
        var rule: StatementRule?
    }

    /// Reads the lines, classifies them (``statementLines``) and works out
    /// the account's values: one at each of its values in the file's span,
    /// and one at each month end of a month that has none. Then the other
    /// side of the money the answers move: a tax pot's values, a purchase's
    /// new account, an account sold.
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
        markAsked(&lines, read: read, account: account)
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

        let rules = session.statementRules
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
            let sender = counterparty.isEmpty ? StatementWords.sender(of: text) : counterparty
            let words = TextTools.words(text)
            lines.append(ReadLine(row: row.number, date: date, amount: amount, text: text, sender: sender,
                                  balance: balance, cells: cells, words: words, senderWords: TextTools.words(sender),
                                  rule: ImportSession.statementRule(for: words, in: rules)))
        }
        if let first = lines.first, let last = lines.last, first.date > last.date { lines.reverse() }
        // A stable sort: lines on one day keep their order.
        return lines.enumerated().sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
            .map(\.element)
    }

    // MARK: - Classifying

    /// Each line's class and why: an answer that moves money to or from an
    /// account, chosen for the line, remembered for it, a rule, a trade of another account
    /// moving the same amount, a line of another account's statement
    /// imported with it moving it the other way, another account named in
    /// the text, the usual words; for money in, a sender paid before or a
    /// recurring one; else the sign. Then the lines that need an answer.
    private func classify(_ read: [ReadLine], account: Account) -> [StatementLine] {
        let names = accountNames(excluding: account)
        let answered = answeredAssets(read, account: account)
        let open = read.indices.filter { index in
            session.statementLineClasses[read[index].row] == nil && remembered(read[index]) == nil
                && read[index].rule == nil
                && answered[read[index].row] == nil && batch.pairs[read[index].row] == nil
        }
        let trades = matchTrades(read, lines: open, excluding: account.id)
        var lines = read.indices.map { index in
            let line = read[index]
            let rule = line.rule
            let chosen: (StatementClass, StatementLine.Source)
            if answered[line.row] != nil {
                // Money moved to or from an account, a purchase or a sale moves money between your accounts.
                if session.statementAssets[line.row] == nil, let rule {
                    chosen = (.transfer, .rule(rule.match))
                } else {
                    chosen = (.transfer, .chosen)
                }
            } else if let statementClass = session.statementLineClasses[line.row] {
                chosen = (statementClass, .chosen)
            } else if let answer = remembered(line) {
                chosen = (answer.statementClass, .chosen)
            } else if let rule {
                chosen = (rule.statementClass, .rule(rule.match))
            } else if let trade = trades[index] {
                chosen = (.transfer, .trade(trade))
            } else if let other = batch.pairs[line.row] {
                chosen = (.transfer, .paired(other))
            } else if let named = Self.namedAccount(in: line.words, names: names) {
                // Paying a debt is spending; a loan paid out into the account is moved between accounts.
                chosen = (named.isLiability && line.amount < 0 ? .spending : .transfer, .account(named.id))
            } else if let suggested = StatementWords.suggestion(for: line.words, amount: line.amount) {
                chosen = (suggested, .words)
            } else if line.amount > 0, Self.paidBefore(line, in: read) {
                chosen = (.spending, .paidBefore)
            } else {
                chosen = (.spending, .sign)
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
        Self.markPassThroughs(&lines)
        return lines
    }

    /// The profile's remembered answer for `line`, chosen for it in an
    /// earlier file (``ImportProfile/answers``).
    private func remembered(_ line: ReadLine) -> StatementAnswer? {
        session.statementAnswer(date: line.date, amount: line.amount, words: line.words)
    }

    /// Marks the lines that need an answer, or would without the class or
    /// answer chosen for them alone (``StatementLine/wasAsked``).
    private func markAsked(_ lines: inout [StatementLine], read: [ReadLine], account: Account) {
        for index in lines.indices where lines[index].needsAnswer { lines[index].wasAsked = true }
        guard !session.statementLineClasses.isEmpty || !session.statementAssets.isEmpty else { return }
        var unanswered = session
        unanswered.statementLineClasses = [:]
        unanswered.statementAssets = [:]
        let bare = PreviewBuilder(session: unanswered, library: library, today: today)
        let asked = Set(bare.classify(read, account: account).filter(\.needsAnswer).map(\.row))
        for index in lines.indices where asked.contains(lines[index].row) { lines[index].wasAsked = true }
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
                && out.senderWords == line.senderWords
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
    /// needs an answer.
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
    /// month's spending needs an answer.
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

    /// Money in and money out of the same amount within ``transferDays``,
    /// both classified by their sign and at least one needing an answer,
    /// passed through the account, such as savings moved to a broker by way
    /// of the current account: both are transfers and need no answer. The
    /// pairs nearest in date are taken first, each line once.
    private static func markPassThroughs(_ lines: inout [StatementLine]) {
        let open = lines.indices.filter { lines[$0].source == .sign && lines[$0].amount != 0 }
        let outs = Dictionary(grouping: open.filter { lines[$0].amount < 0 }) { -lines[$0].amount }
        var pairs: [(in: Int, out: Int, days: Int)] = []
        for incoming in open where lines[incoming].amount > 0 {
            for out in outs[lines[incoming].amount] ?? []
            where lines[incoming].needsAnswer || lines[out].needsAnswer {
                let days = abs(lines[incoming].date.days(to: lines[out].date))
                if days <= transferDays { pairs.append((incoming, out, days)) }
            }
        }
        var used = Set<Int>()
        for pair in pairs.sorted(by: { ($0.days, $0.in, $0.out) < ($1.days, $1.in, $1.out) })
        where !used.contains(pair.in) && !used.contains(pair.out) {
            used.formUnion([pair.in, pair.out])
            for (index, other) in [(pair.in, pair.out), (pair.out, pair.in)] {
                lines[index].statementClass = .transfer
                lines[index].source = .passThrough(row: lines[other].row)
                lines[index].needsAnswer = false
            }
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
        let byAmount = Dictionary(grouping: trades.indices) { trades[$0].amount }
        var pairs: [(line: Int, trade: Int, days: Int)] = []
        for line in lines {
            for index in byAmount[read[line].amount] ?? [] {
                let trade = trades[index]
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

    /// The account whose name is the longest one the text's words have.
    private static func namedAccount(in words: [String], names: [(phrase: String, id: AccountID, isLiability: Bool)])
        -> (id: AccountID, isLiability: Bool)? {
        names.filter { TextTools.contains(words, anyOf: [$0.phrase]) }
            .max { $0.phrase.count < $1.phrase.count }.map { ($0.id, $0.isLiability) }
    }

    // MARK: - Moved to or from an account

    /// The answers that move a line's money to or from an account, by row
    /// (docs/IMPORT.md, "Moved to or from an account"): the session's, else
    /// a rule's with an account for a line without a chosen class. Each
    /// is one the import can take: money moved to or from an account it
    /// can move to (``Library/canMoveFromStatement(_:of:on:)``); a purchase
    /// of money out, of a kind it can start; a sale of money in, of an
    /// account that can be sold from `account`'s statement
    /// (``Library/canSellFromStatement(_:of:on:)``), or one a purchase on or
    /// before its day in the file starts (checked once the purchase has
    /// its ID, ``statementAssetRecords(_:read:account:)``), the first sale
    /// of it in the file.
    private func answeredAssets(_ read: [ReadLine], account: Account) -> [Int: StatementAsset] {
        var answered: [Int: StatementAsset] = [:]
        var sold = Set<AccountID>()
        let purchases = read.filter { line in
            guard case .purchase? = session.statementAssets[line.row] else { return false }
            return line.amount < 0
        }
        for line in read {
            guard let asset = session.statementAssets[line.row] ?? ruleMove(for: line), asset.fits(line.amount)
            else { continue }
            switch asset {
            case .moved(let id):
                guard let other = library.accounts[id], library.canMoveFromStatement(other, of: account, on: line.date)
                else { continue }
            case .purchase(_, let kind):
                guard StatementAsset.purchaseKinds.contains(kind) else { continue }
            case .sale(let id):
                guard !sold.contains(id) else { continue }
                if let other = library.accounts[id] {
                    guard library.canSellFromStatement(other, of: account, on: line.date) else { continue }
                } else {
                    guard purchases.contains(where: { $0.date <= line.date }) else { continue }
                }
                sold.insert(id)
            }
            answered[line.row] = asset
        }
        return answered
    }

    /// The move a rule makes of `line`, when nothing chosen for the line
    /// comes first: money moved to or from the rule's account.
    private func ruleMove(for line: ReadLine) -> StatementAsset? {
        guard session.statementLineClasses[line.row] == nil, session.statementAssets[line.row] == nil,
              remembered(line) == nil, let rule = line.rule, rule.statementClass == .transfer
        else { return nil }
        return rule.account.map(StatementAsset.moved)
    }

    /// The other side of the answers that move money. Money moved to or
    /// from an account is a transfer, at the file's value the line counts
    /// in (``StatementLine/period``), and a cash or savings account's or a
    /// tax pot's values follow from it (``movedRecords(_:moves:)``), unless
    /// its own statement is imported with this one. A purchase or a sale is
    /// recorded on the line's own day, whatever the file's values cover: a
    /// purchase starts a new account (proposed, accepted), opened and worth
    /// 0 the day before, then worth the line's amount, with the amount as
    /// what it saved, so the amount is new money moved from the account, not
    /// what it already held; a sale
    /// values the account sold at 0 that day, with the amount as what it
    /// saved, taken out, and closes it the day after (proposed, accepted, unless this
    /// sale closed it already). The account sold can be one a purchase on
    /// or before the sale's day in the file starts; bought and sold on one
    /// day, it's worth 0 with what the two moved as what it saved. Answers it
    /// can't take are issues: one that doesn't fit leaves the line
    /// classified as if it had none (a rule's move, a transfer, as the rule
    /// says), and a move on a line that counts in no value has no money in
    /// and out to move.
    private mutating func statementAssetRecords(_ lines: inout [StatementLine], read: [ReadLine],
                                                account: Account)
        -> [ImportRecordKey: Accumulator] {
        let answered = answeredAssets(read, account: account)
        var records: [ImportRecordKey: Accumulator] = [:]
        var taken = Set(library.accounts.keys.map(\.rawValue) + accountProposals.map(\.account.id.rawValue))
        var found = Set<AccountID>()
        var moves: [AccountID: [StatementMove]] = [:]
        // The accounts this file's purchases start, by the purchase's day.
        var started: [AccountID: CalendarDate] = [:]
        // Sales come after the purchases, so a sale of an account a purchase starts finds its ID.
        let rows = Set(session.statementAssets.keys).union(answered.keys).sorted()
        let sells = { (row: Int) -> Bool in
            if case .sale? = answered[row] { true } else { false }
        }
        for row in rows.filter({ !sells($0) }) + rows.filter(sells) {
            guard let index = lines.firstIndex(where: { $0.row == row }) else { continue }
            let line = lines[index]
            let cells = read.first { $0.row == row }?.cells ?? []
            if case .moved(let other)? = answered[row] {
                if let to = library.accounts[other], Self.followsMoves(to, of: account),
                   !batch.accounts.contains(other) {
                    if let cut = line.period {
                        moves[other, default: []].append(StatementMove(date: line.date, cut: cut,
                                                                       amount: -line.amount, cells: cells))
                    } else if to.kind == .taxPot {
                        // Still a transfer, as the answer says, but the pot's value can't follow from it.
                        issues.append(ImportIssue(kind: .statementMoveLeftOut(row: row, account: other)))
                        lines[index].assetLeftOut = .notCovered
                        continue
                    }
                }
                lines[index].asset = answered[row]
                lines[index].assetAccount = other
                continue
            }
            // A sale found from an earlier import, or another sale; or a sale of an account no purchase in
            // the file started, or one started after the sale.
            let unrecorded = answered[row].map { asset in
                guard case .sale(let sold) = asset else { return false }
                if let closed = library.accounts[sold]?.closed { return closed != line.date.adding(days: 1) }
                guard library.accounts[sold] == nil else { return false }
                return started[sold].map { $0 > line.date } ?? true
            } ?? false
            guard let asset = answered[row], !unrecorded else {
                if case .moved(let other)? = session.statementAssets[row] {
                    issues.append(ImportIssue(kind: .statementMoveLeftOut(row: row, account: other)))
                    lines[index].assetLeftOut = .accountCantTakeMoves
                    continue
                }
                var account: AccountID?
                if case .sale(let id)? = session.statementAssets[row], answered[row] == nil || unrecorded,
                   session.statementAssets[row]?.fits(line.amount) == true { account = id }
                issues.append(ImportIssue(kind: .statementAssetLeftOut(row: row, account: account)))
                lines[index].assetLeftOut = .doesntFit
                continue
            }
            let amount = -line.amount
            let id: AccountID
            // The new money it brings, stored only where the account asks for it (Account.asksForSaved).
            let asksForSaved: Bool
            switch asset {
            case .moved: continue
            case .purchase(let name, let kind):
                let opened = line.date.adding(days: -1)
                let existing = library.accounts.values.sorted { $0.id < $1.id }.first { existing in
                    existing.name == name && existing.kind == kind && existing.opened == opened
                        && existing.currency == account.currency && !found.contains(existing.id)
                }
                if let existing {
                    // Importing the file again with the same answer finds the account it started.
                    id = existing.id
                    found.insert(id)
                    asksForSaved = existing.asksForSaved
                } else {
                    id = AccountID(Slug.unique(Slug.make(from: name), among: taken))
                    taken.insert(id.rawValue)
                    started[id] = line.date
                    let new = Account(id: id, name: name, kind: kind, currency: account.currency, opened: opened)
                    accountProposals.append(AccountProposal(account: new, names: [name], statementRow: row))
                    asksForSaved = new.asksForSaved
                }
                var start = ImportedRecord(key: .valuation(ValuationKey(account: id, date: opened)))
                start.balance = 0
                records[start.key] = Accumulator(record: start, cells: cells)
            case .sale(let sold):
                id = sold
                let soldAccount = library.accounts[sold] ?? accountProposals.first { $0.account.id == sold }?.account
                asksForSaved = soldAccount?.asksForSaved ?? false
                if library.accounts[sold]?.closed != line.date.adding(days: 1) {
                    statementCloses.append(AccountChangeProposal(account: sold,
                                                                 change: .close(on: line.date.adding(days: 1)),
                                                                 statementRow: row))
                }
            }
            var record = ImportedRecord(key: .valuation(ValuationKey(account: id, date: line.date)))
            record.balance = line.amount < 0 ? amount : 0
            if asksForSaved { record.saved = amount }
            var accumulator = Accumulator(record: record, cells: cells)
            if let bought = records[record.key] {
                // Bought and sold on one day.
                if asksForSaved { accumulator.record.saved = (bought.record.saved ?? 0) + amount }
                accumulator.cells = bought.cells + cells
            }
            records[record.key] = accumulator
            lines[index].asset = asset
            lines[index].assetAccount = id
        }
        // A rule's move it can't take leaves the line a transfer, as the rule says.
        for line in read where answered[line.row] == nil {
            if case .moved(let other)? = ruleMove(for: line) {
                issues.append(ImportIssue(kind: .statementMoveLeftOut(row: line.row, account: other)))
                if let index = lines.firstIndex(where: { $0.row == line.row }) {
                    lines[index].assetLeftOut = .accountCantTakeMoves
                }
            }
        }
        for (other, otherMoves) in moves {
            records.merge(movedRecords(other, moves: otherMoves)) { $1 }
        }
        return records
    }

    /// Money a statement's line moved into another account (negative: taken out),
    /// on the line's day, counted in the statement's value on `cut`.
    private struct StatementMove {
        var date: CalendarDate
        var cut: CalendarDate
        var amount: Decimal
        var cells: [ImportCellRef]
    }

    /// Whether an account's values follow from the money a statement of
    /// `statement` moves to and from it: a cash or savings account or a tax
    /// pot valued by its balance, in the statement's currency.
    static func followsMoves(_ account: Account, of statement: Account) -> Bool {
        account.kind.recordsMoneyInOut && !account.recordsTrades && account.currency == statement.currency
    }

    /// The values of an account the file moved money into and out of
    /// (docs/IMPORT.md, "Moved to or from an account"): one on each of the
    /// statement's values the moves count in, its balance that of the
    /// account's value before it plus the money moved since. A tax pot's
    /// have no money in or out (so it's all moved, Tracker's
    /// `Valuator.moved(_:previous:)`); another account's are left unknown,
    /// its interest too. A value the account has between moves
    /// takes the moves before it as counted already. A pot with no value
    /// before the first move starts worth 0 the day before it, a value that
    /// isn't counted; another account without one gets no values.
    private func movedRecords(_ id: AccountID, moves: [StatementMove]) -> [ImportRecordKey: Accumulator] {
        guard let first = moves.map(\.date).min() else { return [:] }
        let isPot = library.accounts[id]?.kind == .taxPot
        let cuts = Set(moves.map(\.cut)).sorted()
        var values = library.valuations(for: id).filter { !cuts.contains($0.date) }
            .map { (date: $0.date, balance: $0.balance ?? 0) }
        var records: [ImportRecordKey: Accumulator] = [:]
        if !values.contains(where: { $0.date < first }) {
            guard isPot else { return [:] }
            let start = first.adding(days: -1)
            var record = ImportedRecord(key: .valuation(ValuationKey(account: id, date: start)))
            record.balance = 0
            records[record.key] = Accumulator(record: record, cells: [])
            values.append((start, 0))
        }
        for cut in cuts {
            guard let before = values.filter({ $0.date < cut }).max(by: { $0.date < $1.date }) else { continue }
            let counted = moves.filter { $0.cut == cut && $0.date > before.date }
            guard !counted.isEmpty else { continue }
            let moved = counted.reduce(Decimal(0)) { $0 + $1.amount }
            var record = ImportedRecord(key: .valuation(ValuationKey(account: id, date: cut)))
            record.balance = before.balance + moved
            if isPot {
                record.moneyIn = 0
                record.moneyOut = 0
            }
            records[record.key] = Accumulator(record: record, cells: counted.flatMap(\.cells).sorted())
            values.append((cut, before.balance + moved))
        }
        return records
    }

    // MARK: - Values

    /// The account's values over the days the file covers (unless the
    /// session gives them, from its first month's first day to its last
    /// month's last day, or today in the month that isn't over): one at
    /// each of the account's values in the span, one at the end of each
    /// month without one, and one on the last day the session gives (or
    /// the check-in's date, ``ImportSession/statementCheckIn``). Each has the balance, and
    /// when the file covers its whole period, from the value before it,
    /// money in and out (and interest). Sets each line's
    /// ``StatementLine/period``.
    private mutating func statementValues(_ lines: inout [StatementLine], read: [ReadLine],
                                          account: Account) -> [ImportRecordKey: Accumulator] {
        guard let firstDate = lines.first?.date, let lastDate = lines.last?.date else { return [:] }
        let start = session.statementFrom ?? firstDate.startOfMonth
        let checkIn = session.statementCheckIn.flatMap { date in
            date >= lastDate && date <= today && date.yearMonth == lastDate.yearMonth ? date : nil
        }
        let through = session.statementThrough ?? checkIn
        let end = through ?? max(lastDate, min(lastDate.endOfMonth, today))
        if let given = session.statementThrough, given > today {
            issues.append(ImportIssue(kind: .statementThroughAfterToday(given)))
            return [:]
        }
        let outside = lines.filter { $0.date < start || $0.date > end }.count
        guard outside == 0 else {
            issues.append(ImportIssue(kind: .linesOutsidePeriod(count: outside, from: start, through: end)))
            return [:]
        }
        statementPeriod = StatementPeriod(from: start, through: end)
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
        if through != nil { cuts.insert(end) }
        let balances = RunningBalances(lines)
        runningBalanceBreaks = balances.breaks
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
                var total = LineAmounts()
                for index in inPeriod {
                    lines[index].period = cut
                    total = total + lines[index].counted(recordsInterest: account.kind.recordsInterest)
                }
                let interest = total.interest
                record.moneyIn = total.moneyIn
                // More paid back than spent in a period leaves money out at 0, and the rest counts as moved.
                record.moneyOut = max(total.moneyOut, 0)
                if total.oneOff != 0 { record.oneOff = total.oneOff }
                // A tax pot's tax is what moved into it: a bill paid from it is only its money out.
                if total.tax != 0, account.kind != .taxPot { record.tax = total.tax }
                record.countsMoneyInOutFromLines = true
                if interest != 0 { record.interest = interest }
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
