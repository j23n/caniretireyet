import Foundation
import Model

/// Something unusual in a check-in, shown on the review screen.
public enum CheckInWarning: Hashable, Sendable {
    /// A position's quantity went down: did you sell?
    case quantityDecreased(account: AccountID, instrument: InstrumentID, from: Decimal, to: Decimal)
    /// The account's value changed by more than 30% since its previous
    /// valuation; values in the base currency.
    case largeChange(account: AccountID, from: Decimal, to: Decimal)
    /// An updated account's flow is unknown, e.g. a pension fund whose
    /// contributions weren't entered. Its change will count as "other".
    case unknownFlow(account: AccountID)
    /// A price or FX rate is missing, so the value is incomplete.
    case valuation(ValuationProblem)

    /// The account the warning concerns.
    public var account: AccountID {
        switch self {
        case .quantityDecreased(let account, _, _, _), .largeChange(let account, _, _), .unknownFlow(let account):
            account
        case .valuation(let problem):
            problem.account
        }
    }
}

/// One position of a check-in row, valued.
public struct CheckInPositionReview: Hashable, Sendable {
    public let instrument: InstrumentID
    public let quantity: Decimal
    public let previousQuantity: Decimal
    /// The price on the check-in date (the latest on or before it).
    public let price: PriceRecord?
    /// The value in the base currency; `nil` without a price or FX rate.
    public let value: Decimal?
    /// When the quantity went up: the added quantity at the price, in the
    /// account's currency. The placeholder for "paid", and what's used when
    /// nothing was entered.
    public let estimatedPaid: Decimal?
    /// The cost basis that will be written.
    public let costBasis: Decimal?
}

/// One check-in row, valued, with its flow and warnings.
public struct CheckInRowReview: Hashable, Sendable, Identifiable {
    public let account: AccountID
    public let state: CheckInRowState
    /// The valuation the row writes; `nil` for rows not reviewed or skipped.
    public let valuation: Valuation?
    /// The account's value on the check-in date with the row's values.
    public let value: AccountValue?
    /// The previous valuation's value on its own date, in the base currency ("was").
    public let previousValue: Decimal?
    /// The flow that will be written, in the account's currency; `nil` when
    /// unknown or when the row writes nothing.
    public let flow: Decimal?
    /// The default flow for the row's values ("new money"), in the account's currency.
    public let defaultFlow: Decimal?
    /// How the account's kind fills in the flow; `.ask` means the app asks
    /// for it (e.g. "contributions since …"). A trades account's flow comes
    /// from its trades and cash, whatever this says (see ``CheckInRow/isTrades``).
    public let flowRule: FlowDefault
    /// The row's positions, valued; for a trades account, what its trades
    /// hold on the date (and what they held at the previous valuation).
    public let positions: [CheckInPositionReview]
    public let warnings: [CheckInWarning]
    /// For a trades account with positions entered (from a broker
    /// statement, say): where they differ from what its trades give.
    public let mismatches: [PositionMismatch]

    public var id: AccountID { account }
}

/// The review screen: the new total, the waterfall since the previous
/// check-in, and each row with anything unusual.
public struct CheckInReview: Hashable, Sendable {
    public let date: CalendarDate
    /// The latest check-in before this one, where the waterfall starts.
    public let previousCheckIn: CalendarDate?
    public let rows: [CheckInRowReview]
    /// Net worth on the date, with the check-in saved.
    public let netWorth: NetWorth
    /// The change since the previous check-in (start, market, new money,
    /// other, end); `nil` for the first check-in.
    public let change: ChangeReport?
    /// Accounts that open after the date and get a value in this check-in:
    /// saving moves their opening date back to the date. In row order.
    public let openingMoves: [AccountID]

    /// Every warning, in row order.
    public var warnings: [CheckInWarning] {
        rows.flatMap(\.warnings)
    }

    /// The review of one account's row.
    public func row(for account: AccountID) -> CheckInRowReview? {
        rows.first { $0.account == account }
    }
}

/// What a check-in writes to the library.
public struct CheckInRecords: Hashable, Sendable {
    /// One valuation per row updated or marked unchanged, with its flow.
    public let valuations: [Valuation]
    public let prices: [PriceRecord]
    public let fxRates: [FXRecord]
    /// The accounts among ``valuations`` that open after the check-in's
    /// date: their opening date moves back to it.
    public let openingMoves: [AccountID]
}

