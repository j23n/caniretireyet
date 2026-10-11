# Plan

> Status: reviewed once (answers in §8). The planner is in [PLANNER.md](PLANNER.md), the importer is in [IMPORT.md](IMPORT.md), and accounts that record trades are in [TRADES.md](TRADES.md).

## 1. What we're building

A private app for iPhone and Mac with two halves:

1. **Tracker.** Once a month you check in and record what each account is worth. Cash accounts, pension funds, property and debts are recorded as a balance. For ETFs, crypto and gold you record the quantity, and the app multiplies it by the price. An investment account can instead record its trades (buys, sells, deposits, dividends), and its holdings, purchase cost and realised gains are worked out from them ([TRADES.md](TRADES.md)). Accounts are opened and closed over the years, and their history is kept either way.
2. **Planner.** Scenarios that start from your latest check-in and simulate the years ahead, covering:
   - work and savings, from income after tax;
   - spending in retirement;
   - pensions, after tax, from your pension statements;
   - windfalls and large expenses;
   - a tax rate on investment gains and income, and an optional wealth tax, set by hand.

   The result answers the question in the app's name: **can I retire yet, and if not, at what age, and how confident is that?**

All data lives in a folder of plain JSON files in iCloud Drive. The apps on your iPhone and Mac both read and write that folder.

### Principles

- **Files are the source of truth.** The data outlives the app. You can read it, back it up, put it in git, or edit it by hand.
- **Offline-first and private.** There is no server, no analytics and no third-party SDKs. Only instrument symbols ever leave the device, when prices are fetched, and an instrument's ISIN, ticker or name when you search for its symbol. (Debug builds can also send feedback you write, with a screenshot whose amounts are hidden, to the developer's private GitHub inbox; release builds can't: [App/README.md](../App/README.md#feedback).)
- **The monthly check-in should take under five minutes.** Values are pre-filled, prices are fetched for you, and you only change what moved.
- **History is never lost.** Closing an account removes it from today's totals and from check-ins, but not from the charts.
- **Plans start from real data.** The planner's starting portfolio is your latest check-in, not a number you type in.
- **Honest numbers.** Results show ranges and a confidence level, and every assumption is visible and editable. They are estimates, not tax advice.

## 2. Scope

### MVP (this branch: `feat/mvp`)

**Tracker**

- Accounts: create, edit, close and reopen them. Closed accounts stay in the history.
- Holdings: ETFs and stocks, crypto, and precious metals are recorded as quantity × price. Cash, pension funds, TFR, property and debts are recorded as a balance.
- Multiple currencies, with one base currency for the library (the euro in the example library), which plans run in. Every check-in stores the prices and FX rates it used.
- Monthly check-in:
  - pre-filled from the previous check-in;
  - prices and FX rates fetched automatically where possible;
  - every value editable.
- Overview:
  - net worth over time;
  - breakdowns by category, asset class, currency and institution;
  - the change since the last check-in, split into market movement and new money;
  - accounts that haven't been updated recently.
- Import from any spreadsheet or CSV export: you map the columns, the importer handles the file's date and number formats, and the mapping can be saved and reused ([IMPORT.md](IMPORT.md)).
- Money in and out of each account (the *flow*), recorded at every check-in with sensible defaults. Savings and returns can then be measured later ([PROGRESS.md](PROGRESS.md)).
- Sync between iPhone and Mac through iCloud Drive.

**Planner**

- Scenarios ("plans"), one file each.
- Working years:
  - phases of work, each with its income after tax and optional real growth;
  - contributions into specific accounts, such as a pension fund;
  - savings, calculated as income after tax minus spending.
- Retirement years:
  - spending, optionally in phases, and optionally flexible: cut after bad years, never below a floor;
  - pensions after tax, each from an age;
  - accounts that can be drawn only from an age, such as a pension fund;
  - windfalls and one-off expenses.
