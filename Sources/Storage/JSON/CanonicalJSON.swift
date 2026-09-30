import Foundation
import Model

/// The library's JSON layout: the same data always gives the same bytes, so
/// a file only changes when its data does, and diffs show exactly which
/// records changed.
///
/// - UTF-8, two-space indentation, a trailing newline, keys sorted by their
///   Unicode code points. Non-ASCII text is written as is; only `"`, `\` and
///   control characters are escaped.
/// - Numbers in their shortest exact form. (The model writes amounts as
///   strings; numbers are counts, ages, years and free-form options.)
/// - A list or object is kept on one line (`{ "a": "1", "b": 2 }`,
///   `["x", "y"]`) when the whole line, including indentation, key and
///   trailing comma, fits in ``lineWidth`` columns. Otherwise it is spread
///   over lines, one member or element per line, each laid out by the same
///   rule.
/// - Two exceptions are always spread out: the file's top-level object, and
///   lists of records directly inside it (`valuations`, `prices`, `work`,
///   `years`, …), which get one record per line.
public enum CanonicalJSON {
    /// The widest a line may be to keep a list or object on it, in Unicode
    /// characters.
    public static let lineWidth = 130

    /// The canonical text of a JSON value, with a trailing newline.
    public static func string(for value: JSONValue) -> String {
        var writer = Writer()
        writer.write(value, indent: 0, prefix: "", suffix: "", depth: 0)
        return writer.output
    }

    /// The canonical UTF-8 bytes of a JSON value, with a trailing newline.
    public static func data(for value: JSONValue) -> Data {
        Data(string(for: value).utf8)
    }

    /// The canonical bytes of a model value, as it encodes itself.
    public static func data(encoding value: some Encodable) throws -> Data {
        data(for: try json(encoding: value))
    }

    /// A model value as JSON, exactly as it encodes itself (decimals are
    /// strings; numbers stay exact).
    public static func json(encoding value: some Encodable) throws -> JSONValue {
        try parse(JSONEncoder().encode(value))
    }

    /// Parses JSON text strictly, reading numbers exactly. Throws
    /// ``JSONSyntaxError`` with the line and column of the problem.
    public static func parse(_ data: Data) throws(JSONSyntaxError) -> JSONValue {
        try JSONParser.parse(data)
    }

    /// `true` when `data` is already in canonical form.
    public static func isCanonical(_ data: Data) -> Bool {
        guard let value = try? parse(data) else { return false }
        return self.data(for: value) == data
    }
}

// MARK: - Writer

private struct Writer {
    var output = ""

    mutating func write(_ value: JSONValue, indent: Int, prefix: String, suffix: String, depth: Int) {
        let spreadOut: Bool
        switch value {
        case .object(let members) where !members.isEmpty:
            spreadOut = depth == 0
        case .array(let elements) where !elements.isEmpty:
            spreadOut = depth == 0 || (depth == 1 && elements.contains { $0.objectValue != nil })
        default:
            appendLine(indent: indent, prefix + Self.scalarText(value) + suffix)
            return
        }
        if !spreadOut {
            let budget = CanonicalJSON.lineWidth - indent - Self.width(prefix) - Self.width(suffix)
            if let line = Self.inline(value, budget: budget) {
                appendLine(indent: indent, prefix + line + suffix)
                return
            }
        }
        switch value {
        case .object(let members):
            appendLine(indent: indent, prefix + "{")
            let keys = Self.sortedKeys(members)
            for (offset, key) in keys.enumerated() {
                write(members[key]!, indent: indent + 2, prefix: Self.quoted(key) + ": ",
                      suffix: offset < keys.count - 1 ? "," : "", depth: depth + 1)
            }
            appendLine(indent: indent, "}" + suffix)
        case .array(let elements):
            appendLine(indent: indent, prefix + "[")
            for (offset, element) in elements.enumerated() {
                write(element, indent: indent + 2, prefix: "", suffix: offset < elements.count - 1 ? "," : "",
                      depth: depth + 1)
            }
            appendLine(indent: indent, "]" + suffix)
        default:
            break
        }
    }

    mutating func appendLine(indent: Int, _ text: String) {
        output += String(repeating: " ", count: indent)
        output += text
        output += "\n"
    }

    /// The value on one line, or `nil` if it would be wider than `budget`.
    static func inline(_ value: JSONValue, budget: Int) -> String? {
        var text = ""
        var width = 0
        return appendInline(value, to: &text, width: &width, budget: budget) ? text : nil
    }

    private static func appendInline(_ value: JSONValue, to text: inout String, width: inout Int, budget: Int) -> Bool {
        func append(_ piece: String) -> Bool {
            text += piece
            width += Self.width(piece)
            return width <= budget
        }
        switch value {
        case .object(let members) where !members.isEmpty:
            guard append("{ ") else { return false }
            for (offset, key) in sortedKeys(members).enumerated() {
                guard append((offset > 0 ? ", " : "") + quoted(key) + ": "),
                      appendInline(members[key]!, to: &text, width: &width, budget: budget)
                else { return false }
            }
            return append(" }")
        case .array(let elements) where !elements.isEmpty:
            guard append("[") else { return false }
            for (offset, element) in elements.enumerated() {
                if offset > 0, !append(", ") { return false }
                guard appendInline(element, to: &text, width: &width, budget: budget) else { return false }
            }
            return append("]")
        default:
            return append(scalarText(value))
        }
    }

    /// Scalars, and empty lists and objects.
    static func scalarText(_ value: JSONValue) -> String {
        switch value {
        case .null: "null"
        case .bool(let flag): flag ? "true" : "false"
        case .number(let number): number.isFinite ? number.fileString : "null"
        case .string(let string): quoted(string)
        case .array: "[]"
        case .object: "{}"
        }
    }

    /// Keys in Unicode code point order (the same as UTF-8 byte order), which
    /// doesn't depend on locale or platform.
    static func sortedKeys(_ members: [String: JSONValue]) -> [String] {
        members.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }

    static func width(_ text: String) -> Int {
        text.unicodeScalars.count
    }

    static func quoted(_ string: String) -> String {
        var result = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case "\u{8}": result += "\\b"
            case "\u{C}": result += "\\f"
            case _ where scalar.value < 0x20:
                let hex = String(scalar.value, radix: 16)
                result += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }
}