extension CheckInDraft {
    /// How much an account's value may change before the review warns
    /// about it (``CheckInWarning/largeChange(account:from:to:)``): 30%.
    static let largeChangeThreshold: Decimal = 0.3

    /// Values every row and the new total as they stand, with warnings for
    /// anything unusual (``CheckInWarning``).
    public func review(in library: Library) -> CheckInReview {
        let priced = Valuator(library: libraryWithRates(library))
        let proposals = rows.map { proposal(for: $0, using: priced) }
        let records = records(writing: proposals.compactMap(\.written), in: library)
        var saved = library
        apply(records, to: &saved)
        let valuator = Valuator(library: saved)
        let previousCheckIn = priced.previousCheckIn(before: date)

        let reviews = zip(rows, proposals).map { row, proposal in
            let value = priced.value(of: proposal.valuation, on: date)
            let previousValue = row.previous.flatMap { priced.value(of: $0, on: $0.date)?.knownValue }
            var warnings: [CheckInWarning] = []
            if row.state == .updated, row.conflict == nil {
                for position in row.positions where position.quantity < position.previousQuantity && !row.isTrades {
                    warnings.append(.quantityDecreased(account: row.account, instrument: position.instrument,
                                                       from: position.previousQuantity, to: position.quantity))
                }
                if let previousValue, previousValue != 0, let now = value?.knownValue,
                   abs(now - previousValue) > Self.largeChangeThreshold * abs(previousValue) {
                    warnings.append(.largeChange(account: row.account, from: previousValue, to: now))
                }
                if proposal.written?.flow == nil { warnings.append(.unknownFlow(account: row.account)) }
            }
            warnings += (value?.problems ?? []).map(CheckInWarning.valuation)
            return CheckInRowReview(
                account: row.account, state: row.state, valuation: proposal.written, value: value,
                previousValue: previousValue, flow: proposal.written?.flow, defaultFlow: proposal.defaultFlow,
                flowRule: priced.accounts[row.account]?.kind.defaultFlow ?? .ask, positions: proposal.positions,
                warnings: warnings, mismatches: row.isTrades ? priced.reconcile(proposal.valuation) : [])
        }
        return CheckInReview(
            date: date, previousCheckIn: previousCheckIn, rows: reviews, netWorth: valuator.netWorth(on: date),
            change: previousCheckIn.map { valuator.change(from: $0, to: date) }, openingMoves: records.openingMoves)
    }

    /// The valuations (one per row updated or marked unchanged, with flows
    /// and cost bases filled in), prices and FX rates to write, and the
    /// accounts whose opening date moves back to the date. Rows not
    /// reviewed, skipped or in conflict with a valuation saved on the date
    /// write nothing.
    public func records(in library: Library) -> CheckInRecords {
        let priced = Valuator(library: libraryWithRates(library))
        return records(writing: rows.compactMap { proposal(for: $0, using: priced).written }, in: library)
    }

    /// Saves the check-in into `library`: upserts its valuations, prices and
    /// FX rates, and moves the opening date of accounts that open later
    /// back to the date (see ``CheckInRow/opensLater``).
    ///
    /// A past check-in can land between two valuations of an account: the
    /// flow of the valuation after it is then worked out again from the new
    /// one if it was the automatic one, and kept if it was typed by hand
    /// (see ``Library/editValuations(_:)``).
    @discardableResult
    public func apply(to library: inout Library) -> FlowFollowUp {
        let records = records(in: library)
        return library.editValuations { apply(records, to: &$0) }
    }

    // MARK: - Internals

    /// The records for the valuations `written`, with this check-in's prices and FX rates.
    private func records(writing written: [Valuation], in library: Library) -> CheckInRecords {
        let moves = written.map(\.account).filter { library.accounts[$0].map { $0.opened > date } ?? false }
        return CheckInRecords(valuations: written, prices: prices, fxRates: fxRates, openingMoves: moves)
    }

    private func apply(_ records: CheckInRecords, to library: inout Library) {
        for price in records.prices { library.upsert(price) }
        for rate in records.fxRates { library.upsert(rate) }
        for valuation in records.valuations { library.upsert(valuation) }
        for account in records.openingMoves where library.accounts[account].map({ $0.opened > date }) ?? false {
            library.accounts[account]?.opened = date
        }
    }

