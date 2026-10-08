import Foundation

/// Any JSON value. Numbers are held as `Decimal`, so they round-trip exactly.
///
/// Used for free-form data: the plan copy inside a baseline, and by Storage
/// to keep keys this app version doesn't know.
public enum JSONValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Decimal)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

// MARK: - Accessors

extension JSONValue {
    public var isNull: Bool { self == .null }

    public var stringValue: String? {
        if case .string(let value) = self { value } else { nil }
    }

    /// The value as a decimal: a JSON number, or a string holding a decimal
    /// (`"0.0173"`), since the library writes decimals as strings.
    public var decimalValue: Decimal? {
        switch self {
        case .number(let value): value
        case .string(let string): Decimal(fileString: string)
        default: nil
        }
    }

    /// The value as an integer, when it is a whole number (or a string holding one).
    public var intValue: Int? {
        guard let decimal = decimalValue, decimal == decimal.rounded(scale: 0) else { return nil }
        return Int(decimal.fileString)
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { value } else { nil }
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { value } else { nil }
    }

    /// The member for `key`, when this is an object.
    public subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    /// The element at `index`, when this is an array and the index is valid.
    public subscript(index: Int) -> JSONValue? {
        guard let array = arrayValue, array.indices.contains(index) else { return nil }
        return array[index]
    }
}

extension Decimal {
    /// Rounds to `scale` fractional digits, half away from zero.
    func rounded(scale: Int) -> Decimal {
        var input = self
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, .plain)
        return result
    }
}

// MARK: - Converting to and from Codable types

extension JSONValue {
    /// The JSON representation of an encodable value, as the model writes it
    /// (decimals as strings, dates as `"YYYY-MM-DD"`).
    public init(encoding value: some Encodable) throws {
        let data = try JSONEncoder().encode(value)
        self = try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Decodes a model type from this JSON value.
    public func decode<T: Decodable>(as type: T.Type = T.self) throws -> T {
        let data = try JSONEncoder().encode(self)
        return try JSONDecoder().decode(type, from: data)
    }
}

// MARK: - Codable

extension JSONValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Decimal.self) {
            self = .number(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a JSON value.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

// MARK: - Literals

extension JSONValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(nilLiteral: ()) { self = .null }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(Decimal(value)) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}
