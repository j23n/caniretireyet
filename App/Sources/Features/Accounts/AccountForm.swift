import Foundation
import Model
import Tracker

// The fields of an account being added or edited, and the defaults that
// follow its kind and your tax residence (UI.md, "Add account"). Plain
// values, so they can be checked on Linux.

/// Tax wrappers offered for accounts, and the one pre-selected for a kind
/// and residence (e.g. a pension fund in Italy is `it.pensionFund`).
enum AccountWrapperDefaults {
    /// Every wrapper offered in the picker: Italy's, then the generic ones.
    static let choices: [WrapperID] = ["it.ordinary", "it.pensionFund", "it.tfr", .taxable, .taxDeferred, .taxFree]

    /// The wrapper for a new account of `kind` when you live in `residence`.
    /// Property, vehicles and debts have none.
    static func wrapper(for kind: AccountKind, residence: CountryCode?) -> WrapperID? {
        let italy = residence == .it
        switch kind {
        case .property, .vehicle, .loan, .mortgage, .creditCard:
            return nil
        case .pensionFund:
            return italy ? "it.pensionFund" : .taxDeferred
        case .tfr:
            return italy ? "it.tfr" : .taxDeferred
        default:
            return italy ? "it.ordinary" : .taxable
        }
    }

    /// A readable name, e.g. "Pension fund (Italy)".
    static func name(of wrapper: WrapperID) -> String {
        switch wrapper.rawValue {
        case "it.ordinary": "Ordinary account (Italy)"
        case "it.pensionFund": "Pension fund (Italy)"
        case "it.tfr": "TFR (Italy)"
        case WrapperID.taxable.rawValue: "Taxable"
        case WrapperID.taxDeferred.rawValue: "Tax-deferred"
        case WrapperID.taxFree.rawValue: "Tax-free"
        default: wrapper.rawValue
        }
    }

    /// Whether a new account of `kind` counts in plans by default: a home,
    /// vehicles and the mortgage on the home usually don't.
    static func includedInPlan(_ kind: AccountKind) -> Bool {
        !(kind == .property || kind == .vehicle || kind == .mortgage)
    }
}

/// An asset mix as percentages typed by hand, e.g. equity 60, bonds 40.
struct AccountsAssetMixForm: Hashable, Sendable {
    /// The classes offered, in stacking order.
    static let classes: [AssetClass] = BreakdownKey.assetClassOrder

    /// The typed percentage per class; empty for none.
    var percents: [AssetClass: String]

    init(_ mix: AssetMix? = nil, locale: Locale = .current) {
        var percents: [AssetClass: String] = [:]
        for (assetClass, share) in mix?.shares ?? [:] where share != 0 {
            percents[assetClass] = AmountInput.text(for: share * 100, maxDigits: 2, locale: locale)
        }
        self.percents = percents
    }

    /// The classes to show: the standard ones, plus any others in the mix.
    var shownClasses: [AssetClass] {
        Self.classes + percents.keys.filter { !Self.classes.contains($0) }.sorted()
    }

    /// The typed percentages as numbers; `nil` if one can't be read.
    func values(locale: Locale = .current) -> [AssetClass: Decimal]? {
        var values: [AssetClass: Decimal] = [:]
        for (assetClass, text) in percents {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            guard let value = AmountInput.decimal(from: trimmed, locale: locale), value >= 0 else { return nil }
            if value != 0 { values[assetClass] = value }
        }
        return values
    }

    /// The total of the typed percentages; `nil` if one can't be read.
    func totalPercent(locale: Locale = .current) -> Decimal? {
        values(locale: locale).map { $0.values.reduce(0, +) }
    }

