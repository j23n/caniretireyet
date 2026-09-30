import Foundation
import Model

/// A ledger account in the Accounts step: what it is and where it goes.
public struct LedgerAccountRow: Hashable, Sendable, Identifiable {
    /// What kind of account it is, from its root or its declared type.
    public enum Role: String, Hashable, Sendable {
        case asset, liability, income, expense, equity, other

        /// Assets and liabilities count toward net worth.
        public var isNetWorth: Bool { self == .asset || self == .liability }
    }

    /// Where an account's postings go.
    public enum Mapping: Hashable, Sendable {
        /// Assets and liabilities: valued as this library account.
        case account(AccountID)
        /// Assets and liabilities left out; money moving to them is a flow.
        case ignored
        /// A grouping account without postings of its own, such as
        /// `Assets:Bank`: its subaccounts go to accounts of their own.
        case split
        /// Income, expenses and the rest: postings against them are returns
        /// (dividends, interest, fees), not money added or taken out.
        case returns
        /// Income, expenses and the rest: postings against them are money
        /// added or taken out (salary, spending).
        case flow
    }

    /// Why an account goes where it goes.
    public enum Source: Hashable, Sendable {
        /// Set on this account (in the profile's `matches` or `ledger` section).
        case explicit
        /// Set on a parent account.
        case inherited(from: String)
        /// Matched by name to an account of the library.
        case matched
        /// A new account the import creates.
        case new
        /// Returns or not by the account's name.
        case byName
    }

    /// The full name, e.g. `Assets:Broker:Directa`.
    public var name: String
    public var id: String { name }
    /// The last part of the name, e.g. `Directa`.
    public var shortName: String { name.split(separator: ":").last.map(String.init) ?? name }
    /// 0 for a top-level account.
    public var depth: Int { name.split(separator: ":").count - 1 }
    public var role: Role
    public var mapping: Mapping
    public var source: Source
    /// Whether this account is the topmost of the ones going to its library
    /// account, where changing the mapping makes most sense.
    public var isGroupHead: Bool
    /// Postings to the account itself (not its subaccounts).
    public var postings: Int
    /// The account's own balance at the end of the journal.
    public var balance: [LedgerAmount]

    public init(name: String, role: Role, mapping: Mapping, source: Source, isGroupHead: Bool, postings: Int,
                balance: [LedgerAmount]) {
        self.name = name
        self.role = role
        self.mapping = mapping
        self.source = source
        self.isGroupHead = isGroupHead
        self.postings = postings
        self.balance = balance
    }
}

/// A commodity in the Commodities step: a currency, an instrument, or left out.
public struct LedgerCommodityRow: Hashable, Sendable, Identifiable {
    public enum Mapping: Hashable, Sendable {
        /// Cash in this currency.
        case currency(CurrencyCode)
        case instrument(InstrumentID)
        case ignored
    }

    public enum Source: Hashable, Sendable {
        /// Set in the profile.
        case explicit
        /// An ISO code or a currency symbol; amounts without a commodity are
        /// the library's base currency.
        case currency
        /// Matched to an instrument of the library by ticker, ID, symbol or name.
        case matched
        /// A new instrument the import creates.
        case new
    }

    /// The commodity as written, without quotes; empty for amounts without one.
    public var symbol: String
    public var id: String { symbol }
    public var mapping: Mapping
    public var source: Source
    /// Postings in net-worth accounts.
    public var postings: Int
    /// `P` directives for it.
    public var prices: Int

    public init(symbol: String, mapping: Mapping, source: Source, postings: Int, prices: Int) {
        self.symbol = symbol
        self.mapping = mapping
        self.source = source
        self.postings = postings
        self.prices = prices
    }
}

/// Resolves the mapping of a journal against a library: each ledger
/// account's role and target, the library accounts it proposes, each
/// commodity's currency or instrument, and the instruments it proposes.
struct LedgerMapper {
    let journal: LedgerJournal
    let library: Library
    let settings: LedgerImportSettings
    let matches: ImportMatches

