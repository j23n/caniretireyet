import Foundation
import Model
import Tracker

// The fields of an account being added or edited, and the defaults that
// follow its kind (UI.md, "Add account"). Plain values, so they can be
// checked on Linux.

/// The defaults that follow an account's kind.
enum AccountDefaults {
    /// The age from which plans can draw on a new account of `kind`: 65 for
    /// a pension fund, a starting point to change to the fund's rules; any
    /// age for the rest.
    static func availableFromAge(for kind: AccountKind) -> Int? {
        kind == .pensionFund ? 65 : nil
    }

    /// Whether a new account of `kind` counts in plans by default: a home,
    /// belongings and the mortgage on the home usually don't, nor does a tax
    /// pot, whose money is owed.
    static func includedInPlan(_ kind: AccountKind) -> Bool {
        kind.isIncludedByDefault && !(kind == .property || kind == .belongings || kind == .mortgage)
    }

    /// Whether a new account of `kind` counts in net worth by default:
    /// every kind but a tax pot.
    static func includedInNetWorth(_ kind: AccountKind) -> Bool {
        kind.isIncludedByDefault
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
    /// The age from which plans can draw on it; `nil` for any age.
    var availableFromAge: Int?
    /// Whether ``availableFromAge`` was set by hand; otherwise it follows the kind.
    var isAvailabilityChosen: Bool
    var includedInNetWorth: Bool
    /// Whether "include in net worth" was set by hand; otherwise it follows the kind.
    var isNetWorthInclusionChosen: Bool
    var includedInPlan: Bool
    /// Whether "include in plans" was set by hand; otherwise it follows the kind.
    var isPlanInclusionChosen: Bool
    /// The mix of a balance account; empty for the kind's default.
    var assetMix: AccountsAssetMixForm
    /// An estimated loss of value a year, in per cent as typed
    /// ("15"); empty for none (``Model/Account/depreciation``).
    var depreciation: String
    /// The share of what plans take from it that goes to tax, in per cent
    /// as typed ("20"); empty for an account taxed only on its gains
    /// (``Model/Account/withdrawalTaxRate``).
    var withdrawalTaxRate: String
    /// Where its values come from: imported files, or typed by you too
    /// (``Model/Account/values``). Only kinds that take typed values offer
    /// the choice (``offersTypedValues``).
    var values: ValueEntry
    var notes: String
    /// The account being edited, whose other fields are kept.
    private(set) var original: Account?
    /// How many of the account's values are recorded as a single balance
    /// (e.g. imported history of a brokerage that otherwise holds
    /// positions). The asset mix applies to those.
    private(set) var balanceValueCount = 0
    /// Whether the edited account has values or trades, which are in its
    /// currency: the currency can't change then (``locksCurrency``).
    private(set) var hasHistory = false
    /// Whether the edited account has trades: an investment account that
    /// records them can't switch to typed values then.
    private(set) var hasTrades = false

    /// A new account: today, in the base currency, in the country you live
    /// in (`residence`), with the defaults for a current account.
    init(residence: CountryCode?, currency: CurrencyCode, today: CalendarDate) {
        kind = .cash
        name = ""
        institution = ""
        self.currency = currency
        country = residence
        opened = today
        availableFromAge = AccountDefaults.availableFromAge(for: .cash)
        isAvailabilityChosen = false
        includedInNetWorth = true
        isNetWorthInclusionChosen = false
        includedInPlan = true
        isPlanInclusionChosen = false
        assetMix = AccountsAssetMixForm()
        depreciation = ""
        withdrawalTaxRate = ""
        values = .imported
        notes = ""
        original = nil
    }

    /// The fields of an existing account; `hasHistory`: it has values or
    /// trades; `hasTrades`: it has trades.
    init(editing account: Account, balanceValueCount: Int = 0, hasHistory: Bool = false, hasTrades: Bool = false,
         locale: Locale = .current) {
        self.balanceValueCount = balanceValueCount
        self.hasHistory = hasHistory || hasTrades
        self.hasTrades = hasTrades
        kind = account.kind
        name = account.name
        institution = account.institution ?? ""
        currency = account.currency
        country = account.country
        opened = account.opened
        availableFromAge = account.availableFromAge
        isAvailabilityChosen = true
        includedInNetWorth = account.includedInNetWorth
        isNetWorthInclusionChosen = true
        includedInPlan = account.includedInPlan
        isPlanInclusionChosen = true
        assetMix = AccountsAssetMixForm(account.assetClasses, locale: locale)
        depreciation = account.depreciation.map { AmountInput.text(for: $0 * 100, locale: locale) } ?? ""
        withdrawalTaxRate = account.withdrawalTaxRate.map { AmountInput.text(for: $0 * 100, locale: locale) } ?? ""
        values = Self.shownValues(of: account)
        notes = account.notes ?? ""
        original = account
    }

    /// The *Values* choice an account shows: typed, or imported for
    /// anything else (a value a newer app wrote, too).
    private static func shownValues(of account: Account) -> ValueEntry {
        account.effectiveValues == .typed ? .typed : .imported
    }

    var isNew: Bool { original == nil }

    /// Whether the currency can't be changed: the account has values or
    /// trades, whose amounts are in its currency and would otherwise be
    /// read in the new one ($10,000 becoming €10,000).
    var locksCurrency: Bool { original != nil && hasHistory }

    /// Changes the kind, and with it the defaults not chosen by hand.
    mutating func setKind(_ kind: AccountKind) {
        self.kind = kind
        if !isAvailabilityChosen { availableFromAge = AccountDefaults.availableFromAge(for: kind) }
        if !isNetWorthInclusionChosen { includedInNetWorth = AccountDefaults.includedInNetWorth(kind) }
        if !isPlanInclusionChosen { includedInPlan = AccountDefaults.includedInPlan(kind) }
    }

    // For pickers and toggles: setting these is choosing by hand.

    /// The kind; setting it updates the defaults (see ``setKind(_:)``).
    var chosenKind: AccountKind {
        get { kind }
        set { setKind(newValue) }
    }

    /// Whether plans can draw on it only from an age (a pension fund);
    /// setting it stops it following the kind. Turned on, it starts at 65.
    var chosenIsLocked: Bool {
        get { availableFromAge != nil }
        set {
            availableFromAge = newValue ? (availableFromAge ?? 65) : nil
            isAvailabilityChosen = true
        }
    }

    /// The age from which plans can draw on it (65 until set).
    var chosenAvailableFromAge: Int {
        get { availableFromAge ?? 65 }
        set {
            availableFromAge = newValue
            isAvailabilityChosen = true
        }
    }

    /// Whether net worth includes it; setting it stops it following the kind.
    var chosenNetWorthInclusion: Bool {
        get { includedInNetWorth }
        set {
            includedInNetWorth = newValue
            isNetWorthInclusionChosen = true
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

    /// How the account records its values: a balance when its values are
    /// typed (an investment account without trades switches to one), else
    /// an edited account's own mode, which changing its kind doesn't change
    /// (see ``account(id:locale:)``); for a new one, the kind's: brokerage,
    /// crypto and metals record trades, the others a balance
    /// (docs/ACCOUNTS.md, "Decisions").
    var valuationMode: ValuationMode {
        offersTypedValues && values == .typed ? .balance : unchangedValuationMode
    }

    /// The mode the account has without the *Values* choice.
    private var unchangedValuationMode: ValuationMode {
        original?.valuationMode ?? kind.defaultValuationMode
    }

    /// Whether the account records its trades.
    var recordsTrades: Bool {
        valuationMode == .trades
    }

    /// Whether the asset mix applies: accounts that aren't debts and record
    /// a single balance, by default or in some of their values (a
    /// brokerage's imported history, say). Positions follow their instruments.
    var takesAssetMix: Bool {
        !kind.isLiability && (!recordsTrades || balanceValueCount > 0)
    }

    /// Whether it offers *Values: Typed by you*: an account of a kind that
    /// takes typed values (``Model/Account/offersTypedValues``) recorded as
    /// a balance, or an investment account without trades, which typed
    /// values switch to a balance; unless it's a starting estimate, which
    /// takes them anyway until it's closed.
    var offersTypedValues: Bool {
        kind.takesTypedValues && (unchangedValuationMode == .balance || !hasTrades)
            && !(original?.isStartingEstimate ?? false)
    }

    /// Whether choosing *Typed by you* turns Trends off: savings and
    /// investments in net worth (``Model/Account/typedValuesTurnOffTrends``).
    var typedValuesTurnOffTrends: Bool {
        (kind == .savings || kind.isInvestment) && includedInNetWorth
    }

    /// Whether it asks for an estimated loss of value a year: belongings.
    var takesDepreciation: Bool { kind == .belongings }

    /// The loss of value a year as a share ("15" is 0.15); `nil` when
    /// empty, unreadable, 0 (no loss) or not between 0 and 100.
    func depreciationShare(locale: Locale = .current) -> Decimal? {
        guard let percent = AmountInput.parse(depreciation, locale: locale).value, percent > 0, percent < 100
        else { return nil }
        return percent / 100
    }

    /// Whether it asks for a tax on withdrawals: accounts plans count, other
    /// than debts.
    var takesWithdrawalTaxRate: Bool { includedInPlan && !kind.isLiability }

    /// The tax on withdrawals as a share ("20" is 0.2, "0" is 0); `nil` when
    /// empty, unreadable or not between 0 and 100.
    func withdrawalTaxShare(locale: Locale = .current) -> Decimal? {
        guard let percent = AmountInput.parse(withdrawalTaxRate, locale: locale).value, percent >= 0, percent <= 100
        else { return nil }
        return percent / 100
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
        if takesDepreciation {
            switch AmountInput.parse(depreciation, locale: locale) {
            case .empty: break
            case .value(let percent) where percent >= 0 && percent < 100: break
            default: problems.append("Type the loss of value a year as a percentage from 0 to 99.")
            }
        }
        if takesWithdrawalTaxRate {
            switch AmountInput.parse(withdrawalTaxRate, locale: locale) {
            case .empty: break
            case .value(let percent) where percent >= 0 && percent <= 100: break
            default: problems.append("Type the tax on withdrawals as a percentage from 0 to 100.")
            }
        }
        if let closed = original?.closed, closed < opened {
            problems.append("It can't open after the day it closed.")
        }
        return problems
    }

    /// The account with these fields. An edited account keeps its ID and
    /// everything the form doesn't show (tags, successor, closing date,
    /// valuation mode); a new one gets `id`.
    ///
    /// An edited account keeps how its values are read: its valuation mode,
    /// written out when the new kind's default would differ (a current
    /// account made a brokerage stays a balance, and so does an investment
    /// account switched to typed values, switched back too), and its
    /// currency once it has history (``locksCurrency``).
    func account(id: AccountID, locale: Locale = .current) -> Account {
        var account = original ?? Account(id: id, name: "", kind: kind, currency: currency, opened: opened)
        if original?.kind != kind || valuationMode != unchangedValuationMode {
            // Written only when it isn't the kind's default (brokerage defaults to trades).
            account.valuation = valuationMode == kind.defaultValuationMode ? nil : valuationMode
        }
        account.name = trimmedName
        account.kind = kind
        account.currency = locksCurrency ? account.currency : currency
        account.opened = opened
        let trimmedInstitution = institution.trimmingCharacters(in: .whitespacesAndNewlines)
        account.institution = trimmedInstitution.isEmpty ? nil : trimmedInstitution
        account.country = country
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        account.notes = trimmedNotes.isEmpty ? nil : trimmedNotes

        account.availableFromAge = availableFromAge
        // A kind that doesn't lose value drops it, so nothing hidden keeps estimating.
        account.depreciation = takesDepreciation ? depreciationShare(locale: locale) : nil
        // Hidden while plans leave it out: what it had is kept.
        account.withdrawalTaxRate = takesWithdrawalTaxRate
            ? withdrawalTaxShare(locale: locale) : original?.withdrawalTaxRate
        account.values = valuesField

        // What the file leaves out follows the kind: true, or false for a tax pot.
        let byDefault = kind.isIncludedByDefault
        if let original, original.kind.isIncludedByDefault == byDefault,
           original.includedInNetWorth == includedInNetWorth, original.includedInPlan == includedInPlan {
            account.includeIn = original.includeIn
        } else if includedInNetWorth == byDefault && includedInPlan == byDefault {
            account.includeIn = nil
        } else {
            account.includeIn = IncludeIn(netWorth: includedInNetWorth == byDefault ? nil : includedInNetWorth,
                                          plan: includedInPlan == byDefault ? nil : includedInPlan)
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

    /// `values` as written: as the file had it while the choice is
    /// unchanged; `typed` when chosen, else left out. A kind that doesn't
    /// offer the choice drops a known value, so nothing hidden stays typed.
    private var valuesField: ValueEntry? {
        guard offersTypedValues else { return original?.values.flatMap { $0.isKnown ? nil : $0 } }
        if let original, values == Self.shownValues(of: original) { return original.values }
        return values == .typed ? .typed : nil
    }
}