    /// Whether nothing is typed.
    var isEmpty: Bool {
        percents.values.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// The mix as shares that sum to 1, or `nil` when nothing is typed or it
    /// doesn't add up to 100%.
    func mix(locale: Locale = .current) -> AssetMix? {
        guard let values = values(locale: locale), !values.isEmpty,
              values.values.reduce(0, +) == 100
        else { return nil }
        return AssetMix(values.mapValues { $0 / 100 })
    }

    /// What's wrong, if anything: a percentage that can't be read, or a
    /// total other than 100%. Empty is fine when `required` is false.
    func problem(required: Bool, locale: Locale = .current) -> String? {
        if isEmpty { return required ? "Enter the asset mix, e.g. 100% equity." : nil }
        guard let total = totalPercent(locale: locale) else { return "A percentage can't be read." }
        guard total == 100 else {
            return "The asset mix adds up to \(AmountFormat.number(total, maxDigits: 2, locale: locale))%, not 100%."
        }
        return nil
    }
}

/// An account's fields while it's added or edited.
struct AccountForm: Hashable, Sendable {
    var kind: AccountKind
    var name: String
    var institution: String
    var currency: CurrencyCode
    /// The institution's country; `nil` for none.
    var country: CountryCode?
    var opened: CalendarDate
    var wrapper: WrapperID?
    /// Whether the wrapper was picked by hand; otherwise it follows the kind.
    var isWrapperChosen: Bool
    var includedInNetWorth: Bool
    var includedInPlan: Bool
    /// Whether "include in plans" was set by hand; otherwise it follows the kind.
    var isPlanInclusionChosen: Bool
    /// The mix of a balance account; empty for the kind's default.
    var assetMix: AccountsAssetMixForm
    var notes: String
    /// How a new brokerage, crypto or metals account records what it
    /// holds: its trade history (the default) or monthly snapshots of its
    /// positions (UI.md, "Add account"). See ``offersTracking``.
    var tracking: ValuationMode = .trades
    /// Your tax residence, which the default wrapper depends on.
    let residence: CountryCode?
    /// The account being edited, whose other fields are kept.
    private(set) var original: Account?

    /// A new account: today, in the base currency, with the defaults for a
    /// current account.
    init(residence: CountryCode?, currency: CurrencyCode, today: CalendarDate) {
        kind = .cash
        name = ""
        institution = ""
        self.currency = currency
        country = residence
        opened = today
        wrapper = AccountWrapperDefaults.wrapper(for: .cash, residence: residence)
        isWrapperChosen = false
        includedInNetWorth = true
        includedInPlan = true
        isPlanInclusionChosen = false
        assetMix = AccountsAssetMixForm()
        notes = ""
        self.residence = residence
        original = nil
    }

    /// The fields of an existing account.
    init(editing account: Account, residence: CountryCode? = nil, locale: Locale = .current) {
        kind = account.kind
        name = account.name
        institution = account.institution ?? ""
        currency = account.currency
        country = account.country
        opened = account.opened
        wrapper = account.wrapper
        isWrapperChosen = true
        includedInNetWorth = account.includedInNetWorth
        includedInPlan = account.includedInPlan
        isPlanInclusionChosen = true
        assetMix = AccountsAssetMixForm(account.assetClasses, locale: locale)
        notes = account.notes ?? ""
        self.residence = residence
        original = account
    }

    var isNew: Bool { original == nil }

    /// Changes the kind, and with it the defaults not chosen by hand.
    mutating func setKind(_ kind: AccountKind) {
        self.kind = kind
        if !isWrapperChosen { wrapper = AccountWrapperDefaults.wrapper(for: kind, residence: residence) }
        if !isPlanInclusionChosen { includedInPlan = AccountWrapperDefaults.includedInPlan(kind) }
    }

    // For pickers and toggles: setting these is choosing by hand.

    /// The kind; setting it updates the defaults (see ``setKind(_:)``).
    var chosenKind: AccountKind {
        get { kind }
        set { setKind(newValue) }
    }

    /// The wrapper; setting it stops it following the kind.
    var chosenWrapper: WrapperID? {
        get { wrapper }
        set {
            wrapper = newValue
            isWrapperChosen = true
        }
    }

