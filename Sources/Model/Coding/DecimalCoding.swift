import Foundation

// Decimals are written to library files as strings ("1234.56") and read from
// either a string or a JSON number. Neither direction goes through binary
// floating point.

extension Decimal {
    /// Parses a decimal as written in library files: an optional minus sign,
    /// digits, an optional fraction and an optional exponent (`"-1234.56"`,
    /// `"0.4215"`, `"1e3"`). Anything else, including grouping separators,
    /// a leading `+`, surrounding spaces or a trailing unit, returns `nil`.
    public init?(fileString string: String) {
        guard Self.isPlainDecimal(string),
              let value = Decimal(string: string, locale: Self.posixLocale)
        else { return nil }
        self = value
    }

    /// The shortest exact decimal string for this value, as written to library
    /// files: `"1500"`, `"0.1"`, `"-310.2"`. There is no exponent and no
    /// grouping, and the decimal separator is always `.`.
    ///
    /// Trailing fractional zeros are not kept: `"1500.00"` reads back as the
    /// same value and is written as `"1500"`.
    public var fileString: String {
        description
    }

    /// A decimal from a string known at compile time, e.g. a documented
    /// default. Traps if the string isn't a plain decimal.
    static func exactly(_ string: String) -> Decimal {
        guard let value = Decimal(fileString: string) else { preconditionFailure("Invalid decimal \"\(string)\"") }
        return value
    }

    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    /// `-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?`
    private static func isPlainDecimal(_ string: String) -> Bool {
        var bytes = Substring(string).utf8[...]
        func digits() -> Bool {
            let start = bytes.startIndex
            while let byte = bytes.first, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) {
                bytes = bytes.dropFirst()
            }
            return bytes.startIndex != start
        }
        if bytes.first == UInt8(ascii: "-") { bytes = bytes.dropFirst() }
        guard digits() else { return false }
        if bytes.first == UInt8(ascii: ".") {
            bytes = bytes.dropFirst()
            guard digits() else { return false }
        }
        if bytes.first == UInt8(ascii: "e") || bytes.first == UInt8(ascii: "E") {
            bytes = bytes.dropFirst()
            if bytes.first == UInt8(ascii: "-") || bytes.first == UInt8(ascii: "+") {
                bytes = bytes.dropFirst()
            }
            guard digits() else { return false }
        }
        return bytes.isEmpty
    }
}

extension KeyedDecodingContainer {
    /// Decodes a decimal written as a string (`"1234.56"`) or as a JSON number
    /// (`1234.56`), exactly.
    public func decodeDecimal(forKey key: Key) throws -> Decimal {
        if let string = try? decode(String.self, forKey: key) {
            guard let value = Decimal(fileString: string) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key, in: self,
                    debugDescription: "Expected a decimal such as \"1234.56\", found \"\(string)\".")
            }
            return value
        }
        return try decode(Decimal.self, forKey: key)
    }

    /// Like ``decodeDecimal(forKey:)``, but returns `nil` when the key is
    /// absent or `null`.
    public func decodeDecimalIfPresent(forKey key: Key) throws -> Decimal? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        return try decodeDecimal(forKey: key)
    }
}

extension KeyedEncodingContainer {
    /// Encodes a decimal as a string in its shortest exact form (`"1234.56"`).
    public mutating func encodeDecimal(_ value: Decimal, forKey key: Key) throws {
        guard value.isFinite else {
            throw EncodingError.invalidValue(value, EncodingError.Context(
                codingPath: codingPath + [key], debugDescription: "Cannot write a non-finite decimal."))
        }
        try encode(value.fileString, forKey: key)
    }

    /// Encodes a decimal as a string, or nothing when it is `nil`.
    public mutating func encodeDecimalIfPresent(_ value: Decimal?, forKey key: Key) throws {
        if let value { try encodeDecimal(value, forKey: key) }
    }
}
