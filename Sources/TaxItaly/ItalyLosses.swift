import TaxKit

/// How Italy treats a sale's gain or loss from an ordinary account
/// (TUIR art. 44, 67 and 68; tax/IT.md, "Investments").
enum ItalyGainKind: Sendable {
    /// *Redditi diversi* (art. 67 c. 1 lett. c–c-quinquies): shares, bonds,
    /// government bonds, ETCs, gold and other securities. Gains and losses
    /// net within the year, weighted by their rate against the standard one
    /// (government bonds count at 12.5 / 26 = 48.08%), and a net loss is
    /// carried forward to the fourth following year.
    case diversi
    /// Crypto-assets (art. 67 c. 1 lett. c-sexies, art. 68 c. 9-bis): their
    /// own closed basket, netted and carried forward like *redditi diversi*
    /// but never against them.
    case crypto
    /// Funds and ETFs: a gain is *reddito di capitale* (art. 44 c. 1 lett. g),
    /// taxed in full and never offset; a loss is *reddito diverso* (art. 67
    /// c. 1 lett. c-ter), so it offsets other *redditi diversi*.
    case fund
    /// Not taxed: cash, property held over five years, any category at a zero rate.
    case untaxed
}

/// How Italy taxes the gain on one category: the category it's taxed as
/// (every kind of fund is a fund), the rate, the basket, and the weight of
/// a *reddito diverso* in its basket (its rate over the standard rate).
struct ItalyGainRule: Sendable {
    let category: TaxCategory
    let rate: Double
    let kind: ItalyGainKind
    let weight: Double

    init(_ category: TaxCategory, investments: ItalyParameters.Investments) {
        let resolved = ItalyMarketLabels.resolve(category)
        let rate = investments.gainRate(for: resolved)
        self.category = resolved
        self.rate = rate
        if resolved == .cash || rate <= 0 {
            kind = .untaxed
        } else if resolved == .fund {
            kind = .fund
        } else if resolved == .crypto || resolved == .stablecoin {
            kind = .crypto
        } else {
            kind = .diversi
        }
        weight = investments.standardRate > 0 ? rate / investments.standardRate : 1
    }
}

/// The year's gain rules by category, made once per prepared year: sales
/// are classified for every assessment of every path, and finding a rule
/// costs less than resolving a category against the rates each time.
struct ItalyGainRules: Sendable {
    let investments: ItalyParameters.Investments
    private let known: [(category: TaxCategory, rule: ItalyGainRule)]

    /// The planner's categories, the most common first: a short linear
    /// search of small strings is cheaper than hashing them.
    private static let categories: [TaxCategory] = [
        .equityFund, .crypto, .fund, .physicalGold, .governmentBond, .stock, .bond, .mixedFund, .etc,
        .etcWithDeliveryClaim, .stablecoin, .realEstateFund, .foreignRealEstateFund, .cash, .realEstate, .other,
    ]

    init(_ investments: ItalyParameters.Investments) {
        self.investments = investments
        known = Self.categories.map { ($0, ItalyGainRule($0, investments: investments)) }
    }

    func rule(for category: TaxCategory) -> ItalyGainRule {
        for entry in known where entry.category == category { return entry.rule }
        return ItalyGainRule(category, investments: investments)
    }
}

/// A year's gains and losses on sales from ordinary accounts, by basket, in
/// the plan's currency (today's money). Gains of *redditi diversi* and their
/// losses count at their rate's share of the standard rate, so the basket's
/// net is taxed at the standard rate.
struct ItalyGains: Sendable {
    /// Tax on fund gains, which nothing offsets.
    var capitalTax = 0.0
    /// *Redditi diversi* gains at the standard rate's weight, and their tax.
    var diversiGains = 0.0
    var diversiTax = 0.0
    /// *Redditi diversi* losses (funds' included) at the standard rate's weight.
    var diversiLosses = 0.0
    var cryptoGains = 0.0
    var cryptoTax = 0.0
    var cryptoLosses = 0.0

    /// A sale's gain, negative for a loss. Without a documented cost, physical
    /// gold's gain is the parameter's share of the price, and anything else's
    /// the whole price (as if it cost nothing).
    static func gain(of sale: VariableYear.Sale, rule: ItalyGainRule, investments: ItalyParameters.Investments)
        -> Double {
        if let cost = sale.costBasis { return sale.proceeds - cost }
        if rule.category == .physicalGold { return max(0, sale.proceeds * investments.goldUndocumentedGainShare) }
        return max(0, sale.proceeds)
    }

