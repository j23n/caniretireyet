# UI

What the app looks like and how it behaves, on iPhone and Mac. It's built with SwiftUI on iOS 26 and macOS 26, using the system's Liquid Glass look.

## Who uses it, and when

The app has one user, and three situations to design for:

| Situation | Where | How often | What matters |
| --- | --- | --- | --- |
| **Monthly check-in** | Mostly iPhone | Monthly, about 5 minutes | Speed. Values are pre-filled, and only what changed needs a tap. It ends with this month's answer. |
| **Planning session** | Mostly Mac | A few times a year, 30–60 minutes | Inputs and results side by side, what-ifs that update instantly, comparing two plans. |
| **Looking after the data** | Mac | Occasionally | Adding and closing accounts, importing, fixing a value, looking at the files. |

Plus the glance: "how am I doing?" in a widget or on the Overview.

**Tone.** Money is emotional, so the app stays calm and matter-of-fact:

- no confetti, streaks or red alarm screens;
- uncertainty is shown honestly, e.g. "in 9 of 10 simulated futures", never as a single promised number;
- nothing ever scolds you.

## Navigation

**iPhone:** a tab bar with three tabs. The check-in lives in the tab bar's accessory, so it's one tap from anywhere.

```
╭──────────────────────────────────────────╮
│ ◷ October check-in · due in 3 days    ▸  │  ← tab bar accessory (iOS 26)
╰──────────────────────────────────────────╯
   ◉ Overview     ▤ Accounts     ◔ Plan
```

- **Overview:** net worth, history, how you're doing.
- **Accounts:** the list, account details, adding and closing.
- **Plan:** results, progress and inputs for each plan.
- **Settings** opens from a gear button in the Overview toolbar. It's rarely needed, so it doesn't take a tab.
- The accessory shows the check-in's state, e.g. "Last check-in 30 Sep · next 31 Oct", or "due" with a start button.

**Mac and iPad:** a sidebar with a content area, plus an inspector where it helps.

```
Overview
Check-in                •     ← dot when due
Accounts
  Cash · Investments · Crypto & gold · Pension · Property · Debts · Closed
Plans
  Base case
  Part-time from 50
Library
  Import…
  Instruments
  Sync & backups
```

- **Settings** is the standard Settings window (⌘,).
- **Menu commands:**

  | Command | Shortcut |
  | --- | --- |
  | New Account | ⌘N |
  | New Check-in | ⌘K |
  | Import… | ⌘⇧I |
  | Save Baseline | ⌘⇧B |
  | Hide Amounts | ⌘⇧H |
  | Show Future | ⌘⇧F |
  | Duplicate Plan | ⌘D |
  | Compare Plans | ⌘⌥C |

- **Drag and drop:** dropping a CSV, or ledger journals, anywhere on the window starts an import.
- **Windows:** plan comparison and import can open in their own windows.

## Overview

The home screen. Top to bottom:

```
┌──────────────────────────────────────────┐
│ Overview                        👁   ⚙︎   │
│                                          │
│ Net worth                                │
│ 312.480 €                                │
│ ▲ 4.210 € since 31 Aug   ▲ 14,2% this yr │
│                                          │
│  1Y  [3Y]  5Y  All            Future ◯   │
│ ┌──────────────────────────────────────┐ │
│ │                          ╱‾‾╲__╱‾    │ │
│ │              ___╱‾‾‾‾‾‾‾‾            │ │
│ │ ____╱‾‾‾‾‾‾‾‾                        │ │
│ └──────────────────────────────────────┘ │
│  Total │ By asset class                  │
│                                          │
│ ┌ Since last check-in ─────────────────┐ │
│ │ 308.270  ▮ markets   +2.950          │ │
│ │          ▮ new money +1.500          │ │
│ │          ▯ other       −240  312.480 │ │
│ └──────────────────────────────────────┘ │
│ ┌ Can I retire yet? ───────────────────┐ │
│ │ Not yet · earliest at 54 (2042)      │ │
│ │ ▇▇▇▇▇▇▇▇░░░░░░░░░░░ 41% of the way   │ │
│ │ 12.400 € ahead of your Jan baseline  │ │
│ └──────────────────────────────────────┘ │
│ ┌ Needs attention ─────────────────────┐ │
│ │ ⚠︎ Fondo pensione: last value May     │ │
│ └──────────────────────────────────────┘ │
│ ┌ Allocation ─────── Asset class ▾ ────┐ │
│ │ Equity    ▇▇▇▇▇▇▇▇▇▇▇▇  182.400  58% │ │
│ │ Cash      ▇▇▇▇           53.100  17% │ │
│ │ Crypto    ▇▇▇            40.100  13% │ │
│ │ Gold      ▇               6.100   2% │ │
│ │ …                                    │ │
│ └──────────────────────────────────────┘ │
└──────────────────────────────────────────┘
```

