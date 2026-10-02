import Foundation
import Model

/// A period to measure returns over (PROGRESS.md, "Performance"), ending on
/// the as-of date.
public enum PerformancePeriod: String, Hashable, Sendable, CaseIterable {
    /// From the check-in before the latest one to the latest one.
    case sinceLastCheckIn
    /// From 31 December of the previous year.
    case yearToDate
    case oneYear
    case threeYears
    case fiveYears
    /// From the first valuation.
    case sinceStart
}

/// What returns are measured for.
public enum PerformanceSubject: Hashable, Sendable {
    /// Every account in the scope except debts.
    case portfolio(NetWorthScope)
    /// One asset class across the accounts in the scope except debts. Values
    /// and flows are split the way the asset-class breakdown splits them.
    case assetClass(AssetClass, NetWorthScope)
    /// One account.
    case account(AccountID)
}

/// A return over a period, e.g. 0.12 for +12%.
public struct ReturnFigure: Hashable, Sendable {
    /// Over the whole period.
    public let cumulative: Decimal
    /// Per year, for periods longer than a year; `nil` otherwise.
    public let annualized: Decimal?

    /// The figure to show: annualised when the period is longer than a year.
    public var headline: Decimal { annualized ?? cumulative }

    /// A return over `days` days from its cumulative value.
    public init(cumulative: Decimal, days: Int) {
        self.cumulative = cumulative
        if days > 365 {
            let perYear = pow(1 + cumulative.doubleValue, 365 / Double(days)) - 1
            annualized = Decimal(approximating: perYear) ?? cumulative
        } else {
            annualized = nil
        }
    }
}

/// Returns over one period, nominal and real.
public struct PerformanceResult: Hashable, Sendable {
    public let subject: PerformanceSubject
    public let start: CalendarDate
    public let end: CalendarDate
    /// The value of the included accounts at the start and the end, in the base currency.
    public let startValue: Decimal
    public let endValue: Decimal
    /// Net money added (+) or taken out (−) over the period.
    public let netFlows: Decimal
    /// Modified Dietz per period between valuations, chained. Independent of
    /// when money was added; comparable to a plan's assumed return.
    public let timeWeighted: ReturnFigure?
    /// The internal rate of return (XIRR) of the flows: what you experienced.
    public let moneyWeighted: ReturnFigure?
    /// The change of the inflation index (the library's own, e.g. `hicp-de`) over the period.
    public let inflation: ReturnFigure?
    /// The time-weighted return after inflation.
    public let realTimeWeighted: ReturnFigure?
    /// The money-weighted return after inflation, from flows in money of the start date.
    public let realMoneyWeighted: ReturnFigure?
    /// The accounts the returns cover.
    public let accounts: [AccountID]
    /// Accounts left out because their flows are unknown: a valuation in the
    /// period has no flow, or a balance carried into it had none.
    public let unknownFlowAccounts: [AccountID]
    /// Accounts left out because a price or FX rate is missing.
    public let incompleteAccounts: [AccountID]

    /// The length of the period in days.
    public var days: Int { start.days(to: end) }
}

extension Valuator {
    /// The dates `period` covers for `subject`, ending on `date`; `nil` when
    /// the history doesn't reach back to the start (or, for "since the last
    /// check-in", there are fewer than two check-ins).
    public func dateRange(of period: PerformancePeriod, for subject: PerformanceSubject,
                          asOf date: CalendarDate) -> ClosedRange<CalendarDate>? {
        let candidates = performanceCandidates(for: subject)
        // A trades account's history starts with its first trade.
        let firstTrades = candidates.compactMap { ledgers[$0.id]?.firstDate }
        let dates = Set(candidates.flatMap { valuations(for: $0.id).map(\.date) } + firstTrades)
            .filter { $0 <= date }.sorted()
        guard let first = dates.first else { return nil }
        let start: CalendarDate
        var end = date
        switch period {
        case .sinceLastCheckIn:
            guard dates.count >= 2 else { return nil }
            start = dates[dates.count - 2]
            end = dates[dates.count - 1]
        case .yearToDate: start = YearMonth(year: date.year - 1, month: 12)?.lastDay ?? first
        case .oneYear: start = date.adding(years: -1)
        case .threeYears: start = date.adding(years: -3)
        case .fiveYears: start = date.adding(years: -5)
        case .sinceStart: start = first
        }
        guard start >= first, start < end else { return nil }
        return start...end
    }

