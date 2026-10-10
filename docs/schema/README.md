# Library format

The library is a folder of JSON files. Everything the app knows is stored in it: if you delete the app and keep the folder, nothing is lost. The format is defined by the [JSON Schemas](https://json-schema.org) (draft 2020-12) in this folder, one per kind of file: every field, its type, whether it's required, its default and range, what it means, and examples. This page covers what a schema can't say: how the files fit together, how values are computed from them, and how they're written and upgraded.

| File | Schema |
| --- | --- |
| `library.json` | [library.schema.json](library.schema.json) |
| `accounts/<id>.json` | [account.schema.json](account.schema.json) |
| `instruments/<id>.json` | [instrument.schema.json](instrument.schema.json) |
| `history/YYYY/YYYY-MM.json` | [history-month.schema.json](history-month.schema.json) |
| `plans/<id>.json` | [plan.schema.json](plan.schema.json) (how the plan uses it: [PLANNER.md](../PLANNER.md)) |
| `projections/<plan-id>/baselines/<id>.json` | [baseline.schema.json](baseline.schema.json) |
| `projections/<plan-id>/headlines/<year>.json` | [headlines.schema.json](headlines.schema.json) |
| `imports/<id>.json` | [import-profile.schema.json](import-profile.schema.json) (how the importer uses it: [IMPORT.md](../IMPORT.md)) |
| `backups/<name>/backup.json` | [backup.schema.json](backup.schema.json) |
| Shared values: decimals, dates, IDs, codes, asset mixes | [common.schema.json](common.schema.json) |

Check files against them with any 2020-12 validator, e.g. from this folder: `check-jsonschema --schemafile account.schema.json /path/to/library/accounts/*.json`.

- **Unknown keys are allowed.** The app keeps keys it doesn't know, at any depth, when it rewrites a file (in list items too: a work phase, an event, an import column, matched by their key, ID, name or position), so you can add your own notes. The schemas don't forbid them; a validator in strict mode, as the tests run it, reports them.
- **Open enums.** A "kind"-like field lists the values this version knows. A newer version may add values, which this one reads and writes back unchanged.
- **Kept in step with the app.** `JSONSchemaTests` (Tests/StorageTests) checks that every key the app reads is in its schema and the other way round, that every file of the example library and every schema's `examples` match strictly, and that documents with every field set, as the app writes them, match too.

## Principles

- **Plain, stable JSON.** The same data always gives byte-identical files ([Canonical layout](#canonical-layout)), with one record per line in lists of records, so a file only changes when its data does, and a diff shows exactly which records changed. The folder works well in git.
- **Small files.** One file for each thing you edit independently, so a sync conflict between devices stays rare and affects little.
- **Stable IDs you can read.** Files refer to each other by ID (`conto-fineco`), never by display name, so anything can be renamed.
- **Only inputs are stored.** Files hold what you entered, plus the prices, exchange rates and inflation figures fetched for it. Totals, charts and projections are always computed. The exception is `projections/`: what a plan expected at the time, which can't be recomputed later ([PROGRESS.md](../PROGRESS.md)).

## Layout

```
Can I Retire Yet/                   ← the app's folder in iCloud Drive
├── library.json                    settings and format version
├── README.md                       written by the app: what this folder is and how to read it
├── accounts/                       one file per account, open or closed
│   ├── conto-fineco.json
│   └── …
├── instruments/                    one file per thing you hold a quantity of
│   ├── vwce.json
│   └── …
├── history/                        valuations, trades, prices, FX rates and inflation, by month
│   └── 2026/
│       ├── 2026-01.json
│       └── …
├── plans/                          one file per scenario
│   └── base.json
├── projections/
│   └── base/
│       ├── baselines/2026-01-05.json   a saved projection
│       └── headlines/2026.json         the answer at each check-in
├── imports/                        saved import mappings
│   └── net-worth-sheet.json
└── backups/                        copies taken before a migration, an import or a replaced file; safe to delete
```

Files the app doesn't know are ignored. A file's name is its ID (`accounts/<id>.json`), and a record's date decides its month file.

## How values are computed

The value of an account on a date **D**:

1. Take the account's latest valuation dated on or before D. Balances, quantities and cash carry forward until the next valuation.
2. Value each position at the instrument's latest price on or before D. So gold coins you never touch still follow the gold price, as long as gold prices are recorded.
3. Convert to the base currency at the latest exchange rate on or before D: direct, inverse, or crossed through another currency. A missing price or rate makes the value incomplete; it's never counted as zero.
4. Count the account only between its `opened` and `closed` dates.

An account that records trades (`"valuation": "trades"`) holds what its trades leave on D, with its cash: the `cash` of its latest valuation on or before D, plus the cash effect of every trade after it, none for a trade paid from outside the account ([TRADES.md](../TRADES.md)). Steps 2 to 4 are the same.

**Net worth** on D is the sum over the accounts included in net worth (`includeIn.netWorth`, default true); **plan assets** over those included in plans.

**Change since the last check-in.** Each account's change is split into **market**, **new money** and **other**:

- **The flow is known** (every valuation in the period has a `flow`, or there was no new valuation): new money is the flow, and market is the rest. A lower flow, e.g. for reinvested dividends, or a purchase below the check-in price counts as market.
- **Positions, flow unknown:** market is the old quantity × price change, including FX; new money is everything else, meaning changes in quantity and in cash.
- **Balance the check-in asks about, flow unknown** (pension fund, TFR, property, other): each value's flow where one was entered, else what the main plan pays into the account since the value before (its `contributions`), is new money, and market is the rest. The account's first value without a flow is other: what it held when its records start ([PROGRESS.md](../PROGRESS.md#data-this-needs-from-day-one)).
- **Other balances, flow unknown** (an imported history, typically): each value's flow where one was entered, else what a check-in would have filled in, the whole change since the value before, is new money, and market is the rest, the FX movement ([PROGRESS.md](../PROGRESS.md#data-this-needs-from-day-one)). The account's first value without a flow is other. When a price or an exchange rate that needs is missing, only the FX movement of the old balance counts as market, and the rest is other.
- **Trades:** new money is the account's deposits, withdrawals, transfers at market value, buys and sales paid from outside the account at their amount, and residuals (cash typed at a check-in that the trades don't explain), each at its date; market is the rest, including dividends, interest and fees ([TRADES.md](../TRADES.md#flows)).

An account that closes during the period ends at zero: its value on the closing day leaves as new money.

**Staleness.** An account whose latest valuation is older than a threshold (45 days by default, a setting of the app, not of the library) is flagged, unless it holds nothing.

## Canonical layout

The app writes every file the same way, so the same data always gives the same bytes:

- UTF-8 with no byte order mark, two-space indentation, and a newline at the end.
- Object keys sorted by Unicode code point (so `"B"` comes before `"a"`).
- Text is written as is; only `"`, `\` and control characters are escaped (`\n`, `\t`, `\u0007`). Numbers (counts, ages, years) are written in their shortest exact form; amounts are strings (common.schema.json, `decimal`).
- A list or object stays on one line, as `{ "a": "1", "b": 2 }` or `["x", "y"]`, when the whole line fits in **130 columns**, counting indentation, the key and a trailing comma, in characters. Otherwise it's spread over several lines with one member or element per line, each laid out by the same rule. Empty ones are `{}` and `[]`.
- Two exceptions are always spread out: the file's top-level object, and lists of records directly in it (`valuations`, `prices`, `work`, `years`, …), which get one record per line even when they're short.

## Versioning

- `schemaVersion` in `library.json` is 3. Adding optional fields doesn't change it; anything else is a new version, with a migration in the app.
- Versions 1 and 2 were the formats of test versions, before any library was kept (version 2 added trades, version 3 dropped the tax systems from plans, [PLANNER.md](../PLANNER.md#the-model-in-brief)). This app has no migration from them: such a library doesn't open, and the error says why.
- Before migrating, the app copies the library into `backups/<yyyy-MM-dd>-v<old>/`. A migration works on the raw JSON of every file, and nothing is written unless every step succeeds.
- An app older than the library opens it read-only: it loads, and every save is refused. A library older than the app is migrated before the app saves anything to it.

## Reading hand-edited files

- A file with a mistake doesn't stop the library from loading. The app lists each problem with the file's path and where in it, like `valuations[2].balance: Expected a decimal such as "1234.56", found "12,5".` or `Line 4, column 3: Expected "," or "}" after a value in an object`.
- A file that can't be read is left out. In a history or headline file only the records that can't be read are left out, and they're kept in the file when the app rewrites it, until you fix them. A file that is left out is copied to `backups/` before the app writes over it or deletes it.
- A `library.json` that exists but can't be read opens the library read-only, as a newer library does: the app would otherwise have only default settings (EUR, no birth date) to save over yours. Fix the file, or restore it from a backup, and open the library again. A folder with no `library.json` at all is how a new library starts.
- A JSON number where text is expected (`"name": 2026`) is read as text, and a whole number written as text where a number is expected (`"endAge": "95"`) as a number.
- The file name wins over the `id` inside the file, and over the `month` inside a history file; the app points out the mismatch.
- A record dated outside its month file stays where it is, and the app points it out. When two records have the same key, the later one in the file is used.
- Records dated before 1900, or more than a year after today, are loaded and pointed out: usually a mistyped year, or a placeholder such as `9999-12-31`.
- JSON files whose names aren't IDs (`My Account.json`) are pointed out, and so are records that refer to accounts, instruments or plans that don't exist.

## CSV export

To open the library in a spreadsheet or take it to another app, Settings › Library › *Export as CSV…* writes a zip of CSV files, and `retire export <folder>` writes them into a folder. The library isn't changed. Every file is UTF-8 and comma-separated, with a header row and CRLF line ends (RFC 4180); dates are `YYYY-MM-DD` and numbers have a `.` and no grouping, as in the library's files. A field with a comma, a quote or a line break is quoted.

| File | One row per | Columns |
| --- | --- | --- |
| `net-worth.csv` | month end | `date`, `currency` (the base currency), `net_worth`, `plan_assets`, `complete` |
| `account-values.csv` | account and month end, while it's open | `date`, `account`, `name`, `currency`, `value` (in the account's currency), `base_currency`, `value_in_base_currency`, `complete` |
| `accounts.csv` | account | `id`, `name`, `kind`, `currency`, `institution`, `country`, `opened`, `closed`, `valuation`, `available_from_age`, `in_net_worth`, `in_plans`, `asset_classes`, `money_in_out`, `successor`, `tags`, `notes` |
| `instruments.csv` | instrument | `id`, `name`, `kind`, `currency`, `unit`, `isin`, `ticker`, `asset_classes`, `price_provider`, `price_symbol` |
| `valuations.csv` | valuation | `date`, `account`, `balance`, `cash`, `positions` (how many, in `positions.csv`), `flow`, `money_in`, `money_out`, `note`, `source` |
| `positions.csv` | position in a valuation | `date`, `account`, `instrument`, `quantity`, `cost_basis` |
| `trades.csv` | trade | `date`, `account`, `id`, `type`, `instrument`, `quantity`, `price`, `currency`, `amount`, `fees`, `tax`, `cost`, `ratio`, `settlement`, `note`, `source` |
| `prices.csv` | price | `date`, `instrument`, `price`, `currency`, `source` |
| `fx.csv` | exchange rate | `date`, `base`, `quote`, `rate` (1 base = rate × quote), `source` |
| `inflation.csv` | index value | `date`, `index`, `value`, `source` |

- **The first two are worked out** ([How values are computed](#how-values-are-computed)) at each month end from the first value through the export's date (and on that date when it isn't a month end), rounded to cents. `complete` is `no` where a price or an exchange rate is missing; the value is then what could be valued.
- **The others are what's recorded**, field for field as in the library's files, empty where a field isn't set; their meaning is in the schemas. `asset_classes` reads `bonds=0.4; equity=0.6`, `tags` `a; b`, and the yes/no columns `yes` or `no`.
- Plans, projections and import profiles aren't exported: their files are plain JSON already.

How this app merges sync conflicts, saves over files changed elsewhere, keeps backups and undoes an import is in [PLAN.md](../PLAN.md#merging-saving-and-undo).
