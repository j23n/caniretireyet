import Foundation
import Model

/// Balances transactions in date order and keeps every account's running
/// balance, to set balance assignments and check balance assertions.
///
/// Real postings balance among themselves, and so do `[balanced virtual]`
/// ones; `(unbalanced virtual)` postings don't have to. Postings balance at
/// cost: a posting with a lot price or an `@` price counts as its cost. A
/// transaction exchanging two commodities without prices gets its price
/// inferred (the first posting's commodity is priced in the other one).
struct LedgerBalancer {
    /// The most decimals each commodity's amounts were written with.
    let precision: [String: Int]
    private(set) var diagnostics: [LedgerDiagnostic] = []
    /// Running balances: account → commodity → quantity.
    private var balances: [String: [String: Decimal]] = [:]

    init(precision: [String: Int]) {
        self.precision = precision
    }

    /// Half a unit of the commodity's last written decimal: sums within it are zero.
    func tolerance(_ commodity: String) -> Decimal {
        Decimal(sign: .plus, exponent: -((precision[commodity] ?? 2) + 1), significand: 5)
    }

    /// The balanced transaction, or `nil` (with an error) if it can't be balanced.
    mutating func balance(_ raw: RawTransaction) -> LedgerTransaction? {
        var postings = raw.postings
        var inferred = Set<Int>()
        var assigned = Set<Int>()

        // Balance assignments, in posting order, counting this transaction's earlier postings.
        var pending: [String: [String: Decimal]] = [:]
        for index in postings.indices {
            let posting = postings[index]
            if posting.amount == nil, let assignment = posting.assertion {
                let commodity = assignment.amount.commodity
                let current = balance(of: posting.account, commodity: commodity, inclusive: assignment.isInclusive,
                                      plus: pending)
                postings[index].amount = ParsedAmount(quantity: assignment.amount.quantity - current,
                                                      commodity: commodity, decimals: assignment.amount.decimals)
                inferred.insert(index)
                assigned.insert(index)
            }
            if let amount = postings[index].amount {
                pending[posting.account, default: [:]][amount.commodity, default: 0] += amount.quantity
            }
        }

        // Costs from lot prices and `@` prices.
        var costs: [Int: LedgerAmount] = [:]
        var unitPrices: [Int: LedgerAmount] = [:]
        for (index, posting) in postings.enumerated() {
            guard let amount = posting.amount else { continue }
            let sign: Decimal = amount.quantity < 0 ? -1 : 1
            if let price = posting.price, price.amount.commodity != amount.commodity {
                let magnitude = abs(price.amount.quantity)
                unitPrices[index] = price.isTotal
                    ? (amount.quantity == 0 ? nil : LedgerAmount(magnitude / abs(amount.quantity), price.amount.commodity))
                    : LedgerAmount(price.amount.quantity, price.amount.commodity)
                costs[index] = price.isTotal ? LedgerAmount(sign * magnitude, price.amount.commodity)
                    : LedgerAmount(amount.quantity * price.amount.quantity, price.amount.commodity)
            }
            if let lot = posting.lot, lot.amount.commodity != amount.commodity {
                costs[index] = lot.isTotal ? LedgerAmount(sign * abs(lot.amount.quantity), lot.amount.commodity)
                    : LedgerAmount(amount.quantity * lot.amount.quantity, lot.amount.commodity)
            }
        }

        // Amounts left out, and inferred prices, per group of postings that must balance.
        var extra: [Int: [LedgerAmount]] = [:]
        for kind in [LedgerPosting.Kind.real, .balancedVirtual] {
            let members = postings.indices.filter { postings[$0].kind == kind }
            guard !members.isEmpty else { continue }
            let elided = members.filter { postings[$0].amount == nil }
            if elided.count > 1 {
                return fail("More than one posting has no amount, so the transaction can't be balanced.", raw)
            }
            var sums = Sums()
            for index in members {
                guard let amount = postings[index].amount else { continue }
                sums.add(costs[index] ?? amount.amount)
            }
            if let missing = elided.first {
                let open = sums.entries.filter { abs($0.value) > tolerance($0.commodity) }
                if open.isEmpty {
                    let commodity = sums.entries.first?.commodity ?? ""
                    postings[missing].amount = ParsedAmount(quantity: 0, commodity: commodity, decimals: 0)
                } else {
                    postings[missing].amount = ParsedAmount(quantity: -open[0].value, commodity: open[0].commodity,
                                                            decimals: 0)
                    extra[missing] = open.dropFirst().map { LedgerAmount(-$0.value, $0.commodity) }
                }
                inferred.insert(missing)
                continue
            }
            var open = sums.entries.filter { abs($0.value) > tolerance($0.commodity) }
            if open.count == 2, members.allSatisfy({ costs[$0] == nil }) {
                // An exchange without prices: price the first posting's commodity in the other.
                let first = members.lazy.compactMap { postings[$0].amount?.commodity }
                    .first { commodity in open.contains { $0.commodity == commodity } } ?? open[0].commodity
                let from = open.first { $0.commodity == first }!, to = open.first { $0.commodity != first }!
                let rate = -to.value / from.value
                for index in members where postings[index].amount?.commodity == first {
                    costs[index] = LedgerAmount(postings[index].amount!.quantity * rate, to.commodity)
                }
                open = []
            }
            if !open.isEmpty {
                let off = open.map { LedgerAmount($0.value, $0.commodity).description }.joined(separator: ", ")
                return fail("The transaction doesn't balance: it's off by \(off). It was skipped.", raw)
            }
        }

        // Unbalanced virtual postings need their own amounts.
        for index in postings.indices.reversed() where postings[index].amount == nil {
            diagnostics.append(LedgerDiagnostic(.warning, "A virtual posting without an amount was skipped.",
                                                at: postings[index].location))
            postings.remove(at: index)
        }

        // Running balances, and assertions after each posting.
        var result: [LedgerPosting] = []
        for (index, raw) in postings.enumerated() {
            guard let amount = raw.amount else { continue }
            var amounts = [amount.amount] + (extra[index] ?? [])
            if amounts.count > 1 { amounts = amounts.filter { $0.quantity != 0 } }
            for (offset, each) in amounts.enumerated() {
                balances[raw.account, default: [:]][each.commodity, default: 0] += each.quantity
                result.append(LedgerPosting(
                    account: raw.account, kind: raw.kind, amount: each, cost: offset == 0 ? costs[index] : nil,
                    unitPrice: offset == 0 ? unitPrices[index] : nil, isInferred: inferred.contains(index),
                    location: raw.location))
            }
            if let assertion = raw.assertion, !assigned.contains(index) {
                check(assertion, account: raw.account, at: raw.location)
            }
        }
        return LedgerTransaction(date: raw.date, status: raw.status, code: raw.code, description: raw.description,
                                 postings: result, location: raw.location)
    }

