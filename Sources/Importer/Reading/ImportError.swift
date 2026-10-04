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
    /// A profile with a layout this version doesn't import, e.g. a ledger
    /// journal's profile written by an earlier version.
    case unsupportedLayout(String)
    /// The file isn't text at all: a spreadsheet saved as `.xlsx` or
    /// `.numbers`, a PDF, or other binary data.
    case binaryFile(BinaryFileKind)

    /// What a binary file looks like, by its first bytes.
    public enum BinaryFileKind: Hashable, Sendable {
        /// A ZIP archive (`PK`): an `.xlsx` or `.numbers` spreadsheet, most likely.
        case archive
        /// `%PDF`.
        case pdf
        /// NUL bytes in text that isn't UTF-16, e.g. an old `.xls`.
        case other
    }

    public var description: String {
        switch self {
        case .emptyFile: "The file has no rows."
        case .invalidText(let encoding): "The file isn't valid \(encoding.rawValue) text."
        case .unsupportedEncoding(let name): "Unknown text encoding “\(name)”."
        case .unsupportedDelimiter(let delimiter): "“\(delimiter)” can't be used as a delimiter."
        case .headerRowOutOfRange(let row): "Row \(row) can't be the header: the file is shorter."
        case .unsupportedLayout(let layout): "The profile's layout “\(layout)” isn't one this version imports."
        case .binaryFile(let kind):
            switch kind {
            case .archive: "This is a spreadsheet file (such as .xlsx or .numbers), not a CSV file. Export it as "
                + "CSV from Excel or Numbers, and import that."
            case .pdf: "This is a PDF, not a CSV file. Export the data as CSV, and import that."
            case .other: "This file isn't text. Export the data as CSV, and import that."
            }
        }
    }
}
