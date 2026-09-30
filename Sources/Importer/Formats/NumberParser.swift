import Foundation
import Model

/// A number read from a cell.
public struct ParsedNumber: Hashable, Sendable {
    /// The value; percentages are already divided by 100.
    public var value: Decimal
    /// The currency marked in the cell (`€`, `USD`, …), if any.
    public var currency: CurrencyCode?

    public init(value: Decimal, currency: CurrencyCode? = nil) {
        self.value = value
        self.currency = currency
    }
}

/// Reads numbers written in one format.
///
/// - Separators: the decimal separator is `.` or `,`. The thousands
///   separator is `.`, `,`, a space, a non-breaking space, `'`, or `""` for
///   none. When it isn't set, any of them except the decimal separator is
///   accepted. Groups must have three digits.
/// - Currency markers (`€ 1.234,56`, `EUR 1234.56`, `1,234.56 $`) are
///   stripped, and the currency is returned.
/// - Negatives: `-1`, `(1)`, `1-`, and the Unicode minus sign.
/// - Percentages: `12%` is 0.12, and so is `12` when the format says `percent`.
public struct NumberParser: Hashable, Sendable {
    public var format: ImportNumberFormat

    public init(format: ImportNumberFormat = ImportNumberFormat()) {
        self.format = format
    }

    /// The decimal separator in use (default `.`).
    public var decimalSeparator: Character {
        format.decimal.flatMap(\.first) ?? "."
    }

    /// Reads one cell. The text should be non-empty.
    public func parse(_ text: String) -> Result<ParsedNumber, ImportProblem> {
        let parts: NumberText
        switch NumberText.split(TextTools.cellValue(text)) {
        case .success(let value): parts = value
        case .failure(let problem): return .failure(problem)
        }
        guard var value = Self.parseCore(parts.core, decimal: decimalSeparator, thousands: thousandsRule) else {
            return .failure(.notANumber(format: example))
        }
        if parts.negative { value.negate() }
        if parts.percent || format.percent == true { value /= 100 }
        return .success(ParsedNumber(value: value, currency: parts.currency))
    }

    /// How the format writes 1234.56, for messages: `1.234,56`, `1234.56`.
    public var example: String {
        let decimal = String(decimalSeparator)
        switch thousandsRule {
        case .none, .any: return "1234\(decimal)56"
        case .one(let separator): return "1\(separator)234\(decimal)56"
        }
    }

    // MARK: - Internals

    enum ThousandsRule: Hashable {
        case none
        /// One separator class: `.`, `,`, `" "` (all spaces) or `'` (both apostrophes).
        case one(Character)
        /// Any separator except the decimal one.
        case any
    }

    var thousandsRule: ThousandsRule {
        guard let thousands = format.thousands else { return .any }
        guard let first = thousands.first else { return .none }
        return .one(Self.separatorClass(first) ?? first)
    }

    /// The class of a grouping character: all spaces are `" "`, both apostrophes `'`.
    static func separatorClass(_ character: Character) -> Character? {
        switch character {
        case ".", ",": character
        case " ", "\u{00A0}", "\u{202F}": " "
        case "'", "\u{2019}": "'"
        default: nil
        }
    }

    /// Digits with separators → a decimal, or `nil` if they don't fit the rule.
    static func parseCore(_ core: String, decimal: Character, thousands: ThousandsRule) -> Decimal? {
        var groups = [""]
        var fraction = ""
        var seenDecimal = false
        var groupSeparator: Character?
        for character in core {
            if TextTools.isDigit(character) {
                if seenDecimal { fraction.append(character) } else { groups[groups.count - 1].append(character) }
            } else if character == decimal, !seenDecimal {
                seenDecimal = true
            } else if !seenDecimal, let separator = separatorClass(character), separator != decimal {
                switch thousands {
                case .none: return nil
                case .one(let allowed) where allowed != separator: return nil
                default: break
                }
                if let groupSeparator, groupSeparator != separator { return nil }
                groupSeparator = separator
                groups.append("")
            } else {
                return nil
            }
        }
        if groups.count > 1 {
            guard (1...3).contains(groups[0].count), !groups[0].hasPrefix("0"),
                  groups.dropFirst().allSatisfy({ $0.count == 3 })
            else { return nil }
        }
        let integer = groups.joined()
        if seenDecimal, fraction.isEmpty { return nil }
        guard !integer.isEmpty || !fraction.isEmpty else { return nil }
        let plain = (integer.isEmpty ? "0" : integer) + (fraction.isEmpty ? "" : "." + fraction)
        return Decimal(string: plain, locale: Locale(identifier: "en_US_POSIX"))
    }
}

