# Library file format (v1)

The library is a folder. Everything the app knows is stored in it. If you delete the app and keep the folder, nothing is lost.

## Principles

- **Plain, stable JSON.** Files are UTF-8, pretty-printed with two-space indentation, sorted keys and a trailing newline. A record inside a list is kept on a single line when it fits, so a diff shows exactly which records changed. The same data always produces byte-identical files, so a file only changes when its data changes. If you put the folder in git, the diffs stay clean. The exact layout is in [Canonical layout](#canonical-layout).
- **Small files.** There is one file for each thing you edit independently, so a sync conflict between devices stays rare and affects little.
- **Stable IDs you can read.** Files refer to each other by ID, never by display name, so you can rename anything freely.
- **Only inputs are stored.** Files hold what you entered, plus the prices, FX rates and inflation figures fetched at check-in time. Totals, charts and projections are always computed. The one deliberate exception is `projections/`: saved projections record what you expected at the time, which can't be recomputed later ([PROGRESS.md](PROGRESS.md)).
- **Unknown data survives.** When the app rewrites a file, it keeps fields it doesn't recognise, such as notes you added by hand.

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
├── history/
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

## Conventions

| What | How |
| --- | --- |
| IDs | A lowercase slug (`[a-z0-9-]+`), unique within its folder and identical to the file name. The app creates it from the display name ("Conto Fineco" → `conto-fineco`) and adds `-2` if the slug is taken. An ID never changes. |
| Dates | `YYYY-MM-DD`: a calendar date with no time or time zone. A valuation dated `2026-09-30` means "as of the end of that day". |
| Amounts | Decimal strings such as `"1234.56"`, negative for debts. The app also accepts plain JSON numbers, for when you edit by hand. It writes the shortest exact form: `"1500"`, not `"1500.00"`. Both read as the same value. |
| Quantities | Decimal strings, e.g. `"0.4215"`. |
| Rates and shares | Decimal fractions as strings: `"0.26"` means 26%. |
| Currencies | ISO 4217 codes: `EUR`, `USD`, `CHF`. |
| Countries | ISO 3166-1 alpha-2 codes: `IT`, `IE`, `DE`. |

## `library.json`

```json
{
  "baseCurrency": "EUR",
  "mainPlan": "base",
  "person": { "birthDate": "1988-04-12", "name": "Me" },
  "schemaVersion": 1,
  "taxResidence": "IT"
}
```

`mainPlan` is the plan shown on the Overview. It's re-run at every check-in, and a baseline of it is saved automatically at the first check-in of each year.

Settings that belong to one device, such as reminder times and UI state, are stored on that device, not in the library.

## `accounts/<id>.json`

A brokerage account that holds positions:

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
  "tax": { "wrapper": "it.ordinary" }
}
```

A pension fund, recorded as a balance, with its asset mix:

```json
{
  "assetClasses": { "bonds": "0.4", "equity": "0.6" },
  "country": "IT",
  "currency": "EUR",
  "id": "fondo-pensione",
  "kind": "pensionFund",
  "name": "Fondo pensione",
  "opened": "2022-01-01",
  "tax": { "joined": "2022-01-01", "wrapper": "it.pensionFund" }
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

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | yes | The slug; same as the file name. |
| `name` | yes | Display name. Change it whenever you like. |
| `kind` | yes | `cash`, `savings`, `brokerage`, `crypto`, `metals`, `pensionFund`, `tfr`, `property`, `vehicle`, `loan`, `mortgage`, `creditCard` or `other`. |
| `currency` | yes | The currency of this account's balances and cash. |
| `opened` | yes | The first day the account counts toward net worth. |
| `closed` | no | The last day it counts. Absent while the account is active. |
| `institution`, `country` | no | The bank or broker, and its country. The tax system may use the country, e.g. Italy's higher wealth-tax rate for blacklisted countries. So does the RW helper, which lists the foreign accounts you have to declare. |
| `valuation` | no | `balance` or `holdings`. The default depends on `kind`: brokerage, crypto and metals default to holdings. |
| `assetClasses` | no | The asset mix of an account recorded as a balance, used by the planner. Defaults by kind: cash and savings → `cash`, property → `realEstate`. |
| `tax` | no | How the planner taxes this account. `wrapper` names a wrapper defined by a tax system (for Italy: `it.ordinary`, `it.pensionFund`, `it.tfr`) or a generic one (`taxable`, `taxDeferred`, `taxFree`). Wrapper-specific details follow. See [TAXES.md](TAXES.md). |
| `includeIn` | no | `{ "netWorth": true, "plan": true }`. A primary home would normally set `"plan": false`. |
| `successor` | no | The account that replaced this one, e.g. when you switched banks, so charts stay continuous. |
| `tags`, `notes` | no | Free-form. |

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

| Field | Required | Meaning |
| --- | --- | --- |
| `kind` | yes | `etf`, `fund`, `stock`, `bond`, `etc`, `crypto`, `metal` or `other`. |
| `currency`, `unit` | yes | What the price is quoted in and per what. The fetcher converts, e.g. USD per troy ounce into EUR per gram. |
| `assetClasses` | yes | Its mix across `equity`, `bonds`, `cash`, `gold`, `crypto`, `realEstate` and `other`. A 60/40 fund is `{ "equity": "0.6", "bonds": "0.4" }`. |
| `isin`, `ticker` | no | Identification. |
| `tax` | no | Overrides the Italian tax treatment implied by `kind`. For example, `{ "govBondShare": "0.8" }` is used for the 12.5% rate on government bonds, applied pro rata. |
| `priceSource` | no | Where prices come from. If it's absent, you enter prices by hand. |

## `history/YYYY/YYYY-MM.json`

One file per calendar month. It holds the account valuations, prices, FX rates and inflation-index values dated in that month.

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
    {
      "account": "directa",
      "cash": "312.1",
      "date": "2026-09-30",
      "flow": "1500",
      "positions": [{ "costBasis": "48200", "instrument": "vwce", "quantity": "412.5" }]
    },
    { "account": "fondo-pensione", "balance": "18450.12", "date": "2026-09-30", "flow": "1325", "note": "from Q3 statement" },
    { "account": "gold-coins", "date": "2026-09-30", "positions": [{ "instrument": "gold", "quantity": "62.2" }] },
    { "account": "ledger-wallet", "date": "2026-09-30", "positions": [{ "instrument": "btc", "quantity": "0.4215" }] }
  ]
}
```

(The numbers above are made up.)

Rules:

- **Which file.** A record's date decides its file: `2026-09-30` goes in `history/2026/2026-09.json`.
- **Uniqueness.** There is at most one valuation per account per date, one price per instrument per date, one FX rate per currency pair per date, and one value per index per date.
- **Two kinds of valuation.** A valuation holds either a `balance` (one amount in the account's currency, negative for debts) or `positions` plus optional `cash`. An account can switch between them over time. For example, the imported history can be balances and later check-ins can have positions.
- **Cost basis.** `costBasis` is optional: the total purchase cost of a position in the account's currency (Italian brokers show it as *valore di carico*). The planner uses it to estimate the tax due when you sell. Where it's missing, the plan asks for an estimate instead. It matters most for physical gold: if you can't document the purchase price, Italy taxes the whole sale price.
- **Flow.** `flow` is optional: the net money added (+) or taken out (−) since the account's previous valuation, in the account's currency. The check-in fills it in from defaults that depend on the kind of account, and you can edit it (see [PROGRESS.md](PROGRESS.md#data-this-needs-from-day-one)). A missing flow means unknown. The sum of all flows over a period is what you actually saved.
- **FX direction.** FX rates follow the ECB convention: 1 `base` = `rate` × `quote`.
- **Indices.** `indices` holds consumer-price-index values (`hicp-it`: Italy's all-items HICP from Eurostat, 2015 = 100). They're used to express history in today's euros and to compute real returns. A monthly value is dated the last day of the month it measures and stored in that month's file, even when it's published and fetched later.
- **Sorting.** Records are sorted by date, then by ID, so files diff cleanly.

### How values are computed

The value of an account on a date **D**:

1. Take the account's latest valuation dated on or before D. Balances, quantities and cash carry forward until the next valuation.
2. Value each position at the latest price on or before D. So gold coins you never touch still follow the gold price, as long as gold prices are recorded.
3. Convert to the base currency at the latest FX rate on or before D.
4. Count the account only between its `opened` and `closed` dates.

**Net worth** on D is the sum over all accounts included in net worth.

**Staleness.** An account whose latest valuation is more than about 45 days old is flagged in the Overview. The threshold is a setting of the app, not of the library.

**Change since the last check-in.** Each account's change is split into **market**, **new money** and **other**:

- **The flow is known** (every valuation in the period has a `flow`, or there was no new valuation): new money is the flow, and market is the rest. For accounts that hold positions and use the default flow, market is then the old quantity × price change, including FX. A lower flow, e.g. for reinvested dividends, or a purchase below the check-in price counts as market.
- **Positions, flow unknown:** market is the old quantity × price change, including FX; new money is everything else, meaning changes in quantity and in cash.
- **Balance, flow unknown:** the change can't be split. Only the FX movement of the old balance counts as market, and the rest is other.

An account that closes during the period ends at zero: its value on the closing day leaves as new money.

## `plans/<id>.json`

There is one file per scenario. Its fields and what they mean are described in [PLANNER.md](PLANNER.md#plan-file).

## `projections/<plan-id>/`

Saved projections for one plan:

- `baselines/<date>.json`: a projection saved at the first check-in of each year, or by hand. It stores the projected percentiles for each year, the expected path, the accounts included, and a copy of the plan's inputs.
- `headlines/<year>.json`: the headline answer recorded at each check-in.

Fields and examples are in [PROGRESS.md](PROGRESS.md#baselines). These files aren't deleted when a plan changes or is deleted, because they are a record of the past.

## Sync conflicts

When two devices change the same file before it syncs, iCloud keeps both versions. The app merges them.

| File | MVP (M1) | Later (M3) |
| --- | --- | --- |
| `history/…`, `projections/…/headlines/…` | All records from both versions, matched by key: account + date, instrument + date, currency pair + date, index + date, or check-in date. If both versions changed the same record, the more recently modified file wins. | Three-way merge record by record, using the device's last-synced copy as the common base. This also makes deletions merge correctly. |
| All other files | The more recently modified version wins. | Three-way merge field by field. |

Merges are listed on the Sync screen so you can check them.

Versions modified at the same moment are ordered by their contents, so both devices resolve a conflict the same way. Everything else in a merged history or headline file (its unknown keys, for example) comes from the newest version, and the result is written in the canonical layout. A version that isn't valid JSON is left out of a merge.

## Versioning

- `schemaVersion` starts at 1. Adding optional fields doesn't change it. Anything else is a new version with a migration.
- Before migrating, the app copies the library into `backups/<yyyy-MM-dd>-v<old>/`. A migration step works on the raw JSON of every file, and nothing is written unless every step succeeds.
- An app older than the library opens it read-only: it loads, and every save is refused.
- A library older than the app is migrated before the app saves anything to it.

## `imports/<id>.json`

Saved import profiles. Each describes how to read one kind of file (encoding, delimiter, number and date formats) and what each column becomes. See [IMPORT.md](IMPORT.md#import-profiles) for the fields and an example.

## `backups/`

Copies of files taken before a schema migration or an import, in dated folders. They're what "Undo import" restores. Safe to delete.

- `backups/<yyyy-MM-dd-HHmmss>-<label>/` for an import (the time is the device's local time), `backups/<yyyy-MM-dd>-v<old>/` for a migration. A second backup with the same name gets `-2`, `-3`, ….
- Each folder mirrors the library's layout and has a `backup.json` listing the files copied (`files`), the files that didn't exist yet (`absentFiles`, which restoring deletes), a `label` and when it was `created`.
- When the app has to overwrite a file that isn't valid JSON, it first copies it to `backups/<timestamp>-unreadable/`.

## Canonical layout

The app writes every file the same way, so the same data always gives the same bytes:

- UTF-8 with no byte order mark, two-space indentation, and a newline at the end.
- Object keys sorted by Unicode code point (so `"B"` comes before `"a"`).
- Text is written as is; only `"`, `\` and control characters are escaped (`\n`, `\t`, `\u0007`). Numbers (counts, ages, years) are written in their shortest exact form; amounts are strings, as above.
- A list or object stays on one line, as `{ "a": "1", "b": 2 }` or `["x", "y"]`, when the whole line fits in **130 columns**, counting indentation, the key and a trailing comma, in characters. Otherwise it is spread over several lines with one member or element per line, each laid out by the same rule. Empty ones are `{}` and `[]`.
- Two exceptions are always spread out: the file's top-level object, and lists of records directly in it (`valuations`, `prices`, `work`, `years`, …), which get one record per line even when they're short.

## Reading hand-edited files

- A file with a mistake doesn't stop the library from loading. The app lists each problem with the file's path and where in it, like `valuations[2].balance: Expected a decimal such as "1234.56", found "12,5".` or `Line 4, column 3: Expected "," or "}" after a value in an object`.
- A file that can't be read is left out. In a history or headline file only the records that can't be read are left out, and they're kept in the file when the app rewrites it, until you fix them.
- A JSON number where text is expected (`"name": 2026`) is read as text, and a whole number written as text where a number is expected (`"endAge": "95"`) as a number.
- The file name wins over the `id` inside the file, and over the `month` inside a history file; the app points out the mismatch.
- A record dated outside its month file stays where it is, and the app points it out. When two records have the same key, the later one in the file is used.
- Files the app doesn't know are ignored. JSON files in the library's folders whose names aren't IDs (`My Account.json`) are pointed out.
- Records that refer to accounts, instruments or plans that don't exist are pointed out.
