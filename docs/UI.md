# UI

What the app looks like and how it behaves, on iPhone and Mac. It's built with SwiftUI on iOS 26 and macOS 26, using the system's Liquid Glass look.

## Who uses it, and when

The app has one user, and three situations to design for:

| Situation | Where | How often | What matters |
| --- | --- | --- | --- |
| **Monthly check-in** | Mostly iPhone | Monthly, about 5 minutes | Speed. Values are pre-filled, and only what changed needs a tap. It ends with this month's answer. |
| **Planning session** | Mostly Mac | A few times a year, 30–60 minutes | Inputs and results side by side, what-ifs a click away, comparing two plans. |
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
Check-in                       •     ← dot when due
Accounts
  All accounts                       ← the grouped list, with subtotals
  ▾ Cash                  12.990     ← a group, with its subtotal
      Conto deposito       8.200
      Conto Fineco      ◷  4.790     ← ◷ when the value is stale
  ▸ Investments           71.300     ← collapsed
  ▾ Crypto & gold         13.040
      Gold coins           9.640
      Ledger wallet        3.400
  ▸ Pension · Property · Debts
  ▸ Closed (1)                       ← collapsed at first
Plans
  Base case
  Part-time from 50
Library
  Import…
  Instruments
  Sync & backups
```

- **Accounts in the sidebar.** The accounts are in the sidebar itself, so an account is one click away and a group of one doesn't need a page of its own.
  - *All accounts* is the overview: the [list](#accounts), grouped, with subtotals and the closed accounts. Its rows open an account's detail with a back button.
  - Under it, a row per group that has open accounts (Cash, Investments, Crypto & gold, Pension, Property, Debts), with its subtotal on the right. It expands to the group's accounts: kind icon, name and value, with a small clock when the latest value is stale. Values and staleness are the same as in the list. *Closed (n)* expands to the closed accounts. Amounts are left out while they're hidden.
  - Clicking a group, or its disclosure triangle, expands or collapses it; groups aren't pages. They start expanded and *Closed* collapsed, and the device remembers which are collapsed, here and on *All accounts* alike ([Accounts](#accounts)).
  - Selecting an account shows its detail in the content area; the arrow keys move from account to account. Opening an account from elsewhere in the app selects its row and expands its group.
  - The sidebar follows the library, also when it changes on the other device: a new account appears under its group, a selected account that's closed moves under *Closed* and stays selected, and one that's deleted gives way to *All accounts*.
- **Settings** is the standard Settings window (⌘,).
- **Menu commands:**

  | Command | Shortcut |
  | --- | --- |
  | New Account | ⌘N |
  | New Check-in | ⌘K |
  | Import… | ⌘⇧I |
  | Recalculate | ⌘R |
  | Save Baseline | ⌘⇧B |
  | Hide Amounts | ⌘⇧H |
  | Show Future | ⌘⇧F |
  | Duplicate Plan | ⌘D |
  | Compare Plans | ⌘⌥C |

- **Drag and drop:** dropping a CSV, or ledger journals, anywhere on the window starts an import.
- **Windows:** plan comparison and import can open in their own windows.
- **Window size (Mac):** the window opens at 1200 × 800 and can be made as small as 900 × 600. Every page scrolls, with what's pinned to it (the plan's What-if, the import's column settings) scrolling too when there's no room, so no page makes the window taller than the screen.

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
│ 3Y ▾   [Total│By asset class]   Future ◯ │
│ ┌──────────────────────────────────────┐ │
│ │                          ╱‾‾╲__╱‾    │ │
│ │              ___╱‾‾‾‾‾‾‾‾            │ │
│ │ ____╱‾‾‾‾‾‾‾‾                        │ │
│ └──────────────────────────────────────┘ │
│                                          │
│ ┌ Since last check-in ─────────────────┐ │
│ │ ▲ +4.210 € since 31 Aug              │ │
│ │ 308.270 € → 312.480 €                │ │
│ │ Markets    │▇▇▇▇▇▇▇▇▇      +2.950 €  │ │
│ │ New money  │▇▇▇▇▇          +1.500 €  │ │
│ │ Other     ▇│                 −240 €  │ │
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
  - **One row of controls above it:** the time span, *Total / By asset class* and *Future*. On iPhone the row gets shorter words and icons so it fits.
  - By default, a single net-worth line with a light fill. *By asset class* switches to stacked areas, with debts below the zero line, and a legend in its own row above. Like retirement income, each class is a light wash of its colour with a 2-point line along its edge (the top, or the bottom for debts) and a 2-point gap between neighbours, never a solid block.
  - Drag across it to read any month: a vertical rule with a callout showing the date, the total and the breakdown; over the projection, its median and bands.
  - **Future** continues the chart into the active plan's projection: a dashed median with a darker 25–75% band and a lighter 10–90% band, plus markers for retirement, pension starts and the like. See [PROGRESS.md](PROGRESS.md#past-and-future-m2).
    - The projection is a total, so with *Future* on the past is the total line too; *By asset class* is for the past alone (it's greyed out, and the caption says so).
    - The value axis fits the history, the median and the 25–75% band. The 10–90% band may run off the top, and the legend says "↑ 10–90% continues above".
    - A short caption under the chart ("Plan assets, then Base case's projection, in today's money.") with an ⓘ that opens the full explanation.
  - **Time span.** One menu sets how far back and, with *Future* on, how far ahead: *History* last year, 3 or 5 years, or all of it; *Future* to retirement, retirement + 15 years (the default), 20 years or the whole plan, never past the plan's end. Once retirement is behind you, the retirement-based choices give way to 20 years. The menu's label says both ("3Y · retirement +15"). The choice is remembered on the device and shared with the plan's "Your money over time".
  - **Old prices.** When a value in the chart uses a price more than 31 days older than its date, a note under it says so: "10 values in the chart use a price more than 31 days older than their date (Gold coins)." with *Fill In Past Prices…* (see [Instruments](#accounts)).
  - **Partial totals.** Net worth adds up what can be valued. Where a total misses something (a price or an exchange rate, or an account with no value yet), the line is dashed and grey, the callout says "Partial: some values are missing", and a note under the chart says what and when: "Where the line is dashed, the total is partial: exchange rates for US$ are missing for Jun 2018 – Dec 2021 (US brokerage) and 3 accounts have no value yet for Jun 2018 – Sep 2025 (Directa, Fondo pensione and Old bank)." with *Fill In Past Prices…* when some of it is prices or rates.
- **Since last check-in.** A headline, "▲ +4.210 € since 31 Aug", the totals before and after in words, and a bar each for markets, new money and other, from a shared zero line and to the same scale: gains go right in the positive colour, losses left in the negative one, with their signed amounts in a column of their own. It's the most useful single number after the total, because it separates "I saved" from "markets moved". (It used to be a waterfall, whose bars from zero made the totals huge grey blocks and the changes slivers on top.) While amounts are hidden, the headline shows the change in per cent and the bars keep their proportions.
- **Can I retire yet?** The plan's headline, progress toward financial independence, and how you compare with the latest baseline. Tapping it opens the Plan tab. It shows the main plan's latest results, or else the answer recorded at the last check-in, dated; it never starts a calculation. While one is going (a check-in's, or one started on the Plan screen) it says how far along it is, and results that no longer fit the plan or your data say "Calculated before your latest changes".
- **Needs attention.** Only shown when something needs you: stale accounts (not one that holds nothing: see [Accounts](#accounts)), accounts with problems in their trades, prices that couldn't be fetched, sync conflicts that were merged, and plan warnings. An account whose trades have problems (more sold than held, an opening without a cost, a statement that differs from the trades: the notes its page shows) gets one item that opens it: "Directa: 2 problems with trades · More sold than held · VWCE differs from the statement. Open the account to fix them." Prices and exchange rates missing on past month ends get an item each, which opens *Fill In Past Prices*: "Past exchange rates for US$ are missing · US brokerage isn't fully counted in your net worth for Jun 2018 – Dec 2021. Fill in past prices to fetch them."
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
- **Accounts that record trades** ([TRADES.md](TRADES.md#check-ins)). The row shows what the trades hold on the date, read-only, valued at the check-in's prices ("423 VWCE · from trades"), and records only the cash:

  ```
  ┌──────────────────────────────────────────┐
  │ Directa                 59.455,80 €   ●  │
  │   VWCE  423 × 139,80          59.135,40  │
  │         +10,5 since 30 Sep · from trades │
  │   Cash  [    320,40 ]                    │
  │   was 57.410,35 · new money +1.458,10    │
  │   deposits +1.450,00 · cash diff. +8,10  │
  │   ⊕ Add Trade…                           │
  └──────────────────────────────────────────┘
  ```

  - The cash is pre-filled with what the trades give. Typing another amount is fine: the difference counts as money added or taken out that no trade records.
  - The new money is the deposits, withdrawals and transfers recorded as trades since the previous value, and what was bought or sold paid from outside the account, plus that cash difference; the line under it shows the split ("deposits +1.450,00 · paid from outside +1.200,00 · cash diff. +8,10").
  - *Add Trade…* opens the trade sheet dated on the check-in's date. Once it's saved the row follows: the positions, the pre-filled cash and the new money are worked out again, and a cash you typed stays.
  - *Unchanged* (and *Mark rest unchanged*) means as the trades say: the cash they give.
  - *Compare With a Statement* (long-press, or right-click on the Mac) fills in the trades' quantities to correct from a broker statement. They're saved with the value as a check, not as holdings; the review lists where they differ: "The statement on 31 Oct shows 425 VWCE; your trades give 423. Add the missing trade, e.g. a buy or a transfer in." with *Add Trade…*.
  - On the Mac, the positions are read-only sub-rows (Last and Now are quantities), then the cash, then *Add Trade…* with the split.
- **New money (flow).** Shown under each account, filled in by the defaults in [PROGRESS.md](PROGRESS.md#data-this-needs-from-day-one), and editable. For pension funds the app asks for "contributions since …".
- **Keyboard.** A decimal keypad in your locale's format, with ▲ ▼ buttons above it to move between fields. Amounts accept `1.234,56` and `1234.56`. For a debt, type what you owe (`1.200` is recorded as −1.200); if it's in credit, e.g. an overpaid card, type `+` first (`+20`), or use ± above the keypad. *Update value* and a new account's opening balance work the same way.
- **Draft.** An unfinished check-in is saved as a draft on the device and never half-written to the library. Close the sheet, come back later, and continue.
  - The draft follows the library: when you come back, when the other device changes something, and just before saving. Accounts you haven't reviewed take their latest values, new accounts appear and closed ones leave; what you entered stays.
  - If the other device saved a different value on the same date for an account you entered, a banner says so and the review asks: *Keep saved* or *Use mine*. Until you choose, the saved value stays and yours isn't written.
  - The draft is deleted only once the check-in is in the library's files. If saving fails, the error is shown and the draft stays.
- **Review screen.**
  - The new net worth and the change since the last check-in: a headline and a bar each for markets, new money and other.
  - Changed accounts, and anything unusual, e.g. a quantity that went down (did you sell?) or a value that changed more than 30%.
  - Then **Save**.
- **After saving.** The confirmation shows as soon as the check-in is written. The main plan then runs to record this month's answer (only for the latest check-in: see [Adding history](#adding-history)), and the answer card shows its progress ([Calculating](#calculating)) in the meantime, the same as on the Plan screen, without a Cancel button. Then it ends with the answer:

  > Saved · Net worth 312.480 € (▲ 4.210)
  > Can I retire yet? Not yet: earliest at **54**, unchanged since August.

  This is the monthly moment the app is built around, and the one time a plan runs without a button: recording the month's answer is what the check-in is for. *Done* can close the confirmation while it runs; the answer is still recorded.

**On the Mac**, the check-in is a table, and the whole thing can be done without touching the mouse:

- columns: Account, Last, Now, Change, New money, Note;
- Tab and Return move between cells;
- ⌘↩ saves.

## Accounts

- **List.** Grouped: Cash, Investments, Crypto & gold, Pension, Property, Debts. On the Mac and iPad it's *All accounts* in the sidebar, which also lists each group's accounts under it ([Navigation](#navigation)).

  ```
  Accounts                                  +
    9 accounts · Net worth 312.480
  Cash                         12.990  ⌄         ← tap a header to collapse it
    Conto deposito    ╱‾╲_╱     8.200  ›
    Conto Fineco  ◷   _╱‾‾      4.790  ›         ← ◷ "Stale"
  Investments                  71.300  ›         ← collapsed: the header alone
  Crypto & gold                13.040  ⌄
    Gold coins        ‾‾╲_      9.640  ›
    Ledger wallet     _╱‾╲      3.400  ›
  …
  Closed (1)                           ›         ← collapsed at first
  ```

  - Each group's header shows its name and subtotal.
  - Each row shows a kind icon, the name, the institution, the value, a sparkline of the last 12 months (in the account's own currency, with gaps where a value can't be worked out), and a "stale" badge when needed.
  - **Stale** means the latest value is older than the threshold (45 days by default). An account that holds nothing (a zero balance, or no cash and no quantity) has nothing to check in, so it's never stale: not in the list, the sidebar, its detail or *Needs attention*.
  - Swipe actions: *Update value* (a one-account valuation) and *Close*. Saved as it is, *Update value* records the account as unchanged; an account with no earlier value needs a value typed, and an emptied field isn't zero (type 0). Its date can be any day up to the closing date (or a year from today), also before the account opened: see [Adding history](#adding-history). An account that records trades offers *Add trade* instead; its *Update Cash…* (in the context menu) shows the holdings from the trades, read-only, and records the cash.
  - Closed accounts sit in a "Closed (3)" section at the bottom.
  - **Collapsing.** Tapping a group's header, or *Closed*'s, collapses the group to its header (name and subtotal) or expands it again, with an animation; the chevron at the right of the header points down while it's expanded. The groups start expanded and *Closed* collapsed. The device remembers which are collapsed, and the sidebar shares them: collapsing Cash on *All accounts* collapses it in the sidebar too, and the other way round.
  - **Search** (by name, institution, kind, tags or notes) shows every group expanded while there's a query, so no result is hidden. Clearing it brings back the collapsed ones.
- **Account detail.**
  - **In the account's own currency.** The value, its change, the chart and the values list are in the account's currency, which needs no exchange rate: a dollar account in a euro library shows `0,00 US$`. Under the value, its value in the base currency at the day's rate, or "Value in EUR: rate missing".
  - The value and its change since the value before, with the year when it isn't this one: "▼ −123.959,00 US$ since 30 Nov 2021", then its parts (markets, new money, other). A change that shows as zero has no arrow and no sign.
  - A history chart. New-money events are small ticks in a lane along the bottom, pointing up for money added and down for money taken out, coloured by sign, so jumps you caused are distinguishable from market moves; they never stretch the value axis, and the callout gives their amount. The value axis always includes zero, with round ticks that read apart, even for an account that's been at zero. The callout stays inside the chart.
  - A value that can't be worked out (a price missing, or the rate for a position priced in another currency) is a gap in the line, never a zero. A note under the chart says what's missing and when, with *Fill In Past Prices…*: "Some values can't be shown: prices for Gold coins are missing for Mar 2023 – Sep 2025." For an account in another currency, it also says when net worth leaves it out: "Net worth leaves out this account's values for Jun 2018 – Dec 2021: exchange rates for US$ are missing." As on the Overview, a note points out values that use a price more than 31 days old.
  - **Empty accounts.** Once an open account has held nothing for longer than the staleness threshold, it isn't called stale; instead: "This account has been empty since 1 Jan 2022. Close it?" with *Close Account…*, which opens the Close sheet on that day.
  - For accounts with holdings, the positions: quantity, price, value, purchase cost and unrealised gain.
  - The list of valuations, each editable: date, value, new money, note. *Add Past Value…* adds one on an earlier date.
  - An info section: kind, institution, country, currency, tax wrapper, how it's recorded (a balance, snapshots of positions, or trade history), and whether it's included in net worth and plans.
  - A holdings account offers *Switch to Trade History…* next to *Close Account…*: see [Trade history](#trade-history).
- **Add account.** A sheet:
  1. Pick a kind from a grid of icons.
  2. Enter the name, institution, currency, country and opening date. The opening date is today by default; the hint says "Set it to when you opened the account, to add its history." The opening balance is the one on that date.
  3. For a brokerage, crypto or metals account, choose **Track: Trade history / Monthly snapshots**. Trade history is the default: "Record each buy, sell and dividend: holdings, average cost, gains and income follow from them." Snapshots: "Type the quantities and cash at each check-in; no trades to keep."
  4. Enter the positions (choose or create instruments) or the balance, which becomes the first valuation. For trade history, each position becomes an *opening* trade on the opening date, with what you paid as its purchase cost, and the cash becomes the first value.
  5. The tax wrapper is pre-selected from the kind and your residence, through the tax registry: your residence's system (the one for that country, else `generic`) gives a current account its first taxable wrapper, a pension fund its first tax-advantaged one (e.g. `it.pensionFund`), and a TFR its severance-pay wrapper. The picker lists your residence's wrappers first, then other countries', then the generic ones ("Pension fund (Italy)", "Tax-deferred"), so a country's system brings its wrappers when it's registered.
- **Close account.** A sheet asks for:
  - the closing date;
  - "Where did the money go?", which sets the successor account;
  - a short explanation: the account keeps its history, stays in every chart up to that date, and leaves check-ins.

  Reopening is one button. Deleting is for mistakes only, sits at the bottom in red, and asks for confirmation.
- **Instruments** (under Library on the Mac, and from an account's positions on iPhone): name, ISIN or ticker, currency, unit, asset mix, taxes, and price source. **Taxes**, for an ETF or fund: the fund type, *Automatic (equity fund)* from the asset mix as typed (more than half equity is an equity fund, more than half real estate a real-estate fund, a quarter or more equity a mixed fund, anything else another fund, as the planner works it out) or one chosen when the mix doesn't say (equity, mixed, real-estate, foreign real-estate, other); for an ETC, *Right to delivery of the metal*. Some countries tax them differently. Each row shows the latest saved price with its date and source, with a small clock when it's older than the staleness threshold. A footer says: "Prices are also fetched at every check-in. Net worth uses the price on or before each check-in's date. Fill In Past Prices fetches those missing for earlier dates."
  - **Update Prices** (toolbar; pull down on iPhone) fetches today's price of every instrument an open account holds that has a price source, and the FX rates that value them in the base currency, and saves them for today in one edit. A banner shows the progress, then the outcome; *Details* lists each instrument as updated, unchanged, failed (with the reason) or kept. A failure doesn't stop the others. A price typed in by hand for today is kept, as in the check-in, unless you choose *Update* on its row. Instruments typed in by hand or not held in an open account are skipped; a row's *Update Price* fetches one anyway.
  - **Set Price…** (on a row, or in the editor) types a price in by hand: the date (today by default), the amount, and the currency (the instrument's by default). It's saved as a `manual` price, which *Update Prices* doesn't replace.
  - **Fill In Past Prices…** (toolbar; the overflow menu on iPhone) fills in the past: every date a position is valued on without a price for that day (each value, and the month ends it carries over to in months without one of its own), the exchange rates those dates need, and the missing inflation months.
    - A sheet lists what's missing: each instrument with where it comes from, its date range and count ("Gold coins · gold-api.com · XAU · Oct 2015 – Sep 2026 · 132 dates"), then the rates and inflation, then **To type in**: instruments without a price source.
    - **Fill In** fetches with a progress bar: each instrument's whole range is one request, then one per currency and index ([PLAN.md](PLAN.md#prices-and-fx)). Metals' past prices come from their futures on Yahoo Finance (`GC=F` for gold), within about 1% of spot; crypto older than CoinGecko's free year from Yahoo's pairs (`BTC-EUR`).
    - Then each line shows how many dates it got and from where: "12 of 12 · Yahoo Finance · GC=F (history)", or "CoinGecko · ethereum back to Oct 2025, Yahoo Finance · ETH-EUR (history) before". What's left is listed with its dates and the reason, never skipped: *Set Price…* opens on one of its dates, and *Choose a Price Source* (or *Change Price Source*) opens the instrument's editor; *Check Again* fills in again after that.
    - The records are saved in one edit into their month files, after a `fill-history` backup. Nothing already saved is replaced: not a price typed in, not one from an import or a journal, not one fetched before.
  - The editor's *Test price fetch* saves nothing by itself. For an instrument that exists, a successful test offers *Save price*; a new instrument's tested price is saved with the instrument. The symbol's placeholder follows the source: "Yahoo ticker, e.g. VWCE.DE", or for CoinGecko "e.g. ETH or ethereum" (a ticker or a CoinGecko ID).

## Adding history

Accounts added in the app open on the day they're added, unless you set an earlier opening date. Their past values can be added three ways, without an import file.

- **A past check-in.** Pick an earlier date in the check-in's date panel.
  - The accounts open on that date are listed as usual. Accounts that open after it are listed last, under **Opened later** (collapsed on iPhone). They're optional: never counted as missing, *Mark rest unchanged* leaves them alone, and left empty they change nothing.
  - A value entered for one of them moves the account's opening date back to the check-in's date when it's saved. The row says so ("Saving moves its opening date to 31 Mar 2024."), and the review lists the accounts whose opening date will move.
  - Prices and FX rates are fetched for that date: Yahoo Finance and Frankfurter (ECB) have history, CoinGecko about the last year on its free API, and Yahoo Finance's pairs (`BTC-EUR`) before that. gold-api.com only has today's price, so a metal's price comes from its futures on Yahoo Finance, and the price list says so: "Yahoo Finance · GC=F (history)". Only when no source has one does it say "No history for this date: type the price."
  - Values saved after the date stay as they are, and a banner says it's a past check-in.
- ***Update Value* with a past date**, or ***Add Past Value…*** on the account's list of values, which starts on the month end before the first value, so an account fills in a month at a time. Any date up to the closing date works. Before the opening date the sheet says "Saving moves the opening date from 30 Sep 2026 to 31 Mar 2024." and moves it in the same edit. Moving a value earlier in the valuation editor does the same.
- **Import.** For existing accounts, the import's *Accounts* step links the names in the file to them, and the profile remembers the match. Values from before an account's opening date propose to open it on the first of them, applied unless you reject it ([IMPORT.md](IMPORT.md#matching-accounts-and-instruments)).

**Past prices.** Whichever way history arrives, its positions only have the prices it brought: a journal's `@` costs and `P` lines, a spreadsheet's price columns, what a past check-in fetched. Gold bought years ago would otherwise stay at its purchase price in every month since. *Fill In Past Prices…* fetches the rest ([Instruments](#accounts)); the import's Done step offers it ("12 past values have no price for XAU"), and so does a note under a chart that uses old prices.

**A pension fund's joining date** (`tax.joined`, which sets the payout tax: 15%, falling towards 9% with the years of membership) is the opening date when the fund is added. Wherever the opening date moves (these three ways, or the account form), the joining date moves with it if it was the opening date; one set to another day stays.

**New money after an inserted value.** A value's new money (its flow) is measured from the value before it. When a value is added before another one of the same account, or one is corrected, moved or deleted, the next value's new money is worked out again if it was automatic (the default for the account's kind, as the check-in fills it in), and kept if it was typed in. *Update Value* and the valuation editor say which before saving; a past check-in follows the same rule. A value added before an account's first one turns that first value's automatic new money (the whole amount) into the change since. An import follows the same rule for the library's values after the ones it adds or changes: its Preview says how many, and undoing the import puts them back. A journal's own valuations keep the flows the journal gives them ([IMPORT.md](IMPORT.md#preview-conflicts-and-undo)).

**Answers and baselines are only recorded for the latest check-in.** The plan runs on today's data, so re-running it for a past date would record made-up history in "Your answer over time" and a made-up "Start of <year>" baseline. A check-in dated before the library's latest one records neither, and its confirmation says: "Saved a past check-in (31 Mar 2024). The answer isn't recorded for past dates."

## Trade history

A brokerage, crypto or metals account can record its **trades** instead of monthly snapshots of its positions ([TRADES.md](TRADES.md)): its holdings, average cost, cash, realised gains and income follow from them, and its check-ins record only the cash. New accounts of those kinds record trades by default (see *Add account*); existing ones can switch.

**Account detail** of an account that records trades, top to bottom:

```
┌──────────────────────────────────────────┐
│ Directa                            +  ✎  │
│ 57.410,35 €   ▲ 1.318,92 since 31 Aug    │
│ ┌ history chart, deposits as ticks ────┐ │
│ ⚠︎ VWCE differs from the statement       │
│   The statement on 30 Sep shows 424,5    │
│   VWCE; your trades give 414,5. Add the  │
│   missing trade, …        Add Trade…     │
│ HOLDINGS                                 │
│ Vanguard FTSE All-World     57.098,25 €  │
│   412,5 sh × 138,42 EUR   99% of account │
│   Average cost 116,85 €  ▲ 8.898 ▲ 18,5% │
│ Cash                           312,10 €  │
│ Total                       57.410,35 €  │
│ TRADES                                   │
│ ⊕ Add Trade…          20 trades Filter ▾ │
│ AUGUST 2026                              │
│ ⊕ Buy · 10 VWCE × 134,75   −1.352,50 €   │
│ ↓ Deposit                    +200,60 €   │
│ JULY 2026                                │
│ ⊖ Sell · 8,5 VWCE × 144,56 +1.162,80 €   │
│                         gain +234,42     │
│ …                                        │
│ INCOME & GAINS                           │
│ 2026   Realised gains · Dividends ·      │
│        Interest · Fees · Taxes · Net     │
│ CASH AT CHECK-INS · DETAILS · …          │
└──────────────────────────────────────────┘
```

- **Holdings**: per instrument, the quantity, average cost (*costo medio*: what was paid per unit, fees included), value, unrealised gain (amount and %) and its share of the account; then the cash and the total. On the Mac, a grid with those columns.
- **Trades**: grouped by month, newest first; each row shows the type's icon, what it was ("Buy · 10 VWCE × 134,75", with the price's currency when it isn't the account's), the date and note, and the cash it moved, with a sale's realised gain. A trade paid from outside the account shows what was paid or received, marked "paid from outside" (a sale: "proceeds paid out"); on the Mac the mark leads its note. *Filter* shows one instrument or one type. Tap a trade to edit it; swipe or long-press to delete it (the confirmation says what deleting brings in, e.g. a later sale now selling more than is held). On the Mac, a table (date, type, instrument, quantity, price, amount, note) as long as its trades, which scrolls with the page: double-click edits, right-click edits or deletes.
- **Income & gains**, by year: realised gains, dividends, interest, fees and taxes, and the net; a sale whose cost is unknown is left out and said so. In the account's currency.
- **What needs a look**, as banners with the fix: a trade missing a price or amount, a sale of more than was held, an opening without cost, a missing exchange rate, a trade outside the account's dates, a value with a balance (which isn't used), and a statement that differs from the trades ("The statement on 30 Jun shows 12 VWCE; your trades give 10. Add the missing trade."). Each banner's button opens the trade, a new trade on the statement's date, or the value. The Overview's *Needs attention* points to an account with any of these ("Directa: 2 problems with trades").
- **Cash at check-ins**: the account's values, which record its cash. The history chart, the header's change and the new-money ticks come from the Valuator (deposits and transfers on their own dates).
- The toolbar's **+** adds a trade; *Update Cash…* records the cash on a date; *Switch to Snapshots…* sits next to *Close Account…*.

**Add Trade** (and *Edit Trade*) is a sheet:

- **Type**: Buy, Sell or Dividend as segments, and *More ▸* for interest, fee, tax, deposit, withdrawal, transfer in and out, split and opening (a chosen one shows as a fourth segment). Each type shows only its fields; editing a trade keeps showing any field it has.
- **Date**, and for most types the **instrument**: the library's instruments, or *New Instrument…* (the instrument form, in a sheet).
- **Quantity, price and currency** (the instrument's by default). The library's price for the date is a hint with *Use* ("The library's price that day: 138,42 EUR", or the latest before it); *Fetch Price for This Date* asks the instrument's price source.
- **Fees and tax** (a buy's transaction tax, or tax withheld), in the account's currency.
- **Amount**: worked out live as −(quantity × price × FX) − fees − tax for a buy, quantity × price × FX − fees − tax for a sale, and shown as the field's placeholder with "Computed …" (with the rate used when the price is in another currency). Type the broker's amount when it differs (their rate, rounding): the typed amount wins, and the hint shows what was computed, with *Use Computed*. Amounts are typed as positive numbers; the type gives the direction (a buy's *Paid*, a sale's *Received*, a fee's *Charged*).
- **Paid from outside this account** (a buy, a fee or a tax) or **Proceeds leave this account** (a sale), a switch at the top of the amount ([TRADES.md](TRADES.md#paid-from-outside-the-account)): gold bought from a dealer and paid from the bank, a sale paid into the bank. On, the account's cash doesn't change and the amount counts as new money (a line under the switch says so). It's on by default for a metals account and for a trades account that has never held cash (no value with cash, no deposit, no sale whose proceeds stayed), and off otherwise. When it's off and a buy, fee or tax would take the cash below zero on its day, a hint says so with a one-tap switch: "Cash would go to −1.200,00 €. Paid from outside this account?" *Paid from Outside*.
- **Note**.
- Numbers read as in the check-in (`1.234,56` or `1234.56`). Problems show under their field: a number that can't be read at once, what the type needs (a buy without a price or an amount) after *Save* is tried, and warnings (a sign that contradicts the type) as they come.
- **After saving** shows what the edit will change: the cash it moves (for a trade paid from outside: "Cash: Unchanged" and its "New money +1.200,00") and the cash after that day, the quantity held after it, a sale's realised gain, the opening date moving back ("Saving moves the account's opening date from 1 Mar 2021 to 15 Jan 2021."), the new money of later values worked out again (or kept when typed), and problems it brings in (a later sale now selling more than is held).
- *Save* waits for the write; *Delete Trade…* sits at the bottom when editing.

**Switching an account.** *Switch to Trade History…* on a holdings account, and *Switch to Snapshots…* on a trades account, open a sheet with a preview ([TRADES.md](TRADES.md#converting-an-account)):

- what it writes, in a sentence, and the months it changes ("12 months, Oct 2025 – Sep 2026");
- to trades: the opening positions, the buys and the sales inferred from the changes in quantity, each with its date; the estimates, counted and expandable ("11 buys and sales are estimates, priced at their value's price.", "1 opening position has no recorded cost: its cost is its value on that day."); for an account that has never held cash (coins, a wallet), a note that its buys and sales are paid from outside it, so its cash stays at zero;
- to snapshots: a warning that each trade's detail is lost (its date, price, fees, and the income and realised gains worked out from it), and the values it adds on a month's last trade;
- the months' files are backed up first, as for an import, so the switch can be undone from *Sync & backups*. Values and new money stay the same either way.

## Plan

A plan picker sits at the top (Base case ▾, with New, Duplicate, Compare, Rename and Delete), then three parts: **Results**, **Progress** and **Inputs**.

### Calculating

A plan is calculated only when you ask: *Calculate*, *Recalculate* (⌘R, and a toolbar button on the Mac), *Run What-If*, or a check-in recording its answer. Opening a plan, editing an input, moving a what-if slider or choosing another age for the charts runs nothing; the screen says what's out of date instead. Each plan keeps its own results, what-if and chosen age while you switch between plans.

- **Before the first calculation.** The answer recorded at the last check-in, dated ("Recorded at the check-in on 30 Sep 2026", and "before the plan's latest changes" when the plan was edited since), with "Calculate the plan to see its charts." and **Calculate**. With nothing recorded either, a sentence on what calculating does ("simulates 2.000 possible futures… takes a few seconds, and runs only when you ask") and **Calculate**.
- **Out of date.** Results stay on screen, slightly dimmed, under a banner that says why and offers the button that brings them up to date:

  ```
  ┌──────────────────────────────────────────┐
  │ ◷ Out of date                            │
  │   Inputs changed since this was          │
  │   calculated.             [↻ Recalculate]│
  └──────────────────────────────────────────┘
  ```

  - *Inputs changed since this was calculated.*: the plan was edited (a rename doesn't count). Recalculate.
  - *Your accounts or prices changed since this was calculated.*: the library data the plan reads changed, e.g. a check-in or new prices. Recalculate.
  - *What-if values changed since this was calculated.*: a slider moved. Run What-If.
  - *Calculate to see the charts for retiring at 57.*: another age was chosen on the success curve. Calculate.

  Results calculated before for exactly the current inputs, e.g. after changing an input back, show again at once, without a run.
- **Calculating.** While a calculation runs, its progress replaces the banner, and the old results stay underneath, dimmed:

  ```
  ┌──────────────────────────────────────────┐
  │ Calculating…                    [Cancel] │
  │ Earliest age · ages 38–75: 12 / 38       │
  │ ▇▇▇▇▇▇▇▇▇▇░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  │
  │ Overall                             29%  │
  │ ▇▇▇▇▇▇▇▇▇▇░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  │
  └──────────────────────────────────────────┘
  ```

  - The phase and its own bar, in the locale's numbers with tabular figures: "Earliest age · ages 38–75: 12 / 38" (most of the time: the chance at every age), "Simulating 1.234 / 2.000 runs" (the chosen age in detail), "Sustainable spending: step 4 / 16", "Summarising". Then the whole calculation's bar. A what-if's first pass says "Quick estimate…".
  - **Cancel** stops it; the old results stay as they were (and out of date). A check-in's calculation can't be cancelled here: it says "Working out this month's answer…".
  - Editing an input while it runs lets it finish: its results then show as out of date, with Recalculate. Cancelling instead would throw away a calculation you asked for, while it's usually seconds from done.
  - The same view shows on iPhone and Mac, in Compare and in the check-in's confirmation. The header of the answer says "Calculating 29%" meanwhile, and the iPhone pill shows a small bar.

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
│ 100% ┤                 ●━━━━━━━━━━━━━━━━━│
│  90% ┤┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄╱┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄│
│      ┤      ___╱‾‾‾‾‾‾     90% confidence│
│   0% ┼━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
│       40   45   50  54   60   65   70  75│
│                                          │
│ Your money over time · retiring at 54    │
│ 3Y · retirement +15 ▾                    │
│ — Actual — Median ▓ 25–75% ░ 10–90% ↑    │
│      ⚑ fund 57    ⚑ inheritance 62       │
│  ⚑ retire 54           ⚑ INPS 67         │
│ ━━━━━━━░░░░▒▒▒▒▓▓▓▓━━━━▓▓▓▒▒▒░░░░░░░░░░░ │
│                                          │
│ Retirement income · median  Income│Taxes │
│ ▇ Withdrawals ▇ INPS ▇ Pension fund ▇ Tax│
│  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░          │
│  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ Spending  │
│  ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇           │
│   2045      2055      2065      2075     │
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
  - One line; a dotted rule at your confidence level, labelled at its right end, below the rule where the curve ends above it; the earliest age marked where they cross.
  - The age axis runs from today's age to the last age simulated, labelled every 5 years (every 10 when narrow), never from 0.
  - Tapping another age makes it the selected age for the charts below. Charts calculated before for that age show at once; otherwise the banner offers *Calculate* for it.
  - Steps caused by pension eligibility (e.g. at 64 or 67) show as steps, with a note explaining why.
- **In the plan's currency.** Every amount, chart and caption is in the currency the results were calculated in: the plan's own, else the library's base currency ("In today's CHF.").
- **Your money over time.**
  - A fan chart in one hue: the median line, a darker 25–75% band and a lighter 10–90% band, with its legend in a row of its own above it.
  - Your actual past values are drawn as a solid line in ink (not the plan's colour) to the left of today, in the plan's currency: each check-in converted at the library's exchange rate on its date, then into today's money where the library has an inflation index for that currency (Eurostat's HICP for the euro; otherwise in the money of each date). Check-ins without a rate are left out, with a note: "Your actual values leave out 3 check-ins without a EUR–CHF exchange rate (Mar – May 2024): add the rates to see them."
  - **Time span:** the same menu as the Overview's (and the same remembered choice): how far back, and how far ahead, retirement + 15 years by default, so the years around retirement aren't a sliver of a chart running to 95.
  - The value axis fits your history, the median and the 25–75% band; the 10–90% band may run off the top, and the legend says so.
  - Markers above the data: retirement, when locked money becomes accessible, pension starts, windfalls and large expenses. Labels that would collide go in a second row; a marker without room in either shows its icon, and its label is in the callout.
- **Retirement income.**
  - Stacked areas, one flat step a year, by source: withdrawals, work (the year you retire), the plan's first public pension (e.g. INPS), other pensions, pension savings drawn as needed, windfalls, and **lump sums and payouts**, then the taxes they pay in grey on top. Lump sums and payouts are money paid whether it's needed or not: a pension's lump sum in the year it's claimed (a route that takes part of it as capital), severance pay when a job ends (Italy's TFR), and what a wrapper's rules pay out (the whole balance at an age, or spread over a few years); the app recognises them by the scheme's claim and the wrapper's rules, not by name, and keeps them apart from withdrawals. Pension savings and lump sums are labelled by their source when there's one ("Pension fund", "TFR", "BVG lump sum"), else as a group. The spending target is a dashed line, labelled "Spending" at its end, outside the areas. Years are labelled every 5 or 10.
  - *Why the taxes are on top:* the planner reports income before tax. A withdrawal is what's sold: it pays the tax on the sale and the previous year's wealth tax as well as the spending, so in a rich run's later years it can be twice the spending. So that the chart reads against the spending line, each source is shown after its share of the year's taxes (in proportion), and the taxes paid from the year's income are the grey band: the sources reach the spending line (plus expenses and what's saved), the stack the income before tax. The year the money runs out falls short of the line. Taxes on rebalancing are paid inside the portfolio; *Taxes* shows them.
  - A one-off (a windfall, the TFR) that would flatten the rest runs off the top, with a note under the chart: "Inheritance in 2050 (150k €) runs off the top."
  - *Taxes* switches to the same years stacked by tax line: IRPEF, addizionali, the tax on gains, and the 0.2% wealth tax.
- **When it fails.** A sentence or two about the failing runs, including bridge failures, i.e. running out before locked money opens.
- **How the plan reads your library.** A line per bucket: the accounts of one tax wrapper, their value on the start date, and how they're drawn ("Drawn any time · new savings go here · Conto Fineco and Directa", "Drawn as its tax rules allow · Fondo pensione"); then the accounts whose value starts a pension scheme instead of being money to draw on ("BVG starting balance: Pensionskasse: its value on 30 Sep 2026 is where the pension starts"), or isn't used because the plan sets the pension's starting balance itself.
- **Problems** are worded for the screen: schemes, accounts and ways to claim by their names, not their IDs ("This contribution goes into BVG, but the plan has no BVG pension to pay it out: add one under Pensions.", "BVG never offers “Capital” in the plan's years, so it isn't paid.").
- **What if.**
  - Sliders for retirement age, spending, saving and equity return. On iPhone they're in a bottom sheet; on the Mac, in the inspector.
  - Moving a slider runs nothing. The answer next to the sliders says "From before your what-if changes" until **Run What-If** runs it: a quick estimate with fewer runs first, then the full 2,000, with the same random draws, its progress under the sliders. A position calculated before shows again at once.
  - Once it has run, the headline shows the difference ("Earliest 54 → 53").
  - *Keep* writes the change into the plan (its results become the plan's own); *Reset* throws it away.

### Progress

See [PROGRESS.md](PROGRESS.md).

- **Your answer over time.** The earliest retirement age at each check-in, as a step line. Markers show where you changed the plan, where the app's calculations changed, or where new tax rules arrived.
- **Actual vs baseline.**
  - Pick a baseline, e.g. "Start of 2026 (automatic)" or "Before forfettario (saved 12 Mar)".
  - Its fan chart runs from its start date, with your actual line drawn over it, in the baseline's currency (its plan's when it was saved): the same accounts at each check-in's exchange rate, in money of the start date where an inflation index for that currency allows. A line under the chart says which, and names check-ins left out for want of a rate.
  - A summary: "12.400 € ahead of the median · 61st percentile". The Overview's "ahead of your Jan baseline" is in the baseline's currency too, and its *Future* projection is converted to the base currency at the plan's start-date rate.
  - M3 adds the waterfall explaining the gap: savings, markets, inflation and other.
- **Save baseline…** takes a label.

### Inputs

A form with the same sections as the plan file. Each section is a collapsible card with a one-line summary, so the whole plan fits on one screen when collapsed:

```
You            Born 1988 · retire at 55 · plan to 95 · in CHF
Work           Employee 2026–28 · Forfettario 2029–retirement
Spending       36.000 €/yr · 90% from 75 · 80% from 85
Pensions       INPS (earliest) · State pension from previous country 67
Contributions  Fondo pensione 5.000 €/yr · BVG 20.000 CHF in 2030
Events         Inheritance at 62 (80%) · New car 2031
Taxes          Italy · Impatriati (2024) 2025–29        ⚠︎ 1
Assumptions    Equity 4,5% (2% income) · Inflation 2%
Simulation     2.000 runs · 90% confidence
```

(The examples mix countries on purpose; every list and picker comes from the registered tax systems.)

- **You.** The birth date and the citizenships, as in Settings (a line says that some tax treaties decide by citizenship which country taxes a pension), the retirement age, the plan's end, and the plan's **currency**: *Library currency (EUR)* by default, any currency the library has exchange rates for, or another code typed in. Every amount in the plan and its results is in it, in today's money; the accounts are converted at the rates on the plan's start date, and check-ins fetch the rates of the plans' currencies. Money options show its code.
- **Work phases.** Each is a row. Tapping it opens an editor:
  - kind, dates and amounts;
  - a **regime picker** that offers only the regimes that fit (e.g. for self-employed in Italy: *Ordinario* or *Forfettario*);
  - the regime's options form, **generated from the regime's description** ([TAXES.md](TAXES.md#choosing-them-in-a-plan)), so a new regime needs no new screens. Every kind of option has a control: percentages, amounts, whole numbers and years are typed, switches toggle, choices pick. The row's second line lists the options the plan sets, by their labels ("TFR goes to: A pension fund").
- **Pensions.** Each is a row ("From 67 · 4.800 €/yr · State pension · from Germany"). The editor has the scheme and name; for a pension from a statement (`fixed`), its amount and age, **what kind it is** (state, occupational, basic pension, private annuity: some systems tax kinds differently) and the **paying country**; for a scheme, when to claim and, when the scheme lists several, **the way to claim it** ("Capital · at 65, lump sum"), from the scheme's own claim options for the pension's details as they are. A scheme that lists none yet gets a text field, and a way it never offers shows as a warning once the plan is calculated. Then who taxes it, and the scheme's options form.
- **Contributions.** Each is a row ("BVG · Pension scheme (buy-in) · Once in 2030 · 20.000 CHF"). The editor picks where it goes, an account or a pension scheme of the plan's tax systems (a buy-in: the system decides what it adds to the pension and any relief), and whether it's paid every year (until retirement or a date) or once, in a year.
- **Assumptions.** Each class's real return and volatility, then an optional **income yield** for equity and bonds: "The part of the return paid as income each year; some countries tax it yearly."
- **Taxes.**
  - A residence timeline (country system + options per period). A new plan starts in the system of the library's tax residence (the registered system for that country, else `generic`).
  - Overlays (special regimes) with their years shown as a bar.
  - Overrides for what-if law changes.
- **Validation.** Issues appear on the section they concern, and on the row of the work phase, pension or contribution they're about:
  - ⚠︎ for warnings, e.g. "Impatriati doesn't apply to forfettario income: 2029 is lost";
  - ⛔︎ for errors that stop the plan from running.
- **Staying in view.** On iPhone, a small sticky pill at the top ("Earliest 54") keeps the answer visible while you edit; once an edit makes it out of date it says so, with *Recalculate*, and shows a small bar while that runs. On the Mac, Inputs and Results are side by side, so the out-of-date banner and *Recalculate* (⌘R) are next to the field you're editing.

### Comparing two plans

A window on the Mac (a pushed page on iPhone):

- one **Calculate** (or *Recalculate*) for the plans that have no results or whose results are out of date, run one after the other, with the progress of each ("Calculating Base case (1 of 2)…") and Cancel. Until then each side shows its latest results, dimmed with "Out of date" when they are, or its recorded answer, dated;
- both headlines;
- the two success curves overlaid (two series, direct-labelled);
- a table of key numbers, each plan's amounts in its own currency.

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
3. **Columns.** A table: the column header, sample values, *Imports as* (Balance of…, Quantity of…, Price of…, Ignore), and a per-column format override. The layout: a row per date, per record, or per trade.
4. **Accounts.** Names in the file matched to accounts (existing, new, or ignored), plus proposed closings.
5. **Preview.** The parsed grid with errors highlighted, counts (new, updated, identical, conflicting), and the conflict policy.
6. **Done.** A summary, **Undo import**, and **Save as profile**. When the import's positions are valued on dates without a price, a **Past prices** section lists them ("12 past values have no price for XAU") with **Fill In Past Prices…** ([Adding history](#adding-history)).

A broker's transactions (Directa's or Fineco's movements, Degiro's or IBKR's exports) are recognised when the file is read and imported as trades, *A row per trade* ([IMPORT.md](IMPORT.md#broker-transactions)):

- **Columns** offers the trade's fields (Date, Trade type, Instrument, Quantity, Price, Currency, Amount (net), Gross amount, Fees, Tax, Split ratio, Note) and *Account of every row* when the file has no account column. An amount column's format says how its signs are read.
- **Types**, between Columns and Accounts: each word the file uses for a transaction ("Acquisto", "Ritenuta su dividendo", "Giroconto") with its number of rows, where its type comes from (the usual word, set by you or the profile), and a picker of trade types, or *Leave out*. A word the importer doesn't know shows a warning and its rows are left out until you choose; nothing is guessed. Below, how amounts are signed (automatic, without signs: from the type, signed: as written) and notes on how the file's signs were read.
- **Accounts** proposes making an account record trades when the file has trades for one that doesn't, with what that changes; turned off, its trades are left out, or choose another account.
- **Preview** shows the trades like other records ("Directa, buy, 12 Jan 2026 · Buy 15 VWCE at 102,30 · −1.539,50 € · fees 5 €"), with how many of the records are trades; **Done** counts them, names the accounts now recording trades, and has **Undo import** as always.

On iPhone, a CSV opened from Files goes straight to "Import with profile…": choose the profile, preview, import.

Ledger journals (one or several `.ledger`, `.journal`, `.hledger`, `.j` or `.dat` files) have their own steps in the same window:

1. **Files.** What was read: the files, transactions, dates, problems with their file and line, and includes the app can't read, with **Choose the Journal's Folder…**. The saved ledger profiles, best fit first.
2. **Accounts.** The ledger's assets and liabilities as a tree, each with a picker: as proposed (matched or new), a library account, a new account, or left out; the new accounts to create; closings; the income and expense accounts that are returns; month, quarter or activity snapshots. Accounts that record trades get the journal's transactions as trades instead of snapshots, as the footer says, with a **Cash checks** switch for valuations of their cash ([IMPORT.md](IMPORT.md#journals-into-trades-accounts)).
3. **Commodities.** Each commodity as cash, an instrument (matched, new or chosen) or left out; the new instruments; whether `@` prices are recorded.
4. **Preview** and 5. **Done**, as for a spreadsheet, with the journal's notes (flows that couldn't be valued) instead of the grid. **Save as profile** remembers the new accounts you didn't create as left out (`ledger.ignore`), so the next import doesn't propose them again.

On iPhone, journals use "Import with profile…" with a saved ledger profile, like a CSV.

## Settings

| Section | Contents |
| --- | --- |
| Library | Location (iCloud Drive or this device), Show in Files/Finder, sync status, merged conflicts, backups, the file format docs |
| You | Name, birth date, citizenships (each with a remove button, and *Add Citizenship*: "Some tax treaties decide by citizenship which country taxes a pension."), base currency, tax residence (the default for new plans) |
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
- Zero never has a sign: an amount that rounds to zero reads `0,00 €`, never `−0,00 €`, and an axis never reads `−0`.
- Dates in "since …" leave out the year only when it's this one: "since 30 Sep", "since 30 Nov 2021".

**Changes.** Always a sign and an arrow as well as colour: ▲ +4.210 in the success-green text colour, ▼ −240 in red. Never colour alone. A change that shows as zero gets neither: `0 €`, in grey.

**Colour in charts** follows the dataviz reference palette, in light and dark variants.

- **Asset classes** have fixed colours everywhere in the app. Their order is also the stacking order, from bottom to top, and was chosen to pass colour-blindness checks between neighbouring bands:

  | Cash | Bonds | Equity | Gold | Crypto | Real estate | Other | Debt |
  | --- | --- | --- | --- | --- | --- | --- | --- |
  | blue | orange | aqua | yellow | magenta | green | violet | red |

- **Retirement income** stacks its sources in a fixed order, each in its own slot of the same palette, so neighbours in the stack are neighbours in the validated order: withdrawals blue, work orange, INPS aqua, other pensions yellow, the pension fund magenta, windfalls green, TFR violet, other red. The taxes on top are a neutral grey (the secondary ink colour), which stays apart from all eight hues in light and dark. Each band is a wash of its colour with a 2-point line in the colour along its top and a 2-point gap above the line, never a saturated block; net worth by asset class is drawn the same way.
- **Lines and small marks** (the lines along stacked areas, legend swatches, dots, the allocation bars) need 3:1 against what they sit on, the card or the page. In light mode orange, aqua, yellow and magenta don't all reach it, so they use a darker step of the same hue there (orange `#d95926`, aqua `#199e70`, yellow `#ba7e07`, magenta `#d55181`); washes keep the lighter step, and in dark mode every hue already reaches it. Checked as a set on both surfaces with the dataviz validator.
- **Changes** (the bars since the last check-in) use the positive and negative colours, with a sign and an amount in ink beside each bar.
- **Everything else** is one hue (blue) with labels: allocation by account group, fan charts (the bands are lighter steps of blue), success curves.
- **Your actual history** is always drawn in ink, not a series colour, so "what happened" never looks like "what was projected".
- **Status colours** (warning, error) appear only with an icon and a label.

