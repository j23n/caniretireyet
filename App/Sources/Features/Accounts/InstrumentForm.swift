import Foundation
import Model
import Prices

// An instrument's fields while it's added or edited (UI.md, "Instruments"):
// name, ISIN or ticker, currency, unit, asset mix and price source, with
// defaults that follow its kind. Plain values, so they can be checked on
// Linux.

/// An instrument's fields while it's added or edited.
struct InstrumentForm: Hashable, Sendable {
    var name: String
    var kind: InstrumentKind
    var currency: CurrencyCode
    var unit: String
    var isin: String
    var ticker: String
    var assetMix: AccountsAssetMixForm
    /// `nil`: prices are typed in by hand.
    var provider: PriceProvider?
    var symbol: String
    /// What kind of fund an ETF or fund is for tax purposes
    /// (`tax.fundType`); `nil` lets the planner work it out from the asset
    /// mix (``automaticFundType(locale:)``).
    var fundType: FundType?
    /// Whether an ETC gives a right to delivery of the metal (`tax.deliveryClaim`).
    var deliveryClaim: Bool
    /// The instrument being edited, whose other fields (its other tax
    /// overrides) are kept.
    private(set) var original: Instrument?

    /// A new ETF in `currency`, priced from Yahoo Finance.
    init(currency: CurrencyCode) {
        name = ""
        kind = .etf
        self.currency = currency
        unit = InstrumentUnit.share.rawValue
        isin = ""
        ticker = ""
        assetMix = AccountsAssetMixForm(.single(.equity))
        provider = .yahoo
        symbol = ""
        fundType = nil
        deliveryClaim = false
        original = nil
    }

    init(editing instrument: Instrument, locale: Locale = .current) {
        name = instrument.name
        kind = instrument.kind
        currency = instrument.currency
        unit = instrument.unit.rawValue
        isin = instrument.isin ?? ""
        ticker = instrument.ticker ?? ""
        assetMix = AccountsAssetMixForm(instrument.assetClasses, locale: locale)
        provider = instrument.priceSource?.provider
        symbol = instrument.priceSource?.symbol ?? ""
        fundType = instrument.tax?.fundType
        deliveryClaim = instrument.tax?.deliveryClaim ?? false
        original = instrument
    }

    // MARK: Taxes

    /// Whether the kind is a fund (an ETF or a fund), which has a fund type.
    var takesFundType: Bool { kind.hasFundType }

    /// Whether the kind can have a delivery claim (an ETC).
    var takesDeliveryClaim: Bool { kind == .etc }

    /// The fund type the planner works out from the asset mix as typed, or
    /// `nil` while it can't be read.
    func automaticFundType(locale: Locale = .current) -> FundType? {
        assetMix.mix(locale: locale).map(Self.automaticFundType(for:))
    }

    /// The fund type of a fund with `mix`, as the planner works it out when
    /// the instrument doesn't say (`FundType.derived(from:)`, PLANNER.md,
    /// "Portfolio"): more than half in equity is an equity fund, more than
    /// half in real estate a real-estate fund, at least a quarter in equity
    /// a mixed fund, and anything else another fund.
    static func automaticFundType(for mix: AssetMix) -> FundType {
        FundType.derived(from: mix)
    }

    /// The fund-type picker's choices: automatic (`nil`), then each type.
    static let fundTypes: [FundType] = FundType.knownValues

    /// "Equity fund", "Mixed fund", …
    static func name(of fundType: FundType) -> String {
        switch fundType {
        case .equity: "Equity fund"
        case .mixed: "Mixed fund"
        case .realEstate: "Real-estate fund"
        case .foreignRealEstate: "Foreign real-estate fund"
        case .other: "Other fund"
        default: fundType.rawValue
        }
    }

    /// The automatic choice's label: "Automatic (equity fund)", or
    /// "Automatic" while the asset mix can't be read.
    func automaticFundTypeTitle(locale: Locale = .current) -> String {
        guard let automatic = automaticFundType(locale: locale) else { return "Automatic" }
        return "Automatic (\(PlanResultsText.lowercasedFirst(Self.name(of: automatic))))"
    }

