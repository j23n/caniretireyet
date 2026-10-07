# UI

What the app looks like and how it behaves, on iPhone and Mac. It's built with SwiftUI on iOS 26 and macOS 26, using the system's Liquid Glass look.

## Who uses it, and when

The app has one user, and three situations to design for:

| Situation | Where | How often | What matters |
| --- | --- | --- | --- |
| **Monthly check-in** | Mostly iPhone | Monthly, about 5 minutes | Speed. Values are pre-filled, and only what changed needs a tap. It ends with this month's answer. |
| **Planning session** | Mostly Mac | A few times a year, 30–60 minutes | The plan as the chapters of a life, each with its money and its inputs in words, what-ifs a click away, comparing two plans. |
| **Looking after the data** | Mac | Occasionally | Adding and closing accounts, importing, fixing a value, looking at the files. |

Plus the glance: "how am I doing?" in a widget or on the Overview.

**Tone.** Money is emotional, so the app stays calm and matter-of-fact:

- no confetti, streaks or red alarm screens;
- uncertainty is shown honestly, e.g. "in 9 of 10 simulated futures", never as a single promised number;
- nothing ever scolds you.

## Navigation

**iPhone:** a tab bar with three tabs. While a check-in is due or under way, it lives in the tab bar's accessory, so it's one tap from anywhere.

```
╭──────────────────────────────────────────╮
│ ◷ October check-in · due in 3 days    ▸  │  ← tab bar accessory (iOS 26)
╰──────────────────────────────────────────╯
   ◉ Overview     ▤ Accounts     ◔ Plan
```

- **Overview:** net worth, history, how you're doing.
- **Accounts:** the list, account details, adding and closing.
- **Plan:** the plan, chapter by chapter, and its progress, for each plan.
- **Settings** opens from a gear button in the Overview toolbar. It's rarely needed, so it doesn't take a tab.
- The accessory shows the check-in's state, "October check-in · due in 3 days", "Continue check-in · 7 of 9 reviewed", and opens it. It shows only while a check-in is due (within a few days of the month's end, or past it) or a draft is waiting, so it doesn't sit over every screen the rest of the month; then *Check In* in the Overview's toolbar starts one early. (Before iOS 26.1, which can hide it, it always shows: "Last check-in 30 Sep · next 31 Oct".)

**Mac and iPad:** a sidebar with a content area, plus an inspector where it helps.

```
Overview
Check-in                       •     ← dot when due
Accounts                  97.330     ← the total of the open accounts
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
  - The *Accounts* header shows the total of the open accounts on the right: the groups' subtotals added up.
  - Under it, a row per group that has open accounts (Cash, Investments, Crypto & gold, Pension, Property, Debts), with its subtotal on the right. It expands to the group's accounts: kind icon, name and value, with a small clock when the latest value is stale. Values and staleness are the same as in the list. *Closed (n)* expands to the closed accounts. Amounts are left out while they're hidden.
  - Clicking a group, or its disclosure triangle, expands or collapses it; groups aren't pages. They start expanded and *Closed* collapsed, and the device remembers which are collapsed, here and on the iPhone's Accounts tab alike ([Accounts](#accounts)).
  - Selecting an account shows its detail in the content area; the arrow keys move from account to account. Opening an account from elsewhere in the app selects its row and expands its group.
  - The sidebar follows the library, also when it changes on the other device: a new account appears under its group, a selected account that's closed moves under *Closed* and stays selected, and one that's deleted gives way to the Overview.
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
  | Export Calculations… | — |

- **Drag and drop:** dropping a CSV anywhere on the window starts an import.
- **Window size (Mac):** the window opens at 1200 × 800 and can be made as small as 900 × 600. Every page scrolls, with what's pinned to it (the plan's What-if, the import's column settings) scrolling too when there's no room, so no page makes the window taller than the screen.

## Overview

The home screen. Top to bottom:

```
┌──────────────────────────────────────────┐
│ Overview                        👁   ⚙︎   │
│                                          │
│ Net worth                                │
│ 312.480 €                                │
│ ▲ 4.210 € in September   ▲ 14,2% this yr │
│                                          │
│ 3Y ▾                            Future ◯ │
│ ▬ Cash  ▬ Equity  ▬ Real estate  ▬ Debts │
│ ┌──────────────────────────────────────┐ │
│ │                          ╱‾‾╲__╱‾    │ │
│ │              ___╱‾‾‾‾‾‾‾‾░░░░░░░░    │ │
│ │ ____╱‾‾‾‾‾‾‾‾░░░░░░░░░░░░░░░░░░░░    │ │
│ │ ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒    │ │
│ │ ─────────────────────────────────    │ │
│ │ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓    │ │
│ └──────────────────────────────────────┘ │
│                                          │
│ ┌ What moved in September ─────────────┐ │
│ │ 308.270 € → 312.480 €                │ │
│ │ Markets    │▇▇▇▇▇▇▇▇▇      +2.950 €  │ │
│ │ New money  │▇▇▇▇▇          +1.500 €  │ │
│ │ Other     ▇│                 −240 €  │ │
│ └──────────────────────────────────────┘ │
│ ┌ Can I retire yet? ───────────────────┐ │
│ │ Not yet · earliest at 54 (2042)      │ │
│ │ ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇░░░░░░░░░░░░░░░ │ │
│ │ 58% of what retiring today needs ⓘ   │ │
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

The whole screen is net worth: the hero number, the history chart (except with *Future* on, below), the change since the last check-in and the allocation.

- **Hero number.**
  - Net worth at the latest check-in, with its changes since the last check-in and this year: "▲ 4.210 € in September" when the check-in before was the end of August, else "since 31 Jul".
  - It animates when it changes (`.contentTransition(.numericText())`).
  - It's only a number, not a control. (It used to switch to *plan assets* when tapped; plan assets now show only where they matter, in the chart with *Future* on and on the Plan screen.)
