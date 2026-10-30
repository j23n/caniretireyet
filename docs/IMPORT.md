# Importer

Imports any spreadsheet or export by mapping its columns to what the library stores. It handles whatever date and number formats the file uses, and a mapping can be saved and reused, so the next file of the same shape imports in one step.

It also imports a broker's transactions as trades (see [Broker transactions](#broker-transactions)), and a bank's statement as a cash or savings account's values with money in and out (see [Bank statements](#bank-statements)).

## Steps

1. **Open.** Pick a CSV or TSV file, or several bank statements at once ([Several statements at once](#several-statements-at-once)).
2. **Detect.** The importer guesses the encoding, the delimiter, the header row, and the number and date formats. Every guess can be overridden.
3. **Map.** Say what each column is (see [Layouts](#layouts) and [Targets](#targets)). For a broker's transactions, also say what the file's words for its transactions are ([Types](#types)).
4. **Match.** Link names in the file to existing accounts and instruments, or create new ones.
5. **Preview.** Every parsed value is shown, problems are highlighted, and a summary lists what will be added, updated or left alone. Nothing is written yet. Bank statements are reviewed all together ([UI.md](UI.md#import-mac-first), "Review").
6. **Import.** Records are written to the monthly history files. The affected files are backed up first, so the import can be undone.
7. **Save the mapping** as an import profile for next time. Bank statements save theirs with the import ([Remembering banks and senders](#remembering-banks-and-senders)).

## Files

- **Formats:** CSV and TSV with any delimiter (`,` `;` tab `|`) and quoted fields. Numbers and Excel can export these.
- **Encodings:** UTF-8 (with or without BOM), UTF-16, and Windows-1252 / ISO-8859-1. Excel on Windows often exports Italian files in Windows-1252.
- **Rows:** a header row anywhere (with rows above it skipped), empty rows ignored, and footer rows such as "Totale" excluded by a rule you can edit or turn off (by default, rows starting with "Totale" or "Total").
- **Later:** reading `.xlsx` and `.numbers` files directly. For now, a file that isn't text (an `.xlsx` or `.numbers` spreadsheet, a PDF, or anything with NUL bytes outside UTF-16) isn't read: the error says to export it as CSV.

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
- **Statement:** one row per line of a bank statement of one cash or savings account. Each line is income, spending, a one-off, tax, a transfer between your accounts, interest, or left out. See [Bank statements](#bank-statements).

  ```
  Data operazione;Data valuta;Entrate;Uscite;Descrizione
  10/02/2026;10/02/2026;2.800,00;;Accredito stipendio ACME SRL
  ```

## Targets

Each value in a file can become one of these:

| Target | Needs | Stored as |
| --- | --- | --- |
| Account balance | account, date, amount | A valuation with `balance` |
| Quantity held | account, instrument, date, quantity | In an account that records trades, an opening, a buy or a sale ([Quantities in a trades account](#quantities-in-a-trades-account)); otherwise a position in a valuation |
| Purchase cost | account, instrument, date, amount | In an account that records trades, an opening's cost or a buy's amount; otherwise the position's `costBasis` |
| Cash in an investment account | account, date, amount | A valuation's `cash` |
| Saved | account, date, amount | What was saved into the account since its value before: the valuation's `saved` ([Saved](#saved)) |
| Price | instrument, date, price, currency | A price record |
| FX rate | currency pair, date, rate | An FX record |
| Ignore | — | — |

Each field a target needs can come from one of three places:

- **a column**, e.g. an "Account" column in a long file;
- **a constant**, e.g. "every row of this file is account Directa";
- **the column header**, in the wide layout: the column "Directa" means account `directa`. The header gives what the column and the constants leave out: the account of a balance or cash column, the instrument of a price column, and for a quantity or purchase cost, the instrument once the account is set. Headers are matched without their decorations, so "BTC (qtà)" means `btc`. A header the importer can't use this way is flagged rather than guessed.

When there's no profile yet, the importer proposes a mapping from the headers and the values: a column of dates holds the dates; number columns become balances, or quantities, prices, cash, what was saved, purchase costs or FX rates when the header says so (`BTC (qtà)`, `Prezzo VWCE`, `EUR/USD`, `Fondo pensione (versato)`); text, percentage and total columns are ignored. The layout is long when a text column's header names accounts or instruments, and trades when the file looks like a broker's transactions ([Detecting a transactions file](#detecting-a-transactions-file)).

Buys, sells and the rest of a broker's transactions aren't a target: they're read in the trades layout, as the trades of an account that records them ([Broker transactions](#broker-transactions)).

### Saved

A pension fund, TFR, property or other account asks what was saved into it ([PROGRESS.md](PROGRESS.md#data-this-needs-from-day-one)): its balance alone can't tell what was paid in from what it earned. A saved column says it, next to the account's balance column:

```
Data;Fondo pensione;Fondo pensione (versato)
31/03/2026;17.480,90;1.325,00
```

- Each amount is what was saved into the account since its value before, in the account's currency, and is stored as that valuation's `saved`. Money taken out is negative.
- It's kept only on an account that asks for one. Every other account's saved amount is worked out from its values and trades, so the column is left out for it.
- It needs a value of the account on its date, from the file or the library; one without is a cell error. It fills in a value's missing amount, and replaces one only together with an overwritten conflict.
- Without a saved column, an asking account's change in value counts as other, not as money saved ([PROGRESS.md](PROGRESS.md)).

### Quantities in a trades account

An account that records trades (brokerage, crypto and metals accounts do: [TRADES.md](TRADES.md)) gets its holdings from its trades, so a sheet of quantities imported into it becomes trades:

- **An opening** per position on the account's first date in the file, when nothing was held before it. Its cost is the file's purchase cost, else the position's value on the date (the latest price on or before it, in the account's currency, at the latest FX rate on or before it, direct or inverted).
- **Then a buy or a sale** for each change from what's held, on the row's date, at the latest price on or before it. A buy's amount is what the purchase cost says was paid: all of it when nothing was held, else its rise since the file's last row of the instrument.
- What's held comes from the account's trades up to the date, and those made for the file's earlier rows. An instrument a row doesn't mention is left as it is; a row that leaves the quantity unchanged makes no trade.
- An account that has never held cash (no cash or balance in its values or the file, no deposit, no sale into its cash) has its buys and sales paid from another account (`"settlement": "external"`).
- Trades get the conversion's readable IDs (`opening-vwce`, `buy-vwce`, `sell-vwce`), one per instrument and date, so importing the file again finds the same trades, and a trade the library has with the same key is compared like any record. A trade the library has with one of these keys, on a date and for an instrument the file gives, that the file no longer makes (the quantity no longer changes there, or changes the other way) is a conflict too: the file replaces it.
- **An account's trades are decided together**, because each is worked out from those before it: keeping one and taking the others would leave the account holding what neither the file nor the library says. When every conflict among them is overwritten (or there are none), all of them are applied, and the library's trades the file no longer makes are removed. Otherwise none of them are, new ones included, and all of the library's stay; the preview names each such account and how many of its trades are left out until its conflicts are overwritten (`tradesLeftOutUntilOverwritten`). In the app, deciding one of these conflicts decides the others.
- Prices are the library's and the file's: a price column in the same file counts, and wins on the same date.
- The cash column stays a valuation's `cash`, which anchors the account's cash. A purchase cost without a quantity on its date can't be read, since the account's values hold no positions.
- The preview notes how many openings, buys and sales were made, and the buys or sales without a price and the openings without a cost, whose amounts are unknown.

## Value formats

Every column has a format. The file sets the defaults, a column can override them, and the importer proposes a format by testing it against every value in the column.

**Numbers**

- **Separators:** the decimal separator is `.` or `,`. The thousands separator can be none, `.`, `,`, a space, a non-breaking space or `'`.
- **Currency markers** are stripped: `€ 1.234,56`, `EUR 1234.56` and `1,234.56 $` all work. A currency code found in the cell can also be used as the value's currency.
- **Negatives** can be written `-1`, `(1)` or `1-`.
- **Percentages** are supported.
- **Empty cells** are skipped by default (not read as zero). You can choose to read them as zero. In a transactions file a row is one trade, which an empty cell never leaves out: the trade is recorded without that value, and read as zero only an amount (net or gross) is 0, since zero is no quantity, price, fee, tax or ratio ([Signs](#signs)).
- **Ambiguous values** such as `1,234`: when a column could be read either way, the importer asks.

**Dates**

- **Patterns:** `yyyy-MM-dd`, `dd/MM/yyyy`, `MM/dd/yyyy`, `dd.MM.yyyy`, `d-MMM-yy`, and month names in English and Italian (`31 gen 2024`, `gennaio 2024`), or any custom pattern.
- **Month-only dates** such as `2024-01`, `01/2024` or `Jan 2024` become the last day of the month by default, or the first if you prefer.
- **Excel date serial numbers** (e.g. `45322`) are converted.
- **Date-times:** the time is dropped, using the time zone you choose.
- **Day or month first:** `dd/MM` and `MM/dd` are told apart as soon as any day in the column is above 12. If none is, the importer asks.
- **Plausible dates only:** a date before 1900, or more than a week after today, is a cell that can't be read ("after 2026-10-11, more than a week from today"), and its row is left out. It's most likely a typo (`31/01/2204`), which would otherwise become the file's last date.
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
- An unmatched name can create a new account or instrument. You confirm its kind and currency; the importer suggests them, e.g. from a currency code in the values. A new account with quantities, purchase costs or an investment account's cash records trades: a crypto or metals account when its instruments all are, else the kind its name says if that's brokerage, crypto, metals or a pension fund, else a brokerage account. One with only balances is the kind its name says, but a balance column named like a brokerage, crypto or metals account (`Broker`, `Crypto wallet`, `Oro`) is proposed as kind `other`, since those kinds record trades. A new account that records trades keeps them if you change its kind. A new instrument's kind comes with the asset class and unit that usually go with it, as in the instrument form: funds, ETFs and stocks are equity; a precious metal is gold, in grams, unless its name says silver, platinum or palladium; an exchange-traded commodity is gold only when its name says so; and changing the kind changes them.
- An account whose values stop before the file's last date is proposed as closed, on the day after its last value. Trailing zeros don't count as values; a cell that couldn't be read does. It isn't proposed when the library has later values for it. A closing is made only when you turn it on (on the command line, with `--accept-closings`): an account updated less often than the file, such as a quarterly pension in a monthly sheet, stops early without having closed.
- An account with values from before its `opened` date is proposed to open on the first of them.
- New accounts, new instruments and these changes are applied unless you reject them. A rejected account's or instrument's records are left out.

## Preview, conflicts and undo

- **Preview.** Cells that can't be parsed are highlighted with the reason, e.g. "not a date in dd/MM/yyyy". You can fix the format, exclude the rows, or cancel.
- **Records already in the library** are matched by key: account + date, instrument + date, currency pair + date, or for a trade account + date + ID (a stable ID made from the row: [Importing again](#importing-again)).
  - An identical record is left alone. Only the values the file has are compared: a saved amount or a note in the library stays.
  - A record the library has without some of the file's values, such as a purchase cost, is *updated*: the missing values are filled in, and nothing in the library changes.
  - A record with a different value follows the policy you choose: overwrite, keep the existing value, or decide one by one. Conflicts still undecided when you import are kept. Switching a valuation between a balance and positions (in an account that doesn't record trades) is a conflict too. The trades an account's quantities become are decided together ([Quantities in a trades account](#quantities-in-a-trades-account)).
  - Importing the same file twice therefore changes nothing.
- **Values after inserted ones.** What a valuation saved is worked out from the one before it, except on an account that asks for it (`Account.asksForSaved`), so an import that adds a valuation before one the library already has (a month between two check-ins), or changes the one before it, changes nothing stored in the later one: what it saved follows. Its money in and out stay as they are, without a note ([PROGRESS.md](PROGRESS.md#money-in-and-out)).
- **Undo.** Before writing, the files about to change are copied to `backups/<timestamp>-import/`, and after writing, the files as the import wrote them are recorded in the same backup. "Undo import" (and `retire import --undo`) puts back what the import changed and leaves later edits alone: a record you changed after the import keeps its new value, and a file you changed otherwise is left as it is. It lists what it left in place ([PLAN.md](PLAN.md#merging-saving-and-undo)).

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

Every field, with its default: [import-profile.schema.json](schema/import-profile.schema.json). Debts and signs: [Value formats](#value-formats) and [Signs](#signs).

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
- Zero is no value: a quantity, price, fee, tax or ratio of 0 is left out. Deposits, withdrawals, fees and taxes don't keep a row's quantity and price, and a split keeps only its ratio.

A row whose trade can't be applied (a buy without a price or an amount, a split without a ratio) is left out with the reason; smaller problems (a buy with a positive amount) are imported and pointed out by `retire validate`.

### Accounts and instruments

- **Account.** A name in the account column is matched like any account name, or the constant gives it. A new account is proposed recording trades, a brokerage account unless its instruments are all crypto or metals; those kinds record trades without saying so in the file.
- **An account of another kind that doesn't record trades** (cash, savings, a pension fund) gets a proposal to record them (*Record Conto Fineco's trades*), made only when you turn it on; on the command line only with `--accept-trades-mode`. Accepted, the account records trades from then on: its holdings and cash come from its trades, the positions of its valuations become checks, and a balance no longer counts. Rejected, its trades are left out. Or choose another account. A brokerage, crypto or metals account that doesn't record trades (its `valuation` says otherwise) isn't offered the switch: its trades are left out, and the preview says to remove its `valuation`.
- Trades from before the account opened propose to open it earlier. A transactions file never proposes closing an account.
- **Instruments** are read only for the types that have one (buys, sells, dividends, splits, transfers, openings): the columns are tried in order, each name matched to the library's instruments by name, ID, ticker, ISIN or a remembered match. A new instrument is named after the column that's neither an ISIN nor a ticker (`VANGUARD FTSE ALL-WORLD HIGH DIV`), with the ISIN and ticker of the others, and in the currency of its prices. Rows naming the same new instrument differently share it.
- A trade's `currency` is written only when the price's currency isn't the instrument's.

### Importing again

Each trade gets a **stable ID** (`TradeID.stable`): 8 base32 characters from a hash of its account, date, type, instrument, quantity, amount and price, and its position among the file's rows with all of these equal (two identical orders on one day stay two trades). Importing the same file again finds the same trades: identical ones are left alone, fees, tax or a note the library lacks are filled in, and different ones (a corrected fee) follow the conflict policy. A trade the library has with a note of its own keeps it. A row whose amount, price or quantity changed is another trade; the old one stays until you remove it. A deposit or withdrawal that isn't in the library by its ID is one the account already has when a trade of the same type and amount, not one of the file's own, is up to 4 days away, such as one a bank statement's line moved to the account recorded ([Moved to or from an account](#moved-to-or-from-an-account)): the row takes that trade's day and ID, so the money counts once. Each trade stands for one row, the nearest in date first.

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

The fields are those of any profile ([import-profile.schema.json](schema/import-profile.schema.json)), with `tradeTypes` and the `amountSign` format.

### The sample exports

The importer is tested with made-up exports in the shapes of real ones (`Tests/ImporterTests/Samples/trades/`), end to end into the example library:

- **Directa-like** (`directa.csv`): title rows above the header, `;`, `1.234,56`, `dd/MM/yyyy`, UTF-8 with a byte-order mark; signed amounts net of fees, a sale as a negative quantity, a dividend and its tax on two rows, two identical buys on one day, and `Giroconto`, which isn't mapped.
- **Fineco-like** (`fineco.csv`): Windows-1252, `Compravendita acquisto` and `vendita`, absolute gross values (`Controvalore`) with fees and tax (`Ritenuta`) columns, a dividend with its per-share amount, stamp duty; no account column.
- **Degiro-like** (`degiro.csv`): English, `,`, `dd-MM-yyyy`; no type column (sells are negative quantities, buys negative amounts), a stock priced in dollars with the amount in euros at Degiro's rate, costs as negative amounts.
- **IBKR-like** (`ibkr.csv`): a flex query with camel-case headers, an account column, `BUY`/`SELL`, `Dividends`, `Withholding Tax`, `Broker Interest Received`, `Other Fees`, and `Deposits/Withdrawals` both ways.

## Bank statements

A bank's statement export for one cash or savings account is read in the **statement layout**: each row is a line of the statement, and each line is classified as money in, money out or neither. The lines become the account's values, with the balance and money in and out ([PROGRESS.md](PROGRESS.md#money-in-and-out)). The import keeps the lines too ([Lines](#lines)), so a past month can be checked and corrected later.

### Lines

A cash, savings or tax-pot account's statement lines can be kept in the monthly history files (`lines`, Model's `BankLine`, [the schema](schema/history-month.schema.json)), so each one can be checked and changed later. A line keeps:

- its **account**, its **date** (the day the bank booked it) and its **amount**: money in positive, money out negative, in the account's currency. Each line keeps its own date, whatever check-ins the account has: check-ins are when balances are compared, not the shape of the data;
- the bank's **text**, its description and counterparty as the file writes them;
- what it **is** (`class`): income, spending, tax, interest, a one-off, money moved between your accounts (`transfer`, with the other account in `otherAccount` when it's known) or not counted (`ignore`). There are no spending categories ([PLAN.md](PLAN.md#non-goals)), and a line isn't split: a note says what a mixed line was;
- a **note**; whether it was **removed**, such as a line a bank's export has twice: it stays in the file, so importing the statement again doesn't bring it back, but counts in nothing; and whether what it is was **confirmed**, or is still the import's suggestion.

Lines are keyed by account, date and **ID**. An imported line's ID is made from its account, date, amount and text, and its position among the file's lines with all of these equal (`BankLineID.stable`), so importing the same file again finds the same lines and keeps what you changed. A line typed in gets a random ID. Loading points out a line of an account, or moved to an account, that doesn't exist.

**Importing** a statement writes its lines (`ImportPreview.lines`, `ImportResult.linesWritten`), also when the library's values are kept: a stretch that doesn't add up then shows the difference. A line whose class was chosen in the import, or remembered from an earlier one, is confirmed, except a purchase or a sale ([Moved to or from an account](#moved-to-or-from-an-account)): it stays a suggestion, so importing the file again asks for it again and finds the account it started or sold. So does an answer the import leaves out, such as money moved to a tax pot it can't follow. Any other class, from a rule, the usual words or a sender's history, is a suggestion, with the other account when the import knows it and it exists. Importing a file again, or another file with some of the same lines, finds the library's lines by their IDs:

- a **removed** line stays removed, whatever the import chooses for it: it counts in nothing, and isn't in the balance the lines lead to;
- a **confirmed** line keeps what it is, money moved to its other account included, unless the import chooses again;
- a line that is still a suggestion takes the import's new one; its note stays. A purchase or a sale that isn't answered again, such as one below the size the import asks about, becomes what the import suggests, usually spending, and no longer names the account; answering it again, or confirming it on its month's lines, keeps it moved.

**Between two values** (Tracker's `Library.lineStretches(of:)`, `LineStretch`) an account's lines are checked against its balances: the value before, plus every line that counts, has to be the value after. The difference is a line missing, one listed twice, or a balance typed wrong. Each stretch starts from the value before it, so a value corrected later carries into the next stretch. A stretch's **spent** is its money out less the tax in it, and what it **moved** is its transfers. Lines after the account's last value wait for the next one.

**After a line is changed** (`Library.countLines(of:)`), each value whose stretch adds up gets the sums of its lines, also a balance typed without money in and out, as a statement's import counts them ([Values](#values)), so the savings rate follows. A value without lines in its period keeps the money in and out it has: typed totals, or a check-in's. So does a value whose stretch doesn't add up, such as one whose money in and out were typed for a longer period than the lines cover, until it's fixed.

### Your months

The app shows each cash or savings account's and tax pot's money in and out up to each check-in (Tracker's `Library.moneyMonths(next:)`, `MoneyMonth`, `AccountMonth`): one row per account per check-in, newest first, with the check-in still to come on top. An account's month opens at its value before and holds its lines since then, through the check-in's date. It's **done** when its lines add up to the bank's balance on that date and every line is confirmed, or when its money in and out were typed without lines (**typed totals**), or when it has a balance alone. An account's **first month**, whose lines come before its first value, has no balance before to check them against: it's done once every line is confirmed. Otherwise it's not done yet, its lines wait for the bank's balance, or it's off by the difference. `moneyMonths(next:limit:)` builds only the newest check-ins when given a limit.

Each month opens at the balance before it, so changing a past month's balance or lines shows in the months after it (`Library.accountMonths(of:after:next:)`). Saving a line (`Library.save(_:)`) writes the money in and out of the account's values from its lines again ([Lines](#lines)). The bank's balance typed for a month (`Library.setBankBalance(_:of:on:)`) is the value on its date, and its lines count into it once they add up.

**Typed totals** (`Library.saveTypedTotals(of:on:balance:cameIn:spent:tax:)`) are the month's balance, what came in, what was spent and the tax paid, typed from the bank's app instead of a CSV: the value's `moneyIn`, `moneyOut` (spent and tax) and `tax`. What moved to and from your other accounts is the rest, so it isn't stored. A statement imported later replaces them.

**Checking a line** (Importer's `LineEdits.swift`): a rule for a line matches the start of its text up to the first word with a digit (`BankLine.suggestedPhrase`). The same choice can go to every line of the month with those words (`Library.lines(of:matching:after:through:)`) and be remembered as a rule in the profile that reads the account's statements (`Library.rememberStatementRule(_:other:for:account:)`), so the next statement suggests it.

### Detecting a statement

Without a profile, a file is read as a statement when it isn't a broker's transactions and has dates, a description or counterparty column (`Descrizione`, `Causale`, `Verwendungszweck`, `Description`, `Payee`, …), and either a signed amount column (`Importo`, `Betrag`, `Amount`) with money in and out, or columns for money in and out (`Entrate` and `Uscite`, `Avere` and `Dare`, `Haben` and `Soll`, `Credit` and `Debit`, `Paid in` and `Paid out`). It has no quantities or prices. A column whose header names accounts (`Account name`, or a bare `Name`) doesn't count as its description or counterparty. `--layout statement` reads any file this way, and a statement's `Name` column is then who was paid.

### Columns

| Field | What it holds |
| --- | --- |
| `date` | The booking date. A second date column (the value date) is ignored. |
| `amount` | The line's amount: + in, − out. |
| `credit`, `debit` | Instead of `amount`: money in and money out. The sign is dropped. |
| `description` | The bank's text. Several columns are joined. |
| `counterparty` | Who paid or was paid. It's read with the description. |
| `balance` | The account's balance after the line. Optional. |

The account is the profile's `constants.account` (`--account` on the command line): one file is one account, a cash or savings account of the library that doesn't record trades. A row without an amount is skipped. A row with a cell that can't be read is left out, with the cell's error.

### Classes

| Class | Counts as |
| --- | --- |
| `income` | Money in: pay, a pension, rent, a client's payment. |
| `spending` | Money out: shopping, rent, bills, and the payments of a credit card, a loan or a mortgage. Money in that is spending lowers money out: a refund, a friend's share of a bill, an insurance payout. It isn't income. |
| `oneOff` | The value's `oneOff`: money from outside that is neither income nor spending, such as an inheritance, a gift you keep or the sale of something you didn't track. |
| `tax` | Tax paid, such as a yearly income tax bill: money out, and the value's `tax`, so the savings rate takes it off what came in rather than counting it spent ([PROGRESS.md](PROGRESS.md#money-in-and-out)). A refund lowers both. |
| `transfer` | Neither: money moved between your accounts. |
| `interest` | A savings account's `interest`; a current account's money in. |
| `ignore` | Neither. It still counts in the balance. |

Money in that is spending is paid back, and any line that went out is money out, whatever its class. A period with more paid back than spent has no money out, and the rest counts as moved between your accounts.

Each line gets the class of the first of these that says one:

1. **Chosen for the line** (`ImportSession.setStatementClass(_:forRow:)`), for this file only; an answer that moves its money to or from an account is a transfer ([Moved to or from an account](#moved-to-or-from-an-account)). Else **remembered for the line** in the profile's `answers`: the same date and amount, and a text with the same words ([Remembering banks and senders](#remembering-banks-and-senders)).
2. **A rule** in the profile's `rules`: a phrase the line's text has as whole words, ignoring case, accents and punctuation. The longest phrase wins. A rule with an `account` makes its lines money moved to or from that account. `--class "Giroconto=transfer"` adds a rule (`--move "<words>=<account>"` one with an account), and saving the profile keeps the rules, so a correction made once holds for the next statement.
3. **A trade of another account** that moves the same amount within 4 days: a transfer. It's a deposit (a deposit of 500 is −500 on the statement), a withdrawal, or a buy, sale, fee or tax [paid from outside its account](TRADES.md#paid-from-outside-the-account). Each trade matches one line and each line one trade, the pairs nearest in date first.
4. **A line of another account's statement** imported with it ([Several statements at once](#several-statements-at-once)) that moves the same amount the other way within 4 days: a transfer.
5. **Another account's name** in the text, or its institution when it isn't this account's bank: a transfer. Money out to a credit card, a loan or a mortgage is spending, since paying a debt is (money in from one, such as a loan paid out, is a transfer). Names of four letters or fewer, and names made only of words any account could have (`Conto corrente`, `Savings`), don't count.
6. **The usual words:** `Giroconto`, `Girofondi`, `Umbuchung`, `Übertrag` or `Internal transfer` for a transfer, and `Finanzamt`, `Agenzia delle Entrate`, `F24`, `Einkommensteuer`, `HMRC`, `Income tax` or `Self assessment` for tax. For money in only, `Stipendio`, `Emolumenti`, `Pensione`, `Gehalt`, `Lohn`, `Rente`, `Salary`, `Payroll` or `Pension` for income, `Interessi`, `Zinsen` or `Interest` for interest, and `Rimborso`, `Storno`, `Erstattung`, `Refund` or `Reversal` for spending paid back.
7. **Paid before** (money in only): the file paid its sender at least as much in the 90 days before. Spending paid back.
8. **The sign:** spending, which money in lowers.

Then a sender whose money in was classified by its sign in step 8, with similar amounts (within a quarter of their median) in at least 3 of the file's months, is income: those lines are, and any smaller ones from the sender (pay before a raise, a partial month). A larger line from the same sender, such as a bonus or a severance, keeps the class its sign gave it and needs an answer, whatever its size. Its **sender** is who paid or was paid: the counterparty column, else the description's first words that aren't the bank's own (`Bonifico`, `SEPA`, `Überweisung`, a company's `GmbH` or `Srl`, a month), as the text writes them (`StatementLine.sender`). A payment processor's line (PayPal, SumUp, Zettle, Klarna, Stripe, Square's `SQ`) names its merchant in the word right after a `*`: `PayPal Europe *Kleinanzeigen Fahrrad` is Kleinanzeigen's. A rule with the sender's words classifies every line from them, so income is marked once per sender.

Money in classified by its sign that is more than a typical month's spending in the file (the median of its months' money out) **needs an answer** (`StatementLine.needsAnswer`). Money out classified by its sign also needs one when it's more than a typical month's spending without the line itself: the median of the file's months' money out without it (a month whose only spending it is doesn't count), and of the money out of the account's last 12 values before the file. Either way the answer is one of income, spending, a one-off, tax, or moved to or from an account, a purchase you keep or a sale ([Moved to or from an account](#moved-to-or-from-an-account)). Until it has one it counts as spending.

Last, money that **passed through** the account needs no answer: a line in and a line out of the same amount within 4 days, both classified by their sign and at least one needing an answer, such as savings moved to a broker by way of the current account. Both are transfers (`StatementLine.Source.passThrough`). The pairs nearest in date come first, each line once. A class chosen for either line, or a rule, takes it out of the pair.

Nothing is left out unclassified, so a statement imports without any rules; the classes are there to be corrected. Why money in defaults to spending paid back: what you saved comes from the balances, so a wrong class never changes it. A missed income lowers what came in and what you spent by the same amount, and a large one is asked about, while counting every refund as income would raise both with nothing to show it. The preview lists each line with its class and why (`ImportPreview.statementLines`).

### Moved to or from an account

A line can be money moved to or from one of your accounts rather than money spent or earned. Answered for this file only (`ImportSession.setStatementAsset(_:forRow:)`, which replaces a class chosen for the line, and the other way around), or for every line with a phrase by a rule with an `account` (`setStatementRule(movingTo:for:)`, `--move`), such a line is a transfer, and the import records the other side where the other account has no statement of its own (`StatementLine.asset`, `assetAccount`):

- **An account of the library** (`StatementAsset.moved(_:)`): another account, not closed by the line's day (`Library.canMoveFromStatement(_:of:on:)`). The line is a transfer. A cash or savings account or a **tax pot** (`AccountKind.taxPot`), valued by its balance and in the statement's currency, follows from the money moved when its own statement isn't imported with this one (`StatementBatchContext.accounts`): at each of the file's values the moves count in, it gets a value whose balance is its value before's plus the money moved since. A value it already has between moves, such as a check-in, holds the moves before it. A tax pot's values have no money in or out (so all of it is moved, `Valuator.moved(_:previous:)`, which the savings rate counts as tax). Another account's leave money in and out unknown, its interest too, so its own statement can still correct them. A pot with no value before the first move starts worth 0 the day before it, a value that isn't counted, and is opened earlier if it needs to be; another account with no value before the first move gets none, and its own statement records its side. An account that **records trades** ([TRADES.md](TRADES.md)), in the statement's currency and opened by the line's day, gets a deposit on the line's day (a withdrawal for money in), of the line's amount, when the line counts in one of the file's values. So the money counts as saved in the month it left the bank, whether or not the broker's own trades have it yet, and isn't spent. The deposit has the ID the broker's own file gives the same deposit on the same day (`TradeID.stable`), and a deposit or withdrawal of the same amount the account already has within 4 days is the line's, so nothing is added: each stands for one line, the nearest in date first. Importing the broker's file later finds it too ([Importing again](#importing-again)). Any other account records its side itself. Importing the file again finds the same values.

- **A purchase you keep** (`StatementAsset.purchase(name:kind:)`): money out for a car, a home or another thing worth something, of kind `belongings`, `property` or `other`. It starts a new account with that name (`ImportPreview.newAccounts`, with `statementRow`), in the statement's currency, opened and worth 0 the day before the line. On the line's day it's worth the line's amount, which is what it saved (its `saved`, for `property` and `other`, which ask for it). Like a sale, it needs no value of the file: it's recorded on the line's own day even when the file makes no values, such as the first statement of an account without values and without balances. Its first value is 0, so the amount is saved rather than what it already held, and the savings rate counts it as saved, not spent ([PROGRESS.md](PROGRESS.md#money-in-and-out)). Importing the file again with the same answer finds the account it started (same name, kind, currency and opening day) rather than proposing another; an older account with the same name doesn't count.
- **A sale** (`StatementAsset.sale(_:)`): money in for one of your accounts, valued by its balance, that isn't a cash or savings account or a debt (`Account.canBeSoldFromStatement`), in the statement's currency, opened by the line's day, with no values after the line. It's worth 0 on the line's day, with the amount as what it took out (its `saved`, for an account that asks for it), and closes the day after (an accepted `AccountChangeProposal`, with `statementRow`). Importing the file again with the same answer finds the same sale: an account closed the day after a 0 value on the line's day, its only value from the line on. What it sold for, less its last value, is a gain or loss as its kind counts change: market for property and other, saved or spent for belongings, whose change is saved. The account sold can also be one a purchase in the same file starts, on or before the sale's day: its proposed account is valued as for any sale and closes the day after. Bought and sold on one day, it's worth 0 that day, with what the two lines moved as what it saved. Until the statement's account has a value after the line, net worth leaves out what moved: between a sale and the current account's next value it reads low by what the account sold for. Across several statements, a line of any file can sell what another file's purchase starts ([Several statements at once](#several-statements-at-once)).

An answer that doesn't fit is left out, and the preview says so (`ImportIssue.Kind.statementMoveLeftOut` for a move: this account, a closed one, a tax pot in another currency, or a move into a pot on a line that counts in no value; `statementAssetLeftOut` for the others): a purchase that isn't money out or isn't of one of those kinds, a sale that isn't money in, or of an account that can't be sold this way, or sold twice, or of a new account no purchase on or before its day starts, in the file or in a file applied before it. A move into a pot is also left out on a line that counts in no value whose money in and out the file covers, such as one after the file's last value, or on the first statement of an account without values. A line whose answer doesn't fit is classified as if it had none, and one whose rule's move doesn't fit (an account that isn't in the library, or one of those above) stays a transfer, as its rule says; one that counts in no value stays a transfer, which counts in nothing either way. A tax pot's own statement records no tax: a bill paid from the pot is its money out.

### Values

- **The days the file covers** are taken to be whole months: from the first day of the first line's month to the last day of the last line's month, or to today if that month isn't over. The preview notes them. A bank's export of the last 90 days, or one made in the middle of a month, covers less: `--from` and `--through` (`ImportSession.statementFrom`, `statementThrough`) give its first and last days; the last can't be after today. A line outside them is a problem, and nothing is imported. Imported from a check-in ([UI.md](UI.md#check-in)), a file whose last line is in the check-in's month, on or before its date, covers through that date (`ImportSession.statementCheckIn`), unless its last day is given. It's written as any import is.
- **Where.** At each of the account's values in those days, at the end of each month without one, and on the `--through` day when it's given, so the next file follows on from it. Lines after the last value count toward the next one, and the preview notes how many. Before the library's first check-in (its earliest value), the month ends that get a value can be fewer (`ImportSession.statementCheckIns`, `StatementCheckIns`): every month end (the default), every quarter end, or none, when past statements are added in bulk. A difference then shows within a quarter, with a third of the checking, or only for the whole stretch. The file's last month end always gets one, so the next file follows on from it: with none, and no value of the account in the file's days, the lines are one stretch up to it. Month ends from the first check-in on always get a value. A month that isn't over gets none: its lines count toward the next check-in.
- **The balance** comes from the balance column: the balance at the end of each day that has one, plus the lines after it. A day's lines can be listed in any order, so its end is the balance that follows from the day before and the day's lines; a day where none does is noted. Without the column, the balance is the balance before the file plus the lines. That's the account's value on the day before the file's first day, or `--opening-balance` (`ImportSession.statementOpeningBalance`). With neither, nothing is imported, and the preview says why.
- **Money in and out** (and one-offs, tax and a savings account's interest) are the sums of the lines since the value before. The first value gets them only when the file covers its whole period: the account's value before is on the day before the file's first day, or the balance column's first balance follows on from it. A balance before the file's first line (from the column or `--opening-balance`) that differs from the value before means it doesn't. Otherwise the preview notes where money in and out start. An account's first value has none, as at a check-in.
- **What it saved** isn't stored: it's worked out as for any value of the kind, the change, less a savings account's interest. So what moved between your accounts is the transfers ([PROGRESS.md](PROGRESS.md#money-in-and-out)).
- **Values already in the library** are compared like any record ([Preview, conflicts and undo](#preview-conflicts-and-undo)): money in and out they lack are filled in. When the value's balance agrees with the file's, the money in and out (and interest, the one-off and tax) counted from the lines replace the library's, since the lines say what they were: a check-in's money out left as suggested, with a transfer in it, or an earlier import of the file before a line's class was changed. When the balance differs, the value is a conflict and follows the conflict policy. Importing the same file again with the same classes changes nothing. When the file's new values come before a later value with money in and out, the preview notes it: that value's money in and out still cover the months the file now has, so they count twice until it's corrected.

### Several statements at once

Several files can be imported together (`StatementBatch`), such as every account's statements for a year. Each file is one account's statement, read as above, and:

- **Its reading** is the first saved statement profile, by name, that reads all its columns, else a proposed mapping. Before it has an account, a file says what it covers: its lines, the days, and whether its balance column adds up (`ImportSession.statementSummary(today:)`).
- **Its account** is the first of these that names exactly one of the library's open cash and savings accounts that don't record trades: the profile's account; the account the file follows on from, when it has a balance column and its balance before its first line (a first-day line's balance less its amount, or less the day's) is the account's value on the day before the file; the account whose name or institution, without the words any account could have (`Conto Fineco` is `Fineco`), the file's name or its title rows (the rows above the header) have, each word anywhere in them. A profile's account that is closed, or records trades now, doesn't count. A file without one waits for a choice (`StatementBatch.setAccount(_:forFile:)`).
- **Transfers between the files** are paired: a line out of one account and a line in of another in the same currency, the same amount within 4 days, the nearest in date first, each line once. Both become transfers (`StatementBatch.File.pairs`, `StatementLine.Source.paired`). Only lines classified by their sign, a sender or the usual words are paired; a chosen class, a rule, a trade, an answer or a named account comes first. A line answered as a move, a purchase or a sale is never paired, even while the answer can't be taken yet.
- **The order:** files are previewed and applied by account, then by their first line's day, each against the library with the files before it applied (`StatementBatch.previews(against:)`), so February's file follows on from January's value even when neither was in the library before. An account whose files sell an account the library doesn't have yet comes after the others, so the purchase that starts it is applied first.
- **A sale across files:** a line in can be answered as the sale of what a purchase in another file starts, on or after the purchase's day and in the same currency. The sale's file is applied after the purchase's (see the order below), so its preview finds the new account in the library and records the sale like any other.
- **Check-ins before the first:** which month ends before the library's first check-in get a value (`StatementBatch.setCheckIns(_:library:today:)`, `retire import statements --before-first-check-in months|quarters|none`) is set for every file, and for files added later ([Values](#values)).
- **Gaps and overlaps** between consecutive files of one account, by the days each covers, are listed (`StatementBatch.gaps(in:batch:)`): days no file covers leave the money in and out of the next value incomplete, and days two files cover count their lines twice.

A file that can't be read is listed with its error, and the others still import. Files can be added to a batch later (`StatementBatch.add(files:library:checkIn:today:)`) or taken out (`remove(file:library:today:)`): the files already there keep their accounts and answers, and the transfers are paired again. A file's ID is its place among every file given, read or not.

A line that needs an answer stays one once it's answered (`StatementLine.wasAsked`).

Rules live in each file's profile. A rule made for every statement is made in each file's (`StatementBatch.editSessions(library:today:_:)`, which edits every file and pairs the transfers once), and `ImportSession.statementRule(matching:)` finds a profile's rule for a phrase itself, the one a new rule with the phrase replaces.

### Remembering banks and senders

Importing statements can save how each file was read, so the next statement of each bank imports without questions (`StatementBatch.rememberedProfiles(in:today:)`; in the app, *Remember these banks and senders* on Review, on by default). The profiles are written with the import and backed up with it, so undoing the import removes them too.

- **A file read with a saved statement profile** updates that profile, under its ID and name. When several files are read with it, the file of the profile's own account does, else the first.
- **Every other file** gets a new profile, one per account, named after the account's bank and the account (`Fineco, Conto corrente`, ID `fineco-conto-corrente`), or after the file without its extension when the account has no bank.
- **Rules:** every profile gets the rules of every file: its own first, then the others' for words it has no rule for, so a sender answered on one account's statement is known on every bank's. A rule that moves money to or from the profile's own account is left out of it.
- **Answers:** a class chosen for a single line is remembered in its file's profile (`answers`, `ImportSession.statementAnswers(adding:)`): its date, amount, text and class. A later statement with the same line, such as an export of the last 90 days that covers last month again, classifies it the same way and asks nothing. A new class for the line replaces the one remembered. Answers that move money to or from an account, a purchase or a sale aren't remembered.

Without it, a class chosen for a line stays the file's, and only *Save as profile*, `--save-profile` or a rule keeps anything.

### Profiles

The example library's `imports/fineco-movimenti.json` reads an Italian bank's movements into `conto-fineco`:

```json
{
  "answers": [
    { "amount": "35", "class": "income", "date": "2026-03-03", "match": "Rimborso spese" }
  ],
  "columns": [
    { "field": "date", "header": "Data operazione" },
    { "field": "ignore", "header": "Data valuta" },
    { "field": "credit", "header": "Entrate" },
    { "field": "debit", "header": "Uscite" },
    { "field": "description", "header": "Descrizione" }
  ],
  "constants": { "account": "conto-fineco" },
  "defaults": { "date": { "pattern": "dd/MM/yyyy" }, "number": { "decimal": ",", "thousands": "." } },
  "file": { "delimiter": ";", "encoding": "utf-8", "headerRow": 4 },
  "id": "fineco-movimenti",
  "layout": "statement",
  "name": "Fineco, movimenti",
  "onConflict": "ask",
  "rules": [
    { "class": "transfer", "match": "Bonifico a favore di Directa" },
    { "class": "spending", "match": "Addebito carta di credito" }
  ]
}
```

The fields are those of any profile ([import-profile.schema.json](schema/import-profile.schema.json)), with `rules` and `answers`.

### The sample statements

The statement layout is tested with made-up exports in `Tests/ImporterTests/Samples/statements/`:

- **Italian-like** (`italian-bank.csv`): title rows, `;`, `1.234,56`, `dd/MM/yyyy`, the newest line first, `Entrate` and `Uscite`, a value date; pay, a transfer to a broker, a `Giroconto`, interest, and a line in a month that isn't over.
- **English-like** (`english-bank.csv`): `,`, `MM/dd/yyyy`, signed amounts and a running balance, a savings account's interest.

## Where it runs

- **Engine.** The `Importer` module, in pure Swift. It reads bytes and a `Library` and returns results; the app and the CLI back up and write the files it reports as changed. It's tested on Linux against a folder of sample files (`Tests/ImporterTests/Samples/`): Italian Excel CSVs in Windows-1252, US-style exports, Numbers exports, title and totals rows, month-only dates, Excel serial dates, long files, quantities with prices, debts written as positive amounts (and columns that write them negative), broken rows.
  - `ImportSession(data:)` reads a file and proposes a mapping, or `ImportSession(data:profile:)` uses a saved one. The session holds the mapping as an `ImportProfile`, with helpers to map a column, pick the date column (`dateColumn` is the one the dates are read from), remember or forget a match (`rememberedAccount(for:)` finds one as the preview does) and settle an ambiguity.
  - `session.preview(against:today:)` returns an `ImportPreview` (rows dated before 1900 or more than a week after `today`, by default the device's, are cell errors): every record with its status, cell errors, issues, ambiguities, name matches, and the proposed accounts, instruments and account changes, with the records rejecting them leaves out (`leftOutRecords`). The quantities of an account that records trades are its trades there (`QuantityTrades`, noted with `ImportIssue.Kind.quantitiesAsTrades`): Tracker's conversion isn't reachable from the importer, so it follows the same rules with Model's `HeldQuantities`.
  - `preview.apply(to:)` returns an `ImportResult`: the new library and the month files, accounts and instruments that changed.
  - `session.makeProfile(id:name:library:)` saves the mapping with everything detected written out.
  - Broker transactions: the trades layout reads each row into a trade with a stable ID (`TradeID.stable`), keyed `ImportRecordKey.trade`. `ImportSession.looksLikeTransactions` tells a transactions file; `tradeTypeValues` lists the type column's values with the type each is read as (`TradeTypeValue`: from the profile, the usual words in `TradeTypeWords`, or unmapped), and `setTradeType(_:for:)` maps one. The preview carries them in `ImportPreview.tradeTypes`; proposals to make an account record trades are `AccountChangeProposal.Change.recordTrades`, and `ImportResult.tradesAccounts` and `tradesWritten` say what applying did. Tested with the made-up exports in `Tests/ImporterTests/Samples/trades/`.
  - Bank statements: the statement layout reads each line into a `StatementLine` with its class, why it has it, and the value it counts in (`ImportPreview.statementLines`); its values are records keyed `ImportRecordKey.valuation`, with `moneyIn`, `moneyOut`, `interest`, `oneOff` and `tax`, and a purchase's or sale's `saved` (`ImportedRecord`). `ImportSession.looksLikeStatement` tells a statement; `statementRule(for:)` and `setStatementRule(_:for:)` read and change the profile's `rules`, `setStatementClass(_:forRow:)` chooses one line's class, `statementOpeningBalance` gives the balance before the file, and `statementFrom` and `statementThrough` the days it covers. Tested with the made-up exports in `Tests/ImporterTests/Samples/statements/`.
- **App.** The same SwiftUI flow, with the same steps, on Mac and iPhone. The Mac, with its big table, is the comfortable place to build a profile. A broker's transactions add a Types step after Columns. A bank statement asks for its account with the file, keeps Format and Columns in a sheet with the days the file covers, and goes from Files to Review, where the balance before it is given ([UI.md](UI.md#import-mac-first)). The app doesn't ask about lines while importing: what each line is, a move to one of your accounts among them, is checked afterwards on its month's lines ([UI.md](UI.md#a-months-lines)). A purchase you keep and a sale (`--purchase`, `--sale`) are the command line's.
- **CLI.** `retire import <file>` previews without writing (the default, `--dry-run`): the detected settings, what each column becomes, the formats to confirm, notes, proposed accounts and closings, a summary with sample records and conflicts, and the cells that can't be read. `--save-profile <id>` saves the proposed mapping as `imports/<id>.json` to edit and reuse with `--profile <id>`; options such as `--date-format`, `--decimal`, `--delimiter` and `--liability-sign` override what was detected. `--apply` backs up the files that change to `backups/<timestamp>-import/` and writes them; it refuses while formats are still guesses (unless `--accept-guesses`). Non-interactively, new accounts and instruments and closings are only made with `--accept-new-accounts`, `--accept-new-instruments` and `--accept-closings` (their records are left out otherwise), and conflicts follow `--on-conflict keep|overwrite` (undecided ones keep the library's values). `retire import --undo` undoes the latest import not undone yet, leaving later edits in place and listing them, after copying the current files to `backups/<timestamp>-undo-import/`.
- **CLI, broker transactions.** `retire import <file>` reads a transactions file as trades, or with `--layout trades`; the report lists the file's type words with their trade types (**Types**) and notes on signs, and the trades among the records. `--account <id>` names the account of every row, `--type "<word>=<type>"` (repeatable) maps a word, or `--type "<word>=ignore"` leaves its rows out, and `--amount-sign auto|from-type|as-written` sets how amounts are signed. An account of another kind than brokerage, crypto or metals that doesn't record trades is switched only with `--accept-trades-mode`; otherwise its trades are left out. `--save-profile` writes the types too. JSON output adds `tradeTypes`, `summary.trades` and `result.tradesAccounts`.
- **CLI, bank statements.** `retire import <file> --account <id>` reads a statement (or with `--layout statement`), as `retire import statements` reads one file: without `--account`, its account is found as a batch's files' are ([Several statements at once](#several-statements-at-once)). The report's **Lines** lists each class with its money in and out, then the lines with their class and why, those classified by their sign alone first, largest first. `--class "<words>=<class>"` (repeatable) adds a rule, `--move "<words>=<account>"` (repeatable) one that moves the lines' money to or from an account, and `--save-profile` keeps the rules. `--purchase "<row or words>=<kind>:<name>"` answers a line out as a purchase you keep (kind `belongings`, `property` or `other`), and `--sale "<row or words>=<account>"` a line in as a sale ([Moved to or from an account](#moved-to-or-from-an-account)); a number is a row, other words must be in one line's text only, and a line that needs an answer shows its row. Both are repeatable, one answer per line, and their new account and closing are made with `--apply` without `--accept-new-accounts` or `--accept-closings`; an answered line in `statementLines` has `asset` and `assetAccount`. `--opening-balance <amount>` gives the balance before the file, and `--from` and `--through` the days it covers. JSON output adds `statementLines`.
- **CLI, several statements.** `retire import statements <file>…` reads every file as a statement ([Several statements at once](#several-statements-at-once)). The report's **Files** lists each file with its account, how it was found, the days it covers, its lines and how many were paired with another file's, then **Gaps and overlaps**, then each file's lines and preview. `--account "<file>=<id>"` (repeatable, the file by its name or path) gives a file's account, and `--class`, `--move`, `--date-format` and `--on-conflict` apply to every file. `--purchase` and `--sale` name a line by words only one line of the files has, or as `<file>:<row>`. `--apply` writes the files in order as one import, one `--undo` takes back, and refuses while a file has no account, two files of an account cover the same days, or formats are guesses (unless `--accept-guesses`). JSON output has `files` (each with `name`, `account`, `found` and the file's `report`, as `retire import --json` prints it), `unreadable`, `gaps` and `result`.
- **CLI, trades.** `retire trades list <account> [--year] [--instrument] [--json]` and `summary <account> | --all [--year] [--json]` ([TRADES.md](TRADES.md)). Trades are added, edited and converted in the app, or in the history files by hand.