    /// The library with this check-in's prices and FX rates added.
    public func libraryWithRates(_ library: Library) -> Library {
        var library = library
        for price in prices { library.upsert(price) }
        for rate in fxRates { library.upsert(rate) }
        return library
    }

    struct Proposal {
        /// The row's values as a valuation, whatever its state.
        var valuation: Valuation
        /// What the row writes, with its flow; `nil` unless updated or
        /// unchanged, and not in conflict.
        var written: Valuation?
        var defaultFlow: Decimal?
        var positions: [CheckInPositionReview]
    }

    /// The row valued with `valuator`. With `ignoringConflict`, `written` is
    /// what the row would write once its conflict is settled in its favour.
    func proposal(for row: CheckInRow, using valuator: Valuator, ignoringConflict: Bool = false) -> Proposal {
        let currency = valuator.accounts[row.account]?.currency ?? valuator.baseCurrency
        var valuation = Valuation(account: row.account, date: date, note: row.note, source: row.source)
        var reviews: [CheckInPositionReview] = []
        if row.mode == .balance {
            valuation.balance = row.balance
        } else if row.mode == .trades {
            // The cash; positions entered are a reconciliation check, written as entered.
            valuation.cash = row.cash
            valuation.positions = row.positions.filter { $0.quantity != 0 }.map {
                Position(instrument: $0.instrument, quantity: $0.quantity, costBasis: $0.enteredCostBasis)
            }
            // The review shows what the trades hold.
            let ledger = valuator.ledger(for: row.account)
            let held = ledger?.positions(on: date) ?? []
            let before = row.previous.flatMap { ledger?.positions(on: $0.date) } ?? []
            var instruments = held.map(\.instrument)
            for position in before where !instruments.contains(position.instrument) {
                instruments.append(position.instrument)
            }
            for instrument in instruments {
                let position = held.first { $0.instrument == instrument }
                let quantity = position?.quantity ?? 0
                reviews.append(CheckInPositionReview(
                    instrument: instrument, quantity: quantity,
                    previousQuantity: before.first { $0.instrument == instrument }?.quantity ?? 0,
                    price: valuator.prices.latest(for: instrument, onOrBefore: date),
                    value: valuator.marketValue(of: quantity, of: instrument, in: valuator.baseCurrency, on: date),
                    estimatedPaid: nil, costBasis: position?.costBasis))
            }
        } else {
            valuation.cash = row.cash
            for position in row.positions {
                let estimate = position.isIncrease
                    ? valuator.marketValue(of: position.quantityChange, of: position.instrument, in: currency,
                                           on: date)?.rounded(scale: 2)
                    : nil
                let cost = position.enteredCostBasis ?? CostBasis.updated(
                    previousQuantity: position.previousQuantity, previousCost: position.previousCostBasis,
                    quantity: position.quantity, paid: position.paid ?? estimate)
                if position.quantity != 0 {
                    valuation.positions.append(Position(instrument: position.instrument, quantity: position.quantity,
                                                        costBasis: cost))
                }
                reviews.append(CheckInPositionReview(
                    instrument: position.instrument, quantity: position.quantity,
                    previousQuantity: position.previousQuantity,
                    price: valuator.prices.latest(for: position.instrument, onOrBefore: date),
                    value: valuator.marketValue(of: position.quantity, of: position.instrument,
                                                in: valuator.baseCurrency, on: date),
                    estimatedPaid: estimate, costBasis: position.quantity == 0 ? nil : cost))
            }
        }
        // Unchanged is no new money, except in a trades account: its deposits and withdrawals since.
        let defaultFlow = row.state == .unchanged && !row.isTrades
            ? 0 : valuator.defaultFlow(for: valuation, previous: row.previous, paid: row.paid)
        var written: Valuation?
        if row.state == .updated || row.state == .unchanged, ignoringConflict || row.conflict == nil {
            var record = valuation
            record.flow = row.isFlowEdited ? row.enteredFlow : defaultFlow
            let moneyOut = row.enteredMoneyOut ?? CheckInDraft.defaultMoneyOut(moneyIn: row.moneyIn, flow: record.flow)
            // Both or neither: a value with only one of them isn't counted.
            let recordsBoth = row.moneyIn != nil && moneyOut != nil
            record.moneyIn = recordsBoth ? row.moneyIn : nil
            record.moneyOut = recordsBoth ? moneyOut : nil
            written = record
        }
        return Proposal(valuation: valuation, written: written, defaultFlow: defaultFlow, positions: reviews)
    }
}