    /// Every account posted to or declared, with its parents.
    private(set) var accounts: [String] = []
    private(set) var children: [String: [String]] = [:]
    private(set) var postings: [String: Int] = [:]
    private(set) var balances: [String: [String: Decimal]] = [:]
    private(set) var roles: [String: LedgerAccountRow.Role] = [:]
    /// Net-worth accounts: their library account (`nil` when ignored), and why.
    private(set) var targets: [String: (account: AccountID?, source: LedgerAccountRow.Source)] = [:]
    /// Other accounts: whether they're returns, and why.
    private(set) var returns: [String: (isReturns: Bool, source: LedgerAccountRow.Source)] = [:]
    /// Group heads: the topmost account of each set going to one library account.
    private(set) var heads: Set<String> = []
    /// New library accounts, by ID.
    private(set) var newAccounts: [AccountID: Account] = [:]
    /// The ledger accounts each new account stands for.
    private(set) var newAccountNames: [AccountID: [String]] = [:]
    /// How each head was matched to an existing account.
    private(set) var matched: [String: NameMatch.Method] = [:]

    /// Commodities posted in net-worth accounts, with their mapping.
    private(set) var commodities: [String: (mapping: LedgerCommodityRow.Mapping, source: LedgerCommodityRow.Source)] = [:]
    private(set) var commodityPostings: [String: Int] = [:]
    private(set) var newInstruments: [InstrumentID: Instrument] = [:]
    private(set) var newInstrumentNames: [InstrumentID: [String]] = [:]

    private let foldedCommodities: Set<String>
    private let matchKeys: [String: String]
    private let ignoreKeys: Set<String>
    private let returnsKeys: Set<String>
    private let flowsKeys: Set<String>

    init(journal: LedgerJournal, library: Library, settings: LedgerImportSettings, matches: ImportMatches) {
        self.journal = journal
        self.library = library
        self.settings = settings
        self.matches = matches
        foldedCommodities = Set(journal.commodities.flatMap { [TextTools.fold($0), TextTools.fold(Self.baseTicker($0))] })
        matchKeys = Dictionary(matches.accounts.keys.map { (Self.key($0), $0) }, uniquingKeysWith: { first, _ in first })
        ignoreKeys = Set(settings.ignore.map(Self.key))
        returnsKeys = Set(settings.returns.map(Self.key))
        flowsKeys = Set(settings.flows.map(Self.key))
        collectAccounts()
        classify()
        mapCommodities()
        mapAccounts()
    }

    /// How account names are compared: ignoring case, accents and spaces around colons.
    static func key(_ name: String) -> String {
        name.split(separator: ":").map { TextTools.fold(String($0)) }.joined(separator: ":")
    }

    /// `Assets:Broker:Directa` → `Assets:Broker`, `Assets` → `nil`.
    static func parent(of name: String) -> String? {
        guard let colon = name.lastIndex(of: ":") else { return nil }
        return String(name[..<colon])
    }

    /// The account and its parents, nearest first.
    static func lineage(of name: String) -> [String] {
        var result = [name]
        var current = name
        while let parent = parent(of: current) {
            result.append(parent)
            current = parent
        }
        return result
    }

    // MARK: - Accounts

    private mutating func collectAccounts() {
        var names = Set(journal.declaredAccounts)
        for transaction in journal.transactions {
            for posting in transaction.postings where posting.kind != .unbalancedVirtual {
                names.insert(posting.account)
                postings[posting.account, default: 0] += 1
                balances[posting.account, default: [:]][posting.amount.commodity, default: 0] += posting.amount.quantity
            }
        }
        for name in names {
            for ancestor in Self.lineage(of: name) { names.insert(ancestor) }
        }
        accounts = names.sorted()
        for name in accounts {
            if let parent = Self.parent(of: name) { children[parent, default: []].append(name) }
        }
    }

