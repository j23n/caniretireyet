import Foundation
import Model

/// A JSON syntax error, with the line and column where it was found, so a
/// hand-edited file can be fixed quickly.
public struct JSONSyntaxError: Error, Hashable, Sendable, CustomStringConvertible {
    /// What is wrong, e.g. "Expected \",\" or \"}\" after a value in an object".
    public var message: String
    /// 1-based.
    public var line: Int
    /// 1-based, counted in Unicode characters.
    public var column: Int

    public init(message: String, line: Int, column: Int) {
        self.message = message
        self.line = line
        self.column = column
    }

    public var description: String {
        "Line \(line), column \(column): \(message)."
    }
}

/// A strict JSON parser (RFC 8259) that reads numbers exactly as `Decimal`
/// and reports errors with a line and column. A leading UTF-8 byte order
/// mark is skipped. When an object repeats a key, the last value wins.
enum JSONParser {
    static func parse(_ data: Data) throws(JSONSyntaxError) -> JSONValue {
        var parser = Parser(bytes: Array(data))
        return try parser.parseDocument()
    }
}

private struct Parser {
    let bytes: [UInt8]
    var index = 0

    static let maximumDepth = 256

    init(bytes: [UInt8]) {
        self.bytes = bytes
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { index = 3 }
    }

    mutating func parseDocument() throws(JSONSyntaxError) -> JSONValue {
        skipWhitespace()
        guard index < bytes.count else { throw error("The file is empty") }
        let value = try parseValue(depth: 0)
        skipWhitespace()
        guard index == bytes.count else { throw error("Unexpected \(describeCurrent()) after the end of the JSON value") }
        return value
    }

    // MARK: Values

    mutating func parseValue(depth: Int) throws(JSONSyntaxError) -> JSONValue {
        guard depth < Self.maximumDepth else { throw error("The JSON is nested too deeply") }
        guard index < bytes.count else { throw error("Unexpected end of file") }
        switch bytes[index] {
        case UInt8(ascii: "{"): return try parseObject(depth: depth)
        case UInt8(ascii: "["): return try parseArray(depth: depth)
        case UInt8(ascii: "\""): return .string(try parseString())
        case UInt8(ascii: "t"): return try parseLiteral("true", .bool(true))
        case UInt8(ascii: "f"): return try parseLiteral("false", .bool(false))
        case UInt8(ascii: "n"): return try parseLiteral("null", .null)
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return try parseNumber()
        default: throw error("Unexpected \(describeCurrent()); expected a value")
        }
    }

    mutating func parseObject(depth: Int) throws(JSONSyntaxError) -> JSONValue {
        index += 1  // {
        var members: [String: JSONValue] = [:]
        skipWhitespace()
        if consume(UInt8(ascii: "}")) { return .object(members) }
        while true {
            skipWhitespace()
            guard index < bytes.count else { throw error("Unexpected end of file inside an object") }
            guard bytes[index] == UInt8(ascii: "\"") else {
                if bytes[index] == UInt8(ascii: "}") { throw error("Trailing comma before \"}\"") }
                throw error("Expected a key in double quotes, found \(describeCurrent())")
            }
            let key = try parseString()
            skipWhitespace()
            guard consume(UInt8(ascii: ":")) else { throw error("Expected \":\" after the key \"\(key)\"") }
            skipWhitespace()
            members[key] = try parseValue(depth: depth + 1)
            skipWhitespace()
            if consume(UInt8(ascii: ",")) { continue }
            if consume(UInt8(ascii: "}")) { return .object(members) }
            throw error(index < bytes.count
                ? "Expected \",\" or \"}\" after a value in an object, found \(describeCurrent())"
                : "Unexpected end of file inside an object")
        }
    }