    /// Returns for `subject` over `period` ending on `date`; `nil` when the
    /// history doesn't cover the period. Real returns need `inflation`.
    public func performance(of subject: PerformanceSubject, over period: PerformancePeriod,
                            asOf date: CalendarDate, inflation: InflationIndex? = nil) -> PerformanceResult? {
        dateRange(of: period, for: subject, asOf: date).flatMap {
            performance(of: subject, from: $0.lowerBound, to: $0.upperBound, inflation: inflation)
        }
    }

    /// Returns for `subject` from `start` to `end`; `nil` unless `start < end`.
    ///
    /// The period is cut at every valuation date (and closing date) of the
    /// accounts involved. Each piece's return is Modified Dietz: a flow
    /// recorded at a valuation is assumed to happen halfway between the
    /// account's previous valuation and that one, within the piece. A change
    /// in quantity is a flow into the position (at the end price), so buying
    /// with an account's cash moves money between asset classes without
    /// counting as a return.
    ///
    /// Accounts with unknown flows are left out and listed: a valuation in
    /// the period without a flow, or a balance carried into the period whose
    /// valuation has none (such as a home that is never given flows). So are
    /// accounts whose value is incomplete. Debts are left out of the
    /// portfolio and asset classes.
    ///
    /// A trades account's flows are its ``TradeFlow``s (its stored `flow`s
    /// aren't used): deposits, withdrawals and transfers weighted from their
    /// own dates, and residuals from halfway between the valuation and the
    /// one with cash before it. Its flows are always known, unless a
    /// transfer can't be valued (then it's incomplete).
    public func performance(of subject: PerformanceSubject, from start: CalendarDate, to end: CalendarDate,
                            inflation: InflationIndex? = nil) -> PerformanceResult? {
        guard start < end else { return nil }
        let assetClass: AssetClass? = if case .assetClass(let assetClass, _) = subject { assetClass } else { nil }
        let candidates = performanceCandidates(for: subject)
            .filter { $0.opened <= end && ($0.closed.map { $0 >= start } ?? true) }
            .filter { account in assetClass.map { holds($0, in: account, from: start, to: end) } ?? true }

        var cuts: Set<CalendarDate> = [start, end]
        for account in candidates {
            for valuation in valuations(for: account.id) where valuation.date > start && valuation.date < end {
                cuts.insert(valuation.date)
            }
            if let closed = account.closed, closed > start, closed < end { cuts.insert(closed) }
        }
        let grid = cuts.sorted()

        var included: [Account] = []
        var unknownFlow: [AccountID] = []
        var incomplete: [AccountID] = []
        for account in candidates {
            let last = min(end, account.closed ?? end)
            let flows = valuations(for: account.id).filter { $0.date > start && $0.date <= last }
            // A balance carried into the period without a flow was never explained.
            let carried = account.isOpen(on: end) ? latestValuation(for: account.id, onOrBefore: end) : nil
            if account.recordsTrades {
                // Its flows come from its trades and cash.
                var problems: [ValuationProblem] = []
                if tradeFlowsInBaseCurrency(of: account, after: start, through: last, problems: &problems) != nil,
                   isCompletelyValued(account, on: grid, flows: []) {
                    included.append(account)
                } else {
                    incomplete.append(account.id)
                }
            } else if flows.contains(where: { $0.flow == nil })
                || carried.map({ $0.isBalance && $0.flow == nil && $0.date <= start }) ?? false {
                unknownFlow.append(account.id)
            } else if !isCompletelyValued(account, on: grid, flows: flows) {
                incomplete.append(account.id)
            } else {
                included.append(account)
            }
        }

        var growth: Decimal = 1
        var timeWeightedIsDefined = true
        var startValue: Decimal = 0
        var endValue: Decimal = 0
        var netFlows: Decimal = 0
        var flowsByDate: [CalendarDate: Decimal] = [:]
        for (index, (from, to)) in zip(grid, grid.dropFirst()).enumerated() {
            let length = Decimal(from.days(to: to))
            var gain: Decimal = 0
            var invested: Decimal = 0
            for account in included {
                for piece in pieces(of: account, from: from, to: to, splittingBy: assetClass != nil)
                where assetClass == nil || piece.assetClass == assetClass {
                    let weight = Decimal(piece.flowDate.days(to: to)) / length
                    gain += piece.end - piece.start - piece.flow
                    invested += piece.start + weight * piece.flow
                    if index == 0 { startValue += piece.start }
                    if to == end { endValue += piece.end }
                    netFlows += piece.flow
                    flowsByDate[piece.flowDate, default: 0] += piece.flow
                }
            }
            if invested != 0 {
                growth *= 1 + gain / invested
            } else if gain != 0 {
                timeWeightedIsDefined = false
            }
        }

        let days = start.days(to: end)
        let hasMoney = startValue != 0 || flowsByDate.values.contains { $0 != 0 }
        let timeWeighted = timeWeightedIsDefined && hasMoney ? ReturnFigure(cumulative: growth - 1, days: days) : nil

        var cashFlows = [DatedAmount(date: start, amount: -startValue), DatedAmount(date: end, amount: endValue)]
        cashFlows += flowsByDate.map { DatedAmount(date: $0.key, amount: -$0.value) }
        let moneyWeighted = XIRR.rate(of: cashFlows).map { moneyWeightedFigure(rate: $0, days: days) }

        let priceGrowth = inflation?.factor(from: start, to: end)
        var realTimeWeighted: ReturnFigure?
        if let timeWeighted, let priceGrowth {
            realTimeWeighted = ReturnFigure(cumulative: (1 + timeWeighted.cumulative) / priceGrowth - 1, days: days)
        }
        var realMoneyWeighted: ReturnFigure?
        if let inflation, moneyWeighted != nil {
            let deflated = cashFlows.compactMap { flow in
                inflation.convert(flow.amount, from: flow.date, to: start).map { DatedAmount(date: flow.date, amount: $0) }
            }
            if deflated.count == cashFlows.count {
                realMoneyWeighted = XIRR.rate(of: deflated).map { moneyWeightedFigure(rate: $0, days: days) }
            }
        }

        return PerformanceResult(
            subject: subject, start: start, end: end, startValue: startValue, endValue: endValue,
            netFlows: netFlows, timeWeighted: timeWeighted, moneyWeighted: moneyWeighted,
            inflation: priceGrowth.map { ReturnFigure(cumulative: $0 - 1, days: days) },
            realTimeWeighted: realTimeWeighted, realMoneyWeighted: realMoneyWeighted,
            accounts: included.map(\.id), unknownFlowAccounts: unknownFlow, incompleteAccounts: incomplete)
    }

