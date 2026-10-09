import Foundation
import Model

/// Numbers and words as the CLI prints them. Amounts use `,` for thousands
/// and `.` for decimals whatever the locale, so output is the same everywhere
/// and easy to parse.
enum Format {
    /// An amount with thousands separators and exactly `places` decimals:
    /// `1,234,567.89`, `-310.20`.
    static func amount(_ value: Decimal, places: Int = 2) -> String {
        let rounded = value.rounded(scale: places)
        let negative = rounded < 0
        let parts = (negative ? -rounded : rounded).fileString.split(separator: ".", omittingEmptySubsequences: false)
        let integer = String(parts[0])
        var fraction = parts.count > 1 ? String(parts[1]) : ""
        fraction += String(repeating: "0", count: max(0, places - fraction.count))
        var grouped = ""
        for (index, digit) in integer.enumerated() {
            if index > 0, (integer.count - index) % 3 == 0 { grouped.append(",") }
            grouped.append(digit)
        }
        return (negative ? "-" : "") + grouped + (places > 0 ? "." + fraction : "")
    }

    /// An amount with its sign: `+1,234.56`, `-310.20`, `0.00`.
    static func signed(_ value: Decimal, places: Int = 2) -> String {
        value.rounded(scale: places) > 0 ? "+" + amount(value, places: places) : amount(value, places: places)
    }

    /// A number exactly as written in library files, with thousands
    /// separators: `0.4215`, `146,250`.
    static func exact(_ value: Decimal) -> String {
        let text = value.fileString
        let fraction = text.split(separator: ".").dropFirst().first.map(\.count) ?? 0
        return amount(value, places: fraction)
    }

    /// A share as a percentage: `45.2%`; `–` when unknown.
    static func percent(_ share: Decimal?, places: Int = 1) -> String {
        guard let share else { return "–" }
        return amount(share * 100, places: places) + "%"
    }

    /// A share as a percentage with its sign: `+1.7%`, `-0.4%`.
    static func signedPercent(_ share: Decimal, places: Int = 1) -> String {
        signed(share * 100, places: places) + "%"
    }

    /// An amount for JSON output: a string in the file format, rounded to cents.
    static func json(_ value: Decimal, places: Int = 2) -> String {
        value.rounded(scale: places).fileString
    }

    /// `1 account`, `2 accounts`.
    static func count(_ count: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(count) \(count == 1 ? singular : plural ?? singular + "s")"
    }

    /// A list for a sentence: `a`, `a and b`, `a, b and c` (or `a or b`).
    static func list(_ items: [String], or: Bool = false) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        default: items.dropLast().joined(separator: ", ") + (or ? " or " : " and ") + items[items.count - 1]
        }
    }

    /// A delimiter as a reader sees it: `";"`, `tab`.
    static func delimiter(_ delimiter: String) -> String {
        delimiter == "\t" ? "tab" : "\"\(delimiter)\""
    }
}

/// A plain-text table: columns separated by two spaces, numbers aligned
/// right, trailing spaces trimmed.
struct TextTable {
    enum Alignment {
        case left, right
    }

    struct Column {
        var title: String
        var alignment: Alignment

        static func left(_ title: String) -> Column { Column(title: title, alignment: .left) }
        static func right(_ title: String) -> Column { Column(title: title, alignment: .right) }
    }

    var columns: [Column]
    var rows: [[String]] = []
    /// Whether the column titles are printed.
    var showsHeader = true

    init(_ columns: [Column], showsHeader: Bool = true) {
        self.columns = columns
        self.showsHeader = showsHeader
    }

    mutating func add(_ row: [String]) {
        rows.append(row)
    }

    /// The table's lines, each indented by `indent` spaces.
    func lines(indent: Int = 2) -> [String] {
        let all = (showsHeader ? [columns.map(\.title)] : []) + rows
        let widths = columns.indices.map { index in
            all.map { index < $0.count ? $0[index].count : 0 }.max() ?? 0
        }
        let prefix = String(repeating: " ", count: indent)
        return all.map { row in
            let cells = columns.indices.map { index -> String in
                let text = index < row.count ? row[index] : ""
                let padding = String(repeating: " ", count: max(0, widths[index] - text.count))
                return columns[index].alignment == .right ? padding + text : text + padding
            }
            var line = prefix + cells.joined(separator: "  ")
            while line.last == " " { line.removeLast() }
            return line
        }
    }
}

/// Comma-separated values, quoted where needed (RFC 4180).
enum CSV {
    static func line(_ fields: [String]) -> String {
        fields.map { field in
            guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }.joined(separator: ",")
    }
}

/// JSON output: pretty-printed with sorted keys, amounts as strings.
enum JSONOutput {
    static func string(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

/// What a command prints: lines of text, or with `--json` its JSON.
protocol CommandReport {
    associatedtype JSON: Encodable
    func lines() -> [String]
    var json: JSON { get }
}

extension Console {
    /// Prints `report` as text, or with `json` as JSON.
    func print(_ report: some CommandReport, json: Bool) throws {
        if json {
            print(try JSONOutput.string(report.json))
        } else {
            print(lines: report.lines())
        }
    }
}
