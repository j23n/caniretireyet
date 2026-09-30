import Foundation
import Model

/// Where an account or instrument comes from: an ID the profile gives, or a
/// name in the file to match.
enum NameRef: Hashable, Sendable {
    case id(String)
    case name(String)
}

/// Links names in the file to the library's accounts and instruments, and
/// drafts new ones for names that match nothing.
///
/// Order: an ID from the profile, a remembered match, then an existing
/// account's or instrument's name, ID or ticker, ignoring case and accents.
/// Headers are also tried without their decorations (`BTC (qtà)` → `BTC`).
struct NameMatcher {
    let library: Library
    let matches: ImportMatches
    private(set) var accountDrafts: [AccountID: AccountDraft] = [:]
    private(set) var instrumentDrafts: [InstrumentID: InstrumentDraft] = [:]
    private(set) var found: [NameMatch] = []
    private var seen = Set<NameMatch>()
    private var accountCache: [NameRef: AccountID] = [:]
    private var instrumentCache: [NameRef: InstrumentID] = [:]

    init(library: Library, matches: ImportMatches) {
        self.library = library
        self.matches = matches
    }

    // MARK: Resolving

    mutating func account(_ ref: NameRef) -> AccountID {
        if let id = accountCache[ref] { return id }
        let id = resolveAccount(ref)
        accountCache[ref] = id
        return id
    }

    mutating func instrument(_ ref: NameRef) -> InstrumentID {
        if let id = instrumentCache[ref] { return id }
        let id = resolveInstrument(ref)
        instrumentCache[ref] = id
        return id
    }

    /// The account a reference was already resolved to, if any.
    func resolvedAccount(_ ref: NameRef) -> AccountID? {
        accountCache[ref]
    }

    private mutating func resolveAccount(_ ref: NameRef) -> AccountID {
        switch ref {
        case .id(let raw):
            let id = AccountID(Slug.isValid(raw) ? raw : Slug.make(from: raw))
            if library.accounts[id] != nil {
                record(NameMatch(name: raw, account: id, method: .profile))
            } else {
                draftAccount(id: id, name: raw)
            }
            return id
        case .name(let name):
            if let (id, method) = existingAccount(named: name) {
                if library.accounts[id] != nil {
                    record(NameMatch(name: name, account: id, method: method))
                } else {
                    draftAccount(id: id, name: name)
                }
                return id
            }
            let cleaned = Keywords.name(fromHeader: name)
            let slug = AccountID(Slug.make(from: cleaned))
            let id = accountDrafts[slug] != nil ? slug
                : AccountID.make(from: cleaned, existing: Array(library.accounts.keys) + Array(accountDrafts.keys))
            draftAccount(id: id, name: cleaned, fileName: name)
            return id
        }
    }

    private mutating func resolveInstrument(_ ref: NameRef) -> InstrumentID {
        switch ref {
        case .id(let raw):
            let id = InstrumentID(Slug.isValid(raw) ? raw : Slug.make(from: raw))
            if library.instruments[id] != nil {
                record(NameMatch(name: raw, instrument: id, method: .profile))
            } else {
                draftInstrument(id: id, name: raw)
            }
            return id
        case .name(let name):
            if let (id, method) = existingInstrument(named: name) {
                if library.instruments[id] != nil {
                    record(NameMatch(name: name, instrument: id, method: method))
                } else {
                    draftInstrument(id: id, name: name)
                }
                return id
            }
            let cleaned = Keywords.name(fromHeader: name)
            let slug = InstrumentID(Slug.make(from: cleaned))
            let id = instrumentDrafts[slug] != nil ? slug
                : InstrumentID.make(from: cleaned,
                                    existing: Array(library.instruments.keys) + Array(instrumentDrafts.keys))
            draftInstrument(id: id, name: cleaned, fileName: name)
            return id
        }
    }

    /// A remembered or existing account for `name`, without drafting one.
    func existingAccount(named name: String) -> (AccountID, NameMatch.Method)? {
        for candidate in Self.candidates(name) {
            if let id = Self.lookup(candidate, in: matches.accounts) { return (id, .remembered) }
        }
        for candidate in Self.candidates(name) {
            let folded = TextTools.fold(candidate), slug = Slug.make(from: candidate)
            let accounts = library.sortedAccounts
            if let account = accounts.first(where: { TextTools.fold($0.name) == folded })
                ?? accounts.first(where: { $0.id.rawValue == slug }) {
                return (account.id, .existing)
            }
        }
        return nil
    }

