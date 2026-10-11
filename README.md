# Can I Retire Yet?

A personal net-worth tracker and retirement planner for iPhone, iPad and Mac.

- **Track.** Once a month, record what each account and holding is worth: cash, ETFs, crypto, gold, pension funds, property and debts. You can open and close accounts without losing their history.
- **Plan.** Start from your real numbers and project forward: savings, spending, pensions and windfalls, with thousands of simulated markets. The model is deliberately simple, so every year can be checked by hand: you enter income from work and pensions after tax, a tax rate on investment gains and income, and optionally a wealth tax; accounts such as a pension fund can be locked until an age. It answers the question in its name: *can I retire yet, and if not, when?* Results are estimates from a simplified model, not financial or tax advice. *Export Calculations…* writes every calculation behind an answer, anonymized if you like, to check it or give it to someone else.
- **Your data is files.** Everything is stored as plain JSON files in a folder in iCloud Drive. The app on each device (iPhone, iPad, Mac) reads and writes that folder, and iCloud keeps it in sync. There is no server, no account to create, and no lock-in.

**Status: MVP.** Tracking (accounts, check-ins, history, trades), import from spreadsheets, prices, the planner, and the iPhone, iPad and Mac app with iCloud sync. The `retire` command-line tool does the same from a terminal. Start with [docs/PLAN.md](docs/PLAN.md); to build and contribute, see [CLAUDE.md](CLAUDE.md).

## Getting started

You need a Mac with Xcode 26 and an Apple Developer account (for iCloud).

1. **Generate the Xcode project.** It's generated from `project.yml` at the root and never committed:

   ```sh
   brew install xcodegen
   xcodegen
   open CanIRetireYet.xcodeproj
   ```

   Run `xcodegen` (or `make project`) again after pulling changes that add or remove files or change `project.yml`: Xcode only sees them in a newly generated project.
2. **Set your team.** `make signing TEAM=ABCDE12345` writes your Apple Developer team ID (developer.apple.com → Account → Membership details) into `Signing.xcconfig` at the root; then generate again. The bundle identifier is j23n's, `com.j23n.caniretireyet`. To build your own copy under another team, put your own in the same file:

   ```
   DEVELOPMENT_TEAM = ABCDE12345
   APP_BUNDLE_IDENTIFIER = com.<yourdomain>.caniretireyet
   ```

   Git ignores the file and every generated project reads it (`App/Config/Project.xcconfig`), so Xcode doesn't ask for your team after each `xcodegen`, and a pull never touches it. Each build's build number is the number of commits (`make build-number`; j23n/apple-ci's README, "Build numbers"). In Xcode's *Signing & Capabilities*, check that *iCloud → iCloud Documents* lists the container `iCloud.<bundle id>`; the first build with automatic signing registers it.
3. **Run it** on the Mac, your iPhone and your iPad: one app covers all three (in Xcode, pick the device as the run destination). Sign in to the same iCloud account with iCloud Drive on. The first launch creates the library (or finds the one the other device created) in iCloud Drive → *Can I Retire Yet*.
4. **Check the price sources once.** The providers are tested against recorded responses; this checks the live services from your network:

   ```sh
   LIVE_PRICE_TESTS=1 swift test --filter PricesTests
   ```

5. **Bring in your history:** *Import…* (⌘⇧I, or drop a file on the window) takes a spreadsheet export (CSV/TSV); map it once and save the mapping as a profile for next time. Or add values by hand with past check-ins or *Add Past Value…* on an account ([UI.md, "Adding history"](docs/UI.md)). Then *Fill In Past Prices…* (Instruments, or the import's last step) fetches the prices, exchange rates and inflation figures the history is missing.

The command-line tool works on the same folder, on a Mac or Linux:

```sh
swift run retire --help
swift run retire init <folder> --currency CHF --residence CH --birth-date 1985-03-01
swift run retire settings --library <folder>          # --inflation-index sets it
swift run retire import --library <folder> export.csv            # preview; --apply writes
swift run retire import --library <folder> movimenti.csv --account directa   # a broker's export, as trades
swift run retire trades list directa --library <folder>          # also summary: a year's gains and dividends
swift run retire instruments --library <folder>
swift run retire instruments find vwce --library <folder>    # Yahoo Finance listings; --set <symbol> saves one
swift run retire spending --library <folder>                    # money in and out of cash accounts, savings rate
swift run retire prices --library <folder> --fill-history --dry-run  # past prices; without --dry-run writes
swift run retire plan --library <folder> --years                 # the answer, and the median run by year
swift run retire plan show --library <folder>                    # the plan's inputs
swift run retire plan debug --library <folder> --anonymize --output report.md   # every calculation, to share
swift run retire plan pace --library <folder>                    # how much you've saved, the last 12 months
swift run retire export <folder> --library <library>     # the library as CSV files
```

Plans, accounts and trades are edited in the app, or in their JSON files by hand ([docs/schema](docs/schema/)). Commands that change the library back up the files first, and take `--dry-run`; most take `--json`. `retire help <command>` says more.


| Document | What it covers |
| --- | --- |
| [docs/PLAN.md](docs/PLAN.md) | Scope, key decisions, architecture, milestones, open questions |
| [docs/schema](docs/schema/) | The library format: a JSON Schema for every file, how values are computed from them, versions, and the CSV export |
| [docs/TRADES.md](docs/TRADES.md) | Accounts that record trades: buys, sells and dividends, average cost, cash, flows, conversion |
| [docs/PLANNER.md](docs/PLANNER.md) | The retirement simulation |
| [docs/research/tax](docs/research/tax/) | Research notes on the Italian, Swiss and German tax systems, kept from an earlier version that modelled them; not used by the app |
| [docs/IMPORT.md](docs/IMPORT.md) | Importing any spreadsheet or export by mapping its columns |
| [docs/PROGRESS.md](docs/PROGRESS.md) | Net worth, history and projection together, baselines, actual vs. projected |
| [docs/UI.md](docs/UI.md) | What the app looks like: screens, navigation, charts, iPhone, iPad and Mac |

## License

MIT, see [LICENSE](LICENSE). The CLI uses [Swift Argument Parser](https://github.com/apple/swift-argument-parser) (Apache-2.0).
