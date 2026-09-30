import Foundation

/// A system's yearly parameter files: rates and thresholds per tax year,
/// each with its source.
///
/// A simulated year uses the latest file at or before it; later years reuse
/// the latest file, and years before the first file use the first.
public protocol ParameterStore: Sendable {
    /// The system these parameters belong to.
    var system: String { get }
    /// The tax years with a parameter file, ascending.
    var years: [Int] { get }
    /// The parameters that apply in `year`.
    func parameters(for year: Int) throws -> ParameterSet
}

extension ParameterStore {
    /// The tax year whose file applies in `year`, if there are any files.
    public func parameterYear(for year: Int) -> Int? {
        years.last { $0 <= year } ?? years.first
    }
}

/// Errors loading or looking up parameters.
public enum ParameterError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The store has no parameter files.
    case noParameters(system: String)
    /// A file isn't valid JSON, or isn't a JSON object.
    case invalidFile(system: String, name: String, reason: String)

    public var description: String {
        switch self {
        case .noParameters(let system):
            "No tax parameters for \(system)."
        case .invalidFile(let system, let name, let reason):
            "Tax parameter file \(system)/\(name) can't be read: \(reason)"
        }
    }
}

/// One tax year's parameters for one system: the file's JSON tree, with
/// lookup by dotted path and decoding into the system's own typed struct.
public struct ParameterSet: Hashable, Sendable {
    public let system: String
    /// The tax year of the file (which may be earlier than the simulated year).
    public let year: Int
    /// The file's contents, a JSON object.
    public let values: OptionValue

    public init(system: String, year: Int, values: OptionValue) {
        self.system = system
        self.year = year
        self.values = values
    }

    /// The value at a dotted path such as `irpef.brackets.0.rate` (list
    /// elements by index), or `nil` if there is none.
    public func value(at path: String) -> OptionValue? {
        var current = values
        for component in path.split(separator: ".").map(String.init) {
            switch current {
            case .object(let object):
                guard let next = object[component] else { return nil }
                current = next
            case .list(let list):
                guard let index = Int(component), list.indices.contains(index) else { return nil }
                current = list[index]
            default:
                return nil
            }
        }
        return current
    }

    /// The number at a dotted path (numeric strings included).
    public func double(at path: String) -> Double? {
        value(at: path)?.doubleValue
    }

    /// Decodes the whole set into a system's parameter struct. Numbers
    /// written as strings stay strings; decode them with
    /// `decodeDouble(forKey:)`.
    public func decode<T: Decodable>(_ type: T.Type = T.self) throws -> T {
        let data = try JSONEncoder().encode(values)
        return try JSONDecoder().decode(type, from: data)
    }

    /// These parameters with a plan's overrides applied. Keys are
    /// system-prefixed dotted paths (`it.irpef.rates`); keys for other
    /// systems are ignored. Missing objects along a path are created. Inside
    /// a list, a numeric component replaces that element
    /// (`it.irpef.brackets.1.rate`); other components leave the list alone.
    public func applying(overrides: OptionValues) -> ParameterSet {
        let prefix = system + "."
        var tree = values
        for (key, value) in overrides.values.sorted(by: { $0.key < $1.key }) where key.hasPrefix(prefix) {
            let path = key.dropFirst(prefix.count).split(separator: ".").map(String.init)
            guard !path.isEmpty else { continue }
            tree = Self.setting(value, at: path[...], in: tree)
        }
        return ParameterSet(system: system, year: year, values: tree)
    }

    private static func setting(_ value: OptionValue, at path: ArraySlice<String>, in tree: OptionValue) -> OptionValue {
        guard let key = path.first else { return value }
        if case .list(var list) = tree {
            // Only an existing element can be replaced; anything else leaves the list alone.
            guard let index = Int(key), list.indices.contains(index) else { return tree }
            list[index] = setting(value, at: path.dropFirst(), in: list[index])
            return .list(list)
        }
        var object = tree.objectValue ?? [:]
        object[key] = setting(value, at: path.dropFirst(), in: object[key] ?? .object([:]))
        return .object(object)
    }
}

/// Parameters loaded from JSON files named `<year>.json`, e.g. a tax
/// module's bundled `Resources/it/2026.json`.
public struct JSONParameterStore: ParameterStore {
    public let system: String
    public let years: [Int]
    private let sets: [Int: ParameterSet]
    private let overrides: OptionValues

    /// Parses one file per tax year. Throws if a file isn't a JSON object.
    public init(system: String, files: [Int: Data]) throws {
        var sets: [Int: ParameterSet] = [:]
        for (year, data) in files {
            let value: OptionValue
            do {
                value = try JSONDecoder().decode(OptionValue.self, from: data)
            } catch {
                throw ParameterError.invalidFile(system: system, name: "\(year).json", reason: "\(error)")
            }
            guard case .object = value else {
                throw ParameterError.invalidFile(system: system, name: "\(year).json", reason: "not a JSON object")
            }
            sets[year] = ParameterSet(system: system, year: year, values: value)
        }
        self.init(system: system, sets: sets, overrides: [:])
    }

    /// Loads every `<year>.json` in `directory` (other files are ignored).
    public init(system: String, directory: URL) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        var files: [Int: Data] = [:]
        for name in names where name.hasSuffix(".json") {
            let stem = name.dropLast(".json".count)
            guard stem.count == 4, let year = Int(stem) else { continue }
            files[year] = try Data(contentsOf: directory.appendingPathComponent(name))
        }
        try self.init(system: system, files: files)
    }

    private init(system: String, sets: [Int: ParameterSet], overrides: OptionValues) {
        self.system = system
        self.sets = sets
        self.years = sets.keys.sorted()
        self.overrides = overrides
    }

    public func parameters(for year: Int) throws -> ParameterSet {
        guard let fileYear = parameterYear(for: year), let set = sets[fileYear] else {
            throw ParameterError.noParameters(system: system)
        }
        return overrides.isEmpty ? set : set.applying(overrides: overrides)
    }

    /// The same store with a plan's overrides applied to every year.
    public func applying(overrides: OptionValues) -> JSONParameterStore {
        var merged = self.overrides
        for (key, value) in overrides.values { merged[key] = value }
        return JSONParameterStore(system: system, sets: sets, overrides: merged)
    }
}

extension KeyedDecodingContainer {
    /// Decodes a number written as a JSON number or as a numeric string
    /// (`"0.23"`), as parameter files do.
    public func decodeDouble(forKey key: Key) throws -> Double {
        if let string = try? decode(String.self, forKey: key) {
            guard let value = Double(string) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key, in: self, debugDescription: "Expected a number, found \"\(string)\".")
            }
            return value
        }
        return try decode(Double.self, forKey: key)
    }

    /// Like ``decodeDouble(forKey:)``, but `nil` when the key is absent or `null`.
    public func decodeDoubleIfPresent(forKey key: Key) throws -> Double? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        return try decodeDouble(forKey: key)
    }
}