    /// Whether plans include it; setting it stops it following the kind.
    var chosenPlanInclusion: Bool {
        get { includedInPlan }
        set {
            includedInPlan = newValue
            isPlanInclusionChosen = true
        }
    }

    /// The opening day as a `Date` (noon, this device's time zone), for a date picker.
    var openedDate: Date {
        get { opened.dateValue }
        set { opened = CalendarDate(newValue, in: .current) }
    }

    /// Whether the kind can record its trades: brokerage, crypto and metals.
    static func offersTrades(_ kind: AccountKind) -> Bool {
        kind == .brokerage || kind == .crypto || kind == .metals
    }

    /// Whether the form offers "Track: trade history / monthly snapshots":
    /// a new account of a kind that holds positions.
    var offersTracking: Bool {
        isNew && Self.offersTrades(kind)
    }

    /// How the account records its values: as written for an edited
    /// account (else its kind's default); for a new one, ``tracking`` where
    /// it's offered, else the kind's default.
    var valuationMode: ValuationMode {
        if let original { return original.valuation ?? kind.defaultValuationMode }
        return offersTracking ? tracking : kind.defaultValuationMode
    }

    /// Whether the account is recorded as positions, from snapshots or from
    /// its trades (or else as a balance).
    var holdsPositions: Bool {
        valuationMode == .holdings || valuationMode == .trades
    }

    /// Whether the account records its trades.
    var recordsTrades: Bool {
        valuationMode == .trades
    }

    /// The one line under the tracking choice.
    static func trackingExplanation(_ mode: ValuationMode) -> String {
        mode == .trades
            ? "Record each buy, sell and dividend: holdings, average cost, gains and income follow from them."
            : "Type the quantities and cash at each check-in; no trades to keep."
    }

    /// Whether the asset mix applies: balance accounts that aren't debts.
    var takesAssetMix: Bool {
        !holdsPositions && !kind.isLiability
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What must be fixed before saving, in order.
    func problems(locale: Locale = .current) -> [String] {
        var problems: [String] = []
        if trimmedName.isEmpty { problems.append("Give the account a name.") }
        if !currency.isWellFormed { problems.append("Choose a currency.") }
        if takesAssetMix, let problem = assetMix.problem(required: false, locale: locale) { problems.append(problem) }
        if let closed = original?.closed, closed < opened {
            problems.append("It can't open after the day it closed.")
        }
        return problems
    }

    /// The account with these fields. An edited account keeps its ID and
    /// everything the form doesn't show (tags, successor, closing date,
    /// valuation mode, wrapper details); a new one gets `id`. A pension
    /// fund's joining date follows a moved opening date if it was the
    /// opening date (``Account/moveOpening(to:)``).
    func account(id: AccountID, locale: Locale = .current) -> Account {
        var account = original ?? Account(id: id, name: "", kind: kind, currency: currency, opened: opened)
        if original == nil {
            // Written only when it isn't the kind's default (brokerage defaults to holdings).
            account.valuation = valuationMode == kind.defaultValuationMode ? nil : valuationMode
        }
        account.name = trimmedName
        account.kind = kind
        account.currency = currency
        account.moveOpening(to: opened)
        let trimmedInstitution = institution.trimmingCharacters(in: .whitespacesAndNewlines)
        account.institution = trimmedInstitution.isEmpty ? nil : trimmedInstitution
        account.country = country
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        account.notes = trimmedNotes.isEmpty ? nil : trimmedNotes

        if let wrapper {
            var tax = account.tax ?? AccountTax(wrapper: wrapper)
            if tax.wrapper != wrapper {
                tax = AccountTax(wrapper: wrapper)
            }
            if wrapper == "it.pensionFund", tax.details["joined"] == nil {
                tax.details["joined"] = .string(opened.description)
            }
            account.tax = tax
        } else {
            account.tax = nil
        }

        if let original, original.includedInNetWorth == includedInNetWorth, original.includedInPlan == includedInPlan {
            account.includeIn = original.includeIn
        } else if includedInNetWorth && includedInPlan {
            account.includeIn = nil
        } else {
            account.includeIn = IncludeIn(netWorth: includedInNetWorth ? nil : false,
                                          plan: includedInPlan ? nil : false)
        }

        if !takesAssetMix {
            account.assetClasses = original?.assetClasses
        } else if let original, assetMix == AccountsAssetMixForm(original.assetClasses, locale: locale) {
            account.assetClasses = original.assetClasses
        } else {
            account.assetClasses = assetMix.mix(locale: locale)
        }
        return account
    }
}

/// The first valuation of a new account: an opening balance, or cash and
/// positions (UI.md, "Add account", step 3).
struct AccountOpeningForm: Hashable, Sendable {
    /// One position typed in.
    struct PositionField: Hashable, Sendable, Identifiable {
        var id: Int
        var instrument: InstrumentID?
        var quantity: String = ""
        /// What was paid for it in total (its cost basis), optional.
        var cost: String = ""
    }

