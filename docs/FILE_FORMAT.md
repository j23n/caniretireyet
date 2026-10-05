# Library file format

The library is a folder. Everything the app knows is stored in it. If you delete the app and keep the folder, nothing is lost.

## Principles

- **Plain, stable JSON.** Files are UTF-8, pretty-printed with two-space indentation, sorted keys and a trailing newline. A record inside a list is kept on a single line when it fits, so a diff shows exactly which records changed. The same data always produces byte-identical files, so a file only changes when its data changes. If you put the folder in git, the diffs stay clean. The exact layout is in [Canonical layout](#canonical-layout).
- **Small files.** There is one file for each thing you edit independently, so a sync conflict between devices stays rare and affects little.
- **Stable IDs you can read.** Files refer to each other by ID, never by display name, so you can rename anything freely.
- **Only inputs are stored.** Files hold what you entered, plus the prices, FX rates and inflation figures fetched at a check-in, with *Update Prices* or with *Fill In Past Prices*. Totals, charts and projections are always computed. The one deliberate exception is `projections/`: saved projections record what you expected at the time, which can't be recomputed later ([PROGRESS.md](PROGRESS.md)).
- **Unknown data survives.** When the app rewrites a file, it keeps fields it doesn't recognise, such as notes you added by hand, at any depth: in nested objects too, and in list items (a work phase, an event, an import column), which are matched by their key, ID, name or position.

## Layout

```
Can I Retire Yet/                   ← the app's folder in iCloud Drive
├── library.json                    settings and schema version
├── README.md                       written by the app: what this folder is and how to read it
├── accounts/
│   ├── conto-fineco.json
│   ├── directa.json
│   ├── ibkr.json
│   ├── ledger-wallet.json
│   ├── gold-coins.json
│   ├── fondo-pensione.json
│   ├── tfr.json
│   └── old-bank.json               closed accounts stay here
├── instruments/
│   ├── vwce.json
│   ├── btc.json
│   └── gold.json
├── history/                        valuations, trades, prices, FX rates and inflation by month
│   ├── 2025/
│   │   ├── 2025-11.json
│   │   └── 2025-12.json
│   └── 2026/
│       ├── 2026-01.json
│       └── …
├── plans/
│   ├── base.json
│   └── part-time-from-50.json
├── projections/
│   └── base/
│       ├── baselines/
│       │   └── 2026-01-05.json     a saved projection (see PROGRESS.md)
│       └── headlines/
│           └── 2026.json           the answer at each check-in
├── imports/
│   └── net-worth-sheet.json        saved import mappings (see IMPORT.md)
└── backups/                        copies made before a migration or an import
```

## Schemas

Every file's fields are in a [JSON Schema](https://json-schema.org) (draft 2020-12) in [schema/](schema/): types, which fields are required, defaults, ranges and what each field means, in the schemas' `description`s. This document covers what the schemas can't: how the files fit together, how values are computed from them, and how the app writes, merges and upgrades them.

| File | Schema |
| --- | --- |
| `library.json` | [library.schema.json](schema/library.schema.json) |
| `accounts/<id>.json` | [account.schema.json](schema/account.schema.json) |
| `instruments/<id>.json` | [instrument.schema.json](schema/instrument.schema.json) |
| `history/YYYY/YYYY-MM.json` | [history-month.schema.json](schema/history-month.schema.json) |
| `plans/<id>.json` | [plan.schema.json](schema/plan.schema.json) |
| `projections/<plan-id>/baselines/<id>.json` | [baseline.schema.json](schema/baseline.schema.json) |
| `projections/<plan-id>/headlines/<year>.json` | [headlines.schema.json](schema/headlines.schema.json) |
| `imports/<id>.json` | [import-profile.schema.json](schema/import-profile.schema.json) |
| `backups/<name>/backup.json` | [backup.schema.json](schema/backup.schema.json) |
| Shared values: decimals, dates, IDs, codes, asset mixes | [common.schema.json](schema/common.schema.json) |

- **Unknown keys are allowed.** The app keeps keys it doesn't know (Principles), so the schemas don't forbid them; a validator in strict mode, as the tests run it, reports them.
- **Open enums.** A "kind"-like field lists the values this version knows. A newer version may add values, which this one reads and writes back unchanged.
- **Checked by the tests.** `JSONSchemaTests` (StorageTests) validates every file of the example library against its schema, checks that every key the app reads is in its schema and the other way round, and that documents with every field set, as the app writes them, match. Any 2020-12 validator works too, e.g. `check-jsonschema --schemafile docs/schema/account.schema.json accounts/*.json` from the [schema folder](schema/).

The conventions every file shares (common.schema.json): **IDs** are lowercase slugs (`[a-z0-9-]+`), the same as the file name, and never change; files refer to each other by ID, never by name. **Dates** are `YYYY-MM-DD`, with no time or time zone; a value dated `2026-09-30` means "as of the end of that day". **Amounts, quantities, rates and shares** are exact decimals written as strings in their shortest form (`"1500"`, `"0.4215"`, `"0.26"` for 26%), negative for debts; plain JSON numbers are read too. **Currencies** are ISO 4217 codes, **countries** ISO 3166-1 alpha-2.

## `library.json`

```json
{
  "baseCurrency": "EUR",
  "mainPlan": "base",
  "person": { "birthDate": "1988-04-12", "name": "Me" },
  "schemaVersion": 3,
  "taxResidence": "IT"
}
```

Fields: [library.schema.json](schema/library.schema.json). Settings › You sets the base currency, the country and the inflation index (*Automatic* leaves `inflationIndex` out, so it's worked out as the schema describes); so do `retire init` and `retire settings --inflation-index hicp-ea` (`automatic` to leave it out). Check-ins, *Update Prices*, *Fill In Past Prices* and `retire prices` fetch the months missing of the index the library uses. Eurostat publishes an HICP for every EU country, Iceland, Norway, Switzerland, Albania, Montenegro, North Macedonia, Serbia and Türkiye (`hicp-gr` for Greece: ISO codes), and the euro area's (`hicp-ea`).

## `accounts/<id>.json`

A brokerage account whose holdings come from its trades ([TRADES.md](TRADES.md)):

```json
{
  "country": "IT",
  "currency": "EUR",
  "id": "directa",
  "institution": "Directa SIM",
  "kind": "brokerage",
  "name": "Directa",
  "opened": "2021-03-01",
  "tags": ["fire"],
  "valuation": "trades"
}
```

A pension fund, recorded as a balance, with its asset mix, that plans can draw on from 67:

```json
{
  "assetClasses": { "bonds": "0.4", "equity": "0.6" },
  "availableFromAge": 67,
  "country": "IT",
  "currency": "EUR",
  "id": "fondo-pensione",
  "kind": "pensionFund",
  "name": "Fondo pensione",
  "opened": "2022-01-01"
}
```

A closed account:

```json
{
  "closed": "2024-02-29",
  "country": "DE",
  "currency": "EUR",
  "id": "old-bank",
  "kind": "cash",
  "name": "Old bank",
  "opened": "2016-05-01",
  "successor": "conto-fineco"
}
```

Fields: [account.schema.json](schema/account.schema.json).

### Account lifecycle

- **Open:** create the account and set `opened`.
- **Close:** set `closed`. The account leaves check-ins and today's totals. Its valuations stay, and it still appears in every chart up to the day it closed. Nothing is deleted.
- **Reopen:** remove `closed`.
- **Rename or re-categorise:** edit the fields. The history refers to the ID, which never changes.
- **Delete:** only for mistakes. After you confirm, it removes the account file and its valuations.

## `instruments/<id>.json`

An instrument is anything you hold a quantity of. Its price is always per `unit`, in `currency`.

```json
{
  "assetClasses": { "equity": "1" },
  "currency": "EUR",
  "id": "vwce",
  "isin": "IE00BK5BQT80",
  "kind": "etf",
  "name": "Vanguard FTSE All-World UCITS ETF (Acc)",
  "priceSource": { "provider": "yahoo", "symbol": "VWCE.DE" },
  "unit": "share"
}
```

```json
{
  "assetClasses": { "crypto": "1" },
  "currency": "EUR",
  "id": "btc",
  "kind": "crypto",
  "name": "Bitcoin",
  "priceSource": { "provider": "coingecko", "symbol": "bitcoin" },
  "unit": "BTC"
}
```

```json
{
  "assetClasses": { "gold": "1" },
  "currency": "EUR",
  "id": "gold",
  "kind": "metal",
  "name": "Gold (coins and bars)",
  "priceSource": { "provider": "gold-api", "symbol": "XAU" },
  "unit": "g"
}
```

Fields, and how a price source's symbol is resolved: [instrument.schema.json](schema/instrument.schema.json). The price list shows what a CoinGecko ticker resolved to, e.g. "ETH → ethereum". Past prices may come from another source than `priceSource` ([PLAN.md](PLAN.md#prices-and-fx), "Past prices"): the price records say which, in `source`.

## `history/YYYY/YYYY-MM.json`

One file per calendar month. It holds the account valuations, trades, prices, FX rates and inflation-index values dated in that month.

```json
{
  "fx": [
    { "base": "EUR", "date": "2026-09-30", "quote": "USD", "rate": "1.1712", "source": "ecb" }
  ],
  "indices": [
    { "date": "2026-09-30", "index": "hicp-it", "source": "eurostat", "value": "128.41" }
  ],
  "month": "2026-09",
  "prices": [
    { "currency": "EUR", "date": "2026-09-30", "instrument": "btc", "price": "95120", "source": "coingecko" },
    { "currency": "EUR", "date": "2026-09-30", "instrument": "gold", "price": "98.4", "source": "gold-api" },
    { "currency": "EUR", "date": "2026-09-30", "instrument": "vwce", "price": "138.42", "source": "yahoo" }
  ],
  "valuations": [
    { "account": "conto-fineco", "balance": "4210.55", "date": "2026-09-30", "flow": "-310.2" },
    { "account": "directa", "cash": "312.1", "date": "2026-09-30", "flow": "11.3" },
    { "account": "fondo-pensione", "balance": "18450.12", "date": "2026-09-30", "flow": "1325", "note": "from Q3 statement" },
    { "account": "gold-coins", "date": "2026-09-30", "positions": [{ "instrument": "gold", "quantity": "62.2" }] },
    { "account": "ledger-wallet", "date": "2026-09-30", "positions": [{ "instrument": "btc", "quantity": "0.4215" }] }
  ]
}
```

(The numbers above are made up.) Directa records trades, so its valuation holds only its cash; its trades are in a `trades` list, left out when there are none, as in this month. From the example library's August:

```json
"trades": [
  { "account": "directa", "amount": "200.6", "date": "2026-08-04", "id": "rkbyjhkx", "type": "deposit" },
  {
    "account": "directa",
    "date": "2026-08-12",
    "fees": "5",
    "id": "q4nkf6gi",
    "instrument": "vwce",
    "price": "134.75",
    "quantity": "10",
    "type": "buy"
  }
]
```

Fields and rules (which file a record goes in, record keys, the two kinds of valuation, cost basis, flows, FX direction, sources, index values): [history-month.schema.json](schema/history-month.schema.json). How a trades account's holdings, cost and cash are worked out from its trades is in [TRADES.md](TRADES.md).

### How values are computed

The value of an account on a date **D**:

1. Take the account's latest valuation dated on or before D. Balances, quantities and cash carry forward until the next valuation.
2. Value each position at the latest price on or before D. So gold coins you never touch still follow the gold price, as long as gold prices are recorded. *Fill In Past Prices* records them for past valuations and month ends that have none.
3. Convert to the base currency at the latest FX rate on or before D.
4. Count the account only between its `opened` and `closed` dates.

An account that records trades holds what its trades leave on D, with its cash: the `cash` of its latest valuation on or before D, plus the cash effect of every trade after it, none for a trade paid from outside the account ([TRADES.md](TRADES.md#cash)). Steps 2 to 4 are the same.

**Net worth** on D is the sum over all accounts included in net worth.

**Staleness.** An account whose latest valuation is more than about 45 days old is flagged in the Overview. The threshold is a setting of the app, not of the library.

**Change since the last check-in.** Each account's change is split into **market**, **new money** and **other**:

- **The flow is known** (every valuation in the period has a `flow`, or there was no new valuation): new money is the flow, and market is the rest. For accounts that hold positions and use the default flow, market is then the old quantity × price change, including FX. A lower flow, e.g. for reinvested dividends, or a purchase below the check-in price counts as market.
- **Positions, flow unknown:** market is the old quantity × price change, including FX; new money is everything else, meaning changes in quantity and in cash.
- **Balance, flow unknown:** the change can't be split. Only the FX movement of the old balance counts as market, and the rest is other.
- **Trades:** new money is the account's deposits, withdrawals, transfers at market value, buys and sales paid from outside the account at their amount, and residuals (cash typed at a check-in that the trades don't explain), each at its date; market is the rest, including dividends, interest and fees ([TRADES.md](TRADES.md#flows)).

An account that closes during the period ends at zero: its value on the closing day leaves as new money.

## `plans/<id>.json`

There is one file per scenario. Fields: [plan.schema.json](schema/plan.schema.json); how the plan uses them: [PLANNER.md](PLANNER.md). Its amounts are in today's money, in the library's `baseCurrency`.

## `projections/<plan-id>/`

Saved projections for one plan:

- `baselines/<date>.json`: a projection saved at the first check-in of each year, or by hand. It stores the projected percentiles for each year, the expected path, the accounts included, and a copy of the plan's inputs.
- `headlines/<year>.json`: the headline answer recorded at each check-in: the earliest age, the chance at the target age and the readiness (plan assets as a share of what retiring today needs). Records written by earlier versions may also hold the old FI progress and the tax parameters used.

Fields: [baseline.schema.json](schema/baseline.schema.json) and [headlines.schema.json](schema/headlines.schema.json); examples in [PROGRESS.md](PROGRESS.md#baselines). These files aren't deleted when a plan changes or is deleted, because they are a record of the past.

## Sync conflicts

When two devices change the same file before it syncs, iCloud keeps both versions. The app merges them.

| File | MVP (M1) | Later (M3) |
| --- | --- | --- |
| `history/…`, `projections/…/headlines/…` | All records from both versions, matched by key: account + date, account + date + trade ID, instrument + date, currency pair + date, index + date, or check-in date. If both versions changed the same record, the more recently modified file wins. | Three-way merge record by record, using the device's last-synced copy as the common base. This also makes deletions merge correctly. |
| All other files | The more recently modified version wins. | Three-way merge field by field. |

Merges are listed on the Sync screen so you can check them. Before a merge replaces the file and iCloud's other versions are removed, each version that differs from the result is copied to its own `backups/<timestamp>-conflict/` folder, so nothing a merge drops is lost.

Versions modified at the same moment are ordered by their contents, so both devices resolve a conflict the same way. Within one version, the later of two records with the same key counts, as when loading. Everything else in a merged history or headline file (its unknown keys, for example) comes from the newest version, and the result is written in the canonical layout. A version that isn't valid JSON is left out of a merge.

## Saving

The app keeps the library in memory and writes only the files an edit changed. A file can change on disk after the app read it: the other device's change arrives, or you edit it by hand, and the app hasn't reloaded it yet. So every write compares the file on disk with the version the app last read, and never loses a change it hasn't seen:

| File | Changed on disk since the app read it |
| --- | --- |
| `history/…`, `projections/…/headlines/…` | Three-way merge record by record, with the version the app read as the common base. A record changed only on disk keeps the disk's version; a record changed only in the app gets the app's. A record changed on both sides, each in its own way, gets the app's version, unless the app deleted it: then the changed record is kept. Records added on disk, keys the app doesn't know, and records it can't read are kept. |
| All other files | The app's version is written, after the file on disk is copied to `backups/<timestamp>-conflict/`. A file the app deletes is kept instead. |

When records changed on both sides, the file is copied to `backups/<timestamp>-conflict/` first too. The Sync screen lists what happened, and the app then reloads the merged file. Reading, merging and writing a file is one coordinated operation, so a version iCloud Drive delivers meanwhile is merged as well.

A file that couldn't be read when the library loaded (it isn't valid JSON, or doesn't hold what it should) is copied to `backups/<timestamp>-unreadable/` before the app replaces or deletes it. `library.json` is the exception: the app never replaces it, because the settings it would write are only defaults (see [Reading hand-edited files](#reading-hand-edited-files)).

## Versioning

- `schemaVersion` starts at 1. Adding optional fields doesn't change it. Anything else is a new version with a migration.
- Version 2 lets accounts record trades (`"valuation": "trades"`, `trades` in the history files). An app that knows only version 1 would value such an account without its holdings, so it opens the library read-only. The migration from 1 changes nothing but `schemaVersion`.
- Version 3 drops the tax systems from plans ([PLANNER.md](PLANNER.md#the-model-in-brief)): plans take income and pensions after tax and two tax rates (`tax.investmentRate`, `tax.wealthRate`), and accounts say from what age plans can draw on them (`availableFromAge`). The migration from 2 carries over what it can: the residence in force becomes rates (Italy 26% and 0.2%, Germany 26.375%, the generic system's as written; Swiss rates depend on the canton and aren't guessed, so such a plan asks for them); work phases entered net and fixed pensions stay; a phase entered gross or a pension a tax system projected keeps its dates, and its name says what it was, for the amount after tax to be entered. A pension wrapper sets the account's `availableFromAge` (Italy's pension fund 67, Switzerland's pillar 3a and vested benefits 60, …). Account and instrument `tax` sections, the person's citizenships, pension-scheme contributions, event kinds, plan `withdrawals` and plan `currency` go.
- Before migrating, the app copies the library into `backups/<yyyy-MM-dd>-v<old>/`. A migration step works on the raw JSON of every file, and nothing is written unless every step succeeds.
- An app older than the library opens it read-only: it loads, and every save is refused.
- A library older than the app is migrated before the app saves anything to it.

## `imports/<id>.json`

Saved import profiles. Each describes how to read one kind of file (encoding, delimiter, number and date formats) and what each column becomes. Fields: [import-profile.schema.json](schema/import-profile.schema.json); how the importer uses them, with examples: [IMPORT.md](IMPORT.md#import-profiles).

A profile with a layout this version doesn't know, such as `"layout": "ledger"` with a `ledger` section (written by an earlier version, which imported ledger-cli and hledger journals), still loads and keeps all its keys when rewritten, but isn't offered for importing.

Trades an import writes have `"source": "import"` and a stable `id` (`TradeID.stable`: 8 base32 characters hashed from the row's account, date, type, instrument, quantity, amount and price, and its position among identical rows), so importing the same file again finds them instead of adding them twice.

## `backups/`

Copies of files taken before a schema migration, an import, or a save that had to replace a file (see [Saving](#saving)), in dated folders. They're what "Undo import" uses. Safe to delete.

- `backups/<yyyy-MM-dd-HHmmss>-<label>/` (the time is the device's local time), with the label `import`, `undo-import` (the files as they were before an undo), `prices`, `conflict` (a save or a sync conflict's merge replaced the file) or `unreadable`; `backups/<yyyy-MM-dd>-v<old>/` for a migration. A second backup with the same name gets `-2`, `-3`, ….
- Each folder mirrors the library's layout and has a `backup.json` ([backup.schema.json](schema/backup.schema.json)) listing what was copied and what didn't exist yet.
- After an import, the files as the import wrote them are copied to the backup's `result/` folder, and `backup.json` lists them under `result`.

**Undo import** compares each file now with the import's `result` and with the copy from before the import:

- A file unchanged since the import is put back as it was before it; a file the import created is deleted.
- In a history or headline file changed since, records unchanged since the import go back to how they were before it (records it added are removed), and records changed since keep their new values.
- Any other file changed since is left as it is.

The app and `retire import --undo` list what was left in place. A backup without `result` (taken by an older app) is restored as it is. A backup is only restored into a library with the same `schemaVersion`.

## Canonical layout

The app writes every file the same way, so the same data always gives the same bytes:

- UTF-8 with no byte order mark, two-space indentation, and a newline at the end.
- Object keys sorted by Unicode code point (so `"B"` comes before `"a"`).
- Text is written as is; only `"`, `\` and control characters are escaped (`\n`, `\t`, `\u0007`). Numbers (counts, ages, years) are written in their shortest exact form; amounts are strings, as above.
- A list or object stays on one line, as `{ "a": "1", "b": 2 }` or `["x", "y"]`, when the whole line fits in **130 columns**, counting indentation, the key and a trailing comma, in characters. Otherwise it is spread over several lines with one member or element per line, each laid out by the same rule. Empty ones are `{}` and `[]`.
- Two exceptions are always spread out: the file's top-level object, and lists of records directly in it (`valuations`, `prices`, `work`, `years`, …), which get one record per line even when they're short.

## Reading hand-edited files

- A file with a mistake doesn't stop the library from loading. The app lists each problem with the file's path and where in it, like `valuations[2].balance: Expected a decimal such as "1234.56", found "12,5".` or `Line 4, column 3: Expected "," or "}" after a value in an object`.
- A file that can't be read is left out. In a history or headline file only the records that can't be read are left out, and they're kept in the file when the app rewrites it, until you fix them. A file that is left out is copied to `backups/` before the app writes over it or deletes it.
- A `library.json` that exists but can't be read (it isn't valid JSON, or doesn't hold the settings) opens the library read-only, as a newer library does: the app would otherwise have only default settings (EUR, no birth date) to save over yours. The error on `library.json` says what's wrong; fix the file, or restore it from a backup, and open the library again. A folder with no `library.json` at all isn't affected: that's how a new library starts.
- A JSON number where text is expected (`"name": 2026`) is read as text, and a whole number written as text where a number is expected (`"endAge": "95"`) as a number.
- The file name wins over the `id` inside the file, and over the `month` inside a history file; the app points out the mismatch.
- A record dated outside its month file stays where it is, and the app points it out. When two records have the same key, the later one in the file is used.
- Records (valuations, trades, prices, FX rates, index values) dated before 1900, or more than a year after today, are loaded and pointed out: usually a mistyped year, or a placeholder such as `9999-12-31` for "no end date".
- Files the app doesn't know are ignored. JSON files in the library's folders whose names aren't IDs (`My Account.json`) are pointed out.
- Records that refer to accounts, instruments or plans that don't exist are pointed out.
