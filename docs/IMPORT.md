# Importer

Imports any spreadsheet or export by mapping its columns to what the library stores. It handles whatever date and number formats the file uses, and a mapping can be saved and reused, so the next file of the same shape imports in one step.

It also imports ledger-cli and hledger journals: see [Ledger journals](#ledger-journals).

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
- **Rows:** a header row anywhere (with rows above it skipped), empty rows ignored, and footer rows such as "Totale" excluded by a rule you can edit (by default, rows starting with "Totale" or "Total").
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

- The library stores the balance of a debt account (kind `loan`, `mortgage` or `creditCard`) as a negative amount. Spreadsheets usually write it as a positive one ("146.250" for a mortgage), so by default a positive balance for a debt account is read as a debt and stored negative, and the preview adds a note such as “Mutuo”: positive amounts were read as debts (12 values). Negative amounts are kept as they are.
- The account's kind decides, including the kind of a new account the import creates: if you change a proposed account's kind, its balances follow when you import.
- To keep the file's signs, set `liabilitySign` to `asWritten` in the profile's `defaults`, or in one column's `format` (the default is `auto`).

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
| `file.excludeRows` | Rows to skip, such as totals: a row is skipped when its first non-empty cell starts with one of these, ignoring case and accents, e.g. `["Totale"]`. Left out, it's `["Totale", "Total"]`. |
| `file.headerRow` | The 1-based row holding the headers; `0` means the file has none. Left out, it's detected. |
| `defaults.date` | `pattern` (e.g. `dd/MM/yyyy`, or `excel-serial`), `monthOnly` (`end`, the default, or `start`), and `timeZone` (an IANA name) for date-times. |
| `defaults.number` | `decimal` and `thousands` separators (`""` for none), and `percent`. |
| `defaults.liabilitySign` | How balances of debt accounts are signed in the file: `auto` (the default: a positive amount is a debt and is stored negative) or `asWritten` (keep the file's sign). See [Debts](#value-formats). |
| `columns[].index` | The 1-based column position, used only when the file has no header. |
| `columns[].currency`, `base`, `quote` | The currency of a column's amounts or prices, or an FX column's pair. |
| `columns[].format` | Overrides of `defaults` for one column: `date`, `number`, `empty`, `liabilitySign`. |
| `columns[].field` | Long layout: what the column holds for each row's record: `date`, `account`, `instrument`, `value`, `currency`, `base`, `quote` or `ignore`. |
| `target` | Long layout: what each row becomes (`balance`, `quantity`, `costBasis`, `cash`, `price` or `fx`). A value column can set its own `target`, so one row can hold a quantity, a price and a purchase cost. |
| `constants` | Long layout: fields that are the same for every row: `account`, `instrument`, `currency`, `base`, `quote`. Wide columns that leave these out use them too. |
| `matches` | Names found in files matched to IDs, remembered from earlier imports: `{ "accounts": { "Fineco": "conto-fineco" }, "instruments": { … } }`. |
| `onConflict` | `ask` (the default), `overwrite` or `keep`. |

## Ledger journals

Plain-text accounting journals, as [ledger-cli](https://ledger-cli.org) and [hledger](https://hledger.org) read them, can be imported too. A journal records every transaction, so the importer works out what a spreadsheet can't give: each account's value month by month, the money added or taken out, and what holdings cost.

**Steps.** Files → Accounts → Commodities → Preview → Done. Preview, conflicts, the backup and Undo are the same as for a spreadsheet, and the mapping can be saved as a profile, so next month's import is one step.

### Files

- Choose one journal or several at once, e.g. one per year (`.ledger`, `.journal`, `.hledger`, `.j`, `.dat`). The files they `include` are read too.
- Several files are read as one journal. A file both given and included is read once. Transactions are sorted by date, keeping the files' order within a day, before balances, assertions and assignments are worked out.
- Reading is lenient: a transaction that can't be read, or doesn't balance, is reported with its file and line and left out; the rest is imported.
- In the app, the files you choose can be read, but files they include from the same folder may not be (the app's sandbox). They're listed, with **Choose the Journal's Folder…** to let the app read them.

### What's read

| | Supported |
| --- | --- |
| Dates | `2024-01-31`, `2024/01/31`, `2024.01.31`; `1/31` after `year 2024` (or `Y2024`). A secondary date (`2024-01-31=2024-02-02`) is ignored. |
| Transactions | Status `*` or `!`, a `(code)`, the description, a `; comment`. |
| Postings | An account name (single spaces allowed), then two spaces or a tab, then the amount. One posting may leave its amount out: it gets what balances the transaction, one posting per commodity if needed. |
| Amounts | The commodity before or after, with or without a space: `€5`, `5 EUR`, `-5.00 EUR`, `EUR -5`, `-€5`, `€-5`; quoted commodities (`"VWCE.MI"`, `"BTC-2"`); thousands separators. |
| Decimal comma | From `decimal-mark ,`, or per commodity from a format (`commodity 1.000,00 EUR`, a `format` line, `D 1.000,00 EUR`). Otherwise a number shows its own mark (`1.234,56`, `12,5`), and one that could be either (`1.000`) is read the way the file's other numbers are. |
| Prices | `@ unit price`, `@@ total price`, lot prices `{unit}`, `{{total}}`, `{=fixed}` (lot dates `[…]` and notes `(…)` are ignored). A posting with a lot price balances at it, as in ledger. Two commodities exchanged without a price get one inferred: the first posting's commodity is priced in the other. |
| Balance assertions | `= 100 EUR`, `== 100 EUR` (nothing else in the account), `=* 100 EUR` (with subaccounts), `= 0` (nothing at all). They're checked in date order across all files; one that fails is a warning, and the transaction is still imported. |
| Balance assignments | A posting with only `= 100 EUR` gets the amount that makes the balance 100 EUR. |
| Comments | Lines starting with `;` `#` `*` `%` `|`, `;` comments at the end of lines, `comment` … `end comment` (and `test` … `end test`). Tags in comments are ignored. |
| Virtual postings | `(Account)` doesn't have to balance and is **left out** of the import. `[Account]` must balance with the other bracketed postings and is **imported** like a real posting. |
| `include` | A path relative to the including file, with wildcards: `include 2024/*.journal`, `include **/*.journal`, `?`, `[…]`. A cycle is reported, and each file is read once. |
| Directives | `P DATE COMMODITY PRICE` (a time after the date is ignored), `commodity`, `account` (hledger's `type:` tags too), `alias OLD = NEW` (the account and its subaccounts) and `alias /REGEX/ = NEW`, `end aliases`, `apply account` … `end apply account`, `D`, `year` / `Y`, `decimal-mark`. `alias`, `apply account`, `year`, `D` and `decimal-mark` last to the end of their file and apply to the files it includes after them. |
| Skipped, with a warning | Periodic (`~`) and automated (`=`) transactions, `define`, `tag`, `payee`, `assert`, `check`, `bucket` / `A`, timeclock lines and other directives. Value expressions in amounts (`(2 * 3 EUR)`) make their transaction an error. |

### Accounts

- **Only assets and liabilities count.** Accounts under `Assets` and `Liabilities` (and `Asset`, `Liability`, `Attività`, `Passività`, `Attivo`, `Passivo`, `Aktiva`, `Passiva`, `Actifs`, `Passifs`, `Activos`, `Pasivos`), or declared with hledger's `type: A`, `L` or `C`. The profile's `ledger.roots` replaces the list.
- **Each ledger account goes to a library account, with its subaccounts**, unless a subaccount is set otherwise. Or it's **ignored**: moving money to an ignored account counts as money taken out.
- **Grouping.** Accounts nothing is set for are grouped: an account with postings of its own, without subaccounts, or whose subaccounts are all parts of it (`Cash`, `Positions`, a commodity's name, …) is one library account with everything below it. So `Assets:Broker:Directa` with `:Cash` and `:VWCE` is one account, and `Assets:Bank` with `:Fineco` and `:Intesa` is two.
- **Matching.** A group is matched to a library account by name: its full name, its last two parts, its last part, or its last part inside one account's longer name (`Fineco` → “Conto Fineco”), except generic words such as `Wallet` or `Checking`. Otherwise a new account is proposed, named after the last part (with the part before it when that one is generic: “Crypto Wallet”), opened on its first posting, in its most used currency, of a kind guessed from what it is and holds:
  - liabilities: a mortgage, loan or credit card by name, else a loan;
  - holding commodities that aren't currencies: crypto, metals, a pension fund by name, else brokerage;
  - otherwise by name, e.g. savings, else a current account (`cash`).
- **Returns.** Income and expense accounts are either returns or money in or out. Returns are income from the investments themselves (dividends, interest, capital gains, staking, rewards, coupons: found by name, in English and Italian) and their costs (fees and commissions). Salary, spending and everything else is money in or out. Mark accounts either way in the Accounts step, or in the profile's `ledger.returns` and `ledger.flows`.

### Commodities

- **Currencies** (ISO codes and symbols such as `€`, `$`, `£`, `CHF`) are cash in that currency. Amounts without a commodity (and no `D`) are in the library's base currency.
- **Other commodities are instruments**, matched to the library's by ID, ticker, price-source symbol, ISIN or name, with or without an exchange suffix (`VWCE.MI` matches `vwce`); `XAU` and `GOLD` match a gold instrument priced by gold-api. Otherwise a new instrument is proposed:
  - known crypto tickers (`BTC`, `ETH`, …): crypto, priced by CoinGecko with the ticker as its symbol;
  - tickers with an exchange suffix (`VWCE.MI`, `SWDA.L`): priced by Yahoo; an ETF for common ETF tickers, else a stock;
  - `XAU`, `GOLD`, `ORO`, `XAG`, …: a metal priced by gold-api, in troy ounces for `XAU`-style codes and grams otherwise;
  - anything else: “other”, priced by the journal's `P` directives or by hand.
- A commodity can be ignored.

### Valuations

- One per library account at each **month end** (by default), **quarter end**, or **date with a posting**, from the account's first posting to the end of the period with the journal's last transaction, and never after today.
- An account holding only currencies gets a `balance` (other currencies converted at the journal's `P` rates). One holding instruments gets `positions` plus `cash`.
- **Purchase cost** (`costBasis`) is the average cost: a purchase adds what it cost (`@`, `@@`, `{}` or inferred), a sale reduces the cost pro rata, and selling everything starts over. A quantity received as a return (a staking reward) costs its market value then; one received otherwise without a cost (an opening balance) makes the cost unknown until the position is sold.
- **Debts** are negative, as in the journal.
- **Closing.** When an account's balance goes to zero and stays there for at least 45 days before the journal ends, its last valuation is on that day, and closing the account then is proposed. (A card paid off last week isn't closed.)

### Flows

Each valuation's `flow` is the money added or taken out since the account's previous valuation, in the account's currency ([PROGRESS.md](PROGRESS.md#data-this-needs-from-day-one)). For each transaction touching an account, the other side decides:

| The other side is | Flow? | Example |
| --- | --- | --- |
| The same library account | No | Buying VWCE with the broker's cash |
| Another tracked account | Yes, both ways | Moving 1,000 from the bank to the broker: −1,000 and +1,000 |
| An ignored account | Yes | Lending money out |
| Income, expenses, equity | Yes | Salary, spending, opening balances |
| A returns account | No | A dividend, interest, a fee, a capital gain, staking |

- Commodities are valued at their cost (`@`, `@@`, `{}`), else at the latest `P` price on or before the day, and currencies converted at the journal's `P` rates (direct, inverse, or through another currency). When a needed value is missing, the flow is left unknown (`flow` absent) and a note says which posting.
- An account's first valuation counts everything before it as money added, as the check-in does.
- When a transaction touches several tracked accounts and a returns account, the returns go to the first account they're paid into.

### Prices

- `P` directives become price records (source `ledger`) for commodities that are instruments, and FX records for pairs of currencies (`P 2024-01-31 USD 0.92 EUR`: 1 USD = 0.92 EUR).
- Prices paid with `@` or `@@` become price records on the transaction's day, unless a `P` directive gives that day's price. The option `transactionPrices: false` leaves them out.
- Valuations are written with source `ledger` too.

### Importing again

Everything goes through the preview: records identical to the library's are left alone, missing values (such as a flow) are filled in, and different ones follow the conflict policy. So importing the journal again next month only adds the new months.

### Ledger profiles

A ledger profile has `layout: "ledger"` and a `ledger` section. Ledger accounts (each with its subaccounts) and commodities are remembered in `matches`:

```json
{
  "id": "journal",
  "layout": "ledger",
  "ledger": {
    "frequency": "month",
    "ignore": ["Assets:Receivables"],
    "returns": ["Expenses:Fees", "Income:Dividends", "Income:Interest"]
  },
  "matches": {
    "accounts": { "Assets:Bank:Fineco": "conto-fineco", "Assets:Broker:Directa": "directa" },
    "instruments": { "BTC": "btc", "VWCE.MI": "vwce" }
  },
  "name": "My journal",
  "onConflict": "keep"
}
```

| Field | Meaning |
| --- | --- |
| `matches.accounts` | A ledger account, with its subaccounts, → a library account. The nearest setting to an account wins. |
| `matches.instruments` | A commodity → an instrument. |
| `ledger.roots` | The accounts that count toward net worth. Left out: assets and liabilities, as above. |
| `ledger.ignore` | Ledger accounts left out, with their subaccounts. |
| `ledger.returns`, `ledger.flows` | Income and expense accounts (with their subaccounts) that are returns, or money in or out, whatever their names say. |
| `ledger.ignoreCommodities` | Commodities left out. |
| `ledger.frequency` | `month` (the default), `quarter` or `activity`. |
| `ledger.transactionPrices` | `false` to leave `@` prices out. |
| `onConflict` | As for spreadsheets. |

Saving writes out every account and instrument the import used and the returns accounts found by name, so the mapping stays the same when the app's guesses change.

### Not supported

Value expressions, periodic and automated transactions, budgets, timeclock and timedot files, CSV files through `include`, choosing lots when selling (the cost is always the average), posting dates in comments (`; date:`), and `--options` inside journals.

## Where it runs

- **Engine.** The `Importer` module, in pure Swift. It reads bytes and a `Library` and returns results; the app and the CLI back up and write the files it reports as changed. It's tested on Linux against a folder of sample files (`Tests/ImporterTests/Samples/`): Italian Excel CSVs in Windows-1252, US-style exports, Numbers exports, title and totals rows, month-only dates, Excel serial dates, long files, quantities with prices, debts written as positive amounts, broken rows.
  - `ImportSession(data:)` reads a file and proposes a mapping, or `ImportSession(data:profile:)` uses a saved one. The session holds the mapping as an `ImportProfile`, with helpers to map a column, pick the date column, remember a match and settle an ambiguity.
  - `session.preview(against:)` returns an `ImportPreview`: every record with its status, cell errors, issues, ambiguities, name matches, and the proposed accounts, instruments and account changes.
  - `preview.apply(to:)` returns an `ImportResult`: the new library and the month files, accounts and instruments that changed.
  - `session.makeProfile(id:name:library:)` saves the mapping with everything detected written out.
  - Journals: `LedgerReader.read(_:files:)` reads journal files and their includes through a `LedgerFileProvider` (`LocalLedgerFiles`, or the app's, which reads only what it was given access to) into a `LedgerJournal`: balanced transactions, prices, and diagnostics with file and line. `LedgerImportSession(journal:profile:)` holds the mapping as a ledger `ImportProfile`, with helpers to map, ignore or reset an account or commodity and mark returns; `preview(against:until:)` returns a `LedgerImportPreview`: the account and commodity rows, notes, and an `ImportPreview` that applies like any other. `makeProfile(id:name:from:library:)` saves the mapping. Tested with made-up journals in `Tests/ImporterTests/Samples/ledger/`.
- **App.** The same SwiftUI flow on Mac and iPhone. The Mac, with its big table, is the comfortable place to build a profile. On the iPhone, you can open a CSV from Files and import it with a saved profile. Journals (one or several files, chosen or dropped together) go through Files, Accounts, Commodities, Preview and Done; on the iPhone, with a saved ledger profile.
- **CLI.** `retire import <file>` previews without writing (the default, `--dry-run`): the detected settings, what each column becomes, the formats to confirm, notes, proposed accounts and closings, a summary with sample records and conflicts, and the cells that can't be read. `--save-profile <id>` saves the proposed mapping as `imports/<id>.json` to edit and reuse with `--profile <id>`; options such as `--date-format`, `--decimal`, `--delimiter` and `--liability-sign` override what was detected. `--apply` backs up the files that change to `backups/<timestamp>-import/` and writes them; it refuses while formats are still guesses (unless `--accept-guesses`). Non-interactively, new accounts and instruments and closings are only made with `--accept-new-accounts`, `--accept-new-instruments` and `--accept-closings` (their records are left out otherwise), and conflicts follow `--on-conflict keep|overwrite` (undecided ones keep the library's values). `retire import --undo` undoes the latest import not undone yet, leaving later edits in place and listing them, after copying the current files to `backups/<timestamp>-undo-import/`.
- **CLI, journals.** `retire import ledger <files…>` previews the journals (a dry run by default): the files read and their problems, where each ledger account and commodity goes, returns accounts, proposals, closings, and the records with their flows. `--profile <id>` reads them with a saved ledger profile and `--save-profile <id>` saves the mapping; `--frequency month|quarter|activity`, `--until <date>` (default today) and `--no-transaction-prices` change what's written. `--apply` writes with the same backup, accept flags and `--on-conflict` (or `--policy`) as a spreadsheet, and `retire import --undo` undoes it. `retire import <file>` is `retire import csv <file>`.
