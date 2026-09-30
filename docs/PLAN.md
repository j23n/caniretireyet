# Plan

> Status: draft for review. The open questions are at the end.

## 1. What we're building

A private app for iPhone and Mac with two halves:

1. **Tracker.** Once a month you check in and record what each account is worth. Cash accounts, pension funds, property and debts are recorded as a balance. For ETFs, crypto and gold you record the quantity, and the app multiplies it by the price. Accounts are opened and closed over the years, and their history is kept either way.
2. **Planner.** Scenarios that start from your latest check-in and simulate the years ahead, covering:
   - work and savings, with Italian taxes including impatriati and forfettario;
   - spending in retirement;
   - the INPS pension and any other pensions;
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
- Multiple currencies, with EUR as the base currency. Every check-in stores the prices and FX rates it used.
- Monthly check-in:
  - pre-filled from the previous check-in;
  - prices and FX rates fetched automatically where possible;
  - every value editable.
- Overview:
  - net worth over time;
  - breakdowns by category, asset class, currency and institution;
  - the change since the last check-in, split into market movement and new money;
  - accounts that haven't been updated recently.
- Import of your existing spreadsheet (CSV).
- Sync between iPhone and Mac through iCloud Drive.

**Planner**

- Scenarios ("plans"), one file each.
- Working years:
  - income as an employee and/or under the forfettario regime, with or without impatriati;
  - INPS contributions;
  - savings, calculated as net income minus spending.
- Retirement years:
  - spending, optionally in phases;
  - the INPS pension (a projection under the contributory system);
  - foreign and other pensions;
  - the pension fund and TFR;
  - windfalls and one-off expenses.
- Italian taxes:
  - IRPEF;
  - forfettario and impatriati;
  - 26% / 12.5% / crypto rates on investments;
  - bollo and IVAFE;
  - taxation of pension-fund payouts.
- A deterministic projection plus a Monte Carlo simulation, which produce:
  - the headline answer;
  - the earliest retirement age at your chosen confidence level;
  - charts.

### Later

These are listed as M3 and M4 in §6: scenario comparison, widgets, the RW/IVAFE helper, historical return sequences, dynamic withdrawal strategies, retiring abroad, partner planning, and transaction-based cost basis.

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
| History model | Point-in-time valuations (balances and quantities), not transactions. | This matches the monthly workflow, and closing an account never touches its history. |
| Money | `Decimal` for every recorded amount, stored as strings in JSON. | No floating-point rounding errors in the tracker. |
| Currencies | Each account has its own currency; the base currency is EUR. Each check-in stores the prices and FX rates it used. | Past net worth can always be recomputed, even if a price source goes away. |
| Planner | Yearly steps in today's euros, deterministic plus Monte Carlo, with a seeded random-number generator. | This approach is standard and easy to explain. It is also fast enough to recompute live while you drag a slider. |
| Taxes | Pluggable per country, with Italy first. Every rate and threshold lives in yearly parameter files that cite their sources. | Italian tax law changes with every budget law, so parameters must be easy to update and check. |
| Code layout | A Swift package of platform-independent modules, plus a thin app target. | Most of the logic can be built and tested on Linux, in CI and in cloud sessions. Only the UI needs Xcode. |
| Xcode project | Generated from `App/project.yml` with XcodeGen. | The project definition is readable text, there are no `.pbxproj` merge conflicts, and it can be edited without Xcode. |
| Dependencies | None in the core modules (Foundation only). The CLI uses Swift Argument Parser. | Fewer moving parts, and the core builds on Linux. |

## 4. Architecture

### Repository layout

