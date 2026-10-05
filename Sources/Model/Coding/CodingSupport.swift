/// A coding key for JSON objects whose keys aren't fixed, such as free-form
/// `options`, asset mixes and tax details.
public struct AnyCodingKey: CodingKey, Hashable, Sendable {
    public var stringValue: String
    public var intValue: Int?

    public init(_ string: String) {
        self.stringValue = string
        self.intValue = nil
    }

    public init(stringValue: String) {
        self.init(stringValue)
    }

    public init(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

/// A type stored as a JSON object whose keys this app version knows.
///
/// Every file's top-level type and every record type in a list conforms, as
/// do the nested objects with fixed keys. When Storage rewrites a file it
/// keeps the keys that aren't in `knownKeys`, so data written by a newer app
/// or added by hand survives. Types that keep free-form keys themselves
/// (in a `[String: JSONValue]`) don't conform.
public protocol KnownKeysProviding {
    /// The JSON keys this type reads and writes.
    static var knownKeys: Set<String> { get }
}

extension KeyedDecodingContainer {
    /// Decodes an array that may be absent, returning an empty array then.
    func decodeArray<T: Decodable>(_ type: [T].Type, forKey key: Key) throws -> [T] {
        try decodeIfPresent(type, forKey: key) ?? []
    }

    /// Decodes a free-form object that may be absent, returning an empty one then.
    func decodeObject(forKey key: Key) throws -> [String: JSONValue] {
        try decodeIfPresent([String: JSONValue].self, forKey: key) ?? [:]
    }
}

extension KeyedEncodingContainer {
    /// Encodes a collection only when it isn't empty, so files stay minimal.
    mutating func encodeIfNotEmpty<T: Encodable & Collection>(_ value: T, forKey key: Key) throws {
        if !value.isEmpty { try encode(value, forKey: key) }
    }
}
