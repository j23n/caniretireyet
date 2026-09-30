import Foundation
import Model

/// Journals into accounts that record trades (IMPORT.md, "Journals into
/// trades accounts"): each transaction touching such an account becomes its
/// trades, instead of month-end positions.
///
/// - A commodity posting with a cost (`@`, `@@`, `{}`) is a **buy** or a
///   **sell** at that price; a sale is priced by its `@` price when it has
///   a lot cost too. Fee and tax postings of the same transaction are its
///   `fees` and `tax`.
/// - A commodity received without a cost from a returns account (staking,
///   a reward) is a buy at its market value, paid for by the income, so its
///   cost is its value then. Otherwise a commodity moving in or out without a
///   cost is a **transfer**, its cost unknown.
/// - Postings from returns accounts are **dividends** or **interest** (by
///   name), and fees and taxes on their own (returns expense accounts, and
///   expense accounts named for fees or taxes) are **fee** and **tax**
///   trades, or the fees and tax of the transaction's dividend.
/// - Realised gains accounts make no trade: the trades work gains out.
/// - Whatever else changes the account's cash came from outside it: a
///   **deposit** or a **withdrawal**, so the cash the trades give is always
///   the journal's.
extension LedgerSnapshotBuilder {
    /// What a returns or charge posting becomes in a trades account.
    enum ReturnKind {
        case dividend, interest, fee, tax, gain
    }

    /// Whether a posting to an expense account that isn't returns is a charge
    /// on the investments anyway: a fee or a tax by its name.
    func isChargeAccount(_ posting: LedgerPosting) -> Bool {
        guard mapper.role(of: posting.account) == .expense else { return false }
        return TextTools.contains(Self.words(of: posting.account),
                                  anyOf: LedgerKeywords.taxes + LedgerKeywords.expenseReturns)
    }

    /// The words of an account's name below its root.
    static func words(of account: String) -> [String] {
        TextTools.words(LedgerMapper.spaced(account.split(separator: ":").dropFirst().joined(separator: " ")))
    }

    func returnKind(of posting: LedgerPosting) -> ReturnKind {
        let words = Self.words(of: posting.account)
        if mapper.role(of: posting.account) == .expense {
            return TextTools.contains(words, anyOf: LedgerKeywords.taxes) ? .tax : .fee
        }
        if TextTools.contains(words, anyOf: LedgerKeywords.gains) { return .gain }
        if TextTools.contains(words, anyOf: LedgerKeywords.taxes) { return .tax }
        if TextTools.contains(words, anyOf: LedgerKeywords.interest) { return .interest }
        return .dividend
    }