```
caniretireyet/
├── Package.swift
├── Sources/
│   ├── Tracker/      domain model: accounts, instruments, valuations; net-worth math
│   ├── Storage/      library folder ⇄ model: JSON codec, validation, migrations, merging, CSV import
│   ├── Planner/      simulation engine, return model, Italian tax and pension module
│   ├── Prices/       price and FX providers
│   ├── CloudSync/    iCloud container, coordinated file access, change watching (Apple only)
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

- `Tracker` depends on nothing.
- `Storage`, `Planner` and `Prices` depend on `Tracker`.
- `CloudSync` depends on `Storage`.
- The `retire` CLI and the app sit on top.

Only `CloudSync` and the app need Apple frameworks.

### How the app works at runtime

1. **Load.** At launch, `CloudSync` finds the iCloud container. If iCloud is off, it uses a local folder that can be moved to iCloud later. `Storage` then loads the whole library into memory, which takes milliseconds because it's small.
2. **Edit.** The UI reads from an `@Observable` `LibraryStore`. An edit changes the in-memory model first. `Storage` then writes only the files that changed. Writes are atomic and go through `NSFileCoordinator`.
3. **Watch.** `CloudSync` watches the folder using `NSMetadataQuery` and `NSFilePresenter`. When the other device, or you in a text editor, changes a file, the store reloads that file and the UI updates.
4. **Plan.** The planner runs in a background task on an immutable snapshot of the library and the plan. It recomputes after changes (debounced), so the results stay live while you edit a plan.

### Sync with iCloud Drive

- **Location.** The library is the `Documents/` folder of the app's iCloud container. Files are downloaded eagerly because they're tiny, so the "Optimize Storage" setting never leaves gaps.
- **Keeping conflicts rare.** There is one file per account, instrument and plan. History is grouped by month, so a check-in touches one file and past months are rarely edited. Unchanged files are never rewritten.
- **Resolving conflicts.** When two devices change the same file before syncing, iCloud keeps both versions (`NSFileVersion`). The app merges them record by record, marks the conflict resolved, and shows what it merged on a Sync screen. The rules are in [FILE_FORMAT.md](FILE_FORMAT.md#sync-conflicts).
- **Schema guard.** Every library records a `schemaVersion`. An app that finds a newer version than it understands opens the library read-only and asks to be updated. That way an old app on one device can't damage data written by a newer app on the other.

### App structure

The iPhone uses a tab bar and the Mac uses a sidebar. The iPad gets the sidebar layout for free.

- **Overview.** Shows:
  - net worth today;
  - a chart over time, stacked by category;
  - the change since the last check-in, split into market and new money;
  - breakdowns;
  - accounts that haven't been updated recently;
  - progress toward financial independence, taken from the active plan.
- **Accounts.** A grouped list, with closed accounts in a collapsed section. The account detail shows a value chart, the list of valuations, and actions to edit, close or reopen.
- **Check-in.** The main action. The steps are:
  1. Choose the date (default: today).
  2. Review prices and FX rates. They're fetched for you and can be edited.
  3. Update the accounts, pre-filled with last time's values. "Unchanged" is one tap.
  4. Review the new total and the changes.
  5. Save.
- **Plan.** The headline answer and the charts, next to the inputs (side by side on the Mac). Plans can be duplicated as what-if scenarios.
- **Settings.** Library location, price sources, a monthly reminder, app lock, and a description of the file format.

On the Mac there are also tables for editing many valuations at once, keyboard navigation through the check-in, and "Show library in Finder".

### Prices and FX

- Every price can be typed in by hand. Automatic fetching is opt-in per instrument.
- **FX:** ECB reference rates through Frankfurter, which is free and needs no key.
- **Crypto:** CoinGecko, or an exchange's public ticker.
- **Gold and silver:** a free spot-price API, or the market price of a physical-gold ETC as a proxy.
- **ETFs on European exchanges:** there's no reliable free official API. We'll start with Yahoo Finance's public chart endpoint. It's unofficial and can break, so providers are pluggable, and a paid one with your own key (EODHD, Twelve Data) can be added.
- Fetched prices are cached on the device. Only the prices used in a check-in are written to the library.

### Importing your spreadsheet

- The importer lives in `Storage` and is exposed through the CLI first (`retire import`), because this is a one-off migration. An import sheet in the Mac app can follow later.
- It reads two layouts:
  - wide: one row per month and one column per account;
  - long: date, account, value.
- It detects Italian number and date formats such as `1.234,56` and `31/12/2024`.
- Each column becomes an account, and you confirm the name, kind and currency. A column whose values stop before the last row is proposed as a closed account.
- Imported values become balance valuations in the monthly history files. Running the import again updates those records instead of duplicating them.

### Security and privacy

- iCloud Drive encrypts data in transit and at rest. Turning on **Advanced Data Protection** makes it end-to-end encrypted.
- The files are deliberately plain text: anyone with access to your Mac or your iCloud account can read them. That is the price of a file-based design, and there's no extra encryption in the app. An optional Face ID lock (M3) protects the app itself.
- Your real financial data never goes into this repository. The tests use a made-up example library.

## 5. Development workflow

- Most of the code is in the Swift package and doesn't depend on Apple platforms. CI runs `swift build` and `swift test` on Linux for every push. The app target (SwiftUI and iCloud) is built on a macOS runner without code signing to catch compile errors.
- Tests use Swift Testing:
  - **Format golden tests:** load the fixture library, save it again, and expect byte-identical files.
  - **Net-worth tests:** unit tests for the math.
  - **Planner and tax checks:** reference cases calculated by hand, so we can check we're computing the right thing.
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
- Live sync: a check-in on the iPhone appears on the Mac, and edits made directly to files are picked up.
- Import of your spreadsheet through the CLI.

**Done when:** your spreadsheet history is in the app, and you've done a real check-in on the iPhone and seen it on the Mac.

### M2: Planner MVP

- Plan files and a plan editor.
- The engine: yearly simulation, deterministic and Monte Carlo runs, and the earliest-retirement-age search.
- Italy module v1, as described in [PLANNER.md](PLANNER.md):
  - employee and forfettario income, with or without impatriati;
  - INPS contributions and the contributory-system pension projection;
  - IRPEF on pensions;
  - taxes on investment income and gains, bollo and IVAFE;
  - the pension fund and TFR.
- Pensions, windfalls, large expenses and spending phases.
- Results:
  - the "Can I retire yet?" headline;
  - chance of success against retirement age;
  - a fan chart of the portfolio;
  - income sources and taxes per year;
  - what-if sliders.

**Done when:** the plan starts from your latest check-in, and the engine matches the reference cases calculated by hand.

### M3: Hardening and polish

- Conflict merging, with the Sync screen. The schema guard. Clear errors for hand-edited files that don't parse.
- A monthly reminder notification, Face ID lock, CSV export, and import in the Mac app.
- Side-by-side scenario comparison, and widgets for net worth and years to go.
- An RW/IVAFE helper that produces year-end values and holding periods for foreign accounts, for your tax return.

### M4: Depth (pick by interest)

- Historical and bootstrapped return sequences. Guardrail and variable withdrawal strategies.
- Tracking actual income and spending, to measure your real savings rate.
- Cost basis from transactions. PIR and other tax wrappers.
- Retiring abroad, meaning a change of tax residence partway through a plan.
- Planning for a partner or household.

## 7. Risks

- **Unofficial price endpoints break.** Manual entry always works, and providers can be swapped.
- **Italian tax rules change every year.** Rates and thresholds live in yearly parameter files with sources. Each result shows which year's rules it used.
- **iCloud Drive can be slow or create conflicts.** Small files, record-level merging and a visible sync status keep that manageable.
- **The planner could grow forever.** The MVP answers one question well, and everything else waits until M4.

## 8. Open questions for you

1. Do you have a paid Apple Developer Program membership? iCloud needs one.
2. What does your spreadsheet look like? The column layout, or a copy with made-up numbers, is enough to make the importer fit it.
3. Are your banks and brokers Italian or foreign, and do they withhold tax for you (*regime amministrato*) or do you declare it yourself (*regime dichiarativo*)? This affects bollo versus IVAFE, and the RW helper.
4. Are iOS 26 and macOS 26 OK as minimum versions?
