/// A value in a parameter file's JSON tree, with its dotted path, for reading
/// typed values with errors that say where the problem is:
///
///     let irpef = ParameterNode(set)["irpef"]
///     let schedule = try BracketSchedule(irpef)
///     let limit = try ParameterNode(set)["forfettario"]["revenueLimit"].double()
///
/// Looking up a missing key gives a node that doesn't `exist`; reading a
/// value from it throws. Numbers may be JSON numbers or numeric strings.
public struct ParameterNode: Sendable {
    /// The value, or `nil` when the path doesn't exist.
    public let value: OptionValue?
    /// The dotted path from the file's root, e.g. `irpef.brackets.1.rate`.
    public let path: String

    public init(_ value: OptionValue?, path: String = "") {
        self.value = value
        self.path = path
    }

    /// The root of a parameter set.
    public init(_ set: ParameterSet) {
        self.init(set.values, path: "")
    }

    /// Whether the path exists (and isn't `null`).
    public var exists: Bool {
        if let value, value != .null { true } else { false }
    }

    /// The member `key`, when this is an object.
    public subscript(key: String) -> ParameterNode {
        ParameterNode(value?[key], path: path.isEmpty ? key : "\(path).\(key)")
    }

    /// The element at `index`, when this is a list.
    public subscript(index: Int) -> ParameterNode {
        let element = value?.listValue.flatMap { $0.indices.contains(index) ? $0[index] : nil }
        return ParameterNode(element, path: path.isEmpty ? "\(index)" : "\(path).\(index)")
    }

    /// An error about this node.
    public func error(_ reason: String) -> ParameterLookupError {
        ParameterLookupError(path: path, reason: reason)
    }

    public func double() throws -> Double {
        guard exists else { throw error("is missing") }
        guard let number = value?.doubleValue else { throw error("is not a number") }
        return number
    }

    /// The number, or `nil` when the path doesn't exist.
    public func optionalDouble() throws -> Double? {
        exists ? try double() : nil
    }

    /// The number, or `fallback` when the path doesn't exist.
    public func double(default fallback: Double) throws -> Double {
        try optionalDouble() ?? fallback
    }

    public func int() throws -> Int {
        guard exists else { throw error("is missing") }
        guard let number = value?.intValue else { throw error("is not a whole number") }
        return number
    }

    /// The whole number, or `fallback` when the path doesn't exist.
    public func int(default fallback: Int) throws -> Int {
        exists ? try int() : fallback
    }

    public func bool() throws -> Bool {
        guard exists else { throw error("is missing") }
        guard let flag = value?.boolValue else { throw error("is not true or false") }
        return flag
    }

    /// The flag, or `fallback` when the path doesn't exist.
    public func bool(default fallback: Bool) throws -> Bool {
        exists ? try bool() : fallback
    }

    public func string() throws -> String {
        guard exists else { throw error("is missing") }
        guard let text = value?.stringValue else { throw error("is not a string") }
        return text
    }

    /// The elements of a list.
    public func list() throws -> [ParameterNode] {
        guard exists else { throw error("is missing") }
        guard let list = value?.listValue else { throw error("is not a list") }
        return list.indices.map { self[$0] }
    }

    /// The elements of a list, or none when the path doesn't exist.
    public func optionalList() throws -> [ParameterNode] {
        exists ? try list() : []
    }

    /// A list of numbers.
    public func doubles() throws -> [Double] {
        try list().map { try $0.double() }
    }

    /// A list of strings.
    public func strings() throws -> [String] {
        try list().map { try $0.string() }
    }

    /// The members of an object, by key.
    public func members() throws -> [String: ParameterNode] {
        guard exists else { throw error("is missing") }
        guard let object = value?.objectValue else { throw error("is not an object") }
        return Dictionary(uniqueKeysWithValues: object.keys.map { ($0, self[$0]) })
    }
}

/// A parameter that is missing or has the wrong type.
public struct ParameterLookupError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The dotted path, e.g. `irpef.brackets.1.rate`.
    public var path: String
    public var reason: String

    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }

    public var description: String {
        "Tax parameter \(path.isEmpty ? "(root)" : path) \(reason)."
    }
}

/// Checks on a parameter file's contents: every value must cite a source,
/// and values nobody could confirm are flagged for review.
///
/// A value is sourced when it, or an object enclosing it, has a non-empty
/// string `source`. An object flagged `"verify": true` holds values that need
/// checking against a ruling or an official text.
public enum ParameterAudit {
    /// Keys that describe a file or an object rather than hold parameters.
    public static let metadataKeys: Set<String> = ["year", "system", "checked", "source", "verify", "note", "description"]

    /// Dotted paths of values that no enclosing object gives a source for.
    public static func unsourcedPaths(in values: OptionValue) -> [String] {
        var result: [String] = []
        collectUnsourced(values, path: "", sourced: false, into: &result)
        return result.sorted()
    }

    /// Dotted paths of the objects flagged `"verify": true`.
    public static func pathsToVerify(in values: OptionValue) -> [String] {
        var result: [String] = []
        collectVerify(values, path: "", into: &result)
        return result.sorted()
    }

    private static func join(_ path: String, _ key: String) -> String {
        path.isEmpty ? key : "\(path).\(key)"
    }

    private static func hasSource(_ object: [String: OptionValue]) -> Bool {
        guard let source = object["source"]?.stringValue else { return false }
        return source.contains { !$0.isWhitespace }
    }

    private static func collectUnsourced(_ value: OptionValue, path: String, sourced: Bool, into result: inout [String]) {
        switch value {
        case .object(let object):
            let sourced = sourced || hasSource(object)
            for (key, member) in object where !metadataKeys.contains(key) {
                collectUnsourced(member, path: join(path, key), sourced: sourced, into: &result)
            }
        case .list(let list):
            for (index, element) in list.enumerated() {
                collectUnsourced(element, path: join(path, "\(index)"), sourced: sourced, into: &result)
            }
        default:
            if !sourced { result.append(path) }
        }
    }

    private static func collectVerify(_ value: OptionValue, path: String, into result: inout [String]) {
        switch value {
        case .object(let object):
            if object["verify"]?.boolValue == true { result.append(path) }
            for (key, member) in object where !metadataKeys.contains(key) {
                collectVerify(member, path: join(path, key), into: &result)
            }
        case .list(let list):
            for (index, element) in list.enumerated() {
                collectVerify(element, path: join(path, "\(index)"), into: &result)
            }
        default:
            break
        }
    }
}
