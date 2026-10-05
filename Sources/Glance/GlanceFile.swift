import Foundation

/// The snapshot as a file: JSON the app writes into the App Group container
/// and the widget extension reads.
public enum GlanceFile {
    /// The file's name in the container.
    public static let name = "glance.json"

    /// The snapshot as JSON, with sorted keys, so the same snapshot is the same bytes.
    public static func data(for snapshot: GlanceSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }

    /// The snapshot in `data`; `nil` when it can't be read or is of a newer
    /// format than this version knows.
    public static func snapshot(from data: Data) -> GlanceSnapshot? {
        let decoder = JSONDecoder()
        guard let format = try? decoder.decode(Format.self, from: data),
              format.version <= GlanceSnapshot.currentVersion
        else { return nil }
        return try? decoder.decode(GlanceSnapshot.self, from: data)
    }

    /// The snapshot in the file at `url`; `nil` when there's none, or it
    /// can't be read.
    public static func read(at url: URL) -> GlanceSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return snapshot(from: data)
    }

    /// Writes `snapshot` to `url` atomically, creating its folder if needed.
    public static func write(_ snapshot: GlanceSnapshot, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data(for: snapshot).write(to: url, options: .atomic)
    }

    /// Just the format, read before the rest.
    private struct Format: Decodable {
        var version: Int
    }
}
