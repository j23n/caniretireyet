# Importer

Imports any spreadsheet or export by mapping its columns to what the library stores. It handles whatever date and number formats the file uses, and a mapping can be saved and reused, so the next file of the same shape imports in one step.

## Steps

1. **Open.** Pick a CSV or TSV file.
2. **Detect.** The importer guesses the encoding, the delimiter, the header row, and the number and date formats. Every guess can be overridden.
3. **Map.** Say what each column is (see [Layouts](#layouts) and [Targets](#targets)).
4. **Match.** Link names in the file to existing accounts and instruments, or create new ones.
5. **Preview.** Every parsed value is shown, problems are highlighted, and a summary lists what will be added, updated or left alone. Nothing is written yet.
6. **Import.** Records are written to the monthly history files. The affected files are backed up first, so the import can be undone.
7. **Save the mapping** as an import profile for next time.

## Files

- **Formats:** CSV and TSV with any delimiter (`,` `;` tab `|`) and quoted fields. Numbers and Excel can export these.
- **Encodings:** UTF-8 (with or without BOM), UTF-16, and Windows-1252 / ISO-8859-1. Excel on Windows often exports Italian files in Windows-1252.
- **Rows:** a header row anywhere (with rows above it skipped), empty rows ignored, and footer rows such as "Totale" excluded by a rule you can edit.
- **Later:** reading `.xlsx` and `.numbers` files directly.

## Layouts

- **Wide:** one row per date, one column per account or value. This is how most net-worth spreadsheets look.

  ```
  Data;Conto Fineco;Directa;BTC (qtà);Oro
  31/01/2024;5.120,33;38.400,00;0,215;4.100,00
  ```

  One column holds the date. Each other column is mapped to a target, or ignored.
- **Long:** one row per record, e.g. a broker export or a table with date, account and value. Each column is mapped to a field.

  ```
  date,account,value,currency
  2024-01-31,Conto Fineco,5120.33,EUR
  ```

## Targets

Each value in a file can become one of these:

| Target | Needs | Stored as |
| --- | --- | --- |
| Account balance | account, date, amount | A valuation with `balance` |
| Quantity held | account, instrument, date, quantity | A position in a valuation |
| Purchase cost | account, instrument, date, amount | The position's `costBasis` |
| Cash in an investment account | account, date, amount | A valuation's `cash` |
| Price | instrument, date, price, currency | A price record |
| FX rate | currency pair, date, rate | An FX record |
| Ignore | — | — |

Each field a target needs can come from one of three places:

- **a column**, e.g. an "Account" column in a long file;
- **a constant**, e.g. "every row of this file is account Directa";
- **the column header**, in the wide layout: the column "Directa" means account `directa`.

Buy and sell transactions aren't a target in the MVP, because the tracker stores holdings month by month rather than transactions. A later target could turn a broker's transaction export into monthly holdings and purchase costs.

## Value formats

Every column has a format. The file sets the defaults, a column can override them, and the importer proposes a format by testing it against every value in the column.

**Numbers**

- **Separators:** the decimal separator is `.` or `,`. The thousands separator can be none, `.`, `,`, a space, a non-breaking space or `'`.
- **Currency markers** are stripped: `€ 1.234,56`, `EUR 1234.56` and `1,234.56 $` all work. A currency code found in the cell can also be used as the value's currency.
- **Negatives** can be written `-1`, `(1)` or `1-`.
- **Percentages** are supported.
- **Empty cells** are skipped by default (not read as zero). You can choose to read them as zero.
- **Ambiguous values** such as `1,234`: when a column could be read either way, the importer asks.

**Dates**

- **Patterns:** `yyyy-MM-dd`, `dd/MM/yyyy`, `MM/dd/yyyy`, `dd.MM.yyyy`, `d-MMM-yy`, and month names in English and Italian (`31 gen 2024`, `gennaio 2024`), or any custom pattern.
- **Month-only dates** such as `2024-01`, `01/2024` or `Jan 2024` become the last day of the month by default, or the first if you prefer.
- **Excel date serial numbers** (e.g. `45322`) are converted.
- **Date-times:** the time is dropped, using the time zone you choose.
- **Day or month first:** `dd/MM` and `MM/dd` are told apart as soon as any day in the column is above 12. If none is, the importer asks.

**Text**

- Values are trimmed.
- A value map translates labels, e.g. both "Fineco" and "Conto Fineco" → account `conto-fineco`.

## Matching accounts and instruments

- Names are matched ignoring case and accents, and every match you confirm is remembered in the profile.
- An unmatched name can create a new account or instrument. You confirm its kind and currency; the importer suggests them, e.g. from a currency code in the values.
- An account whose values stop before the file's last date is proposed as closed, on the day after its last value.

## Preview, conflicts and undo

- **Preview.** Cells that can't be parsed are highlighted with the reason, e.g. "not a date in dd/MM/yyyy". You can fix the format, exclude the rows, or cancel.
- **Records already in the library** are matched by key: account + date, instrument + date, or currency pair + date.
  - An identical record is left alone.
  - A record with a different value follows the policy you choose: overwrite, keep the existing value, or decide one by one.
  - Importing the same file twice therefore changes nothing.
- **Undo.** Before writing, the files about to change are copied to `backups/<timestamp>-import/`. "Undo import" restores them.

## Import profiles

A profile is a saved mapping in the library: `imports/<id>.json`. It syncs like everything else, so a profile made on the Mac works on the iPhone and in the CLI.

Columns are identified by their header text, and by position only when there's no header. So reordered columns still import, and a column the profile doesn't know is flagged instead of being guessed.

```json
{
  "id": "net-worth-sheet",
  "name": "My net worth spreadsheet",
  "file": { "delimiter": ";", "encoding": "windows-1252", "headerRow": 1 },
  "defaults": {
    "date": { "pattern": "dd/MM/yyyy" },
    "number": { "decimal": ",", "thousands": "." },
    "empty": "skip"
  },
  "layout": "wide",
  "dateColumn": "Data",
  "columns": [
    { "header": "Conto Fineco", "target": "balance", "account": "conto-fineco" },
    { "header": "Directa", "target": "balance", "account": "directa" },
    { "header": "BTC (qtà)", "target": "quantity", "account": "ledger-wallet", "instrument": "btc" },
    { "header": "Oro", "target": "balance", "account": "gold-coins" },
    { "header": "Note", "target": "ignore" }
  ],
  "onConflict": "ask"
}
```

(Keys are shown in reading order; the app writes them sorted.)

Other fields a profile can have, all optional:

| Field | Meaning |
| --- | --- |
| `file.excludeRows` | Rows to skip, such as totals: a row is skipped when its first non-empty cell starts with one of these, ignoring case and accents, e.g. `["Totale"]`. |
| `file.headerRow` | The 1-based row holding the headers; `0` means the file has none. Left out, it's detected. |
| `defaults.date` | `pattern` (e.g. `dd/MM/yyyy`, or `excel-serial`), `monthOnly` (`end`, the default, or `start`), and `timeZone` (an IANA name) for date-times. |
| `defaults.number` | `decimal` and `thousands` separators (`""` for none), and `percent`. |
| `columns[].index` | The 1-based column position, used only when the file has no header. |
| `columns[].currency`, `base`, `quote` | The currency of a column's amounts or prices, or an FX column's pair. |
| `columns[].format` | Overrides of `defaults` for one column: `date`, `number`, `empty`. |
| `columns[].field` | Long layout: what the column holds for each row's record: `date`, `account`, `instrument`, `value`, `currency`, `base`, `quote` or `ignore`. |
| `target` | Long layout: what each row becomes (`balance`, `quantity`, `costBasis`, `cash`, `price` or `fx`). |
| `constants` | Long layout: fields that are the same for every row: `account`, `instrument`, `currency`, `base`, `quote`. |
| `matches` | Names found in files matched to IDs, remembered from earlier imports: `{ "accounts": { "Fineco": "conto-fineco" }, "instruments": { … } }`. |
| `onConflict` | `ask` (the default), `overwrite` or `keep`. |

## Where it runs

- **Engine.** The `Importer` module, in pure Swift. It's tested on Linux against a folder of sample files: Italian Excel CSVs in Windows-1252, US-style exports, Numbers exports, month-only dates, Excel serial dates, broken rows.
- **App.** The same SwiftUI flow on Mac and iPhone. The Mac, with its big table, is the comfortable place to build a profile. On the iPhone, you can open a CSV from Files and import it with a saved profile.
- **CLI.** `retire import <file> --profile <id> [--dry-run]` prints the same summary as the preview.
