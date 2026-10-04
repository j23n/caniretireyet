import Foundation

extension PlanDebugReport {
    /// The full report as JSON: pretty-printed, keys sorted, so the same
    /// report always gives the same text. ``decode(json:)`` reads it back.
    public func json() throws -> String {
        String(decoding: try Self.encoder.encode(self), as: UTF8.self)
    }

    /// A report from ``json()``'s output.
    public static func decode(json: String) throws -> PlanDebugReport {
        try decoder.decode(PlanDebugReport.self, from: Data(json.utf8))
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return decoder
    }
}

/// Numbers and words as the debug report writes them, the same in every
/// locale: `,` for thousands, `.` for decimals.
enum PlanDebugFormat {
    /// A whole amount: `12,345`, `-310`.
    static func money(_ value: Double) -> String {
        guard value.isFinite else { return "?" }
        let rounded = value.rounded()
        guard abs(rounded) < 1e15 else { return String(format: "%.0f", rounded) }
        let whole = Int64(rounded)
        let digits = String(abs(whole))
        var grouped = ""
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { grouped.append(",") }
            grouped.append(digit)
        }
        return (whole < 0 ? "-" : "") + grouped
    }

    /// A fraction as a percentage: `4.5%`.
    static func percent(_ value: Double, places: Int = 1) -> String {
        guard value.isFinite else { return "?" }
        var text = String(format: "%.\(places)f", value * 100)
        if Double(text) == 0 { text = String(format: "%.\(places)f", 0.0) }
        return text + "%"
    }

    /// A return with its sign: `+12.3%`, `-4.0%`.
    static func signedPercent(_ value: Double) -> String {
        let text = percent(value)
        return text.hasPrefix("-") || Double(text.dropLast()) == 0 ? text : "+" + text
    }

    /// A number without needless decimals: `20`, `13.5`, `0.25`.
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "?" }
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        var text = String(format: "%.4f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// `13.5 times`.
    static func times(_ value: Double) -> String {
        "\(String(format: "%.1f", value)) times"
    }

    /// "Crypto", "Real estate".
    static func className(_ raw: String) -> String {
        var words = ""
        for character in raw {
            if character.isUppercase, !words.isEmpty { words += " " + character.lowercased() } else { words.append(character) }
        }
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// `a`, `a and b`, `a, b and c`.
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        default: items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }

    /// The rows of a long yearly table to show: every year when there are at
    /// most 25, else the first 10, the ones in `keep`, every age divisible by
    /// 5 and the last.
    static func shownRows(ages: [Int], keep: Set<Int>) -> [Int] {
        let count = ages.count
        guard count > 25 else { return Array(0..<count) }
        var shown = Set(0..<min(10, count))
        shown.formUnion(keep.filter { (0..<count).contains($0) })
        shown.insert(count - 1)
        for index in 0..<count where ages[index] % 5 == 0 { shown.insert(index) }
        return shown.sorted()
    }
}

/// A Markdown table, written row by row.
struct MarkdownTable {
    var header: [String]
    /// Columns aligned right (numbers).
    var right: Set<Int>
    var rows: [[String]] = []

    init(_ header: [String], right: Set<Int> = []) {
        self.header = header
        self.right = right
    }

    mutating func add(_ row: [String]) {
        rows.append(row)
    }

    /// Adds rows for `shown` of `count` items, with a `…` row where some are skipped.
    mutating func add(shown: [Int], _ row: (Int) -> [String]) {
        var previous: Int?
        for index in shown {
            if let previous, index > previous + 1 { rows.append(["…"] + Array(repeating: "", count: header.count - 1)) }
            rows.append(row(index))
            previous = index
        }
    }

    var lines: [String] {
        func line(_ cells: [String]) -> String {
            "| " + cells.map { $0.replacingOccurrences(of: "|", with: "\\|") }.joined(separator: " | ") + " |"
        }
        let rule = "|" + header.indices.map { right.contains($0) ? " ---: " : " --- " }.joined(separator: "|") + "|"
        return [line(header), rule] + rows.map { line($0 + Array(repeating: "", count: max(0, header.count - $0.count))) }
    }
}