    /// Adds the trades one transaction makes in a trades account (`postings`
    /// are its own; `returns` the returns and charges it gets), unless
    /// `writes` is false (a transaction after `until`). Returns the money the
    /// transaction added or took out, as the trades count it (deposits,
    /// withdrawals and transfers at their value); `nil` if a transfer can't
    /// be valued.
    mutating func makeTrades(_ transaction: LedgerTransaction, account id: AccountID, postings: [LedgerPosting],
                             returns: [LedgerPosting], writes: Bool) -> Decimal? {
        let date = transaction.date
        let currency = currency(of: id)
        let name = account(id)?.name ?? id.rawValue
        var trades: [Trade] = []
        var flow: Decimal? = 0
        func trade(_ type: TradeType, instrument: InstrumentID? = nil, quantity: Decimal? = nil, price: Decimal? = nil,
                   priceCurrency: CurrencyCode? = nil, amount: Decimal? = nil) -> Trade {
            Trade(account: id, date: date, type: type, instrument: instrument, quantity: quantity, price: price,
                  currency: priceCurrency, amount: amount?.ledgerRounded(2), note: transaction.description.isEmpty
                      ? nil : transaction.description, source: .ledger)
        }
        func warn(_ posting: LedgerPosting, _ what: String) {
            guard writes else { return }
            notes.append(LedgerDiagnostic(
                .warning, "\(posting.amount) in \(posting.account) can't be valued in \(currency.rawValue) on \(date): "
                    + "there's no @ cost and no P price for it. \(what)", at: transaction.location))
        }

        // The account's cash: what its currency postings changed it by.
        var cash: Decimal = 0
        for posting in postings where mapper.currency(of: posting.amount.commodity) != nil {
            guard let value = value(of: posting, in: currency, on: date) else {
                warn(posting, "The trades of \(name) on \(date) were left out.")
                return nil
            }
            cash += value
        }
        let rewarded = returns.contains { mapper.role(of: $0.account) != .expense && returnKind(of: $0) != .gain }

        // Units bought, sold, received or moved.
        for posting in postings {
            guard let instrument = mapper.instrument(of: posting.amount.commodity), posting.amount.quantity != 0
            else { continue }
            let quantity = abs(posting.amount.quantity)
            let buying = posting.amount.quantity > 0
            let perUnit = posting.cost.map { LedgerAmount(abs($0.quantity) / quantity, $0.commodity) }
            let unit = buying ? perUnit ?? posting.unitPrice : posting.unitPrice ?? perUnit
            let total = unit.map { buying ? posting.cost.map { abs($0.quantity) } ?? $0.quantity * quantity
                : $0.quantity * quantity }
            if let unit, let total, let unitCurrency = mapper.currency(of: unit.commodity),
               let gross = book.convert(total, from: unitCurrency, to: currency, on: date) {
                let price = unit == posting.unitPrice ? unit.quantity : unit.quantity.ledgerRounded(6)
                trades.append(trade(buying ? .buy : .sell, instrument: instrument, quantity: quantity, price: price,
                                    priceCurrency: unitCurrency, amount: buying ? -gross : gross))
            } else if buying, rewarded, let value = value(of: posting, in: currency, on: date),
                      let price = book.price(of: posting.amount.commodity, on: date),
                      let priceCurrency = mapper.currency(of: price.commodity) {
                // A reward: bought at its market value with the income it is.
                trades.append(trade(.buy, instrument: instrument, quantity: quantity, price: price.quantity,
                                    priceCurrency: priceCurrency, amount: -value))
            } else {
                trades.append(trade(buying ? .transferIn : .transferOut, instrument: instrument, quantity: quantity))
                let value = value(of: posting, in: currency, on: date)
                flow = flow.flatMap { total in value.map { total + $0.ledgerRounded(2) } }
                if buying, writes {
                    notes.append(LedgerDiagnostic(
                        .note, "\(posting.amount) came into \(name) without a cost: it's a transfer in, and the cost "
                            + "of \(instrument) is unknown until it's sold. Write its cost with {…} or @ in the journal.",
                        at: posting.location))
                }
            }
        }

        // Income, and charges: the fees and tax of the transaction's trade, or trades of their own.
        var charges: [(type: TradeType, amount: Decimal)] = []
        for posting in returns {
            let kind = returnKind(of: posting)
            guard kind != .gain else { continue }
            guard let value = value(of: posting, in: currency, on: date) else {
                warn(posting, "It was left out of the trades of \(name).")
                continue
            }
            switch kind {
            case .dividend: trades.append(trade(.dividend, amount: -value))
            case .interest: trades.append(trade(.interest, amount: -value))
            case .fee, .tax:
                let type: TradeType = kind == .fee ? .fee : .tax
                if value > 0 { charges.append((type, value.ledgerRounded(2))) } else {
                    trades.append(trade(type, amount: -value))
                }
            case .gain: break
            }
        }
        let bearer = trades.firstIndex { $0.type == .buy || $0.type == .sell }
            ?? trades.firstIndex { $0.type == .dividend || $0.type == .interest }
        for charge in charges {
            guard let index = bearer else {
                trades.append(trade(charge.type, amount: -charge.amount))
                continue
            }
            if charge.type == .fee {
                trades[index].fees = (trades[index].fees ?? 0) + charge.amount
            } else {
                trades[index].tax = (trades[index].tax ?? 0) + charge.amount
            }
            trades[index].amount = trades[index].amount.map { $0 - charge.amount }
        }

        // Money from outside the account.
        let residual = (cash - trades.reduce(0) { $0 + ($1.amount ?? 0) }).ledgerRounded(2)
        if residual != 0 {
            trades.append(trade(residual > 0 ? .deposit : .withdrawal, amount: residual))
            flow = flow.map { $0 + residual }
        }

        guard writes else { return flow }
        for var trade in trades {
            omitComputableAmount(&trade, in: currency)
            let instrumentCurrency = trade.instrument.flatMap {
                library.instruments[$0]?.currency ?? mapper.newInstruments[$0]?.currency
            }
            if trade.currency == (instrumentCurrency ?? currency) { trade.currency = nil }
            let identity = [id.rawValue, date.description, trade.type.rawValue, trade.instrument?.rawValue ?? "",
                            trade.quantity?.fileString ?? "", trade.amount?.fileString ?? "",
                            trade.price?.fileString ?? ""].joined(separator: "|")
            let ordinal = tradeOrdinals[identity, default: 0]
            tradeOrdinals[identity] = ordinal + 1
            trade.id = TradeID.stable(for: trade, ordinal: ordinal)
            var record = ImportedRecord(trade: trade)
            record.source = .ledger
            records.append(record)
        }
        return flow
    }

    /// Leaves out a buy's or sell's amount when its price, quantity, fees and
    /// tax give the same, as the trade would be written by hand.
    private func omitComputableAmount(_ trade: inout Trade, in currency: CurrencyCode) {
        guard trade.type == .buy || trade.type == .sell, let amount = trade.amount, let quantity = trade.quantity,
              let price = trade.price, (trade.currency ?? currency) == currency else { return }
        let gross = (quantity * price).ledgerRounded(2)
        let charges = (trade.fees ?? 0) + (trade.tax ?? 0)
        if (trade.type == .buy ? -(gross + charges) : gross - charges) == amount { trade.amount = nil }
    }
}
