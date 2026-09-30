/// A value that is stored in JSON as a plain string: typed IDs, open enums,
/// and currency and country codes.
///
/// Conforming types are one-field structs around `rawValue`. They encode as a
/// bare JSON string, can be written as string literals, sort by their raw
/// value, and can be used as dictionary keys that encode as JSON object keys.
public protocol StringValue: RawRepresentable, Codable, Hashable, Comparable, Sendable,
    ExpressibleByStringLiteral, CustomStringConvertible, CodingKeyRepresentable
where RawValue == String {
    /// Wraps a raw string. Never fails: unknown values are kept as they are.
    init(rawValue: String)
}

extension StringValue {
    /// Wraps a raw string.
    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public var description: String { rawValue }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A "kind"-like field whose set of values can grow in later app versions.
///
/// Open enums are structs rather than Swift enums, so a value this version
/// doesn't know (written by a newer app, or by hand) still decodes and is
/// written back unchanged. Known values are static constants.
public protocol OpenEnum: StringValue {
    /// The values this version of the app knows, in display order.
    static var knownValues: [Self] { get }
}

extension OpenEnum {
    /// Whether this version of the app knows the value.
    public var isKnown: Bool { Self.knownValues.contains(self) }
}