- **Hero number.**
  - Net worth at the latest check-in, with its changes since the last check-in and this year.
  - It animates when it changes (`.contentTransition(.numericText())`).
  - Tapping it switches between net worth and *plan assets* (what the plan counts, e.g. without your home).
- **History chart.**
  - By default, a single net-worth line with a light fill. *By asset class* switches to stacked areas, with debts below the zero line.
  - Drag across it to read any month: a vertical rule with a callout showing the date, the total and the breakdown.
  - **Future** continues the chart into the active plan's projection: a dashed median with the 10–90% band, plus markers for retirement and pension starts. See [PROGRESS.md](PROGRESS.md#past-and-future-m2).
- **Since last check-in.** A small waterfall from last month's total to this month's: markets, new money, and other. It's the most useful single number after the total, because it separates "I saved" from "markets moved".
- **Can I retire yet?** The plan's headline, progress toward financial independence, and how you compare with the latest baseline. Tapping it opens the Plan tab.
- **Needs attention.** Only shown when something needs you: stale accounts, prices that couldn't be fetched, sync conflicts that were merged, and plan warnings.
- **Allocation.** Horizontal bars with values and percentages; a donut would be harder to read. The dimension can be switched between asset class, account group, currency, institution, and liquid vs locked.
  - *Asset class* splits holdings by their instrument's mix and balances by the account's mix, and shows debts as their own bar.
  - *Currency* is where each part is priced; bitcoin in a euro wallet counts as dollars.
  - *Locked* is pension funds, TFR, property and vehicles, and the mortgage secured on the property.

## Check-in

The flow that has to be fast. It opens as a full-screen sheet on iPhone and as the Check-in page on Mac. Everything is on one scrolling page; there's no wizard.

```
┌──────────────────────────────────────────┐
│ Cancel          Check-in          Review │
│ 30 September 2026 ▾                      │
│ ✓ Prices and FX updated (4)           ▸  │
│                                          │
│ CASH                                     │
│ Conto Fineco        [   4.210,55 € ]  ●  │
│   was 4.520,75 · new money −310,20       │
│ Savings                 12.000,00 €   ✓  │
│   unchanged                              │
│ INVESTMENTS                              │
│ Directa                  57.410 €     ●  │
│   VWCE  [ 412,5 ] sh × 138,42   57.098   │
│         +10,5 since Aug · paid [1.450,00]│
│   Cash  [ 312,10 ]                       │
│ CRYPTO & GOLD                            │
│ Ledger wallet   0,4215 BTC   40.093   ✓  │
│ Gold coins      62,2 g        6.120   ✓  │
│ PENSION                                  │
│ Fondo pensione      [  18.450,12 € ]  ○  │
│   contributions since June [ 1.325,00 ]  │
│ PROPERTY & DEBTS                         │
│ Mutuo              −182.340,00 €      ○  │
│                                          │
│ ╭──────────────────────────────────────╮ │
│ │ 7 of 9 reviewed   Mark rest unchanged│ │
│ ╰──────────────────────────────────────╯ │
└──────────────────────────────────────────┘
  ●  updated   ✓  unchanged   ○  not reviewed yet
```