    /// Roles from declared types, then the roots.
    private mutating func classify() {
        let roots = settings.effectiveRoots.map(Self.key)
        let types = journal.accountTypes
        for name in accounts {
            if let type = Self.lineage(of: name).lazy.compactMap({ types[$0] }).first {
                switch type {
                case .asset, .cash: roles[name] = .asset
                case .liability: roles[name] = .liability
                case .revenue: roles[name] = .income
                case .expense: roles[name] = .expense
                case .equity, .conversion: roles[name] = .equity
                }
                continue
            }
            let key = Self.key(name)
            let top = String(key.split(separator: ":").first ?? "")
            if roots.contains(where: { key == $0 || key.hasPrefix($0 + ":") }) {
                roles[name] = LedgerKeywords.liabilityRoots.contains(top) ? .liability : .asset
            } else if LedgerKeywords.incomeRoots.contains(top) {
                roles[name] = .income
            } else if LedgerKeywords.expenseRoots.contains(top) {
                roles[name] = .expense
            } else if LedgerKeywords.equityRoots.contains(top) {
                roles[name] = .equity
            } else {
                roles[name] = .other
            }
        }
    }

    func role(of name: String) -> LedgerAccountRow.Role {
        roles[name] ?? .other
    }

    /// The nearest explicit setting on the account or a parent: a match or `ignore`.
    private func explicitTarget(of name: String) -> (target: AccountID?, at: String)? {
        for ancestor in Self.lineage(of: name) where role(of: ancestor).isNetWorth {
            let key = Self.key(ancestor)
            if ignoreKeys.contains(key) { return (nil, ancestor) }
            if let written = matchKeys[key], let id = matches.accounts[written] { return (id, ancestor) }
        }
        return nil
    }

    /// How many parts of the name belong to its net-worth root.
    private func rootDepth(of name: String) -> Int {
        var depth = 1
        for ancestor in Self.lineage(of: name).dropFirst() where role(of: ancestor).isNetWorth {
            depth = ancestor.split(separator: ":").count
        }
        let key = Self.key(name)
        for root in settings.effectiveRoots.map(Self.key) where key == root || key.hasPrefix(root + ":") {
            depth = max(depth, root.split(separator: ":").count)
        }
        return min(depth, name.split(separator: ":").count)
    }

    /// Whether a subaccount is a part of its parent's account: cash, a
    /// commodity's holdings, and so on, all the way down.
    private func isBucket(_ name: String) -> Bool {
        let last = TextTools.fold(String(name.split(separator: ":").last ?? ""))
        guard LedgerKeywords.buckets.contains(last) || foldedCommodities.contains(last) else { return false }
        return (children[name] ?? []).allSatisfy(isBucket)
    }

    /// The account that heads the library account a net-worth account goes to,
    /// when nothing is set: the first account down its name that has postings
    /// of its own, has no subaccounts, or whose subaccounts are all parts of
    /// it. `nil` for a grouping account such as `Assets:Bank`.
    func head(of name: String) -> String? {
        let parts = name.split(separator: ":").map(String.init)
        let start = rootDepth(of: name) + 1
        guard parts.count >= start else { return (postings[name] ?? 0) > 0 ? name : nil }
        for depth in start...parts.count {
            let node = parts.prefix(depth).joined(separator: ":")
            let subaccounts = children[node] ?? []
            if (postings[node] ?? 0) > 0 || subaccounts.isEmpty || subaccounts.allSatisfy(isBucket) { return node }
        }
        return nil
    }

    private mutating func mapAccounts() {
        var proposals: [String: AccountID] = [:]
        var usedIDs = Set(library.accounts.keys)
        let netWorth = accounts.filter { role(of: $0).isNetWorth }
        // Heads without an explicit setting, in name order, so IDs are stable.
        var headsToPropose: [String] = []
        for name in netWorth {
            if let explicit = explicitTarget(of: name) {
                targets[name] = (explicit.target, explicit.at == name ? .explicit : .inherited(from: explicit.at))
                if explicit.at == name { heads.insert(name) }
            } else if let head = head(of: name), !headsToPropose.contains(head) {
                headsToPropose.append(head)
            }
        }
        for head in headsToPropose.sorted() {
            if let (id, method) = existingAccount(for: head) {
                proposals[head] = id
                matched[head] = method
            } else {
                let name = Self.displayName(of: head)
                let id = AccountID.make(from: name, existing: usedIDs)
                usedIDs.insert(id)
                proposals[head] = id
            }
            heads.insert(head)
        }
        for name in netWorth where targets[name] == nil {
            guard let head = head(of: name), let id = proposals[head] else { continue }
            targets[name] = (id, matched[head] != nil ? .matched : .new)
        }
        for (name, target) in targets.sorted(by: { $0.key < $1.key }) {
            guard let id = target.account, library.accounts[id] == nil else { continue }
            newAccountNames[id, default: []].append(name)
        }
        for (id, names) in newAccountNames {
            let heads = names.filter { self.heads.contains($0) }
            newAccountNames[id] = heads.isEmpty ? [names[0]] : heads
            newAccounts[id] = proposedAccount(id: id, ledgerAccounts: names)
        }
        for name in accounts where !role(of: name).isNetWorth {
            returns[name] = isReturns(name)
        }
    }

