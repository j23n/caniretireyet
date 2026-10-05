import Foundation
import Model
import Storage

/// A small JSON Schema (draft 2020-12) validator for the tests, covering the
/// keywords the schemas in docs/schema use: `$ref` (to a `$defs` entry of
/// the same file or of another file in the folder), `type`, `enum`, `const`,
/// `pattern`, `minimum`, `maximum`, `properties`, `required`,
/// `additionalProperties`, `propertyNames`, `items`, `anyOf` and `oneOf`.
/// Annotations (`title`, `description`, `$comment`, `$schema`) are ignored.
///
/// In strict mode, an object member that a schema with `properties` doesn't
/// declare (and has no `additionalProperties` for) is reported: the app
/// keeps unknown keys, so the schemas allow them, but the example library
/// and what the app writes should have none.
struct JSONSchemaValidator {
    /// The schemas by file name, e.g. `plan.schema.json`.
    let schemas: [String: JSONValue]

    /// The folder of schemas, docs/schema.
    static var folder: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("docs/schema")
    }

    init(folder: URL = Self.folder) throws {
        var schemas: [String: JSONValue] = [:]
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasSuffix(".schema.json") }
        for name in names {
            schemas[name] = try CanonicalJSON.parse(Data(contentsOf: folder.appendingPathComponent(name)))
        }
        self.schemas = schemas
    }

    /// The problems with `value` against the schema in `file`, each as
    /// "path: what's wrong"; empty when it's valid.
    func validate(_ value: JSONValue, against file: String, strict: Bool = true) -> [String] {
        guard let schema = schemas[file] else { return ["No schema \(file)"] }
        var problems: [String] = []
        check(value, schema, file: file, path: "$", strict: strict, problems: &problems)
        return problems
    }

    /// Every `$ref` in every schema that doesn't resolve.
    func unresolvedReferences() -> [String] {
        var unresolved: [String] = []
        func walk(_ value: JSONValue, file: String) {
            switch value {
            case .object(let members):
                if let ref = members["$ref"]?.stringValue, resolve(ref, from: file) == nil {
                    unresolved.append("\(file): \(ref)")
                }
                members.values.forEach { walk($0, file: file) }
            case .array(let items):
                items.forEach { walk($0, file: file) }
            default:
                break
            }
        }
        for (file, schema) in schemas { walk(schema, file: file) }
        return unresolved.sorted()
    }

    /// The schema a `$ref` points at, and the file it's in.
    func resolve(_ ref: String, from file: String) -> (schema: JSONValue, file: String)? {
        let parts = ref.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let target = parts[0].isEmpty ? file : parts[0]
        guard var node = schemas[target] else { return nil }
        let pointer = parts.count > 1 ? parts[1] : ""
        for token in pointer.split(separator: "/").map(String.init) {
            let key = token.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
            guard let next = node[key] else { return nil }
            node = next
        }
        return (node, target)
    }

    private func check(_ value: JSONValue, _ schema: JSONValue, file: String, path: String, strict: Bool,
                       problems: inout [String]) {
        guard case .object(let keywords) = schema else {
            if schema == .bool(false) { problems.append("\(path): not allowed") }
            return
        }
        if let ref = keywords["$ref"]?.stringValue {
            if let (target, targetFile) = resolve(ref, from: file) {
                check(value, target, file: targetFile, path: path, strict: strict, problems: &problems)
            } else {
                problems.append("\(path): unresolved $ref \(ref)")
            }
        }
        if let type = keywords["type"] {
            let types = type.arrayValue?.compactMap(\.stringValue) ?? [type.stringValue ?? ""]
            if !types.contains(where: { Self.has(value, type: $0) }) {
                problems.append("\(path): expected \(types.joined(separator: " or ")), found \(Self.describe(value))")
                return
            }
        }
        if let options = keywords["enum"]?.arrayValue, !options.contains(value) {
            problems.append("\(path): \(Self.describe(value)) isn't one of \(options.map(Self.describe))")
        }
        if let constant = keywords["const"], constant != value {
            problems.append("\(path): expected \(Self.describe(constant)), found \(Self.describe(value))")
        }
        if let pattern = keywords["pattern"]?.stringValue, case .string(let string) = value,
           string.range(of: pattern, options: .regularExpression) == nil {
            problems.append("\(path): \"\(string)\" doesn't match \(pattern)")
        }
        if case .number(let number) = value {
            if let minimum = keywords["minimum"]?.decimalValue, number < minimum {
                problems.append("\(path): \(number) is below \(minimum)")
            }
            if let maximum = keywords["maximum"]?.decimalValue, number > maximum {
                problems.append("\(path): \(number) is above \(maximum)")
            }
        }
        if case .object(let members) = value {
            checkObject(members, keywords, file: file, path: path, strict: strict, problems: &problems)
        }
        if case .array(let items) = value, let itemSchema = keywords["items"] {
            for (index, item) in items.enumerated() {
                check(item, itemSchema, file: file, path: "\(path)[\(index)]", strict: strict, problems: &problems)
            }
        }
        if let options = keywords["anyOf"]?.arrayValue {
            let results = options.map { option in
                var found: [String] = []
                check(value, option, file: file, path: path, strict: strict, problems: &found)
                return found
            }
            if !results.contains(where: \.isEmpty) {
                problems.append("\(path): matches none of anyOf (\(results.flatMap { $0 }.joined(separator: "; ")))")
            }
        }
        if let options = keywords["oneOf"]?.arrayValue {
            let matches = options.filter { option in
                var found: [String] = []
                check(value, option, file: file, path: path, strict: strict, problems: &found)
                return found.isEmpty
            }.count
            if matches != 1 { problems.append("\(path): matches \(matches) of oneOf, not exactly one") }
        }
    }

    private func checkObject(_ members: [String: JSONValue], _ keywords: [String: JSONValue], file: String,
                             path: String, strict: Bool, problems: inout [String]) {
        for key in keywords["required"]?.arrayValue?.compactMap(\.stringValue) ?? [] where members[key] == nil {
            problems.append("\(path): \(key) is required")
        }
        let properties = keywords["properties"]?.objectValue ?? [:]
        for (key, member) in members.sorted(by: { $0.key < $1.key }) {
            let memberPath = "\(path).\(key)"
            if let names = keywords["propertyNames"] {
                check(.string(key), names, file: file, path: "\(path) key \(key)", strict: strict, problems: &problems)
            }
            if let schema = properties[key] {
                check(member, schema, file: file, path: memberPath, strict: strict, problems: &problems)
            } else if let additional = keywords["additionalProperties"] {
                check(member, additional, file: file, path: memberPath, strict: strict, problems: &problems)
            } else if strict, keywords["properties"] != nil {
                problems.append("\(memberPath): not in the schema")
            }
        }
    }

    private static func has(_ value: JSONValue, type: String) -> Bool {
        switch (type, value) {
        case ("null", .null), ("boolean", .bool), ("number", .number), ("string", .string), ("array", .array),
             ("object", .object):
            true
        case ("integer", .number(let number)):
            !number.fileString.contains(".")
        default:
            false
        }
    }

    private static func describe(_ value: JSONValue) -> String {
        switch value {
        case .null: "null"
        case .bool(let bool): String(bool)
        case .number(let number): number.fileString
        case .string(let string): "\"\(string)\""
        case .array: "an array"
        case .object: "an object"
        }
    }
}
