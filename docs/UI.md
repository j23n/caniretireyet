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
  | Import CSV | ⌘⇧I |
  | Save Baseline | ⌘⇧B |
  | Hide Amounts | ⌘⇧H |
  | Show Future | ⌘⇧F |
  | Duplicate Plan | ⌘D |
  | Compare Plans | ⌘⌥C |

- **Drag and drop:** dropping a CSV anywhere on the window starts an import.
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

- **Date.** Defaults to today. In the first days of a month it suggests the end of the previous month.
- **Prices.** Fetched as soon as the sheet opens, while you work. The status row opens the price list, where you can see the source and time of each price and type in any that failed.
- **Accounts, in groups.** Each row has one of three states:
  - **updated:** you entered a new value;
  - **unchanged:** you confirmed it's the same. This still writes a valuation, so the account isn't stale;
  - **not reviewed.**

  "Review" asks about any rows not reviewed: mark them unchanged, or skip them (then no record is written, and the account will show as stale).
- **Accounts with holdings.** Each position's quantity is pre-filled, and its value updates live with the fetched price. When a quantity goes up, an optional "paid" field appears. What you enter updates the position's purchase cost and the new money, which is how purchase costs are tracked without transactions.
- **New money (flow).** Shown under each account, filled in by the defaults in [PROGRESS.md](PROGRESS.md#data-this-needs-from-day-one), and editable. For pension funds the app asks for "contributions since …".
- **Keyboard.** A decimal keypad in your locale's format, with ▲ ▼ buttons above it to move between fields. Amounts accept `1.234,56` and `1234.56`.
- **Draft.** An unfinished check-in is saved as a draft on the device and never half-written to the library. Close the sheet, come back later, and continue.
- **Review screen.**
  - The new net worth and the waterfall (markets, new money, other).
  - Changed accounts, and anything unusual, e.g. a quantity that went down (did you sell?) or a value that changed more than 30%.
  - Then **Save**.
- **After saving.** The plan is re-run, and the confirmation ends with this month's answer:

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
  - Swipe actions: *Update value* (a one-account valuation) and *Close*.
  - Closed accounts sit in a collapsed "Closed (3)" section at the bottom.
- **Account detail.**
  - The value and its change.
  - A history chart. New-money events are small ticks on the time axis, so jumps you caused are distinguishable from market moves.
  - For accounts with holdings, the positions: quantity, price, value, purchase cost and unrealised gain.
  - The list of valuations, each editable: date, value, new money, note.
  - An info section: kind, institution, country, currency, tax wrapper, and whether it's included in net worth and plans.
- **Add account.** A sheet:
  1. Pick a kind from a grid of icons.
  2. Enter the name, institution, currency, country and opening date.
  3. Enter the positions (choose or create instruments) or the balance, which becomes the first valuation.
  4. The tax wrapper is pre-selected from the kind and your residence, e.g. a pension fund becomes `it.pensionFund`.
- **Close account.** A sheet asks for:
  - the closing date;
  - "Where did the money go?", which sets the successor account;
  - a short explanation: the account keeps its history, stays in every chart up to that date, and leaves check-ins.

  Reopening is one button. Deleting is for mistakes only, sits at the bottom in red, and asks for confirmation.
- **Instruments** (under Library on the Mac, and from an account's positions on iPhone): name, ISIN or ticker, currency, unit, asset mix, and price source. There's a *Test price fetch* button.

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

- **State.** `@Observable` stores, injected through the environment:

  | Store | Holds |
  | --- | --- |
  | `LibraryStore` | the in-memory library, edits, sync status |
  | `PlanStore` | runs, cached results, recompute scheduling |
  | `CheckInSession` | the draft |
  | `PriceService` | price fetching |
  | `ImportSession` | an import in progress |

- **Navigation.** One root view chooses between `TabView` (compact width) and `NavigationSplitView` (regular width and Mac). The screens themselves don't know which one they're in.
- **Folders.** `App/Sources/` holds `App`, `Stores`, `Overview`, `CheckIn`, `Accounts`, `Plan`, `Progress`, `Import`, `Settings`, `Components` (charts, amount text, cards) and `DesignSystem` (colours, number formats, spacing).
- **Chart components**, reused everywhere: `NetWorthChart`, `FanChart`, `SuccessCurveChart`, `IncomeStackChart`, `WaterfallChart`, `BreakdownBars`, `Sparkline`.
- **Previews.** Every screen has SwiftUI previews built from a made-up library in code, with the same numbers as the example library in the tests.
