import Foundation
import Model
import TaxKit

/// Forms generated from `OptionField`s (TAXES.md: "Each regime's options
/// appear as a form generated from the regime's own description, so a new
/// regime needs no UI code"). The plan keeps options as `[String: JSONValue]`
/// in its file form: percentages and amounts as decimal strings (`"0.0173"`),
/// years and whole numbers as numbers, switches as booleans, choices as
/// strings. An empty field removes the key, so the default applies.
enum PlanOptionForm {
    /// What a text field holds after typing.
    enum Parsed: Hashable, Sendable {
        /// The field is empty: the option is removed and its default applies.
        case empty
        case value(JSONValue)
        /// Not a number of the right kind; the plan keeps its value.
        case invalid
    }

    // MARK: Reading

    /// A plan value as TaxKit sees it, for validation.
    static func optionValue(_ json: JSONValue) -> OptionValue {
        switch json {
        case .null: .null
        case .bool(let value): .bool(value)
        case .number(let value): .number(value.doubleValue)
        case .string(let value): .string(value)
        case .array(let values): .list(values.map(optionValue))
        case .object(let values): .object(values.mapValues(optionValue))
        }
    }

    static func optionValues(_ options: [String: JSONValue]) -> OptionValues {
        OptionValues(options.mapValues(optionValue))
    }

    /// The problems with `options` against `fields`, by key: missing required
    /// options, wrong types, numbers out of range, unknown keys.
    static func problems(_ options: [String: JSONValue], fields: [OptionField]) -> [String: OptionProblem] {
        var result: [String: OptionProblem] = [:]
        for problem in optionValues(options).problems(against: fields) where result[problem.key] == nil {
            result[problem.key] = problem
        }
        return result
    }

    /// The keys set in the plan that no field describes, e.g. from a newer app or a typo.
    static func unknownKeys(_ options: [String: JSONValue], fields: [OptionField]) -> [String] {
        let known = Set(fields.map(\.key))
        return options.keys.filter { !known.contains($0) }.sorted()
    }

    /// Whether a field takes typed text (numbers), rather than a switch or a picker.
    static func isTextField(_ kind: OptionField.Kind) -> Bool {
        switch kind {
        case .percent, .money, .int, .year: true
        case .bool, .choice: false
        }
    }

    /// The text a number field shows for `value`: a percentage ×100 ("1,73"),
    /// an amount or a whole number as typed.
    static func text(for value: JSONValue?, kind: OptionField.Kind, locale: Locale = .current) -> String {
        guard let number = value?.decimalValue else { return value?.stringValue ?? "" }
        switch kind {
        case .percent: return AmountInput.text(for: number * 100, maxDigits: 4, locale: locale)
        case .int, .year: return number.fileString
        default: return AmountInput.text(for: number, maxDigits: 2, locale: locale)
        }
    }

    /// The prompt of an empty field: the default value, e.g. "1,73 (default)".
    static func placeholder(for field: OptionField, locale: Locale = .current) -> String {
        guard let value = field.defaultValue else { return field.isRequired ? "Required" : "" }
        switch value {
        case .number(let number):
            let decimal = Decimal(string: String(number)) ?? 0
            let json = JSONValue.number(decimal)
            let unit = field.kind == .percent ? " %" : ""
            return text(for: json, kind: field.kind, locale: locale) + unit
        case .string(let string):
            return string
        case .bool(let flag):
            return flag ? "On" : "Off"
        default:
            return ""
        }
    }

    /// Reads typed text for a field of `kind`.
    static func parse(_ text: String, kind: OptionField.Kind, locale: Locale = .current) -> Parsed {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        guard let number = AmountInput.decimal(from: trimmed, locale: locale) else { return .invalid }
        switch kind {
        case .percent:
            return .value(.string((number / 100).fileString))
        case .money:
            return .value(.string(number.fileString))
        case .int, .year:
            guard let whole = Int(number.fileString) else { return .invalid }
            return .value(.number(Decimal(whole)))
        case .bool, .choice:
            return .invalid
        }
    }

    // MARK: Writing

    /// `options` with `key` set to `value`, or removed for `nil`.
    static func setting(_ key: String, to value: JSONValue?, in options: [String: JSONValue]) -> [String: JSONValue] {
        var options = options
        options[key] = value
        return options
    }

    /// `options` after typing `text` into the field for `field`; unchanged if
    /// the text isn't valid.
    static func applying(_ text: String, to field: OptionField, in options: [String: JSONValue],
                         locale: Locale = .current) -> [String: JSONValue] {
        switch parse(text, kind: field.kind, locale: locale) {
        case .empty: setting(field.key, to: nil, in: options)
        case .value(let value): setting(field.key, to: value, in: options)
        case .invalid: options
        }
    }

    /// A switch's state: the plan's value, else the default.
    static func bool(_ field: OptionField, in options: [String: JSONValue]) -> Bool {
        options[field.key]?.boolValue ?? field.defaultValue?.boolValue ?? false
    }

    /// A picker's selection: the plan's value, else the default.
    static func choice(_ field: OptionField, in options: [String: JSONValue]) -> String? {
        options[field.key]?.stringValue ?? field.defaultValue?.stringValue
    }

    /// A choice field's allowed values.
    static func choices(_ field: OptionField) -> [OptionField.Choice] {
        if case .choice(let choices) = field.kind { choices } else { [] }
    }

    /// Keeps only the options `fields` describe that are still valid for a
    /// newly chosen regime or scheme, so switching doesn't leave stale keys.
    static func carryOver(_ options: [String: JSONValue], to fields: [OptionField]) -> [String: JSONValue] {
        let keys = Set(fields.map(\.key))
        return options.filter { keys.contains($0.key) }
    }
}