**Charts.**

- Swift Charts, with thin marks: 2 pt lines and rounded bar ends.
- Faint gridlines; marker rules are solid hairlines, never dashed.
- A value axis always includes zero and has round ticks whose labels read apart; flat or near-zero data gets a sensible span (0 to 1 at least), never a sliver labelled "0, 0, −0, −0".
- **Domains fit the data.** A time axis spans the dates shown (or the chosen time span), an age axis today's age to the last age simulated, never from 0.
- **Ticks fit the width.** Years every 1, 2, 5 or 10, or months for a span of a year or two (January says the year); ages every 5. Never a label per bar.
- **Labels never collide.** Marker labels sit above the data, in room the value axis keeps for them, staggered in up to two rows; a marker without room in either shows its icon, and its label is in the callout. A line's label goes at its end, outside the other marks: the time axis reaches past the data to make room.
- **Legends sit in a row of their own** above the chart, each swatch mirroring its mark (a line for a line, a block for an area), names in text colours. A single series has none: the title names it.
- **A projection's value axis** fits the history, the median and the 25–75% band. The 10–90% band may run off the top, cut at the chart's edge, and the legend says "↑ 10–90% continues above". No log scale.
- A value that couldn't be worked out (a price or exchange rate missing) is never drawn as zero: an account's line has a gap there, and a total that adds up what it could is drawn dashed and grey. A note under the chart says what's missing.
- Direct labels on the last point as well as the legend, where they don't collide.
- Every chart can be read by dragging across it (`chartXSelection`) and has a VoiceOver summary (`accessibilityChartDescriptor`). The callout stays inside the chart, never over what's above it.
- No dual axes. When two measures need comparing, they get two charts.

