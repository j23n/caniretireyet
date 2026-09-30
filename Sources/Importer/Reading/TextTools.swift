import Foundation

/// Text helpers shared across the importer: trimming, folding for matching,
/// and whole-word keyword tests.
enum TextTools {
    /// Whitespace, including non-breaking spaces and a stray byte-order mark.
    static func isSpace(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isWhitespace || scalar == "\u{FEFF}"
    }

    /// The text without leading and trailing whitespace (non-breaking spaces included).
    static func trim(_ string: String) -> String {
        let scalars = string.unicodeScalars
        guard let start = scalars.firstIndex(where: { !isSpace($0) }),
              let end = scalars.lastIndex(where: { !isSpace($0) })
        else { return "" }
        return String(scalars[start...end])
    }

    /// A cell's value: trimmed, with Excel's `="…"` text wrapper removed.
    static func cellValue(_ string: String) -> String {
        let trimmed = trim(string)
        if trimmed.hasPrefix("=\""), trimmed.hasSuffix("\""), trimmed.count >= 3 {
            return trim(String(trimmed.dropFirst(2).dropLast()))
        }
        return trimmed
    }

    /// Lowercased, without diacritics, trimmed, with runs of whitespace
    /// collapsed to one space: `"  Più  Crédit "` → `"piu credit"`.
    static func fold(_ string: String) -> String {
        var folded = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in string.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars {
            if scalar.properties.generalCategory == .nonspacingMark { continue }
            if isSpace(scalar) {
                pendingSpace = !folded.isEmpty
                continue
            }
            if pendingSpace {
                folded.append(" ")
                pendingSpace = false
            }
            folded.append(scalar)
        }
        return String(folded)
    }

    /// The folded words of a text: runs of letters and digits.
    static func words(_ string: String) -> [String] {
        fold(string).split { !($0.isLetter || $0.isNumber) }.map(String.init)
    }

    /// Whether `words` contains one of `phrases` (each one or more folded
    /// words separated by spaces) as consecutive whole words.
    static func contains(_ words: [String], anyOf phrases: [String]) -> Bool {
        phrases.contains { phrase in
            let parts = phrase.split(separator: " ").map(String.init)
            guard !parts.isEmpty, parts.count <= words.count else { return false }
            return (0...(words.count - parts.count)).contains { start in
                Array(words[start..<(start + parts.count)]) == parts
            }
        }
    }

    /// Whether the character is an ASCII digit.
    static func isDigit(_ character: Character) -> Bool {
        character.isASCII && character.isWholeNumber
    }

    /// Whether the scalar is an ASCII digit.
    static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
        ("0"..."9").contains(scalar)
    }
}
