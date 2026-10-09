import Foundation
import Model
import Storage
import Testing
import TestSupport

/// The JSON Schemas in docs/schema describe the library's files: every file
/// of the example library matches its schema, every key the Model reads is
/// in its schema and the other way round, and documents with every field
/// set, as the Model writes them, match too.
@Suite struct JSONSchemaTests {
    let validator: JSONSchemaValidator

    init() throws {
        validator = try JSONSchemaValidator()
    }

    /// The schema a library file follows, by its path in the folder.
    static func schema(forPath path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        switch (parts.first, parts.count) {
        case ("library.json", 1): return "library.schema.json"
        case ("accounts", 2): return "account.schema.json"
        case ("instruments", 2): return "instrument.schema.json"
        case ("history", 3): return "history-month.schema.json"
        case ("plans", 2): return "plan.schema.json"
        case ("imports", 2): return "import-profile.schema.json"
        case ("projections", 4) where parts[2] == "baselines": return "baseline.schema.json"
        case ("projections", 4) where parts[2] == "headlines": return "headlines.schema.json"
        case ("backups", 3) where parts[2] == "backup.json": return "backup.schema.json"
        default: return nil
        }
    }

    @Test func everyReferenceResolves() {
        #expect(validator.schemas.count == 10)
        #expect(validator.unresolvedReferences() == [])
    }

    @Test func theExampleLibraryMatchesTheSchemas() throws {
        let files = Fixtures.allJSONFiles
        #expect(files.count > 20)
        for path in files {
            let schema = try #require(Self.schema(forPath: path), "No schema for \(path)")
            let json = try CanonicalJSON.parse(Fixtures.data(for: path))
            let problems = validator.validate(json, against: schema)
            #expect(problems.isEmpty, "\(path): \(problems.joined(separator: "\n"))")
        }
    }

    /// The schemas define the format, so their examples must be right.
    @Test func everySchemasExamplesMatchIt() {
        var checked = 0
        for (file, schema) in validator.schemas.sorted(by: { $0.key < $1.key }) {
            for (index, example) in (schema["examples"]?.arrayValue ?? []).enumerated() {
                let problems = validator.validate(example, against: file)
                #expect(problems.isEmpty, "\(file) examples[\(index)]: \(problems.joined(separator: "\n"))")
                checked += 1
            }
        }
        #expect(checked >= 9)
    }

    // MARK: Keys

