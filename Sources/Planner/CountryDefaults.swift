import Foundation
import Model

/// What first launch suggests for the country you live in (UI.md, "Empty
/// states and first launch"): the age a state pension starts, the age a
/// pension pot can be drawn from, and the tax on investment gains. Round
/// suggestions to check, shown in the fields and editable; a country
/// without one leaves the field empty.
public enum CountryDefaults {
    /// The age the state pension starts: 67 where the country has none here.
    public static func statePensionAge(for country: CountryCode?) -> Int {
        switch country?.rawValue {
        case "AT", "CH": 65
        case "FR": 64
        case "PT", "IE": 66
        default: 67
        }
    }

    /// The age a private pension pot can be drawn from: 60 in the United
    /// States (59½), 57 in the United Kingdom, else the state pension's.
    public static func pensionPotAge(for country: CountryCode?) -> Int {
        switch country?.rawValue {
        case "US": 60
        case "GB": 57
        default: statePensionAge(for: country)
        }
    }

    /// The flat tax on investment gains and income, as a fraction, where
    /// the country has one rate for most savers: Germany's 25% with the
    /// solidarity surcharge, Austria, Italy, France's flat tax, Portugal,
    /// and the United States' usual long-term rate. `nil` elsewhere.
    public static func investmentTax(for country: CountryCode?) -> Decimal? {
        switch country?.rawValue {
        case "DE": Decimal(string: "0.26375")
        case "AT": Decimal(string: "0.275")
        case "IT": Decimal(string: "0.26")
        case "FR": Decimal(string: "0.30")
        case "PT": Decimal(string: "0.28")
        case "US": Decimal(string: "0.15")
        default: nil
        }
    }

    /// What the state pension is called where you live: "Social Security"
    /// in the United States, else "State pension".
    public static func statePensionName(for country: CountryCode?) -> String {
        country?.rawValue == "US" ? "Social Security" : "State pension"
    }

    /// Where the state pension's amount comes from: "your Social Security
    /// statement" in the United States, "your State Pension forecast" in the
    /// United Kingdom, "your Renteninformation" in Germany, else "your
    /// pension statement".
    public static func statePensionSource(for country: CountryCode?) -> String {
        switch country?.rawValue {
        case "US": "your Social Security statement"
        case "GB": "your State Pension forecast"
        case "DE": "your Renteninformation"
        default: "your pension statement"
        }
    }
}