    /// An existing library account for a head, by name: the whole name, the
    /// last two parts, or the last part (also inside a longer name, when it
    /// isn't a generic word and only one account has it).
    private func existingAccount(for head: String) -> (AccountID, NameMatch.Method)? {
        let parts = head.split(separator: ":").map(String.init)
        let depth = rootDepth(of: head)
        let own = Array(parts.dropFirst(depth))
        var candidates: [String] = []
        if own.count > 1 { candidates.append(own.joined(separator: " ")) }
        if own.count > 2 { candidates.append(own.suffix(2).joined(separator: " ")) }
        if let last = own.last { candidates.append(last) }
        candidates.append(Self.displayName(of: head))
        let accounts = library.sortedAccounts
        for candidate in candidates {
            let folded = TextTools.fold(Self.spaced(candidate)), slug = Slug.make(from: candidate)
            if let account = accounts.first(where: { TextTools.fold($0.name) == folded })
                ?? accounts.first(where: { $0.id.rawValue == slug }) {
                return (account.id, .existing)
            }
        }
        if let last = own.last {
            let words = TextTools.words(Self.spaced(last))
            if !words.isEmpty, !words.allSatisfy({ LedgerKeywords.generic.contains($0) || $0.count < 3 }) {
                let found = accounts.filter { TextTools.contains(TextTools.words($0.name), anyOf: [words.joined(separator: " ")]) }
                if found.count == 1 { return (found[0].id, .existing) }
            }
        }
        return nil
    }

    /// `CreditCard` → `Credit Card`, `conto_corrente` → `conto corrente`.
    static func spaced(_ part: String) -> String {
        var result = ""
        var previous: Character?
        for character in part {
            if character == "_" || character == "-" {
                result.append(" ")
            } else {
                if let previous, previous.isLowercase, character.isUppercase { result.append(" ") }
                result.append(character)
            }
            previous = character
        }
        return result.split(separator: " ").joined(separator: " ")
    }

    /// A new account's name from its ledger account: the last part, with the
    /// one before it when the last part is generic (`Crypto Wallet`).
    static func displayName(of name: String) -> String {
        let parts = name.split(separator: ":").map { spaced(String($0)) }
        guard let last = parts.last else { return name }
        var result = last
        let generic = TextTools.words(last).allSatisfy { LedgerKeywords.generic.contains($0) }
        if generic, parts.count > 2 { result = parts[parts.count - 2] + " " + last }
        return result.prefix(1).uppercased() + result.dropFirst()
    }