    /// The instrument's tax overrides with the form's fund type and
    /// delivery claim (each only for the kinds it applies to), keeping the
    /// others; `nil` when there's none left.
    func tax(keeping original: InstrumentTax?) -> InstrumentTax? {
        var tax = original ?? InstrumentTax()
        tax.fundType = takesFundType ? fundType : nil
        tax.deliveryClaim = takesDeliveryClaim && deliveryClaim ? true : nil
        return tax == InstrumentTax() ? nil : tax
    }

    var isNew: Bool { original == nil }

    /// Changes the kind of a new instrument, and with it the unit, asset
    /// mix and price source that usually go with it.
    mutating func setKind(_ kind: InstrumentKind) {
        self.kind = kind
        guard isNew else { return }
        switch kind {
        case .crypto:
            unit = ticker.isEmpty ? "BTC" : ticker.uppercased()
            assetMix = AccountsAssetMixForm(.single(.crypto))
            provider = .coingecko
        case .metal:
            unit = InstrumentUnit.gram.rawValue
            assetMix = AccountsAssetMixForm(.single(.gold))
            provider = .goldAPI
            if symbol.isEmpty { symbol = "XAU" }
        case .bond:
            unit = InstrumentUnit.share.rawValue
            assetMix = AccountsAssetMixForm(.single(.bonds))
            provider = .yahoo
        case .etf, .stock:
            unit = InstrumentUnit.share.rawValue
            assetMix = AccountsAssetMixForm(.single(.equity))
            provider = .yahoo
        case .fund:
            unit = InstrumentUnit.share.rawValue
            assetMix = AccountsAssetMixForm()
            provider = nil
        default:
            unit = InstrumentUnit.share.rawValue
            assetMix = AccountsAssetMixForm(.single(.other))
            provider = nil
        }
    }

    // For pickers: setting these applies what goes with them.

    /// The kind; setting it applies its defaults (see ``setKind(_:)``).
    var chosenKind: InstrumentKind {
        get { kind }
        set { setKind(newValue) }
    }

    /// The price source; choosing one fills in a suggested symbol when
    /// there's none yet.
    var chosenProvider: PriceProvider? {
        get { provider }
        set {
            provider = newValue
            if symbol.trimmingCharacters(in: .whitespaces).isEmpty { symbol = suggestedSymbol }
        }
    }

    /// The instrument as typed so far, for *Test price fetch*: only the
    /// fields a fetch needs (currency, unit, price source).
    func testInstrument(id: InstrumentID) -> Instrument {
        let trimmedSymbol = symbol.trimmingCharacters(in: .whitespaces)
        let trimmedUnit = unit.trimmingCharacters(in: .whitespaces)
        return Instrument(
            id: id, name: trimmedName.isEmpty ? id.rawValue : trimmedName, kind: kind, currency: currency,
            unit: InstrumentUnit(rawValue: trimmedUnit.isEmpty ? InstrumentUnit.share.rawValue : trimmedUnit),
            assetClasses: .single(.other),
            priceSource: provider.flatMap { trimmedSymbol.isEmpty ? nil : PriceSource(provider: $0, symbol: trimmedSymbol) })
    }

    /// A symbol to suggest for the price source: the ticker for Yahoo, the
    /// name for CoinGecko, `XAU` for gold.
    var suggestedSymbol: String {
        guard let provider else { return "" }
        switch provider {
        case .yahoo, .eodhd, .twelveData: return ticker.trimmingCharacters(in: .whitespaces)
        case .coingecko: return trimmedName.isEmpty ? "" : Slug.make(from: trimmedName)
        case .goldAPI: return "XAU"
        default: return ""
        }
    }

    /// The symbol field's placeholder: the suggested symbol, or an example
    /// for the price source ("Yahoo ticker, e.g. VWCE.DE", "e.g. ETH or
    /// ethereum", "XAU or XAG").
    var symbolPrompt: String {
        let suggested = suggestedSymbol
        guard suggested.isEmpty else { return suggested }
        guard let provider else { return "" }
        switch provider {
        case .yahoo: return "Yahoo ticker, e.g. VWCE.DE"
        case .coingecko: return "e.g. ETH or ethereum"
        case .goldAPI: return "XAU or XAG"
        default: return "e.g. VWCE.DE"
        }
    }

