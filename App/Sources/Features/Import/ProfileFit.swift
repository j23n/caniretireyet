import Foundation
import Importer
import Model
import Storage

/// How well a saved import profile fits a file: how many of the file's
/// columns it imports, and which columns don't line up. Used to suggest a
/// profile, and on iPhone to list them for "Import with profile…".
struct ProfileFit: Hashable, Sendable, Identifiable {
    var profile: ImportProfile
    /// File columns the profile imports.
    var imported: Int
    /// Columns of the profile the file doesn't have.
    var missing: Int
    /// File columns with values the profile doesn't know.
    var unknown: Int
    /// Whether a column of the file holds the dates.
    var hasDates: Bool
    /// Why the file can't be read with this profile, if it can't.
    var problem: String?

    var id: ImportProfileID { profile.id }

    /// Whether the profile reads the whole file: every column known, none
    /// missing, dates found and something imported.
    var fits: Bool {
        problem == nil && hasDates && missing == 0 && unknown == 0 && imported > 0
    }

    /// E.g. "Fits this file", "1 column missing, 2 new columns".
    var summary: String {
        if let problem { return "Can't read the file with it: \(problem)" }
        if fits { return "Fits this file" }
        var parts: [String] = []
        if missing > 0 { parts.append(missing == 1 ? "1 column missing" : "\(missing) columns missing") }
        if unknown > 0 { parts.append(unknown == 1 ? "1 new column" : "\(unknown) new columns") }
        if !hasDates { parts.append("no date column") }
        if imported == 0 { parts.append("imports nothing") }
        return parts.joined(separator: ", ")
    }

    /// Reads `data` with each profile and sorts them: those that fit first,
    /// then the fewest columns out of line, the most imported, then by name.
    static func rank(_ data: Data, profiles: [ImportProfile]) -> [ProfileFit] {
        profiles.filter { !$0.isLedger }.map { fit(data, profile: $0) }.sorted { lhs, rhs in
            let left = (lhs.fits ? 0 : 1, lhs.problem == nil ? 0 : 1, lhs.missing + lhs.unknown, -lhs.imported)
            let right = (rhs.fits ? 0 : 1, rhs.problem == nil ? 0 : 1, rhs.missing + rhs.unknown, -rhs.imported)
            if left != right { return left < right }
            return (lhs.profile.name, lhs.profile.id) < (rhs.profile.name, rhs.profile.id)
        }
    }

    /// How well one profile reads `data`.
    static func fit(_ data: Data, profile: ImportProfile) -> ProfileFit {
        let session: ImportSession
        do {
            session = try ImportSession(data: data, profile: profile)
        } catch {
            return ProfileFit(profile: profile, imported: 0, missing: 0, unknown: 0, hasDates: false,
                              problem: ImportFlow.describe(error))
        }
        var imported = 0
        var hasDates = false
        for role in session.columnRoles {
            switch role {
            case .date:
                hasDates = true
            case .mapped(let index):
                let column = session.profile.columns[index]
                if column.field == .date { hasDates = true } else if column.isImported { imported += 1 }
            case .unknown, .unused:
                break
            }
        }
        var missing = 0
        var unknown = 0
        for issue in session.issues {
            switch issue.kind {
            case .missingColumn: missing += 1
            case .unknownColumn: unknown += 1
            default: break
            }
        }
        return ProfileFit(profile: profile, imported: imported, missing: missing, unknown: unknown,
                          hasDates: hasDates, problem: nil)
    }
}

extension ImportProfile {
    /// A line about the profile for lists, e.g. "A row per date · 4 columns
    /// imported · dd/MM/yyyy · imports/net-worth-sheet.json".
    var importSummary: String {
        if isLedger {
            let accounts = matches.accounts.count
            return ["Ledger journal", accounts == 1 ? "1 account" : "\(accounts) accounts",
                    LedgerChoices.frequencyName(ledger?.effectiveFrequency ?? .month),
                    LibraryFile.importProfile(id).path].joined(separator: " · ")
        }
        let imported = columns.filter(\.isImported).count
        var parts = [ImportChoices.layoutName(layout),
                     imported == 1 ? "1 column imported" : "\(imported) columns imported"]
        if let pattern = defaults.date?.pattern { parts.append(pattern) }
        parts.append(LibraryFile.importProfile(id).path)
        return parts.joined(separator: " · ")
    }
}

extension ImportColumn {
    /// Whether the column's values are imported: it isn't ignored, and in
    /// the long layout it isn't just a name or currency field.
    var isImported: Bool {
        if let field { return field == .value }
        if let target { return target != .ignore }
        return false
    }
}