/// A cell split into its number and its decorations: sign, currency, percent.
struct NumberText: Hashable {
    var core: String
    var negative = false
    var currency: CurrencyCode?
    var percent = false

    /// Strips currency markers, signs, parentheses and `%` from both ends.
    static func split(_ text: String) -> Result<NumberText, ImportProblem> {
        var result = NumberText(core: text)
        var signs = 0
        var changed = true
        while changed {
            changed = false
            let trimmed = TextTools.trim(result.core)
            if trimmed != result.core {
                result.core = trimmed
            }
            let core = result.core
            guard !core.isEmpty else { break }
            if core.hasPrefix("("), core.hasSuffix(")"), core.count >= 2 {
                result.core = String(core.dropFirst().dropLast())
                signs += 1
                changed = true
            } else if let first = core.first, first == "-" || first == "\u{2212}" {
                result.core = String(core.dropFirst())
                signs += 1
                changed = true
            } else if let last = core.last, last == "-" || last == "\u{2212}" {
                result.core = String(core.dropLast())
                signs += 1
                changed = true
            } else if core.first == "+" {
                result.core = String(core.dropFirst())
                changed = true
            } else if core.first == "%" || core.last == "%" {
                result.core = core.first == "%" ? String(core.dropFirst()) : String(core.dropLast())
                result.percent = true
                changed = true
            } else if let (currency, rest) = CurrencyMarkers.strip(core) {
                if let existing = result.currency, existing != currency { return .failure(.conflictingMarkers) }
                result.currency = currency
                result.core = rest
                changed = true
            }
        }
        if signs > 1 { return .failure(.conflictingMarkers) }
        result.negative = signs == 1
        return .success(result)
    }
}

/// Currency symbols and ISO codes as they appear next to amounts.
enum CurrencyMarkers {
    static let symbols: [(String, CurrencyCode)] = [
        ("US$", .usd), ("€", .eur), ("$", .usd), ("£", .gbp), ("¥", .jpy), ("CHF", .chf),
    ]

    /// Codes recognised next to amounts and in currency columns.
    static let codes: Set<String> = [
        "EUR", "USD", "GBP", "CHF", "JPY", "CAD", "AUD", "NZD", "SEK", "NOK", "DKK", "PLN", "CZK", "HUF",
        "RON", "BGN", "CNY", "HKD", "SGD", "INR", "BRL", "MXN", "ZAR", "TRY", "ILS", "KRW",
    ]

    /// The currency marked at the start or end of `text`, and the rest.
    static func strip(_ text: String) -> (CurrencyCode, String)? {
        for (symbol, code) in symbols {
            if text.hasPrefix(symbol) { return (code, String(text.dropFirst(symbol.count))) }
            if text.hasSuffix(symbol) { return (code, String(text.dropLast(symbol.count))) }
        }
        let upper = text.uppercased()
        if upper.count >= 3 {
            let prefix = String(upper.prefix(3))
            let next = upper.dropFirst(3).first
            if codes.contains(prefix), next.map({ !$0.isLetter }) ?? true {
                return (CurrencyCode(prefix), String(text.dropFirst(3)))
            }
            let suffix = String(upper.suffix(3))
            let before = upper.dropLast(3).last
            if codes.contains(suffix), before.map({ !$0.isLetter }) ?? true {
                return (CurrencyCode(suffix), String(text.dropLast(3)))
            }
        }
        return nil
    }

    /// A cell or header word that is only a currency: `EUR`, `usd`, `€`.
    static func currency(in text: String) -> CurrencyCode? {
        let trimmed = TextTools.trim(text)
        if let (code, rest) = strip(trimmed), TextTools.trim(rest).isEmpty { return code }
        return nil
    }

    /// A currency named in a header, e.g. `Saldo (€)` or `Balance USD`.
    static func currency(inHeader header: String) -> CurrencyCode? {
        for (symbol, code) in symbols where header.contains(symbol) && symbol != "CHF" { return code }
        let tokens = header.uppercased().split { !$0.isLetter }.map(String.init)
        let found = Set(tokens.filter { codes.contains($0) })
        return found.count == 1 ? found.first.map { CurrencyCode($0) } : nil
    }
}