    // MARK: - Internals

    /// The accounts a subject covers, sorted by ID: debts only when asked for by name.
    func performanceCandidates(for subject: PerformanceSubject) -> [Account] {
        switch subject {
        case .account(let id):
            return accounts[id].map { [$0] } ?? []
        case .portfolio(let scope), .assetClass(_, let scope):
            return accounts.values.filter { scope.includes($0) && !$0.kind.isLiability }.sorted { $0.id < $1.id }
        }
    }

    /// Whether the account holds some of `assetClass` at the start, the end
    /// or one of its valuations in between.
    private func holds(_ assetClass: AssetClass, in account: Account, from start: CalendarDate,
                       to end: CalendarDate) -> Bool {
        let dates = [start, end] + valuations(for: account.id).map(\.date).filter { $0 > start && $0 < end }
        return dates.contains { date in
            account.isOpen(on: date) && value(of: account, on: date).components.contains { component in
                (component.value ?? 1) != 0 && assetMix(of: component.kind, in: account).contains { $0.0 == assetClass }
            }
        }
    }

    /// Whether the account can be valued completely on every grid date it is
    /// open, and its flows converted to the base currency.
    private func isCompletelyValued(_ account: Account, on grid: [CalendarDate], flows: [Valuation]) -> Bool {
        for date in grid where account.isOpen(on: date) {
            let value = value(of: account, on: date)
            if value.problems.contains(where: { if case .noValuation = $0 { false } else { true } }) { return false }
        }
        if account.currency != baseCurrency {
            for valuation in flows where valuation.flow != 0 {
                if fx.quote(from: account.currency, to: baseCurrency, on: valuation.date) == nil { return false }
            }
        }
        return true
    }

    /// The annual XIRR as a figure: cumulative over the period, and annualised when longer than a year.
    private func moneyWeightedFigure(rate: Decimal, days: Int) -> ReturnFigure {
        let cumulative = pow(1 + rate.doubleValue, Double(days) / 365) - 1
        return ReturnFigure(cumulative: Decimal(approximating: cumulative) ?? rate, days: days)
    }

    /// One part of an account over one piece of the period, in the base currency.
    struct PerformancePiece {
        var assetClass: AssetClass?
        var start: Decimal
        var end: Decimal
        /// Money in (+) or out (−) during the piece.
        var flow: Decimal
        /// When the flow is assumed to happen, within the piece.
        var flowDate: CalendarDate
    }

