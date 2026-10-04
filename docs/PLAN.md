# Plan

> Status: reviewed once (answers in §8). The tax architecture is in [TAXES.md](TAXES.md), the importer is in [IMPORT.md](IMPORT.md), and accounts that record trades are in [TRADES.md](TRADES.md).

## 1. What we're building

A private app for iPhone and Mac with two halves:

1. **Tracker.** Once a month you check in and record what each account is worth. Cash accounts, pension funds, property and debts are recorded as a balance. For ETFs, crypto and gold you record the quantity, and the app multiplies it by the price. An investment account can instead record its trades (buys, sells, deposits, dividends), and its holdings, purchase cost and realised gains are worked out from them ([TRADES.md](TRADES.md)). Accounts are opened and closed over the years, and their history is kept either way.
2. **Planner.** Scenarios that start from your latest check-in and simulate the years ahead, covering:
   - work and savings, with taxes from a pluggable tax system per country of residence (Italy first, with its regimes such as impatriati and forfettario; Switzerland and Germany designed; a generic flat-rate system for any other country);
   - spending in retirement;
   - public pensions projected from contributions (Italy's INPS first) and any other pensions, taxed by the country of residence or the paying country;
   - windfalls and large expenses.

   The result answers the question in the app's name: **can I retire yet, and if not, at what age, and how confident is that?**

All data lives in a folder of plain JSON files in iCloud Drive. The apps on your iPhone and Mac both read and write that folder.

### Principles

- **Files are the source of truth.** The data outlives the app. You can read it, back it up, put it in git, or edit it by hand.
- **Offline-first and private.** There is no server, no analytics and no third-party SDKs. Only instrument symbols ever leave the device, when prices are fetched.
- **The monthly check-in should take under five minutes.** Values are pre-filled, prices are fetched for you, and you only change what moved.
- **History is never lost.** Closing an account removes it from today's totals and from check-ins, but not from the charts.
- **Plans start from real data.** The planner's starting portfolio is your latest check-in, not a number you type in.
- **Honest numbers.** Results show ranges and a confidence level, and every assumption is visible and editable. They are estimates, not tax advice.

## 2. Scope

### MVP (this branch: `feat/mvp`)

**Tracker**

- Accounts: create, edit, close and reopen them. Closed accounts stay in the history.
- Holdings: ETFs and stocks, crypto, and precious metals are recorded as quantity × price. Cash, pension funds, TFR, property and debts are recorded as a balance.
- Multiple currencies, with one base currency for the library (the euro in the example library); a plan can run in any currency. Every check-in stores the prices and FX rates it used.
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
  - income as an employee or self-employed, under the regimes of the residence's tax system (in Italy: forfettario or regime ordinario, with impatriati where it applies);
  - a side-by-side comparison of two regimes, e.g. forfettario against ordinario with impatriati, which can't be combined;
  - social contributions and the pension credits they earn (INPS in Italy);
  - savings, calculated as net income minus spending.
- Retirement years:
  - spending, optionally in phases;
  - public pensions projected from contributions (INPS under the contributory system first);
  - foreign and other pensions, taxed where the plan and the treaties say;
  - the pension fund and TFR;
  - windfalls and one-off expenses.
- Pluggable taxes ([TAXES.md](TAXES.md)):
  - each plan picks a tax system per period of residence, a tax regime for each work phase, and special regimes such as impatriati;
  - the Italian system ([tax/IT.md](tax/IT.md)): IRPEF, forfettario, ordinario, impatriati, INPS, pension fund, TFR, 26% / 12.5% / 33% on investments, and the 0.2% wealth tax;
  - a generic flat-rate system for rough plans in a country that has no system yet.
- A deterministic projection plus a Monte Carlo simulation, which produce:
  - the headline answer;
  - the earliest retirement age at your chosen confidence level;
  - charts.
- Progress ([PROGRESS.md](PROGRESS.md)):
  - your history and your projection on one chart;
  - the headline answer recorded at every check-in;
  - baselines (saved projections), with your actual line drawn over them.

### Later

These are listed as M3 and M4 in §6: investment performance, explaining the gap to a baseline, widgets, the RW/IVAFE helper, historical return sequences, dynamic withdrawal strategies, retiring abroad, and partner planning. Transaction-based cost basis is done: accounts can record trades ([TRADES.md](TRADES.md)).

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
| History model | Point-in-time valuations (balances and quantities) by default. An investment account can opt in to trades (`"valuation": "trades"`): its holdings, average cost, cash and realised gains are worked out from buys, sells, deposits and the like, and its check-ins record only cash ([TRADES.md](TRADES.md)). | Valuations match the monthly workflow, and closing an account never touches its history. Trades give an exact purchase cost (*costo medio ponderato*), realised gains, dividends and exact flows for a broker account, which the Italian tax treatment of sales needs. Both styles work for a trades account: record every deposit, or type the cash at each check-in. |
| Money | `Decimal` for every recorded amount, stored as strings in JSON. | No floating-point rounding errors in the tracker. |
| Currencies | Each account has its own currency; the base currency is EUR. Each check-in stores the prices and FX rates it used. | Past net worth can always be recomputed, even if a price source goes away. |
| Planner | Yearly steps in today's money, in the plan's currency, deterministic plus Monte Carlo, with a seeded random-number generator. | This approach is standard and easy to explain. It is also fast enough to recompute live while you drag a slider. |
| Taxes | The engine contains no tax rules. Tax systems (countries) and regimes (forfettario, impatriati, …) are plugins behind one interface, and plans choose them per period. Rates and thresholds live in yearly parameter files that cite their sources. | Tax law changes with every budget law, regimes come and go, and you might move. Each of these should be a new file or module, not a change to the engine. |
| Code layout | A Swift package of platform-independent modules, plus a thin app target. | Most of the logic can be built and tested on Linux, in CI and in cloud sessions. Only the UI needs Xcode. |
| Xcode project | Generated from `App/project.yml` with XcodeGen. | The project definition is readable text, there are no `.pbxproj` merge conflicts, and it can be edited without Xcode. |
| Dependencies | None in the core modules (Foundation only). The CLI uses Swift Argument Parser. | Fewer moving parts, and the core builds on Linux. |

## 4. Architecture

### Repository layout

```
caniretireyet/
├── Package.swift
├── Sources/
│   ├── Model/        the library's data model: every file type, decimals, dates, IDs
│   ├── Tracker/      net-worth math: values, series, breakdowns, flows, performance
│   ├── Storage/      library folder ⇄ model: JSON codec, validation, migrations, merging
│   ├── Importer/     CSV reading, format detection, column mapping, import profiles
│   ├── Planner/      simulation engine and return model; no tax rules
│   ├── TaxKit/       tax plugin interfaces, shared building blocks, parameter loading
│   ├── TaxItaly/     the Italian tax system: regimes, INPS, wrappers, yearly parameters
│   ├── TaxGeneric/   a flat-rate tax system
│   ├── Prices/       price and FX providers
│   ├── CloudSync/    iCloud container, coordinated file access, downloading, change watching (Apple only)
│   └── retire/       command-line tool: validate, import, net worth, run a plan
├── Tests/            one test target per module; fixtures are a fake example library
├── App/
│   ├── project.yml   XcodeGen spec → CanIRetireYet.xcodeproj (generated, not committed)
│   ├── Sources/      SwiftUI app shared by iPhone and Mac
│   └── Resources/
├── docs/
└── .github/workflows/
```

Module dependencies:

- `Model` and `TaxKit` depend on nothing.
- `Tracker`, `Storage`, `Importer` and `Prices` depend on `Model`.
- `Planner` depends on `Model`, `Tracker` and `TaxKit`, and never on a specific country.
- `TaxItaly` and `TaxGeneric` depend on `TaxKit`.
- `CloudSync` depends on `Storage`.
- The `retire` CLI and the app sit on top. They register the available tax systems in one place (`TaxRegistry`).

Only `CloudSync` and the app need Apple frameworks.

### How the app works at runtime

1. **Load.** At launch, `CloudSync` finds the iCloud container. If iCloud is off, it uses a local folder that can be moved to iCloud later. For a library in iCloud Drive, `CloudSync` first makes sure every file is on the device, downloading the missing ones all at once with progress (see "Sync with iCloud Drive"). `Storage` then loads the whole library into memory, which takes milliseconds because it's small. The opening screen says which step it's at, and never dead-ends.
2. **Edit.** The UI reads from an `@Observable` `LibraryStore`. An edit changes the in-memory model first. `Storage` then writes only the files that changed. Writes are atomic and go through `NSFileCoordinator`. Each write is merged with the file on disk, so a change that arrived from the other device (or a text editor) and hasn't been reloaded yet is never overwritten unseen ([FILE_FORMAT.md](FILE_FORMAT.md#saving)); the store then reloads what was merged in.
3. **Watch.** `CloudSync` watches the folder: an `NSMetadataQuery` for a library in iCloud Drive (which also downloads files that aren't on the device yet), or by comparing modification dates for a library on this device. When the other device, or you in a text editor, changes a file, the store reloads that file and the UI updates.
4. **Plan.** The planner runs in a background task on an immutable snapshot of the library and the plan. It recomputes after changes (debounced), so the results stay live while you edit a plan.

### Sync with iCloud Drive

- **Location.** The library is the `Documents/` folder of the app's iCloud container. Files are downloaded eagerly because they're tiny, before the library is read and whenever they change, so the "Optimize Storage" setting never leaves gaps.
- **Keeping conflicts rare.** There is one file per account, instrument and plan. History is grouped by month, so a check-in touches one file and past months are rarely edited. Unchanged files are never rewritten.
- **Resolving conflicts.** When two devices change the same file before syncing, iCloud keeps both versions (`NSFileVersion`). The app merges them record by record, marks the conflict resolved, and shows what it merged on a Sync screen. The rules are in [FILE_FORMAT.md](FILE_FORMAT.md#sync-conflicts).
- **Saving over a newer file.** A file can also change on disk between the app reading it and writing an edit to it. The write merges with it: record by record for history and headlines, and for other files with a copy in `backups/` before replacing it ([FILE_FORMAT.md](FILE_FORMAT.md#saving)). The Sync screen lists these too.
- **Not missing changes.** The store records every file's modification date when it loads the library, and the watcher's first look is compared with them, so a change that lands while the library loads is reloaded too. When the app comes back to the foreground it compares modification dates again.
- **First launch on a new device.** A library in iCloud Drive may not be on the device yet. Before offering to create a new one, the app asks iCloud Drive whether `library.json` exists (an `NSMetadataQuery`), waiting up to a few seconds for the answer, so the second device opens the existing library instead of creating another.
- **Downloading before reading.** A file iCloud Drive hasn't downloaded is only a placeholder, and a coordinated read of it waits until it's downloaded. Read one by one, a library of a few hundred files (an import back to 2017 makes over a hundred months) would take minutes, and never finish offline. So before reading, the app lists the library's files (the folder on disk, then an `NSMetadataQuery` with each file's download status, size and error), asks iCloud for every missing one at once, and shows "Downloading n of N files from iCloud Drive" with a bar until they're all here. Reads stay coordinated, but no longer wait on the network. A library already on the device is read at once.
- **Never stuck.** If nothing moves for 20 seconds while opening, the app says it's still waiting for iCloud Drive, lists the likely reasons (offline, cellular data off for iCloud Drive, Low Power Mode, iCloud Drive off for the app), and offers Try Again and Keep Waiting. It never offers to create a library then, since that would duplicate the one that hasn't arrived. Each step of opening is logged (`os.Logger`, category `library`), so Console shows where it stops.
- **Schema guard.** Every library records a `schemaVersion`. An app that finds a newer version than it understands opens the library read-only and asks to be updated. That way an old app on one device can't damage data written by a newer app on the other.

### App structure

The iPhone uses a tab bar and the Mac uses a sidebar. The iPad gets the sidebar layout for free.

- **Overview.** Shows:
  - net worth today;
  - a chart over time, stacked by category;
  - the change since the last check-in, split into market and new money;
  - breakdowns;
  - accounts that haven't been updated recently;
  - a *past and future* switch that continues the chart into the plan's projection;
  - whether you're ahead of or behind your latest baseline;
  - how close your plan assets are to what retiring today needs, taken from the active plan ([PLANNER.md](PLANNER.md#assets-needed-to-retire-today)).
- **Accounts.** A grouped list, with closed accounts in a collapsed section. The account detail shows a value chart, the list of valuations, and actions to edit, close or reopen.
- **Check-in.** The main action. The steps are:
  1. Choose the date (default: today).
  2. Review prices and FX rates. They're fetched for you and can be edited.
  3. Update the accounts, pre-filled with last time's values. "Unchanged" is one tap.
  4. Review the new total and the changes.
  5. Save.
- **Plan.** Three parts:
  - *Results*: the headline answer and the charts;
  - *Progress*: the answer over time, and your actual numbers against baselines;
  - *Inputs*.

  On the Mac, inputs and results sit side by side. Plans can be duplicated as what-if scenarios. The screens are designed in [UI.md](UI.md).
- **Settings.** Library location, price sources, a monthly reminder, app lock, and a description of the file format.

On the Mac there are also tables for editing many valuations at once, keyboard navigation through the check-in, and "Show library in Finder".

### Prices and FX

- Every price can be typed in by hand. Automatic fetching is opt-in per instrument.
- **FX:** ECB reference rates through Frankfurter, which is free and needs no key.
- **Crypto:** CoinGecko, or an exchange's public ticker. The symbol is the coin's CoinGecko ID or its ticker (`ETH`), which is resolved to an ID through a built-in table of well-known coins or CoinGecko's search. An optional demo API key, kept in the Keychain, raises its rate limit. CoinGecko's free API only has the last 365 days; older prices come from Yahoo Finance's crypto pairs (below).
- **Gold and silver:** a free spot-price API (gold-api.com, USD per troy ounce, converted to the instrument's currency and unit), or the market price of a physical-gold ETC as a proxy. gold-api.com only has today's spot price, so past prices come from the metal's front-month futures on Yahoo Finance: `GC=F` for gold (`XAU`), `SI=F` for silver, `PL=F` for platinum and `PA=F` for palladium, all in USD per troy ounce and converted the same way. Futures trade within about 1% of spot, so these are an approximation; the price list says so ("Yahoo Finance · GC=F (history)"), and the instrument keeps `gold-api` as its price source.
- **ETFs on European exchanges:** there's no reliable free official API. We'll start with Yahoo Finance's public chart endpoint. It's unofficial and can break, so providers are pluggable, and a paid one with your own key (EODHD, Twelve Data) can be added.
- **Inflation:** a consumer-price index, fetched with the FX rates for the months the library is missing: the library's (`inflationIndex` in `library.json`, by default the HICP of the tax residence, else of the base currency), and one for each plan's currency ([FILE_FORMAT.md](FILE_FORMAT.md#libraryjson)). Eurostat's HICP (`prc_hicp_minr`, all items, 2015 = 100) covers every EU country, Iceland, Norway, Switzerland, the candidate countries and the euro area (`hicp-de`, `hicp-ch`, `hicp-ea`, …), through one series builder; other indices are added as providers.
- **Dates:** each value is the latest on or before the check-in date and is recorded on that date. The price list shows the day it's from, e.g. Friday's close for a Sunday check-in.
- Fetched prices are cached on the device. Only the prices used in a check-in are written to the library.
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
  - **Planner checks:** invariants, run against the `generic` tax system so tax-law changes don't break them.
  - **Tax reference cases:** data files per tax system, calculated by hand or taken from real payslips and returns, so we can check we're computing the right thing.
  - **Importer:** a folder of sample files in awkward formats.
- One-time setup on your Mac:
  1. Join the **Apple Developer Program**, which is paid. iCloud requires it, and without it apps you install on your iPhone stop working after 7 days.
  2. Install Xcode and XcodeGen (`brew install xcodegen`).
  3. Choose a bundle identifier such as `com.<yourdomain>.caniretireyet`.
  4. Run `cd App && xcodegen generate`, then open the project.
  5. In *Signing & Capabilities*, pick your team and enable iCloud → iCloud Documents with the container `iCloud.<bundle id>`.

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
- The tax plugin layer, as described in [TAXES.md](TAXES.md): `TaxKit`, the registry, option forms generated from regime descriptions, validation, and parameter files.
- The `generic` flat-rate system.
- The Italian system, as described in [tax/IT.md](tax/IT.md):
  - employee and freelance income (forfettario or regime ordinario), with impatriati where it applies;
  - INPS contributions and the contributory-system pension projection;
  - IRPEF on pensions;
  - taxes on investment income and gains, and the 0.2% wealth tax;
  - the pension fund and TFR.
- Pensions, windfalls, large expenses and spending phases.
- Results:
  - the "Can I retire yet?" headline;
  - chance of success against retirement age;
  - a fan chart of the portfolio;
  - income sources and taxes per year;
  - what-if sliders;
  - two plans side by side, e.g. forfettario against ordinario with impatriati.
- Progress: the past-and-future chart, the headline recorded at each check-in, yearly and hand-saved baselines, and your actual line over a baseline.

**Done when:** the plan starts from your latest check-in, and the engine matches the reference cases calculated by hand.

### M3: Hardening and polish

- Conflict merging, with the Sync screen. The schema guard. Clear errors for hand-edited files that don't parse.
- A monthly reminder notification, Face ID lock, and CSV export.
- Performance (time-weighted and money-weighted returns, nominal and real), the explanation of the gap to a baseline, and fetching an inflation index (any country's HICP, or the euro area's).
- Widgets for net worth and years to go.
- An RW/IVAFE helper that produces year-end values and holding periods for foreign accounts, for an Italian tax return.

### M4: Depth (pick by interest)

- Historical and bootstrapped return sequences. Guardrail and variable withdrawal strategies.
- Tracking actual income and spending, to measure your real savings rate.
- Cost basis from transactions: done, as trades ([TRADES.md](TRADES.md)), with the app's screens and broker transaction CSVs importing into them ([IMPORT.md](IMPORT.md)). Still to do: PIR and other tax wrappers, lots (FIFO), and carrying actual losses forward (minusvalenze) from the trades; the plan's simulation already nets and carries forward the losses of simulated sales, as each country allows ([TAXES.md](TAXES.md#what-a-system-can-tell-the-planner-and-whats-told)).
- Tax systems for more countries (Switzerland and Germany are designed: [tax/CH.md](tax/CH.md), [tax/DE.md](tax/DE.md)). Until a country has one, the `generic` system approximates it.
- Reading `.xlsx` and `.numbers` files directly.
- Planning for a partner or household.

## 7. Risks

- **Unofficial price endpoints break.** Manual entry always works, and providers can be swapped.
- **Tax rules change every year, and so can your situation.** Rates live in yearly parameter files with sources, regimes and countries are plugins, and each result shows which rules it used.
- **iCloud Drive can be slow or create conflicts.** Small files, record-level merging and a visible sync status keep that manageable.
- **The planner could grow forever.** The MVP answers one question well, and everything else waits until M4.

## 8. Answers from the first review

1. **Apple Developer Program:** a paid membership is assumed, so iCloud is fine.
2. **Spreadsheet:** the importer maps any layout and format, and doesn't assume a particular spreadsheet ([IMPORT.md](IMPORT.md)).
3. **Bollo and IVAFE:** the same 0.2%, so the planner treats them as one wealth tax. They differ only in who pays: Italian intermediaries withhold bollo, while for foreign accounts the taxpayer pays IVAFE and declares the account in RW. Blacklisted countries pay 0.4%. The country only matters to the RW helper.
4. **iOS 26 and macOS 26** are the minimum versions.
5. **Taxes must be pluggable:** see [TAXES.md](TAXES.md).
