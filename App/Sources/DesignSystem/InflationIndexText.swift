import Foundation
import Model

/// How the app names an inflation index (docs/schema,
/// library.schema.json: `inflationIndex`): by the area whose consumer prices it measures, in the
/// user's language. Free of SwiftUI so it can be checked on Linux.
enum InflationIndexText {
    /// "Germany", "the euro area": the area an HICP measures; `nil` for an
    /// index that isn't one (`cpi-us`).
    static func area(of index: IndexID, locale: Locale = .current) -> String? {
        guard let area = index.hicpArea else { return nil }
        if area == "EA" { return "the euro area" }
        return CountryChoices.name(of: CountryCode(area), locale: locale)
    }

    /// "Inflation (Germany)", "Inflation (euro area)", or "Inflation (cpi-us)".
    static func title(of index: IndexID, locale: Locale = .current) -> String {
        guard let area = area(of: index, locale: locale) else { return "Inflation (\(index.rawValue))" }
        return "Inflation (\(area.hasPrefix("the ") ? String(area.dropFirst(4)) : area))"
    }

    /// "Germany's prices", "the euro area's prices", or "cpi-us", for
    /// sentences: "adjusted with Germany's prices".
    static func prices(of index: IndexID, locale: Locale = .current) -> String {
        area(of: index, locale: locale).map { "\($0)'s prices" } ?? index.rawValue
    }

    /// The Settings picker's automatic choice: "Automatic: Germany", or
    /// "Automatic: none" when the library has no index.
    static func automaticChoice(_ index: IndexID?, locale: Locale = .current) -> String {
        guard let index else { return "Automatic: none" }
        return "Automatic: " + choice(index, locale: locale)
    }

    /// A choice in the Settings picker: "Germany", "Euro area", or the ID.
    static func choice(_ index: IndexID, locale: Locale = .current) -> String {
        guard let area = area(of: index, locale: locale) else { return index.rawValue }
        return area == "the euro area" ? "Euro area" : area
    }
}
