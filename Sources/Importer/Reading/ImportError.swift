import Model

/// Why a file can't be read at all. Problems with single cells are
/// ``ImportProblem``s in the preview instead.
public enum ImportError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The file has no rows.
    case emptyFile
    /// The bytes aren't valid text in the given encoding.
    case invalidText(encoding: TextEncodingName)
    /// An encoding name the importer doesn't know.
    case unsupportedEncoding(String)
    /// A delimiter other than one character.
    case unsupportedDelimiter(String)
    /// The header row is past the end of the file.
    case headerRowOutOfRange(Int)

    public var description: String {
        switch self {
        case .emptyFile: "The file has no rows."
        case .invalidText(let encoding): "The file isn't valid \(encoding.rawValue) text."
        case .unsupportedEncoding(let name): "Unknown text encoding “\(name)”."
        case .unsupportedDelimiter(let delimiter): "“\(delimiter)” can't be used as a delimiter."
        case .headerRowOutOfRange(let row): "Row \(row) can't be the header: the file is shorter."
        }
    }
}
