# Importer

Imports any spreadsheet or export by mapping its columns to what the library stores. It handles whatever date and number formats the file uses, and a mapping can be saved and reused, so the next file of the same shape imports in one step.

It also imports a broker's transactions as trades (see [Broker transactions](#broker-transactions)).

## Steps

1. **Open.** Pick a CSV or TSV file.
2. **Detect.** The importer guesses the encoding, the delimiter, the header row, and the number and date formats. Every guess can be overridden.
3. **Map.** Say what each column is (see [Layouts](#layouts) and [Targets](#targets)). For a broker's transactions, also say what the file's words for its transactions are ([Types](#types)).
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
- **Trades:** one row per trade, a broker's transactions export. Each column is a field of the trade. See [Broker transactions](#broker-transactions).

  ```
  Data operazione;Tipo operazione;ISIN;Quantità;Prezzo;Importo euro;Commissioni
  12/01/2026;Acquisto;IE00BK5BQT80;15;102,30;-1.539,50;5,00
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

When there's no profile yet, the importer proposes a mapping from the headers and the values: a column of dates holds the dates; number columns become balances, or quantities, prices, cash, purchase costs or FX rates when the header says so (`BTC (qtà)`, `Prezzo VWCE`, `EUR/USD`); text, percentage and total columns are ignored. The layout is long when a text column's header names accounts or instruments, and trades when the file looks like a broker's transactions ([Detecting a transactions file](#detecting-a-transactions-file)).

Buys, sells and the rest of a broker's transactions aren't a target: they're read in the trades layout, as the trades of an account that records them ([Broker transactions](#broker-transactions)).

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
- An account whose values stop before the file's last date is proposed as closed, on the day after its last value. Trailing zeros don't count as values; a cell that couldn't be read does. It isn't proposed when the library has later values for it. A closing is made only when you turn it on (on the command line, with `--accept-closings`): an account updated less often than the file, such as a quarterly pension in a monthly sheet, stops early without having closed.
- An account with values from before its `opened` date is proposed to open on the first of them.
- New accounts, new instruments and these changes are applied unless you reject them. A rejected account's or instrument's records are left out.

## Preview, conflicts and undo

- **Preview.** Cells that can't be parsed are highlighted with the reason, e.g. "not a date in dd/MM/yyyy". You can fix the format, exclude the rows, or cancel.
- **Records already in the library** are matched by key: account + date, instrument + date, currency pair + date, or for a trade account + date + ID (a stable ID made from the row: [Importing again](#importing-again)).
  - An identical record is left alone. Only the values the file has are compared: a flow or a note in the library stays.
  - A record the library has without some of the file's values, such as a purchase cost, is *updated*: the missing values are filled in, and nothing in the library changes.
  - A record with a different value follows the policy you choose: overwrite, keep the existing value, or decide one by one. Conflicts still undecided when you import are kept. Switching a valuation between a balance and positions is a conflict too.
  - Importing the same file twice therefore changes nothing.
- **Flows after inserted values.** A valuation's flow is measured from the one before it. When the import adds a valuation before one the library already has (a month between two check-ins), or changes the one before it, that later valuation's flow is worked out again if it was automatic (the default for the account's kind, as a check-in fills it in), and kept if it was typed, as when a value is added in the app ([UI.md](UI.md#adding-history)). The app's Preview says how many, and `retire import --apply` lists them. They're written, backed up and undone with the import.
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
| `defaults.amountSign` | Trades layout: how amounts are signed: `auto` (the default), `fromType` or `asWritten`. See [Signs](#signs). |
| `columns[].format` | Overrides of `defaults` for one column: `date`, `number`, `empty`, `liabilitySign`, `amountSign`. |
| `columns[].field` | Long layout: what the column holds for each row's record: `date`, `account`, `instrument`, `value`, `currency`, `base`, `quote` or `ignore`. Trades layout: `date`, `type`, `account`, `instrument` (several columns can), `quantity`, `price`, `currency`, `amount`, `gross`, `fees`, `tax`, `ratio`, `note` or `ignore` ([Columns](#columns)). |
| `target` | Long layout: what each row becomes (`balance`, `quantity`, `costBasis`, `cash`, `price` or `fx`). A value column can set its own `target`, so one row can hold a quantity, a price and a purchase cost. |
| `constants` | Long layout: fields that are the same for every row: `account`, `instrument`, `currency`, `base`, `quote`. Wide columns that leave these out use them too. Trades layout: `account`. |
| `tradeTypes` | Trades layout: the file's type words, as written, → trade types, or `ignore` to leave their rows out. Matched exactly, then ignoring case and accents. See [Types](#types). |
| `matches` | Names found in files matched to IDs, remembered from earlier imports: `{ "accounts": { "Fineco": "conto-fineco" }, "instruments": { … } }`. |
| `onConflict` | `ask` (the default), `overwrite` or `keep`. |

A profile with a layout this version doesn't know, such as `ledger` (a ledger-cli or hledger journal's profile, written by an earlier version that imported journals), is kept as it is but not offered, and `retire validate` warns about it.

## Broker transactions

A broker's transactions export (Directa's or Fineco's movements, Degiro's transactions, an IBKR flex query) is read in the **trades layout**: each row is one trade of an account that records trades ([TRADES.md](TRADES.md)), a buy, a sell, a dividend, a fee, a deposit. The account's holdings, average cost, cash and realised gains then come from them.

**Steps.** File, Format, Columns, **Types**, Accounts, Preview, Done. Types maps the file's words for its transactions to trade types. Everything else is as for any spreadsheet: the preview shows the trades like other records, conflicts follow the policy, and Done has Undo.

### Detecting a transactions file

Without a profile, a file is read as trades when it has a quantity or price column and either a column of types (a text column whose values are mostly trade types in the usual words, at least half and two different types, or whose header names types: `Tipo operazione`, `Operazione`, `Type`, `Buy/Sell`) or a quantity column with negative values next to a price column (Degiro's sells). Its columns are proposed by their headers, with camel case spaced out (`NetCash` → net cash): the first date column (a second one, the value date, is ignored), the type column, instruments, quantities, prices, the currency, the net amount, the gross value, fees, tax, notes and an account column. Each field is used once, by the column whose header says it most plainly (`Netto`, `Net cash` over `Importo`, `Amount`); values in another currency (`Local value`) and exchange rates are ignored. Every choice can be changed in Columns, or with `--layout trades` on the command line.

### Columns

| Field | What it holds |
| --- | --- |
| `date` | The trade date. |
| `type` | The trade's type in the file's words: `Acquisto`, `Compravendita vendita`, `Dividend`. See [Types](#types). Without a type column, a positive quantity is a buy and a negative one a sell. |
| `account` | The account's name. Without an account column, every row is the account the profile's `constants.account` names (*Account of every row* in Columns; `--account` on the command line). |
| `instrument` | Its name, ticker or ISIN. Several columns can hold it (e.g. `Titolo`, `Ticker`, `ISIN`); they're tried in order. |
| `quantity` | Units. The sign is dropped. |
| `price` | The price per unit. |
| `currency` | The price's currency. A currency marked in the price cell (`$230.50`) counts too. |
| `amount` | The cash the trade moved in the account's currency, **net** of fees and tax. |
| `gross` | The value before fees and tax: a sale's proceeds, a buy's quantity × price, a dividend before tax (`Controvalore`). Used when there's no amount: the amount is then gross − fees − tax, signed. |
| `fees`, `tax` | Commissions, and tax withheld or charged, in the account's currency. The sign is dropped. |
| `ratio` | A split's new units per old unit. |
| `note` | Free text for the trade's note (`Descrizione`). |
| `settlement` | Whether a buy, sell, fee or tax was [paid from or into another account](TRADES.md#paid-from-outside-the-account): `external`, `outside`, `esterno`, `yes`, `sì`, `x` or `1` for another account (a dealer's invoice paid from the bank); empty, `account`, `conto`, `no` or `0` for the account's own cash. Anything else leaves the row out, with an error. Ignored for other types. Never proposed: map it in Columns. Without the column, the profile's `constants.settlement` (`"external"`) applies to every row (`--settlement external` on the command line). |

Amount, gross, fees and tax are in the account's currency; a column whose mapping or header names another currency (`Total USD` for an account in euros) is flagged. A row with a cell that can't be read is left out whole, with the cell's error: one row is one trade.

### Types

The profile's `tradeTypes` maps the file's words to trade types, and is written out in full when the profile is saved. Words it doesn't have are read with the usual words, in Italian and English:

| Type | Usual words |
| --- | --- |
| `buy` | Acquisto, Compravendita acquisto, Acquisto titoli, Sottoscrizione, Buy, Bought, Purchase |
| `sell` | Vendita, Compravendita vendita, Vendita titoli, Sell, Sold, Sale |
| `dividend` | Dividendo, Dividendi, Cedola, Cedole, Distribuzione, Dividend, Coupon, Distribution |
| `interest` | Interessi, Interessi attivi, Interessi creditori, Interest |
| `fee` | Commissioni, Commissione, Spese, Fee, Fees, Commission |
| `tax` | Bollo, Imposta, Imposta di bollo, Imposte, Ritenuta, Tassa, Tasse, Tax, Taxes, Withholding tax, Tobin tax, FTT |
| `deposit` | Versamento, Bonifico in entrata, Deposit, Deposits, Deposits/Withdrawals |
| `withdrawal` | Prelievo, Prelevamento, Bonifico in uscita, Withdrawal, Withdrawals |
| `split` | Frazionamento, Raggruppamento, Split, Reverse split, Stock split |

- Words are compared ignoring case, accents and punctuation. A value is first compared whole; otherwise the usual words it contains count (`Broker Interest Received` is interest), as long as they point to one type, or to a charge on something else (`Ritenuta su dividendo`, `Dividend Tax`: a tax; `Commissioni su vendita`: a fee).
- **Nothing is guessed.** A value that matches nothing, or several types (`Acquisto/Vendita`, `Giroconto`, `Rimborso`), is flagged: its rows are left out, each with an error, until it's mapped in Types (or with `--type "Giroconto=deposit"`). Mapping it to `ignore` leaves its rows out on purpose, with a note.
- The Types step lists every value with its rows and where its type comes from (the profile, the usual words, or nothing), and the preview's notes say how signs were read.

### Signs

The library stores quantities, prices, fees and tax as positive numbers, and a trade's `amount` as its signed cash effect: negative for buys, fees, taxes and withdrawals ([TRADES.md](TRADES.md#trades-in-the-files)). Brokers write them every way, so:

- **Quantities, prices, fees and tax** are made positive, whatever the file writes (Directa and Degiro write sells as negative quantities, IBKR commissions as negative amounts); the type says the direction. The preview notes how many quantities were negative.
- **Amounts** (and gross values) follow the column's `amountSign`, in `defaults` or in the column's `format`:
  - `auto` (the default): a column with any negative amount writes signed amounts, and its signs are kept (Degiro's buys are negative, its sells positive); a column without one writes absolute values, and each amount's sign comes from its type (Fineco's `Controvalore`).
  - `fromType`: absolute values, whatever the signs.
  - `asWritten`: the file's signs, whatever they are.
  The preview notes which, for each amount column.
- In a file with signed amounts, a deposit or withdrawal goes by its sign: IBKR writes both as `Deposits/Withdrawals`, a negative one is a withdrawal. The preview notes how many.
- Without a type column, a negative quantity is a sell and a positive one a buy; without quantities, a negative signed amount is a buy.
- Zero is no value: a quantity or price of 0 is left out. Deposits, withdrawals, fees and taxes don't keep a row's quantity and price, and a split keeps only its ratio.

A row whose trade can't be applied (a buy without a price or an amount, a split without a ratio) is left out with the reason; smaller problems (a buy with a positive amount) are imported and pointed out by `retire validate`.

### Accounts and instruments

- **Account.** A name in the account column is matched like any account name, or the constant gives it. A new account is proposed recording trades (`"valuation": "trades"`), a brokerage account unless its instruments are all crypto or metals.
- **An account that doesn't record trades** gets a proposal to record them (*Record Conto Fineco's trades*), made only when you turn it on; on the command line only with `--accept-trades-mode`. Accepted, the account records trades from then on: its holdings and cash come from its trades, the positions of its valuations become checks, and a balance no longer counts (to keep past balances as cash, convert the account first: [TRADES.md](TRADES.md#converting-an-account), `retire trades convert`). Rejected, its trades are left out. Or choose another account.
- Trades from before the account opened propose to open it earlier. A transactions file never proposes closing an account.
- **Instruments** are read only for the types that have one (buys, sells, dividends, splits, transfers, openings): the columns are tried in order, each name matched to the library's instruments by name, ID, ticker, ISIN or a remembered match. A new instrument is named after the column that's neither an ISIN nor a ticker (`VANGUARD FTSE ALL-WORLD HIGH DIV`), with the ISIN and ticker of the others, and in the currency of its prices. Rows naming the same new instrument differently share it.
- A trade's `currency` is written only when the price's currency isn't the instrument's.

### Importing again

Each trade gets a **stable ID** (`TradeID.stable`): 8 base32 characters from a hash of its account, date, type, instrument, quantity, amount and price, and its position among the file's rows with all of these equal (two identical orders on one day stay two trades). Importing the same file again finds the same trades: identical ones are left alone, fees, tax or a note the library lacks are filled in, and different ones (a corrected fee) follow the conflict policy. A trade the library has with a note of its own keeps it. A row whose amount, price or quantity changed is another trade; the old one stays until you remove it.

### Profiles

The example library's `imports/directa-movimenti.json` reads Directa-like movements:

```json
{
  "columns": [
    { "field": "date", "header": "Data operazione" },
    { "field": "ignore", "header": "Data valuta" },
    { "field": "type", "header": "Tipo operazione" },
    { "field": "instrument", "header": "Ticker" },
    { "field": "instrument", "header": "ISIN" },
    { "field": "instrument", "header": "Titolo" },
    { "field": "quantity", "header": "Quantità" },
    { "field": "price", "header": "Prezzo" },
    { "field": "amount", "header": "Importo euro" },
    { "field": "fees", "header": "Commissioni" },
    { "field": "currency", "header": "Divisa" },
    { "field": "note", "header": "Descrizione" }
  ],
  "constants": { "account": "directa" },
  "defaults": { "date": { "pattern": "dd/MM/yyyy" }, "number": { "decimal": ",", "thousands": "." } },
  "file": { "delimiter": ";", "encoding": "utf-8", "headerRow": 5 },
  "id": "directa-movimenti",
  "layout": "trades",
  "matches": { "instruments": { "IE00BK5BQT80": "vwce", "VWCE": "vwce" } },
  "name": "Directa, movimenti",
  "onConflict": "ask",
  "tradeTypes": {
    "Acquisto": "buy",
    "Bonifico in entrata": "deposit",
    "Commissioni": "fee",
    "Dividendo": "dividend",
    "Giroconto": "ignore",
    "Imposta di bollo": "tax",
    "Ritenuta su dividendo": "tax",
    "Vendita": "sell"
  }
}
```

The fields are those of any profile ([Import profiles](#import-profiles)), with `tradeTypes` and the `amountSign` format.

### The sample exports

The importer is tested with made-up exports in the shapes of real ones (`Tests/ImporterTests/Samples/trades/`), end to end into the example library:

- **Directa-like** (`directa.csv`): title rows above the header, `;`, `1.234,56`, `dd/MM/yyyy`, UTF-8 with a byte-order mark; signed amounts net of fees, a sale as a negative quantity, a dividend and its tax on two rows, two identical buys on one day, and `Giroconto`, which isn't mapped.
- **Fineco-like** (`fineco.csv`): Windows-1252, `Compravendita acquisto` and `vendita`, absolute gross values (`Controvalore`) with fees and tax (`Ritenuta`) columns, a dividend with its per-share amount, stamp duty; no account column.
- **Degiro-like** (`degiro.csv`): English, `,`, `dd-MM-yyyy`; no type column (sells are negative quantities, buys negative amounts), a stock priced in dollars with the amount in euros at Degiro's rate, costs as negative amounts.
- **IBKR-like** (`ibkr.csv`): a flex query with camel-case headers, an account column, `BUY`/`SELL`, `Dividends`, `Withholding Tax`, `Broker Interest Received`, `Other Fees`, and `Deposits/Withdrawals` both ways.

## Where it runs

- **Engine.** The `Importer` module, in pure Swift. It reads bytes and a `Library` and returns results; the app and the CLI back up and write the files it reports as changed. It's tested on Linux against a folder of sample files (`Tests/ImporterTests/Samples/`): Italian Excel CSVs in Windows-1252, US-style exports, Numbers exports, title and totals rows, month-only dates, Excel serial dates, long files, quantities with prices, debts written as positive amounts (and columns that write them negative), broken rows.
  - `ImportSession(data:)` reads a file and proposes a mapping, or `ImportSession(data:profile:)` uses a saved one. The session holds the mapping as an `ImportProfile`, with helpers to map a column, pick the date column, remember a match and settle an ambiguity.
  - `session.preview(against:)` returns an `ImportPreview`: every record with its status, cell errors, issues, ambiguities, name matches, and the proposed accounts, instruments and account changes.
  - `preview.apply(to:)` returns an `ImportResult`: the new library and the month files, accounts and instruments that changed.
  - `session.makeProfile(id:name:library:)` saves the mapping with everything detected written out.
  - Broker transactions: the trades layout reads each row into a trade with a stable ID (`TradeID.stable`), keyed `ImportRecordKey.trade`. `ImportSession.looksLikeTransactions` tells a transactions file; `tradeTypeValues` lists the type column's values with the type each is read as (`TradeTypeValue`: from the profile, the usual words in `TradeTypeWords`, or unmapped), and `setTradeType(_:for:)` maps one. The preview carries them in `ImportPreview.tradeTypes`; proposals to make an account record trades are `AccountChangeProposal.Change.recordTrades`, and `ImportResult.tradesAccounts` and `tradesWritten` say what applying did. Tested with the made-up exports in `Tests/ImporterTests/Samples/trades/`.
- **App.** The same SwiftUI flow on Mac and iPhone. The Mac, with its big table, is the comfortable place to build a profile. On the iPhone, you can open a CSV from Files and import it with a saved profile. A broker's transactions add a Types step after Columns.
- **CLI.** `retire import <file>` previews without writing (the default, `--dry-run`): the detected settings, what each column becomes, the formats to confirm, notes, proposed accounts and closings, a summary with sample records and conflicts, and the cells that can't be read. `--save-profile <id>` saves the proposed mapping as `imports/<id>.json` to edit and reuse with `--profile <id>`; options such as `--date-format`, `--decimal`, `--delimiter` and `--liability-sign` override what was detected. `--apply` backs up the files that change to `backups/<timestamp>-import/` and writes them; it refuses while formats are still guesses (unless `--accept-guesses`). Non-interactively, new accounts and instruments and closings are only made with `--accept-new-accounts`, `--accept-new-instruments` and `--accept-closings` (their records are left out otherwise), and conflicts follow `--on-conflict keep|overwrite` (undecided ones keep the library's values). `retire import --undo` undoes the latest import not undone yet, leaving later edits in place and listing them, after copying the current files to `backups/<timestamp>-undo-import/`.
- **CLI, broker transactions.** `retire import <file>` reads a transactions file as trades, or with `--layout trades`; the report lists the file's type words with their trade types (**Types**) and notes on signs, and the trades among the records. `--account <id>` names the account of every row, `--type "<word>=<type>"` (repeatable) maps a word, or `--type "<word>=ignore"` leaves its rows out, and `--amount-sign auto|from-type|as-written` sets how amounts are signed. An account that doesn't record trades is switched only with `--accept-trades-mode`; otherwise its trades are left out. `--save-profile` writes the types too. JSON output adds `tradeTypes`, `summary.trades` and `result.tradesAccounts`.
- **CLI, trades.** `retire trades list <account> [--year] [--instrument] [--json]`, `add <account> --type … [--instrument --quantity --price --currency --amount --fees --tax --cost --ratio --note --id]`, `remove <account> <id>`, `summary <account> | --all [--year] [--json]` and `convert <account> --to trades|snapshots [--apply]` ([TRADES.md](TRADES.md)). `add` and `remove` write after a backup (`backups/<timestamp>-trades/`; `--dry-run` shows the effects), and `convert` previews unless you pass `--apply` (backups labelled `convert-to-trades` and `convert-to-snapshots`, as in the app).