    /// A new library account for ledger accounts: its kind from the role,
    /// the instruments it holds and its name; its currency the most used;
    /// opened on its first posting.
    private func proposedAccount(id: AccountID, ledgerAccounts: [String]) -> Account {
        let own = Set(ledgerAccounts)
        var currencies: [CurrencyCode: Int] = [:]
        var instrumentKinds: [InstrumentKind] = []
        var first: CalendarDate?
        for transaction in journal.transactions {
            for posting in transaction.postings where own.contains(posting.account) && posting.kind != .unbalancedVirtual {
                first = first ?? transaction.date
                switch commodities[posting.amount.commodity]?.mapping {
                case .currency(let code)?: currencies[code, default: 0] += 1
                case .instrument(let instrument)?:
                    if let kind = library.instruments[instrument]?.kind ?? newInstruments[instrument]?.kind {
                        instrumentKinds.append(kind)
                    }
                    if let cost = posting.cost, let code = currency(of: cost.commodity) {
                        currencies[code, default: 0] += 1
                    }
                default: break
                }
            }
        }
        let head = newAccountNames[id].flatMap { names in names.first { heads.contains($0) } ?? names.first }
            ?? ledgerAccounts[0]
        let words = TextTools.words(Self.spaced(head.split(separator: ":").dropFirst().joined(separator: " ")))
        let byName = Keywords.accountKinds.filter { TextTools.contains(words, anyOf: $0.1) }.map(\.0)
        let kind: AccountKind
        if ledgerAccounts.contains(where: { role(of: $0) == .liability }) {
            kind = byName.first { $0.isLiability } ?? .loan
        } else if !instrumentKinds.isEmpty {
            if instrumentKinds.allSatisfy({ $0 == .crypto }) {
                kind = .crypto
            } else if instrumentKinds.allSatisfy({ $0 == .metal }) {
                kind = .metals
            } else {
                kind = byName.first { $0 == .pensionFund || $0.defaultValuationMode == .holdings } ?? .brokerage
            }
        } else {
            kind = byName.first { !$0.isLiability } ?? .cash
        }
        let currency = currencies.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key ?? library.settings.baseCurrency
        return Account(id: id, name: Self.displayName(of: head), kind: kind, currency: currency,
                       opened: first ?? journal.firstDate ?? CalendarDate(daysSinceEpoch: 0))
    }

    /// Whether an income, expense or other account's postings are returns:
    /// the nearest setting, else its name.
    private func isReturns(_ name: String) -> (isReturns: Bool, source: LedgerAccountRow.Source) {
        for ancestor in Self.lineage(of: name) {
            let key = Self.key(ancestor)
            if returnsKeys.contains(key) { return (true, ancestor == name ? .explicit : .inherited(from: ancestor)) }
            if flowsKeys.contains(key) { return (false, ancestor == name ? .explicit : .inherited(from: ancestor)) }
        }
        let words = TextTools.words(Self.spaced(name.split(separator: ":").dropFirst().joined(separator: " ")))
        switch role(of: name) {
        case .income: return (TextTools.contains(words, anyOf: LedgerKeywords.incomeReturns), .byName)
        case .expense: return (TextTools.contains(words, anyOf: LedgerKeywords.expenseReturns), .byName)
        default: return (false, .byName)
        }
    }

    /// The library account a net-worth account goes to; `nil` when ignored.
    func libraryAccount(of name: String) -> AccountID? {
        targets[name]?.account
    }

    /// Whether postings against a non-net-worth account are returns.
    func isReturnsAccount(_ name: String) -> Bool {
        returns[name]?.isReturns ?? false
    }

    /// The accounts, as rows for the Accounts step.
    var rows: [LedgerAccountRow] {
        accounts.map { name in
            let role = role(of: name)
            let mapping: LedgerAccountRow.Mapping
            let source: LedgerAccountRow.Source
            if role.isNetWorth {
                if let target = targets[name] {
                    mapping = target.account.map(LedgerAccountRow.Mapping.account) ?? .ignored
                    source = target.source
                } else {
                    mapping = .split
                    source = .byName
                }
            } else {
                let value = returns[name] ?? (false, .byName)
                mapping = value.isReturns ? .returns : .flow
                source = value.source
            }
            let balance = (balances[name] ?? [:]).filter { $0.value != 0 }.sorted { $0.key < $1.key }
                .map { LedgerAmount($0.value, $0.key) }
            return LedgerAccountRow(name: name, role: role, mapping: mapping, source: source,
                                    isGroupHead: heads.contains(name), postings: postings[name] ?? 0,
                                    balance: balance)
        }
    }

    // MARK: - Commodities

    /// The currency a commodity stands for: an ISO code or a symbol, the
    /// base currency for none; `nil` for anything else.
    func currency(of symbol: String) -> CurrencyCode? {
        if let mapping = commodities[symbol]?.mapping {
            if case .currency(let code) = mapping { return code }
            return nil
        }
        return Self.currency(of: symbol, base: library.settings.baseCurrency)
    }