    var balance = ""
    var cash = ""
    var positions: [PositionField] = []
    private var nextID = 0

    init() {}

    /// Adds an empty position, optionally for `instrument`.
    mutating func addPosition(_ instrument: InstrumentID? = nil) {
        positions.append(PositionField(id: nextID, instrument: instrument))
        nextID += 1
    }

    mutating func removePosition(id: Int) {
        positions.removeAll { $0.id == id }
    }

    /// The position with `id`, for bindings that stay valid while rows are
    /// removed (an empty position once it's gone).
    subscript(position id: Int) -> PositionField {
        get { positions.first { $0.id == id } ?? PositionField(id: id) }
        set {
            guard let index = positions.firstIndex(where: { $0.id == id }) else { return }
            positions[index] = newValue
        }
    }

    /// Whether anything was typed.
    var isEmpty: Bool {
        balance.trimmingCharacters(in: .whitespaces).isEmpty && cash.trimmingCharacters(in: .whitespaces).isEmpty
            && positions.allSatisfy { $0.quantity.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// The opening balance's footer, which names a past opening date so the
    /// balance typed is the one on that day: "What it held on 1 Jan 2023,
    /// the day it opened. It becomes the account's first value; add later
    /// values with Update Value or a check-in."
    static func balanceFooter(opened: CalendarDate, today: CalendarDate, isLiability: Bool,
                              locale: Locale = .current) -> String {
        let isPast = opened < today
        let day = isPast ? "on \(AmountFormat.mediumDate(opened, locale: locale)), the day it opened" : "on the day it opens"
        if isLiability {
            return "What you \(isPast ? "owed" : "owe") \(day). It's recorded as a negative amount. "
                + "If the account is in credit, type + first, e.g. +20."
        }
        return "What it \(isPast ? "held" : "holds") \(day). It becomes the account's first value"
            + (isPast ? "; add later values with Update Value or a check-in." : ".")
    }

    /// The opening positions' footer: "What it held on 1 Jan 2023, the day
    /// it opened: choose an instrument, …".
    static func positionsFooter(opened: CalendarDate, today: CalendarDate, locale: Locale = .current) -> String {
        let isPast = opened < today
        let day = isPast ? "on \(AmountFormat.mediumDate(opened, locale: locale)), the day it opened" : "on the day it opens"
        return "What it \(isPast ? "held" : "holds") \(day): choose an instrument, or create one (an ETF, a coin, "
            + "gold). What you paid becomes the purchase cost."
    }

    /// What can't be read.
    func problems(holdsPositions: Bool, locale: Locale = .current) -> [String] {
        var problems: [String] = []
        func check(_ text: String, _ what: String) {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, AmountInput.decimal(from: trimmed, locale: locale) == nil {
                problems.append("The \(what) can't be read.")
            }
        }
        if holdsPositions {
            check(cash, "cash")
            for position in positions {
                check(position.quantity, "quantity")
                check(position.cost, "amount paid")
                if position.instrument == nil, !position.quantity.trimmingCharacters(in: .whitespaces).isEmpty {
                    problems.append("Choose the instrument of each position.")
                }
            }
            let instruments = positions.compactMap(\.instrument)
            if Set(instruments).count != instruments.count {
                problems.append("Each instrument can be listed once.")
            }
        } else {
            check(balance, "balance")
        }
        return problems
    }

    /// The first valuation of `account`, on the day it opened, or `nil` if
    /// nothing was typed. A debt's amount is what's owed and is recorded as
    /// negative, unless typed with a leading "+" (in credit). The flow is
    /// what the check-in would suggest for a first
    /// valuation (the whole amount, at the day's prices, for most kinds;
    /// unknown for pension funds and property).
    ///
    /// For an account that records trades, the positions become opening
    /// trades (``openingTrades(for:locale:)``), and the valuation records
    /// only the cash; `nil` without cash.
    func valuation(for account: Account, in library: Library, locale: Locale = .current) -> Valuation? {
        guard !isEmpty else { return nil }
        var valuation = Valuation(account: account.id, date: account.opened, source: .manual)
        var paid: [InstrumentID: Decimal] = [:]
        if account.recordsTrades {
            guard let cash = AmountInput.decimal(from: cash, locale: locale) else { return nil }
            valuation.cash = cash
            var snapshot = library
            snapshot.accounts[account.id] = account
            for trade in openingTrades(for: account, locale: locale) { snapshot.upsert(trade) }
            // The openings at their market value, and the cash typed.
            valuation.flow = Valuator(library: snapshot).defaultFlow(for: valuation, previous: nil)
            return valuation
        }
        if account.valuationMode == .holdings {
            valuation.cash = AmountInput.decimal(from: cash, locale: locale)
            for position in positions {
                guard let instrument = position.instrument,
                      let quantity = AmountInput.decimal(from: position.quantity, locale: locale), quantity != 0
                else { continue }
                let cost = AmountInput.decimal(from: position.cost, locale: locale)
                valuation.positions.append(Position(instrument: instrument, quantity: quantity, costBasis: cost))
                if let cost { paid[instrument] = cost }
            }
        } else {
            guard let amount = AmountInput.balance(from: balance, isLiability: account.kind.isLiability, locale: locale)
            else { return nil }
            valuation.balance = amount
        }
        var snapshot = library
        snapshot.accounts[account.id] = account
        valuation.flow = Valuator(library: snapshot).defaultFlow(for: valuation, previous: nil, paid: paid)
        return valuation
    }

    /// For a new account that records trades: an `opening` trade per
    /// position typed, on the day it opened, with what was paid as its
    /// purchase cost (unknown when empty). Empty for other accounts.
    func openingTrades(for account: Account, locale: Locale = .current) -> [Trade] {
        guard account.recordsTrades else { return [] }
        return positions.compactMap { position in
            guard let instrument = position.instrument,
                  let quantity = AmountInput.decimal(from: position.quantity, locale: locale), quantity > 0
            else { return nil }
            return Trade(account: account.id, date: account.opened, type: .opening, instrument: instrument,
                         quantity: quantity, cost: AmountInput.decimal(from: position.cost, locale: locale),
                         source: .manual)
        }
    }

    /// The opening positions' footer for an account that records trades.
    static func openingTradesFooter(opened: CalendarDate, today: CalendarDate, locale: Locale = .current) -> String {
        let isPast = opened < today
        let day = isPast ? "on \(AmountFormat.mediumDate(opened, locale: locale)), the day it opened" : "on the day it opens"
        return "What it \(isPast ? "held" : "holds") \(day), if anything: each position becomes an opening trade, "
            + "with what you paid as its purchase cost. Add later buys and sells as trades."
    }
}