    /// A remembered or existing instrument for `name`, without drafting one.
    func existingInstrument(named name: String) -> (InstrumentID, NameMatch.Method)? {
        for candidate in Self.candidates(name) {
            if let id = Self.lookup(candidate, in: matches.instruments) { return (id, .remembered) }
        }
        let instruments = library.instruments.values.sorted { $0.id < $1.id }
        for candidate in Self.candidates(name) {
            let folded = TextTools.fold(candidate), slug = Slug.make(from: candidate)
            if let instrument = instruments.first(where: { TextTools.fold($0.name) == folded })
                ?? instruments.first(where: {
                    $0.id.rawValue == slug || $0.ticker.map(TextTools.fold) == folded
                        || $0.isin.map(TextTools.fold) == folded
                }) {
                return (instrument.id, .existing)
            }
        }
        return nil
    }

    // MARK: Evidence for drafts

    /// Notes what a value says about the account it belongs to.
    mutating func note(account id: AccountID, target: ImportTarget, value: Decimal, currency: CurrencyCode?,
                       instrument: InstrumentID?, date: CalendarDate) {
        guard var draft = accountDrafts[id] else { return }
        draft.targets.insert(target)
        if let currency, target != .price { draft.currencies[currency, default: 0] += 1 }
        if let instrument { draft.instruments.insert(instrument) }
        if value > 0 { draft.sawPositive = true }
        if value < 0 { draft.sawNegative = true }
        draft.firstDate = min(draft.firstDate ?? date, date)
        accountDrafts[id] = draft
    }

    /// Notes the currency a price of an instrument is quoted in.
    mutating func note(instrument id: InstrumentID, priceCurrency: CurrencyCode?) {
        guard var draft = instrumentDrafts[id], let priceCurrency else { return }
        draft.currencies[priceCurrency, default: 0] += 1
        instrumentDrafts[id] = draft
    }

    // MARK: Results

    /// The drafted instruments, as proposals.
    func instrumentProposals(baseCurrency: CurrencyCode) -> [InstrumentProposal] {
        instrumentDrafts.values.sorted { $0.id < $1.id }.map {
            InstrumentProposal(instrument: $0.instrument(baseCurrency: baseCurrency), names: $0.names)
        }
    }

    /// The drafted accounts, as proposals. Accounts that were never used
    /// by a value are left out.
    func accountProposals(baseCurrency: CurrencyCode, instruments: [InstrumentID: Instrument]) -> [AccountProposal] {
        accountDrafts.values.sorted { $0.id < $1.id }.compactMap { draft in
            guard let first = draft.firstDate else { return nil }
            let kinds = draft.instruments.compactMap { instruments[$0]?.kind }
            return AccountProposal(account: draft.account(baseCurrency: baseCurrency, opened: first,
                                                          instrumentKinds: kinds),
                                   names: draft.names)
        }
    }

    // MARK: Internals

    private mutating func record(_ match: NameMatch) {
        if seen.insert(match).inserted { found.append(match) }
    }

    private mutating func draftAccount(id: AccountID, name: String, fileName: String? = nil) {
        let fileName = fileName ?? name
        var draft = accountDrafts[id] ?? AccountDraft(id: id, name: name)
        if !draft.names.contains(fileName) { draft.names.append(fileName) }
        accountDrafts[id] = draft
        record(NameMatch(name: fileName, account: id, method: .new))
    }

    private mutating func draftInstrument(id: InstrumentID, name: String, fileName: String? = nil) {
        let fileName = fileName ?? name
        var draft = instrumentDrafts[id] ?? InstrumentDraft(id: id, name: name)
        if !draft.names.contains(fileName) { draft.names.append(fileName) }
        instrumentDrafts[id] = draft
        record(NameMatch(name: fileName, instrument: id, method: .new))
    }

