import Foundation

/// An amount as parsed, with how many decimals it was written with (the
/// commodity's precision, used as the tolerance when balancing).
struct ParsedAmount: Hashable, Sendable {
    var quantity: Decimal
    var commodity: String
    var decimals: Int

    var amount: LedgerAmount { LedgerAmount(quantity, commodity) }
}

/// An amount's parts as written, before the number is read: `-€1.000,50`
/// is negative, `1.000,50` and `€`.
struct AmountText: Hashable, Sendable {
    var negative: Bool
    var number: String
    var commodity: String
}

/// Reads amounts in the common ledger-cli and hledger forms: the commodity
/// before or after, with or without a space (`€5`, `5 EUR`, `EUR -5`,
/// `-€5`, `€-5`), quoted commodities (`"VWCE.MI"`), and numbers with
/// thousands separators and a decimal point or comma.
enum LedgerAmountParser {
    /// Characters that end an unquoted commodity symbol.
    private static let reserved: Set<Character> = ["-", "+", ";", "@", "{", "}", "[", "]", "(", ")", "=", "*", "\"",
                                                   "!", "&", "|", ","]

    static func isNumberStart(_ character: Character, next: Character?) -> Bool {
        if TextTools.isDigit(character) { return true }
        if character == "." || character == "," { return next.map(TextTools.isDigit) ?? false }
        return false
    }

    /// Splits an amount into sign, number text and commodity. Returns a
    /// reason when the text isn't an amount.
    static func split(_ text: String) -> Result<AmountText, AmountError> {
        let characters = Array(text.trimmingCharacters(in: .whitespaces))
        guard !characters.isEmpty else { return .failure(.empty) }
        var index = 0
        var negative = false
        var signs = 0
        var commodity = ""
        var number = ""

        func skipSpaces() {
            while index < characters.count, characters[index] == " " || characters[index] == "\t" { index += 1 }
        }
        func peek(_ offset: Int = 0) -> Character? {
            index + offset < characters.count ? characters[index + offset] : nil
        }
        func readSign() {
            while let character = peek(), character == "-" || character == "+" {
                if character == "-" { negative.toggle() }
                signs += 1
                index += 1
                skipSpaces()
            }
        }
        func readQuoted() -> String? {
            guard peek() == "\"" else { return nil }
            index += 1
            var symbol = ""
            while let character = peek(), character != "\"" {
                symbol.append(character)
                index += 1
            }
            guard peek() == "\"" else { return nil }
            index += 1
            return symbol
        }
        func readSymbol(after: Bool) -> String {
            var symbol = ""
            while let character = peek() {
                if character == " " || character == "\t" { break }
                if !after, TextTools.isDigit(character) { break }
                if character == "." {
                    // A suffix such as `.MI` belongs to the symbol; a decimal mark doesn't.
                    guard !symbol.isEmpty, let next = peek(1), next.isLetter else { break }
                } else if reserved.contains(character) {
                    break
                }
                symbol.append(character)
                index += 1
            }
            return symbol
        }

        readSign()
        if peek() == "\"" {
            guard let quoted = readQuoted() else { return .failure(.unclosedQuote) }
            commodity = quoted
            skipSpaces()
            readSign()
        } else if let first = peek(), !isNumberStart(first, next: peek(1)) {
            commodity = readSymbol(after: false)
            guard !commodity.isEmpty else { return .failure(.unexpected(String(first))) }
            skipSpaces()
            readSign()
        }
        while let character = peek(), TextTools.isDigit(character) || character == "." || character == ","
            || character == "'" {
            number.append(character)
            index += 1
        }
        guard number.contains(where: TextTools.isDigit) else {
            return .failure(commodity.isEmpty ? .unexpected(String(characters[index...])) : .noNumber)
        }
        skipSpaces()
        if commodity.isEmpty, peek() != nil {
            if peek() == "\"" {
                guard let quoted = readQuoted() else { return .failure(.unclosedQuote) }
                commodity = quoted
            } else {
                commodity = readSymbol(after: true)
            }
            skipSpaces()
        }
        if index < characters.count { return .failure(.unexpected(String(characters[index...]))) }
        if signs > 1 { return .failure(.twoSigns) }
        return .success(AmountText(negative: negative, number: number, commodity: commodity))
    }

