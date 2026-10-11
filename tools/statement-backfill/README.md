# Statement backfill

A one-off script that reads PDF bank, broker, card and loan statements with a local model and writes CSVs that `retire import` reads. It runs on a Mac with Apple silicon, through [mlx-lm](https://github.com/ml-explore/mlx-lm), so no statement leaves the Mac. It isn't part of the Swift package or the app.

## What it does

1. **Text.** `pdftotext -layout` reads each page. A page with almost no text is a scan, and `ocrmypdf` reads it, if installed.
2. **Classify.** The model reads the first page: bank, broker, card, loan or something else (skipped), the institution, the account number and the period.
3. **Extract.** The model copies each page into JSON: transactions, balances, holdings. It copies; it never adds anything up. The prompts are in `prompts/`.
4. **Check.** The script adds up the numbers. In a bank statement, the opening balance plus the transactions must equal the closing balance, and every running balance printed must follow from the line before. In a broker statement with cash balances, the same goes for the cash. A page that doesn't add up is asked again, with the numbers that don't match; a statement that still fails is tried with `RETRY_MODEL`; one that fails again is left out and listed in the report.
5. **Assemble.** Account numbers are mapped to the library's accounts (`accounts.json`), and then:
   - **Cash and savings:** one row per month end, with the balance, money in, money out and interest. Transfers between your accounts (the same amount out of one and into another within 4 days, a broker deposit included) count as neither money in nor money out. Several statement accounts mapped to one library account are merged: their balances add up.
   - **Brokers:** every trade. A depot transfer between two statement accounts mapped to one library account is dropped on both sides, so the holdings keep the cost of the original buys. The holdings the trades give are compared with those each statement lists.
   - **Cards and loans:** the balance owed on each statement date.
   - The checks across statements: each closing balance is the next opening balance, and missing statements show as gaps. A month end that falls in a gap or in a failed statement is left out rather than guessed.

Every model reply is cached in `WORK`, one folder per PDF (named after its hash). Stopping and running again picks up where it stopped, and a rerun after the full run costs nothing until something changes.

## Setup

```sh
brew install uv poppler
brew install ocrmypdf          # only if some statements are scans
cp accounts.example.json accounts.json
```

- **accounts.json** maps each account number on your statements to a library account ID. Spaces don't matter, and a masked number (`**** 4242`) matches on the digits it shows. Point several numbers at one ID to merge them. Git ignores this file. A number that isn't in it is listed in the report, with how many statements it has, so the first run tells you what to add.
- **The library's accounts** should exist before importing, with the right kinds: a cash or savings account per ID in `cash.csv`, a brokerage account that records trades per ID in `trades.csv`, a credit card or loan per ID in `debts.csv`.
- **The paths and models** are at the top of `backfill.py`.

## Run

```sh
uv run backfill.py
```

The first run downloads the models from Hugging Face (about 17 GB and 18 GB at 4-bit). It prints what it does for each PDF: the pages, what kind of statement it is, how many transactions each page has, the model's speed, and whether the numbers add up. Set `SHOW_REPLIES = True` to see every reply.

Start with the pilot `LIMIT = 20` and pick PDFs from every bank and broker with `ONLY`. Check the CSVs and `report.md` by hand, then set `LIMIT = None` for the rest.

**Rerunning after a change:** each PDF's folder in `WORK` holds `text.json`, `classify.json`, `page-N.json` (the model's JSON and the conversation) and `status.json`. Delete the files to redo: all of a PDF's folder to read it again from scratch, its `page-*.json` and `status.json` after changing an extraction prompt, or every folder's `status.json` and `page-*.json` to rerun every statement with a new prompt. Assembling runs at the end of every run and reads only the cache.

## Output

In `OUTPUT`:

| File | What it holds |
| --- | --- |
| `cash.csv` | `date, account, balance, moneyIn, moneyOut, interest`: month ends of cash and savings accounts. A month after a gap, and an account's first month, have no money in and out. |
| `debts.csv` | `date, account, balance`: what was owed, as a positive amount. |
| `trades.csv` | `date, account, type, isin, instrument, quantity, price, currency, amount, fees, tax, ratio, note`. |
| `profiles/` | Import profiles for the three CSVs. |
| `report.md` | What was left out and why: failed checks, unknown accounts, gaps, balances that don't carry over, merged accounts, holdings that differ, trade types to map. |

## Import

Copy the profiles into the library, preview each file, then import it:

```sh
cp ~/statement-backfill/output/profiles/*.json "<library>/imports/"
swift run retire import ~/statement-backfill/output/cash.csv --profile backfill-cash
swift run retire import ~/statement-backfill/output/cash.csv --profile backfill-cash --apply
swift run retire import ~/statement-backfill/output/debts.csv --profile backfill-debts --apply
swift run retire import ~/statement-backfill/output/trades.csv --profile backfill-trades --apply \
    --accept-new-instruments
swift run retire import --undo     # puts back what the latest import changed
```

- The profiles keep what the library already has where they differ (`onConflict: keep`), so your check-ins win.
- Add `--library <path>` if `retire` doesn't find the library by itself.
- A trade type the model couldn't name keeps the statement's word and is listed in the report; map it with `--type "Word=fee"`.
- **Not imported yet:** money in, money out and interest. The importer has no target for them, so the cash profile ignores those columns. Once it has, map those columns in `backfill-cash.json`.

## Tests

```sh
python3 -m unittest
```

The tests build made-up PDFs and answer for the model, so they need `pdftotext` but not mlx-lm or a Mac.
