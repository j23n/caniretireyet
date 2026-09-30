# Library file format (v1)

The library is a folder. Everything the app knows is stored in it. If you delete the app and keep the folder, nothing is lost.

## Principles

- **Plain, stable JSON.** Files are UTF-8, pretty-printed with two-space indentation, sorted keys and a trailing newline. A record inside a list is kept on a single line when it fits, so a diff shows exactly which records changed. The same data always produces byte-identical files, so a file only changes when its data changes. If you put the folder in git, the diffs stay clean.
- **Small files.** There is one file for each thing you edit independently, so a sync conflict between devices stays rare and affects little.
- **Stable IDs you can read.** Files refer to each other by ID, never by display name, so you can rename anything freely.
- **Only inputs are stored.** Files hold what you entered, plus the prices and FX rates fetched at check-in time. Totals, charts and projections are always computed.
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
└── plans/
    ├── base.json
    └── part-time-from-50.json
```

## Conventions

| What | How |
| --- | --- |
| IDs | A lowercase slug (`[a-z0-9-]+`), unique within its folder and identical to the file name. The app creates it from the display name ("Conto Fineco" → `conto-fineco`) and adds `-2` if the slug is taken. An ID never changes. |
| Dates | `YYYY-MM-DD`: a calendar date with no time or time zone. A valuation dated `2026-09-30` means "as of the end of that day". |
| Amounts | Decimal strings such as `"1234.56"`, negative for debts. The app also accepts plain JSON numbers, for when you edit by hand. |
| Quantities | Decimal strings, e.g. `"0.4215"`. |
| Rates and shares | Decimal fractions as strings: `"0.26"` means 26%. |
| Currencies | ISO 4217 codes: `EUR`, `USD`, `CHF`. |
| Countries | ISO 3166-1 alpha-2 codes: `IT`, `IE`, `DE`. |

## `library.json`

```json
{
  "baseCurrency": "EUR",
  "person": {
    "birthDate": "1988-04-12",
    "name": "Me"
  },
  "schemaVersion": 1,
  "taxResidence": "IT"
}
```

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
  "tax": { "regime": "amministrato", "wrapper": "it.ordinary" }
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
| `institution`, `country` | no | The bank or broker, and its country. Foreign accounts mean IVAFE instead of bollo, and must be reported in the RW section of the tax return. |
| `valuation` | no | `balance` or `holdings`. The default depends on `kind`: brokerage, crypto and metals default to holdings. |
| `assetClasses` | no | The asset mix of an account recorded as a balance, used by the planner. Defaults by kind: cash → `cash`, property → `realEstate`. |
| `tax` | no | How the planner taxes this account. `wrapper` is one of `it.ordinary`, `it.pensionFund`, `it.tfr`, `it.pir` or `none`, followed by wrapper-specific details. |
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

One file per calendar month. It holds the account valuations, prices and FX rates dated in that month.

```json
{
  "fx": [
    { "base": "EUR", "date": "2026-09-30", "quote": "USD", "rate": "1.1712", "source": "ecb" }
  ],
  "month": "2026-09",
  "prices": [
    { "currency": "EUR", "date": "2026-09-30", "instrument": "btc", "price": "95120.00", "source": "coingecko" },
    { "currency": "EUR", "date": "2026-09-30", "instrument": "gold", "price": "98.40", "source": "gold-api" },
    { "currency": "EUR", "date": "2026-09-30", "instrument": "vwce", "price": "138.42", "source": "yahoo" }
  ],
  "valuations": [
    { "account": "conto-fineco", "balance": "4210.55", "date": "2026-09-30" },
    {
      "account": "directa",
      "cash": "312.10",
      "date": "2026-09-30",
      "positions": [
        { "costBasis": "48200.00", "instrument": "vwce", "quantity": "412.5" }
      ]
    },
    { "account": "fondo-pensione", "balance": "18450.12", "date": "2026-09-30", "note": "from Q3 statement" },
    { "account": "gold-coins", "date": "2026-09-30", "positions": [{ "instrument": "gold", "quantity": "62.2" }] },
    { "account": "ledger-wallet", "date": "2026-09-30", "positions": [{ "instrument": "btc", "quantity": "0.4215" }] }
  ]
}
```

(The prices above are made up.)

Rules:

- **Which file.** A record's date decides its file: `2026-09-30` goes in `history/2026/2026-09.json`.
- **Uniqueness.** There is at most one valuation per account per date, one price per instrument per date, and one FX rate per currency pair per date.
- **Two kinds of valuation.** A valuation holds either a `balance` (one amount in the account's currency, negative for debts) or `positions` plus optional `cash`. An account can switch between them over time. For example, the imported history can be balances and later check-ins can have positions.
- **Cost basis.** `costBasis` is optional: the total purchase cost of a position in the account's currency (Italian brokers show it as *valore di carico*). The planner uses it to estimate the tax due when you sell. Where it's missing, the plan asks for an estimate instead.
- **FX direction.** FX rates follow the ECB convention: 1 `base` = `rate` × `quote`.
- **Sorting.** Records are sorted by date, then by ID, so files diff cleanly.

### How values are computed

The value of an account on a date **D**:

1. Take the account's latest valuation dated on or before D. Balances, quantities and cash carry forward until the next valuation.
2. Value each position at the latest price on or before D. So gold coins you never touch still follow the gold price, as long as gold prices are recorded.
3. Convert to the base currency at the latest FX rate on or before D.
4. Count the account only between its `opened` and `closed` dates.

**Net worth** on D is the sum over all accounts included in net worth.

**Staleness.** An account whose latest valuation is more than about 45 days old is flagged in the Overview.

**Change since the last check-in.** For accounts that hold positions, the change is split into two parts:

- **market:** old quantity × price change, including FX;
- **new money:** everything else, meaning changes in quantity and in cash.

For accounts recorded as a balance, the change can't be split.

## `plans/<id>.json`

There is one file per scenario. Its fields and what they mean are described in [PLANNER.md](PLANNER.md#plan-file).

## Sync conflicts

When two devices change the same file before it syncs, iCloud keeps both versions. The app merges them.

| File | MVP (M1) | Later (M3) |
| --- | --- | --- |
| `history/…` | All records from both versions, matched by key: account + date, instrument + date, or currency pair + date. If both versions changed the same record, the more recently modified file wins. | Three-way merge record by record, using the device's last-synced copy as the common base. This also makes deletions merge correctly. |
| All other files | The more recently modified version wins. | Three-way merge field by field. |

Merges are listed on the Sync screen so you can check them.

## Versioning

- `schemaVersion` starts at 1. Adding optional fields doesn't change it. Anything else is a new version with a migration.
- Before migrating, the app copies the library into `backups/<date>-v<old>/`.
- An app older than the library opens it read-only.

## CSV import

The importer reads your spreadsheet as CSV. It detects the delimiter, the decimal separator and the date format, and shows a preview before it writes anything.

Wide layout (one row per month, one column per account):

```
Data;Conto Fineco;Directa;Bitcoin;Oro;Fondo pensione;Mutuo
31/01/2024;5.120,33;38.400,00;9.870,50;4.100,00;12.300,00;-195.000,00
29/02/2024;4.980,10;39.950,12;11.020,00;4.180,00;12.410,00;-194.300,00
```

Long layout:

```
date,account,value,currency
2024-01-31,Conto Fineco,5120.33,EUR
2024-01-31,Directa,38400.00,EUR
```

- **Mapping.** Each column or account name is mapped to an account. You can create new accounts or match existing ones.
- **Result.** Values become balance valuations.
- **Closed accounts.** An account whose values stop before the last row is proposed as closed.
- **Re-running.** A second import updates the same records instead of duplicating them.