    static func currency(of symbol: String, base: CurrencyCode) -> CurrencyCode? {
        if symbol.isEmpty { return base }
        if let code = LedgerKeywords.currencySymbols[symbol] { return code }
        let upper = symbol.uppercased()
        return LedgerKeywords.currencyCodes.contains(upper) && symbol == upper ? CurrencyCode(upper) : nil
    }

    private mutating func mapCommodities() {
        var symbols: [String] = []
        for transaction in journal.transactions {
            for posting in transaction.postings where posting.kind != .unbalancedVirtual {
                guard role(of: posting.account).isNetWorth, explicitTarget(of: posting.account).map({ $0.target != nil })
                    ?? true else { continue }
                if commodityPostings[posting.amount.commodity] == nil { symbols.append(posting.amount.commodity) }
                commodityPostings[posting.amount.commodity, default: 0] += 1
            }
        }
        let ignored = Set(settings.ignoreCommodities)
        var usedIDs = Set(library.instruments.keys)
        for symbol in symbols.sorted() {
            if ignored.contains(symbol) {
                commodities[symbol] = (.ignored, .explicit)
            } else if let id = NameMatcher.lookup(symbol, in: matches.instruments) {
                commodities[symbol] = (.instrument(id), .explicit)
                if library.instruments[id] == nil, newInstruments[id] == nil {
                    newInstruments[id] = proposedInstrument(id: id, symbol: symbol)
                    newInstrumentNames[id, default: []].append(symbol)
                }
            } else if let code = Self.currency(of: symbol, base: library.settings.baseCurrency) {
                commodities[symbol] = (.currency(code), .currency)
            } else if let id = existingInstrument(for: symbol) {
                commodities[symbol] = (.instrument(id), .matched)
            } else {
                let base = Self.baseTicker(symbol)
                let preferred = Slug.make(from: base)
                let id = usedIDs.contains(InstrumentID(preferred))
                    ? InstrumentID.make(from: symbol, existing: usedIDs) : InstrumentID(preferred)
                usedIDs.insert(id)
                commodities[symbol] = (.instrument(id), .new)
                newInstruments[id] = proposedInstrument(id: id, symbol: symbol)
                newInstrumentNames[id, default: []].append(symbol)
            }
        }
    }

    /// `VWCE.MI` → `VWCE`.
    static func baseTicker(_ symbol: String) -> String {
        guard let dot = symbol.lastIndex(of: "."), dot != symbol.startIndex else { return symbol }
        let suffix = symbol[symbol.index(after: dot)...]
        guard (1...3).contains(suffix.count), suffix.allSatisfy(\.isLetter) else { return symbol }
        return String(symbol[..<dot])
    }

    /// An existing instrument for a commodity: by ID, ticker, price-source
    /// symbol, ISIN or name, with or without an exchange suffix; metals by
    /// their gold-api symbol.
    private func existingInstrument(for symbol: String) -> InstrumentID? {
        let instruments = library.instruments.values.sorted { $0.id < $1.id }
        let base = Self.baseTicker(symbol)
        for candidate in [symbol, base] {
            let folded = TextTools.fold(candidate), slug = Slug.make(from: candidate)
            if let instrument = instruments.first(where: { $0.id.rawValue == slug })
                ?? instruments.first(where: {
                    $0.ticker.map(TextTools.fold) == folded || $0.priceSource.map { TextTools.fold($0.symbol) } == folded
                        || $0.isin.map(TextTools.fold) == folded || TextTools.fold($0.name) == folded
                }) {
                return instrument.id
            }
        }
        if let metal = LedgerKeywords.metals[symbol.uppercased()] {
            return instruments.first { $0.kind == .metal && $0.priceSource?.symbol.uppercased() == metal.symbol }?.id
        }
        return nil
    }

