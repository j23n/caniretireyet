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
- **Rows:** a header row anywhere (with rows above it skipped), empty rows ignored, and footer rows such as "Totale" excluded by a rule you can edit or turn off (by default, rows starting with "Totale" or "Total").
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
- **the column header**, in the wide layout: the column "Directa" means account `directa`. The header gives what the column and the constants leave out: the account of a balance or cash column, the instrument of a price column, and for a quantity or purchase cost, the instrument once the account is set. Headers are matched without their decorations, so "BTC (qtà)" means `btc`. A header the importer can't use this way is flagged rather than guessed.

When there's no profile yet, the importer proposes a mapping from the headers and the values: a column of dates holds the dates; number columns become balances, or quantities, prices, cash, purchase costs or FX rates when the header says so (`BTC (qtà)`, `Prezzo VWCE`, `EUR/USD`); text, percentage and total columns are ignored. The layout is long when a text column's header names accounts or instruments.

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
- **Excel serials or numbers:** whole numbers are read as Excel dates when the header says it's a date column (`Data`, `Date`, `Mese`, …). A first column of increasing serials without such a header is read as dates too, but the importer asks.

**Debts**

- The library stores the balance of a debt account (kind `loan`, `mortgage` or `creditCard`) as a negative amount. Spreadsheets usually write it as a positive one ("146.250" for a mortgage), so by default (`auto`) a positive balance for a debt account is read as a debt and stored negative, and the preview adds a note such as “Mutuo”: positive amounts were read as debts (12 values). Negative amounts are kept as they are.
- `auto` looks at each column's convention first. A column where any balance of a debt account is negative already writes debts as negative amounts, so its signs are kept: a positive amount there is a debt in credit (an overpaid card at +20 stays +20), and the preview notes it: “Carta”: the column writes debts as negative amounts, so positive amounts were kept as credit (1 value). In the long layout, one value column holds every account, so one negative debt keeps the signs of the whole column.
- The account's kind decides, including the kind of a new account the import creates: if you change a proposed account's kind, its balances (and its column's convention) follow when you import.
- To keep the file's signs whatever they are, set `liabilitySign` to `asWritten` in the profile's `defaults`, or in one column's `format` (the default is `auto`).

**Text**

- Values are trimmed.
- A value map translates labels, e.g. both "Fineco" and "Conto Fineco" → account `conto-fineco`.

## Matching accounts and instruments

- Names are matched ignoring case and accents, and every match you confirm is remembered in the profile.
- An unmatched name can create a new account or instrument. You confirm its kind and currency; the importer suggests them, e.g. from a currency code in the values.
- An account whose values stop before the file's last date is proposed as closed, on the day after its last value. Trailing zeros don't count as values; a cell that couldn't be read does. It isn't proposed when the library has later values for it.
- An account with values from before its `opened` date is proposed to open on the first of them.
- New accounts, new instruments and these changes are applied unless you reject them. A rejected account's or instrument's records are left out.

## Preview, conflicts and undo

- **Preview.** Cells that can't be parsed are highlighted with the reason, e.g. "not a date in dd/MM/yyyy". You can fix the format, exclude the rows, or cancel.
- **Records already in the library** are matched by key: account + date, instrument + date, or currency pair + date.
  - An identical record is left alone. Only the values the file has are compared: a flow or a note in the library stays.
  - A record the library has without some of the file's values, such as a purchase cost, is *updated*: the missing values are filled in, and nothing in the library changes.
  - A record with a different value follows the policy you choose: overwrite, keep the existing value, or decide one by one. Conflicts still undecided when you import are kept. Switching a valuation between a balance and positions is a conflict too.
  - Importing the same file twice therefore changes nothing.
- **Undo.** Before writing, the files about to change are copied to `backups/<timestamp>-import/`, and after writing, the files as the import wrote them are recorded in the same backup. "Undo import" (and `retire import --undo`) puts back what the import changed and leaves later edits alone: a record you changed after the import keeps its new value, and a file you changed otherwise is left as it is. It lists what it left in place ([FILE_FORMAT.md](FILE_FORMAT.md#backups)).

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
| `file.encoding` | The text encoding. Left out, it's detected. A byte-order mark in the file wins, and so does valid UTF-8 with accented letters over `windows-1252` or `iso-8859-1`, as when a file is saved again from another app. |
| `file.excludeRows` | Rows to skip, such as totals: a row is skipped when its first non-empty cell starts with one of these, ignoring case and accents, e.g. `["Totale"]`. Left out, it's `["Totale", "Total"]`; an empty list, `[]`, skips no rows. |
| `file.headerRow` | The 1-based row holding the headers; `0` means the file has none. Left out, it's detected. |
| `defaults.date` | `pattern` (e.g. `dd/MM/yyyy`, or `excel-serial`), `monthOnly` (`end`, the default, or `start`), and `timeZone` (an IANA name) for date-times. |
| `defaults.number` | `decimal` and `thousands` separators (`""` for none), and `percent`. |
| `defaults.liabilitySign` | How balances of debt accounts are signed in the file: `auto` (the default: a positive amount is a debt and is stored negative, unless its column writes any debt as a negative amount, when the column's signs are kept) or `asWritten` (keep the file's sign). See [Debts](#value-formats). |
| `columns[].index` | The 1-based column position, used only when the file has no header. |
| `columns[].currency`, `base`, `quote` | The currency of a column's amounts or prices, or an FX column's pair. |
| `columns[].format` | Overrides of `defaults` for one column: `date`, `number`, `empty`, `liabilitySign`. |
| `columns[].field` | Long layout: what the column holds for each row's record: `date`, `account`, `instrument`, `value`, `currency`, `base`, `quote` or `ignore`. |
| `target` | Long layout: what each row becomes (`balance`, `quantity`, `costBasis`, `cash`, `price` or `fx`). A value column can set its own `target`, so one row can hold a quantity, a price and a purchase cost. |
| `constants` | Long layout: fields that are the same for every row: `account`, `instrument`, `currency`, `base`, `quote`. Wide columns that leave these out use them too. |
| `matches` | Names found in files matched to IDs, remembered from earlier imports: `{ "accounts": { "Fineco": "conto-fineco" }, "instruments": { … } }`. |
| `onConflict` | `ask` (the default), `overwrite` or `keep`. |

## Where it runs

- **Engine.** The `Importer` module, in pure Swift. It reads bytes and a `Library` and returns results; the app and the CLI back up and write the files it reports as changed. It's tested on Linux against a folder of sample files (`Tests/ImporterTests/Samples/`): Italian Excel CSVs in Windows-1252, US-style exports, Numbers exports, title and totals rows, month-only dates, Excel serial dates, long files, quantities with prices, debts written as positive amounts (and columns that write them negative), broken rows.
  - `ImportSession(data:)` reads a file and proposes a mapping, or `ImportSession(data:profile:)` uses a saved one. The session holds the mapping as an `ImportProfile`, with helpers to map a column, pick the date column, remember a match and settle an ambiguity.
  - `session.preview(against:)` returns an `ImportPreview`: every record with its status, cell errors, issues, ambiguities, name matches, and the proposed accounts, instruments and account changes.
  - `preview.apply(to:)` returns an `ImportResult`: the new library and the month files, accounts and instruments that changed.
  - `session.makeProfile(id:name:library:)` saves the mapping with everything detected written out.
- **App.** The same SwiftUI flow on Mac and iPhone. The Mac, with its big table, is the comfortable place to build a profile. On the iPhone, you can open a CSV from Files and import it with a saved profile.
- **CLI.** `retire import <file>` previews without writing (the default, `--dry-run`): the detected settings, what each column becomes, the formats to confirm, notes, proposed accounts and closings, a summary with sample records and conflicts, and the cells that can't be read. `--save-profile <id>` saves the proposed mapping as `imports/<id>.json` to edit and reuse with `--profile <id>`; options such as `--date-format`, `--decimal`, `--delimiter` and `--liability-sign` override what was detected. `--apply` backs up the files that change to `backups/<timestamp>-import/` and writes them; it refuses while formats are still guesses (unless `--accept-guesses`). Non-interactively, new accounts and instruments and closings are only made with `--accept-new-accounts`, `--accept-new-instruments` and `--accept-closings` (their records are left out otherwise), and conflicts follow `--on-conflict keep|overwrite` (undecided ones keep the library's values). `retire import --undo` undoes the latest import not undone yet, leaving later edits in place and listing them, after copying the current files to `backups/<timestamp>-undo-import/`.
