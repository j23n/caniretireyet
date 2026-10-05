import Foundation

// Which consumer price index measures prices where: the harmonised index of
// consumer prices (HICP) of each country that has one and of the euro area,
// and the one a library adjusts its amounts with (FILE_FORMAT.md,
// "library.json": `inflationIndex`).

extension IndexID {
    /// The euro area's harmonised index of consumer prices, from Eurostat:
    /// prices across the countries that use the euro.
    public static let hicpEA: IndexID = "hicp-ea"

    /// The countries with a harmonised index of consumer prices, which
    /// Eurostat publishes every month: the EU's members, Iceland, Norway and
    /// Switzerland, and the candidate countries Albania, Montenegro, North
    /// Macedonia, Serbia and Türkiye. Sorted.
    public static let hicpCountries: [CountryCode] = hicpCurrencies.keys.sorted()

    /// `hicp-de`: the all-items HICP of `country` (any case), or `nil` for a
    /// country without one (``hicpCountries``).
    public static func hicp(_ country: CountryCode) -> IndexID? {
        let code = CountryCode(country.rawValue.uppercased())
        guard hicpCurrencies[code] != nil else { return nil }
        return IndexID("hicp-" + code.rawValue.lowercased())
    }

    /// The HICP that measures prices in `currency`: the euro area's for the
    /// euro, else that of the country whose currency it is (`hicp-ch` for
    /// francs, `hicp-se` for kronor). `nil` when no HICP is in that
    /// currency, e.g. for dollars.
    public static func hicp(currency: CurrencyCode) -> IndexID? {
        let code = CurrencyCode(currency.rawValue.uppercased())
        if code == .eur { return .hicpEA }
        let countries = hicpCurrencies.filter { $0.value == code }.keys.sorted()
        return countries.count == 1 ? hicp(countries[0]) : nil
    }

    /// The area an HICP measures: its country's code in capitals (`IT`), or
    /// `EA` for the euro area. `nil` for any other index.
    public var hicpArea: String? {
        guard rawValue.hasPrefix("hicp-") else { return nil }
        let area = String(rawValue.dropFirst("hicp-".count)).uppercased()
        if area == "EA" { return area }
        return Self.hicpCurrencies[CountryCode(area)] != nil ? area : nil
    }

    /// The currency an HICP's prices are in: the euro for the euro area and
    /// the countries that use it, the country's own otherwise. `nil` for any
    /// other index.
    public var hicpCurrency: CurrencyCode? {
        guard let area = hicpArea else { return nil }
        return area == "EA" ? .eur : Self.hicpCurrencies[CountryCode(area)]
    }

    /// Each country with an HICP, and the currency its prices are in today
    /// (Croatia has used the euro since 2023, Bulgaria since 2026;
    /// Montenegro uses it without being a member of the euro area).
    private static let hicpCurrencies: [CountryCode: CurrencyCode] = {
        let euro: [String] = ["AT", "BE", "BG", "CY", "DE", "EE", "ES", "FI", "FR", "GR", "HR", "IE", "IT", "LT",
                              "LU", "LV", "ME", "MT", "NL", "PT", "SI", "SK"]
        let own: [(String, String)] = [
            ("AL", "ALL"), ("CH", "CHF"), ("CZ", "CZK"), ("DK", "DKK"), ("HU", "HUF"), ("IS", "ISK"),
            ("MK", "MKD"), ("NO", "NOK"), ("PL", "PLN"), ("RO", "RON"), ("RS", "RSD"), ("SE", "SEK"),
            ("TR", "TRY"),
        ]
        var currencies: [CountryCode: CurrencyCode] = [:]
        for country in euro { currencies[CountryCode(country)] = .eur }
        for (country, currency) in own { currencies[CountryCode(country)] = CurrencyCode(currency) }
        return currencies
    }()
}

extension Library {
    /// The consumer price index the library expresses amounts in today's
    /// money with, and computes real returns with (FILE_FORMAT.md,
    /// "library.json"):
    ///
    /// 1. `settings.inflationIndex`, when it's set;
    /// 2. else the HICP of the tax residence (`hicp-de` for `DE`), when the
    ///    country has one;
    /// 3. else, among the indices in the base currency that the library has
    ///    values of, the one with the most (so a library in euros that
    ///    recorded `hicp-it` keeps using it);
    /// 4. else the HICP of the base currency: the euro area's for euros
    ///    (`hicp-ea`), Switzerland's for francs (`hicp-ch`).
    ///
    /// `nil` when none applies, e.g. a library in dollars whose tax
    /// residence has no HICP.
    public var effectiveInflationIndex: IndexID? {
        if let chosen = settings.inflationIndex { return chosen }
        if let residence = settings.taxResidence, let index = IndexID.hicp(residence) { return index }
        let base = settings.baseCurrency
        var counts: [IndexID: Int] = [:]
        for month in months.values {
            for record in month.indices where record.index.hicpCurrency == base {
                counts[record.index, default: 0] += 1
            }
        }
        if let recorded = counts.max(by: { ($0.value, $1.key) < ($1.value, $0.key) })?.key { return recorded }
        return IndexID.hicp(currency: base)
    }

    /// The index for amounts in `currency`, such as a plan's: the library's
    /// own (``effectiveInflationIndex``) for its base currency or when its
    /// prices are in `currency` (`hicp-it` for euros); else the HICP of that
    /// currency (`hicp-ch` for francs, `hicp-ea` for euros). `nil` when no
    /// index is known for it.
    public func inflationIndex(for currency: CurrencyCode) -> IndexID? {
        let own = effectiveInflationIndex
        if currency == settings.baseCurrency { return own }
        if let own, own.hicpCurrency == currency { return own }
        return IndexID.hicp(currency: currency)
    }

    /// Every index the library needs values of: its own. Plans are in the
    /// base currency, so they need no other.
    public var inflationIndices: [IndexID] {
        [effectiveInflationIndex].compactMap { $0 }
    }
}
