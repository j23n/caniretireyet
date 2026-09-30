# Can I Retire Yet?

A personal net-worth tracker and retirement planner for iPhone and Mac.

- **Track.** Once a month, record what each account and holding is worth: cash, ETFs, crypto, gold, pension funds, property and debts. You can open and close accounts without losing their history.
- **Plan.** Start from your real numbers and project forward: savings, spending, pensions, windfalls and taxes. Taxes come from pluggable tax systems and regimes. Italy is first, including impatriati and forfettario. The app answers the question in its name: *can I retire yet, and if not, when?*
- **Your data is files.** Everything is stored as plain JSON files in a folder in iCloud Drive. The iPhone and Mac apps both read and write that folder, and iCloud keeps it in sync. There is no server, no account to create, and no lock-in.

**Status: MVP.** Tracking (accounts, check-ins, history, performance data), import from spreadsheets and ledger-cli / hledger journals, prices, the planner with Italy's tax system, and the iPhone, iPad and Mac app with iCloud sync. The `retire` command-line tool does the same from a terminal. Start with [docs/PLAN.md](docs/PLAN.md); to build and contribute, see [CLAUDE.md](CLAUDE.md).

## Getting started

You need a Mac with Xcode 26 and an Apple Developer account (for iCloud).

1. **Generate the Xcode project.** It's generated from `App/project.yml` and never committed:

   ```sh
   brew install xcodegen
   xcodegen generate --spec App/project.yml
   open App/CanIRetireYet.xcodeproj
   ```

   Run `xcodegen generate` again after pulling changes that add or remove files.
2. **Make it yours.** In `App/project.yml`, set `PRODUCT_BUNDLE_IDENTIFIER` (e.g. `com.<yourdomain>.caniretireyet`) and `DEVELOPMENT_TEAM` (your team ID), then generate again. In Xcode's *Signing & Capabilities*, check that *iCloud → iCloud Documents* lists the container `iCloud.<bundle id>`; the first build with automatic signing registers it.
3. **Run it** on the Mac and on your iPhone, signed in to the same iCloud account with iCloud Drive on. The first launch creates the library (or finds the one the other device created) in iCloud Drive → *Can I Retire Yet*.
4. **Check the price sources once.** The providers are tested against recorded responses; this checks the live services from your network:

   ```sh
   LIVE_PRICE_TESTS=1 swift test --filter PricesTests
   ```

5. **Bring in your history:** *Import…* (⌘⇧I, or drop files on the window) takes a spreadsheet export (CSV/TSV) or ledger journals; map it once and save the mapping as a profile for next time. Or add values by hand with past check-ins or *Add Past Value…* on an account ([UI.md, "Adding history"](docs/UI.md)). Then *Fill In Past Prices…* (Instruments, or the import's last step) fetches the prices, exchange rates and inflation figures the history is missing.

The command-line tool works on the same folder, on a Mac or Linux:

```sh
swift run retire --help
swift run retire import --library <folder> export.csv            # preview; --apply writes
swift run retire import ledger --library <folder> 2024.journal 2025.journal
swift run retire prices --library <folder> --fill-history --dry-run  # past prices; without --dry-run writes
swift run retire plan --library <folder>
```


| Document | What it covers |
| --- | --- |
| [docs/PLAN.md](docs/PLAN.md) | Scope, key decisions, architecture, milestones, open questions |
| [docs/FILE_FORMAT.md](docs/FILE_FORMAT.md) | The library folder: files, fields, and how sync conflicts are merged |
| [docs/PLANNER.md](docs/PLANNER.md) | The retirement simulation |
| [docs/TAXES.md](docs/TAXES.md) | Pluggable tax systems and regimes: concepts, interfaces, parameter files |
| [docs/tax/IT.md](docs/tax/IT.md) | The Italian tax system: work income, impatriati, INPS, pension fund, investments |
| [docs/IMPORT.md](docs/IMPORT.md) | Importing any spreadsheet or export by mapping its columns |
| [docs/PROGRESS.md](docs/PROGRESS.md) | Net worth, history and projection together, baselines, actual vs. projected, performance |
| [docs/UI.md](docs/UI.md) | What the app looks like: screens, navigation, charts, iPhone and Mac |
