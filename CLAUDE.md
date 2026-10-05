# CLAUDE.md

Guidance for engineers and AI sessions working in this repository. Start with [docs/PLAN.md](docs/PLAN.md); the file format is in [docs/FILE_FORMAT.md](docs/FILE_FORMAT.md).

## Build and test

```sh
swift build
swift test
swift test --filter ModelTests          # one test target
swift run retire --help                 # the CLI
```

- **Cloud sessions (Linux):** the Swift toolchain is in `/opt/swift/usr/bin`, not on the PATH. Prefix every shell command that uses Swift with `export PATH=/opt/swift/usr/bin:$PATH;`. Keep the default build directory (`.build`).
- **The app** can only be built on a Mac: `brew install xcodegen && xcodegen generate --spec App/project.yml`, then open `App/CanIRetireYet.xcodeproj`. The project is generated, never committed. CI (`.github/workflows/ci.yml`) builds the package on Linux and macOS, and the app for the iOS Simulator and the Mac.
- `swift build` and `swift test` must pass with no warnings in our code before every commit.
- **Stale builds:** after a change to a stored property of a Model type, an incremental build can link stale objects. The symptom is an "undefined reference" linker error, or a test crashing with signal 11 while releasing that type. `rm -rf .build` and rebuild before looking for a code bug.
- **SwiftUI code can't be compiled on Linux.** App changes are only checked by CI's macOS job. Its `xcodebuild -quiet` log ends with the compiler errors.

## Module map

| Module | What it is | Depends on |
| --- | --- | --- |
| `Model` | The library's data model: every file type, decimals, dates, IDs, `Library`. **Shared contract.** | — |
| `Tracker` | Net-worth math: `Valuator` (values on a date), series, breakdowns, flows, performance; trades (`TradeLedger`: holdings, average cost, gains; converting and editing); the CSV export (`CSVExport`) | Model |
| `Storage` | Library folder ⇄ `Library`: JSON writer, validation, migrations, merging | Model |
| `Importer` | CSV reading, format detection, column mapping, import profiles | Model |
| `Prices` | Price, FX and inflation-index providers | Model |
| `Planner` | Simulation engine (docs/PLANNER.md): income after tax, two tax rates set by hand, no tax law | Model, Tracker |
| `CloudSync` | iCloud container, file coordination, change watching; Apple-only code inside `#if canImport(Darwin)` | Model, Storage |
| `TestSupport` | Test helpers and the made-up example library (`Fixtures`) — tests only, not a product | Model |
| `RetireCLI` | The `retire` commands (Swift Argument Parser), a library so `RetireCLITests` can run them | Model, Tracker, Storage, Importer, Planner, Prices |
| `retire` | Command-line tool: the executable that starts `RetireCLI` | RetireCLI |
| `App/` | SwiftUI app for iPhone, iPad and Mac (XcodeGen) | all library products |

Rules:

- Dependencies only point the way the table says. Add a new edge only with a reason, in `Package.swift`'s `libraries` table. Test targets that need more (e.g. `ImporterTests` checks imported trades with Tracker's `TradeLedger`) list it in its `testDependencies` table.
- `Model` depends on nothing.
- Only `CloudSync` and `App/` may use Apple-only frameworks. Everything else builds and tests on Linux.
- No third-party dependencies in the library modules (Foundation only). The CLI may use Swift Argument Parser.

## Shared contract: Model

Every other module builds on `Model`, and the app and the CLI read and write the library's files through it, so change their public API with care:

- **Until the first public release (1.0)**, the API may also shrink: removing or renaming something public, or dropping a field or a compatibility path for versions that never shipped, is allowed when the commit message says why and every caller (Sources, App, Tests, docs) is updated in the same change. Files that existing libraries contain must still load: what a library may hold stays readable (an unknown key survives, an unknown open-enum value decodes), or a migration in Storage converts it.
- **From 1.0 on, additive changes only:** new types, new optional fields, new cases on open enums, new methods, new protocol requirements *with default implementations*. Never rename, remove or change the meaning or type of anything public.
- **State the reason in the commit message** of any commit that changes `Sources/Model` (e.g. "Model: add `Account.iban` (optional), needed by the RW helper").
- A change to the file format also updates its JSON Schema in docs/schema (`JSONSchemaTests` fails until the schema and the Model's `knownKeys` agree), docs/FILE_FORMAT.md where behaviour changes (or PLANNER.md, IMPORT.md, PROGRESS.md), the example library, and the round-trip tests. Adding optional fields keeps `schemaVersion`; anything else is a new schema version with a migration in Storage.

## Conventions

- **Money types.** `Decimal` in `Model` and `Tracker` (and Storage, Importer, Prices); decimals are written to JSON as strings in their shortest exact form (`"1500"`, `"0.1"`) and read from strings or numbers, never through `Double`. Use the container helpers `decodeDecimal(forKey:)`, `decodeDecimalIfPresent(forKey:)`, `encodeDecimal(_:forKey:)`. `Double` in `Planner`: the simulation is an estimate.
- **Dates.** `CalendarDate` (`"YYYY-MM-DD"`) and `YearMonth` (`"YYYY-MM"`); no time zones in the model. Convert a `Date` only at the edges (`CalendarDate(date, in: timeZone)`). `CalendarDate("2026-09-30")` with a literal is a literal (it traps if invalid); parse user input from a `String` variable, which returns an optional.
- **Open enums.** Every "kind"-like field is a `RawRepresentable` string struct conforming to `OpenEnum`, with static constants, so values written by a newer app still decode. Typed IDs (`AccountID`, `InstrumentID`, `PlanID`, …) are `SlugID` string structs. Don't add Swift `enum`s for values stored in files.
- **Defaults are computed, not stored.** Stored properties mirror the JSON exactly (optional when the key is optional); defaults from the docs are computed properties, usually named `effective…` (`plan.effectiveEndAge`) or by what they answer (`account.valuationMode`, `account.includedInPlan`). Files stay minimal: empty collections and empty sections are left out.
- **Unknown keys survive.** Every JSON object type with fixed keys exposes `static var knownKeys`; Storage keeps other keys when it rewrites a file. Free-form objects are `[String: JSONValue]`.
- **Records have keys.** `Valuation.key` (account + date), `Trade.key` (account + date + trade ID), `PriceRecord.key`, `FXRecord.key`, `IndexRecord.key`, `Headline.key`; keys sort by date, then ID, which is the order records are written in.
- **Trades accounts.** An account with `"valuation": "trades"` gets its holdings from its trades (docs/TRADES.md). Read what an account holds with `Valuator.snapshot(of:on:)` or `holdings(of:on:)`, not from its latest valuation's `positions`, which for such an account are only a reconciliation check.
- **Files.** One type family per file; public API has short doc comments.
- **Tests.** Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest. One test target per module (`<Module>Tests`), each depending on `TestSupport`. Use `Fixtures.exampleLibrary()` for a ready `Library` without depending on Storage.
- **Made-up data only.** Never commit real financial data, real account numbers or personal details. The example library (`Sources/TestSupport/Resources/ExampleLibrary/`) is fake; keep it consistent with FILE_FORMAT.md, and when you change it, keep the tests that check its totals in step.