    /// Each Model type with fixed keys, and where its object is described.
    static let objects: [(name: String, keys: Set<String>, file: String, pointer: String)] = [
        ("LibrarySettings", LibrarySettings.knownKeys, "library.schema.json", ""),
        ("Person", Person.knownKeys, "library.schema.json", "/properties/person"),
        ("Account", Account.knownKeys, "account.schema.json", ""),
        ("IncludeIn", IncludeIn.knownKeys, "account.schema.json", "/properties/includeIn"),
        ("Instrument", Instrument.knownKeys, "instrument.schema.json", ""),
        ("PriceSource", PriceSource.knownKeys, "instrument.schema.json", "/properties/priceSource"),
        ("MonthFile", MonthFile.knownKeys, "history-month.schema.json", ""),
        ("Valuation", Valuation.knownKeys, "history-month.schema.json", "/$defs/valuation"),
        ("Position", Position.knownKeys, "history-month.schema.json", "/$defs/position"),
        ("Trade", Trade.knownKeys, "history-month.schema.json", "/$defs/trade"),
        ("PriceRecord", PriceRecord.knownKeys, "history-month.schema.json", "/$defs/price"),
        ("FXRecord", FXRecord.knownKeys, "history-month.schema.json", "/$defs/fx"),
        ("IndexRecord", IndexRecord.knownKeys, "history-month.schema.json", "/$defs/index"),
        ("PlanDocument", PlanDocument.knownKeys, "plan.schema.json", ""),
        ("PlanRetirement", PlanRetirement.knownKeys, "plan.schema.json", "/properties/retirement"),
        ("PlanTax", PlanTax.knownKeys, "plan.schema.json", "/properties/tax"),
        ("PlanSimulation", PlanSimulation.knownKeys, "plan.schema.json", "/properties/simulation"),
        ("WorkPhase", WorkPhase.knownKeys, "plan.schema.json", "/$defs/workPhase"),
        ("PlanSpending", PlanSpending.knownKeys, "plan.schema.json", "/$defs/spending"),
        ("SpendingPhase", SpendingPhase.knownKeys, "plan.schema.json", "/$defs/spending/properties/phases/items"),
        ("FlexibleSpending", FlexibleSpending.knownKeys, "plan.schema.json", "/$defs/flexibleSpending"),
        ("PlanPension", PlanPension.knownKeys, "plan.schema.json", "/$defs/pension"),
        ("PlanIncome", PlanIncome.knownKeys, "plan.schema.json", "/$defs/income"),
        ("PlanContribution", PlanContribution.knownKeys, "plan.schema.json", "/$defs/contribution"),
        ("PlanEvent", PlanEvent.knownKeys, "plan.schema.json", "/$defs/event"),
        ("PlanPortfolio", PlanPortfolio.knownKeys, "plan.schema.json", "/$defs/portfolio"),
        ("TargetMixStep", TargetMixStep.knownKeys, "plan.schema.json",
         "/$defs/portfolio/properties/targetMixByAge/items"),
        ("PlanAssumptions", PlanAssumptions.knownKeys, "plan.schema.json", "/$defs/assumptions"),
        ("ReturnAssumption", ReturnAssumption.knownKeys, "plan.schema.json", "/$defs/returnAssumption"),
        ("Baseline", Baseline.knownKeys, "baseline.schema.json", ""),
        ("BaselineStart", BaselineStart.knownKeys, "baseline.schema.json", "/properties/start"),
        ("BaselineYear", BaselineYear.knownKeys, "baseline.schema.json", "/properties/years/items"),
        ("HeadlineFile", HeadlineFile.knownKeys, "headlines.schema.json", ""),
        ("HeadlineSummary", HeadlineSummary.knownKeys, "headlines.schema.json", "/$defs/summary"),
        ("Headline", Headline.knownKeys, "headlines.schema.json", "/$defs/headline"),
        ("ImportProfile", ImportProfile.knownKeys, "import-profile.schema.json", ""),
        ("ImportFileSettings", ImportFileSettings.knownKeys, "import-profile.schema.json", "/properties/file"),
        ("ImportConstants", ImportConstants.knownKeys, "import-profile.schema.json", "/properties/constants"),
        ("ImportMatches", ImportMatches.knownKeys, "import-profile.schema.json", "/properties/matches"),
        ("ImportColumn", ImportColumn.knownKeys, "import-profile.schema.json", "/$defs/column"),
        ("ImportFormat", ImportFormat.knownKeys, "import-profile.schema.json", "/$defs/format"),
        ("ImportDateFormat", ImportDateFormat.knownKeys, "import-profile.schema.json",
         "/$defs/format/properties/date"),
        ("ImportNumberFormat", ImportNumberFormat.knownKeys, "import-profile.schema.json",
         "/$defs/format/properties/number"),
    ]

