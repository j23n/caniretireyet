import Foundation

/// A value decoded from JSON text with a plain `JSONDecoder`.
public func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

/// The value written as JSON text with a plain `JSONEncoder`, keys sorted.
public func json<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}