    /// What the symbol is for the chosen price source, for the section's
    /// footer; `nil` when there's nothing to add.
    var symbolHint: String? {
        guard let provider else { return nil }
        switch provider {
        case .yahoo: return "The symbol is the Yahoo Finance ticker with its exchange, e.g. VWCE.DE (Xetra)."
        case .coingecko: return "The symbol is the coin's ticker or its CoinGecko ID, e.g. ETH or ethereum."
        case .goldAPI: return "XAU is gold, XAG silver."
        default: return nil
        }
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What must be fixed before saving, in order.
    func problems(locale: Locale = .current) -> [String] {
        var problems: [String] = []
        if trimmedName.isEmpty { problems.append("Give the instrument a name.") }
        if !currency.isWellFormed { problems.append("Choose the currency prices are quoted in.") }
        if unit.trimmingCharacters(in: .whitespaces).isEmpty { problems.append("Enter the unit a price is per.") }
        if let problem = assetMix.problem(required: true, locale: locale) { problems.append(problem) }
        if provider != nil, symbol.trimmingCharacters(in: .whitespaces).isEmpty {
            problems.append("Enter the symbol the price source knows it by, or choose \"Typed in by hand\".")
        }
        return problems
    }

    /// The instrument with these fields. An edited instrument keeps its ID
    /// and its tax overrides; a new one gets `id`. `nil` while the asset mix
    /// doesn't add up.
    func instrument(id: InstrumentID, locale: Locale = .current) -> Instrument? {
        guard let mix = assetMix.mix(locale: locale) else { return nil }
        func optional(_ text: String) -> String? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        var instrument = original ?? Instrument(id: id, name: "", kind: kind, currency: currency, unit: .share,
                                                assetClasses: mix)
        instrument.name = trimmedName
        instrument.kind = kind
        instrument.currency = currency
        instrument.unit = InstrumentUnit(rawValue: unit.trimmingCharacters(in: .whitespaces))
        if let original, assetMix == AccountsAssetMixForm(original.assetClasses, locale: locale) {
            instrument.assetClasses = original.assetClasses
        } else {
            instrument.assetClasses = mix
        }
        instrument.isin = optional(isin)?.uppercased()
        instrument.ticker = optional(ticker)
        if let provider, let symbol = optional(symbol) {
            instrument.priceSource = PriceSource(provider: provider, symbol: symbol)
        } else {
            instrument.priceSource = nil
        }
        instrument.tax = tax(keeping: original?.tax)
        return instrument
    }

    // MARK: Names

    /// Units offered as suggestions.
    static let units: [InstrumentUnit] = [.share, .gram, .kilogram, .troyOunce]

    static func name(of kind: InstrumentKind) -> String {
        switch kind {
        case .etf: "ETF"
        case .fund: "Fund"
        case .stock: "Stock"
        case .bond: "Bond"
        case .etc: "ETC"
        case .crypto: "Crypto"
        case .metal: "Precious metal"
        case .other: "Other"
        default: kind.rawValue
        }
    }

    static func name(of provider: PriceProvider) -> String {
        switch provider {
        case .yahoo: "Yahoo Finance"
        case .coingecko: "CoinGecko"
        case .goldAPI: "gold-api.com"
        case .eodhd: "EODHD"
        case .twelveData: "Twelve Data"
        default: provider.rawValue
        }
    }

    static func name(of unit: InstrumentUnit) -> String {
        switch unit {
        case .share: "share"
        case .gram: "gram"
        case .kilogram: "kilogram"
        case .troyOunce: "troy ounce"
        default: unit.rawValue
        }
    }

    /// A short unit for amounts: "sh", "g", "BTC".
    static func shortName(of unit: InstrumentUnit) -> String {
        unit == .share ? "sh" : unit.rawValue
    }

    /// The outcome of a *Test price fetch*, as a sentence.
    static func describe(_ entry: PriceListEntry, canFetch: Bool, locale: Locale = .current) -> String {
        switch entry.outcome {
        case .fetched(let details):
            guard let quote = details.quote else { return "Fetched a price." }
            var text = "Fetched \(AmountFormat.number(quote.price, locale: locale)) \(quote.currency)"
            if let unit = quote.unit { text += " per \(name(of: unit))" }
            text += " for \(AmountFormat.shortDate(quote.observedOn, locale: locale))."
            return text
        case .manual:
            return canFetch ? "There's no price source: prices are typed in by hand at each check-in."
                : "Fetching is off here (previews). In the app this fetches today's price."
        case .failed(let error):
            return error.description
        }
    }
}