**Uncertainty** is always a band, never just the median. The words are "in 9 of 10 simulated futures", not "90% probability".

**Privacy.**

- An eye button hides every amount (`•••••`) while charts keep their shape and a relative value axis: net worth (and an account's value) in multiples of today's (`0`, `1×`, `2×`), the plan's money in multiples of today's plan assets, retirement income in multiples of the spending. Only labels that would reveal amounts hide; the change since the last check-in shows in per cent.
- Amounts are marked `.privacySensitive()`, so widgets and the app switcher hide them when the device is locked.
- Optional Face ID lock.

**Accessibility.**

- Dynamic Type everywhere; the hero number scales too, up to a cap.
- VoiceOver labels read amounts properly ("three hundred twelve thousand euros").
- Reduce Motion turns off the number animations.
- Contrast checked in light and dark.

**Opening the library.** While the library opens, the screen says what it's doing, one step at a time: "Looking for your library in iCloud Drive…", "Downloading 52 of 140 files from iCloud Drive…" with a bar and the bytes ("1.3 MB of 3.4 MB"), then "Reading your library…". A library already on the device goes straight to reading, in a blink. Files iCloud couldn't download are named under the bar ("2 files couldn't be downloaded: …").

If nothing moves for 20 seconds, the screen says why it may be stuck and what to do. It never dead-ends, and it never offers to create a library, which would duplicate the one that hasn't arrived:

```
╭──────────────────────────────────────────────────────────────╮
│ ☁ Still waiting for iCloud Drive                             │
│ Your library is in iCloud Drive, but 88 of its files aren't  │
│ on this device yet.                                          │
│ ┌──────────────────────────────────────────────────────────┐ │
│ │ Downloading 52 of 140 files from iCloud Drive…           │ │
│ │ ━━━━━━━━━━━━━━━━━━━━━━──────────────────────────────     │ │
│ │ 1.3 MB of 3.4 MB                                         │ │
│ └──────────────────────────────────────────────────────────┘ │
│ This can happen when:                                        │
│ • You're offline, or the connection is poor.                 │
│ • Cellular data is turned off for iCloud Drive               │
│   (Settings › Cellular).                                     │
│ • Low Power Mode is on, which can pause iCloud downloads.    │
│ • iCloud Drive is turned off for this app                    │
│   (Settings › [your name] › iCloud › iCloud Drive).          │
│ [        Try Again        ]                                  │
│ [      Keep Waiting       ]                                  │
│ [      Open Settings      ]   iPhone and iPad only           │
╰──────────────────────────────────────────────────────────────╯
```

- **Try Again** starts opening from the beginning.
- **Keep Waiting** asks iCloud again for the missing files and gives it another 20 seconds.
- **Open Settings** opens the app's page in Settings. The Mac names System Settings in the reasons and has no cellular reason.

**Empty states and first launch.** Every empty screen has one clear next step. First launch runs:

1. Welcome.
2. Where to keep your data (iCloud Drive is recommended).
3. Birth date, base currency, tax residence and citizenship, starting from the device's currency and region (nothing else is assumed: without a region the residence is *Not set*). When no tax system is registered for the residence, a note says so: "There are no tax rules for Germany yet: plans use the generic system's flat rates, which you choose."
4. "Import a spreadsheet or journals" or "Add accounts".
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
  | `LibraryStore` | the in-memory library, edits, how far opening it has come, sync status, merged conflicts |
  | `PlanStore` | runs on request, their progress, results and what they were calculated from (out of date or not), headlines and baselines |
  | `CheckInStore` | the check-in draft, kept on the device until it's saved |
  | `PriceStore` | price fetching (wraps `PriceService`) |
  | `PrivacySettings`, `AppPreferences`, `AppNavigation` | hidden amounts, this device's settings, where you are in the app |

  An import in progress belongs to the Import screen.
- **Navigation.** One root view chooses between `TabView` (compact width) and `NavigationSplitView` (regular width and Mac). The screens themselves don't know which one they're in.
- **Mac layouts.** A Mac window can't be smaller than the minimum size of its content, so every page's content scrolls, and what's pinned to a page scrolls when there's no room (`OverflowScrollView`). Tables on a scrolling page are as tall as their rows (`PageTable`), so the page scrolls them; a `Table` is used only as a whole page (Instruments, the import's columns). [App/README.md](../App/README.md#design-system) has the details.
- **Folders.** `App/Sources/` holds `App`, `Stores`, `Navigation`, `DesignSystem` (colours, number formats, spacing, amount text, cards), `Components/Charts`, `Features/<Feature>` (Overview, Accounts, CheckIn, Plan, Import, Settings, Onboarding, Library) and `Preview`. [App/README.md](../App/README.md) describes them and the stores' APIs.
- **Chart components**, reused everywhere: `NetWorthChart`, `FanChart`, `SuccessCurveChart`, `IncomeStackChart`, `WaterfallChart` (now a headline and change bars), `BreakdownBars`, `Sparkline`. Their layout (ticks, marker labels, scales, the time span) is worked out without SwiftUI and tested on Linux.
- **Previews.** Every screen has SwiftUI previews built from a made-up library in code, with the same numbers as the example library in the tests.