    /// An account's parts from `from` to `to`, where no valuation of the
    /// account falls strictly between the two dates.
    ///
    /// A position's flow is its change in quantity at the end price; the
    /// rest of the account's recorded flow goes to its cash or balance (or,
    /// without either, to its positions pro rata). A closing account's value
    /// on the closing day leaves as a flow.
    func pieces(of account: Account, from: CalendarDate, to: CalendarDate,
                splittingBy splitByClass: Bool) -> [PerformancePiece] {
        if account.recordsTrades { return tradePieces(of: account, from: from, to: to, splittingBy: splitByClass) }
        typealias Kind = ValueComponent.Kind
        func parts(_ valuation: Valuation?, on date: CalendarDate) -> [Kind: Decimal] {
            guard let valuation else { return [:] }
            var parts: [Kind: Decimal] = [:]
            for component in value(of: account, valuation: valuation, on: date).components {
                parts[component.kind, default: 0] += component.value ?? 0
            }
            return parts
        }

        let openAtStart = account.isOpen(on: from)
        let openAtEnd = account.isOpen(on: to)
        guard openAtStart || openAtEnd else { return [] }
        let startValuation = openAtStart ? latestValuation(for: account.id, onOrBefore: from) : nil
        let atStart = parts(startValuation, on: from)

        var atEnd: [Kind: Decimal] = [:]
        var flows: [Kind: Decimal] = [:]
        var flowDate = to
        if !openAtEnd, let closed = account.closed {
            flowDate = max(closed, from)
            for (kind, amount) in parts(latestValuation(for: account.id, onOrBefore: closed), on: closed) {
                flows[kind] = -amount
            }
        } else {
            let endValuation = latestValuation(for: account.id, onOrBefore: to)
            atEnd = parts(endValuation, on: to)
            if let endValuation, endValuation.date != startValuation?.date {
                let held = parts(startValuation, on: to)
                var positionFlows: Decimal = 0
                for kind in Set(atEnd.keys).union(held.keys) {
                    guard case .position = kind else { continue }
                    let flow = (atEnd[kind] ?? 0) - (held[kind] ?? 0)
                    flows[kind] = flow
                    positionFlows += flow
                }
                let recorded = endValuation.flow.flatMap {
                    $0 == 0 ? 0 : fx.convert($0, from: account.currency, to: baseCurrency, on: endValuation.date)
                } ?? 0
                let rest = recorded - positionFlows
                if rest != 0 {
                    let has = { (kind: Kind) in atStart[kind] != nil || atEnd[kind] != nil }
                    let positions = atEnd.compactMap { kind, amount -> (InstrumentID, Decimal)? in
                        guard case .position(let instrument) = kind, amount > 0 else { return nil }
                        return (instrument, amount)
                    }.sorted { $0.0 < $1.0 }
                    if has(.cash) || positions.isEmpty && !has(.balance) {
                        flows[.cash, default: 0] += rest
                    } else if has(.balance) {
                        flows[.balance, default: 0] += rest
                    } else {
                        let total = positions.reduce(0) { $0 + $1.1 }
                        for (instrument, part) in split(rest, by: positions.map { ($0.0, $0.1 / total) }) {
                            flows[.position(instrument), default: 0] += part
                        }
                    }
                }
                let previous = previousValuation(for: account.id, before: endValuation.date)?.date ?? account.opened
                let middle = CalendarDate(daysSinceEpoch: (previous.daysSinceEpoch + endValuation.date.daysSinceEpoch) / 2)
                flowDate = min(max(middle, from), to)
            }
        }

        var pieces: [PerformancePiece] = []
        for kind in Set(atStart.keys).union(atEnd.keys).union(flows.keys) {
            let piece = PerformancePiece(assetClass: nil, start: atStart[kind] ?? 0, end: atEnd[kind] ?? 0,
                                         flow: flows[kind] ?? 0, flowDate: flowDate)
            pieces += classPieces(piece, kind: kind, in: account, splittingBy: splitByClass)
        }
        return pieces
    }

    /// `piece` of one part of an account, split by the part's asset mix
    /// when `splitByClass`.
    private func classPieces(_ piece: PerformancePiece, kind: ValueComponent.Kind, in account: Account,
                             splittingBy splitByClass: Bool) -> [PerformancePiece] {
        guard splitByClass else { return [piece] }
        let mix = assetMix(of: kind, in: account)
        let starts = split(piece.start, by: mix)
        let ends = split(piece.end, by: mix)
        let splitFlows = split(piece.flow, by: mix)
        return mix.indices.map { index in
            PerformancePiece(assetClass: mix[index].0, start: starts[index].1, end: ends[index].1,
                             flow: splitFlows[index].1, flowDate: piece.flowDate)
        }
    }