    private mutating func fail(_ message: String, _ raw: RawTransaction) -> LedgerTransaction? {
        diagnostics.append(LedgerDiagnostic(.error, message, at: raw.location))
        return nil
    }

    /// An account's balance in one commodity, optionally with its subaccounts,
    /// plus amounts not yet applied.
    private func balance(of account: String, commodity: String, inclusive: Bool,
                         plus pending: [String: [String: Decimal]] = [:]) -> Decimal {
        var total: Decimal = 0
        for source in [balances, pending] {
            for (name, amounts) in source where name == account || (inclusive && name.hasPrefix(account + ":")) {
                total += amounts[commodity] ?? 0
            }
        }
        return total
    }

    private mutating func check(_ assertion: RawAssertion, account: String, at location: LedgerLocation) {
        var held: [String: Decimal] = [:]
        for (name, amounts) in balances where name == account || (assertion.isInclusive && name.hasPrefix(account + ":")) {
            for (commodity, quantity) in amounts { held[commodity, default: 0] += quantity }
        }
        let asserted = assertion.amount
        var problems: [String] = []
        if assertion.isAnyCommodity {
            let nonzero = held.filter { abs($0.value) > tolerance($0.key) }.sorted { $0.key < $1.key }
            if !nonzero.isEmpty {
                problems.append("it's " + nonzero.map { LedgerAmount($0.value, $0.key).description }
                    .joined(separator: ", ") + ", the journal says 0")
            }
        } else {
            let actual = held[asserted.commodity] ?? 0
            if abs(actual - asserted.quantity) > tolerance(asserted.commodity) {
                problems.append("it's \(LedgerAmount(actual, asserted.commodity)), the journal says \(asserted.amount)")
            }
            if assertion.isExact {
                let others = held.filter { $0.key != asserted.commodity && abs($0.value) > tolerance($0.key) }
                if !others.isEmpty {
                    problems.append("it also holds " + others.sorted { $0.key < $1.key }
                        .map { LedgerAmount($0.value, $0.key).description }.joined(separator: ", "))
                }
            }
        }
        if !problems.isEmpty {
            diagnostics.append(LedgerDiagnostic(
                .warning, "The balance assertion for \(account) fails: \(problems.joined(separator: "; ")).",
                at: location))
        }
    }
}

/// Sums per commodity, in the order commodities first appear.
private struct Sums {
    private(set) var entries: [(commodity: String, value: Decimal)] = []

    mutating func add(_ amount: LedgerAmount) {
        if let index = entries.firstIndex(where: { $0.commodity == amount.commodity }) {
            entries[index].value += amount.quantity
        } else {
            entries.append((amount.commodity, amount.quantity))
        }
    }
}