- **History chart.**
  - **One row of controls above it:** the time span and *Future*. Where the row doesn't fit (an iPhone at larger text sizes), the time span's label gets shorter words ("3Y → ret. +15") and *Future* becomes a button that stays lit while it's on; at the largest sizes *Future* moves under the time span.
  - Always net worth stacked by asset class, with debts below the zero line, and a legend in its own row above. Like retirement income, each class is a light wash of its colour with a 2-point line along its edge (the top, or the bottom for debts) and a 2-point gap between neighbours, never a solid block. Only when there's nothing to stack (every value zero) is it a single line.
  - Drag across it to read any month: a vertical rule with a callout showing the date, the total and the breakdown; over the projection, its median and bands.
  - **Future** continues the chart into the active plan's projection: a dashed median with a darker 25–75% band and a lighter 10–90% band, plus markers for retirement, pension starts and the like. See [PROGRESS.md](PROGRESS.md#past-and-future-m2).
    - The switch shows whenever there's a main plan. Plans only run when asked, so when the main plan hasn't been calculated yet, turning *Future* on is that request: it calculates the plan, with "Calculating Base case's projection… 34%" and a bar under the controls until the projection is there. A plan that can't run says why ("Base case can't be calculated: …"), with *Try Again* and *Open Plan*, and isn't tried again on its own.
    - **The past shows plan assets, still by asset class.** The projection is of what the plan counts (*plan assets*: e.g. without your home and its mortgage), so with *Future* on the past covers the same accounts and its total meets the projection's median at today. The alternatives mislead: net worth up to today and then a projection of less would look like a fall at today, and carrying the home on at its last value would invent a forecast the plan doesn't make. The projection is one total, so where the plan counts a debt, the median starts below the top of the stack, at what's left after it.
    - The legend gets a second row for the projection: the median and the two bands (the asset classes stand for the past, so there's no "Actual" line).
    - The value axis fits the history, the median and the 25–75% band. The 10–90% band may run off the top, and the legend says "↑ 10–90% continues above".
    - A short caption under the chart ("Plan assets by asset class, then Base case's projection, in today's money.") with an ⓘ that opens the full explanation: why the past is plan assets, and that turning *Future* off shows the whole net worth.
  - **Time span.** One menu sets how far back and, with *Future* on, how far ahead: *History* last year, 3 or 5 years, or all of it; *Future* to retirement, retirement + 15 years (the default), 20 years or the whole plan, never past the plan's end. Once retirement is behind you, the retirement-based choices give way to 20 years. The menu's label says both ("3Y · retirement +15"). The choice is remembered on the device and shared with the plan's "Your money over time".
  - **Old prices.** When a value in the chart uses a price more than 31 days older than its date, a note under it says so: "10 values in the chart use a price more than 31 days older than their date (Gold coins)." with *Fill In Past Prices…* (see [Instruments](#accounts)).
  - **Partial totals.** Net worth adds up what can be valued. Where a total misses something (a price or an exchange rate, or an account with no value yet), every class's line is dashed (as a partial total's line is elsewhere, so it doesn't look like a fall), the callout says "Partial: some values are missing", and a note under the chart says what and when: "Where lines are dashed, the total is partial: exchange rates for US$ are missing for Jun 2018 – Dec 2021 (US brokerage) and 3 accounts have no value yet for Jun 2018 – Sep 2025 (Directa, Fondo pensione and Old bank)." with *Fill In Past Prices…* when some of it is prices or rates.
- **Since last check-in.** "What moved in September" (or "Since last check-in" when the check-in before wasn't the end of the month before): the totals before and after in words, and a bar each for markets, new money and other, from a shared zero line and to the same scale: gains go right in the positive colour, losses left in the negative one, with their signed amounts in a column of their own. The change itself is the hero number's, said once; the check-in's review leads with it ("▲ +4.210 € since 31 Aug", in per cent while amounts are hidden). It's the most useful split after the total, because it separates "I saved" from "markets moved". (It used to be a waterfall, whose bars from zero made the totals huge grey blocks and the changes slivers on top.) While amounts are hidden, the bars keep their proportions.
- **Can I retire yet?** The plan's headline, how close your plan assets are to what retiring today needs, and how you compare with the latest baseline. Tapping it opens the Plan tab.
  - **Readiness**: a bar and "58% of what you'd need to retire today" ([PLANNER.md](PLANNER.md#assets-needed-to-retire-today)). Its ⓘ explains it: "Your plan assets compared with what retiring now would need for a 90% chance (the plan's confidence), including the years before your pensions start and taxes. The plan finds it by simulating retiring today with extra money added to accounts you can draw now, or with money taken out of them; money locked in pension funds stays as it is. At 100% you could retire today." It comes from the same simulation as the chance of retiring today, so it reaches 100% exactly when the answer turns to "Yes" (above 100% it keeps counting: "130% of what you'd need…"). When retiring today would need more than 20 times your plan assets, it says so instead of a percentage.
  - An answer recorded before readiness existed has only the old "of the way to financial independence", a rule of thumb that ignored the years before the pensions and taxes and so disagreed with the chance of retiring today: the card shows "Calculate the plan to see how close you are to retiring today." instead.
  - A caption under the answer says what it is: "Estimates, not financial or tax advice."
  - The card opens the plan on a tap anywhere but the ⓘ; the chevron is its button for VoiceOver and the keyboard. It shows the main plan's latest results, or else the answer recorded at the last check-in, dated; it never starts a calculation. While one is going (a check-in's, or one started on the Plan screen) it says how far along it is, and results that no longer fit the plan or your data say "Calculated before your latest changes".
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
│   VWCE  [ 412,5 ] sh × 138,42 €  57.098  │
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
  ●  updated   ✓  unchanged or from trades   ○  not reviewed yet
```

- **Date.** Defaults to today. In the first days of a month it suggests the end of the previous month. An earlier date fills in history: see [Adding history](#adding-history).
- **Prices.** Fetched as soon as the sheet opens, while you work. The status row opens the price list, where you can see the source and time of each price and type in any that failed.
- **Accounts, in groups.** Each row has one of three states:
  - **updated:** you entered a new value;
  - **unchanged:** you confirmed it's the same. This still writes a valuation, so the account isn't stale;
  - **not reviewed.**

  "Review" asks about any rows not reviewed: mark them unchanged, or skip them (then no record is written, and the account will show as stale). A new account with no earlier value can't be unchanged: it's entered or skipped. An account that records trades has nothing to type, so its row is done from the start, "from trades" (below).
- **Accounts with holdings.** Each position's quantity is pre-filled, and its value updates live with the fetched price. When a quantity goes up, an optional "paid" field appears. What you enter updates the position's purchase cost and the new money, which is how purchase costs are tracked without transactions.
- **Accounts that record trades** ([TRADES.md](TRADES.md#check-ins)). Nothing to type: the value is the trades at the check-in's prices, so the row is **done from the start** (✓, "From trades" to VoiceOver), and counts as reviewed. It leads with what matters, what the trades hold and their value, and *Add Trade…* for what was bought or sold since the last check-in:

  ```
  ┌────────────────────────────────────────────────────┐
  │ ▸ Directa                           59.447,70 €  ✓ │
  │   423 VWCE · from trades                           │
  │   Bought or sold since 30 Sep?      [⊕ Add Trade…] │
  │   Cash 312,30 · from trades   Enter From Statement │
  │   New money +1.450,00 · deposits                   │
  │ ▸ Gold coins                         9.255,36 €  ✓ │
  │   93,3 g · from trades                             │
  │   Bought or sold since 30 Sep?      [⊕ Add Trade…] │
  └────────────────────────────────────────────────────┘
  ```

  - **As the trades say.** Saving writes the cash the trades give and the new money they record: the deposits, withdrawals and transfers recorded as trades since the previous value, and what was bought or sold paid from outside the account. It's shown read-only when it isn't zero ("New money +1.200,00 · paid from outside", or with several parts "New money +1.650,60 · deposits +450,60 · paid from outside +1.200,00"). *Mark rest unchanged* leaves the row alone.
  - ***Add Trade…*** (a bordered button, not a footnote) opens the trade sheet dated on the check-in's date. Once it's saved the row follows: the positions, the cash and the new money are worked out again, and a cash from a statement stays.
  - **Cash.** When the account holds cash by its trades (a trade settled in its cash, a deposit or withdrawal, or a value that recorded cash), it shows read-only, "Cash 312,30 · from trades", with *Enter From Statement* to type the cash from a broker statement to compare. Typed, it anchors the cash and the difference counts as money added or taken out that no trade records; the new money is then shown as for other accounts, editable, with its split:

    ```
    │   Cash  [    320,40 € ]                            │
    │   From a statement · the trades give 312,30        │
    │   Use Trades' Cash                                 │
    │   was 57.410,35 · new money +1.458,10              │
    │   deposits +1.450,00 · cash difference +8,10       │
    ```

    *Use Trades' Cash* (or *Use the Trades' Values* in the menu, the leading swipe *From Trades*) goes back to what the trades say. An account that never holds cash, e.g. coins or crypto whose every trade was paid from a bank account, shows no cash line at all.
  - **Nothing to follow yet.** A trades account with nothing recorded before the date (a new one) says "No trades yet", has its cash field and *Add Trade…*, and is entered or skipped like any new account; one that opens after the date is optional, under *Opened later*.
  - **Expanded** (tap the name), the positions the trades hold, read-only at the check-in's prices ("VWCE 423 sh × 139,80 € 59.135,40", "+10,5 since 30 Sep · from trades"), and *Compare With a Statement* (also in the menu: long-press, or right-click on the Mac), which fills in the trades' quantities to correct from a broker statement. They're saved with the value as a check, not as holdings; the review lists where they differ: "The statement on 31 Oct shows 425 VWCE; your trades give 423. Add the missing trade, e.g. a buy or a transfer in." with *Add Trade…*. *Stop Comparing* drops them.
  - On the Mac, under the account's line (its value, and its new money read-only in the New money column, unless a statement's cash makes it editable): "Bought or sold since 30 Sep? [⊕ Add Trade…]" with the new money's parts, then the positions as read-only sub-rows (Last and Now are quantities), then the cash from the trades with *From Statement…* in the New money column (*Use Trades' Cash* once typed). Return moves down the Now column past a cash that isn't typed.
- **New money (flow).** Shown under each account, filled in by the defaults in [PROGRESS.md](PROGRESS.md#data-this-needs-from-day-one), and editable. For pension funds the app asks for "contributions since …".
- **Keyboard.** A decimal keypad in your locale's format, with ▲ ▼ buttons above it to move between fields. Amounts accept `1.234,56` and `1234.56`. For a debt, type what you owe (`1.200` is recorded as −1.200); if it's in credit, e.g. an overpaid card, type `+` first (`+20`), or use ± above the keypad. *Update value* and a new account's opening balance work the same way.
- **Draft.** An unfinished check-in is saved as a draft on the device and never half-written to the library. Close the sheet, come back later, and continue.
  - The draft follows the library: when you come back, when the other device changes something, and just before saving. Accounts you haven't reviewed take their latest values, new accounts appear and closed ones leave; what you entered stays.
  - If the other device saved a different value on the same date for an account you entered, a banner says so and the review asks: *Keep saved* or *Use mine*. Until you choose, the saved value stays and yours isn't written.
  - The draft is deleted only once the check-in is in the library's files. If saving fails, the error is shown and the draft stays.
- **Review screen.**
  - The new net worth and the change since the last check-in: a headline and a bar each for markets, new money and other; under it the rows by state, "5 updated · 1 unchanged · 2 from trades".
  - Changed accounts (accounts that record trades among them when their value or new money changed, "New money +1.450 € · from trades"), and anything unusual, e.g. a quantity that went down (did you sell?) or a value that changed more than 30%.
  - Then **Save**.
- **After saving.** The confirmation shows as soon as the check-in is written. The main plan then runs to record this month's answer (only for the latest check-in: see [Adding history](#adding-history)), and the answer card shows its progress ([Calculating](#calculating)) in the meantime, the same as on the Plan screen, without a Cancel button. Then it ends with the answer:

  > Saved · Net worth 312.480 € (▲ 4.210)
  > Can I retire yet? Not yet: earliest at **54**, unchanged since August.
  > 58% of what you'd need to retire today

  This is the monthly moment the app is built around, and the one time a plan runs without a button: recording the month's answer is what the check-in is for. *Done* can close the confirmation while it runs; the answer is still recorded.

**On the Mac**, the check-in is a table, and the whole thing can be done without touching the mouse:

- columns: Account, Last, Now, Change, New money, Note;
- Tab and Return move between cells;
- ⌘↩ saves.

## Accounts

- **List.** Grouped: Cash, Investments, Crypto & gold, Pension, Property, Debts. It's the iPhone's Accounts tab (and the iPad's in compact width); on the Mac and iPad the sidebar lists each group's accounts itself ([Navigation](#navigation)).

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
  - **Collapsing.** Tapping a group's header, or *Closed*'s, collapses the group to its header (name and subtotal) or expands it again, with an animation; the chevron at the right of the header points down while it's expanded. The groups start expanded and *Closed* collapsed. The device remembers which are collapsed, and the sidebar shares them: collapsing Cash on the Accounts tab collapses it in the sidebar too (on an iPad that switches layouts), and the other way round.
  - **Search** (by name, institution, kind, tags or notes) shows every group expanded while there's a query, so no result is hidden. Clearing it brings back the collapsed ones.
- **Account detail.**
  - **In the account's own currency.** The value, its change, the chart and the values list are in the account's currency, which needs no exchange rate: a dollar account in a euro library shows `0,00 US$`. Under the value, its value in the base currency at the day's rate, or "Value in EUR: rate missing".
  - The value and its change since the value before, with the year when it isn't this one: "▼ −123.959,00 US$ since 30 Nov 2021", then its parts (markets, new money, other). A change that shows as zero has no arrow and no sign.
  - A history chart. New-money events are small ticks in a lane along the bottom, pointing up for money added and down for money taken out, coloured by sign, so jumps you caused are distinguishable from market moves; they never stretch the value axis, and the callout gives their amount. The value axis always includes zero, with round ticks that read apart, even for an account that's been at zero. The callout stays inside the chart.
  - A value that can't be worked out (a price missing, or the rate for a position priced in another currency) is a gap in the line, never a zero. A note under the chart says what's missing and when, with *Fill In Past Prices…*: "Some values can't be shown: prices for Gold coins are missing for Mar 2023 – Sep 2025." For an account in another currency, it also says when net worth leaves it out: "Net worth leaves out this account's values for Jun 2018 – Dec 2021: exchange rates for US$ are missing." As on the Overview, a note points out values that use a price more than 31 days old.
  - **Empty accounts.** Once an open account has held nothing for longer than the staleness threshold, it isn't called stale; instead: "This account has been empty since 1 Jan 2022. Close it?" with *Close Account…*, which opens the Close sheet on that day.
  - For accounts with holdings, the positions: quantity, price, value, purchase cost and unrealised gain.
  - The list of valuations, each editable: date, value, new money, note. *Add Past Value…* adds one on an earlier date.
  - An info section: kind, institution, country, currency, from what age plans can draw on it ("Plans can draw on it: From 67", or "At any age"), how it's recorded (a balance, snapshots of positions, or trade history), and whether it's included in net worth and plans.
  - A holdings account offers *Switch to Trade History…* next to *Close Account…*: see [Trade history](#trade-history).
- **Add account.** A sheet:
  1. Pick a kind from a grid of icons.
  2. Enter the name, institution, currency, country and opening date. The opening date is today by default; the hint says "Set it to when you opened the account, to add its history." The opening balance is the one on that date.
  3. For a brokerage, crypto or metals account, choose **Track: Trade history / Monthly snapshots**. Trade history is the default: "Record each buy, sell and dividend: holdings, average cost, gains and income follow from them." Snapshots: "Type the quantities and cash at each check-in; no trades to keep."
  4. Enter the positions (choose or create instruments) or the balance, which becomes the first valuation. For trade history, each position becomes an *opening* trade on the opening date, with what you paid as its purchase cost, and the cash becomes the first value.
  5. **Plans:** whether it counts in net worth and in plans and, for an asset counted in plans, **Available only from an age** with a stepper ("Available from 65"): money plans can't draw on before then, such as a pension fund ([PLANNER.md](PLANNER.md#the-model-in-brief)). A pension fund starts at 65, every other kind at any age, until you change it; the footer says "Money available only from an age, such as a pension fund, can't pay for the years before it." The account's editor has the same fields.
- **Close account.** A sheet asks for:
  - the closing date;
  - "Where did the money go?", which sets the successor account;
  - a short explanation: the account keeps its history, stays in every chart up to that date, and leaves check-ins.

  Reopening is one button. Deleting is for mistakes only, sits at the bottom in red, and asks for confirmation.
- **Instruments** (under Library on the Mac, and from an account's positions on iPhone): name, ISIN or ticker, currency, unit, asset mix, and price source. Each row shows the latest saved price with its date and source, with a small clock when it's older than the staleness threshold. A footer says: "Prices are also fetched at every check-in. Net worth uses the price on or before each check-in's date. Fill In Past Prices fetches those missing for earlier dates."
  - **Update Prices** (toolbar; pull down on iPhone) fetches today's price of every instrument an open account holds that has a price source, the FX rates that value them in the base currency, and the months the library's inflation indices are missing (as a check-in would: an *Inflation* section, "Added Sep 2026." or "No new months published yet."), and saves them for today in one edit. An index value is only added, never replaced. A banner shows the progress, then the outcome; *Details* lists each instrument as updated, unchanged, failed (with the reason) or kept. A failure doesn't stop the others. A price typed in by hand for today is kept, as in the check-in, unless you choose *Update* on its row. Instruments typed in by hand or not held in an open account are skipped; a row's *Update Price* fetches one anyway.
  - **Set Price…** (on a row, or in the editor) types a price in by hand: the date (today by default), the amount, and the currency (the instrument's by default). It's saved as a `manual` price, which *Update Prices* doesn't replace.
  - **Fill In Past Prices…** (toolbar; the overflow menu on iPhone) fills in the past: every date a position is valued on without a price for that day (each value, and the month ends it carries over to in months without one of its own), the exchange rates those dates need, and the missing inflation months.
    - A sheet lists what's missing: each instrument with where it comes from, its date range and count ("Gold coins · gold-api.com · XAU · Oct 2015 – Sep 2026 · 132 dates"), then the rates and inflation, then **To type in**: instruments without a price source.
    - **Fill In** fetches with a progress bar: each instrument's whole range is one request, then one per currency and index ([PLAN.md](PLAN.md#prices-and-fx)). Metals' past prices come from their futures on Yahoo Finance (`GC=F` for gold), within about 1% of spot; crypto older than CoinGecko's free year from Yahoo's pairs (`BTC-EUR`).
    - Then each line shows how many dates it got and from where: "12 of 12 · Yahoo Finance · GC=F (history)", or "CoinGecko · ethereum back to Oct 2025, Yahoo Finance · ETH-EUR (history) before". What's left is listed with its dates and the reason, never skipped: *Set Price…* opens on one of its dates, and *Choose a Price Source* (or *Change Price Source*) opens the instrument's editor; *Check Again* fills in again after that.
    - The records are saved in one edit into their month files, after a `fill-history` backup. Nothing already saved is replaced: not a price typed in, not one from an import, not one fetched before.
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

**Past prices.** Whichever way history arrives, its positions only have the prices it brought: a spreadsheet's price columns, what a past check-in fetched. Gold bought years ago would otherwise stay at its purchase price in every month since. *Fill In Past Prices…* fetches the rest ([Instruments](#accounts)); the import's Done step offers it ("12 past values have no price for XAU"), and so does a note under a chart that uses old prices.

**New money after an inserted value.** A value's new money (its flow) is measured from the value before it. When a value is added before another one of the same account, or one is corrected, moved or deleted, the next value's new money is worked out again if it was automatic (the default for the account's kind, as the check-in fills it in), and kept if it was typed in. *Update Value* and the valuation editor say which before saving; a past check-in follows the same rule. A value added before an account's first one turns that first value's automatic new money (the whole amount) into the change since. An import follows the same rule for the library's values after the ones it adds or changes: its Preview says how many, and undoing the import puts them back ([IMPORT.md](IMPORT.md#preview-conflicts-and-undo)).

**Answers and baselines are only recorded for the latest check-in.** The plan runs on today's data, so re-running it for a past date would record made-up history in "Your answer over time" and a made-up "Start of <year>" baseline. A check-in dated before the library's latest one records neither, and its confirmation says: "Saved a past check-in (31 Mar 2024). The answer isn't recorded for past dates."

## Trade history

A brokerage, crypto or metals account can record its **trades** instead of monthly snapshots of its positions ([TRADES.md](TRADES.md)): its holdings, average cost, cash, realised gains and income follow from them, and its check-ins need nothing typed (see [Check-in](#check-in)). New accounts of those kinds record trades by default (see *Add account*); existing ones can switch.

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
│ Vanguard FTSE All-World      57.098,25 € │
│   412,5 sh × 138,42 € 99% of the account │
│   Average cost 116,85 € ▲ 8.898 € +18,5% │
│ Cash                           312,10 €  │
│ Total                       57.410,35 €  │
│ TRADES                                   │
│ ⊕ Add Trade…          20 trades Filter ▾ │
│ AUGUST 2026                              │
│ ⊕ Buy 10 VWCE                −1.352,50 € │
│   at 134,75 € · 12 Aug 2026              │
│ ↓ Deposit                      +200,60 € │
│   4 Aug 2026                             │
│ JULY 2026                                │
│ ⊖ Sell 8,5 VWCE              +1.162,80 € │
│   at 144,56 € · 14 Jul 2026 gain +234,42 │
│ …                                        │
│ INCOME & GAINS                           │
│ 2026   Realised gains · Dividends ·      │
│        Interest · Fees · Taxes · Net     │
│ CASH AT CHECK-INS · DETAILS · …          │
└──────────────────────────────────────────┘
```

- **Holdings**: per instrument, the quantity, average cost (*costo medio*: what was paid per unit, fees included), value, unrealised gain (amount and %) and its share of the account; then the cash and the total. Each position is three lines: the name and value; "0,10383916 BTC × 73.785,11 €" and "95 % of the account" (when they don't fit on one line, the quantity and the share share it and "at 73.785,11 €" goes on the next; at the largest text sizes each is a line of its own); "Average cost 101.437,74 €" and the gain ("▼ −2.871 € −27,3 %"), the gain under the cost when they don't fit. A label and its value are one piece of text, so they never wrap apart. On the Mac, a grid with those columns.
- **Trades**: grouped by month, newest first; each row shows the type's icon, what it was ("Buy 0,10383916 BTC") over its price, date and note ("at 101.437,76 € · 1 Oct 2025", the price in its own currency), and on the other side the cash it moved, with a sale's realised gain. A trade paid from outside the account shows what was paid or received, marked "paid from outside" (a sale: "proceeds paid out"); on the Mac the mark leads its note. At the largest text sizes the amount goes under the description. *Filter* shows one instrument or one type. Tap a trade to edit it; swipe or long-press to delete it (the confirmation says what deleting brings in, e.g. a later sale now selling more than is held). On the Mac, a table (date, type, instrument, quantity, price, amount, note) as long as its trades, which scrolls with the page: double-click edits, right-click edits or deletes.
- **Income & gains**, by year: realised gains, dividends, interest, fees and taxes, and the net; a sale whose cost is unknown is left out and said so. In the account's currency.
- **What needs a look**, as banners with the fix: a trade missing a price or amount, a sale of more than was held, an opening without cost, a missing exchange rate, a trade outside the account's dates, a value with a balance (which isn't used), and a statement that differs from the trades ("The statement on 30 Jun shows 12 VWCE; your trades give 10. Add the missing trade."). Each banner's button opens the trade, a new trade on the statement's date, or the value. The Overview's *Needs attention* points to an account with any of these ("Directa: 2 problems with trades").
- **Cash at check-ins**: the account's values, which record its cash. The history chart, the header's change and the new-money ticks come from the Valuator (deposits and transfers on their own dates).
- The toolbar's **+** adds a trade; *Update Cash…* records the cash on a date; *Switch to Snapshots…* sits next to *Close Account…*.

**Add Trade** (and *Edit Trade*) is a sheet:

- **Type**: Buy, Sell or Dividend as segments, and *More ▸* for interest, fee, tax, deposit, withdrawal, transfer in and out, split and opening (a chosen one shows as a fourth segment). Each type shows only its fields; editing a trade keeps showing any field it has.
- **Date**, and for most types the **instrument**: the library's instruments, or *New Instrument…* (the instrument form, in a sheet).
- **Quantity, price and currency** (the instrument's by default). The library's price for the date is a hint with *Use* ("The library's price that day: 138,42 €", or the latest before it); *Fetch Price for This Date* asks the instrument's price source.
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

A plan picker sits at the top (Base case ▾, with New Plan, Duplicate, Rename…, Set as Main Plan, Save Baseline…, *Export Calculations…* under how the answer shown was calculated, "Calculated at 09:41 with 2.000 runs", and Delete…), then two parts, **Plan** and **Progress**: a segmented control at the top on iPhone, in the toolbar on the Mac and iPad. *What if* is a sheet on iPhone and a column beside the plan on the Mac and iPad, opened from the toolbar, which also has *Recalculate* and *Save Baseline…*.

### Calculating

A plan is calculated only when you ask: *Calculate*, *Recalculate* (⌘R, and a toolbar button on the Mac), *Run What If*, a check-in recording its answer, or turning on the Overview's *Future* when the main plan has no results yet. Opening a plan, editing an input, moving a what-if slider or choosing another age for the charts runs nothing; the screen says what's out of date instead. Each plan keeps its own results, what-if and chosen age while you switch between plans.

- **Before the first calculation.** The answer recorded at the last check-in, dated ("Recorded at the check-in on 30 Sep 2026", and "before the plan's latest changes" when the plan was edited since), with "Calculate the plan to see its charts." and **Calculate**. With nothing recorded either, a sentence on what calculating does ("simulates 2.000 possible futures… takes a few seconds, and runs only when you ask") and **Calculate**.
- **Out of date.** The answer and the charts stay on screen, slightly dimmed, under a banner that says why and offers the button that brings them up to date:

  ```
  ┌──────────────────────────────────────────┐
  │ ◷ Out of date                            │
  │   Inputs changed since this was          │
  │   calculated.             [↻ Recalculate]│
  └──────────────────────────────────────────┘
  ```

  - *Inputs changed since this was calculated.*: the plan was edited (a rename doesn't count). Recalculate.
  - *Your accounts or prices changed since this was calculated.*: the library data the plan reads changed, e.g. a check-in or new prices. Recalculate.
  - *What-if values changed since this was calculated.*: a slider moved. Run What If.
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

  - The phase and its own bar, in the locale's numbers with tabular figures: "Earliest age · ages 38–75: 12 / 38" (most of the time: the chance at every age), "Simulating 1.234 / 2.000 runs" (the chosen age in detail), "Sustainable spending: step 4 / 16", "Needed to retire today: step 3 / 9", "Summarising". Then the whole calculation's bar. A what-if's first pass says "Quick estimate…".
  - **Cancel** stops it; the old results stay as they were (and out of date). A check-in's calculation can't be cancelled here: it says "Working out this month's answer…".
  - Editing an input while it runs lets it finish: its results then show as out of date, with Recalculate. Cancelling instead would throw away a calculation you asked for, while it's usually seconds from done.
  - The same view shows on iPhone and Mac, and in the check-in's confirmation. The answer's status line says "Calculating 29%" meanwhile.

### The plan

The plan reads as a life ([PLANNER.md](PLANNER.md#chapters)): the answer first, then your life as a strip of **chapters** with the money running through them, then the chosen chapter: what happens in it, in words, and its settings, where the plan changes. A chapter starts in the year the work you do changes, work stops, the first pension is paid, or retirement spending moves to another phase; everything else (another pension, a contribution, an event, a change of the target mix) belongs to the chapter it starts or happens in.

```
┌──────────────────────────────────────────┐
│ Base case ▾                          ⋯   │
│           [ Plan ]  Progress             │
│ ╭──────────────────────────────────────╮ │
│ │ Can I retire yet?                    │ │
│ │ Not yet. Stop at 54, in March 2042.  │ │
│ │ ●●●●○○○○○○ At 50, as planned, 4 in   │ │
│ │ 10 futures last to 95. Your bar is 9 │ │
│ │ in 10.                               │ │
│ │ [What if…]  [18.400 € ahead ›]       │ │
│ ╰──────────────────────────────────────╯ │
│ ⓘ TFR counts as cash: it has no mix of   │
│   investments set. Set one…              │
│ Your life in four chapters               │
│ Scroll sideways; tap a chapter.          │
│ ╭────────────────╮╭──────────────╮╭──────│
│ │① Employee      ││② Bridge      ││③ Pens│
│ │Now to 54 ·     ││54 to 67 ·    ││67 to │
│ │2026 to 2042    ││2042 to 2055  ││2055 t│
│ │           ▁▃▅▇ ││█▇▆▅▄▃        ││▃▃▂▂▂ │
│ │━━━━━━━━━━━━━━━━││━━━━━━━━━━━━━━││━━━━━━│
│ │Now   40    50  ││54   60    65 ││67  70│
│ │  ● New car,    ││              ││      │
│ │    25.000 €    ││              ││      │
│ │At 54, typically││At 67, typ.   ││At 80,│
│ │      612.000 € ││    480.000 € ││  390.│
│ ╰────────────────╯╰──────────────╯╰──────│
│ ╭──────────────────────────────────────╮ │
│ │ ② Bridge                      ‹  ›   │ │
│ │   54 to 67 · 2042 to 2055 · 13 years │ │
│ │ WHAT HAPPENS                         │ │
│ │ You stop working as early as you     │ │
│ │ can, at 54 in 2042, and spend        │ │
│ │ 3.000 € a month, all from your       │ │
│ │ savings.                             │ │
│ │ A MONTH                              │ │
│ │ ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇ │ │
│ │ 3.400 € from savings 400 € of it tax │ │
│ │ WHAT CAN GO WRONG                    │ │
│ │ ⚠ In 4 in 100 futures, the money     │ │
│ │   you can draw runs out before       │ │
│ │   Fondo pensione opens at 67.        │ │
│ ╰──────────────────────────────────────╯ │
│ Settings         A month, in today's EUR │
│ ╭──────────────────────────────────────╮ │
│ │ ▣ Stop working As early as you can › │ │
│ │   At 54, in 2042                     │ │
│ │ ▣ Spending                 3.000 € › │ │
│ │ ▣ Flexible spending            Off › │ │
│ │ ▣ Inheritance           +150.000 € › │ │
│ │   At 62 · 80% likely                 │ │
│ ╰──────────────────────────────────────╯ │
│ + Add to this chapter                    │
│ Every chapter assumes                    │
│ ╭──────────────────╮╭──────────────────╮ │
│ │ Shares        5% ││ Bonds       1.5% │ │
│ ╰──────────────────╯╰──────────────────╯ │
│ … inflation, taxes, your bar             │
│ All assumptions…   Export Calculations…  │
│ ▸ More charts                            │
└──────────────────────────────────────────┘
```

- **The answer.** "Not yet. Stop at 54, in March 2042." or "Yes. You could stop working today.", then why, at the age the plan is shown for: how many futures in 10 last to the plan's end, as ten dots and in words, against your bar ("At 50, as planned, 4 in 10 futures last to 95. Your bar is 9 in 10."; "If you stop at 56, …" for another age; "… That meets your bar." when it does; rounded down, so a plan short of its bar never reads as reaching it, and in hundredths for a bar like 95 in 100), and where the latest check-in stands against this year's automatic baseline ("18.400 € ahead ›" on iPhone, "18.400 € ahead of plan ›" on the Mac and iPad), which opens Progress. On iPhone it's a card, with *What if…* beside it, opening the sliders in a sheet; on the Mac and iPad a header across the page, and What if is in the toolbar. How the answer was calculated ("2.000 runs · 09:41") is in the plan menu; while it runs or is out of date, the banner above says so. Before the first calculation, the answer recorded at the last check-in with *Calculate* instead ([Calculating](#calculating)). What stops the plan from answering (it can't run, a change wasn't saved) shows above it; what it assumed that you may want to change shows under it, quietly, a line each with the way to fix it: "TFR counts as cash: it has no mix of investments set. *Set one…*", which opens the account (two at most; the rest with the inputs they concern).
- **Your life in chapters.** "Your life in four chapters": a strip that scrolls sideways, a card per chapter as wide as its years (26 points a year on the Mac and iPad, 22 on iPhone, never narrower than 164, so its name and where the money stands fit), side by side with a small gap. Every card draws the money on one scale, so the graph runs on from one chapter into the next.
  - Its number in the colour of its kind of life (grey while working or between jobs, orange for the bridge before the pensions, violet with them, a lighter violet for a later phase of spending), its name ("Employee", "Not working", "Bridge", "Retired" when no pension is ever paid, "Pension" or "Pensions", "Slowing down" or "Spending more" for a later phase) and its span ("Now to 54 · 2026 to 2042").
  - The money through it, in today's money: the median in the hue, half the futures in the darker band and 8 in 10 in the lighter one. The scale fits the medians and the middle half of futures, so the outer band may run off the top. Gridlines are labelled inside the plot, and not at all while amounts are hidden.
  - Along its bottom, a line in its colour, "Now" or the age it starts at, the round ages in it, and the plan's end age under the last card.
  - What happens in it, as dots on the median: events ("New car, 25.000 €", "in 2031" or "80% likely"), a pension starting after its first year, a later phase of spending, a one-off saving. Their labels sit under the ages, each starting at its date; one that would run into the one before shows only its dot.
  - The milestones the median reaches in it: the first and the last named on the graph, with an outlined flag, the name and when ("10 years of spending", "early 2037"), above the line (below it when there's no room); the last only when the two names don't run into each other. The rest are small dots on the line, which the read-out names.
  - At its end, once the plan is calculated: "At 67, typically 480.000 €", the range 8 in 10 futures fall in ("Bad 210k €, good 790k €") and how many futures run out during it ("4 in 100 futures run out here", "No futures run out here"). Dimmed while the results are out of date or being recalculated. Before calculating, the cards have their names, spans and events, and the first says "Calculate to see your money".
  - **Reading the graph.** On the Mac and an iPad with a pointer, the pointer over a card shows a rule down the plot, a dot on the median and a small label: the age and the year ("48 · 2034"), "Typically 640.000 €" (to the nearest thousand) and the range 8 in 10 futures fall in ("Bad 410k €, good 980k €"). Over a milestone's flag or an event's dot it reads that instead, by name ("Half of what retiring today needs", "Typically by mid 2034"; "New car, 25.000 €", "in 2031"). On iPhone, touch and hold a card (a light tap of haptics), then drag: the read-out follows the finger, and the strip stays put until it lifts. A tap or a click still chooses the chapter. Amounts hide with the eye.
  - Choosing a card selects it: outlined in the accent, its number filled. ‹ › (⌘[ and ⌘] with a keyboard) step through the chapters (above the strip on the Mac and iPad, with *Today* back to the first; in the chapter's header on iPhone), and the strip scrolls to the one selected. The selection follows the chapter's first year, so it stays put while an edit moves the chapters.
- **The chosen chapter.** Below the strip, at the page's full width whatever the chapter's length: its number, name, span and length ("54 to 67 · 2042 to 2055 · 13 years"). Then two parts, one to read and one to change: side by side on the Mac and iPad (the settings 380 points wide), the settings under the words on iPhone. Each value has one place where it changes.
  - **What happens**, in words that only read, their values in bold: "You take home **4.500 €** a month and spend **3.000 €**, so you save about 1.500 €.", "You stop working **as early as you can**, at 54 in 2042, and spend **3.000 €** a month, all from your savings.", "**State pension** pays **1.100 €** a month from **67**.", "In **2031** you spend **25.000 €** on **New car**." Amounts are a month's, from the plan's yearly ones, in today's money. An uncertain windfall says what it's worth to the answer: "At **62** you may receive **150.000 €** from **Inheritance**, **80%** likely; without it, your earliest age would be 56." ([PLANNER.md](PLANNER.md#ages-without)).
  - **A month**: a month's money as one bar, every chapter's on the same scale. While working, pay spent and saved ("Pay 4.500 € · spend 3.000 €", "save 1.500 €"), or, when pay falls short, what your savings add; retired, what comes from your savings and, once calculated, the tax on what's sold in the median run; with pensions, what they pay and what's left to draw or to spare.
  - **Along the way, typically**: the milestones the median future reaches in the chapter, a flag, the name and when ("400.000 €", "mid 2027"), four at most, then "And 2 more ahead."
  - **What can go wrong**, once calculated: in the bridge, "In 3 in 100 futures, the money you can draw runs out before Fondo pensione opens at 67."; in a chapter where futures run out, "Most of the futures that run out here do so before 85."
  - **Settings** ("A month, in today's EUR"): every input that starts in the chapter, once, as a row with an icon, its name and second line, and its value: when work stops ("As early as you can", "At 54, in 2042"), spending while working or in retirement and flexible spending ("Never below 80%", "Off"), a later phase of spending ("Spending from 75", "90% of spending in retirement"), work phases ("Employee", "2026–42 · take-home pay · grows 1% a year"), pensions ("From 67, after tax"), contributions ("Into Fondo pensione", "Until you stop working", or "Once, in 2031" with its amount), events ("At 62 · 80% likely", "+150.000 €"), the target mix and its changes with age ("Your savings from 60", "60% in shares") and the plan's end in the last chapter. A value opens its small editor (a popover pointing at the row on the Mac and iPad, a sheet on iPhone): its field, stepper or switch, applied as you type, and for an item's value a way to the item's whole sheet; an item opens its sheet, and the target mix its own. An input's problems show on its row. Under the rows, what carries on from earlier chapters ("Continuing: Spending while working · Saving into Fondo pensione · Target mix"), and **Add to this chapter**: before retirement, a work phase (from the chapter's first day) or a contribution (in a later chapter, a one-off in its first year); in retirement, a pension from the chapter's first age or a later spending phase from its middle; in any, an event in its first year.
- **The age they're cut at.** Work stops at the age the charts are for: one chosen on the chance-by-age chart, else the what-if's, else the plan's own, else the earliest age the plan found, else the one recorded at the last check-in. A plan asking for the earliest age with none of these yet assumes 65 until it's calculated, and says so where work stops. When the charts are for an age chosen on the chart, it says that, with *Plan's age*.
- **Outside the plan's years.** Inputs that apply in no year the plan runs (an event after its end, a work phase over before it starts, a pension without an age) are listed after the chapter as settings, like the rest. Without a birth date there are no chapters: a card asks for it instead.
- **Every chapter assumes.** What every chapter shares, as tiles that open their small editors: **Shares** and **Bonds** ("5%", a typical year above inflation), **Inflation** ("2%"), **Tax on gains** ("26%", or "Not set"), **Wealth tax** ("0.2%", or "None") and **Your bar** ("9 in 10" futures where the money lasts); three to a row on the Mac and iPad, two on iPhone. Then *All assumptions…*, *Export Calculations…* and the disclaimer. *All assumptions…* is a sheet of collapsible cards with a one-line summary each: **You** (the birth date, as in Settings), **Taxes**, **Assumptions**, **Target mix** and **Simulation**.
- **More charts**, folded away: the charts behind the answer ([below](#more-charts)), *Your money over time* first, the rest in two columns on the Mac and iPad.
- **Staying in view.** The answer heads the page. Once an edit makes it out of date, the banner under it says so, with *Recalculate*; on the Mac *Recalculate* (⌘R) is also in the toolbar.

#### More charts

- **Your money over time.** The money over the plan's length as a fan in one hue (the median, a darker 25–75% band and a lighter 10–90% one), with your actual past values in ink, in today's money with the library's inflation index, and markers for retirement, pensions starting, locked money opening, windfalls and large expenses. The time span menu, shared with the Overview's, sets how far back and ahead it reaches (retirement + 15 years by default). The value axis fits your history, the median and the 25–75% band; the 10–90% band may run off the top, and the legend says so.
- **Chance of success by retirement age.**
  - One line; a dotted rule at your confidence level, labelled at its right end, below the rule where the curve ends above it; the earliest age marked where they cross.
  - The age axis runs from today's age to the last age simulated, labelled every 5 years (every 10 when narrow), never from 0.
  - Tapping (or clicking) another age makes it the age the charts and the chapters are for; dragging across the curve, or hovering over it on the Mac, only shows the chance at each age. Charts calculated before for that age show at once; otherwise the banner offers *Calculate* for it.
  - Steps where a pension starts or an account opens show as steps.
- **In today's money,** in the library's base currency ("In today's EUR.").
- **Retirement income.**
  - Stacked areas, one flat step a year, by source: withdrawals, work (the year you retire), pensions and windfalls, then the taxes they pay in grey on top. A source is labelled by its name when there's only one ("State pension"), else as a group ("Pensions"). The spending target is a dashed line, labelled "Spending" at its end, outside the areas. Years are labelled every 5 or 10.
  - *Why the taxes are on top:* a withdrawal is what's sold: it pays the tax on the gain part of the sale, the year's wealth tax and last year's tax on investment income as well as the spending. So that the chart reads against the spending line, each source is shown after its share of the year's taxes (in proportion), and the taxes are the grey band: the sources reach the spending line (plus expenses and what's saved), the stack the income before those taxes. The year the money runs out falls short of the line.
  - A one-off (a windfall) that would flatten the rest runs off the top, with a note under the chart: "Inheritance in 2050 (150k €) runs off the top."
  - *Taxes* switches to the same years stacked by tax: the tax on investments (on what's sold and on investment income) and the wealth tax.
- **Key numbers.** Earliest retirement and its date, the chance at the target age and what you could spend then (the engine's solver for the highest spending that still meets your confidence level), what retiring today would need ([PLANNER.md](PLANNER.md#assets-needed-to-retire-today)): "Needed to retire today", "Extra in accounts you can draw now" and "You have 58%", or "At most what's locked away" when retiring today works even with the money you can draw emptied; the median at retirement and at the end, lifetime taxes, and how often the money runs out before a locked account opens.
- **Problems** are worded for the screen: accounts by their names, not their IDs ("A contribution goes into Fondo pensione, which the plan doesn't count; it's left out.").
- **What if.** "Try a change before you make it in the plan." On iPhone in a bottom sheet; on the Mac and iPad in a column 340 points wide beside the plan, from *Show What If* in the toolbar (from Progress it goes back to the plan, whose answer it changes). Not an inspector: the window's split view wouldn't narrow the page for one, which then ran past the window's edge. Beside it the page is narrower, so the answer's pill goes under its words, the chosen chapter's settings under its words, and what every chapter assumes two to a row.
  - The plan's answer now ("Your plan now · Not yet. Stop at 63."), then sliders, their values in words: **Stop working at** ("55"), **Spending** ("3.000 € a month", in retirement; the plan keeps it a year), **Saving** ("333 € a month", while working; "After Calculate" until the plan has run) and **Shares, above inflation** ("3.14% a year": equity's typical year, its median real return, as the defaults are given; the mean follows from the plan's volatility). Spending and saving move 50 a month at a time.
  - Moving a slider runs nothing. The answer says "From before your what-if changes" until **Run What If** runs it: "A quick estimate first, then the full answer": fewer runs, then all 2,000, with the same random draws, its progress in place of the buttons. A position calculated before shows again at once.
  - Once it has run, the answer shows the difference ("With your changes · Earliest 54 → 53").
  - *Keep* writes the change into the plan (its results become the plan's own); *Reset* throws it away.

#### The editors

- **New plans and items.** A new plan retires as early as possible, and takes its tax rates and spending from the main plan (else another plan), since you've said them already. A library without plans starts from 30.000 euros' worth of spending in its base currency at its latest exchange rate, to two significant figures (35.000 for dollars, 4.800.000 for yen), or 30.000 when it has no rate to the euro, and with no tax rate on investments, which the plan asks for before it runs. A new work phase earns 4/3 of the plan's spending while working, a new contribution is a thirtieth of it a year and a new event an expense of a third, so every default is in the plan's own money; a new pension starts at 67, with its amount to enter.
- **Amounts a month.** The settings, the small editors and the sheets take amounts a month, as the words say them (the plan stores them a year: a month typed in counts twelve times). One-offs, events and the wealth tax's allowance are their amount.
- **Work phases.** Each is a setting in the chapter it starts in ("Employee", "2026–28 · take-home pay · grows 1% a year", "3.333 €"). The editor has the name, the dates (from, and until a date or retirement), **Take-home pay** a month and an optional real growth: "What reaches your bank account in a month, after income tax and social contributions, in today's EUR. Growth is a year, above inflation."
- **Pensions.** Each is a setting ("State pension", "From 67, after tax", "1.167 €"). The editor has the name, the age it's paid from, and **After tax, a month**: "From your pension statement, after the tax you expect to pay on it, in today's EUR."
- **Contributions.** Each is a setting ("Into Fondo pensione", "Until you stop working", "417 €"). The editor picks the account it goes into ("Paid into the account, and drawn once it's available (Available from age on the account). The rest of your savings goes to the money you can draw."), and whether it's paid every month (**A month**, until retirement or a date) or once, in a year.
- **Spending.** While working (in the first chapter), in retirement (where you retire), and the later phases (from an age, a share of it, where each begins). Under spending in retirement, folded away, **Flexible spending** ([PLANNER.md](PLANNER.md#flexible-spending)):

  ```
  Flexible spending                      [ ● ]
  Cuts spending in retirement after bad years and restores it after good ones, as real
  retirees do, instead of spending the same whatever the markets do. A future only fails
  if you'd have to spend less than the floor.
  Cut by                                [10] %
  Never below                           [80] %
  of the plan's spending: 28.800 €/yr
  ▸ Guardrails
      Cut when it rises by              [20] %
      Restore when it falls by          [20] %
      Each year the plan compares the share of your money you draw with the first year of
      retirement's: this much above it, spending is cut; this much below it, a cut is restored.
  ```

  - The switch writes `{ "enabled": true }`; turning it off keeps settings that differ from the defaults (`enabled: false`), and with only defaults removes the rule, so nothing is written.
  - The fields show the defaults as their prompts; a field left empty, or set to its default, isn't written. *Never below* is also shown in money: the floor share of the retirement spending, before the phases, hidden with the eye.
  - The guardrails are folded away (*Guardrails*, a disclosure group). Settings out of range show as errors above the chapters.
- **Taxes** ([PLANNER.md](PLANNER.md#the-model-in-brief)):

  ```
  Tax on investments                    [26] %
  Paid on the gain part of what you sell and, every year, on the income your
  investments pay out (Assumptions, income yield). 26% in Italy, for example; 0% if
  they aren't taxed. Income from work and pensions is entered after tax.
  ──────────────────────────────────────────
  Wealth tax                             [ ● ]
  Rate                                [0.2] %/yr
  Untaxed allowance                  [5000] EUR
  A yearly tax on the money you can draw, above the allowance. Accounts available only
  from a later age, such as a pension fund, aren't counted until then.
  ```

  - The rate on investments is required: until it's set, the card shows the error and the summary says "Tax on investments not set".
  - Turning the wealth tax off removes its rate and allowance from the plan.
- **Assumptions.** Inflation, then each class's real return as its mean and its median, and its volatility, three fields a row ("Crypto 16.6 % · 0 % · 70 %"). Either return can be typed: the other follows from it and the volatility, and changing the volatility keeps the one that was given (crypto's default is given by its median). The line under them: "Placeholders to review, not forecasts: real returns after fund costs. The mean is the average year, the median the typical one, which a portfolio rebalanced every year grows at. Enter either: the other follows from the volatility." What equals the default isn't written to the plan. A class whose return and volatility are exactly an earlier version's default, which that version wrote into the plan when one of the class's numbers was edited ([PLANNER.md](PLANNER.md#returns)), gets a line under its row: "This is the previous default (4.5% average). The current default is a 5.0% typical year.", with a *Use Default* button that removes the plan's entry for the class (keeping its income yield), so it follows the current default. Nothing changes until it's tapped. The card's summary counts them ("4 previous default returns"), and it shows equity's return as it's given: "Equity 5% typical year", or "Equity 4,5% average". Then an optional **income yield** for equity and bonds: "The part of the return paid out as income each year (dividends, interest), taxed every year at the rate on investments. Leave it empty to count it as growth, taxed when sold." Then the estimate of unrealised gains for holdings without a purchase cost, and the accounts in the plan, each with a switch. A class the portfolio holds whose median is below −2% a year gets a warning on the card: "Crypto's returns give a typical year of −18% (an average of 0.0% at 70% volatility): holding it and rebalancing back into it every year shrinks your portfolio. Check its return under Assumptions."
- **Target mix.** A card of its own in *All assumptions…*, after Assumptions, and a sheet of its own from the chapters' words: the mix the plan rebalances the money you can draw to every year ([PLANNER.md](PLANNER.md#target-mix)). Its first line says what that does: "Each year the plan rebalances the money you can draw back to this mix: new money goes in at it, withdrawals sell every class alike, and rebalancing isn't taxed."

  ```
  [ Today's mix | A mix I choose ]
  Class      Today    Target   Median
  Equity       46%    [80] %     5.0%
             44% of all
  Bonds         0%    [20] %     1.5%
              5% of all
  Crypto       35%    [  ] %     0.0%
             28% of all
  ✓ Total 100%
  Grows at a median of 4.5% a year, rebalanced every year (today's mix: 3.0%).
  Changes with age
  ╭ From retirement      ⊖ ╮ ╭ From 75             ⊖ ╮
  │ [At an age|At retirement]│ │ [At an age|At retirement]│
  │ Equity          [60] %   │ │ Equity          [40] %   │
  │ Bonds           [40] %   │ │ Bonds           [60] %   │
  ╰──────────────────────────╯ ╰──────────────────────────╯
  + Add a change with age
  Accounts available only from a later age, such as a pension fund, keep their own mix until then.
  ```

  - **Today's mix or a mix I choose.** *Today's mix* writes nothing (no `targetMix`): the money you can draw is rebalanced back to its own mix today, crypto included, and a line says so, with how that mix grows. *A mix I choose* starts from today's mix of the money you can draw in whole percentages, to edit; going back to *Today's mix* removes the mix and its changes with age.
  - **Per asset class** (equity, bonds, cash, gold, crypto, real estate, and any other class held today or named in the plan): *Today*, its share of the money you can draw, with its share of all plan assets under it ("44% of all"); *Target*, a percentage typed as you go (an empty field or 0 leaves the class out); *Median*, its median real return from the assumptions, so what a class like crypto does to the mix is in view.
  - **The total** runs under the table: "✓ Total 100%", or an error line until it is ("Total 95%. Adds up to 95%: add 5% to reach 100%."); a plan saved short of 100% runs scaled, with a warning on the card. Then the mix's median growth, rebalanced every year, against today's mix's.
  - **Changes with age.** A card per change, side by side when there's room (one column on iPhone, two or three on a wide iPad or Mac window), each starting *At an age* (a stepper kept after today's age and between the changes before and after it) or *At retirement* ("The year you stop working, whatever age the plan finds"), with its own percentages, total and growth. *Add a change with age* adds one from retirement first, then ten years after the last, starting from the mix before it. A change whose age has passed says "You're 56: this already applies from the start." with **Make it the target mix**, which makes it the target from today so every version reads the plan the same.
  - **VoiceOver** reads each class as its name, today's shares in words ("Equity today: 46% of the money you can draw, 44% of all plan assets"), its target field ("Equity target, percent") and its median ("Equity median return 5.0% a year"); the column headers are hidden from it, and each change's title is a heading.
  - Issues about the target mix (a total, ages that don't go up, a change after the plan's end) show on this card; the summary reads "Today's mix", or "Equity 80% · bonds 20% · changes at retirement and 75".
- **Simulation.** The number of runs, the confidence a "yes" needs, and the random seed.
- **Validation.** Issues appear on the row of the work phase, pension, contribution or event they're about, on the *All assumptions* card they concern, and the rest (spending's, and those about a whole list) above the chapters:
  - ⚠︎ for warnings, e.g. "State pension starts after the plan's end age, so the plan never pays it.";
  - ⛔︎ for errors that stop the plan from running, e.g. "Employee: enter the income after tax for this phase (netIncome)."

### Progress

See [PROGRESS.md](PROGRESS.md).

```
┌──────────────────────────────────────────┐
│ Base case ▾                          ⋯   │
│            Plan  [ Progress ]            │
│ ╭──────────────────────────────────────╮ │
│ │ Are you on track?                    │ │
│ │ Ahead of plan.                       │ │
│ │ You have 21.572 € more than January  │ │
│ │ expected, more than in 9 of its 10   │ │
│ │ futures.                             │ │
│ │ ╭ To go ──────────╮╭ Since Jan 2026 ╮│ │
│ │ │ 24½ years       ││ A year sooner  ││ │
│ │ ╰─────────────────╯╰────────────────╯│ │
│ │ September: you saved 1.532 € and     │ │
│ │ markets added 3.236 €.               │ │
│ ╰──────────────────────────────────────╯ │
│ Year by year                             │
│ Scroll back through the years; tap one.  │
│ ╭──────╮╭──────────────────────────────╮ │
│ │2025  ││ 2026 so far                  │ │
│ │132k →││ 21.572 € ahead of January    │ │
│ │134k  ││                      160k €  │ │
│ │      ││       Coast point ⚑ ┃Today ░ │ │
│ │      ││  150.000 € ⚑   ▅▆▇● ┃░░░░░░░ │ │
│ │      ││ ▁▂▃▄▅▆▇▇            ┃░░░░░░░ │ │
│ │      ││ ┅┅┅┅┅┅┅┅┅┅┅┅┅┅┅┅┅┅┅┅┃┅┅┅┅┅┅┅ │ │
│ │      ││ January expected    ┃ 120k € │ │
│ │      ││ J F M A M J J A S O N D      │ │
│ │Show  ││ (55)      (54)               │ │
│ ╰──────╯╰──────────────────────────────╯ │
│ ╭──────────────────────────────────────╮ │
│ │ 2026 so far                   ‹  ›   │ │
│ │ A year sooner, and past 150.000 €.   │ │
│ │ ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇┃▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇  │ │
│ │           planned by now             │ │
│ │ You saved 20.486 € · markets added   │ │
│ │ 6.628 €                              │ │
│ │ Mar    You saved 9.121 €, more than  │ │
│ │        usual.                        │ │
│ │ May  ⚑ Plan changed. Passed          │ │
│ │        150.000 €.                    │ │
│ │ Jun    54, a year sooner.            │ │
│ │ Aug  ⚑ Passed the coast point: 67.   │ │
│ │ ──────────────────────────────────── │ │
│ │ Why you're ahead                     │ │
│ │ Going into 2026           +12.557 €  │ │
│ │ On 31 Dec you had 134.392 €; January │ │
│ │ started from 121.835 €.              │ │
│ │ Saving                     +7.023 €  │ │
│ │ You saved 20.486 €; January planned  │ │
│ │ 13.463 € by now.                     │ │
│ │ Markets                    +4.645 €  │ │
│ │ They added 6.628 €; January expected │ │
│ │ 1.982 €.                             │ │
│ │ Inflation                  −2.654 €  │ │
│ │ ──────────────────────────────────── │ │
│ │ Ahead of January          +21.572 €  │ │
│ │ January expected 137.280 € by now,   │ │
│ │ in January's money.                  │ │
│ ╰──────────────────────────────────────╯ │
│ ╭──────────────────────────────────────╮ │
│ │ ⚑ Next milestone                     │ │
│ │ 5 years of spending        90% there │ │
│ │ ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇░░░░ │ │
│ │ 180.000 € · typically by late 2028   │ │
│ │ ──────────────────────────────────── │ │
│ │ Saving nothing more     retire at 71 │ │
│ │ In August it was 67, when your first │ │
│ │ pension starts: the coast point.     │ │
│ │ ──────────────────────────────────── │ │
│ │ All Milestones                     › │ │
│ ╰──────────────────────────────────────╯ │
│ ╭──────────────────────────────────────╮ │
│ │ Next in your plan                    │ │
│ │ ② Self-employed, from 41 in 2029 Open│ │
│ │ [          Save Baseline…          ] │ │
│ │ Freeze what you expect now, to       │ │
│ │ measure against it later.            │ │
│ │ Add a Past Baseline…                 │ │
│ ╰──────────────────────────────────────╯ │
│ ▸ More charts                            │
└──────────────────────────────────────────┘
```

- **Are you on track?** Where the latest check-in stands against this year's automatic baseline: "Ahead of plan.", "Behind plan." or "On plan." (within 1% of its median), then "You have 21.572 € more than January expected, more than in 9 of its 10 futures." Without a baseline for the year, "Not measured yet." and how one is made; while this year's baseline starts at the latest check-in, that the next check-in is the first measured against it. Then two figures, the time to go until the earliest date ("To go · 24½ years") and how the answer moved since the first check-in that recorded one ("Since Jan 2026 · A year sooner"), and the last check-in's month in a sentence ("September: you saved 1.532 € and markets added 3.236 €."). On the Mac and iPad the three are tiles, as wide as their figures ("September · Saved 1.532 € · markets +3.236 €"), beside the words when there's room for both, else under them. To go comes from the plan's results, else from the answer recorded at the latest check-in.
- **Year by year.** "Scroll back through the years; tap one." ("Scroll back, or use the arrows." on the Mac and iPad, with ‹ › and *Today* beside it). A card per calendar year from your first record of a plan asset (a value, or a trade) through the latest check-in, oldest on the left. A year without a check-in is valued from what you held and its prices ("No check-ins · from prices"), and the line runs through each check-in and the end of every month without one, to 31 December (this year's to the latest check-in), so what only a check-in can tell, like a bank balance, shows as a step at the next one; the strip opens at today, on the right. Each card is a year wide (26 points a month on the Mac and iPad, 21 on iPhone), and the cards on screen share one money scale fitted to their values rather than from zero, so a year's movement shows however far its money is from other years', and December of one year meets January of the next; when the strip comes to rest after scrolling, the scale refits to the cards then on screen, the lines fading to their new places. The cards name their own lines, so there's no key:
  - its year and change ("2025 +41.200 €", "2026 so far"), and where it ended against January, in green ahead ("21.572 € ahead of January") and orange behind ("3.000 € behind January"), against the month its baseline was saved in when the year's first check-in came after January ("2.100 € ahead of October"), or "Measured from your next check-in" while its baseline starts at the latest check-in, or "No January baseline";
  - your money through it, an ink line from January: solid into each check-in, with a small dot there, lighter where it's valued from what you held and its prices, dotted where a price or a rate is missing (those holdings count as zero), with a larger dot at the last; against what January expected: the year's automatic baseline's median, dashed, from its start to the year's end, labelled where it starts ("January expected"), on the side away from your line; between the two, green where you're ahead and orange where behind. With a baseline the line is the baseline's accounts, in money of its start where an inflation index allows, also before a baseline saved later in the year, where nothing is shaded; without one, plan assets in the base currency. On this year's card *Today* is a line down the graph, the rest of the year shaded after it;
  - the milestones reached, on the line: the year's first and last named beside a filled flag ("150.000 €", "Coast point"), the last alone when their names would run into each other, the rest small dots;
  - the gridlines' amounts at the card's edge where nothing is drawn: the right, where the rest of this year is still to come, unless your line ends there;
  - the months' initials along its bottom, and under them the answer: where the year started (outlined), and each check-in where it moved, in the accent when it came sooner, grey when later, violet when the plan changed. A chip without room is left out.
  - **Reading the line.** The pointer over a card (the Mac, an iPad with a pointer), or a finger touched and held on it, then dragged (iPhone; the strip stays put until it lifts), reads the line at the nearest check-in or month end: a rule, a dot and a label with the date and where the value comes from ("31 Mar 2026 · check-in", "30 Apr 2026 · from prices"), the money ("312.480 €"), what January expected and the gap, from the baseline's start ("January expected 305.000 €", "7.480 € ahead"), a milestone reached there ("Passed 300.000 €."), what changed that day ("55, a year sooner.") and, when a price or a rate was missing, "Not every price is known". Amounts hide with the eye.
  - Choosing a card selects it, outlined in the accent; ‹ › (⌘[ and ⌘] with a keyboard) step through the years, and on the Mac and iPad *Today* goes back to this year's.
  - **VoiceOver and text size.** Each card is read as its year, change, where it stands and the year in a line, and as a chart: its audio graph and chart details give your money at each point and what was expected. The cards' graphs and labels grow with the text size up to the third-largest standard size, with room above and below the graph; past it they stop growing, and the year's words carry them at any size. The same goes for the plan's chapter cards.
  - The years before your first recorded answer are folded into one card at the strip's start ("2021–2023", "148.000 € → 205.000 €", "Before your first answer.", "⚑ 3 milestones") with *Show*, which lays them out as the others; choosing one of them with the arrows shows them too, and they stay laid out. On iPhone it's narrow, beside this year's card: the years, the amounts in short and *Show*.
- **The year's words**, said once: on iPhone below the strip for the chosen year, headed by its title and change with ‹ ›; on the Mac and iPad in each year's card, under its graph.
  - The year in a line: how the answer moved, the milestone it passed and what markets did, at most two of them ("A year sooner, and past 150.000 €.", "A strong year for markets, and a year sooner."); for a year whose check-ins stop early, "No check-ins after June: what you held is valued at its prices."
  - What you saved and what markets added as one bar, with a mark where January planned your saving to be ("planned by now"; "planned" for a past year), and the two in words in the bar's colours ("You saved 20.486 € · markets added 6.628 €").
  - What happened, a row a month, a month with a milestone flagged and the milestone in bold ("Mar · You saved 9.121 €, more than usual.", "May · ⚑ Plan changed. **Passed 150.000 €.**", "Jun · 55 again.", "Aug · ⚑ **Passed the coast point: 67.**", "Calculations updated.").
  - Why ([PROGRESS.md](PROGRESS.md#actual-vs-a-baseline)): "Why you're ahead" ("Why you ended behind" for a past year), a row each, signed, in green or orange: the gap going into the year ("Going into 2026", "On 31 Dec you had 134.392 €; January started from 121.835 €."; against a baseline from before the year, what it expected then; where past values changed after the baseline was saved, the library's value on its start), saving ("You saved 20.486 €; January planned 13.463 € by now."), markets ("They added 6.628 €; January expected 1.982 €."), inflation and the rest ("Balances that changed without a recorded flow, and exchange rates."). Then the total, "Ahead of January +21.572 €", "January expected 137.280 € by now, in January's money." (for a past year by 31 Dec, and how that compares with its futures: "That's more than in 68 of its 100 futures."). Without the split, January's note instead.
  - A year with missing prices or rates says that those holdings count as zero and the line is dotted there, with *Fill In Past Prices…*. A year without a baseline offers *Add What You Planned in 2021…*, which opens *Add Past Baseline…* on its first day.
- **Milestones**, after the year's words on iPhone, beside the strip on the Mac and iPad ([Milestones](#milestones)): the next, how far there and when it typically comes; saving nothing more, when you could still retire, and when you reached the coast point; *All Milestones*, every milestone reached and ahead, in a sheet.
- **Next in your plan.** The chapter after the current one ("② Bridge, from 54 in 2042") with *Open*; then the one button, *Save Baseline…*, which takes a label ("Freeze what you expect now, to measure against it later."); and quietly under it *Add a Past Baseline…*. On the Mac and iPad under the milestones, beside the strip.
- **Add Past Baseline…** ([PROGRESS.md](PROGRESS.md#past-baselines)): a sheet for what you planned before you used the app. *Planned on* (a day from your first record of a plan asset to your latest check-in, starting at the end of the first month) with your plan assets that day; **What you planned then**: take-home pay, spending while working, when to stop working and spending in retirement, a month each, starting from today's plan ("Returns, taxes, pensions, events and the rest are as in today's plan."); a name ("What I planned in 2021" when left empty). *Calculate and Save* runs the plan from that day and saves it; the baseline picker lists it as "What I planned in 2021 (added 6 Oct 2026)", and the years without their own baseline are measured against it ("12.400 € ahead of your 2021 plan", "Your 2021 plan expected …").
- **More charts**, folded away:
  - **Your answer over time.** The earliest retirement age at each check-in, as a step line. Markers show where you changed the plan or where the app's calculations changed. A check-in's callout adds its readiness ("58% of what retiring today needed") when it was recorded; the old FI progress isn't shown.
  - **Actual vs baseline.** Pick a baseline, e.g. "Start of 2026 (automatic)" or "Before part-time (saved 12 Mar)". Its fan chart runs from its start date, with your actual line drawn over it: the same accounts at each check-in, in money of the start date where the inflation index allows. A line under the chart says which. A summary: "12.400 € ahead of the median · 61st percentile". Why it's ahead or behind shows on each year of the strip.

### Milestones

The points you pass on the way ([PROGRESS.md](PROGRESS.md#milestones)): round amounts of plan assets, years of the spending you plan for retirement, shares of what retiring today needs, and the crossover, where a typical year's growth adds as much as you save. They're there to notice progress between the rare moves of the answer, calmly: a flag, a sentence, a row in a list. No badges, confetti or streaks, and nothing is taken away when markets fall back.

```
┌──────────────────────────────────────────┐
│ Milestones                               │
│ ⚑ Next milestone                88% there│
│ 400.000 €                                │
│ ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇░░░░░   │
│ Typically by mid 2027.                   │
│ ──────────────────────────────────────── │
│ Reached                                  │
│ ⚑ 300.000 €                    Jun 2026  │
│ ⚑ A third of what retiring…    Jun 2026  │
│ ⚑ 250.000 €                    Aug 2025  │
│ Ahead, typically                         │
│ ⚐ 10 years of spending         early 2028│
│ ⚐ 400.000 €                    early 2029│
└──────────────────────────────────────────┘
```

- **Progress.** A card after the year's words (beside the strip on the Mac and iPad): the next milestone ("⚑ Next milestone", "5 years of spending · 90% there") with how far there as a bar, and what its name doesn't say and when the median future typically reaches it ("180.000 € · typically by late 2028"); saving nothing more (below); and *All Milestones*, a sheet with the next, what's been reached, newest first, and what's ahead, soonest first (five of each, *Show All* for the rest; side by side on the Mac and iPad). On a year's card, a flag on the line at the check-in or the month end that reached one (in the years before your first check-in too): filled and named for the year's first and last, a small dot for the rest; and in the year's words, the month's row flagged, the milestone in bold ("Jun · ⚑ **Passed 300.000 €.**"). Notable check-ins join the rows too: "You saved 3.200 €, more than usual.", "Markets fell 24.500 €, 8%.", "Saved the year's baseline."
- **Plan.** On the chapter cards, on the median where it reaches one: the chapter's first and last named, with an outlined flag and when ("10 years of spending", "early 2037"), the rest small dots; and in the chosen chapter's words: "Along the way, typically: 400.000 € in mid 2027 and 10 years of spending in early 2028." (The answer no longer has the next milestone under it: Progress has it.)
- **Check-in.** After saving, the milestones passed since the check-in before, at this one or at a month end between them, each a line with a flag ("Passed 300.000 €."). The shares of what retiring today needs and the coast point come with the month's answer, and show on Progress.
- **The coast age.** On Progress's Milestones card, once a calculation or a check-in has worked it out ([PLANNER.md](PLANNER.md#ages-without)): "Saving nothing more · retire at 71", in green once it's at or under the coast point, and under it where it stands against the coast point: "In August it was 67, when your first pension starts: the coast point." once you'd reached it and the age has moved since, "The coast point is 67, when your first pension starts.", or "You're past the coast point: your first pension starts at 67." The *All Milestones* sheet says it in full ("If you stopped saving today, you could still retire at 63; the coast point is 67, when your first pension starts."), and so do the plan's key numbers. The coast point is a milestone: the check-in whose recorded coast age first comes down to the age the first pension starts ("Passed the coast point: saving nothing more, you could still retire at 67.").
- **The widget.** *Next milestone* shows the next one, its bar and when it typically comes ([Widgets](#widgets)).
- **Words.** A round amount is its amount ("A round amount" while amounts are hidden); "10 years of spending" ("Enough for 10 years of the spending you plan for retirement."); "Half of what retiring today needs" ("Halfway to what retiring today needs."), and all of it "All that retiring today needs: you could stop."; "The crossover" ("A typical year now adds more than you save."). Dates ahead are a part of a year, "early", "mid" or "late 2028", since they're the median of many futures.

### Export Calculations

When an answer looks wrong ("I need 2 million to withdraw 20,000 a year?"), *Export Calculations…* in the plan picker's menu (iPhone, iPad and Mac) and in the Mac's Plan menu writes every calculation behind it as Markdown ([PLANNER.md](PLANNER.md#calculations)), for the plan on screen (with its what-if, when one is in use), to check it or give to someone else. It's a small sheet:

```
┌──────────────────────────────────────────┐
│            Export Calculations     Done  │
│ Anonymize                          [ ● ] │
│ Round amounts to       The nearest 100 ▾ │
│ Leaves out names, account and plan names │
│ and exact dates, and rounds amounts, so  │
│ the file can be given to someone else.   │
│ ⇪ Share Plan calculations.md…            │
│ ⇩ Save Plan calculations.md…             │
│ Markdown: the plan as read, the starting │
│ portfolio, the chance of success by      │
│ retirement age, the expected and median  │
│ runs year by year, and why runs fail.    │
└──────────────────────────────────────────┘
```

- **Anonymize** is on by default, with the rounding: whole amounts, or the nearest 100, 1,000 or 10,000.
- The plan runs in full off the main thread while the sheet shows "Calculating…", and again whenever an option changes; then **Share…** hands the file to the share sheet (Save to Files on iPhone), and on the Mac **Save…** opens a save panel. A plan that can't run says why.
- The file, *Plan calculations.md* anonymized or *Base case calculations.md* (the plan's name) otherwise, is written to a temporary folder. While amounts are hidden, the file still holds them.

## Import (Mac first)

A window with steps along the top, as described in [IMPORT.md](IMPORT.md):

1. **File.** A drop zone, or the result of dragging a file onto the app.
2. **Format.** The detected settings, each a picker with a live sample: encoding, delimiter, header row, decimal and thousands separators, date format, and whether empty cells are skipped.
3. **Columns.** A table: the column header, sample values, *Imports as* (Balance of…, Quantity of…, Price of…, Ignore), and a per-column format override. The layout: a row per date, per record, or per trade.
4. **Accounts.** Names in the file matched to accounts (existing, new, or ignored), plus proposed closings, which are off until you turn them on.
5. **Preview.** The parsed grid with errors highlighted, counts (new, updated, identical, conflicting), and the conflict policy.
6. **Done.** A summary, **Undo import**, and **Save as profile**. When the import's positions are valued on dates without a price, a **Past prices** section lists them ("12 past values have no price for XAU") with **Fill In Past Prices…** ([Adding history](#adding-history)).

A broker's transactions (Directa's or Fineco's movements, Degiro's or IBKR's exports) are recognised when the file is read and imported as trades, *A row per trade* ([IMPORT.md](IMPORT.md#broker-transactions)):

- **Columns** offers the trade's fields (Date, Trade type, Instrument, Quantity, Price, Currency, Amount (net), Gross amount, Fees, Tax, Split ratio, Note) and *Account of every row* when the file has no account column. An amount column's format says how its signs are read.
- **Types**, between Columns and Accounts: each word the file uses for a transaction ("Acquisto", "Ritenuta su dividendo", "Giroconto") with its number of rows, where its type comes from (the usual word, set by you or the profile), and a picker of trade types, or *Leave out*. A word the importer doesn't know shows a warning and its rows are left out until you choose; nothing is guessed. Below, how amounts are signed (automatic, without signs: from the type, signed: as written) and notes on how the file's signs were read.
- **Accounts** proposes making an account record trades when the file has trades for one that doesn't, with what that changes. It's off until you turn it on; while off, its trades are left out. Or choose another account.
- **Preview** shows the trades like other records ("Directa, buy, 12 Jan 2026 · Buy 15 VWCE at 102,30 · −1.539,50 € · fees 5 €"), with how many of the records are trades; **Done** counts them, names the accounts now recording trades, and has **Undo import** as always.

On iPhone, a CSV opened from Files goes straight to "Import with profile…": choose the profile, preview, import.

## Settings

| Section | Contents |
| --- | --- |
| Library | Location (iCloud Drive or this device), Show in Files/Finder, for a library on this device *Move to iCloud Drive* (refused when iCloud Drive already has one) and *Use the iCloud Drive Library* (opens that one; this one stays on the device), sync status, merged conflicts, backups, the file format docs, and *Export as CSV…*: a sheet that writes the library as CSV files ([schema/README.md](schema/README.md#csv-export)), zipped as *Can I Retire Yet CSV 2026-09-30.zip*, with *Share…* and on the Mac *Save…* |
| You | Name, birth date, base currency, country (it picks the default inflation index), and **Inflation**: *Automatic: Italy* (the tax residence's HICP, else the base currency's; `inflationIndex` left out) or a choice of the euro area and every country with an HICP |
| Prices | Price source per instrument kind: *Yahoo Finance (unofficial)* (so named wherever a price source is chosen or shown with an instrument; the footer says it has no official interface for apps and may stop working), CoinGecko with *Powered by CoinGecko* linking to coingecko.com (its attribution), gold-api.com, ECB via Frankfurter, and Eurostat HICP for inflation; API keys (stored in the Keychain), fetch on check-in |
| Check-in reminder | Day of the month and time. This device only, so you aren't reminded twice. |
| Privacy | Hide amounts, hide amounts when the app opens, and (iPhone and iPad) cover the app in the app switcher: the whole screen is covered while the app isn't active. The footer says only that. A Face ID lock is planned (M3), not built. |
| About | The version and the library's format, and under them: "Results are estimates from a simplified model with the returns, taxes and pensions you enter. Plans take your income and pensions after tax, and tax your investments at the rates you set. They aren't financial, tax or legal advice: check important decisions with a professional." |

## Design system

**Look.**

- System components and Liquid Glass on iOS 26 and macOS 26: a floating tab bar and toolbars, sheets with detents, the sidebar and the inspector.
- Glass is only for controls that float above content (the tab bar accessory, floating buttons). Content (numbers, charts, forms) sits on plain surfaces, where it's most legible.

**Numbers.**

- The system font. Large standalone numbers use its default figures; columns that must line up (tables, check-in fields, axis labels) use tabular figures (`.monospacedDigit()`).
- Formatted for your locale and base currency: in Italian, `312.480 €`, with decimals only where they matter (check-in fields, account detail).
- **Quantities and unit prices** read the same everywhere (account holdings, the trades list, the check-in's positions, the instruments, the trade form, the review; `QuantityFormat`): a quantity has up to 8 decimals, trailing zeros trimmed (`0,10383916 BTC`, `412,5 sh`); a unit price (or an average cost per unit) is money in its own currency, with the currency's symbol, 2 decimals from 1 up (`73.785,11 €`, `165,00 $`) and 4 significant digits below (`0,004312 €`). The import's preview shows prices as read from the file.
- A label and its value are one piece of text ("Average cost 101.437,74 €"), so they wrap together; a line too narrow for both breaks between the label and the value.
- Charts use compact numbers (`312k`).
- Zero never has a sign: an amount that rounds to zero reads `0,00 €`, never `−0,00 €`, and an axis never reads `−0`.
- Dates in "since …" leave out the year only when it's this one: "since 30 Sep", "since 30 Nov 2021".

**Changes.** Always a sign and an arrow as well as colour: ▲ +4.210 in the success-green text colour, ▼ −240 in red. Never colour alone. A change that shows as zero gets neither: `0 €`, in grey.

**Colour in charts** follows the dataviz reference palette, in light and dark variants.

- **Asset classes** have fixed colours everywhere in the app. Their order is also the stacking order, from bottom to top, and was chosen to pass colour-blindness checks between neighbouring bands:

  | Cash | Bonds | Equity | Gold | Crypto | Real estate | Other | Debt |
  | --- | --- | --- | --- | --- | --- | --- | --- |
  | blue | orange | aqua | yellow | magenta | green | violet | red |

- **Retirement income** stacks its sources in a fixed order, each in its own slot of the same palette, so neighbours in the stack are neighbours in the validated order: withdrawals blue, work orange, pensions aqua, windfalls green, other red. The taxes on top are a neutral grey (the secondary ink colour), which stays apart from all eight hues in light and dark. Each band is a wash of its colour with a 2-point line in the colour along its top and a 2-point gap above the line, never a saturated block; net worth by asset class is drawn the same way.
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

- An eye button hides every amount (`•••••`) while charts keep their shape and a relative value axis: net worth (and an account's value) in multiples of today's (`0`, `1×`, `2×`), the plan's money (and the Overview's chart with *Future* on) in multiples of today's plan assets, retirement income in multiples of the spending. Only labels that would reveal amounts hide; the change since the last check-in shows in per cent.
- Amounts are marked `.privacySensitive()`, and the widgets hide them while the device is locked ([Widgets](#widgets)).
- *Cover the app in the app switcher* (iPhone and iPad) covers the whole screen while the app isn't active.
- Optional Face ID lock (M3, not built yet).

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

1. Welcome, with "The answers are estimates, not financial or tax advice."
2. Where to keep your data (iCloud Drive is recommended).
3. Birth date, base currency and country, starting from the device's currency and region (nothing else is assumed: without a region the country is *Not set*).
4. "Import a spreadsheet" or "Add accounts".
5. The first check-in.
6. "Create your first plan" (a guided form covering work, spending and pensions).

**Haptics.** A light tap on save, and when a what-if slider moves the earliest retirement age.

## Widgets

The glance: how am I doing, without opening the app. On the home screen of the iPhone and iPad, the iPhone's lock screen, and the Mac's desktop and Notification Center. Tapping one opens the app where it belongs: net worth on the Overview, the answer on the main plan, the check-in on the check-in.

| Widget | Sizes | What it shows |
| --- | --- | --- |
| **Time to retire** | small, medium; lock screen inline and rectangular | "Retire in 15 y 6 m", at 54 · April 2042, in 9 of 10 futures. The small one sits on the app icon's dusk; the medium one adds the earliest age at each check-in of the year as a step line, and "55 → 54 in June". On the lock screen: "Retire in 15y 6m" |
| **Net worth** | small, medium, large; lock screen rectangular and circular | the total at the latest check-in, "▲ +4.210 € since 31 Aug", and the year's month ends as a line in ink. The medium one adds this year's change and "Earliest retirement 54 · in 15 y 6 m"; the large one is everything at once, with "Can I retire yet?" and the readiness bar. On the lock screen, the changes in per cent |
| **Since last check-in** | medium | the change split into markets, new money and other, as bars from a shared zero, as on the Overview |
| **Can I retire yet?** | small; lock screen circular | the readiness as a ring: "58% of what retiring today would need" |
| **Check-in** | small; lock screen circular | the days to the next check-in, with how much of the month has gone; once it's due, the month and "Start check-in" |
| **Earliest retirement age** | small; lock screen circular | "54", April 2042, and how it moved |
| **Next milestone** | small; lock screen rectangular | the main plan's next milestone ([Milestones](#milestones)): "400.000 €", its bar, "78% there", "Typically by mid 2027". On the lock screen without its amount: "A round amount" |
| **What you could spend** | small | retiring at the plan's age: "38.400 € a year to spend", "3.200 € a month", in today's money |
| **Allocation** | medium | what you own by asset class: one bar in the asset classes' colours, and their shares |

- **Where the numbers come from:** the Overview's. Net worth at the latest check-in, and the main plan's latest results, or else the answer recorded at the last check-in (which has no spending, so *What you could spend* asks for the plan to be calculated). The widgets never open the library or run the plan: the app writes a small snapshot of what they show into an App Group whenever the library or the answer changes, and they draw it. The countdowns are worked out each day from its dates.
- **Locked:** amounts read `•••••` and changes show in per cent, as with the eye button; bars and lines keep their shape. Lock screen widgets never show amounts.
- **Empty states** say what's missing in a sentence: open the app, the first check-in, the plan's answer.
- **Tone:** as in the app. The answer always comes with "in 9 of 10 futures"; an earliest age that moved sooner is green, one that moved later is said plainly, in grey.
- The widget gallery shows made-up numbers, never yours.

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
- **Mac layouts.** A Mac window can't be smaller than the minimum size of its content, so every page's content scrolls, and what's pinned to a page scrolls when there's no room (`OverflowScrollView`). Tables on a scrolling page are as tall as their rows (`PageTable`, also on iPad for the plan debugger), so the page scrolls them; a `Table` is used only as a whole page (Instruments, the import's columns). [App/README.md](../App/README.md#design-system) has the details.
- **Folders.** `App/Sources/` holds `App`, `Stores`, `Navigation`, `DesignSystem` (colours, number formats, spacing, amount text, cards), `Components/Charts`, `Features/<Feature>` (Overview, Accounts, CheckIn, Plan, Import, Settings, Onboarding, Library) and `Preview`. [App/README.md](../App/README.md) describes them and the stores' APIs.
- **Chart components**, reused everywhere: `NetWorthChart`, `FanChart`, `SuccessCurveChart`, `IncomeStackChart`, `WaterfallChart` (now a headline and change bars), `BreakdownBars`, `Sparkline`. Their layout (ticks, marker labels, scales, the time span) is worked out without SwiftUI and tested on Linux.
- **Previews.** Every screen has SwiftUI previews built from a made-up library in code, with the same numbers as the example library in the tests.