    /// A trades account's parts from `from` to `to` (no valuation of the
    /// account strictly between them, but trades may be).
    ///
    /// Values are snapshots. Each flow (``TradeFlow``) is its own piece,
    /// weighted from its date: deposits, withdrawals and residuals go to
    /// cash, transfers and openings to their position at their market
    /// value, buys and sales settled outside the account to their position
    /// at their amount (a fee or tax without an instrument to cash), and a
    /// residual is placed halfway between the valuation and the one with
    /// cash before it. Units bought or sold move money between
    /// cash and the position at the end price, weighted as at the end, so
    /// they add nothing for the account. A closing account's value on the
    /// closing day leaves as a flow.
    func tradePieces(of account: Account, from: CalendarDate, to: CalendarDate,
                     splittingBy splitByClass: Bool) -> [PerformancePiece] {
        typealias Kind = ValueComponent.Kind
        func parts(_ valuation: Valuation?, on date: CalendarDate) -> [Kind: Decimal] {
            guard let valuation else { return [:] }
            var parts: [Kind: Decimal] = [:]
            for component in value(of: account, valuation: valuation, on: date).components {
                parts[component.kind, default: 0] += component.value ?? 0
            }
            return parts
        }

        let openAtStart = account.isOpen(on: from)
        let openAtEnd = account.isOpen(on: to)
        guard openAtStart || openAtEnd else { return [] }
        let end = openAtEnd ? to : max(account.closed ?? to, from)
        let startSnapshot = openAtStart ? carried(account, on: from) : nil
        let atStart = parts(startSnapshot, on: from)
        let atEnd = account.opened <= end ? parts(carried(account, on: end), on: end) : [:]
        let held = parts(startSnapshot, on: end)

        var problems: [ValuationProblem] = []
        let flows = tradeFlowsInBaseCurrency(of: account, after: from, through: end, problems: &problems) ?? []
        var pieces: [PerformancePiece] = []

        // Units bought or sold (not moved in or out) at the end price, paid from cash.
        var bought: [Kind: Decimal] = [:]
        for kind in Set(atEnd.keys).union(held.keys) where kind != .cash && kind != .balance {
            bought[kind] = (atEnd[kind] ?? 0) - (held[kind] ?? 0)
        }
        for flow in flows {
            guard let trade = flow.flow.trade, let instrument = trade.instrument, let quantity = trade.quantity,
                  trade.type != .deposit, trade.type != .withdrawal
            else { continue }
            let moved = marketValue(of: quantity, of: instrument, in: baseCurrency, on: end) ?? flow.amount
            bought[.position(instrument), default: 0] -= trade.type.removesUnits ? -moved : moved
        }
        let spent = bought.values.reduce(0, +)

        for kind in Set(atStart.keys).union(atEnd.keys).union(bought.keys).union([.cash]) {
            let flow = kind == .cash ? -spent : bought[kind] ?? 0
            let piece = PerformancePiece(assetClass: nil, start: atStart[kind] ?? 0, end: atEnd[kind] ?? 0,
                                         flow: flow, flowDate: end)
            guard piece.start != 0 || piece.end != 0 || piece.flow != 0 else { continue }
            pieces += classPieces(piece, kind: kind, in: account, splittingBy: splitByClass)
        }
        for flow in flows {
            var kind = Kind.cash
            if let trade = flow.flow.trade, let instrument = trade.instrument, trade.type != .deposit,
               trade.type != .withdrawal {
                kind = .position(instrument)
            }
            var date = flow.date
            if let since = flow.flow.since {
                date = CalendarDate(daysSinceEpoch: (since.daysSinceEpoch + flow.date.daysSinceEpoch) / 2)
            }
            let piece = PerformancePiece(assetClass: nil, start: 0, end: 0, flow: flow.amount,
                                         flowDate: min(max(date, from), end))
            pieces += classPieces(piece, kind: kind, in: account, splittingBy: splitByClass)
        }
        if !openAtEnd {
            // Closed in the period: its value on the closing day leaves.
            for (kind, amount) in atEnd where amount != 0 {
                let piece = PerformancePiece(assetClass: nil, start: 0, end: -amount, flow: -amount, flowDate: end)
                pieces += classPieces(piece, kind: kind, in: account, splittingBy: splitByClass)
            }
        }
        return pieces
    }
}
