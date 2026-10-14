# Accounts: what each kind records

An account's kind alone says what its values record and how what it saved is worked out. Values come only from imported files: the app types no balance, money in and out, what was saved or trade, and the check-in is read-only ([UI.md](UI.md#check-in)).

The rules are in `Sources/Model/Accounts/`: `AccountKind.defaultValuationMode`, `AccountKind.defaultFlow` (`FlowDefault`), `AccountKind.recordsMoneyInOut`, `Account.valuationMode` and `Account.asksForFlow`.

## Every kind

| Kind | Records | Saved (`flow`) |
| --- | --- | --- |
| `cash` | Balance, money in, money out | The whole change |
| `savings` | Balance, interest (optional), money in, money out | The change minus the interest |
| `creditCard` | What's owed, negative | The whole change |
| `loan` | What's owed | The whole change |
| `mortgage` | What's owed | The whole change |
| `brokerage` | Trades (`"valuation": "trades"`); a broker statement's cash and positions are a check. Set in its file, a balance instead (`"valuation": "balance"`) | Worked out from the trades; for a balance, the whole change |
| `crypto` | As brokerage | Worked out from the trades |
| `metals` | As brokerage | Worked out from the trades |
| `pensionFund` | Balance, and what was saved, from its file ("Paid in since …") | Recorded, from a spreadsheet's saved column ([IMPORT.md](IMPORT.md#saved)); left out, unknown, and the change counts as other |
| `tfr` | As a pension fund | As a pension fund |
| `property` | As a pension fund (usually nothing paid in) | As a pension fund |
| `belongings` | Things you own that lose value and might sell (a car, a bike, a boat, electronics): balance, and optionally an estimated loss of value a year (`depreciation`) | The whole change, so its loss of value is spent; between values, the estimated loss |
| `taxPot` | Money set aside for a tax bill paid later, such as once a year: balance, money in (a refund of tax) and money out (tax paid from it), in neither net worth nor plans unless `includeIn` says so; what moves into it from your other accounts is tax, so came in is after it and it isn't spent ([PROGRESS.md](PROGRESS.md#money-in-and-out)) | The whole change |
| `other` | As a pension fund | As a pension fund |

## Decisions

### What each kind records

Each kind's values record the fields in the table above, from its files. An account's first value records only its balance (or, for a trades account, its opening positions and cash): there's no value before it to measure money in and out from.

### Money in and out

- **Required** on every cash and savings account, at every value after its first.
- **Credit cards, loans and mortgages don't record them.** They're debts: paying one off is money out of the cash or savings account the payment leaves.
- **No budgeting.** Nothing is categorized: the app records only how much comes in and how much goes out ([PLAN.md](PLAN.md#non-goals)).

### Saved

- **Stored only where it's information.** What a pension fund, a TFR, a property or an `other` account saved can't be told from its balance, so its values record it in `flow` (`Account.asksForFlow`). Every other account's is worked out from what's recorded whenever it's needed (Tracker's `Valuator.flow(of:previous:)`), and its values store none: a stored copy could only fall out of step.
- **Cash:** the whole change. **Savings:** the change minus the interest. **Debts and belongings:** the whole change. **Trades accounts:** from the trades ([TRADES.md](TRADES.md#flows)).
- So a savings account's interest counts as market, as a fund's return does.
- What was saved splits the change into market, saved and other ([schema/README.md](schema/README.md#how-values-are-computed)).

### Moved between your accounts

What's left over. It's shown, and not stored:

> moved = balance − previous balance − money in − one-off + money out (− interest, for savings)

The flow is the change (cash) or the change minus the interest (savings), so this is **flow − money in − the one-off + money out** for both kinds (`Valuator.moved(_:previous:)`).

- **Shown with each value** of a cash or savings account on its page ([UI.md](UI.md#accounts)).
- **Interest on a current account** isn't recorded; it ends up in "moved".

### Loans and mortgages

- **Payments are money out** of the account they leave, like rent, so money out a year matches a plan whose spending includes them ([PROGRESS.md](PROGRESS.md#money-in-and-out)).
- **The principal repaid** is saved in the savings rate: the savings rate adds up what every account saved ([PROGRESS.md](PROGRESS.md#money-in-and-out), *Savings rate*), and what a loan or mortgage saved is the drop in what's owed. Its interest is spent.
- **Credit card payments** are money out too. A card's purchases are spent when they're made: what it saved is the change in what's owed.

### Investment accounts record trades

- Brokerage, crypto and metals accounts record trades (`"valuation": "trades"`).
- **Trades come from the broker's exports.** Holdings, cash and what was saved follow from them ([TRADES.md](TRADES.md#check-ins)).
- **A broker statement's cash and positions**, imported, stay as a check ([TRADES.md](TRADES.md#reconciliation)).
- **The account details** list the trades in place of the account's values.