- Taxes set by hand: one rate on the gain part of sales and on investment income, and an optional wealth tax above an allowance ([PLANNER.md](PLANNER.md#the-model-in-brief)).
- A target mix, changing with age, that the portfolio is rebalanced to every year.
- A deterministic projection plus a Monte Carlo simulation, which produce:
  - the headline answer;
  - the earliest retirement age at your chosen confidence level;
  - charts.
- Progress ([PROGRESS.md](PROGRESS.md)):
  - your history and your projection on one chart;
  - the headline answer recorded at every check-in;
  - baselines (saved projections), with your actual line drawn over them.

### Later

These are listed as M3 and M4 in §6: explaining the gap to a baseline, the RW/IVAFE helper, historical return sequences, and partner planning. Transaction-based cost basis is done: accounts can record trades ([TRADES.md](TRADES.md)). So are the widgets ([UI.md](UI.md#widgets)).

### Non-goals

- Connecting to banks or brokers (PSD2 and similar). Manual monthly check-ins are a deliberate design choice, not a gap.
- Budgeting or categorising expenses.
- Investment advice or tax filing.
- Android, Windows or web versions.

## 3. Key decisions

| Topic | Decision | Why |
| --- | --- | --- |
| Platform | One SwiftUI app target for iPhone, iPad and Mac. Minimum iOS 26 and macOS 26. | One codebase with a native feel on both platforms and first-class iCloud Drive APIs. A personal app doesn't need to support old OS versions. |
| Source of truth | A folder of small JSON files, called "the library". | Human-readable, diffable and easy to back up. The data is tiny (thousands of records), so no database is needed. |
| Sync | iCloud Drive, in the app's own iCloud container. It shows up as a "Can I Retire Yet" folder in Files and Finder. | No server, it works offline, and the files stay visible and editable. |
| History model | Point-in-time valuations (balances and quantities) by default. An investment account can opt in to trades (`"valuation": "trades"`): its holdings, average cost, cash and realised gains are worked out from buys, sells, deposits and the like, and its check-ins record only cash ([TRADES.md](TRADES.md)). | Valuations match the monthly workflow, and closing an account never touches its history. Trades give an exact purchase cost (*costo medio ponderato*), realised gains, dividends and exact flows for a broker account, which the tax on sales needs. Both styles work for a trades account: record every deposit, or type the cash at each check-in. |
| Money | `Decimal` for every recorded amount, stored as strings in JSON. | No floating-point rounding errors in the tracker. |
| Currencies | Each account has its own currency; the base currency is EUR. Each check-in stores the prices and FX rates it used. | Past net worth can always be recomputed, even if a price source goes away. |
| Planner | Yearly steps in today's money, in the base currency, deterministic plus Monte Carlo, with a seeded random-number generator. | This approach is standard and easy to explain. It is also fast enough to recompute live while you drag a slider. |
| Taxes | No tax law. Income from work and pensions is entered after tax; investments pay one rate on gains and income, and an optional wealth tax, both set by hand. | An earlier version modelled the Italian, Swiss and German systems in detail. They were hard to get right, harder to check, and still estimates; a few rates you can see beat rules you can't. The research is kept in [research/tax](research/tax/). |
| Code layout | A Swift package of platform-independent modules, plus a thin app target. | Most of the logic can be built and tested on Linux, in CI and in cloud sessions. Only the UI needs Xcode. |
| Xcode project | Generated from `project.yml` at the root with XcodeGen. | The project definition is readable text, there are no `.pbxproj` merge conflicts, and it can be edited without Xcode. |
| Dependencies | None in the core modules (Foundation only). The CLI uses Swift Argument Parser. | Fewer moving parts, and the core builds on Linux. |

## 4. Architecture

### Repository layout

```
caniretireyet/
├── Package.swift
├── Sources/
│   ├── Model/        the library's data model: every file type, decimals, dates, IDs
│   ├── Tracker/      net-worth math: values, series, breakdowns, flows
│   ├── Storage/      library folder ⇄ model: JSON codec, validation, migrations, merging
│   ├── Importer/     CSV reading, format detection, column mapping, import profiles
│   ├── Planner/      simulation engine and return model
│   ├── Prices/       price and FX providers
│   ├── CloudSync/    iCloud container, coordinated file access, downloading, change watching (Apple only)
│   ├── RetireCLI/    the `retire` commands, a library so they can be tested
│   └── retire/       command-line tool: validate, import, net worth, prices, run a plan
├── Tests/            one test target per module; fixtures are a fake example library
├── project.yml       XcodeGen spec → CanIRetireYet.xcodeproj (generated, not committed)
├── App/
│   ├── Sources/      SwiftUI app shared by iPhone and Mac
│   └── Resources/
├── docs/
└── .github/workflows/
```

Module dependencies:

- `Model` depends on nothing.
- `Tracker`, `Storage`, `Importer` and `Prices` depend on `Model`.
- `Planner` depends on `Model` and `Tracker`.
- `CloudSync` depends on `Storage`.
- The `retire` CLI and the app sit on top.

Only `CloudSync` and the app need Apple frameworks.

### How the app works at runtime

1. **Load.** At launch, `CloudSync` finds the iCloud container. If iCloud is off, it uses a local folder that can be moved to iCloud later. For a library in iCloud Drive, `CloudSync` first makes sure every file is on the device, downloading the missing ones all at once with progress (see "Sync with iCloud Drive"). `Storage` then loads the whole library into memory, which takes milliseconds because it's small. The opening screen says which step it's at, and never dead-ends.
2. **Edit.** The UI reads from an `@Observable` `LibraryStore`. An edit changes the in-memory model first. `Storage` then writes only the files that changed. Writes are atomic and go through `NSFileCoordinator`. Each write is merged with the file on disk, so a change that arrived from the other device (or a text editor) and hasn't been reloaded yet is never overwritten unseen ([Merging, saving and undo](#merging-saving-and-undo)); the store then reloads what was merged in.
3. **Watch.** `CloudSync` watches the folder: an `NSMetadataQuery` for a library in iCloud Drive (which also downloads files that aren't on the device yet), or by comparing modification dates for a library on this device. When the other device, or you in a text editor, changes a file, the store reloads that file and the UI updates.
4. **Plan.** The planner runs in a background task on an immutable snapshot of the library and the plan. It recomputes after changes (debounced), so the results stay live while you edit a plan.

### Sync with iCloud Drive

- **Location.** The library is the `Documents/` folder of the app's iCloud container. Files are downloaded eagerly because they're tiny, before the library is read and whenever they change, so the "Optimize Storage" setting never leaves gaps.
- **Keeping conflicts rare.** There is one file per account, instrument and plan. History is grouped by month, so a check-in touches one file and past months are rarely edited. Unchanged files are never rewritten.
- **Resolving conflicts.** When two devices change the same file before syncing, iCloud keeps both versions (`NSFileVersion`). The app merges them record by record, marks the conflict resolved, and shows what it merged on a Sync screen ([Merging, saving and undo](#merging-saving-and-undo)).
- **Saving over a newer file.** A file can also change on disk between the app reading it and writing an edit to it. The write merges with it: record by record for history and headlines, and for other files with a copy in `backups/` before replacing it ([Merging, saving and undo](#merging-saving-and-undo)). The Sync screen lists these too.
- **Not missing changes.** The store records every file's modification date when it loads the library, and the watcher's first look is compared with them, so a change that lands while the library loads is reloaded too. When the app comes back to the foreground it compares modification dates again.
- **First launch on a new device.** A library in iCloud Drive may not be on the device yet. Before offering to create a new one, the app asks iCloud Drive whether `library.json` exists (an `NSMetadataQuery`), waiting up to a few seconds for the answer, so the second device opens the existing library instead of creating another.
- **Downloading before reading.** A file iCloud Drive hasn't downloaded is only a placeholder, and a coordinated read of it waits until it's downloaded. Read one by one, a library of a few hundred files (an import back to 2017 makes over a hundred months) would take minutes, and never finish offline. So before reading, the app lists the library's files (the folder on disk, then an `NSMetadataQuery` with each file's download status, size and error), asks iCloud for every missing one at once, and shows "Downloading n of N files from iCloud Drive" with a bar until they're all here. Reads stay coordinated, but no longer wait on the network. A library already on the device is read at once.
- **Never stuck.** If nothing moves for 20 seconds while opening, the app says it's still waiting for iCloud Drive, lists the likely reasons (offline, cellular data off for iCloud Drive, Low Power Mode, iCloud Drive off for the app), and offers Try Again and Keep Waiting. It never offers to create a library then, since that would duplicate the one that hasn't arrived. Each step of opening is logged (`os.Logger`, category `library`), so Console shows where it stops.
- **Schema guard.** Every library records a `schemaVersion`. An app that finds a newer version than it understands opens the library read-only and asks to be updated. That way an old app on one device can't damage data written by a newer app on the other. A `library.json` that exists but can't be read makes the library read-only too, also when it breaks while the library is open, until it's fixed or restored from a backup: the app would otherwise save default settings over yours ([schema/README.md](schema/README.md#reading-hand-edited-files)).

### Merging, saving and undo

How the app treats the files when two copies differ. History and headline files merge **record by record**, matched by their keys: account + date (valuations), account + date + trade ID (trades), instrument + date (prices), currency pair + date (FX rates), index + date (inflation values), and check-in date (headlines). Other files are taken whole.

- **Sync conflicts.** When two devices change the same file before it syncs, iCloud keeps both versions, and the app merges them. History and headline files: every record from every version, and where versions disagree about a record, the most recently modified version wins. Other files: the most recently modified version wins. Versions modified at the same moment are ordered by their contents, so both devices resolve a conflict the same way; within one version, the later of two records with the same key counts, as when loading. Everything else in a merged history or headline file (its unknown keys, for example) comes from the newest version, and the result is written in the canonical layout. A version that isn't valid JSON is left out. Before the merge replaces the file and iCloud's other versions are removed, each version that differs from the result is copied to its own `backups/<timestamp>-conflict/`, so nothing a merge drops is lost; merges are listed on the Sync screen. (A three-way merge against the last-synced copy, which would also merge deletions, is for later.)
- **Saving over a file changed on disk.** The app writes only the files an edit changed, and each write compares the file on disk with the version the app last read, so a change it hasn't seen yet (the other device's, or one made in a text editor) is never lost. History and headline files: a three-way merge record by record, with the version the app read as the common base. A record changed only on disk keeps the disk's version; one changed only in the app gets the app's; one changed on both sides gets the app's version, unless the app deleted it, when the changed record is kept. Records added on disk, keys the app doesn't know, and records it can't read are kept; when records changed on both sides, the file is first copied to `backups/<timestamp>-conflict/`. Other files: the app's version is written, after the file on disk is copied to `backups/<timestamp>-conflict/`; a file the app deletes is kept instead. Reading, merging and writing a file is one coordinated operation, so a version iCloud Drive delivers meanwhile is merged as well; the Sync screen lists what happened, and the app reloads the merged file.
- **Unreadable files.** A file that couldn't be read when the library loaded is copied to `backups/<timestamp>-unreadable/` before the app replaces or deletes it; unless it's a history or headline file, the app's version doesn't keep its unknown keys, which the copy has. `library.json` is never replaced: the settings the app would write are only defaults ([schema/README.md](schema/README.md#reading-hand-edited-files)).
- **Backups.** `backups/<yyyy-MM-dd-HHmmss>-<label>/` (in the device's local time), with the label `import`, `undo-import` (the files as they were before an undo), `fill-history` (*Fill In Past Prices*), `delete-account`, `convert-to-trades` or `convert-to-snapshots` (the app), `prices` or `settings` (the CLI), `restore` (the files as they were before a backup was restored over them), `conflict` or `unreadable`, and `backups/<yyyy-MM-dd>-v<old>/` for a migration; a second backup with the same name gets `-2`, `-3`, …. Each mirrors the library's layout, with a `backup.json` ([backup.schema.json](schema/backup.schema.json)). After an edit that backs up the files it changes (all of these but `undo-import`, `restore`, `conflict`, `unreadable` and a migration), the files as the edit wrote them are copied to the backup's `result/`.
- **Undo import** (the app, `retire import --undo`) compares each file now with the import's `result` and with the copy from before the import. A file unchanged since the import is put back as it was before it, and a file the import created is deleted. In a history or headline file changed since, records unchanged since the import go back to how they were before it (records it added are removed), and records changed since keep their new values. Any other file changed since is left as it is. What was left in place is listed. A backup without `result` is restored as it is, and a backup is only restored into a library with the same `schemaVersion`.

### App structure

The iPhone uses a tab bar and the Mac uses a sidebar. The iPad gets the sidebar layout for free.

- **Overview.** Shows:
  - the main plan's answer to *Can I retire yet?*, first when there is one, with the time to go;
  - net worth today;
  - a chart over time, stacked by category;
  - the change since the last check-in, split into market and new money;
  - the change this year, split the same way, with the savings rate when money in and out are recorded;
  - breakdowns;
  - accounts that haven't been updated recently;
  - a *past and future* switch that continues the chart into the plan's projection;
  - whether you're ahead of or behind the year's baseline, as Progress measures it;
  - how close your plan assets are to what retiring today needs, taken from the active plan ([PLANNER.md](PLANNER.md#assets-needed-to-retire-today)).
- **Accounts.** A grouped list, with closed accounts in a collapsed section. The account detail shows a value chart, the list of valuations, and actions to edit, close or reopen.
- **Check-in.** The main action. The steps are:
  1. Choose the date (default: today).
  2. Review prices and FX rates. They're fetched for you and can be edited.
  3. Update the accounts, pre-filled with last time's values. "Unchanged" is one tap.
  4. Review the new total and the changes.
  5. Save.
- **Plan.** Two parts:
  - *Plan*: the answer, then your life as a strip of chapters (working, retired before the pensions, with them), each with the money running through it and where it stands at its end, and the chosen chapter in words, with its settings, where the plan changes; the charts behind the answer fold away;
  - *Progress*: whether you're on track, then year by year your money against what January expected and how the answer moved, and your actual numbers against baselines.

  What-ifs are a sheet on iPhone and the inspector on the Mac. Plans can be duplicated as what-if scenarios. The screens are designed in [UI.md](UI.md).
- **Settings.** Library location, price sources, a monthly reminder, app lock, and a description of the file format.

On the Mac there are also tables for editing many valuations at once, keyboard navigation through the check-in, and "Show library in Finder".

### Prices and FX

- Every price can be typed in by hand. Automatic fetching is opt-in per instrument.
- **FX:** ECB reference rates through Frankfurter, which is free and needs no key.
- **Crypto:** CoinGecko, or an exchange's public ticker. The symbol is the coin's CoinGecko ID or its ticker (`ETH`), which is resolved to an ID through a built-in table of well-known coins or CoinGecko's search. An optional demo API key, kept in the Keychain, raises its rate limit. CoinGecko's free API only has the last 365 days; older prices come from Yahoo Finance's crypto pairs (below).
- **Gold and silver:** a free spot-price API (gold-api.com, USD per troy ounce, converted to the instrument's currency and unit), or the market price of a physical-gold ETC as a proxy. gold-api.com only has today's spot price, so past prices come from the metal's front-month futures on Yahoo Finance: `GC=F` for gold (`XAU`), `SI=F` for silver, `PL=F` for platinum and `PA=F` for palladium, all in USD per troy ounce and converted the same way. Futures trade within about 1% of spot, so these are an approximation; the price list says so ("Yahoo Finance · GC=F (history)"), and the instrument keeps `gold-api` as its price source.
- **ETFs on European exchanges:** there's no reliable free official API. We'll start with Yahoo Finance's public chart endpoint. It's unofficial and can break, so providers are pluggable, and a paid one with your own key (EODHD, Twelve Data) can be added.
- **Finding a symbol.** Nobody should have to know that VWCE trades as `VWCE.DE` on XETRA. Yahoo Finance's search endpoint (`v1/finance/search?q=<ISIN, ticker or name>&quotesCount=10&newsCount=0`, `Prices.YahooSymbolSearch`) lists an instrument's listings: symbol, name, exchange, kind and, when it says, currency. The instrument editor's *Find…*, the import's *Find Price Sources…* for the instruments it created ([UI.md](UI.md#import-mac-first)) and `retire instruments find <instrument> [--set <symbol>]` search by the ISIN, else the ticker, else the name, and suggest the first listing in the instrument's currency (`SymbolCandidate.preferred(among:currency:)`), which you confirm.
- **Inflation:** a consumer-price index, fetched with the FX rates for the months the library is missing: the library's (`inflationIndex` in `library.json`, by default the index of the tax residence, else of the base currency; [library.schema.json](schema/library.schema.json)). Each index has a provider (`InflationIndexProvider`): Eurostat's HICP (`prc_hicp_minr`, all items, 2015 = 100) covers every EU country, Iceland, Norway, Switzerland, the candidate countries and the euro area (`hicp-de`, `hicp-ch`, `hicp-ea`, …); the BLS public API (version 1, no key, at most ten years a request) has the United States' CPI-U (`cpi-us`: series `CUUR0000SA0`, all items, not seasonally adjusted, 1982–84 = 100); the ONS time-series download has the United Kingdom's CPI (`cpi-gb`: series D7BT of MM23, all items, 2015 = 100), the whole series as CSV, of which the monthly rows are read. Other indices are added as providers.
- **Dates:** each value is the latest on or before the check-in date and is recorded on that date. The price list shows the day it's from, e.g. Friday's close for a Sunday check-in.
- Fetched prices are cached on the device. Only the prices used in a check-in are written to the library.
- **Rate limits.** Free APIs allow only a few calls a minute, so at most four instruments are fetched at once (`PriceService.maxConcurrentFetches`), and a check-in's CoinGecko coins are priced in one `simple/price?ids=bitcoin,ethereum,…` call, in every currency asked for.
- **Past prices.** An import, or history added by hand, can leave years of positions without a price for their dates: gold bought long ago stays at its purchase price in every month since. *Fill In Past Prices* (the Instruments screen, the import's last step, a note under a chart, `retire prices --fill-history`) finds every date the library values a position on without a price for that day (each valuation, and the month ends it's carried over to in months without one of its own), the FX rates those dates need, and the missing inflation months, and fetches them in as few requests as possible:
  - **One history per instrument.** Each provider says where its past prices come from, best first, and each source is asked once for the whole range of dates it covers:

    | Provider | History | Reaches back |
    | --- | --- | --- |
    | Yahoo Finance | the chart endpoint with `period1`/`period2`: daily closes, or monthly ones for more than five years of month ends | the listing |
    | CoinGecko | `coins/{id}/market_chart/range` | 365 days (free API) |
    | ↳ then | Yahoo Finance `<TICKER>-<CUR>` (e.g. `ETH-EUR`), then `<TICKER>-USD` converted with ECB rates; the ticker of a coin given by its ID comes from the built-in table or CoinGecko's search | the pair's listing |
    | gold-api.com | Yahoo Finance futures: `GC=F`, `SI=F`, `PL=F`, `PA=F` | about 2000 |
    | Frankfurter (ECB) | the time series `/v1/<from>..<to>`, which may thin a long range out to weekly rates | 1999 |
    | Eurostat | the series for the missing months | 1996 |
    | BLS | the series for the missing months' years, ten years a request | 1913 |
    | ONS | the whole series | 1988 |

    A provider without a history (a price source the app doesn't fetch, or a metal without futures) is listed with its dates, not skipped.
  - **Values on or before each date.** Each date takes the latest value on or before it: up to 7 days back in a daily series (weekends and holidays; two weeks for weekly rates), or the month's close in a monthly one. The price list and results show the day it's from.
  - **Then one request per currency** for the FX rates missing and those that convert a price into its instrument's currency; a rate the library has for the day is used as it is. **One request per index.**
  - **Nothing is replaced.** Only dates without a record are filled: a price typed in, read from a file (an import) or fetched before stays. The records are written in one edit, into each date's month file, after a `fill-history` backup, with the source that answered (`yahoo` for gold from `GC=F`).
  - **What's left** is listed per instrument with the dates still missing and why (no price source, CoinGecko's year and no Yahoo pair, no listing yet), with *Set Price…* for a date and *Choose a Price Source*.
  - A check-in on a past date uses the same sources for the instruments whose provider has no price for that date.

### Importing

The importer works with any spreadsheet or export instead of a fixed layout. Details are in [IMPORT.md](IMPORT.md).

- **Files.** It reads CSV and TSV in any delimiter and encoding, including Excel's Windows-1252 exports.
- **Layouts.** Wide (one row per date, one column per account) or long (one row per record).
- **Targets.** Each column is mapped to what it holds: a balance, a quantity, a purchase cost, a price or an FX rate. A column can also be ignored.
- **Formats.** Date and number formats are detected per column and can be overridden: decimal comma or point, thousands separators, currency symbols, day-first or month-first dates, month-only dates, and Excel serial dates.
- **Preview.** A full preview shows problems highlighted before anything is written. Imports are idempotent and can be undone.
- **Profiles.** A mapping can be saved as a profile in the library and reused on the Mac, on the iPhone, or with `retire import`.

### Security and privacy

- iCloud Drive encrypts data in transit and at rest. Turning on **Advanced Data Protection** makes it end-to-end encrypted.
- The files are deliberately plain text: anyone with access to your Mac or your iCloud account can read them. That is the price of a file-based design, and there's no extra encryption in the app. An optional Face ID lock (M3) protects the app itself.
- Your real financial data never goes into this repository. The tests use a made-up example library.

## 5. Development workflow

- Most of the code is in the Swift package and doesn't depend on Apple platforms. CI runs `swift build` and `swift test` on Linux for every push. The app target (SwiftUI and iCloud) is built on a macOS runner without code signing to catch compile errors.
- Tests use Swift Testing:
  - **Format golden tests:** load the fixture library, save it again, and expect byte-identical files.
  - **Net-worth tests:** unit tests for the math.
  - **Planner checks:** cases worked out by hand, and invariants (more savings never lowers the chance of success, and the like).
  - **Importer:** a folder of sample files in awkward formats.
- One-time setup on your Mac:
  1. Join the **Apple Developer Program**, which is paid. iCloud requires it, and without it apps you install on your iPhone stop working after 7 days.
  2. Install Xcode and XcodeGen (`brew install xcodegen`).
  3. The bundle identifier is `com.j23n.caniretireyet`; a build under another team chooses its own, such as `com.<yourdomain>.caniretireyet`.
  4. Put your team ID (and your own bundle identifier, if any) in `Signing.xcconfig` at the root (`DEVELOPMENT_TEAM = …`, `APP_BUNDLE_IDENTIFIER = …`; `make signing TEAM=…` writes the team), which git ignores and every generated project reads.
  5. Run `xcodegen` at the root, then open the project.
  6. In *Signing & Capabilities*, check iCloud → iCloud Documents lists the container `iCloud.<bundle id>`.

## 6. Milestones

### M0: Foundations

- The package skeleton with the modules above, and CI on Linux.
- The domain model and file format v1, with round-trip tests against a made-up example library.
- The XcodeGen project and an app shell that creates or opens the library in iCloud Drive and lists its accounts.

**Done when:** CI passes, and the app runs on your Mac and iPhone with the example library visible in iCloud Drive.

### M1: Tracker MVP

- Accounts and instruments: create, edit, close and reopen.
- The check-in flow, with pre-filled values, fetched prices and FX rates, and manual overrides.
- The Overview: net-worth history, breakdowns, and the change since the last check-in split into market and new money. Plus the account detail screen.
- Flows recorded at each check-in, with defaults per kind of account.
- Live sync: a check-in on the iPhone appears on the Mac, and edits made directly to files are picked up.
- The importer: the engine, the mapping and preview flow in the app, saved profiles, and `retire import`.

**Done when:** your spreadsheet history is in the app, and you've done a real check-in on the iPhone and seen it on the Mac.

### M2: Planner MVP

- Plan files and a plan editor.
- The engine: yearly simulation, deterministic and Monte Carlo runs, and the earliest-retirement-age search.
- Taxes set by hand: a rate on investment gains and income, and a wealth tax.
- Income after tax, pensions, accounts available from an age, windfalls, large expenses and spending phases.
- Results:
  - the "Can I retire yet?" headline;
  - chance of success against retirement age;
  - a fan chart of the portfolio;
  - income sources and taxes per year;
  - what-if sliders.
- Progress: the past-and-future chart, the headline recorded at each check-in, yearly and hand-saved baselines, and your actual line over a baseline.

**Done when:** the plan starts from your latest check-in, and the engine matches the reference cases calculated by hand.

### M3: Hardening and polish

- Conflict merging, with the Sync screen. The schema guard. Clear errors for hand-edited files that don't parse.
- A monthly reminder notification, Face ID lock, and CSV export.
- The explanation of the gap to a baseline (done: on each year of Progress, [PROGRESS.md](PROGRESS.md#actual-vs-a-baseline)), and fetching an inflation index (any country's HICP, the euro area's, or the US or UK CPI).
- Widgets for net worth and years to go: done, on the home screen, the lock screen and the Mac's desktop ([UI.md](UI.md#widgets)).
- An RW/IVAFE helper that produces year-end values and holding periods for foreign accounts, for an Italian tax return.

### M4: Depth (pick by interest)

- Historical and bootstrapped return sequences. Variable withdrawal strategies (a guardrails rule is done: flexible spending, [PLANNER.md](PLANNER.md#flexible-spending)).
- Tracking actual income and spending, to measure your real savings rate: started, as money in and out of cash and savings accounts, and the savings rate they give with pension contributions ([PROGRESS.md](PROGRESS.md#money-in-and-out)).
- Cost basis from transactions: done, as trades ([TRADES.md](TRADES.md)), with the app's screens and broker transaction CSVs importing into them ([IMPORT.md](IMPORT.md)). Still to do: lots (FIFO).
- Reading `.xlsx` and `.numbers` files directly.
- Planning for a partner or household.

## 7. Risks

- **Unofficial price endpoints break.** Manual entry always works, and providers can be swapped.
- **Tax rules change every year, and so can your situation.** The plan takes income after tax and two rates you set, so a change is an edit to a number, and every result can be checked by hand ([PLANNER.md](PLANNER.md#calculations)).
- **iCloud Drive can be slow or create conflicts.** Small files, record-level merging and a visible sync status keep that manageable.
- **The planner could grow forever.** The MVP answers one question well, and everything else waits until M4.

## 8. Answers from the first review

1. **Apple Developer Program:** a paid membership is assumed, so iCloud is fine.
2. **Spreadsheet:** the importer maps any layout and format, and doesn't assume a particular spreadsheet ([IMPORT.md](IMPORT.md)).
3. **Bollo and IVAFE:** the same 0.2%, so in Italy they're one wealth tax rate (`tax.wealthRate` 0.002). They differ only in who pays: Italian intermediaries withhold bollo, while for foreign accounts the taxpayer pays IVAFE and declares the account in RW. Blacklisted countries pay 0.4%. The country only matters to the RW helper.
4. **iOS 26 and macOS 26** are the minimum versions.
5. **Taxes must be pluggable:** they were, as tax systems per country, and were later replaced by rates set by hand (§3, "Taxes").
