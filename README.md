# Can I Retire Yet?

A personal net-worth tracker and retirement planner for iPhone, iPad and Mac.

- **Track.** Once a month, record what each account and holding is worth: cash, ETFs, crypto, gold, pension funds, property and debts. You can open and close accounts without losing their history.
- **Plan.** Start from your real numbers and project forward: savings, spending, pensions, windfalls and taxes, in your currency or any other. Taxes come from pluggable tax systems and regimes, picked by where you live: Italy is first, including impatriati and forfettario; Switzerland and Germany are designed; anywhere else uses a generic system with flat rates you choose. The app answers the question in its name: *can I retire yet, and if not, when?* When an answer looks odd, *Show Calculations…* lays out every calculation behind it, and exports it anonymized to give to someone else.
- **Your data is files.** Everything is stored as plain JSON files in a folder in iCloud Drive. The app on each device (iPhone, iPad, Mac) reads and writes that folder, and iCloud keeps it in sync. There is no server, no account to create, and no lock-in.

**Status: MVP.** Tracking (accounts, check-ins, history, performance data), import from spreadsheets, prices, the planner with Italy's tax system, and the iPhone, iPad and Mac app with iCloud sync. The `retire` command-line tool does the same from a terminal. Start with [docs/PLAN.md](docs/PLAN.md); to build and contribute, see [CLAUDE.md](CLAUDE.md).

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
3. **Run it** on the Mac, your iPhone and your iPad: one app covers all three (in Xcode, pick the device as the run destination). Sign in to the same iCloud account with iCloud Drive on. The first launch creates the library (or finds the one the other device created) in iCloud Drive → *Can I Retire Yet*.
4. **Check the price sources once.** The providers are tested against recorded responses; this checks the live services from your network:

   ```sh
   LIVE_PRICE_TESTS=1 swift test --filter PricesTests
   ```

5. **Bring in your history:** *Import…* (⌘⇧I, or drop a file on the window) takes a spreadsheet export (CSV/TSV); map it once and save the mapping as a profile for next time. Or add values by hand with past check-ins or *Add Past Value…* on an account ([UI.md, "Adding history"](docs/UI.md)). Then *Fill In Past Prices…* (Instruments, or the import's last step) fetches the prices, exchange rates and inflation figures the history is missing.

The command-line tool works on the same folder, on a Mac or Linux:

```sh
swift run retire --help
swift run retire init <folder> --currency CHF --residence CH --birth-date 1985-03-01 --citizenship IT
swift run retire settings --library <folder>          # --citizenship, --inflation-index set them
swift run retire import --library <folder> export.csv            # preview; --apply writes
swift run retire import --library <folder> movimenti.csv --account directa   # a broker's export, as trades
swift run retire trades list directa --library <folder>                      # also add, remove, summary, convert
swift run retire instruments --library <folder>                  # kinds for taxes; `set` a fund type
swift run retire prices --library <folder> --fill-history --dry-run  # past prices; without --dry-run writes
swift run retire plan --library <folder> --years                 # the answer, and the median run by year
swift run retire plan show --library <folder>                    # also set, contribution, pension
swift run retire plan set --library <folder> --target-mix equity=80%,bonds=20% \
    --target-mix-from retirement:equity=60%,bonds=40%            # the mix to rebalance to, by age
swift run retire plan debug --library <folder> --anonymize --output report.md   # every calculation, to share
```

Commands that change the library back up the files first, and take `--dry-run`; most take `--json`. `retire help <command>` says more.


| Document | What it covers |
| --- | --- |
| [docs/PLAN.md](docs/PLAN.md) | Scope, key decisions, architecture, milestones, open questions |
| [docs/FILE_FORMAT.md](docs/FILE_FORMAT.md) | The library folder: files, fields, and how sync conflicts are merged |
| [docs/TRADES.md](docs/TRADES.md) | Accounts that record trades: buys, sells and dividends, average cost, cash, flows, conversion |
| [docs/PLANNER.md](docs/PLANNER.md) | The retirement simulation |
| [docs/TAXES.md](docs/TAXES.md) | Pluggable tax systems and regimes: concepts, interfaces, parameter files |
| [docs/tax/IT.md](docs/tax/IT.md) | The Italian tax system: work income, impatriati, INPS, pension fund, investments |
| [docs/tax/CH.md](docs/tax/CH.md), [docs/tax/DE.md](docs/tax/DE.md) | The Swiss and German tax systems, as designed |
| [docs/IMPORT.md](docs/IMPORT.md) | Importing any spreadsheet or export by mapping its columns |
| [docs/PROGRESS.md](docs/PROGRESS.md) | Net worth, history and projection together, baselines, actual vs. projected, performance |
| [docs/UI.md](docs/UI.md) | What the app looks like: screens, navigation, charts, iPhone, iPad and Mac |