    /// Adds a sale from an ordinary account.
    mutating func add(_ sale: VariableYear.Sale, rules: ItalyGainRules) {
        let rule = rules.rule(for: sale.category)
        guard rule.kind != .untaxed else { return }
        let gain = Self.gain(of: sale, rule: rule, investments: rules.investments)
        switch rule.kind {
        case .untaxed:
            break
        case .fund:
            if gain > 0 {
                capitalTax += rule.rate * gain
            } else {
                diversiLosses -= gain * rule.weight
            }
        case .diversi:
            if gain > 0 {
                diversiGains += gain * rule.weight
                diversiTax += rule.rate * gain
            } else {
                diversiLosses -= gain * rule.weight
            }
        case .crypto:
            if gain > 0 {
                cryptoGains += gain
                cryptoTax += rule.rate * gain
            } else {
                cryptoLosses -= gain
            }
        }
    }

    /// Adds the sales from ordinary accounts (and wrappers Italy doesn't
    /// know, which it treats alike).
    mutating func add(_ sales: [VariableYear.Sale], rules: ItalyGainRules) {
        for sale in sales {
            switch WrapperTreatment(sale.wrapper) {
            case .ordinary, .unknown: add(sale, rules: rules)
            default: break
            }
        }
    }

    /// How much of the *redditi diversi* gains losses offset: the year's
    /// own first, then those carried forward.
    func diversiOffset(carried: Double) -> Double {
        min(diversiGains, diversiLosses + max(0, carried))
    }

    func cryptoOffset(carried: Double) -> Double {
        min(cryptoGains, cryptoLosses + max(0, carried))
    }

    /// The share of each basket's gains left to tax.
    func taxedShares(_ carried: ItalyCarriedLosses) -> (diversi: Double, crypto: Double) {
        (diversiGains > 0 ? (diversiGains - diversiOffset(carried: carried.diversiTotal)) / diversiGains : 1,
         cryptoGains > 0 ? (cryptoGains - cryptoOffset(carried: carried.cryptoTotal)) / cryptoGains : 1)
    }

    /// The tax on the year's gains after losses.
    func tax(_ carried: ItalyCarriedLosses) -> Double {
        let shares = taxedShares(carried)
        return capitalTax + diversiTax * shares.diversi + cryptoTax * shares.crypto
    }
}

/// Losses carried into a year along a path, per basket and the year they
/// were realised: slot 0 is four years back (its last year of use), slot 3
/// last year. In the plan's currency, today's money.
struct ItalyCarriedLosses: Sendable {
    var diversi = SIMD4<Double>(repeating: 0)
    var crypto = SIMD4<Double>(repeating: 0)
    /// Whether the state holds loss keys that have expired or aren't known.
    var stale = false

    var diversiTotal: Double { diversi.sum() }
    var cryptoTotal: Double { crypto.sum() }

    /// Uses `amount` of the losses in `slots`, oldest first.
    static func consume(_ amount: Double, from slots: inout SIMD4<Double>) {
        var left = amount
        for index in 0..<4 where left > 0 {
            let take = min(left, slots[index])
            slots[index] -= take
            left -= take
        }
    }
}

/// The path-state keys of losses carried forward, made once per prepared
/// year: `it.losses.diversi.<year>` and `it.losses.crypto.<year>`, each in
/// nominal euros of no particular year (euros × the prices of the year they
/// were stored in), so a loss shrinks in today's money as prices rise.
struct ItalyLossKeys: Sendable {
    static let prefix = "it.losses."
    let year: Int
    /// For the years `year − 4 … year`.
    let diversi: [String]
    let crypto: [String]
    /// Plan currency in today's money to nominal euros: the currency rate
    /// times the year's prices.
    let scale: Double

    init(year: Int, currencyRate: Double, prices: Double) {
        self.year = year
        diversi = (year - 4...year).map { "\(Self.prefix)diversi.\($0)" }
        crypto = (year - 4...year).map { "\(Self.prefix)crypto.\($0)" }
        let scale = currencyRate * prices
        self.scale = scale > 0 ? scale : 1
    }

