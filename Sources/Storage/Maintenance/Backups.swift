import Foundation
import Model

/// A copy of some library files in `backups/<name>/`, taken before a
/// migration or an import so it can be undone.
///
/// The folder mirrors the library's layout and holds a `backup.json` that
/// lists what was copied, and which files didn't exist yet (restoring
/// deletes those, so an import that created a month file is fully undone).
public struct Backup: Hashable, Sendable {
    /// The folder name in `backups/`, e.g. `2026-09-30-142501-import`.
    public var name: String
    /// What the backup was taken for, e.g. `import`.
    public var label: String
    /// When the backup was taken, to the second.
    public var created: Date
    /// The files copied, as paths relative to the library folder.
    public var files: [String]
    /// Paths that were asked for but didn't exist when the backup was taken.
    public var absentFiles: [String]

    public init(name: String, label: String, created: Date, files: [String], absentFiles: [String] = []) {
        self.name = name
        self.label = label
        self.created = created
        self.files = files
        self.absentFiles = absentFiles
    }

    /// The backup's folder, relative to the library folder.
    public var path: String { "\(LibraryFolder.backupsFolder)/\(name)" }
}

extension LibraryFolder {
    /// The folder that holds backups.
    public static let backupsFolder = "backups"

    /// The file in each backup folder that describes it.
    static let backupManifestName = "backup.json"

    /// Copies files into a new folder `backups/<timestamp>-<label>/`, e.g.
    /// before an import, so ``restore(backup:)`` can undo it. `paths` are
    /// relative to the library folder; paths that don't exist are recorded,
    /// and restoring deletes them. The timestamp is `date` in the device's
    /// time zone (`2026-09-30-142501`).
    @discardableResult
    public func backup(paths: [String], label: String, date: Date = Date()) throws -> Backup {
        let label = Slug.make(from: label)
        return try makeBackup(paths: paths, name: "\(Self.timestamp(date))-\(label)", label: label, date: date)
    }

    /// Puts the files of a backup back in place, and deletes the files that
    /// didn't exist when it was taken. The backup itself is kept.
    @discardableResult
    public func restore(backup: Backup) throws -> SaveReport {
        try validateRelativePath(backup.name)
        let folder = backup.path
        guard files.fileExists(at: url(for: "\(folder)/\(Self.backupManifestName)")) else {
            throw StorageError.backupNotFound(backup.name)
        }
        var report = SaveReport()
        for path in backup.files {
            try validateRelativePath(path)
            try files.writeData(files.readData(at: url(for: "\(folder)/\(path)")), to: url(for: path))
            report.written.append(path)
        }
        for path in backup.absentFiles {
            try validateRelativePath(path)
            guard files.fileExists(at: url(for: path)) else { continue }
            try files.removeItem(at: url(for: path))
            report.deleted.append(path)
        }
        return report
    }

    /// The backups in `backups/`, oldest first. Folders without a readable
    /// `backup.json` are left out.
    public func backups() throws -> [Backup] {
        let paths = try files.listFiles(in: url(for: Self.backupsFolder))
        var backups: [Backup] = []
        for path in paths {
            let parts = path.split(separator: "/")
            guard parts.count == 2, parts[1] == Self.backupManifestName else { continue }
            let name = String(parts[0])
            guard let data = try? files.readData(at: url(for: "\(Self.backupsFolder)/\(path)")),
                  let manifest = try? JSONDecoder().decode(BackupManifest.self, from: data),
                  let created = try? Date(manifest.created, strategy: .iso8601)
            else { continue }
            backups.append(Backup(name: name, label: manifest.label, created: created, files: manifest.files,
                                  absentFiles: manifest.absentFiles ?? []))
        }
        return backups.sorted { ($0.created, $0.name) < ($1.created, $1.name) }
    }

    /// Copies `paths` into `backups/<name>/` (or `<name>-2`, … if taken)
    /// and writes its `backup.json`.
    func makeBackup(paths: [String], name: String, label: String, date: Date) throws -> Backup {
        for path in paths {
            try validateRelativePath(path)
            guard path != Self.backupManifestName, !path.hasPrefix(Self.backupsFolder + "/") else {
                throw StorageError.invalidPath(path)
            }
        }
        let existing = Set(try files.listFiles(in: url(for: Self.backupsFolder)).map { String($0.prefix { $0 != "/" }) })
        let uniqueName = Slug.unique(name, among: existing)
        let folder = "\(Self.backupsFolder)/\(uniqueName)"
        var copied: [String] = []
        var absent: [String] = []
        for path in Set(paths).sorted() {
            let source = url(for: path)
            if files.fileExists(at: source) {
                try files.writeData(files.readData(at: source), to: url(for: "\(folder)/\(path)"))
                copied.append(path)
            } else {
                absent.append(path)
            }
        }
        let created = date.formatted(.iso8601)
        let manifest = BackupManifest(label: label, created: created, files: copied,
                                      absentFiles: absent.isEmpty ? nil : absent)
        try files.writeData(CanonicalJSON.data(encoding: manifest), to: url(for: "\(folder)/\(Self.backupManifestName)"))
        // Whole seconds, as listed by `backups()`.
        return Backup(name: uniqueName, label: label, created: (try? Date(created, strategy: .iso8601)) ?? date,
                      files: copied, absentFiles: absent)
    }

    /// `2026-09-30-142501`, in the device's time zone.
    static func timestamp(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func pad(_ value: Int?, _ width: Int) -> String {
            let digits = String(value ?? 0)
            return String(repeating: "0", count: max(0, width - digits.count)) + digits
        }
        return "\(pad(parts.year, 4))-\(pad(parts.month, 2))-\(pad(parts.day, 2))-"
            + "\(pad(parts.hour, 2))\(pad(parts.minute, 2))\(pad(parts.second, 2))"
    }
}

/// `backups/<name>/backup.json`.
private struct BackupManifest: Codable {
    var label: String
    /// ISO 8601, e.g. `2026-09-30T12:25:01Z`.
    var created: String
    var files: [String]
    var absentFiles: [String]?
}
