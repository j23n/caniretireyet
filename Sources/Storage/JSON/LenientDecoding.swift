import Foundation
import Model

/// Decodes model types from hand-editable files, forgivingly: a JSON number
/// where the model expects text (`"name": 2026`) is read as that text, and
/// a whole number written as text where the model expects a whole number
/// (`"endAge": "95"`) is read as that number. The file is left as it is;
/// the next write puts the value in its usual form.
enum LenientDecoding {
    /// Decodes `type` from a parsed file or record. `data` is the file's
    /// text, when at hand, to skip re-encoding; `location` is where `json`
    /// is in its file (`"valuations[2]"`), for error messages.
    static func decode<T: Decodable>(_ type: T.Type, from json: JSONValue, data: Data? = nil,
                                     location: String = "") throws -> T {
        var json = json
        var input = data ?? CanonicalJSON.data(for: json)
        for _ in 0..<10_000 {
            do {
                return try JSONDecoder().decode(T.self, from: input)
            } catch let error as DecodingError {
                guard let repaired = json.repairing(error) else {
                    throw DecodingProblem(error: error, json: json, location: location)
                }
                json = repaired
                input = CanonicalJSON.data(for: json)
            }
        }
        throw DecodingProblem(message: "Too many values of the wrong type.")
    }

    /// Whether `json` decodes as `type`.
    static func decodes<T: Decodable>(_ type: T.Type, from json: JSONValue) -> Bool {
        (try? decode(type, from: json)) != nil
    }
}

/// Why a file or record couldn't be decoded, in words for the person who
/// will fix it by hand: where (`valuations[2].balance`) and what is wrong.
struct DecodingProblem: Error, CustomStringConvertible {
    var message: String

    init(message: String) {
        self.message = message
    }

    init(error: DecodingError, json: JSONValue, location: String = "") {
        func located(_ path: [any CodingKey], _ message: String) -> String {
            let place = Self.pathText(path, after: location)
            guard !place.isEmpty else { return message.prefix(1).uppercased() + message.dropFirst() }
            return "\(place): \(message)"
        }
        switch error {
        case .typeMismatch(let type, let context):
            let found = json.value(atCodingPath: context.codingPath)
            message = located(context.codingPath, "expected \(Self.describe(type)), found \(Self.describe(found)).")
        case .valueNotFound(let type, let context):
            message = located(context.codingPath, "expected \(Self.describe(type)), found null.")
        case .keyNotFound(let key, let context):
            message = located(context.codingPath, "\"\(key.stringValue)\" is missing.")
        case .dataCorrupted(let context):
            message = located(context.codingPath, context.debugDescription)
        @unknown default:
            message = "\(error)"
        }
    }

    var description: String { message }

    /// `valuations[2].balance`: the coding path, appended to `location`.
    static func pathText(_ path: [any CodingKey], after location: String = "") -> String {
        var text = location
        for key in path {
            if let index = key.intValue, key.stringValue.hasPrefix("Index ") || key.stringValue == String(index) {
                text += "[\(index)]"
            } else {
                text += text.isEmpty ? key.stringValue : "." + key.stringValue
            }
        }
        return text
    }

    private static func describe(_ type: Any.Type) -> String {
        let name = String(describing: type)
        switch name {
        case "String": return "text"
        case "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64":
            return "a whole number"
        case "Double", "Float", "Decimal": return "a number"
        case "Bool": return "true or false"
        default:
            if name.hasPrefix("Array<") { return "a list" }
            if name.hasPrefix("Dictionary<") { return "an object" }
            return name
        }
    }

    private static func describe(_ value: JSONValue?) -> String {
        switch value {
        case nil: return "nothing"
        case .null: return "null"
        case .bool(let flag): return flag ? "true" : "false"
        case .number(let number): return "the number \(number.fileString)"
        case .string(let string):
            let shown = string.count > 40 ? String(string.prefix(40)) + "…" : string
            return "\"\(shown)\""
        case .array: return "a list"
        case .object: return "an object"
        }
    }
}

extension JSONValue {
    /// The value at a decoder's coding path, if there is one.
    func value(atCodingPath path: [any CodingKey]) -> JSONValue? {
        var current = self
        for key in path {
            guard let next = current.child(for: key) else { return nil }
            current = next
        }
        return current
    }

    private func child(for key: any CodingKey) -> JSONValue? {
        switch self {
        case .object(let members): members[key.stringValue]
        case .array(let elements):
            key.intValue.flatMap { elements.indices.contains($0) ? elements[$0] : nil }
        default: nil
        }
    }

    /// This value with `transform` applied at `path`, or `nil` if the path
    /// doesn't exist or `transform` returns `nil`.
    func replacing(atCodingPath path: ArraySlice<any CodingKey>, _ transform: (JSONValue) -> JSONValue?) -> JSONValue? {
        guard let key = path.first else { return transform(self) }
        switch self {
        case .object(var members):
            guard let child = members[key.stringValue],
                  let replaced = child.replacing(atCodingPath: path.dropFirst(), transform) else { return nil }
            members[key.stringValue] = replaced
            return .object(members)
        case .array(var elements):
            guard let index = key.intValue, elements.indices.contains(index),
                  let replaced = elements[index].replacing(atCodingPath: path.dropFirst(), transform) else { return nil }
            elements[index] = replaced
            return .array(elements)
        default:
            return nil
        }
    }

    /// This value with the mismatch behind `error` repaired, if it is one
    /// that is accepted: a number where text is expected, or a whole number
    /// written as text where a whole number is expected.
    fileprivate func repairing(_ error: DecodingError) -> JSONValue? {
        guard case .typeMismatch(let expected, let context) = error else { return nil }
        let wantsText = expected == String.self
        let wantsInteger = expected == Int.self
        guard wantsText || wantsInteger else { return nil }
        return replacing(atCodingPath: context.codingPath[...]) { found in
            switch found {
            case .number(let number) where wantsText:
                return .string(number.fileString)
            case .string(let string) where wantsInteger:
                guard let number = Decimal(fileString: string), JSONValue.number(number).intValue != nil else { return nil }
                return .number(number)
            default:
                return nil
            }
        }
    }
}