    /// Reads a number with a known decimal mark, or infers it when `mark` is
    /// `nil`: with both `.` and `,` the last one is the decimal mark; one
    /// mark used more than once separates thousands; one mark used once is
    /// the decimal mark unless exactly three digits follow, when `fallback`
    /// decides. `'` always separates thousands.
    static func value(of number: String, negative: Bool, mark: Character?,
                      fallback: Character) -> (value: Decimal, decimals: Int)? {
        let decimalMark: Character?
        if let mark {
            decimalMark = mark
        } else {
            let dots = number.filter { $0 == "." }.count
            let commas = number.filter { $0 == "," }.count
            if dots > 0, commas > 0 {
                decimalMark = number.last { $0 == "." || $0 == "," }
            } else if dots + commas == 0 {
                decimalMark = nil
            } else {
                let only: Character = dots > 0 ? "." : ","
                if dots + commas > 1 {
                    decimalMark = only == "." ? "," : "."
                } else if isAmbiguous(number) {
                    decimalMark = fallback == only ? only : (only == "." ? "," : ".")
                } else {
                    decimalMark = only
                }
            }
        }
        var digits = ""
        var decimals = 0
        var seenMark = false
        for character in number {
            if TextTools.isDigit(character) {
                digits.append(character)
                if seenMark { decimals += 1 }
            } else if character == decimalMark {
                guard !seenMark else { return nil }
                seenMark = true
                digits.append(".")
            } else if character == "." || character == "," || character == "'" {
                guard !seenMark else { return nil }
            } else {
                return nil
            }
        }
        if digits.hasPrefix(".") { digits = "0" + digits }
        if digits.hasSuffix(".") { digits.removeLast() }
        guard let value = Decimal(string: digits, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return (negative ? -value : value, decimals)
    }

    /// Whether a number could be read either way: one `.` or `,`, used once,
    /// with exactly three digits after it and one to three before (`1.000`).
    static func isAmbiguous(_ number: String) -> Bool {
        let marks = number.filter { $0 == "." || $0 == "," }
        guard marks.count == 1, let index = number.firstIndex(where: { $0 == "." || $0 == "," }) else { return false }
        let before = number[..<index].filter(TextTools.isDigit).count
        let after = number[number.index(after: index)...]
        return after.count == 3 && after.allSatisfy(TextTools.isDigit) && (1...3).contains(before)
            && !number.contains("'")
    }

    /// The decimal mark a number shows unambiguously, if it does.
    static func evidence(_ number: String) -> Character? {
        let dots = number.filter { $0 == "." }.count
        let commas = number.filter { $0 == "," }.count
        if dots > 0, commas > 0 { return number.last { $0 == "." || $0 == "," } }
        if dots + commas == 1, !isAmbiguous(number) { return dots == 1 ? "." : "," }
        if dots > 1 { return "," }
        if commas > 1 { return "." }
        return nil
    }

    /// The decimal mark of a format sample in a `commodity` or `D` directive:
    /// the last mark when there are both, a mark used once, or the other
    /// one when a mark repeats (`1.000.000`).
    static func formatMark(_ number: String) -> Character? {
        let dots = number.filter { $0 == "." }.count
        let commas = number.filter { $0 == "," }.count
        if dots > 0, commas > 0 { return number.last { $0 == "." || $0 == "," } }
        if dots == 1 { return "." }
        if commas == 1 { return "," }
        if dots > 1 { return "," }
        if commas > 1 { return "." }
        return nil
    }
}

/// Why a text isn't an amount.
enum AmountError: Error, Hashable, CustomStringConvertible {
    case empty
    case noNumber
    case unclosedQuote
    case twoSigns
    case unexpected(String)
    case badNumber(String)

    var description: String {
        switch self {
        case .empty: "no amount"
        case .noNumber: "a commodity without a number"
        case .unclosedQuote: "a quoted commodity without its closing quote"
        case .twoSigns: "more than one sign"
        case .unexpected(let text): "“\(text)” isn't part of an amount"
        case .badNumber(let text): "“\(text)” isn't a number"
        }
    }
}
