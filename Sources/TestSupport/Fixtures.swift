import Foundation
import Model

/// The made-up example library shipped with the tests, in the FILE_FORMAT.md
/// layout (`Resources/ExampleLibrary/`). All names and numbers are fake.
///
/// Contents: 10 accounts (current, savings, `directa`, a brokerage that
/// records trades, crypto wallet, gold coins, pension fund, TFR, a home and
/// its mortgage, both excluded from plans, and `old-bank`, closed on
/// 2025-11-15 with a successor);
/// instruments `vwce` (EUR), `btc` (priced in USD) and `gold` (per gram);
/// month files 2025-10 to 2026-09 with month-end valuations (Directa's
/// record its cash), prices, EUR/USD rates and `hicp-it` values (none yet
/// for 2026-09), and Directa's trades: an opening of 338 VWCE, a deposit and
/// a buy each month, and a sale in July 2026; plans `base` and
/// `part-time-from-50`; the import profile `net-worth-sheet`; and a baseline
/// and a headline file for `base`.
public enum Fixtures {
    /// The example library folder.
    public static var exampleLibraryURL: URL {
        guard let url = Bundle.module.url(forResource: "ExampleLibrary", withExtension: nil) else {
            preconditionFailure("TestSupport's ExampleLibrary resource is missing")
        }
        return url
    }

    /// A file in the example library, e.g. `url(for: "plans/base.json")`.
    public static func url(for relativePath: String) -> URL {
        exampleLibraryURL.appendingPathComponent(relativePath)
    }

    /// The contents of a file in the example library.
    public static func data(for relativePath: String) throws -> Data {
        try Data(contentsOf: url(for: relativePath))
    }

    /// The paths of every JSON file in the example library, relative to its
    /// folder and sorted, e.g. `history/2026/2026-09.json`.
    public static var allJSONFiles: [String] {
        let root = exampleLibraryURL.standardizedFileURL.path
        guard let enumerator = FileManager.default.enumerator(atPath: root) else { return [] }
        return enumerator.compactMap { $0 as? String }.filter { $0.hasSuffix(".json") }.sorted()
    }

    /// Decodes one file of the example library with a plain `JSONDecoder`.
    public static func decode<T: Decodable>(_ type: T.Type, from relativePath: String) throws -> T {
        try JSONDecoder().decode(type, from: data(for: relativePath))
    }

    /// The model type a library file decodes to, by its path in the folder.
    public static func modelType(forPath path: String) -> (any (Codable & Hashable).Type)? {
        let parts = path.split(separator: "/").map(String.init)
        switch (parts.first, parts.count) {
        case ("library.json", 1): return LibrarySettings.self
        case ("accounts", 2): return Account.self
        case ("instruments", 2): return Instrument.self
        case ("history", 3): return MonthFile.self
        case ("plans", 2): return PlanDocument.self
        case ("imports", 2): return ImportProfile.self
        case ("projections", 4) where parts[2] == "baselines": return Baseline.self
        case ("projections", 4) where parts[2] == "headlines": return HeadlineFile.self
        default: return nil
        }
    }

    /// The example library as a `Library`, read naively with `JSONDecoder`.
    ///
    /// For tests of modules that need data (Tracker, Planner, …) without
    /// depending on Storage. It doesn't validate, keep unknown keys, or check
    /// that file names match IDs; Storage's loader does that.
    public static func exampleLibrary() throws -> Library {
        var library = Library(settings: try decode(LibrarySettings.self, from: "library.json"))
        for path in allJSONFiles {
            let parts = path.split(separator: "/").map(String.init)
            let stem = String(parts[parts.count - 1].dropLast(".json".count))
            switch parts[0] {
            case "accounts":
                let account = try decode(Account.self, from: path)
                library.accounts[account.id] = account
            case "instruments":
                let instrument = try decode(Instrument.self, from: path)
                library.instruments[instrument.id] = instrument
            case "history":
                let month = try decode(MonthFile.self, from: path)
                library.months[month.month] = month
            case "plans":
                let plan = try decode(PlanDocument.self, from: path)
                library.plans[plan.id] = plan
            case "imports":
                let profile = try decode(ImportProfile.self, from: path)
                library.importProfiles[profile.id] = profile
            case "projections" where parts.count == 4:
                let plan = PlanID(parts[1])
                var projections = library.projections[plan] ?? PlanProjections()
                if parts[2] == "baselines" {
                    projections.baselines[BaselineID(stem)] = try decode(Baseline.self, from: path)
                } else if parts[2] == "headlines", let year = Int(stem) {
                    projections.headlines[year] = try decode(HeadlineFile.self, from: path)
                }
                library.projections[plan] = projections
            default:
                break
            }
        }
        return library
    }
}