- **Date.** Defaults to today. In the first days of a month it suggests the end of the previous month. An earlier date fills in history: see [Adding history](#adding-history).
- **Prices.** Fetched as soon as the sheet opens, while you work. The status row opens the price list, where you can see the source and time of each price and type in any that failed.
- **Accounts, in groups.** Each row has one of three states:
  - **updated:** you entered a new value;
  - **unchanged:** you confirmed it's the same. This still writes a valuation, so the account isn't stale;
  - **not reviewed.**

  "Review" asks about any rows not reviewed: mark them unchanged, or skip them (then no record is written, and the account will show as stale). A new account with no earlier value can't be unchanged: it's entered or skipped.
- **Accounts with holdings.** Each position's quantity is pre-filled, and its value updates live with the fetched price. When a quantity goes up, an optional "paid" field appears. What you enter updates the position's purchase cost and the new money, which is how purchase costs are tracked without transactions.
- **New money (flow).** Shown under each account, filled in by the defaults in [PROGRESS.md](PROGRESS.md#data-this-needs-from-day-one), and editable. For pension funds the app asks for "contributions since …".
- **Keyboard.** A decimal keypad in your locale's format, with ▲ ▼ buttons above it to move between fields. Amounts accept `1.234,56` and `1234.56`. For a debt, type what you owe (`1.200` is recorded as −1.200); if it's in credit, e.g. an overpaid card, type `+` first (`+20`), or use ± above the keypad. *Update value* and a new account's opening balance work the same way.
- **Draft.** An unfinished check-in is saved as a draft on the device and never half-written to the library. Close the sheet, come back later, and continue.
  - The draft follows the library: when you come back, when the other device changes something, and just before saving. Accounts you haven't reviewed take their latest values, new accounts appear and closed ones leave; what you entered stays.
  - If the other device saved a different value on the same date for an account you entered, a banner says so and the review asks: *Keep saved* or *Use mine*. Until you choose, the saved value stays and yours isn't written.
  - The draft is deleted only once the check-in is in the library's files. If saving fails, the error is shown and the draft stays.
- **Review screen.**
  - The new net worth and the waterfall (markets, new money, other).
  - Changed accounts, and anything unusual, e.g. a quantity that went down (did you sell?) or a value that changed more than 30%.
  - Then **Save**.
- **After saving.** The plan is re-run, and the confirmation ends with this month's answer (only for the latest check-in: see [Adding history](#adding-history)):

  > Saved · Net worth 312.480 € (▲ 4.210)
  > Can I retire yet? Not yet: earliest at **54**, unchanged since August.

  This is the monthly moment the app is built around.

**On the Mac**, the check-in is a table, and the whole thing can be done without touching the mouse:

- columns: Account, Last, Now, Change, New money, Note;
- Tab and Return move between cells;
- ⌘↩ saves.

## Accounts

- **List.** Grouped: Cash, Investments, Crypto & gold, Pension, Property, Debts.
  - Each group shows its subtotal.
  - Each row shows a kind icon, the name, the institution, the value, a sparkline of the last 12 months, and a "stale" badge when needed.
  - Swipe actions: *Update value* (a one-account valuation) and *Close*. Saved as it is, *Update value* records the account as unchanged; an account with no earlier value needs a value typed, and an emptied field isn't zero (type 0). Its date can be any day up to the closing date (or a year from today), also before the account opened: see [Adding history](#adding-history).
  - Closed accounts sit in a collapsed "Closed (3)" section at the bottom.
- **Account detail.**
  - The value and its change.
  - A history chart. New-money events are small ticks on the time axis, so jumps you caused are distinguishable from market moves.
  - For accounts with holdings, the positions: quantity, price, value, purchase cost and unrealised gain.
  - The list of valuations, each editable: date, value, new money, note. *Add Past Value…* adds one on an earlier date.
  - An info section: kind, institution, country, currency, tax wrapper, and whether it's included in net worth and plans.
- **Add account.** A sheet:
  1. Pick a kind from a grid of icons.
  2. Enter the name, institution, currency, country and opening date. The opening date is today by default; the hint says "Set it to when you opened the account, to add its history." The opening balance is the one on that date.
  3. Enter the positions (choose or create instruments) or the balance, which becomes the first valuation.
  4. The tax wrapper is pre-selected from the kind and your residence, e.g. a pension fund becomes `it.pensionFund`.
- **Close account.** A sheet asks for:
  - the closing date;
  - "Where did the money go?", which sets the successor account;
  - a short explanation: the account keeps its history, stays in every chart up to that date, and leaves check-ins.

  Reopening is one button. Deleting is for mistakes only, sits at the bottom in red, and asks for confirmation.
- **Instruments** (under Library on the Mac, and from an account's positions on iPhone): name, ISIN or ticker, currency, unit, asset mix, and price source. Each row shows the latest saved price with its date and source, with a small clock when it's older than the staleness threshold. A footer says: "Prices are also fetched at every check-in. Net worth uses the price on or before each check-in's date."
  - **Update Prices** (toolbar; pull down on iPhone) fetches today's price of every instrument an open account holds that has a price source, and the FX rates that value them in the base currency, and saves them for today in one edit. A banner shows the progress, then the outcome; *Details* lists each instrument as updated, unchanged, failed (with the reason) or kept. A failure doesn't stop the others. A price typed in by hand for today is kept, as in the check-in, unless you choose *Update* on its row. Instruments typed in by hand or not held in an open account are skipped; a row's *Update Price* fetches one anyway.
  - **Set Price…** (on a row, or in the editor) types a price in by hand: the date (today by default), the amount, and the currency (the instrument's by default). It's saved as a `manual` price, which *Update Prices* doesn't replace.
  - The editor's *Test price fetch* saves nothing by itself. For an instrument that exists, a successful test offers *Save price*; a new instrument's tested price is saved with the instrument. The symbol's placeholder follows the source: "Yahoo ticker, e.g. VWCE.DE", or for CoinGecko "e.g. ETH or ethereum" (a ticker or a CoinGecko ID).

## Adding history

Accounts added in the app open on the day they're added, unless you set an earlier opening date. Their past values can be added three ways, without an import file.

- **A past check-in.** Pick an earlier date in the check-in's date panel.
  - The accounts open on that date are listed as usual. Accounts that open after it are listed last, under **Opened later** (collapsed on iPhone). They're optional: never counted as missing, *Mark rest unchanged* leaves them alone, and left empty they change nothing.
  - A value entered for one of them moves the account's opening date back to the check-in's date when it's saved. The row says so ("Saving moves its opening date to 31 Mar 2024."), and the review lists the accounts whose opening date will move.
  - Prices and FX rates are fetched for that date: Yahoo Finance and Frankfurter (ECB) have history, CoinGecko about the last year on its free API. gold-api.com only has today's price, so the price list says "No history for this date: type the price."
  - Values saved after the date stay as they are, and a banner says it's a past check-in.
- ***Update Value* with a past date**, or ***Add Past Value…*** on the account's list of values, which starts on the month end before the first value, so an account fills in a month at a time. Any date up to the closing date works. Before the opening date the sheet says "Saving moves the opening date from 30 Sep 2026 to 31 Mar 2024." and moves it in the same edit. Moving a value earlier in the valuation editor does the same.
- **Import.** For existing accounts, the import's *Accounts* step links the names in the file to them, and the profile remembers the match. Values from before an account's opening date propose to open it on the first of them, applied unless you reject it ([IMPORT.md](IMPORT.md#matching-accounts-and-instruments)).

**A pension fund's joining date** (`tax.joined`, which sets the payout tax: 15%, falling towards 9% with the years of membership) is the opening date when the fund is added. Wherever the opening date moves (these three ways, or the account form), the joining date moves with it if it was the opening date; one set to another day stays.

**New money after an inserted value.** A value's new money (its flow) is measured from the value before it. When a value is added before another one of the same account, or one is corrected, moved or deleted, the next value's new money is worked out again if it was automatic (the default for the account's kind, as the check-in fills it in), and kept if it was typed in. *Update Value* and the valuation editor say which before saving; a past check-in follows the same rule. A value added before an account's first one turns that first value's automatic new money (the whole amount) into the change since. An import leaves flows as they are.

**Answers and baselines are only recorded for the latest check-in.** The plan runs on today's data, so re-running it for a past date would record made-up history in "Your answer over time" and a made-up "Start of <year>" baseline. A check-in dated before the library's latest one records neither, and its confirmation says: "Saved a past check-in (31 Mar 2024). The answer isn't recorded for past dates."

## Plan

A plan picker sits at the top (Base case ▾, with New, Duplicate, Compare, Rename and Delete), then three parts: **Results**, **Progress** and **Inputs**.

### Results

```
┌──────────────────────────────────────────┐
│ Base case ▾                          ⋯   │
│ [ Results ]  Progress   Inputs           │
│                                          │
│ Can I retire yet?                        │
│ Not yet.                                 │
│ Earliest at 54 · March 2042              │
│ in 9 of 10 simulated futures             │
│ Retiring today: 12%                      │
│ At 55 you could spend 38.400 €/yr        │
│                                          │
│ Chance of success by retirement age      │
│ 100% ┤                 ●━━━━━━━━━━━━     │
│  90% ┤┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄╱┄┄┄┄┄┄┄┄┄┄┄┄┄     │
│      ┤           ╱‾‾‾                    │
│   0% ┼━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━     │
│       40    45    50  54      60         │
│                                          │
│ Your money over time · retiring at 54    │
│      ░░░░▒▒▒▒▓▓▓▓━━━━▓▓▓▒▒▒░░            │
│      ↑retire  ↑fund 57  ↑inheritance 62  │
│      ↑INPS 67                            │
│                                          │
│ Retirement income · median  Income│Taxes │
│  ▇▇▇▇▇▇▇▇▇▇▇▇ stacked by source …        │
│                                          │
│ When it fails (1 in 10)                  │
│ Money usually runs out around 84.        │
│ 3% run out before the pension fund opens │
│ at 57.                                   │
│                                          │
│ ╭ What if… ────────────────────────────╮ │
│ │ Retire at     ━━━━━●━━━━  54          │ │
│ │ Spending      ━━━━●━━━━━  36.000 €    │ │
│ │ Saving/month  ━━━━━━●━━━  1.500 €     │ │
│ │ Equity return ━━━━●━━━━━  4,5%        │ │
│ ╰──────────────────────────────────────╯ │
└──────────────────────────────────────────┘
```

- **Headline.**
  - "Yes." or "Not yet.", then the earliest age and date, and the confidence in plain words ("in 9 of 10 simulated futures").
  - Two secondary numbers: the chance if you retired today, and **how much you could spend** if you retired at your target age. The second comes from the engine's solver for the highest spending that still meets your confidence level.
- **Chance of success by retirement age.**
  - One line; a dotted rule at your confidence level; the earliest age marked where they cross.
  - Tapping another age makes it the selected age for the charts below.
  - Steps caused by pension eligibility (e.g. at 64 or 67) show as steps, with a note explaining why.
- **Your money over time.**
  - A fan chart in one hue: the median line, a darker 25–75% band and a lighter 10–90% band.
  - With *Future* history turned on, your actual past values are drawn as a solid line in ink (not the plan's colour) to the left of today.
  - Markers along the time axis: retirement, when locked money becomes accessible, pension starts, windfalls and large expenses.
- **Retirement income.** Stacked bars per year, by source: withdrawals, INPS, other pensions, pension fund, TFR and windfalls, with the spending target as a line. *Taxes* switches to the same years stacked by tax line: IRPEF, addizionali, the tax on gains, and the 0.2% wealth tax.
- **When it fails.** A sentence or two about the failing runs, including bridge failures, i.e. running out before locked money opens.
- **What if.**
  - Sliders for retirement age, spending, saving and equity return. On iPhone they're in a bottom sheet; on the Mac, in the inspector.
  - Results update as you drag: fewer runs while dragging, the full 2,000 when you let go.
  - The headline shows the difference ("Earliest 54 → 53").
  - *Keep* writes the change into the plan; *Reset* throws it away.

### Progress

See [PROGRESS.md](PROGRESS.md).

- **Your answer over time.** The earliest retirement age at each check-in, as a step line. Markers show where you changed the plan, where the app's calculations changed, or where new tax rules arrived.
- **Actual vs baseline.**
  - Pick a baseline, e.g. "Start of 2026 (automatic)" or "Before forfettario (saved 12 Mar)".
  - Its fan chart runs from its start date, with your actual line drawn over it.
  - A summary: "12.400 € ahead of the median · 61st percentile".
  - M3 adds the waterfall explaining the gap: savings, markets, inflation and other.
- **Save baseline…** takes a label.

### Inputs

A form with the same sections as the plan file. Each section is a collapsible card with a one-line summary, so the whole plan fits on one screen when collapsed:

```
You            Born 1988 · retire at 55 · plan to 95
Work           Employee 2026–28 · Forfettario 2029–retirement
Spending       36.000 €/yr · 90% from 75 · 80% from 85
Pensions       INPS (earliest) · State pension from previous country 67
Contributions  Fondo pensione 5.000 €/yr
Events         Inheritance at 62 (80%) · New car 2031
Taxes          Italy · Impatriati (2024) 2025–29        ⚠︎ 1
Assumptions    Equity 4,5% · Inflation 2%
Simulation     2.000 runs · 90% confidence
```

- **Work phases.** Each is a row. Tapping it opens an editor:
  - kind, dates and amounts;
  - a **regime picker** that offers only the regimes that fit (e.g. for self-employed in Italy: *Ordinario* or *Forfettario*);
  - the regime's options form, **generated from the regime's description** ([TAXES.md](TAXES.md#choosing-them-in-a-plan)), so a new regime needs no new screens.
- **Taxes.**
  - A residence timeline (country system + options per period).
  - Overlays (special regimes) with their years shown as a bar.
  - Overrides for what-if law changes.
- **Validation.** Issues appear on the section they concern:
  - ⚠︎ for warnings, e.g. "Impatriati doesn't apply to forfettario income: 2029 is lost";
  - ⛔︎ for errors that stop the plan from running.
- **Staying in view.** On iPhone, a small sticky pill at the top ("Earliest 54") keeps the answer visible while you edit. On the Mac, Inputs and Results are side by side, so results update next to the field you're editing.

### Comparing two plans

A window on the Mac (a pushed page on iPhone):

- both headlines;
- the two success curves overlaid (two series, direct-labelled);
- a table of key numbers.

| | Forfettario | Ordinario + impatriati |
| --- | --- | --- |
| Net income 2029 | 49.600 € | 45.800 € |
| INPS pension at 67 | 14.200 €/yr | 16.900 €/yr |
| Taxes, lifetime | 212.000 € | 238.000 € |
| Earliest retirement | 54 | 55 |

(The numbers are made up.) This is the screen for regime decisions.

## Import (Mac first)

A window with steps along the top, as described in [IMPORT.md](IMPORT.md):

1. **File.** A drop zone, or the result of dragging a file onto the app.
2. **Format.** The detected settings, each a picker with a live sample: encoding, delimiter, header row, decimal and thousands separators, date format, and whether empty cells are skipped.
3. **Columns.** A table: the column header, sample values, *Imports as* (Balance of…, Quantity of…, Price of…, Ignore), and a per-column format override.
4. **Accounts.** Names in the file matched to accounts (existing, new, or ignored), plus proposed closings.
5. **Preview.** The parsed grid with errors highlighted, counts (new, updated, identical, conflicting), and the conflict policy.
6. **Done.** A summary, **Undo import**, and **Save as profile**.

On iPhone, a CSV opened from Files goes straight to "Import with profile…": choose the profile, preview, import.

Ledger journals (one or several `.ledger`, `.journal`, `.hledger`, `.j` or `.dat` files) have their own steps in the same window:

1. **Files.** What was read: the files, transactions, dates, problems with their file and line, and includes the app can't read, with **Choose the Journal's Folder…**. The saved ledger profiles, best fit first.
2. **Accounts.** The ledger's assets and liabilities as a tree, each with a picker: as proposed (matched or new), a library account, a new account, or left out; the new accounts to create; closings; the income and expense accounts that are returns; month, quarter or activity snapshots.
3. **Commodities.** Each commodity as cash, an instrument (matched, new or chosen) or left out; the new instruments; whether `@` prices are recorded.
4. **Preview** and 5. **Done**, as for a spreadsheet, with the journal's notes (flows that couldn't be valued) instead of the grid.

On iPhone, journals use "Import with profile…" with a saved ledger profile, like a CSV.

## Settings

| Section | Contents |
| --- | --- |
| Library | Location (iCloud Drive or this device), Show in Files/Finder, sync status, merged conflicts, backups, the file format docs |
| You | Name, birth date, base currency, tax residence (the default for new plans) |
| Prices | Price source per instrument kind, API keys (stored in the Keychain), fetch on check-in |
| Check-in reminder | Day of the month and time. This device only, so you aren't reminded twice. |
| Privacy | Face ID lock, hide amounts on launch, hide amounts in the app switcher |

## Design system

**Look.**

- System components and Liquid Glass on iOS 26 and macOS 26: a floating tab bar and toolbars, sheets with detents, the sidebar and the inspector.
- Glass is only for controls that float above content (the tab bar accessory, floating buttons). Content (numbers, charts, forms) sits on plain surfaces, where it's most legible.

**Numbers.**

- The system font. Large standalone numbers use its default figures; columns that must line up (tables, check-in fields, axis labels) use tabular figures (`.monospacedDigit()`).
- Formatted for your locale and base currency: in Italian, `312.480 €`, with decimals only where they matter (check-in fields, account detail).
- Charts use compact numbers (`312k`).

**Changes.** Always a sign and an arrow as well as colour: ▲ +4.210 in the success-green text colour, ▼ −240 in red. Never colour alone.

**Colour in charts** follows the dataviz reference palette, in light and dark variants.

- **Asset classes** have fixed colours everywhere in the app. Their order is also the stacking order, from bottom to top, and was chosen to pass colour-blindness checks between neighbouring bands:

  | Cash | Bonds | Equity | Gold | Crypto | Real estate | Other | Debt |
  | --- | --- | --- | --- | --- | --- | --- | --- |
  | blue | orange | aqua | yellow | magenta | green | violet | red |

- **Everything else** is one hue (blue) with labels: allocation by account group, fan charts (the bands are lighter steps of blue), success curves.
- **Your actual history** is always drawn in ink, not a series colour, so "what happened" never looks like "what was projected".
- **Status colours** (warning, error) appear only with an icon and a label.

**Charts.**

- Swift Charts, with thin marks: 2 pt lines and rounded bar ends.
- Faint gridlines.
- Direct labels on the last point instead of legends, wherever there are four series or fewer.
- Every chart can be read by dragging across it (`chartXSelection`) and has a VoiceOver summary (`accessibilityChartDescriptor`).
- No dual axes. When two measures need comparing, they get two charts.

**Uncertainty** is always a band, never just the median. The words are "in 9 of 10 simulated futures", not "90% probability".

**Privacy.**

- An eye button hides every amount (`•••••`) while charts keep their shape.
- Amounts are marked `.privacySensitive()`, so widgets and the app switcher hide them when the device is locked.
- Optional Face ID lock.

**Accessibility.**

- Dynamic Type everywhere; the hero number scales too, up to a cap.
- VoiceOver labels read amounts properly ("three hundred twelve thousand euros").
- Reduce Motion turns off the number animations.
- Contrast checked in light and dark.

**Empty states and first launch.** Every empty screen has one clear next step. First launch runs:

1. Welcome.
2. Where to keep your data (iCloud Drive is recommended).
3. Birth date, base currency and tax residence.
4. "Import a spreadsheet" or "Add accounts".
5. The first check-in.
6. "Create your first plan" (a guided form covering work, spending and pensions).

**Haptics.** A light tap on save, and when a what-if slider moves the earliest retirement age.

## Widgets (M3)

- **Small:** net worth and its change.
- **Medium:** a 12-month sparkline and "Earliest retirement 54".
- **Lock screen:** "Retire in 15 y 6 m".

All widgets hide amounts when the device is locked.

## How it's built

- **State.** `@Observable` stores, created once and injected through the environment:

  | Store | Holds |
  | --- | --- |
  | `LibraryStore` | the in-memory library, edits, sync status, merged conflicts |
  | `PlanStore` | runs, cached results, recompute scheduling, headlines and baselines |
  | `CheckInStore` | the check-in draft, kept on the device until it's saved |
  | `PriceStore` | price fetching (wraps `PriceService`) |
  | `PrivacySettings`, `AppPreferences`, `AppNavigation` | hidden amounts, this device's settings, where you are in the app |

  An import in progress belongs to the Import screen.
- **Navigation.** One root view chooses between `TabView` (compact width) and `NavigationSplitView` (regular width and Mac). The screens themselves don't know which one they're in.
- **Folders.** `App/Sources/` holds `App`, `Stores`, `Navigation`, `DesignSystem` (colours, number formats, spacing, amount text, cards), `Components/Charts`, `Features/<Feature>` (Overview, Accounts, CheckIn, Plan, Import, Settings, Onboarding, Library) and `Preview`. [App/README.md](../App/README.md) describes them and the stores' APIs.
- **Chart components**, reused everywhere: `NetWorthChart`, `FanChart`, `SuccessCurveChart`, `IncomeStackChart`, `WaterfallChart`, `BreakdownBars`, `Sparkline`.
- **Previews.** Every screen has SwiftUI previews built from a made-up library in code, with the same numbers as the example library in the tests.
