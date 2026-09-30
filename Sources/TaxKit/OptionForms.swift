// Helpers for describing options as form fields and checking a plan's
// values against them, so regimes, schemes and systems declare their options
// once and get validation for free.

extension OptionField {
    /// A fraction shown as a percentage, by default between 0 and 1.
    public static func percent(_ key: String, _ label: String, default value: Double? = nil,
                               range: ClosedRange<Double>? = 0...1, required: Bool = false,
                               help: String? = nil) -> OptionField {
        OptionField(key: key, label: label, kind: .percent, defaultValue: value.map(OptionValue.number),
                    isRequired: required, range: range, help: help)
    }

    /// An amount in euros, by default not negative.
    public static func money(_ key: String, _ label: String, default value: Double? = nil,
                             range: ClosedRange<Double>? = 0...Double.greatestFiniteMagnitude,
                             required: Bool = false, help: String? = nil) -> OptionField {
        OptionField(key: key, label: label, kind: .money, defaultValue: value.map(OptionValue.number),
                    isRequired: required, range: range, help: help)
    }

    /// A whole number.
    public static func int(_ key: String, _ label: String, default value: Int? = nil,
                           range: ClosedRange<Double>? = nil, required: Bool = false,
                           help: String? = nil) -> OptionField {
        OptionField(key: key, label: label, kind: .int, defaultValue: value.map { .number(Double($0)) },
                    isRequired: required, range: range, help: help)
    }

    /// A calendar year.
    public static func year(_ key: String, _ label: String, default value: Int? = nil,
                            range: ClosedRange<Double>? = 1900...2200, required: Bool = false,
                            help: String? = nil) -> OptionField {
        OptionField(key: key, label: label, kind: .year, defaultValue: value.map { .number(Double($0)) },
                    isRequired: required, range: range, help: help)
    }

    /// A yes-or-no switch.
    public static func bool(_ key: String, _ label: String, default value: Bool? = false,
                            help: String? = nil) -> OptionField {
        OptionField(key: key, label: label, kind: .bool, defaultValue: value.map(OptionValue.bool), help: help)
    }

    /// One of a fixed set of values, given as `(value, label)` pairs.
    public static func choice(_ key: String, _ label: String, _ choices: [(value: String, label: String)],
                              default value: String? = nil, required: Bool = false,
                              help: String? = nil) -> OptionField {
        OptionField(key: key, label: label, kind: .choice(choices.map { Choice(value: $0.value, label: $0.label) }),
                    defaultValue: value.map(OptionValue.string), isRequired: required && value == nil, help: help)
    }

    /// The problem with `value` for this field, if any. `nil` is a missing value.
    public func problem(with value: OptionValue?) -> OptionProblem? {
        guard let value, value != .null else {
            return isRequired && defaultValue == nil
                ? OptionProblem(key: key, kind: .missing, message: "\(label) is required.") : nil
        }
        switch kind {
        case .percent, .money, .int, .year:
            guard let number = value.doubleValue else {
                return OptionProblem(key: key, kind: .wrongType, message: "\(label) must be a number.")
            }
            if kind == .int || kind == .year, value.intValue == nil {
                return OptionProblem(key: key, kind: .wrongType, message: "\(label) must be a whole number.")
            }
            if let range, !range.contains(number) {
                return OptionProblem(key: key, kind: .outOfRange, message: "\(label) must be between "
                                     + "\(Self.format(range.lowerBound, kind)) and \(Self.format(range.upperBound, kind)).")
            }
        case .bool:
            if value.boolValue == nil {
                return OptionProblem(key: key, kind: .wrongType, message: "\(label) must be true or false.")
            }
        case .choice(let choices):
            guard let string = value.stringValue, choices.contains(where: { $0.value == string }) else {
                let allowed = choices.map(\.value).joined(separator: ", ")
                return OptionProblem(key: key, kind: .invalidChoice, message: "\(label) must be one of: \(allowed).")
            }
        }
        return nil
    }

    private static func format(_ number: Double, _ kind: Kind) -> String {
        if number >= Double.greatestFiniteMagnitude { return "any amount" }
        if kind == .percent {
            let percent = (number * 10_000).rounded() / 100
            return percent == percent.rounded() ? "\(Int(percent))%" : "\(percent)%"
        }
        return number == number.rounded() && abs(number) < 1e15 ? "\(Int(number))" : "\(number)"
    }
}

/// A problem with one option value in a plan.
public struct OptionProblem: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        /// A required option without a default isn't set.
        case missing
        /// The value has the wrong type, e.g. text for a percentage.
        case wrongType
        /// A number outside the field's range.
        case outOfRange
        /// A value that isn't one of a choice's values.
        case invalidChoice
        /// A key no field describes, e.g. a typo.
        case unknownKey
    }

    public var key: String
    public var kind: Kind
    public var message: String

    public init(key: String, kind: Kind, message: String) {
        self.key = key
        self.kind = kind
        self.message = message
    }

    /// The problem as an issue: unknown keys are warnings, everything else
    /// errors. The code is `<prefix>.<kind>`, e.g. `it.options.missing`.
    public func issue(codePrefix: String, regime: String? = nil, year: Int? = nil) -> TaxIssue {
        TaxIssue(kind == .unknownKey ? .warning : .error, code: "\(codePrefix).\(kind.rawValue)",
                 message: message, year: year, regime: regime, option: key)
    }
}

extension OptionValues {
    /// Every problem with these values against `fields`: missing required
    /// options, wrong types, numbers out of range, invalid choices and keys
    /// no field describes. Sorted by key.
    public func problems(against fields: [OptionField]) -> [OptionProblem] {
        var problems = fields.compactMap { $0.problem(with: values[$0.key]) }
        let known = Set(fields.map(\.key))
        for key in values.keys where !known.contains(key) {
            problems.append(OptionProblem(key: key, kind: .unknownKey, message: "Unknown option \"\(key)\"."))
        }
        return problems.sorted { ($0.key, $0.kind.rawValue) < ($1.key, $1.kind.rawValue) }
    }

    /// ``problems(against:)`` as issues (see ``OptionProblem/issue(codePrefix:regime:year:)``).
    public func issues(against fields: [OptionField], codePrefix: String, regime: String? = nil,
                       year: Int? = nil) -> [TaxIssue] {
        problems(against: fields).map { $0.issue(codePrefix: codePrefix, regime: regime, year: year) }
    }

    /// The number for `key`, or `fallback` when it isn't set or isn't a number.
    public func double(_ key: String, default fallback: Double) -> Double {
        double(key) ?? fallback
    }

    /// The whole number for `key`, or `fallback`.
    public func int(_ key: String, default fallback: Int) -> Int {
        int(key) ?? fallback
    }

    /// The flag for `key`, or `fallback`.
    public func bool(_ key: String, default fallback: Bool) -> Bool {
        bool(key) ?? fallback
    }

    /// The string for `key`, or `fallback`.
    public func string(_ key: String, default fallback: String) -> String {
        string(key) ?? fallback
    }
}