    /// The losses `state` carries into the year: those of the four years
    /// before it (`offset` 0), or of the year and the three before it
    /// (`offset` 1, what the year carries into the next). One pass over the
    /// state's few keys, reading each loss key's basket and year from its
    /// bytes: it runs for every assessment, where hashing every key the
    /// state might hold would cost more.
    func carried(in state: TaxState, offset: Int = 0) -> ItalyCarriedLosses {
        var carried = ItalyCarriedLosses()
        guard !state.values.isEmpty else { return carried }
        let first = year - 4 + offset
        for (key, value) in state.values {
            guard let (isCrypto, realised) = Self.parse(key) else { continue }
            let slot = realised - first
            guard slot >= 0 && slot < 4 else {
                carried.stale = true
                continue
            }
            if isCrypto {
                carried.crypto[slot] = max(0, value) / scale
            } else {
                carried.diversi[slot] = max(0, value) / scale
            }
        }
        return carried
    }

    /// A loss key's basket and year, or `nil` for any other key (an
    /// unparseable loss key gets year `Int.min`, so it counts as stale).
    static func parse(_ key: String) -> (isCrypto: Bool, year: Int)? {
        key.utf8.withContiguousStorageIfAvailable { bytes in
            parse(bytes)
        } ?? parse(Array(key.utf8))
    }

    private static let prefixBytes = Array(prefix.utf8)
    private static let diversiBytes = Array("diversi.".utf8)
    private static let cryptoBytes = Array("crypto.".utf8)

    private static func parse<Bytes: RandomAccessCollection>(_ bytes: Bytes) -> (isCrypto: Bool, year: Int)?
    where Bytes.Element == UInt8, Bytes.Index == Int {
        func matches(_ part: [UInt8], at start: Int) -> Bool {
            guard bytes.count - start >= part.count else { return false }
            for (offset, byte) in part.enumerated() where bytes[bytes.startIndex + start + offset] != byte {
                return false
            }
            return true
        }
        guard matches(prefixBytes, at: 0) else { return nil }
        let isCrypto: Bool
        var position: Int
        if matches(diversiBytes, at: prefixBytes.count) {
            isCrypto = false
            position = prefixBytes.count + diversiBytes.count
        } else if matches(cryptoBytes, at: prefixBytes.count) {
            isCrypto = true
            position = prefixBytes.count + cryptoBytes.count
        } else {
            return (false, Int.min)
        }
        var year = 0
        guard position < bytes.count else { return (isCrypto, Int.min) }
        while position < bytes.count {
            let byte = bytes[bytes.startIndex + position]
            guard byte >= 48 && byte <= 57, year < 100_000 else { return (isCrypto, Int.min) }
            year = year * 10 + Int(byte - 48)
            position += 1
        }
        return (isCrypto, year)
    }

    /// `state` with the losses carried out of the year: what's left of the
    /// three years before it (the fourth year's expire with it) and the
    /// year's own new losses. Only the keys that change are written.
    func state(_ state: TaxState, carried: ItalyCarriedLosses, left: ItalyCarriedLosses, newDiversi: Double,
               newCrypto: Double) -> TaxState {
        var next = state
        func store(_ key: String, _ amount: Double) {
            next[key] = amount > 1e-9 ? amount * scale : nil
        }
        if carried.stale {
            for key in state.values.keys where Self.parse(key) != nil { next[key] = nil }
        }
        if carried.stale || carried.diversi[0] > 0 { next[diversi[0]] = nil }
        if carried.stale || carried.crypto[0] > 0 { next[crypto[0]] = nil }
        for slot in 1..<4 {
            if carried.stale || left.diversi[slot] != carried.diversi[slot] { store(diversi[slot], left.diversi[slot]) }
            if carried.stale || left.crypto[slot] != carried.crypto[slot] { store(crypto[slot], left.crypto[slot]) }
        }
        if newDiversi > 0 { store(diversi[4], newDiversi) }
        if newCrypto > 0 { store(crypto[4], newCrypto) }
        return next
    }

    /// The losses carried out of the year, per year they were realised, for reports.
    func lines(_ state: TaxState) -> [TaxLine] {
        let carried = self.carried(in: state, offset: 1)
        var lines: [TaxLine] = []
        for slot in 0..<4 {
            let realised = year - 3 + slot
            if carried.diversi[slot] > 0.005 {
                lines.append(TaxLine(id: "it.losses.diversi",
                                     label: "Losses from \(realised) (redditi diversi), usable to \(realised + 4)",
                                     amount: carried.diversi[slot]))
            }
            if carried.crypto[slot] > 0.005 {
                lines.append(TaxLine(id: "it.losses.crypto",
                                     label: "Crypto losses from \(realised), usable to \(realised + 4)",
                                     amount: carried.crypto[slot]))
            }
        }
        return lines
    }
}
