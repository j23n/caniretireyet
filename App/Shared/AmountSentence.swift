import Foundation

/// A sentence with amounts in it, each kept apart from the words: "You
/// saved 4.210 € and markets added 1.200 €." While amounts are hidden
/// (UI.md, "Privacy"), ``AmountSentenceText`` draws a placeholder in place of
/// each amount and the words stay readable. Compiled into the app and the
/// widgets.
///
///     let saved: AmountSentence = "You saved \(amount: AmountFormat.amount(value, currency: currency))."
///     AmountSentenceText(saved)
struct AmountSentence: Hashable, Sendable {
    /// A piece of the sentence: words, or an amount.
    enum Part: Hashable, Sendable {
        case words(String)
        case amount(String)
    }

    /// Its pieces in order; words next to each other are one piece.
    private(set) var parts: [Part] = []

    init() {}

    /// Words with no amount in them.
    init(_ words: String) {
        append(words: words)
    }

    /// The sentence made of `parts`.
    init(parts: [Part]) {
        for part in parts {
            append(part)
        }
    }

    /// An amount on its own: "312.480 €".
    static func amount(_ text: String) -> AmountSentence {
        AmountSentence(parts: [.amount(text)])
    }

    /// What VoiceOver reads in place of an amount while amounts are hidden.
    static let hiddenAmount = "amount hidden"

    /// The sentence as it reads with its amounts.
    var text: String {
        parts.map { part in
            switch part {
            case .words(let words): words
            case .amount(let amount): amount
            }
        }.joined()
    }

    /// The sentence as VoiceOver reads it: with its amounts, or while
    /// amounts are hidden with "amount hidden" in place of each.
    func spoken(hidesAmounts: Bool) -> String {
        guard hidesAmounts else { return text }
        return parts.map { part in
            switch part {
            case .words(let words): words
            case .amount: Self.hiddenAmount
            }
        }.joined()
    }

    /// Whether it has an amount in it.
    var hasAmounts: Bool {
        parts.contains { if case .amount = $0 { true } else { false } }
    }

    var isEmpty: Bool {
        parts.isEmpty
    }

    mutating func append(words: String) {
        append(.words(words))
    }

    mutating func append(amount: String) {
        append(.amount(amount))
    }

    mutating func append(_ sentence: AmountSentence) {
        for part in sentence.parts {
            append(part)
        }
    }

    private mutating func append(_ part: Part) {
        switch part {
        case .words(let words):
            guard !words.isEmpty else { return }
            if case .words(let before) = parts.last {
                parts[parts.count - 1] = .words(before + words)
            } else {
                parts.append(part)
            }
        case .amount:
            parts.append(part)
        }
    }

    static func + (lhs: AmountSentence, rhs: AmountSentence) -> AmountSentence {
        var sentence = lhs
        sentence.append(rhs)
        return sentence
    }

    static func += (lhs: inout AmountSentence, rhs: AmountSentence) {
        lhs.append(rhs)
    }

    /// The sentence with its first letter capitalized: "Typically by late 2028".
    var capitalizedFirst: AmountSentence {
        guard case .words(let first) = parts.first, let letter = first.first else { return self }
        var sentence = self
        sentence.parts[0] = .words(letter.uppercased() + first.dropFirst())
        return sentence
    }
}

extension AmountSentence: ExpressibleByStringInterpolation {
    init(stringLiteral value: String) {
        self.init(value)
    }

    init(stringInterpolation: StringInterpolation) {
        self = stringInterpolation.sentence
    }

    /// `"Passed \(amount: text)."`: words, amounts and other sentences.
    struct StringInterpolation: StringInterpolationProtocol {
        fileprivate var sentence = AmountSentence()

        init(literalCapacity: Int, interpolationCount: Int) {}

        mutating func appendLiteral(_ literal: String) {
            sentence.append(words: literal)
        }

        /// Words: a name, an age, a date, a percentage.
        mutating func appendInterpolation(_ value: some CustomStringConvertible) {
            sentence.append(words: value.description)
        }

        /// An amount, formatted.
        mutating func appendInterpolation(amount: String) {
            sentence.append(amount: amount)
        }

        /// Another sentence, its amounts kept.
        mutating func appendInterpolation(_ other: AmountSentence) {
            sentence.append(other)
        }
    }
}

extension Array where Element == AmountSentence {
    /// The sentences joined by `separator`: "4.210 € · typically by late 2028".
    func joined(separator: String) -> AmountSentence {
        var result = AmountSentence()
        for (index, sentence) in enumerated() {
            if index > 0 { result.append(words: separator) }
            result.append(sentence)
        }
        return result
    }

    /// The sentences as a list, as `Wording.list` writes one: "a, b and c".
    func listed() -> AmountSentence {
        guard let last else { return AmountSentence() }
        guard count > 1 else { return last }
        return Array(dropLast()).joined(separator: ", ") + " and " + last
    }
}