    @Test func everyKnownKeyIsInItsSchemaAndNoMore() throws {
        for object in Self.objects {
            let (schema, _) = try #require(validator.resolve("#\(object.pointer)", from: object.file),
                                           "\(object.name): \(object.file)#\(object.pointer)")
            let properties = Set(schema["properties"]?.objectValue?.keys.map { $0 } ?? [])
            let onlyInModel = object.keys.subtracting(properties).sorted()
            let onlyInSchema = properties.subtracting(object.keys).sorted()
            #expect(properties == object.keys,
                    "\(object.name): only in the Model \(onlyInModel), only in the schema \(onlyInSchema)")
        }
    }

    /// Every Model type with fixed keys is in ``objects``, so a new one
    /// can't go without a schema.
    @Test func everyTypeWithKnownKeysIsCovered() throws {
        let model = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/Model")
        let files = try #require(FileManager.default.enumerator(atPath: model.path)).compactMap { $0 as? String }
            .filter { $0.hasSuffix(".swift") }
        var types: Set<String> = []
        for file in files {
            let text = try String(contentsOf: model.appendingPathComponent(file), encoding: .utf8)
            for line in text.split(separator: "\n") where line.contains("KnownKeysProviding")
                && line.contains("public struct ") {
                if let name = line.split(separator: "struct ").last?.split(separator: ":").first {
                    types.insert(String(name).trimmingCharacters(in: .whitespaces))
                }
            }
        }
        #expect(!types.isEmpty)
        #expect(types.subtracting(Self.objects.map(\.name)).sorted() == [])
    }

    // MARK: What the app writes

    /// Decodes `json` as `type`, encodes it the way the app writes files,
    /// and checks the result against `schema`.
    private func checkRoundTrip<T: Codable>(_ type: T.Type, _ json: String, against schema: String) throws {
        let value = try JSONDecoder().decode(T.self, from: Data(json.utf8))
        let written = try CanonicalJSON.json(encoding: value)
        let problems = validator.validate(written, against: schema)
        #expect(problems.isEmpty, "\(T.self): \(problems.joined(separator: "\n"))")
        // Nothing of the full document was dropped on the way.
        let original = try CanonicalJSON.parse(Data(json.utf8))
        #expect(written == original, "\(T.self) didn't round-trip")
    }

    @Test func aPlanWithEveryFieldMatches() throws {
        try checkRoundTrip(PlanDocument.self, """
            {
              "assumptions": {
                "correlations": { "equity": { "bonds": "0.1", "crypto": "0.4" } },
                "inflation": "0.02",
                "returns": {
                  "bonds": { "real": "0.017", "volatility": "0.06" },
                  "equity": { "incomeYield": "0.02", "medianReal": "0.05", "real": "0.063334", "volatility": "0.17" }
                }
              },
              "contributions": [
                { "account": "fondo-pensione", "perYear": "5000", "until": "2040-12-31" },
                { "account": "fondo-pensione", "amount": "20000", "year": 2030 }
              ],
              "endAge": 95,
              "events": [
                { "age": 62, "amount": "150000", "name": "Inheritance", "probability": "0.8" },
                { "amount": "-25000", "name": "New car", "year": 2031 }
              ],
              "id": "base",
              "name": "Base case",
              "pensions": [{ "fromAge": 67, "name": "State pension", "perYear": "14000" }],
              "portfolio": {
                "exclude": ["casa"],
                "start": "2026-09-30",
                "targetMix": { "bonds": "0.2", "equity": "0.8" },
                "targetMixByAge": [
                  { "fromAge": "retirement", "mix": { "bonds": "0.4", "equity": "0.6" } },
                  { "fromAge": 75, "mix": { "bonds": "0.6", "equity": "0.4" } }
                ],
                "unrealizedGainShare": "0.2"
              },
              "retirement": { "age": "earliest" },
              "simulation": { "confidence": "0.9", "runs": 2000, "seed": 7 },
              "spending": {
                "flexible": { "cut": "0.1", "enabled": true, "floor": "0.8", "lowerGuardrail": "0.2", "upperGuardrail": "0.2" },
                "phases": [{ "factor": "0.9", "fromAge": 75 }],
                "retired": "36000",
                "working": "36000"
              },
              "tax": { "investmentRate": "0.26", "wealthAllowance": "5000", "wealthRate": "0.002" },
              "work": [{ "from": "2026-01-01", "name": "Employee", "netIncome": "40000", "realGrowth": "0.01", "until": "retirement" }]
            }
            """, against: "plan.schema.json")
    }

    @Test func aMonthWithEveryKindOfRecordMatches() throws {
        try checkRoundTrip(MonthFile.self, """
            {
              "fx": [{ "base": "EUR", "date": "2026-09-30", "quote": "USD", "rate": "1.1712", "source": "ecb" }],
              "indices": [{ "date": "2026-09-30", "index": "hicp-it", "source": "eurostat", "value": "128.41" }],
              "month": "2026-09",
              "prices": [{ "currency": "EUR", "date": "2026-09-30", "instrument": "btc", "price": "95120", "source": "coingecko" }],
              "trades": [
                {
                  "account": "directa", "amount": "-1356", "cost": "1356", "currency": "EUR", "date": "2026-09-12", "fees": "5",
                  "id": "q4nkf6gi", "instrument": "vwce", "note": "monthly", "price": "134.75", "quantity": "10", "ratio": "2",
                  "settlement": "external", "source": "import", "tax": "2.5", "type": "buy"
                }
              ],
              "valuations": [
                { "account": "conto-fineco", "balance": "4210.55", "date": "2026-09-30", "flow": "-310.2", "note": "statement", "source": "manual" },
                { "account": "directa", "cash": "312.1", "date": "2026-09-30", "positions": [{ "costBasis": "50000", "instrument": "vwce", "quantity": "423" }] }
              ]
            }
            """, against: "history-month.schema.json")
    }

    @Test func accountsInstrumentsAndSettingsWithEveryFieldMatch() throws {
        try checkRoundTrip(Account.self, """
            {
              "assetClasses": { "bonds": "0.4", "equity": "0.6" }, "availableFromAge": 67, "closed": "2030-12-31", "country": "IT",
              "currency": "EUR", "id": "fondo-pensione", "includeIn": { "netWorth": true, "plan": false }, "institution": "Fondo Esempio",
              "kind": "pensionFund", "name": "Fondo pensione", "notes": "joined at work", "opened": "2022-01-01", "successor": "new-fund",
              "tags": ["pension"], "valuation": "balance"
            }
            """, against: "account.schema.json")
        try checkRoundTrip(Instrument.self, """
            {
              "assetClasses": { "equity": "1" }, "currency": "EUR", "id": "vwce", "isin": "IE00BK5BQT80", "kind": "etf",
              "name": "Vanguard FTSE All-World", "priceSource": { "provider": "yahoo", "symbol": "VWCE.DE" }, "ticker": "VWCE", "unit": "share"
            }
            """, against: "instrument.schema.json")
        try checkRoundTrip(LibrarySettings.self, """
            {
              "baseCurrency": "EUR", "inflationIndex": "hicp-ea", "mainPlan": "base",
              "person": { "birthDate": "1988-04-12", "name": "Alex Example" }, "schemaVersion": 3, "taxResidence": "IT"
            }
            """, against: "library.schema.json")
    }

    @Test func projectionsWithEveryFieldMatch() throws {
        try checkRoundTrip(HeadlineFile.self, """
            {
              "headlines": [
                {
                  "confidence": "0.9", "date": "2026-09-30", "earliestAge": 54, "engine": "1.2.0",
                  "planHash": "5c1f", "readiness": "0.07", "successAtTarget": "0.86"
                }
              ]
            }
            """, against: "headlines.schema.json")
        try checkRoundTrip(Baseline.self, """
            {
              "accounts": ["conto-fineco"], "created": "2026-01-05", "engine": "2.0.0",
              "headline": { "confidence": "0.9", "earliestAge": 54, "readiness": "0.5", "successAtTarget": "0.83" },
              "kind": "manual", "label": "Before part-time", "plan": { "id": "base" }, "start": { "date": "2025-12-31", "value": "212400" },
              "years": [{ "expected": "231500", "p10": "214800", "p25": "223900", "p50": "230900", "p75": "238200", "p90": "249700", "savings": "18000", "year": 2026 }]
            }
            """, against: "baseline.schema.json")
    }

    @Test func anImportProfileWithEveryFieldMatches() throws {
        try checkRoundTrip(ImportProfile.self, """
            {
              "columns": [
                {
                  "account": "directa", "base": "EUR", "currency": "EUR", "field": "amount",
                  "format": { "amountSign": "fromType", "empty": "zero", "liabilitySign": "asWritten", "number": { "percent": true } },
                  "header": "Importo", "index": 3, "instrument": "vwce", "quote": "USD", "target": "balance"
                }
              ],
              "constants": { "account": "directa", "base": "EUR", "currency": "EUR", "instrument": "vwce", "quote": "USD", "settlement": "external" },
              "dateColumn": "Data",
              "defaults": { "date": { "monthOnly": "start", "pattern": "dd/MM/yyyy", "timeZone": "Europe/Rome" }, "number": { "decimal": ",", "thousands": "." } },
              "file": { "delimiter": ";", "encoding": "utf-8", "excludeRows": ["Totale"], "headerRow": 5 },
              "id": "directa-movimenti",
              "layout": "trades",
              "matches": { "accounts": { "Directa": "directa" }, "instruments": { "VWCE": "vwce" } },
              "name": "Directa, movimenti",
              "onConflict": "keep",
              "target": "price",
              "tradeTypes": { "Acquisto": "buy", "Giroconto": "ignore" }
            }
            """, against: "import-profile.schema.json")
    }

    // MARK: The validator itself

    @Test func mistakesAreReported() throws {
        let account = try CanonicalJSON.parse(Data("""
            { "currency": "eur", "id": "Conto", "kind": "cash", "name": "Conto", "opened": "2026-13-01", "nickname": "x",
              "includeIn": { "plan": "no" } }
            """.utf8))
        let problems = validator.validate(account, against: "account.schema.json")
        #expect(problems.contains { $0.hasPrefix("$.currency:") })
        #expect(problems.contains { $0.hasPrefix("$.id:") })
        #expect(problems.contains { $0.hasPrefix("$.opened:") })
        #expect(problems.contains { $0.hasPrefix("$.includeIn.plan:") })
        #expect(problems.contains("$.nickname: not in the schema"))
        // Unknown keys are kept by the app, so outside strict mode they're fine.
        #expect(!validator.validate(account, against: "account.schema.json", strict: false)
            .contains { $0.contains("nickname") })

        // An event at an age and in a year matches both of its oneOf.
        let plan = try CanonicalJSON.parse(Data("""
            { "events": [{ "age": 60, "amount": "1", "name": "Both", "year": 2030 }], "id": "p", "name": "P",
              "retirement": { "age": 55 }, "spending": { "retired": "1", "working": "1" } }
            """.utf8))
        #expect(validator.validate(plan, against: "plan.schema.json")
            .contains("$.events[0]: matches 2 of oneOf, not exactly one"))
    }
}
