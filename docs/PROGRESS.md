# Progress: net worth, projections, and how you're doing against them

The tracker shows where you are, and the planner shows where you're heading. This document covers what connects the two:

- your history and your projection on one chart;
- how the answer to "can I retire yet?" changes from one check-in to the next;
- how reality compares with what you projected earlier, and why;
- what your investments actually returned.

## Views

### Net worth (tracker, M1)

The Overview described in [PLAN.md](PLAN.md#app-structure):

- net worth over time, stacked by category;
- breakdowns by category, asset class, currency and institution;
- the change since the last check-in, split into market movement and new money;
- accounts that haven't been updated recently.

### Past and future (M2)

One chart from your first check-in to the end of the plan:

- **History:** your actual values up to today, as a solid line.
- **Projection:** from today, the median as a dashed line with the 10th–90th percentile band.
- **Markers:** the retirement age, pension starts, and when locked money (such as the pension fund) becomes accessible.
- **Scope:** switch between *net worth* (everything) and *plan assets* (only the accounts the plan counts; your home, for example, is excluded).
- **Units:** the projection is in today's euros, so by default the history is shown in today's euros too, adjusted with actual inflation. A toggle shows the history in the euros of the time instead.

### The answer over time (M2)

Each check-in re-runs the main plan (`mainPlan` in `library.json`) and records the headline:

- the earliest retirement age at your confidence level;
- the chance of success at your target age;
- progress toward financial independence.

The chart then shows how "you can retire at 54" moves from month to month.

Markers show when the plan's inputs, the app's calculation code or the tax parameters changed. So you can tell a move caused by markets and savings from one caused by changing the plan or by a new budget law.

### Actual vs. a baseline (basic in M2; the explanation in M3)

A **baseline** is a projection saved at a point in time (see below). Choosing one shows:

- **Chart:** the baseline's projection band from its start date, with your actual line drawn over it. The actual line uses the same accounts, in the same euros.
- **Where you are:** e.g. "€12,400 ahead of the median, at the 61st percentile of what you expected in January 2026".
- **Why** (M3): the gap between your actual line and the baseline's expected path, split into four parts. The expected path is its deterministic run.

  | Part | Meaning |
  | --- | --- |
  | Savings | The new money you actually added, minus what the plan expected you to save |
  | Markets | Your actual investment returns, minus the assumed returns |
  | Inflation | Actual inflation, minus assumed inflation (it changes what your money is worth in the baseline's euros) |
  | Other | Everything else: windfalls and expenses the plan didn't include, and balance accounts whose changes can't be explained |

  The split is an approximation, since the four parts affect each other. It answers the useful question, though: am I behind because I saved less, or because markets were bad?

### Performance (M3)

The returns on your investments over a period:

- **Two measures:**
  - **Time-weighted return:** how the investments did, independent of when you added money. It is comparable to the return your plan assumes.
  - **Money-weighted return** (an internal rate of return): what you actually experienced, including the effect of when you added and withdrew money.
- **Units:** nominal and real (adjusted with actual inflation).
- **Breakdowns:** for the whole portfolio, by asset class and by account.
- **Periods:** since the last check-in, year to date, 1, 3 and 5 years, and since the start. Periods longer than a year are annualised.
- **What it needs:** knowing how much money went in or out of each account (see below). Accounts without that information show their change in value, but no return.

## Baselines

A baseline stores the **outputs** of a projection, not just its inputs. If the app recalculated an old plan with today's code and today's tax parameters, it would give a different answer from the one you saw then. The point of a baseline is to remember what you expected at the time.

Baselines are created:

- **automatically**, at the first check-in of each year, for the main plan;
- **by hand**, with *Save baseline* and a label, e.g. before a big decision such as switching to forfettario.

`projections/<plan-id>/baselines/<date>.json`, about 10 KB each. The file name is the baseline's ID; a second baseline saved on the same day gets `-2`.

```json
{
  "accounts": ["conto-fineco", "directa", "fondo-pensione", "gold-coins", "ledger-wallet"],
  "created": "2026-01-05",
  "engine": "1.2.0",
  "headline": { "confidence": "0.9", "earliestAge": 54, "successAtTarget": "0.83" },
  "kind": "yearly",
  "label": "Start of 2026",
  "plan": { "…": "a full copy of plans/base.json as it was" },
  "start": { "date": "2025-12-31", "value": "212400" },
  "taxParameters": { "it": 2026 },
  "years": [
    { "expected": "231500", "p10": "214800", "p25": "223900", "p50": "230900", "p75": "238200", "p90": "249700", "savings": "18000", "year": 2026 }
  ]
}
```

(The numbers are made up. `years` has one row per year up to the plan's end age. Values are in euros of the start date. Months between year-ends are interpolated.)

## The answer over time

`projections/<plan-id>/headlines/<year>.json`: one small record per check-in.

```json
{
  "headlines": [
    { "date": "2026-09-30", "earliestAge": 54, "engine": "1.2.0", "fiProgress": "0.41",
      "planHash": "5c1f…", "successAtTarget": "0.86", "taxParameters": { "it": 2026 } }
  ]
}
```

`planHash` identifies the plan's inputs, so the chart can mark the check-ins where you changed the plan. `earliestAge` is left out when no age reaches the confidence level, and an optional `confidence` records the level used.

## Data this needs from day one

Two kinds of data are needed for the comparisons above.

**How much money went in or out of each account.** This is the only one that can't be reconstructed later, so it's recorded from the first check-in (M1), even though the analysis comes in M3.

- Each valuation can carry a `flow`: the net money added (+) or taken out (−) since the previous valuation, in the account's currency.
- The check-in fills it in for you and asks only where it can't:

  | Account kind | Default flow |
  | --- | --- |
  | Current accounts, credit cards, loans, mortgages | The whole change. Money arriving or leaving (salary, spending, repayments) is new money, and interest is small. |
  | Savings accounts | The whole change, but editable, since interest can matter. |
  | Brokerage, crypto, metals | The *new money* part of the change, i.e. everything that isn't price movement. Override it if a distributing fund's dividends were reinvested, since those are returns, not new money. |
  | Pension fund, TFR, property, other balance accounts | Asked for: e.g. contributions from the pension fund's statement. If left empty, the flow is unknown, and the account's change counts as "other". |

- Moving money between two tracked accounts cancels out at the portfolio level (−1,000 from the current account, +1,000 into the broker). So the sum of all flows is your actual savings for the period, which is what the plan's savings are compared against.

**Inflation.** Needed to put the actual line in today's euros and to compute real returns. The app fetches Italy's consumer price index (Eurostat HICP) along with FX rates, and stores it in the monthly history files. Past values are public, so this can be filled in later if needed.

## What changes in the files

- **Valuations:** an optional `flow` field.
- **Monthly history files:** a list of `indices` (consumer price index values).
- **A new `projections/` folder:** baselines and headlines. They are the one deliberate exception to "only inputs are stored", because they record what you expected at the time.

Details are in [FILE_FORMAT.md](FILE_FORMAT.md).