    /// A new instrument for a commodity: crypto tickers priced by CoinGecko,
    /// tickers with an exchange suffix by Yahoo, metals by gold-api; its
    /// currency the one its prices and costs are in.
    private func proposedInstrument(id: InstrumentID, symbol: String) -> Instrument {
        var currencies: [CurrencyCode: Int] = [:]
        for price in journal.prices where price.commodity == symbol {
            if let code = Self.currency(of: price.price.commodity, base: library.settings.baseCurrency) {
                currencies[code, default: 0] += 1
            }
        }
        for transaction in journal.transactions {
            for posting in transaction.postings where posting.amount.commodity == symbol {
                if let cost = posting.cost, let code = Self.currency(of: cost.commodity, base: library.settings.baseCurrency) {
                    currencies[code, default: 0] += 1
                }
            }
        }
        let currency = currencies.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key ?? library.settings.baseCurrency
        let upper = symbol.uppercased()
        let base = Self.baseTicker(symbol)
        let isSuffixed = base != symbol
        if LedgerKeywords.cryptoTickers.contains(upper) {
            return Instrument(id: id, name: symbol, kind: .crypto, currency: currency, unit: InstrumentUnit(upper),
                              assetClasses: .single(.crypto), ticker: upper,
                              priceSource: PriceSource(provider: .coingecko, symbol: upper))
        }
        if let metal = LedgerKeywords.metals[upper] {
            return Instrument(id: id, name: symbol, kind: .metal, currency: currency,
                              unit: upper.hasPrefix("X") ? .troyOunce : .gram,
                              assetClasses: .single(metal.isGold ? .gold : .other),
                              priceSource: PriceSource(provider: .goldAPI, symbol: metal.symbol))
        }
        let compact = symbol.filter { !$0.isWhitespace }
        if compact.count == 12, compact.prefix(2).allSatisfy({ $0.isUppercase && $0.isLetter }),
           compact.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) {
            return Instrument(id: id, name: symbol, kind: .other, currency: currency, unit: .share,
                              assetClasses: .single(.other), isin: compact)
        }
        let isTicker = !base.isEmpty && base.count <= 6
            && base.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) }
        if isSuffixed || (isTicker && LedgerKeywords.etfTickers.contains(base)) {
            let kind: InstrumentKind = LedgerKeywords.etfTickers.contains(base.uppercased()) ? .etf : .stock
            return Instrument(id: id, name: symbol, kind: kind, currency: currency, unit: .share,
                              assetClasses: .single(.equity), ticker: base,
                              priceSource: PriceSource(provider: .yahoo, symbol: symbol))
        }
        let words = TextTools.words(symbol)
        let kind = Keywords.instrumentKinds.first { TextTools.contains(words, anyOf: $0.1) }?.0 ?? .other
        let assetClass: AssetClass = switch kind {
        case .etf, .stock, .fund: .equity
        case .bond: .bonds
        case .crypto: .crypto
        default: .other
        }
        return Instrument(id: id, name: symbol, kind: kind, currency: currency, unit: .share,
                          assetClasses: .single(assetClass), ticker: isTicker ? symbol : nil)
    }

    /// The commodities, as rows for the Commodities step.
    var commodityRows: [LedgerCommodityRow] {
        let priceCounts = Dictionary(journal.prices.map { ($0.commodity, 1) }, uniquingKeysWith: +)
        return commodities.keys.sorted().map { symbol in
            let entry = commodities[symbol]!
            return LedgerCommodityRow(symbol: symbol, mapping: entry.mapping, source: entry.source,
                                      postings: commodityPostings[symbol] ?? 0, prices: priceCounts[symbol] ?? 0)
        }
    }

    /// The instrument a commodity stands for, if it's mapped to one.
    func instrument(of symbol: String) -> InstrumentID? {
        if case .instrument(let id)? = commodities[symbol]?.mapping { return id }
        return nil
    }

    /// An instrument for a commodity only seen in prices: an existing one, or nothing.
    func existingInstrument(forPriced symbol: String) -> InstrumentID? {
        if let mapped = commodities[symbol] {
            if case .instrument(let id) = mapped.mapping { return id }
            return nil
        }
        if let id = NameMatcher.lookup(symbol, in: matches.instruments), library.instruments[id] != nil { return id }
        return existingInstrument(for: symbol)
    }
}
