import Foundation
import Model

/// A file's text and the encoding it was read with.
public struct DecodedText: Hashable, Sendable {
    public var text: String
    public var encoding: TextEncodingName

    public init(text: String, encoding: TextEncodingName) {
        self.text = text
        self.encoding = encoding
    }
}

/// Turns a file's bytes into text: UTF-8 with or without a byte-order mark,
/// UTF-16 (little or big endian), Windows-1252 and ISO-8859-1.
public enum TextDecoding {
    /// Decodes `data`, detecting the encoding when `encoding` is `nil`.
    ///
    /// Detection: a byte-order mark decides; otherwise text that looks like
    /// UTF-16 is read as UTF-16, valid UTF-8 as UTF-8, and anything else as
    /// Windows-1252.
    ///
    /// A given encoding is used unless the file clearly says otherwise: a
    /// byte-order mark always wins, and a single-byte encoding (Windows-1252,
    /// ISO-8859-1) gives way to UTF-8 when the bytes are valid UTF-8 with
    /// accented letters, as when a file is saved again from another app. A
    /// given UTF encoding that doesn't fit the bytes throws.
    ///
    /// A file that isn't text (an `.xlsx` or `.numbers` spreadsheet, which
    /// is a ZIP archive, a PDF, or NUL bytes outside UTF-16) throws
    /// ``ImportError/binaryFile(_:)`` instead of being read as Windows-1252.
    public static func decode(_ data: Data, encoding: TextEncodingName? = nil) throws(ImportError) -> DecodedText {
        let bytes = [UInt8](data)
        let name: TextEncodingName
        if let encoding, !hasByteOrderMark(bytes) {
            let singleByte = ["windows1252", "cp1252", "iso88591", "latin1"].contains(normalized(encoding))
            let looksUTF8 = bytes.contains { $0 >= 0x80 } && String(validating: bytes, as: UTF8.self) != nil
            name = singleByte && looksUTF8 ? .utf8 : encoding
        } else {
            name = detectEncoding(bytes)
        }
        let isUTF16 = ["utf16", "utf16le", "utf16be", "unicode"].contains(normalized(name))
        if let kind = binaryKind(bytes, isUTF16: isUTF16) { throw .binaryFile(kind) }
        switch normalized(name) {
        case "utf8":
            let start = bytes.starts(with: utf8BOM) ? 3 : 0
            guard let text = String(validating: bytes[start...], as: UTF8.self) else {
                throw .invalidText(encoding: name)
            }
            return DecodedText(text: text, encoding: name)
        case "utf16", "utf16le", "utf16be", "unicode":
            let bigEndian = bytes.starts(with: [0xFE, 0xFF])
                || (!bytes.starts(with: [0xFF, 0xFE])
                    && (normalized(name) == "utf16be" || utf16Endianness(bytes) == .big))
            let start = bytes.starts(with: [0xFE, 0xFF]) || bytes.starts(with: [0xFF, 0xFE]) ? 2 : 0
            var units: [UInt16] = []
            units.reserveCapacity((bytes.count - start) / 2)
            var index = start
            while index + 1 < bytes.count {
                let first = UInt16(bytes[index]), second = UInt16(bytes[index + 1])
                units.append(bigEndian ? first << 8 | second : second << 8 | first)
                index += 2
            }
            guard let text = String(validating: units, as: UTF16.self) else {
                throw .invalidText(encoding: name)
            }
            return DecodedText(text: text, encoding: name)
        case "windows1252", "cp1252":
            return DecodedText(text: decodeWindows1252(bytes), encoding: name)
        case "iso88591", "latin1":
            var scalars = String.UnicodeScalarView()
            scalars.append(contentsOf: bytes.map { Unicode.Scalar($0) })
            return DecodedText(text: String(scalars), encoding: name)
        default:
            throw .unsupportedEncoding(name.rawValue)
        }
    }

    /// The encoding `decode` would pick for these bytes.
    public static func detectEncoding(_ data: Data) -> TextEncodingName {
        detectEncoding([UInt8](data))
    }

    static func detectEncoding(_ bytes: [UInt8]) -> TextEncodingName {
        if bytes.starts(with: utf8BOM) { return .utf8 }
        if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]) { return .utf16 }
        if utf16Endianness(bytes) != nil { return .utf16 }
        if String(validating: bytes, as: UTF8.self) != nil { return .utf8 }
        return .windows1252
    }

    private static let utf8BOM: [UInt8] = [0xEF, 0xBB, 0xBF]

    /// The kind of file that isn't text, by its first bytes; `nil` for text.
    static func binaryKind(_ bytes: [UInt8], isUTF16: Bool) -> ImportError.BinaryFileKind? {
        let zipSignatures: [[UInt8]] = [[0x50, 0x4B, 0x03, 0x04], [0x50, 0x4B, 0x05, 0x06], [0x50, 0x4B, 0x07, 0x08]]
        if zipSignatures.contains(where: { bytes.starts(with: $0) }) { return .archive }
        if bytes.starts(with: Array("%PDF".utf8)) { return .pdf }
        if !isUTF16, bytes.contains(0) { return .other }
        return nil
    }

    private static func hasByteOrderMark(_ bytes: [UInt8]) -> Bool {
        bytes.starts(with: utf8BOM) || bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF])
    }

    private enum Endianness { case little, big }

    /// UTF-16 without a byte-order mark: mostly-ASCII text has a zero byte
    /// in every other position.
    private static func utf16Endianness(_ bytes: [UInt8]) -> Endianness? {
        let sample = bytes.prefix(4096)
        guard sample.count >= 4, sample.count % 2 == 0 else { return nil }
        let pairs = sample.count / 2
        var zeroEven = 0, zeroOdd = 0
        for (offset, byte) in sample.enumerated() where byte == 0 {
            if offset % 2 == 0 { zeroEven += 1 } else { zeroOdd += 1 }
        }
        if zeroOdd * 10 >= pairs * 4, zeroEven * 20 < pairs { return .little }
        if zeroEven * 10 >= pairs * 4, zeroOdd * 20 < pairs { return .big }
        return nil
    }

    private static func normalized(_ name: TextEncodingName) -> String {
        name.rawValue.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Windows-1252: Latin-1 except for 0x80–0x9F, which hold typographic
    /// characters and the euro sign. Unassigned bytes map to C1 controls.
    private static func decodeWindows1252(_ bytes: [UInt8]) -> String {
        var scalars = String.UnicodeScalarView()
        for byte in bytes {
            if (0x80...0x9F).contains(byte), let scalar = Unicode.Scalar(windows1252High[Int(byte - 0x80)]) {
                scalars.append(scalar)
            } else {
                scalars.append(Unicode.Scalar(byte))
            }
        }
        return String(scalars)
    }

    private static let windows1252High: [UInt32] = [
        0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
        0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
        0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
        0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178,
    ]
}