    mutating func parseArray(depth: Int) throws(JSONSyntaxError) -> JSONValue {
        index += 1  // [
        var elements: [JSONValue] = []
        skipWhitespace()
        if consume(UInt8(ascii: "]")) { return .array(elements) }
        while true {
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "]") { throw error("Trailing comma before \"]\"") }
            elements.append(try parseValue(depth: depth + 1))
            skipWhitespace()
            if consume(UInt8(ascii: ",")) { continue }
            if consume(UInt8(ascii: "]")) { return .array(elements) }
            throw error(index < bytes.count
                ? "Expected \",\" or \"]\" after a value in a list, found \(describeCurrent())"
                : "Unexpected end of file inside a list")
        }
    }

    mutating func parseLiteral(_ word: String, _ value: JSONValue) throws(JSONSyntaxError) -> JSONValue {
        let utf8 = Array(word.utf8)
        guard bytes[index...].starts(with: utf8) else { throw error("Unexpected \(describeCurrent()); expected a value") }
        index += utf8.count
        return value
    }

    /// `-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?`, read exactly.
    mutating func parseNumber() throws(JSONSyntaxError) -> JSONValue {
        let start = index
        _ = consume(UInt8(ascii: "-"))
        guard let first = current, isDigit(first) else { throw error("Expected a digit in a number") }
        if first == UInt8(ascii: "0") {
            index += 1
            if let next = current, isDigit(next) { throw error("A number can't start with 0 (write \"0.5\" or \"5\")") }
        } else {
            skipDigits()
        }
        if consume(UInt8(ascii: ".")) {
            guard let next = current, isDigit(next) else { throw error("Expected a digit after the decimal point") }
            skipDigits()
        }
        if let marker = current, marker == UInt8(ascii: "e") || marker == UInt8(ascii: "E") {
            index += 1
            if let sign = current, sign == UInt8(ascii: "+") || sign == UInt8(ascii: "-") { index += 1 }
            guard let next = current, isDigit(next) else { throw error("Expected a digit in the exponent") }
            skipDigits()
        }
        let text = String(decoding: bytes[start..<index], as: UTF8.self)
        guard let value = Decimal(fileString: text), value.isFinite else {
            index = start
            throw error("The number \(text) is out of range")
        }
        return .number(value)
    }

    mutating func parseString() throws(JSONSyntaxError) -> String {
        let quote = index
        index += 1  // "
        var result = ""
        var runStart = index
        while true {
            guard index < bytes.count else {
                index = quote
                throw error("This text has no closing double quote")
            }
            let byte = bytes[index]
            if byte == UInt8(ascii: "\"") {
                try appendRun(from: runStart, to: &result)
                index += 1
                return result
            }
            if byte == UInt8(ascii: "\\") {
                try appendRun(from: runStart, to: &result)
                try parseEscape(into: &result)
                runStart = index
                continue
            }
            if byte < 0x20 {
                throw error(byte == 0x0A
                    ? "Line break inside text (write \\n, or close the double quote)"
                    : "Control character inside text; escape it")
            }
            index += 1
        }
    }

    /// Appends the raw bytes `start..<index`, which must be valid UTF-8.
    func appendRun(from start: Int, to result: inout String) throws(JSONSyntaxError) {
        guard start < index else { return }
        guard let text = String(validating: bytes[start..<index], as: UTF8.self) else {
            throw errorAt(start, "The text isn't valid UTF-8")
        }
        result += text
    }

    mutating func parseEscape(into result: inout String) throws(JSONSyntaxError) {
        index += 1  // backslash
        guard let byte = current else { throw error("Unexpected end of file in an escape sequence") }
        index += 1
        switch byte {
        case UInt8(ascii: "\""): result.append("\"")
        case UInt8(ascii: "\\"): result.append("\\")
        case UInt8(ascii: "/"): result.append("/")
        case UInt8(ascii: "b"): result.append("\u{8}")
        case UInt8(ascii: "f"): result.append("\u{C}")
        case UInt8(ascii: "n"): result.append("\n")
        case UInt8(ascii: "r"): result.append("\r")
        case UInt8(ascii: "t"): result.append("\t")
        case UInt8(ascii: "u"):
            let high = try parseHex4()
            if (0xD800...0xDBFF).contains(high) {
                guard bytes[index...].starts(with: [UInt8(ascii: "\\"), UInt8(ascii: "u")]) else {
                    throw error("Unpaired surrogate in a \\u escape")
                }
                index += 2
                let low = try parseHex4()
                guard (0xDC00...0xDFFF).contains(low) else { throw error("Unpaired surrogate in a \\u escape") }
                let scalar = 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00)
                result.unicodeScalars.append(Unicode.Scalar(scalar)!)
            } else {
                guard let scalar = Unicode.Scalar(high) else { throw error("Unpaired surrogate in a \\u escape") }
                result.unicodeScalars.append(scalar)
            }
        default:
            index -= 2
            throw error("Unknown escape sequence \\\(String(decoding: [byte], as: UTF8.self))")
        }
    }

    mutating func parseHex4() throws(JSONSyntaxError) -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard let byte = current, let digit = hexValue(byte) else { throw error("Expected four hex digits after \\u") }
            value = value << 4 | digit
            index += 1
        }
        return value
    }

    // MARK: Helpers

    var current: UInt8? { index < bytes.count ? bytes[index] : nil }

    mutating func consume(_ byte: UInt8) -> Bool {
        guard current == byte else { return false }
        index += 1
        return true
    }

    mutating func skipWhitespace() {
        while let byte = current, byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 { index += 1 }
    }

    mutating func skipDigits() {
        while let byte = current, isDigit(byte) { index += 1 }
    }

    func isDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }

    func hexValue(_ byte: UInt8) -> UInt32? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): UInt32(byte - UInt8(ascii: "0"))
        case UInt8(ascii: "a")...UInt8(ascii: "f"): UInt32(byte - UInt8(ascii: "a") + 10)
        case UInt8(ascii: "A")...UInt8(ascii: "F"): UInt32(byte - UInt8(ascii: "A") + 10)
        default: nil
        }
    }

    /// The character at the current position, for messages: `"x"`, or "end of file".
    func describeCurrent() -> String {
        guard index < bytes.count else { return "end of file" }
        let end = min(bytes.count, index + 4)
        let character = String(decoding: bytes[index..<end], as: UTF8.self).first.map(String.init) ?? "?"
        return "\"\(character)\""
    }

    func error(_ message: String) -> JSONSyntaxError {
        errorAt(index, message)
    }

    /// An error at byte offset `offset`, with its line and column.
    func errorAt(_ offset: Int, _ message: String) -> JSONSyntaxError {
        var line = 1
        var column = 1
        let begin = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
        for byte in bytes[begin..<max(begin, min(offset, bytes.count))] {
            if byte == 0x0A {
                line += 1
                column = 1
            } else if byte & 0xC0 != 0x80 {
                column += 1
            }
        }
        return JSONSyntaxError(message: message, line: line, column: column)
    }
}