    /// The name as written, then without header decorations.
    static func candidates(_ name: String) -> [String] {
        let trimmed = TextTools.trim(name)
        let cleaned = Keywords.name(fromHeader: trimmed)
        return cleaned == trimmed ? [trimmed] : [trimmed, cleaned]
    }

    /// A remembered match: the exact name first, then ignoring case and accents.
    static func lookup<ID>(_ name: String, in remembered: [String: ID]) -> ID? {
        if let id = remembered[name] { return id }
        let folded = TextTools.fold(name)
        return remembered.keys.sorted().first { TextTools.fold($0) == folded }.flatMap { remembered[$0] }
    }
}

/// What the file says about an account the library doesn't have yet.
struct AccountDraft: Hashable {
    var id: AccountID
    var name: String
    var names: [String] = []
    var targets = Set<ImportTarget>()
    var currencies: [CurrencyCode: Int] = [:]
    var instruments = Set<InstrumentID>()
    var sawPositive = false
    var sawNegative = false
    var firstDate: CalendarDate?

    init(id: AccountID, name: String) {
        self.id = id
        self.name = name
    }

    /// The most common currency of its amounts.
    func currency(baseCurrency: CurrencyCode) -> CurrencyCode {
        currencies.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key ?? baseCurrency
    }

    func account(baseCurrency: CurrencyCode, opened: CalendarDate, instrumentKinds: [InstrumentKind]) -> Account {
        Account(id: id, name: name, kind: suggestedKind(instrumentKinds: instrumentKinds),
                currency: currency(baseCurrency: baseCurrency), opened: opened)
    }

    /// From the name, what the account holds and the sign of its values.
    func suggestedKind(instrumentKinds: [InstrumentKind]) -> AccountKind {
        let words = TextTools.words(name)
        let byName = Keywords.accountKinds.first { TextTools.contains(words, anyOf: $0.1) }?.0
        if !targets.isDisjoint(with: [.quantity, .costBasis, .cash]) {
            if !instrumentKinds.isEmpty, instrumentKinds.allSatisfy({ $0 == .crypto }) { return .crypto }
            if !instrumentKinds.isEmpty, instrumentKinds.allSatisfy({ $0 == .metal }) { return .metals }
            if let byName, byName.defaultValuationMode == .holdings || byName == .pensionFund { return byName }
            return .brokerage
        }
        if let byName { return byName }
        return sawNegative && !sawPositive ? .loan : .other
    }
}

/// What the file says about an instrument the library doesn't have yet.
struct InstrumentDraft: Hashable {
    var id: InstrumentID
    var name: String
    var names: [String] = []
    var currencies: [CurrencyCode: Int] = [:]

    init(id: InstrumentID, name: String) {
        self.id = id
        self.name = name
    }

    func instrument(baseCurrency: CurrencyCode) -> Instrument {
        let words = TextTools.words(name)
        let kind = Keywords.instrumentKinds.first { TextTools.contains(words, anyOf: $0.1) }?.0 ?? .other
        let currency = currencies.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key ?? baseCurrency
        let compact = name.filter { !$0.isWhitespace }
        let isISIN = compact.count == 12 && compact.prefix(2).allSatisfy { $0.isUppercase && $0.isLetter }
            && compact.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
        let isTicker = !isISIN && !name.contains(" ") && name.count <= 12
            && name.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber || $0 == ".") }
        let unit: InstrumentUnit = switch kind {
        case .crypto: InstrumentUnit(Keywords.cryptoSymbols[TextTools.fold(name)] ?? name.uppercased())
        case .metal: .gram
        default: .share
        }
        let assetClass: AssetClass = switch kind {
        case .crypto: .crypto
        case .metal: words.contains(where: { ["oro", "gold", "xau"].contains($0) }) ? .gold : .other
        case .etf, .stock, .fund: .equity
        case .bond: .bonds
        case .etc: words.contains(where: { ["oro", "gold", "xau"].contains($0) }) ? .gold : .other
        default: .other
        }
        return Instrument(id: id, name: name, kind: kind, currency: currency, unit: unit,
                          assetClasses: .single(assetClass), isin: isISIN ? compact : nil,
                          ticker: isTicker ? name : nil)
    }
}
