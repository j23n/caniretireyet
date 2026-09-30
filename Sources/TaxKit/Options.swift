import Foundation

/// A value in a regime's, scheme's or system's options, or in a parameter
/// file. TaxKit's own JSON-like type (it doesn't depend on Model); numbers
/// are `Double` because the planner and tax systems work in floating point.
///
/// Library files write decimals as strings (`"0.0173"`), so the numeric
/// accessors also read numeric strings.
public enum OptionValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case list([OptionValue])
    case object([String: OptionValue])

    /// A number, or a string holding one.
    public var doubleValue: Double? {
        switch self {
        case .number(let value): value
        case .string(let string): Double(string)
        default: nil
        }
    }

    /// A whole number, or a string holding one.
    public var intValue: Int? {
        guard let value = doubleValue, value.rounded() == value, abs(value) < 1e15 else { return nil }
        return Int(value)
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { value } else { nil }
    }

    public var stringValue: String? {
        if case .string(let value) = self { value } else { nil }
    }

    public var listValue: [OptionValue]? {
        if case .list(let value) = self { value } else { nil }
    }

    public var objectValue: [String: OptionValue]? {
        if case .object(let value) = self { value } else { nil }
    }

    /// The member for `key`, when this is an object.
    public subscript(key: String) -> OptionValue? {
        objectValue?[key]
    }
}

extension OptionValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode([OptionValue].self) {
            self = .list(value)
        } else if let value = try? container.decode([String: OptionValue].self) {
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
        case .list(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

extension OptionValue: ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: OptionValue...) { self = .list(elements) }
    public init(dictionaryLiteral elements: (String, OptionValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

/// A set of options by key, e.g. a regime's options from the plan, with
/// typed accessors.
public struct OptionValues: Hashable, Sendable, ExpressibleByDictionaryLiteral {
    public var values: [String: OptionValue]

    public init(_ values: [String: OptionValue] = [:]) {
        self.values = values
    }

    public init(dictionaryLiteral elements: (String, OptionValue)...) {
        self.values = Dictionary(elements, uniquingKeysWith: { _, last in last })
    }

    public subscript(key: String) -> OptionValue? {
        get { values[key] }
        set { values[key] = newValue }
    }

    public func double(_ key: String) -> Double? { values[key]?.doubleValue }
    public func int(_ key: String) -> Int? { values[key]?.intValue }
    public func bool(_ key: String) -> Bool? { values[key]?.boolValue }
    public func string(_ key: String) -> String? { values[key]?.stringValue }

    /// These values, with each field's default filled in where the key is missing.
    public func withDefaults(from fields: [OptionField]) -> OptionValues {
        var result = self
        for field in fields where result.values[field.key] == nil {
            if let value = field.defaultValue { result.values[field.key] = value }
        }
        return result
    }

    public var isEmpty: Bool { values.isEmpty }
}

/// One option of a regime, scheme or system, described so the plan editor
/// can render it as a form field and validate it generically.
public struct OptionField: Hashable, Sendable {
    /// The key in the plan's `options` object, e.g. `coefficient`.
    public var key: String
    /// The form label, e.g. "Profitability coefficient".
    public var label: String
    public var kind: Kind
    /// Used when the plan doesn't set the option. `nil` with `isRequired`
    /// means the plan must set it.
    public var defaultValue: OptionValue?
    /// Whether the plan must set it (only meaningful without a default).
    public var isRequired: Bool
    /// Allowed numeric range, for numeric kinds.
    public var range: ClosedRange<Double>?
    /// A short explanation shown under the field.
    public var help: String?

    public init(key: String, label: String, kind: Kind, defaultValue: OptionValue? = nil, isRequired: Bool = false,
                range: ClosedRange<Double>? = nil, help: String? = nil) {
        self.key = key
        self.label = label
        self.kind = kind
        self.defaultValue = defaultValue
        self.isRequired = isRequired
        self.range = range
        self.help = help
    }

    /// What kind of value an option takes.
    public enum Kind: Hashable, Sendable {
        /// A fraction shown as a percentage: 0.0173 → 1.73%.
        case percent
        /// An amount in euros (today's euros unless the help says otherwise).
        case money
        case bool
        case int
        /// A calendar year, e.g. the year you moved.
        case year
        /// One of a fixed set of string values.
        case choice([Choice])
    }

    /// One allowed value of a `choice` option.
    public struct Choice: Hashable, Sendable {
        /// The value stored in the plan.
        public var value: String
        /// The label shown in the picker.
        public var label: String

        public init(value: String, label: String) {
            self.value = value
            self.label = label
        }
    }
}
