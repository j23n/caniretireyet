# UI

What the app looks like and how it behaves, on iPhone and Mac. It's built with SwiftUI on iOS 26 and macOS 26, using the system's Liquid Glass look.

## Who uses it, and when

The app has one user, and three situations to design for:

| Situation | Where | How often | What matters |
| --- | --- | --- | --- |
| **Monthly check-in** | Mostly iPhone | Monthly, about 5 minutes | Speed. Import the month's files, look, save. It ends with this month's answer. |
| **Planning session** | Mostly Mac | A few times a year, 30–60 minutes | The plan as the chapters of a life, each with its money and its inputs in words, levers to try a change, comparing two plans. |
| **Looking after the data** | Mac | Occasionally | Adding and closing accounts, importing, fixing a value, looking at the files. |

Plus the glance: "how am I doing?" in a widget or on Today.

**Tone.** Money is emotional, so the app stays calm and matter-of-fact:

- no confetti, streaks or red alarm screens;
- uncertainty is shown honestly, e.g. "in 9 of 10 simulated futures", never as a single promised number;
- nothing ever scolds you;
- plain, complete sentences that say what a thing is or does. Headings and buttons name a thing or an action. No taglines or fragments ("Once a month, a short note."), no two phrases joined by a middle dot outside compact status lines, no setups with a twist ("X. Never Y."), no "the one thing", and no claims about being honest.

## Navigation

**iPhone:** a tab bar with three tabs. While a check-in is due or under way, it lives in the tab bar's accessory, so it's one tap from anywhere.

```
╭──────────────────────────────────────────╮
│ ◷ October check-in · due in 3 days    ▸  │  ← tab bar accessory (iOS 26)
╰──────────────────────────────────────────╯
   ◉ Today       ◷ So far       ↗ Ahead
```

- **Today:** your last Monday at work, where you stand, what changed and what needs attention.
- **So far:** how you've been doing, from your own records, against the main plan: the year, your savings rate, your money in and out, year by year, and your date at each check-in.
- **Ahead:** the plan, with its chart to the plan's end, What if, and your life ahead, chapter by chapter, for each plan.
- **Accounts** open from Today's *Net worth* row, on Today's stack: the list with net worth and the allocation, account details, adding and closing ([Accounts](#accounts)). The list's *More* menu has *Import Files…* and *Instruments*.
- **Settings** opens from a gear button in Today's toolbar. It's rarely needed, so it doesn't take a tab. *Sync & backups* is in it, under Library: the library's banners (a sync conflict, a file that couldn't be read) open it there with *Review* or *Show details*, also from the check-in, which closes first and stays open. In an import they open it over the import, which is as you left it when you go back.
- The accessory shows the check-in's state, "October check-in · due in 3 days", "Continue check-in · 31 Oct", and opens it. It shows only while a check-in is due (within a few days of the month's end, or past it) or one is open, so it doesn't sit over every screen the rest of the month; then *Check In* in Today's toolbar starts one early. (Before iOS 26.1, which can hide it, it always shows: "Last check-in 30 Sep · next 31 Oct".)

**Mac and iPad:** a sidebar with a content area.

```
Today
So far
Ahead                                ← the main plan
Check-in                       •     ← while due or under way; dot when due
Accounts                  97.330     ← the total of the open accounts
  All Accounts                 9     ← the list, with net worth and allocation
  ● Cash               ◷  12.990     ← a group: its color dot and subtotal;
  ● Investments           71.300        ◷ when one of its values is stale
  ● Crypto & gold         13.040
  ● Pension · Property · Debts
Plans
  Base case                   63     ← the age of its latest answer
  Part-time from 50           62
Library
  Import…
  Instruments
  Sync & backups
```

- **Ahead** opens the main plan, or "create your first plan" when there are none; the plan's own row under *Plans* is then selected. *Plans* lists every plan with the age of its latest answer, once there is one.
- **Check-in** is a row while a check-in is due or under way, with a dot, and while it's selected. *New Check-in* (⌘K) starts one at any time.
- **Accounts in the sidebar.** The sidebar shows the groups, not the accounts, so it stays short however many accounts there are.
  - The *Accounts* header shows the total of the open accounts on the right: the groups' subtotals added up.
  - *All Accounts* opens the accounts list ([Accounts](#accounts)), with net worth, its chart and the allocation at its top, and shows how many accounts are open.
  - Under it, a row per group that has open accounts (Cash, Investments, Crypto & gold, Pension, Property, Debts), with its color dot, a small clock when one of its accounts' values is stale, and its subtotal on the right, on one line; a long name wraps. On iPad these rows are a size smaller than the places above them, so names have room beside their amounts. Subtotals and staleness are the same as in the list. Amounts are placeholders while they're hidden.
  - Selecting a group shows the list of its accounts alone, open and closed, without the net worth card. Selecting an account in either list shows its detail over it. Opening an account from elsewhere in the app shows its detail over *All Accounts*.
  - The sidebar follows the library, also when it changes on the other device: a group appears once it has an open account, and a selected group left without open accounts gives way to *All Accounts*. An account's detail open over it stays, so closing a group's last account leaves its detail on screen, over *All Accounts*.
- **Settings** is the standard Settings window (⌘,).
- **Menu commands:**

  | Command | Shortcut |
  | --- | --- |
  | New Account | ⌘N |
  | New Check-in | ⌘K |
  | Import… | ⌘⇧I |
  | Recalculate | ⌘R |
  | Hide Amounts | ⌘⇧H |
  | Duplicate Plan | ⌘D |
  | Export Calculations… | — |

- **Drag and drop:** dropping a CSV anywhere on the window starts an import.
- **Window size (Mac):** the window opens at 1200 × 800 and can be made as small as 900 × 600. Every page scrolls, with what's pinned to it (the import's column settings) scrolling too when there's no room, so no page makes the window taller than the screen.

## Today

The home screen. It answers the app's question with a date, your last Monday at work, then says where you stand and what changed. It has one layout at every width, the answer and then tiles ([Tiles](#tiles)); on iPhone, top to bottom:

```
┌──────────────────────────────────────────┐
│ Today                    Check In  👁  ⚙︎ │
│ ╭──────────────────────────────────────╮ │
│ │ Your last Monday at work      (dusk) │ │
│ │ 27 March                             │ │
│ │ 2051                                 │ │
│ │ At 63 · in 9 of 10 futures           │ │
│ │ About 25 years from now.             │ │
│ │ (← A year sooner since September)    │ │
│ │ ~~~~~~~~~~~~~~~~~ ◓ ~~~~~~~~~~~~~~~~ │ │
│ ╰──────────────────────────────────────╯ │
│ ╭──────────────────────────────────────╮ │
│ │ 📊 Net worth                          │ │
│ │ 312.480 €                     ╱‾‾╲╱• │ │
│ │ ▲ +36.210 € in a year     ╱‾‾╲╱      │ │
│ │ +4.210 € in September  ‾‾╱           │ │
│ ╰──────────────────────────────────────╯ │
│ ╭─────────────────╮  ╭─────────────────╮ │
│ │ 🛋️ Next milestone│  │ 🐷 Savings rate  │ │
│ │ 10 years of     │  │ 31%             │ │
│ │ spending        │  │ of what came in,│ │
│ │ ▇▇▇▇▇▇▇▇▇▇▇░░░  │  │ (▲ from 27%)    │ │
│ │ 80% there  2027 │  │ last 12 months  │ │
│ ╰─────────────────╯  ╰─────────────────╯ │
│ ╭ 🌤️ What moved in September ───────────╮ │
│ │ +4.450 €                             │ │
│ │ in net worth                         │ │
│ │ 💰 You saved ▇▇▇▇▇▇▇▇         1.500 €│ │
│ │ 📈 Markets   ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇  2.950 €│ │
│ │ You saved about 2½ weeks of the life │ │
│ │ you plan.                            │ │
│ ╰──────────────────────────────────────╯ │
│ ╭──────────────────────────────────────╮ │
│ │ ◷ Fondo pensione            (Update) │ │
│ │   Last value in May                  │ │
│ ╰──────────────────────────────────────╯ │
└──────────────────────────────────────────┘
```

Then the offer of the yearly notes, once there's an answer, and *Import your first values* before the first check-in. The check-in itself is the tab bar's accessory while one is due ([Navigation](#navigation)).

Where a row of tiles has four slots or six (the larger iPhones in landscape, the iPad, the Mac), the answer takes two of them on the left, with net worth and what moved beside it as tall tiles that end with it: the line under net worth's figures fills its height, and what moved has each bar under its name. With two slots beside the answer they stand side by side, and with four each takes two. The smaller tiles follow under all three: the next milestone, the savings rate, this year so far, and the next check-in over saving nothing more. Then *Needs attention* and *Coming up*. On the Mac, *Check In* is in the toolbar.

```
╭ dusk ─────────────╮ ╭ 📊 Net ──╮ ╭ 🌤️ What ─╮
│ Your last Monday  │ │ worth    │ │ moved    │
│ 27 March 2051     │ │ 312.480 €│ │ +4.450 € │
│                   │ │    ╱‾‾╲╱•│ │ 💰 ▇▇▇▇  │
│ ~~~~~~ ◓ ~~~~~~   │ │ ╱‾‾╲╱    │ │ 📈 ▇▇▇▇▇▇│
╰───────────────────╯ ╰──────────╯ ╰──────────╯
╭ 🛋️ ─────╮ ╭ 🐷 ─────╮ ╭ 📅 ─────╮ ╭ 🗓️ ─────╮
│         │ │         │ │         │ ├ ⛵ ─────┤
╰─────────╯ ╰─────────╯ ╰─────────╯ ╰─────────╯
COMING UP
╭ 💰 ─────╮ ╭ 🛋️ ─────╮ ╭ 🧩 ─────╮ ╭ ⚖️ ─────╮
```

- **The answer.** The main plan's latest results, or else the answer recorded at the last check-in, in a card. A tap anywhere on it opens the plan. VoiceOver reads it as one, with "Opens the plan".
  - The card is the app icon's dusk (`DuskBackground`, shared with the widgets), its words in white over the horizon and the sun: "Your last Monday at work", then the date as the one big number, the day and month on one line ("27 March") and the year under it in the sun's light ("2051"), 64 pt heavy, growing with Dynamic Type and smaller only when it must: the Monday on or before the day the earliest age is reached, Glance's `LastMonday`. Under it how sure, "At 63 · in 9 of 10 futures" (`TodayText.ageAndFutures`), and how far away, "About 25 years from now." (`TodayText.away`, rounded to the nearest year from two years on, else in months; left out once it's passed). Beside tiles the card takes their height, and the horizon and the sun stay at its bottom, a band of the same height at any size, so larger type never runs into them. On a short screen (iPhone in landscape) the date is on one line, smaller, over a lower horizon. No ⓘ: the plan explains the answer, and carries the disclaimer.
  - Without a date (you could retire today, or no age works out) the card asks "Can I retire yet?" and answers "Yes", with "You could stop working today, in 9 of 10 futures.", or "Not yet", with "No age works out in 9 of 10 futures yet. The plan shows what would change that."
  - **How it moved:** a chip under it, white on the dusk, with how the earliest age moved since the check-in before the latest, against the age recorded there (Glance's `LastMondayMove`): "A year sooner since September" in blue, "2 years later since September 2025" in orange, "The same as in September" in grey. Not shown without an answer recorded at an earlier check-in.
  - **Status:** while the main plan calculates (a check-in's run, or Today's own), "Updating 34%" with a bar under the chip; when it can't run, "Can't be calculated: …". The date stays meanwhile.
  - **Before there's an answer** the card is titled "Your last Monday at work" and has one next step. Without a main plan: "Make a plan to see when you could retire." with *Create a plan*, which creates "Base case" from the latest check-in, makes it the main plan and opens it, as Ahead's *Create your first plan* does (when there are plans but none is the main one: "Choose a main plan to see when you could retire." with *Open Plan*, where *Set as Main Plan* chooses it; when the main plan's file couldn't be read: "Your main plan's file couldn't be read, so it has no answer." with *Show Details*, which opens Sync). Why *Create a plan* failed shows under it until the plans change. With a main plan not yet calculated: "Calculate Base case to see when you could retire. Each check-in then records its answer." with *Calculate*; while it runs, "Working out Base case… 34%"; a plan that can't run says why, with *Try Again* and *Open Plan*.
- **Calculating on its own.** Today calculates the main plan when it has no results, or when they no longer fit the plan or your data (after a check-in, an import or new prices), so the date shown is the latest ([Calculating](#calculating)). A plan that couldn't run isn't tried again here: it waits for *Try Again*.
- **Tiles.** Where you stand, as tiles ([Tiles](#tiles)): net worth (wide), then the next milestone and the savings rate (small each; when only one of those two has something to show, it's wide); then this year so far (small), the next check-in and saving nothing more (half tiles, stacked), and what moved (wide). Where a row has four slots or six, net worth and what moved are tall, beside the answer, and the others follow under them (above).
  - **📊 Net worth**: the total, how it changed over the last 12 months ("▲ +36.210 € in a year", "since March" for a shorter history) and at the last check-in ("+4.210 € in September"), and the last 12 month ends as a line. It opens the accounts. Net worth is today's, as the accounts list has it: each account's latest value, what it holds at the latest prices, so a value imported or a trade added since the last check-in, or prices fetched since, count. It animates when it changes (`.contentTransition(.numericText())`).
  - **Next milestone**: the main plan's next milestone ([Milestones](#milestones)), with how far there and when it typically comes, or the ones passed at the latest check-in. It opens So far.
  - **🐷 Savings rate**: the rate over the last 12 months, as the savings rate counts it ([PROGRESS.md](PROGRESS.md#money-in-and-out); "31%", "of what came in"), with its change against the 12 months before ("▲ from 27%"); its line says "of what came in, last 12 months". Left out while looking back is off ([So far](#money-in-and-out-year-by-year)) or until something has come in. It opens So far.
- **What moved it.** A wide tile, "🌤️ What moved in September" (or "… since 15 Aug" when the check-in before wasn't the end of the month before): how net worth changed ("+4.450 €", "in net worth"; in per cent while amounts are hidden), a bar each for *💰 You saved* and *📈 Markets*, to the larger of the two, with its amount, then one sentence with what was saved as time (*Saving as time*, below). Tall beside the answer, each bar goes under its name and amount. Saved is as the savings rate counts it (`Valuator.savedSplit(of:)`): money moved between your accounts cancels out, and what a new account already held when its records start, and a one-off, don't count. While amounts are hidden, the bars keep their proportions. It opens the accounts.
  - **📅 Net worth change in 2026**: how net worth changed since 31 December of last year (in per cent while amounts are hidden), then what you saved (as the savings rate counts it) and what markets did. From `Valuator.changeThisYear(asOf:)`, in Tracker. Not shown when net worth has no value by 31 December (a library started this year). It opens So far, on this year.
  - **🗓️ Next check-in**: a half tile with its date and how soon ("in 6 days", "tomorrow", "today", "ready to start"), or "Under way" with *Continue* while one is. It starts the check-in. Not shown before the first.
  - **⛵ If you stopped saving now**: a half tile with the coast age, "earliest age to stop", as Ahead has it ([Milestones](#milestones)). It opens So far.
- **Coming up.** Under the tiles, the main plan's milestones its median future reaches after the next one, a small tile each: what kind of milestone it is as its heading ("Your plan passes", "Saved", "You'll have", "Growth matches saving", "You could stop saving"), the milestone's name ("500.000 €", "10 years of spending") and when it typically comes ("typically late 2028"). As many as a row holds, and at least two. Each opens So far, where *All Milestones* is.
- **Saving as time.** What was saved, said as time of the main plan's retirement spending a year (`SavingAsTime`, in Glance). *What moved* ends with it, short: "You saved about 2½ weeks of the life you plan." The check-in's ending says it with the amount and what markets did: "You saved 1.500 €, about 2½ weeks of expenses. Markets added about 7 more." (or "Markets took about a week."). Days below a week, then weeks, months and years, in halves below 3¾ and whole above, all "about". What markets added is counted in the saving's unit and said only when it rounds to at least a half of it; what they took is said in its own unit, from a day. Nothing without a main plan with spending, or when nothing was saved. An amount hides with the eye and the time stays, which doesn't give it away on its own; in a feedback screenshot the sentence hides as a whole.
- **Keep your goal in view.** Once there's an answer, once, while any of the yearly notes is off: "Retiring is years away. A few times a year, a short note can show how far you've come. Never amounts, never about markets." with the yearly notes that are off ticked (of *Your year*, *Birthday*, *Records anniversary* and *Plan check-up*; after onboarding, *Your year* is already on), *Turn On* and *Not Now*, and "Shown once. Settings › Notifications changes them later." *Turn On* asks for permission and turns on the ones ticked, leaving the others as they are. Either button puts the card away for good. See [Notifications](#notifications).
- **Import your first values.** Before the first check-in: "Your accounts get their values from the files you import: bank statements, broker exports or a spreadsheet. Your history starts with them." with *Import Files…*. A library without accounts shows "No accounts yet" in place of the page, with *Import Files…* and *Add an Account*.
- **Needs attention.** Only shown when something needs you: stale accounts (not one that holds nothing: see [Accounts](#accounts)), accounts with problems in their trades, prices and exchange rates that are missing, old or couldn't be fetched (each opens Instruments, or the instrument, where they're fetched or typed in), sync conflicts that were merged, and plan warnings. Each is a compact row: what ("Fondo pensione"), why in a short line ("Last value in May"), and its action ("Update", "Fix", "Add Price", "Fill In"); the whole row opens it. On iPhone a warning icon leads and the action is at the trailing edge, in a card without a title; on the Mac and iPad the card is titled "Needs attention" with an orange edge, and the action is under each. The first three show, then *2 More*. An account whose trades have problems (more sold than held, an opening without a cost, a statement that differs from the trades: the notes its page shows) gets one item that opens it: "Directa · 2 problems with trades: More sold than held · VWCE differs from the statement". Prices and exchange rates missing on past month ends get an item each, which opens *Fill In Past Prices*: "Past exchange rates for US$ are missing · US brokerage isn't fully counted in your net worth for Jun 2018 – Dec 2021".
- **Hidden amounts:** amounts hide as they do everywhere else (`AmountText`, `DeltaText`): the *Net worth* tile's amount is a placeholder, its changes show in per cent and its line keeps its shape, and the bars of *What moved it* and the milestone's bar keep their proportions, and the savings rate stays. The date, the ages and the futures have no amounts; in a feedback screenshot they hide.

## So far

How you've been doing, from your own records, always against the main plan (or the first plan, when none is the main one), one year at a time, on one page: the chosen year against what you planned in January, its tiles, the year month by month on a line, its savings rate and money in and out by month, then year by year. Everything but *Year by year* is the chosen year's: no figure mixes it with the last 12 months or with the whole history. See [PROGRESS.md](PROGRESS.md). The plan appears only as what you're measured against and as dashed reference lines ("your plan's 28%"), never as what's measured, so editing the plan doesn't change the past, only the lines it's set against. Money in and out is the library's, the same under every plan.

- **Where it opens.** At the top, on this year. Today's tiles open it there, the import's *Open So Far* opens it too, the *Your year* note opens it on last year, and Ahead's "21.572 € ahead ›" opens it. A year in *Year by year* opens that year at the top.
- **Nothing to show yet:** without a check-in, "So far starts with your first values. Import a file to add them."; without a plan, "So far follows your main plan. Create one on Ahead."

```
┌──────────────────────────────────────────┐
│ So far                                   │
│ ╭──────────────────────────────────────╮ │
│ │ (‹)        2026 so far           (›) │ │
│ │  Ahead of what you planned in January│ │
│ │                ⚑     ▅▆▇●           │ │
│ │ ▁▂▃▄▅▆▇▇┅┅┅┅┅┅┅┅┅┅┅┅┅┅┅┅┅┅┅┅┅┅┅┅┅ │ │
│ │ J F M A M J J A S O N D              │ │
│ ╰──────────────────────────────────────╯ │
│ ╭ 💰 You saved ───╮╭ 📊 Your money now ╮ │
│ │ 20.486 €        ││                   │ │
│ ╰─────────────────╯│ 338.600 €         │ │
│ ╭ 📈 Markets added╮│ started the year  │ │
│ │ 6.628 €         ││ at 311.486 €      │ │
│ ╰─────────────────╯╰───────────────────╯ │
│ ╭ 🐷 Savings rate ╮╭ 🧭 Earliest age ──╮ │
│ │ 31%             ││ 63                │ │
│ ╰─────────────────╯╰───────────────────╯ │
│ ╭ 🛒 Spent ───────╮╭ ✅ Check-ins ─────╮ │
│ │ 2.633 €         ││ 9                 │ │
│ ╰─────────────────╯╰───────────────────╯ │
│ Month by month           All Milestones │
│ ○ JAN Started the year       311.486 € │
│ ○ MAR 💪 Saved more than usual (9.121 €)│
│ ● APR 🏁 10 years of spending   reached │
│ ○ MAY ✏️ Plan changed          (64 → 63)│
│ ○ JUN 📉 Markets fell 4%      (−3.100 €)│
│ ● OCT Now                     338.600 € │
│ Savings rate by month               2026 │
│ ╭──────────────────────────────────────╮ │
│ │ 30% ┤ █  ▃  █  █  █  ▄  █  ▅  ▆ ━━━━ │ │
│ ╰──────────────────────────────────────╯ │
│ Money in and out                    2026 │
│ ╭──────────────────────────────────────╮ │
│ │ ▇▆ ▇▅ ▇▆ ▇▇ ▇▅ …                     │ │
│ ╰──────────────────────────────────────╯ │
│ Year by year              saved and spent│
│ ╭──────────────────────────────────────╮ │
│ │ 2026 so far ▇▇▇▇▇░░░░░░░░    31%   › │ │
│ │ 2025        ▇▇▇▇░░░░░░░░░░   27%   › │ │
│ │ 2024        ▇▇▇░░░░░░░░░     22%     │ │
│ ╰──────────────────────────────────────╯ │
└──────────────────────────────────────────┘
```

### The year

Each year is measured against **your January plan**: the plan as it was at the year's first check-in, which the check-in keeps as the year's automatic baseline ([PROGRESS.md](PROGRESS.md#actual-vs-a-baseline)). It's named for the month it was kept in: "your October plan" when the year's first check-in came in October. A year without one is measured against a past baseline the library holds that starts before the year ends: "your 2021 plan".

The years run from your first record of an account the plan counts (a value, or a trade) through the latest check-in. The page opens at this one.
- **The year's card.** Its title ("2026 so far", "2025") and its verdict, each on one line: "Ahead of what you planned in January", "On track with …" or "Behind …", in orange when behind ("Ended ahead of what you planned in January" for a past year; a long verdict shrinks to fit, and keeps the line's height, so the card is as tall for every year), as [PROGRESS.md](PROGRESS.md#actual-vs-a-baseline) ("On track") puts it; left out while the year has no plan kept. ‹ › step through the years (⌘[ and ⌘] with a keyboard): on iPhone round buttons either side of the title, on the Mac and iPad at the card's right with *Today*, which goes back to this year. Then the year's chart across the card:
  - your money through it, an ink line from January: solid into each check-in, with a small dot there, lighter where it's valued from what you held and its prices, dotted where a price or a rate is missing (those holdings count as zero), with a larger blue dot at the last. A year without a check-in is valued from what you held and its prices, and the line runs through each check-in and the end of every month without one, so what only a check-in can tell, like a bank balance, shows as a step at the next one. The line is the money in the plan as it was, in the base currency, as the milestones flagged on it and the year's change count it;
  - what you planned in January: its median, dashed in blue, from its start to the year's end, labelled "planned in January" on the side away from your line. It's in the same money: its median in the base currency on each day (from money of its start where an inflation index allows), with the accounts it doesn't compare (an account added since with an older history, one its plan leaves out) at their value. Between the two, a blue wash where you're ahead and orange where behind. Before a plan kept later in the year nothing is washed. This year's line ends at the latest check-in, and what was planned runs on to December;
  - a flag on the line where a milestone was reached;
  - the gridlines' amounts at the card's edge where nothing is drawn, with the decimals they need to read apart ("1,1M €", "1,15M €"; placeholders while amounts are hidden), on a scale fitted to the year's money and what was planned, not from zero;
  - the months' initials along its bottom.
  - **Reading the line.** The pointer over the chart (the Mac, an iPad with a pointer), or a finger touched and held on it (a light tap of haptics), then dragged, reads the line at the nearest check-in or month end: a rule, a dot and a callout that reads as the History chart's does over its history: the date and where the value comes from ("31 Mar 2026 · check-in", "30 Apr 2026 · from prices"), the money as the headline ("312.480 €"), "Not every price is known" when a price or a rate was missing, what was planned and the gap as rows, all in short amounts, then a milestone reached there, with its flag ("Passed 300.000 €."), and what changed that day ("55, a year sooner."). It stays inside the card. Amounts hide with the eye.
  - **VoiceOver** reads the card as its year and verdict, and the chart as a chart: its audio graph and chart details give your money at each point and what was planned.
- **Tiles** under the card ([Tiles](#tiles)), the year's alone: **💰 You saved** (mint: "20.486 €", "planned 13.463 € by now" this year, "planned 13.463 €" for a past one) over **📈 Markets added** (sky: "6.628 €", "expected 1.982 €"), half tiles, "You took out" and "📉 Markets took" (peach) when they're below zero; beside them **📊 Your money now** (or *Your money at the year's end* for a past year), small, your money in the plan with "started the year at 311.486 €" under it. Then, when money in and out was recorded in the year, **🐷 Savings rate** (lilac: the year's rate, "31%", with "your plan's 28%", the plan as it is now, for every year, as the charts' dashed lines; or "of what came in" without the plan's own rate) over **🛒 Spent** (peach: what the year spent a month, scaled from what its values cover as `retire spending` scales it, "2.633 €", with "a month, plan 2.700 €", the plan's spending while working, or "a month" when the plan is past working), half tiles; and **🧭 Earliest age to stop** ("63", "was 64 at the year's start" or "same as at the year's start") over **✅ Check-ins this year** (or *that year*: how many the year had, "each one's figures ›"), half tiles. *Check-ins* opens the year's check-ins as a table in a sheet, newest first (*Month*, *Money*, *You saved*, *Markets*, *Age*, *Moved*). Typed savings or investment accounts leave out the savings rate and spending ([Money in and out, year by year](#money-in-and-out-year-by-year)).
- **Month by month**, after the tiles: the year on a line down the left, like *Your life ahead*, a row each on a card: the month in capitals, what it was, and its figure. First where the year started ("Started the year", or "First values" in the year of the first record, with the money then); then, in the order they came, the milestones it reached (on butter, a filled dot: "🏁 10 years of spending", "reached"; [Milestones](#milestones)) and what happened at its check-ins, each with a dot and a capsule green when it's good news, orange when not, grey otherwise: an earliest age that moved ("⏪ Earliest age moved" or "⏩", "✏️ Plan changed" when you changed the plan, "64 → 63" or "55 again"), a change of the plan or of the app's calculations that didn't move it ("✏️" or "⚙️"), a check-in where no age worked out ("⚠️"), a month you saved more than usual ("💪 Saved more than usual", "9.121 €") and a month markets moved a lot ("📈 Markets rose 3%" or "📉 Markets fell 4%", "−3.100 €"). Last, in ink, "Now" with your money, or "The year's end" for a past year. Keeping the year's plan isn't a row. *All Milestones* beside the title opens every milestone, reached and ahead ([Milestones](#milestones)). Under the line, a year whose check-ins stop early says so ("No check-ins after June: what you held is valued at its prices."), and one with missing prices or rates that those holdings count as zero and the line is dotted there, with *Fill In Past Prices…*. The months, the shares and the ages are hidden in feedback screenshots; amounts hide with the eye.
- **Mac and iPad.** The same page at every width; the tiles fill the grid's slots, four or six to a row.
- Without a check-in, "Your year shows here from your first check-in."

### Money in and out, year by year

**Off while savings or investments are typed.** While an open savings or investment account in net worth has its values typed ([ACCOUNTS.md](ACCOUNTS.md#typed-values)), So far shows one card, **Money in and out is off**, in place of the charts by month and *Year by year*, and the year's tiles leave out the savings rate and spending: "Your savings rate and your money in and out are built on the money in and out and the money invested that statements record. A typed value is a balance only, so they're off while a savings or investment account's values are typed.", those accounts by name, each opening its page, and "To turn it on, set their Values to From imported files in Edit Account and import their statements." Today's *Saved this year* leaves out its savings rate then, and the plan form leaves out "You spent … a month", which stand on the same records.

- **The chosen year's months.** *Savings rate by month* and *Money in and out* go month by month over the year chosen at the top, its year beside their titles ("2026"); this year's run to the latest check-in, and the current month is drawn lighter and called "so far". *Year by year* has every year recorded. A year without money in and out says "No money in and out was recorded in 2024." on both cards.
- **Savings rate** (titled *Savings rate by month*). A bar per month: the savings rate over the values of that period, a bar below the zero line when more was spent than came in. No line over 12 months: they'd reach outside the year. A rate needs something to have come in after tax, so a month has none when nothing came in, less than nothing came in (money in and pension contributions add up to less than zero), or more tax than came in. A month with money in and out but no rate has no bar: a dot in spent's colour at the value axis's bottom edge marks it, the legend adds *No rate*, and its callout says why. A dashed rule at the plan's own savings rate while working: a year's saving as the crossover counts it (the take-home pay of the work phase in force less spending while working), over that pay ("your plan's 28%"), left out without a work phase in force. The value axis fits the rule and the bars, each bar's rate kept within a band around the typical rate of its 12 periods with a rate (those that end at it, or the first 12 while fewer come before it): their median, give or take three times how far their rates typically stray from it (their median distance from it), and at least 50 points either side of it and of zero. A month without a rate takes the band of the last one with a rate before it, or of the first. So a month with almost nothing in, whose rate can be −40.000%, doesn't flatten the others, and a rate that swings from month to month isn't cut. A bar beyond the axis is drawn to its edge with a gap across it, the legend says "Cut at the edge", and the callout and VoiceOver read the real rates.
- **Money in and out**, a card after *Savings rate*. Per month, *came in* and *spent* as a pair of bars from zero, and *saved* as a dot between them, counted as the tiles and the savings rate count them (came in and saved include pension contributions), in the base currency at each value's date. A dashed rule at the plan's spending while working, for a month, left out when the plan is past working. A value is counted in the period of its date, so after a skipped check-in its month holds two months' money: when the values of the account the most came into cover more than one and a half months, the period's bars are hatched, the legend says so, and the callout says what they cover ("31 Oct · covers Sep – Oct"). The value axis fits what's typical, not the extremes, so a month with an inheritance or a car doesn't flatten the others: each period's came in, spent and saved are kept within 2.5 times its typical amount either side of zero, the larger of the medians of came in and of spent over its 12 periods (as on *Savings rate*), so a rising income moves the limit along. Those medians are of what came in and was spent a month of what each period holds, and a period that holds more after a skipped check-in has its typical amount times the months it holds: a quarter's money after quarterly check-ins isn't cut. The plan's rule is always in view. A bar beyond the axis is drawn to its edge with a gap across it, a dot as a triangle at the edge pointing past it, the legend says "Cut at the edge", and the callout and VoiceOver read the real amounts.
- **Year by year**, after *Money in and out*, titled with "saved and spent": a row for each calendar year with money in and out recorded, newest first. Each has the year ("2026 so far" for this one), a bar of what was saved, in the accent, then what was spent, in grey, to the scale of the year that took in the most, and the year's savings rate ("31%", "—" without one). A year with a check-in has a chevron and opens at the top of the page, which scrolls up to it. Under the rows: "The percentage is that year's savings rate. Tap a year to see it at the top." VoiceOver reads a row as "2025: saved 31% of what came in". The bars and the years are hidden in feedback screenshots.
- **Reading the charts.** The pointer, or a finger touched and held then dragged, reads a period as the History chart's callout does: the month, then its rows. On *Money in and out*: "Savings rate 34%", "Came in 4.100 €", "Spent 2.600 €", "Saved 1.500 €". On *Savings rate*, the rate with what it's worked out from: "Savings rate 34%" with its "Came in 4.100 €" and "Saved 1.500 €". A rate reads "–" when there's none, with why under it: "Nothing came in", "Less than nothing came in" or "More tax than came in". Rates stay with the eye; amounts hide.
- **Accessibility.** *Savings rate*'s summary says what the bars are, and names the months without a bar, each with why: "No rate in Aug 2026 (nothing came in) and Oct 2026 (more tax than came in), so they have no bar."
- **Not enough data.** Money in and out start at the first check-in that records them, so *Savings rate* and *Money in and out* say where their data starts when the year reaches back before it: "Money in and out is recorded since 30 Jun 2026: 3 months so far." (the date the first counted value is measured from, and the year's months recorded; "6 months recorded." for a year that has ended). A year that ends before it says only that none was recorded. Without any recorded, *Savings rate*, *Money in and out* and *Year by year* fold into one card that says what records them, with *Open Accounts*, and the tiles leave out the savings rate and spending.
- **Mac and iPad.** The same page, wider: the tiles on the grid of slots, and each chart across the page.
- **Hidden amounts.** Rates, words, ages and the charts' shapes stay. Amounts are placeholders, and the value axis of *Money in and out* switches to relative labels (*Privacy* under [Design system](#design-system)): multiples of what typically came in in a period (the median, so one month with an inheritance doesn't move it).
- **VoiceOver** reads each figure and tile as its title, figure and change, and each chart as a chart with its audio graph and chart details.

### Milestones

The points you pass on the way ([PROGRESS.md](PROGRESS.md#milestones)): round amounts of the money in your plan from 10.000 €, years of the spending you plan for retirement, shares of what retiring today needs, and the crossover, where a typical year's growth adds as much as you save. They're there to notice progress between the rare moves of the answer: a flag, a sentence, a row in a list, and on Today a tile with a little color, an emoji for each kind, and pink with 🎉 when one is passed. No badges or streaks, and nothing is taken away when markets fall back.

```
┌──────────────────────────────────────────┐
│ Milestones                          Done │
│ ╭ 🛋️ Almost there    typically early… ─╮ │
│ │ 10 years of spending             98% │ │
│ │ ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇░  │ │
│ │ Last: 💰 300.000 €, Jun…  Then: ⚖️ … │ │
│ ╰──────────────────────────────────────╯ │
│ ╭ ⛵ Saving nothing more ──────────────╮ │
│ │ 71                                   │ │
│ │ If you stopped saving today, you     │ │
│ │ could still retire at 71; the coast  │ │
│ │ point is 67, when your first pension │ │
│ │ starts.                              │ │
│ ╰──────────────────────────────────────╯ │
│ What they mean                           │
│ ╭ 💰 Round amounts ────────────────────╮ │
│ │ The money in your plan passing       │ │
│ │ 10.000 €, 15.000 €, 20.000 €,        │ │
│ │ 25.000 € and on, each about a        │ │
│ │ quarter above the last: simple marks │ │
│ │ of the money growing.                │ │
│ │ ⚑ 300.000 €                Jun 2026 │ │
│ │ ⚐ 400.000 €       typically early 2… │ │
│ ╰──────────────────────────────────────╯ │
│ ╭ 🛋️ Years of spending ───────────────╮ │
│ │ …                                    │ │
│ ╰──────────────────────────────────────╯ │
│   (🧩 What retiring today needs,         │
│    ⚖️ The crossover, ⛵ The coast point)  │
│ ╭ Reached ─────────────────────────────╮ │
│ │ 💰 300.000 €               Jun 2026 │ │
│ │ 🧩 A third of what retir…  Jun 2026 │ │
│ │ 💰 250.000 €               Aug 2025 │ │
│ ╰──────────────────────────────────────╯ │
│ ╭ Ahead, typically ────────────────────╮ │
│ │ 🛋️ 10 years of spending  early 2027 │ │
│ │ ⚖️ The crossover            mid 2027 │ │
│ │ 💰 400.000 €              early 2028 │ │
│ ╰──────────────────────────────────────╯ │
└──────────────────────────────────────────┘
```

- **So far.** The milestones a year reached are on its line, *Month by month* ([The year](#the-year)), with *All Milestones* beside its title, a sheet of wide tiles: the next milestone and saving nothing more; *What they mean*, a tile for each kind of milestone the plan has, explained, with the latest of it reached and the next ahead (below); then cards of what's been reached, newest first, and what's ahead, soonest first, each row with its kind's emoji (five of each, *Show All* for the rest). On a year's chart, a filled flag on the line at the check-in or the month end that reached one (in the years before your first check-in too).
- **Today.** The *Next milestone* tile ([Tiles](#tiles)), which opens So far; *All Milestones* shows the same tile, wide. Tinted by the milestone's kind, with its emoji: round amounts butter 💰, years of spending mint 🛋️, shares of what retiring today needs lilac 🧩 (🏖️ for all of it), the crossover peach ⚖️, the coast point sky ⛵. It shows the next milestone's name, its bar and how far there ("80% there"), and when the median future typically reaches it ("mid 2027"); "Almost there" from 95%. The wide tile adds the last one passed and the one after ("Last: 💰 300.000 €, Sep 2026", "Then: 💰 500.000 €"), and when markets took it back since the check-in before, a fainter bar where it was and "81% in August" in place of the last one. Milestones passed at the latest check-in (or at a month end since the check-in before) turn it pink until the next check-in: "🎉 Passed in September" and the name ("2 passed in September" and both), the coast point as its age, then "Next: 💰 400.000 €". Without a next one: "No more before the plan's end."; before the plan has results, it says the milestones show once it's calculated.
- **Plan.** In the chosen chapter, *Along the way, typically*: the milestones the median future reaches in it, each with its flag and when ("400.000 €", "mid 2027").
- **Check-in.** After saving, the milestones passed since the check-in before, at this one or at a month end between them, each a line with a flag ("Passed 300.000 €."), and the next with how far there ("Next: 5 years of spending, 80% there."). The shares of what retiring today needs and the coast point come with the month's answer, and show on So far.
- **The coast age.** On Today, once a calculation or a check-in has worked it out ([PLANNER.md](PLANNER.md#ages-without)): a small tile, ⛵ *Saving nothing more*, the age large and the coast point under it ("The coast point is 67."), sky, and mint once it's at or under the coast point ("Past the coast point, 67."). The *All Milestones* sheet's wide tile says it in full ("If you stopped saving today, you could still retire at 63; the coast point is 67, when your first pension starts."), and so do the plan's key numbers. The coast point is a milestone: the first check-in whose recorded coast age is at or under the age the first pension starts, the first check-in that recorded one included ("Passed the coast point: saving nothing more, you could still retire at 67."). It stays under *Reached* when the age rises again.
- **The widget.** *Next milestone* shows the next one, its bar and when it typically comes ([Widgets](#widgets)).
- **What they mean.** In the *All Milestones* sheet, between saving nothing more and the lists, a wide tile for each kind the plan has, in this order, in the kind's tint with its emoji: its name, what it means and why it matters, then the latest of it reached (a filled flag, "None yet." without one) and the next of it ahead (an outlined flag; "No more before the plan's end." without one, nothing without results). Round amounts are always there: "The money in your plan passing 10.000 €, 15.000 €, 20.000 €, 25.000 € and on, each about a quarter above the last: simple marks of the money growing." (its amounts placeholders while amounts are hidden). Years of spending need the plan's retirement spending: "What you have, counted in years of the 36.000 € a year you plan to spend in retirement." What retiring today needs: "The money in your plan against what retiring today would need. All of it means you could stop now." The crossover needs saving and growth: "From about 380.000 €, a typical year's growth adds as much as you save: from there, markets do more than your saving." The coast point needs a pension, and has nothing ahead: "When you could stop saving and still retire when your first pension starts, at 67." A kind with none on the ladder and none reached is left out.
- **Words.** A round amount is its amount (a placeholder while amounts are hidden; "A round amount" on the lock screen); "10 years of spending" ("Enough for 10 years of the spending you plan for retirement."); "Half of what retiring today needs" ("Halfway to what retiring today needs."), and all of it "All that retiring today needs: you could stop."; "The crossover" ("A typical year now adds more than you save."). Dates ahead are a part of a year, "early", "mid" or "late 2028", since they're the median of many futures.

## Check-in

Once a month: import the month's files, update the values you type, look at what they did, save. It opens as a full-screen sheet on iPhone and as the Check-in page on the Mac and iPad, one scrolling page.

```
┌──────────────────────────────────────────┐
│ Cancel    October check-in          Save │
│           31 Oct 2026 ▾                  │
│ ╭ ⤓ Import Files ───╮╭ ✓ Prices updated ╮ │
│ TO CONFIRM · 2                           │
│ ╭──────────────────────────────────────╮ │
│ │ Home                  € [ 312.000 ]  │ │  ← typed: a field
│ │ Last value 30 Jun                    │ │
│ │ Fondo pensione             24.300    │ │  ← no file this month
│ │ Last value 31 May                    │ │
│ ╰──────────────────────────────────────╯ │
│ UPDATED · 5                              │
│ ╭──────────────────────────────────────╮ │
│ │ Conto Fineco                6.012    │ │
│ │ Conto deposito             17.901    │ │
│ │ Directa                    59.448    │ │
│ │ 2 more                           ›   │ │
│ ╰──────────────────────────────────────╯ │
│ Net worth so far     312.480 € ▲ +4.210  │  ← pinned to the bottom
└──────────────────────────────────────────┘
```

- **Date.** Defaults to today. In the first days of a month it suggests the end of the previous month (`CheckInDates.suggested(today:lastCheckIn:)`). The title says the month, with the date under it ("October check-in", "31 Oct 2026"); tapping the date picks another; an earlier date fills in history: see [Adding history](#adding-history).
- ***Import Files*** opens the import ([Import](#import-mac-first)) in a sheet for the check-in's date: bank statements are read through that date ([IMPORT.md](IMPORT.md#bank-statements)), and broker exports, pension spreadsheets and any other file import as they do anywhere. Each import is written when you tap *Import*, with its own backup, and undone from its Done step or with `retire import --undo`. Import as many files as the month has; the page follows each one.
- **Prices.** Fetched for the date as soon as the check-in opens, and again after each import, for what the accounts hold then (Settings can turn this off). The button beside *Import Files* says their status in a few words ("Prices updated", "Check prices") and opens the price list, read-only: each price, rate and inflation value with its source and time, or why it couldn't be fetched. A price that couldn't be fetched uses the latest one known. An instrument without a price source gets its price on the Instruments screen.
- **Net worth so far**, on the date with the fetched prices, and its change since the previous check-in, in a bar pinned to the bottom.
- **To confirm:** first the open accounts whose values you type (`Account.acceptsTypedValues`: those set to *Typed by you*, and starting estimates), each with the date of its latest value and its balance on the check-in's date in a field, prefilled from that value. Changing it and pressing Return, or leaving the field, saves it as a typed value on the check-in's date with its own backup, as *Update Value* does ([Accounts](#accounts)), which the row's context menu also opens; a balance that can't be read says so under the name. Then the accounts no file this month covered, which keep their last values (an account that holds nothing isn't listed), in gray, the date of the last value in the warning color when it's stale.
- **Updated:** the other open accounts with a value, or for a trades account a trade, in the date's month on or before the date, with their value; past three, the rest behind "2 more". Imported values aren't edited here: a wrong one comes from a file, so fix the file and import it again, or delete the value on the account's page.
- **Save** writes the fetched prices, FX rates and inflation values (a price you set by hand for the date stays) and records this month's answer. *Cancel* drops the fetched prices; what the imports wrote stays. Nothing is kept on the device: an open check-in is its date and its prices.
- **After saving.** The confirmation shows as soon as the prices are written, titled "October saved": a card with your date, then the milestones passed since the check-in before ([Milestones](#milestones)), then *What moved it* with net worth and its change, and *Done* pinned to the bottom. The main plan then runs to record this month's answer (only for the latest check-in: see [Adding history](#adding-history)), and the card *Your last Monday at work* shows its progress ([Calculating](#calculating)) in the meantime, the same as on Ahead, without a Cancel button, and "You can close this now: the answer is recorded when it's ready." Then it ends with your date, moved:

  > October saved · Net worth 312.480 € (▲ 4.210)
  > Your last Monday at work: ~~3 April 2051~~ **27 March 2051** · A year sooner
  > At 62, in 9 of 10 futures.

  The date is the screen's hero, centered on its card under "Your last Monday at work"; the date before is struck through above it, with an arrow down, when it differs. The chip says how the earliest age moved since the check-in before: "A year sooner", "2 years later", "The same date". The line under it says the age and how sure: "Still at 63, in 9 of 10 futures." when it didn't move, "At 62, in 9 of 10 futures." when it moved or there's no answer before, "You could stop today, in 9 of 10 futures.", or "No age works out in 9 of 10 futures yet." *Open the plan* follows. Without a main plan: "Create a plan to see your last Monday at work. Every check-in will then end with it, moved." with *Create a plan*. When there's no answer for the month, the last one ("Last time (31 Aug): 27 March 2051.") and why: "The plan couldn't run this time: …", or "This month's date isn't ready yet. The plan works it out when you open it."

  This is the monthly moment the app is built around: recording the month's answer is what the check-in is for. *Done* can close the confirmation while it runs; the answer is still recorded.
- **The ending.** Under the date, *What moved it*: net worth and its change ("312.480 € ▲ +4.210 €"), a bar each for what you saved and what markets did, what was saved as time ("You saved 1.500 €, about 2½ weeks of expenses. Markets added about 7 more.", see [Today](#today), *Saving as time*), and when markets took 5% or more of net worth, a word of perspective, "Markets took 8%. Months like this are part of the 9 in 10 futures your plan already counts." (`MarketPerspective`). Then the next milestone, on a card of its own: "⚑ Next: 5 years of spending, 80% there."
- **Notes.** Saving schedules the notes again ([Notifications](#notifications)): the month's note is answered, and the next one counts from this check-in.
- ⌘S saves on the Mac and iPad.

## Accounts

- **List.** Grouped: Cash, Investments, Crypto & gold, Pension, Property, Debts. On iPhone (and the iPad in compact width) it opens from Today's *Net worth* row; on the Mac and iPad it's *All Accounts* in the sidebar, and each group's row there is the list of that group alone ([Navigation](#navigation)).

  ```
  Accounts                              ⋯   +
  ╭──────────────────────────────────────╮
  │ Net worth               Last 3 years ▾│
  │ 312.480 €                             │
  │ ▲ +4.210 € in September  ▲ 14% this year
  │ ╱‾‾‾‾‾‾‾‾‾‾‾‾‾‾  net worth            │
  │ ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇   │
  │ ● Real estate 66%  ● Equity 14%  …    │
  │ Allocation                         ›  │
  ╰──────────────────────────────────────╯
  ╭──────────────────────────────────────╮
  │ CASH                         12.990   │  ← a group: its name and subtotal
  │ Conto deposito  Fineco        8.200 › │
  │ Conto Fineco ◷  Fineco        4.790 › │  ← ◷ stale
  ╰──────────────────────────────────────╯
  ╭──────────────────────────────────────╮
  │ INVESTMENTS                  71.300   │
  │ …                                     │
  ╰──────────────────────────────────────╯
  ╭──────────────────────────────────────╮
  │ CLOSED                            1   │
  │ Old savings  Closed 31 Mar 2025   0 › │
  ╰──────────────────────────────────────╯
  ```

  - **Net worth** heads the list, on one card: net worth today, as Today's *Net worth* row has it, animating when it changes; under it the change at the last check-in ("▲ +4.210 € in September") and this year's ("▲ 14% this year"); a menu of the chart's span (the *History* half of the decades chart's, sharing its choice); the chart of net worth over that span, a single line, read by dragging across it; and a strip of what you own by asset class, with its shares as a legend ("Equity 14%"). Not shown while searching.
  - **Allocation.** Under the strip, collapsed at first: horizontal bars with values and percentages; a donut would be harder to read. *Group by* switches the dimension between asset class, account group, currency, institution, and liquid vs locked, and the device remembers it.
    - *Asset class* splits holdings by their instrument's mix and balances by the account's mix, and shows debts as their own bar.
    - *Currency* is where each part is priced; bitcoin in a euro wallet counts as dollars.
    - *Locked* is pension funds, TFR, property and belongings, and the mortgage secured on the property.
  - Each group is a card: its name and subtotal at the top, then all of its accounts. Groups don't collapse.
  - Each row shows the name and the institution on one line, a clock when the value is stale, and the value on the right. When they don't fit beside the value, the institution goes under the name, and a long name wraps; nothing is cut short, and the value stays on one line.
  - **Stale** means the latest value is older than the threshold (45 days by default). An account that holds nothing (a zero balance, or no cash and no quantity) has nothing to check in, so it's never stale: not in the list, the sidebar, its detail or *Needs attention*.
  - Swipe actions (iPhone): *Close*. The context menu adds *Edit Account…*. Values are typed on the account's page, for an account that takes them.
  - Closed accounts sit under *Closed* at the bottom, a card like a group's with their count at the top.
  - On iPhone the toolbar has *More*, with *Import Files…* and *Instruments*, *New Account* and the eye.
  - On the Mac the cards are a scrolling page; on iPhone and iPad they're a grouped list.
- **Account detail.**
  - **Layout.** Under the account's name, a line with its group and its institution ("Cash, FinecoBank"), or for an account that records trades "Investments, from your trades" (on the Mac, the window's subtitle). Then one card with the value, its change and the chart; then the rest, a card each. On iPhone a trades account's holdings, trades, income and statements are behind a segmented control, one at a time.
  - **In the account's own currency.** The value, its change, the chart and the values list are in the account's currency, which needs no exchange rate: a dollar account in a euro library shows `0,00 US$`. Under the value, its value in the base currency at the day's rate, or "Value in EUR: rate missing".
  - The value and its change since the value before, with the year when it isn't this one: "▼ −123.959,00 US$ since 30 Nov 2021", then its parts (markets, saved, other). A change that shows as zero has no arrow and no sign.
  - A history chart. New-money events are small ticks in a lane along the bottom, pointing up for money added and down for money taken out, coloured by sign, so jumps you caused are distinguishable from market moves; they never stretch the value axis, and the callout gives their amount. The value axis always includes zero, with round ticks that read apart, even for an account that's been at zero. The callout stays inside the chart.
  - A value that can't be worked out (a price missing, or the rate for a position priced in another currency) is a gap in the line, never a zero. A note under the chart says what's missing and when, with *Fill In Past Prices…*: "Some values can't be shown: prices for Gold coins are missing for Mar 2023 – Sep 2025." For an account in another currency, it also says when net worth leaves it out: "Net worth leaves out this account's values for Jun 2018 – Dec 2021: exchange rates for US$ are missing." As on Ahead's chart, a note points out values that use a price more than 31 days old.
  - **Empty accounts.** Once an open account has held nothing for longer than the staleness threshold, it isn't called stale; instead: "This account has been empty since 1 Jan 2022. Close it?" with *Close Account…*, which opens the Close sheet on that day.
  - The list of valuations: date, value, what the kind records, note. Swipe or right-click one to delete it (the confirmation says what that does to what the next value saved). An imported value is read-only: a wrong one is fixed in its file and imported again. Without values: "No values yet. Import a file for this account: a bank statement, a broker's export, or a spreadsheet you keep for it." An account that records trades lists its trades instead: see [Trade history](#trade-history).
  - **Typed values.** An open account that takes typed values ([ACCOUNTS.md](ACCOUNTS.md#typed-values): set to *Typed by you*, or a starting estimate) has *Update Value…* in the toolbar and next to *Close Account…*. It opens a sheet, half height on iPhone: the date (today by default, never after today, nor after the account closed), the balance, prefilled from the last value (*Owed* for a loan or mortgage, typed as what's owed), and the last value with its date. A date that already has a value says "There's already a value on this date. Saving replaces it."; a date before the opening date says "Saving moves the opening date from … to …". Save writes it as a `manual` balance, with a `typed-value` backup, and waits for the write. Tapping a typed value (double-click or *Edit Value…* on the Mac) opens the same sheet as *Edit Value*, which keeps its note. The list's footer says "Values come from your imports and from Update Value. Tap a typed value to change it, or swipe a wrong one to delete it."; without values, "No values yet. Update the value, or import a file for this account."
  - **What the latest value saved**, on iPhone and iPad, as tiles under the chart ([Tiles](#tiles)), when the latest value knows it: **💰 Saved** (mint: the amount, signed, with the value's month under it, "in September", or "in September: 3.400,00 € in, 2.554,65 € out" when it records money in and out) and, for a savings account whose values record interest, **🌱 Interest** (butter, "in September") beside it; without interest, *Saved* is wide. In the account's currency.
  - A cash or savings account's values show what they record: money in, money out, a savings account's interest, and what moved between your own accounts, the part of the change those don't explain (saved − money in − the one-off + money out; [ACCOUNTS.md](ACCOUNTS.md#moved-between-your-accounts)). On iPhone they're lines under the value ("in 3.400,00 € out 2.554,65 €", "moved −1.150,00 €") in place of what it saved; on the Mac, columns *In*, *Out*, *Interest* (savings) and *Moved* after *Saved*. A value from before money in and out were recorded (an account's first, or an older one) shows what it saved alone. A note under the list says what *moved* means.
  - An info section: kind, institution, country, currency, from what age plans can draw on it ("Plans can draw on it: From 67", or "At any age"), its tax on withdrawals for an asset plans count that has one ("Tax on withdrawals: 15%"), how it's recorded (a balance, or trade history), and whether it's included in net worth and plans. A cash or savings account adds what came in and went out over the last twelve months.
- **Add account.** A sheet:
  1. Pick a kind from a grid of icons.
  2. Enter the name, institution, currency, country and opening date. The opening date is today by default; the hint says "Set it to when you opened the account, to add its history."
  3. **Plans:** whether it counts in net worth and in plans and, for an asset counted in plans, **Available only from an age** with a stepper ("Available from 65"): money plans can't draw on before then, such as a pension fund ([PLANNER.md](PLANNER.md#the-model-in-brief)). A pension fund starts at 65, every other kind at any age, until you change it; the footer says "Money available only from an age, such as a pension fund, can't pay for the years before it." A tax pot starts in neither net worth nor plans, and its footer says "Money you set aside for a tax bill is owed, so net worth and plans leave it out. What you put in counts as tax: what came in is after it, and it isn't spent." Changing the kind changes either default until you set it by hand. The account's editor has the same fields.
  4. **Taxes** (an asset counted in plans): *Tax on withdrawals*, in per cent from 0 to 100, empty by default (`withdrawalTaxRate`): the share of every amount plans take from the account that goes to tax, in place of the tax on investments ([PLANNER.md](PLANNER.md#the-model-in-brief)). The footer says "The share of every amount plans take from this account that goes to tax, in place of the tax on investments, such as for a pension fund taxed when it pays out. Leave it empty for an account taxed only on its gains." Emptying it clears the rate; while plans leave the account out the field is hidden and the rate is kept. Changing the account to a debt drops it, and plans ignore a rate that a debt's file holds. Editing the account shows the same field.
  5. **Loss of value** (belongings): *Loses a year*, in per cent, empty or 0 for none (`depreciation`). Changing the account to another kind drops it. Between its values, its value is estimated from it, and its loss of value counts as spent; the next value imported or typed corrects the estimate ([PROGRESS.md](PROGRESS.md#data-this-needs-from-day-one)). Editing the account shows the same field.
- **Edit account.** The same fields, with the kind as a picker. For every kind but a current account, a credit card or a tax pot it adds **Values**: *From imported files* (the default) or *Typed by you* (`values`, [ACCOUNTS.md](ACCOUNTS.md#typed-values)), changeable any time, with the footer "Typed values are balances only: Trends shows no money in and out for them." For savings and investments in net worth the footer says instead "Typed values are balances only. Trends needs the money in and out that statements record, so it's off while a savings or investment account's values are typed." An investment account with trades doesn't show it; one without switches to a balance when typed. A starting estimate doesn't show it: it takes typed values until it's closed. Changing the kind to one that doesn't take typed values drops the choice.
- **Close account.** A sheet asks for:
  - the closing date;
  - "Where did the money go?", which sets the successor account;
  - a short explanation: the account keeps its history, stays in every chart up to that date, and leaves check-ins.

  Reopening is one button. Deleting is for mistakes only, sits at the bottom in red, and asks for confirmation.
- **Instruments** (under Library on the Mac and iPad; on iPhone from the accounts list's *More* menu or an account's positions): name, ISIN or ticker, currency, unit, asset mix, and price source. A new instrument's kind sets the unit, asset mix and price source that usually go with it, as the importer proposes them ([IMPORT.md](IMPORT.md)): a fund, an ETF or a stock is equity; a precious metal is gold, in grams, priced from gold-api.com, unless its name says another metal. Each row shows the latest saved price with its date and source, with a small clock when it's older than the staleness threshold. A footer says: "Prices are also fetched at every check-in. Net worth uses the price on or before each check-in's date. Fill In Past Prices fetches those missing for earlier dates."
  - **Update Prices** (toolbar; pull down on iPhone) fetches today's price of every instrument an open account holds that has a price source, the FX rates that value them in the base currency, and the months the library's inflation indices are missing (as a check-in would: an *Inflation* section, "Added Sep 2026." or "No new months published yet."), and saves them for today in one edit. An index value is only added, never replaced. A banner shows the progress, then the outcome; *Details* lists each instrument as updated, unchanged, failed (with the reason) or kept. A failure doesn't stop the others. A price typed in by hand for today is kept, as in the check-in, unless you choose *Update* on its row. Instruments typed in by hand or not held in an open account are skipped; a row's *Update Price* fetches one anyway.
  - **Set Price…** (on a row, or in the editor) types a price in by hand: the date (today by default), the amount, and the currency (the instrument's by default). It's saved as a `manual` price, which *Update Prices* doesn't replace.
  - **Fill In Past Prices…** (toolbar; the overflow menu on iPhone) fills in the past: every date a position is valued on without a price for that day (each value, and the month ends it carries over to in months without one of its own), the exchange rates those dates need, and the missing inflation months.
    - A sheet lists what's missing: each instrument with where it comes from, its date range and count ("Gold coins · gold-api.com · XAU · Oct 2015 – Sep 2026 · 132 dates"), then the rates and inflation, then **To type in**: instruments without a price source.
    - **Fill In** fetches with a progress bar: each instrument's whole range is one request, then one per currency and index ([PLAN.md](PLAN.md#prices-and-fx)). Metals' past prices come from their futures on Yahoo Finance (`GC=F` for gold), within about 1% of spot; crypto from Yahoo's pairs (`BTC-EUR`).
    - Then each line shows how many dates it got and from where: "12 of 12 · Yahoo Finance · GC=F (history)", or "gold-api.com · XAU back to Sep 2026, Yahoo Finance · GC=F (history) before". What's left is listed with its dates and the reason, never skipped: *Set Price…* opens on one of its dates, and *Choose a Price Source* (or *Change Price Source*) opens the instrument's editor; *Check Again* fills in again after that.
    - The records are saved in one edit into their month files, after a `fill-history` backup. Nothing already saved is replaced: not a price typed in, not one from an import, not one fetched before.
  - The editor's *Test price fetch* saves nothing by itself. For an instrument that exists, a successful test offers *Save price*; a new instrument's tested price is saved with the instrument. The symbol's placeholder follows the source: "Yahoo ticker, e.g. VWCE.DE", or for crypto the pair in the instrument's currency, "BTC-EUR".
  - **Find…** (next to the symbol, or *Find on Yahoo Finance…* for an instrument typed in by hand) searches Yahoo Finance by the ISIN, else the ticker, else the name, which can be changed before searching again. Each listing shows its symbol, name, exchange, kind and currency ("XETRA · ETF · EUR"); the first in the instrument's currency is marked *Best match*. Choosing one sets the price source to Yahoo Finance with its symbol, and *Test Price Fetch* tries it. Only what's searched for leaves the device. A listing's currency is Yahoo Finance's when the search gives one, else that of an exchange where nearly everything trades in one currency (XETRA and Milan in EUR, New York in USD); London, which lists in several, has none (`SymbolCandidate.likelyCurrency`).

## Adding history

Accounts added in the app open on the day they're added, unless you set an earlier opening date. Their past values come from files, or for an account whose values you type, from *Update Value…* on an earlier date ([ACCOUNTS.md](ACCOUNTS.md#typed-values)), which moves the opening date back when it's before it.

- **Import.** For existing accounts, the import's *Accounts* step links the names in the file to them, and the profile remembers the match. Values from before an account's opening date propose to open it on the first of them, applied unless you reject it ([IMPORT.md](IMPORT.md#matching-accounts-and-instruments)).
- **A past check-in.** Pick an earlier date in the check-in's date panel: its import reads statements through that date, and its prices are fetched for it. Yahoo Finance (crypto too, through its pairs such as `BTC-EUR`) and Frankfurter (ECB) have history. gold-api.com only has today's price, so a metal's price comes from its futures on Yahoo Finance, and the price list says so: "Yahoo Finance · GC=F (history)". Values saved after the date stay as they are, and a banner says it's a past check-in.

**Past prices.** Whichever way history arrives, its positions only have the prices it brought: a spreadsheet's price columns, what a past check-in fetched. Gold bought years ago would otherwise stay at its purchase price in every month since. *Fill In Past Prices…* fetches the rest ([Instruments](#accounts)); the import's Done step offers it ("12 past values have no price for XAU"), and so does a note under a chart that uses old prices.

**Saved after an inserted value.** What a value saved is worked out from the value before it, except on an account that asks for it (pension funds, TFR, property, other), where it's recorded. So when a value is added before another one of the same account, or one is corrected, moved or deleted, what the next value saved follows, and a recorded one stays. Money in and out ([PROGRESS.md](PROGRESS.md#money-in-and-out)) stay as they are: the confirmation for deleting a value asks to check them on the value after it. An import adds values the same way, and undoing it puts them back ([IMPORT.md](IMPORT.md#preview-conflicts-and-undo)).

**Answers and baselines are only recorded for the latest check-in.** The plan runs on today's data, so re-running it for a past date would record a made-up answer for a past check-in and a made-up January plan for its year. A check-in dated before the library's latest one records neither, and its confirmation says: "Saved a past check-in (31 Mar 2024). The answer isn't recorded for past dates."

## Trade history

A brokerage, crypto or metals account records its **trades** ([TRADES.md](TRADES.md)): its holdings, average cost, cash, realised gains and income follow from them. Its trades come from the broker's exports ([IMPORT.md](IMPORT.md#broker-transactions)); the app doesn't type or edit one. New accounts of those kinds record trades; nothing switches an account back to a balance.

**Account detail** of an account that records trades, top to bottom:

```
┌──────────────────────────────────────────┐
│ Directa                               ✎  │
│ 57.410,35 €   ▲ 1.318,92 since 31 Aug    │
│ ┌ history chart, deposits as ticks ────┐ │
│ ⚠︎ VWCE differs from the statement       │
│   The statement on 30 Sep shows 424,5    │
│   VWCE; your trades give 414,5. Import   │
│   the missing trade, …                   │
│ HOLDINGS                                 │
│ Vanguard FTSE All-World      57.098,25 € │
│   412,5 sh × 138,42 € 99% of the account │
│   Average cost 116,85 € ▲ 8.898 € +18,5% │
│ Cash                           312,10 €  │
│ Total                       57.410,35 €  │
│ TRADES                                   │
│                       20 trades Filter ▾ │
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
│ STATEMENTS                               │
│ 30 Sep 2026                cash 312,10 € │
│               not in the trades +11,30 € │
│ …                                        │
│ DETAILS · …                              │
└──────────────────────────────────────────┘
```

- **Holdings**: per instrument, the quantity, price, average cost (*costo medio*: what was paid per unit, fees included), value and unrealised gain; then the cash and the unrealised gain of them all. On iPhone each position is two lines: the name, wrapping when it's long, and the value; "412,5 sh at 138,42 €, paid 116,85 € each" and the gain ("▲ +8.898 €"), the gain under it when they don't fit. On the Mac, a grid with those columns, its share of the account and the total; a long name wraps in its column.
- **Trades**: grouped by month, newest first; each row shows the type's icon, what it was ("Buy 0,10383916 BTC") over its price, date and note ("at 101.437,76 € · 1 Oct 2025", the price in its own currency), and on the other side the cash it moved, with a sale's realised gain. A trade paid from outside the account shows what was paid or received, marked "paid from outside" (a sale: "proceeds paid out"); on the Mac the mark leads its note. At the largest text sizes the amount goes under the description. *Filter* shows one instrument or one type. Swipe or long-press a trade to delete it (the confirmation says what deleting brings in, e.g. a later sale now selling more than is held). On the Mac, a table (date, type, instrument, quantity, price, amount, note) as long as its trades, which scrolls with the page: right-click deletes.
- **Income & gains**, by year: realised gains, dividends, interest, fees and taxes, and the net; a sale whose cost is unknown is left out and said so. In the account's currency.
- **What needs a look**, as banners with the fix: a trade missing a price or amount, a sale of more than was held, an opening without cost, a missing exchange rate, a trade outside the account's dates, a value with a balance (which isn't used), and a statement that differs from the trades ("The statement on 30 Jun shows 12 VWCE; your trades give 10. Import the missing trade."). The fix is in the file: correct it and import it again, or delete the trade. A trade outside the account's dates offers *Edit Account…*. Today's *Needs attention* points to an account with any of these ("Directa: 2 problems with trades").
- **Statements**, in place of the values at check-ins: the values that record a broker statement, newest first. The account's other values only follow the trades, so they aren't listed. A statement is a value whose cash differs from what the trades give on its day ("cash 312,10 €", and "not in the trades +11,30 €", which counts as money added or taken out), or one that lists positions ("1 position listed, 1 differs from the trades"; [Reconciliation](TRADES.md#reconciliation)). An import of a broker statement records one. Swipe one to delete it; on the Mac, a table (date, cash, not in the trades, positions, note), where right-click deletes. Without any, the section isn't shown. The history chart, the header's change and the new-money ticks come from the Valuator (deposits and transfers on their own dates).

## Ahead

The plan. Its name is its menu (Base case ▾: the plans, then New Plan, Duplicate, Rename…, Set as Main Plan, then what every chapter shares, *Assumptions…*, *Target Mix…* and *Flexible Spending…*, then *Export Calculations…* under how the results shown were calculated, "Calculated at 09:41 with 2.000 runs" or "Not calculated yet", and Delete…, whose confirmation says "The dates it worked out at your check-ins stay in the library."). Then one page: your last Monday with the plan's chart to its end, What if, the key numbers, and your life ahead. On iPhone the page has no navigation bar: it draws "Ahead" as its large title, with the plan menu and the eye beside it. On the Mac and iPad a header row holds "Ahead", the plan menu under it and how the results were calculated; the toolbar has *Calculate* (*Recalculate* once there are results) and the eye. *New Plan*, *Duplicate*, moving the levers, *Save as a New Plan…* and *Export Calculations…* come with [Plus](#plus); without it they open the paywall.

### Calculating

A plan calculates on its own, in the background. Ahead runs it 600 ms after the plan or the library last changed, when its results are missing or no longer fit, so a burst of edits runs once. Today runs the main plan when it has no results or they no longer fit, A check-in runs it to record the month's answer, and What if's levers run their what-if as they come to rest ([The plan](#the-plan)), and an edit sheet works out *With this change*. *Recalculate* (⌘R, and *Calculate* or *Recalculate* in the toolbar on the Mac and iPad) runs it on request. A plan whose last run failed isn't tried again on its own: it says why, with *Try Again*. Choosing another age under *If you stopped at another age* runs nothing either: its charts show at once when they were calculated before, else after *Recalculate*. Each plan keeps its own results, levers and chosen age while you switch between plans.

**Results are kept on the device.** Each plan's latest results (not a what-if's, nor another age's) are kept on this device, outside the library, so they show again the next time the app opens, without waiting: up to date when the plan and your accounts and prices are as they were, else dimmed until the plan has run again. They don't sync: each device keeps the results it calculated, and the library holds only what a check-in records (its answer, and the year's baseline). Results up to date with your accounts and prices are the latest answer, whatever date the plan starts from. When they're not up to date because the library changed, and the other device recorded an answer at a check-in they didn't see (one after the latest check-in when they were calculated), Today, So far and the widgets show that answer instead, until the plan is calculated again. An answer recorded at a check-in they saw doesn't: after a trade or an edited account they stay the answer until new results replace them. The plan menu says when they were calculated: "Calculated at 14:05 with 2.000 runs", with the day when it isn't today ("Calculated on 3 Oct at 14:05 …") and the year when it isn't this one. Results of an older version of the app's calculations aren't shown, nor results in another base currency than the library's (after it changed), and the system may clear the kept results when space runs low; the plan is then calculated again.

- **Before the first calculation.** The date header shows the answer recorded at the last check-in, while the plan runs; with nothing recorded, "Working out your date…", or "Your date shows here once the plan is calculated." when it can't run yet.
- **Not up to date.** Results that no longer fit the plan or your data (the plan was edited, a rename aside; your accounts or prices changed; a lever moved) stay on screen, the date dimmed, until the run on its way replaces them. There's no banner. Results calculated before for exactly the current inputs, e.g. after changing an input back, show again at once, without a run.
- **Calculating.** While a calculation runs, its progress shows under the date, and the old results stay, dimmed:

  ```
  ┌──────────────────────────────────────────┐
  │ Calculating…                    [Cancel] │
  │ Earliest age · ages 38–75: 12 / 38       │
  │ ▇▇▇▇▇▇▇▇▇▇░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  │
  │ Overall                             29%  │
  │ ▇▇▇▇▇▇▇▇▇▇░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  │
  └──────────────────────────────────────────┘
  ```

  - The phase and its own bar, in the locale's numbers with tabular figures: "Earliest age · ages 38–75: 12 / 38" (most of the time: the chance at every age), "Simulating 1.234 / 2.000 runs" (the chosen age in detail), "Sustainable spending: step 4 / 16", "Needed to retire today: step 3 / 9", "Summarising". Then the whole calculation's bar. A first pass with fewer runs says "Estimating…".
  - **Cancel** stops it; the old results stay as they were. A check-in's calculation can't be cancelled here: it says "Working out this month's answer…".
  - Editing an input while it runs lets it finish; the plan then runs again for the edit. Cancelling instead would throw away a calculation, while it's usually seconds from done.
  - The same view shows on iPhone and Mac, and in the check-in's confirmation. Today's answer says "Updating 29%" meanwhile. A what-if's run shows only the levers' spinner.

### The plan

The plan reads as a life ([PLANNER.md](PLANNER.md#chapters)): your last Monday first, with the chart of your money to the plan's end, then *Your life ahead*: the **chapters** and what changes along the way, down one line, with when you stop working on it. A chapter starts in the year the work you do changes, work stops, the first pension is paid, or retirement spending moves to another phase; everything else (another pension, a contribution, an event, a change of the target mix) belongs to the chapter it starts or happens in.

On iPhone:

```
┌──────────────────────────────────────────┐
│ Ahead                        Base case ▾ │
│ ╭──────────────────────────────────────╮ │
│ │ Your last Monday                     │ │
│ │ At 63, 27 March 2051                 │ │
│ │ In 9 of 10 futures your money lasts  │ │
│ │ to 95.                               │ │
│ │ ━ Typical  ▇ Half of futures  ░ 8 in 10│
│ │        ┃Now, 38    ┃27 Mar 2051, at 63 │
│ │  ▁▂▃▄▅▆●━━━━▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒   500k │ │
│ │ 30    40    50    60    70    80  90 │ │
│ │ [ What if… ]  [ 21.572 € ahead › ]   │ │
│ ╰──────────────────────────────────────╯ │
│ ╭ 🛍️ You could… ─╮╭ ⛵ Saving nothing… ─╮ │
│ ╰─────────────────╯╰───────────────────╯ │
│ Your life ahead                     Add  │
│ ● ╭ ① Employee            now to 41 › ╮ │
│ │ │ 4.200 € take-home, 3.000 € spent,  │ │
│ │ │ 1.200 € saved a month    Today 180k│ │
│ │ ╰────────────────────────────────────╯ │
│ · ╭ State pension   From 67  1.100 € › ╮ │
│ │ ╰────────────────────────────────────╯ │
│ ◉ ╭ You stop working                   ╮ │
│ │ │ At 63, 27 March 2051               │ │
│ │ │ 820.000 €, typically               │ │
│ │ │ ‹ 62: 8 in 10      64: 10 in 10 ›  │ │
│ │ ╰────────────────────────────────────╯ │
│ ● ╭ ③ Pensions                  67 on › ╮ │
│ │ ╰────────────────────────────────────╯ │
│ ○ ╭ 95 · The plan's end                ╮ │
│   │ 350.000 € left, typically.         │ │
│   ╰────────────────────────────────────╯ │
└──────────────────────────────────────────┘
```

On the Mac and iPad it's the same page, wider: the header row; your last Monday's card with the levers beside it (What if, below), or under it when the page is too narrow for both; the chart on a card of its own, "Your money to 95", with its legend beside the title; *Your life ahead* on the same line, with what changes in a chapter beside it; and the tiles on the grid of slots ([Tiles](#tiles)).

- **Your last Monday.** A card: "Your last Monday" ("Your last Monday, with the levers" in the accent once a lever has moved, with a chip for how far they moved it: "10 months sooner", "A year later", "Same date"), then the age and date large ("At 63, 27 March 2051"; "You could stop today" or "Not yet" without a date; "No age works out in 9 of 10 futures yet. Try What if." under it), and how sure: "In 9 of 10 futures your money lasts to 95." On the Mac and iPad it adds how sure stopping at the plan's own age is ("Stop at 55: 4 in 10.") when that isn't the earliest age. The date dims while the results are being recalculated or no longer fit. Before the first calculation it's the answer recorded at the last check-in. A calculation's progress shows under it ([Calculating](#calculating)). On iPhone the card holds the chart (below), then *What if…*, which opens What if, and how far ahead of what you planned in January you are ("21.572 € ahead ›", "… behind ›" in orange), which opens So far; on the Mac and iPad only the latter ("21.572 € ahead of January").
  - What stops the plan from answering (it can't run, a change wasn't saved) shows above it as a banner, with *Try Again* after a failed run; what it assumed that you may want to change shows under it, quietly, a line each with the way to fix it: "TFR counts as cash: it has no mix of investments set. *Set one…*", which opens the account (two at most; the rest with the inputs they concern).
  - **Feedback screenshots** hide the date, the age, the futures and the levers' values; amounts are amounts.
- **The chart** (`DecadesChart`): your records to now, then the plan's futures to its end, across your ages. Its legend, one row: *Typical* (the median, a blue line), *Half of futures* (the 25–75% band) and *8 in 10* (the 10–90% band), and, once a lever has moved, *With the levers* in place of *Typical* and *As it is*, the plan as it is, dashed. Above the chart on iPhone, beside the title on the Mac and iPad.
  - Your money to now in ink, then the futures from now: the typical one as a blue line, half of them in the darker band and 8 in 10 in the lighter one. The value axis fits the past and the typical future, its top about a tenth above the higher of them, so the typical line stays readable however far the luckiest futures grow; the bands may run off the top, cut at the edge. The gridlines' amounts are at the left (multiples of today's value while amounts are hidden).
  - A rule at *Now* ("Now, 38"), and one at the day you stop, with its date and age in a blue label ("27 Mar 2051, at 63").
  - Your ages along the bottom (every 1, 2, 5, 10 or 20 years, as many as fit; years without a birth date), and the plan's chapters as a band under them, each in its colour and named where its name fits.
  - The past reaches back as far as the accounts' time span (*History* in the accounts list's chart).
  - **The past shows the money in the plan.** The projection is of what the plan counts (e.g. without your home and its mortgage), so the past covers the same accounts, through the latest check-in, where the plan starts, and its total meets the projection's median there. The alternatives mislead: net worth up to today and then a projection of less would look like a fall at today, and carrying the home on at its last value would invent a forecast the plan doesn't make.
  - **Reading it.** The pointer, or a finger touched and held then dragged, reads the money there: a rule, a dot and a callout with the date and your age, then your value, or over the futures the median as the headline with *Top 10%* and *Bottom 10%*. The callout's amounts are short: below 1.000.000 in full (`300.000 €`), from there in millions with three significant digits (`1,00M €`, `12,3M €`), and from 1.000.000.000 in billions the same way (`1,00B €`). VoiceOver reads the chart with its audio graph and chart details, and the full amounts.
  - **Old prices.** When a value in the chart uses a price more than 31 days older than its date, a note under it says so: "10 values in the chart use a price more than 31 days older than their date (Gold coins)." with *Fill In Past Prices…* (see [Instruments](#accounts)).
  - **Partial totals.** Where a total misses something (a price or an exchange rate, or an account with no value yet), the line is dashed and grey there, and a note under the chart says what and when, with *Fill In Past Prices…* when some of it is prices or rates.
  - Once a lever has moved, the chart is the what-if's, and the plan as it is shows as a dashed line in the taxes' colour.
- **What if.** Three levers, each with its name and value over its slider and what the plan says under it: **Stop working at** ("55", or "As early as you can" while the plan retires as early as it can; "As planned: at 60."), **Take-home pay, while working** (a change a month on top of the pay of each working chapter that hasn't ended before the plan starts, "+300 €", or "As planned"; "As planned: 4.200 €, then 3.500 € a month."; "Set take-home pay in a working chapter to move it." without pay) and **Spend a month, retired** ("3.000 €"; "As planned: 3.000 € a month in every retired chapter."). Pay and spending move 50 a month at a time (`PlanWhatIfModel`). On iPhone *What if…* opens them in a sheet: *The main levers* on a card, then *With these levers* (see *With this change*; "Move a lever to see what it does to your date." before one moves), with *Reset* and *Done* in its bar; *Done* keeps the levers where they are, so the page shows their date, chart and tiles until they're reset. On the Mac and iPad they're a card beside your last Monday, "What if" with "Move a lever and the chart follows.", *Reset* and a spinner while the date updates; the page's chart and tiles follow the levers.
  - The what-if runs 350 ms after the last move: a first pass with fewer runs, then all 2,000, with the same random draws. A position calculated before shows again at once.
  - After a move: **Apply to Base case** writes the levers into the plan ("Apply writes the levers into the chapters: the pay into each working chapter, the spending into each retired one.") and resets them; **Save as a New Plan…** asks for a name ("Save as a new plan": "A new plan with the levers where they are. This plan stays as it was."; left empty, "Base case, changed", made unique), and the new plan opens. Without Plus the levers are greyed, with *Move the Levers…*, which opens the paywall.
- **With this change.** Every sheet that changes the plan (work, a pension, other income, a contribution, an event, spending, the target mix) has, after its form, *With this change*: your last Monday with the change, large, with a chip for how far it moves it ("10 months sooner", "A year later", "Same date") and "Was 27 March 2051, at 63."; the plan's chart with the change, the plan as it is dashed under it (*As it is*); and four small tiles, each with how it moved in a capsule, green when it's good news, orange when not: **How sure** ("9 in 10", "▲ from 8 in 10", against the plan as it is at the same age), **Saved a month** (while working), **You could spend** (a month, retired) and **Money left at the end** ("at 95, typically"). It's worked out as you type: what the engine kept for the copy shows at once, else, once the form rests for 250 ms, a quick estimate, then every run; meanwhile the last figures dim (before any, the plan as it is dims, with "Working out what it does…"). Before a change it shows the plan as it is, so the chart is there when you start typing: its date with "Change something above to see what it does to your date.", its chart (*Typical*) and its tiles, without capsules. The sheet's confirm button reads *Apply*, and *Save as a New Plan…* under the preview saves the plan with the change as another plan instead (with Plus). The preview's runs are the sheet's own: they don't replace the plan's results or show a calculation's progress, and the engine keeps them like any run, so applying the change shows its results at once.
- **Results as tiles.** Once there are results, tiles after your last Monday ([Tiles](#tiles)), at every width: **🛍️ Spending you can afford** (butter: "2.350 €", "a month from 55, in 9 of 10 futures": the engine's solver for the highest spending that still meets your confidence level, from the age the chapters are cut at); **⛵ If you stopped saving now** (the age you could still stop at if you saved nothing more, "earliest age to stop", as So far has it; [PLANNER.md](PLANNER.md#ages-without)) over **🐢 Saving as much as last year** (the age at your pace of the last 12 months, "earliest age to stop"), half tiles, or saving nothing more small without a pace; **🧮 Needed to retire today** (what retiring today would need, [PLANNER.md](PLANNER.md#assets-needed-to-retire-today), or "At most what's locked away" when retiring today works even with the money you can draw emptied), with a bar for how much of it you have ("You have 64% of it"); **🏁 Money left at the end** ("at 95, typically") over **🧾 Taxes from now to the end** ("in total, typically"), half tiles; and across the row **🎯 If you stopped at another age**: "How many of 10 futures keep your money lasting to 95.", a bar for each of up to 11 ages around the earliest age, as tall as the futures it lasts in, the earliest age's in the accent and the age the chapters are cut at outlined, a dotted rule at your confidence level, the ages under them, and the answer in words ("Stop at 63: 9 in 10. Stop at 60: 6 in 10."). Tapping a bar cuts the chapters at that age ("Chapters for stopping at 57 · 6 in 10", with *Plan's age* to go back). In today's money, in the library's base currency; the rest is in *Export Calculations…*.
- **Your life ahead**, with *Add* (a work phase, a pension, other income, a contribution, an event, a later phase of spending or a change of mix, each in the chapter it starts in) and "The chapters and what changes along the way, in order. Tap one to change it; the chart redraws." Then one line down the left, a dot for each stop: the chapter's colour for a chapter, a small dot for its changes, the accent for when you stop, a ring at the end. On the Mac and iPad the line stays, in two columns: a chapter, *You stop working* and the plan's end on the left, what changes in a chapter beside it on the right, sharing the chapter's dot; a page too narrow for both has one column, as on iPhone.
  - **A chapter** is a card: its number, white in a circle of the colour of its kind of life (grey while working or between jobs, orange for the bridge before the pensions, violet with them, a lighter violet for a later phase of spending), its name ("Employee", "Not working", "Bridge", "Retired" when no pension is ever paid, "Pension" or "Pensions", "Slowing down" or "Spending more" for a later phase), its ages with a chevron ("now to 41", "41 to 55", "67 on"), its month's money in words ("4.200 € take-home, 3.000 € spent, 1.200 € saved a month", "3.000 € a month from your savings", "1.900 € from pensions, 1.100 € from savings"), its one-offs ("New car 2031, 25.000 €"), and the money typically there as it starts ("Today" for the first, "At 41, typically"). It opens the chapter's sheet (below).
  - **What changes in it** follows the chapter on a card of its own, a row each, as its settings are: other income, contributions, one-offs, later spending and changes of the target mix, each opening its sheet. Work and pensions aren't rows: the sheet of the chapter they start in lists them (work and the first pension paid in retirement start a chapter of their own).
  - **You stop working**, before the first retired chapter: "At 63, 27 March 2051" (the year without a day before the plan is calculated), the money typically there then, where 8 in 10 futures are ("8 in 10 futures: 600.000 € to 1,1M €"), and a stepper on the line, "‹ 62: 8 in 10" and "64: 10 in 10 ›", which sets the plan's own age a year sooner or later (the lever's, within its range, while it has moved; an age chosen on *If you stopped at another age* gives way to the plan's). Tapping the card opens when work stops in its small editor.
  - **The plan's end**: "95 · The plan's end", "350.000 € left, typically. Runs out first in 1 of 10 futures.", opening the end age's small editor.
- **A chapter's sheet**, titled with its name and "41 to 55, 2029 to 2043", with *Done*. The chosen chapter follows its first year, so the sheet stays put while an edit moves the chapters. Each value has one place where it changes. First its settings, then its words:
  - **In this chapter** ("A month, in today's EUR"): every input that starts in the chapter, once, as a row with its name and its value, each on one line, and a chevron: when work stops ("As early as you can"), spending while working or in retirement and flexible spending ("Never below 80%", "Off"), a later phase of spending ("Spending from 75"), take-home pay, pensions, other income, contributions ("Into Fondo pensione", or a one-off's amount), events ("2031, −25.000 €"), the target mix and its changes with age ("Your savings from 60", "60% in shares") and the plan's end in the last chapter; "Nothing starts in this chapter." without any. VoiceOver adds each row's details ("At 54, in 2042", "From 67, after tax"). When work stops and the plan's end open their small editor (a popover pointing at the row on the Mac and iPad, a sheet on iPhone): its stepper or switch, applied as you change it. Spending (while working, in retirement, flexible, and each later phase) and an item open a sheet, the target mix its own. A sheet has a grouped form with an inline title, then *With this change*, and *Cancel* and *Apply*: it edits a copy, which *Apply* writes into the plan, and while it has changes, swiping it down does nothing. An input's problems show on its row. Under the rows, what carries on from earlier chapters ("Continuing: Spending while working · Saving into Fondo pensione · Target mix"), and **Add to This Chapter**: before retirement, a work phase (from the chapter's first day) or a contribution (in a later chapter, a one-off in its first year); in retirement, a pension from the chapter's first age or a later spending phase from its middle; in any, other income (from when work stops in the chapter it stops in, else from the chapter's first age) and an event in its first year. Each opens its sheet, titled for a new one ("New later spending"), and adds nothing until *Apply*.
  - **What happens**, on a card, in words that only read, their values in bold: "You take home **4.500 €** a month and spend **3.000 €**, so you save about 1.500 €.", "You stop working **as early as you can**, at 54 in 2042, and spend **3.000 €** a month, all from your savings.", "**State pension** pays **1.100 €** a month from **67**.", "In **2031** you spend **25.000 €** on **New car**." Amounts are a month's, from the plan's yearly ones, in today's money. An uncertain windfall says what it's worth to the answer: "At **62** you may receive **150.000 €** from **Inheritance**, **80%** likely; without it, your earliest age would be 56." ([PLANNER.md](PLANNER.md#ages-without)).
  - Under the words, a month's money as a bar, with a line under it: while working, "Spent 3.000 €" and "Saved 1.500 €", or, when pay falls short, what your savings add; retired, what comes from your savings and, once calculated, the tax on what's sold, as the chapter's average a month in the median run ("400 € of it tax, on average"; from its first whole year of retirement to its last, the years the run reaches, a year without tax counting as none). An average, not the first year's: the share of gain in what's sold grows over the years, as what was paid for what's left shrinks with each sale and with inflation while its value keeps its returns, so the first year pays the least. With pensions or other income, what they pay ("Pensions", "Other income", or "Income" for both) and what's left to draw or to spare.
  - **Along the way, typically**: the milestones the median future reaches in the chapter, as rows, the name and when ("400.000 €", "mid 2027"), four at most, then "And 2 more ahead." ([Milestones](#milestones)).
  - **What can go wrong**, once calculated: in the bridge, "In 3 in 100 futures, the money you can draw runs out before Fondo pensione opens at 67."; in a chapter where futures run out, "Most of the futures that run out here do so before 85."
- **The age they're cut at.** Work stops at the age the charts are for: one chosen under *If you stopped at another age*, else the levers', else the plan's own, else the earliest age the plan found, else the one recorded at the last check-in. A plan asking for the earliest age with none of these yet assumes 65 until it's calculated, and says so where work stops. When the charts are for an age chosen there, it says that, with *Plan's age*.
- **Outside the plan's years.** Inputs that apply in no year the plan runs (an event after its end, a work phase over before it starts, a pension without an age) are listed after the chapters as settings, like the rest. Without a birth date there are no chapters: a card asks for it instead.
- **What every chapter shares** is in the plan menu: *Assumptions…* opens a sheet of collapsible cards with a one-line summary each: **You** (the birth date, as in Settings), **Taxes**, **Assumptions** (inflation, shares above inflation, the tax on investments), **Target mix** and **Simulation**; *Target Mix…* and *Flexible Spending…* open their own sheets. The disclaimer ends the page.
- **Problems** are worded for the screen: accounts by their names, not their IDs ("A contribution goes into Fondo pensione, which the plan doesn't count; it's left out.").

#### The editors

- **New plans and items.** A new plan retires as early as possible, and takes its tax rates and spending from the main plan (else another plan), since you've said them already. A library without plans starts from 30.000 euros' worth of spending in its base currency at its latest exchange rate, to two significant figures (35.000 for dollars, 4.800.000 for yen), or 30.000 when it has no rate to the euro, and with no tax rate on investments: it runs as if they weren't taxed, with a notice to set the rate. A new work phase earns 4/3 of the plan's spending while working, a new contribution is a thirtieth of it a year and a new event an expense of a third, so every default is in the plan's own money; a new pension starts at 67, with its amount to enter.
- **Amounts a month.** The settings, the small editors and the sheets take amounts a month, as the words say them (the plan stores them a year: a month typed in counts twelve times). One-offs, events and the wealth tax's allowance are their amount.
- **Work phases.** Each is a setting in the chapter it starts in ("Employee", "2026–28 · take-home pay · grows 1% a year", "3.333 €"). The editor has the name, the dates (from, and until a date or retirement), **Take-home pay** a month and an optional real growth: "What reaches your bank account in a month, after income tax and social contributions, in today's EUR. Growth is a year, above inflation."
- **Pensions.** Each is a setting ("State pension", "From 67, after tax", "1.167 €"). The editor has the name, the age it's paid from, and **After tax, a month**: "From your pension statement, after the tax you expect to pay on it, in today's EUR."
- **Other income.** Each is a setting ("Rent", "From 45 until 85, after tax", "800 €"), and in the chapter's words: "Part-time pays 1.500 € a month from when you stop working until 60." The editor has the name, **From when you stop working** (on) or the age it starts at, **Stops at an age** and the age, and **After tax, a month**: "Rent, a side business, an annuity, or part-time work once you stop your main job, after tax, in today's EUR. Unlike work, it doesn't stop when you retire."
- **Contributions.** Each is a setting ("Into Fondo pensione", "Until you stop working", "417 €"). The editor picks the account it goes into ("Paid into the account, and drawn once it's available (Available from age on the account). The rest of your savings goes to the money you can draw."), and whether it's paid every month (**A month**, until retirement or a date) or once, in a year.
- **Spending.** While working (in the first chapter), in retirement (where you retire), and the later phases (from an age, a share of it, where each begins). Each is a setting with a sheet of its own:
  - **Spending while working:** **A month**: "In today's EUR.", then what the cash and savings accounts recorded going out a month in the last year, when they did: loan, mortgage and credit card payments included, money moved between your own accounts left out.
  - **Spending in retirement:** **A month**: "In today's EUR. Later phases spend a share of it."
  - **Later spending:** the age it starts at (**From 75**) and **Share of spending**, each a row: "From an age, a share of what you spend in retirement." **Delete** at the bottom removes a phase already in the plan.
  - **Flexible spending** ([PLANNER.md](PLANNER.md#flexible-spending)), a setting after spending in retirement:

  ```
  Flexible spending                      [ ● ]
  Cuts spending in retirement after bad years and restores it after good ones, as real
  retirees do, instead of spending the same whatever the markets do. A future only fails
  if you'd have to spend less than the floor.

  Cut by                                [10] %
  Never below                           [80] %
  Of the plan's spending in retirement: 28.800 €/yr.

  GUARDRAILS
  Cut when it rises by                  [20] %
  Restore when it falls by              [20] %
  Each year the plan compares the share of your money you draw with the first year of
  retirement's: this much above it, spending is cut; this much below it, a cut is restored.
  ```

  - The switch writes `{ "enabled": true }`; turning it off keeps settings that differ from the defaults (`enabled: false`), and with only defaults removes the rule, so nothing is written.
  - The fields show the defaults as their prompts; a field left empty, or set to its default, isn't written. *Never below* is also shown in money: the floor share of the retirement spending, before the phases, hidden with the eye.
  - The guardrails are a section of their own, with their explanation under them. Settings out of range show as errors above the chapters.
- **Taxes** ([PLANNER.md](PLANNER.md#the-model-in-brief)):

  ```
  Tax on investments                    [26] %
  Paid on the gain part of what you sell and, every year, on the income your
  investments pay out (Assumptions, income yield). 26% in Italy, for example; 0% if
  they aren't taxed. Income from work, pensions and other income is entered after tax.
  ──────────────────────────────────────────
  Wealth tax                             [ ● ]
  Rate                                [0.2] %/yr
  Untaxed allowance                  [5000] EUR
  A yearly tax on the money you can draw, above the allowance. Accounts available only
  from a later age, such as a pension fund, aren't counted until then.
  ```

  - Until the rate on investments is set, the plan runs as if investments weren't taxed: the card and the answer show the warning "Tax on investments isn't set, so the answer assumes none. Set it under Taxes (0% if they aren't taxed).", and the summary says "Tax on investments not set".
  - Turning the wealth tax off removes its rate and allowance from the plan.
- **Assumptions.** Inflation, then each class's real return as its mean and its median, and its volatility, three fields a row ("Crypto 16.6 % · 0 % · 70 %"). Either return can be typed: the other follows from it and the volatility, and changing the volatility keeps the one that was given (crypto's default is given by its median). The line under them: "Placeholders to review, not forecasts: real returns after fund costs. The mean is the average year, the median the typical one, which a portfolio rebalanced every year grows at. Enter either: the other follows from the volatility." What equals the default isn't written to the plan. The card's summary shows equity's return as it's given: "Equity 5% typical year", or "Equity 4,5% average". Then an optional **income yield** for equity and bonds: "The part of the return paid out as income each year (dividends, interest), taxed every year at the rate on investments. Leave it empty to count it as growth, taxed when sold." Then the estimate of unrealised gains for holdings without a purchase cost, and the accounts in the plan, each with a switch. A class the portfolio holds whose median is below −2% a year gets a warning on the card: "Crypto's returns give a typical year of −18% (an average of 0.0% at 70% volatility): holding it and rebalancing back into it every year shrinks your portfolio. Check its return under Assumptions."
- **Target mix.** A sheet of its own, opened from the chapters' words and from its card in *Assumptions…*: the mix the plan rebalances the money you can draw to every year ([PLANNER.md](PLANNER.md#target-mix)). It's a grouped form like the work phase sheet, and like it edits a copy of the plan's target mix and its changes with age: *Apply* writes them to the plan, *Cancel* throws them away. Once something is changed, swiping the sheet down does nothing, so only *Cancel* loses an edit. The footer of its first section says what rebalancing does: "Each year the plan rebalances the money you can draw back to this mix: what you save goes in at it, withdrawals sell every class alike, and rebalancing isn't taxed."

  ```
  Cancel            Target mix          Done

  REBALANCE TO
  ┌─────────────────────────────────────────┐
  │ [ Today's mix | A mix I choose ]        │
  └─────────────────────────────────────────┘
  Each year the plan rebalances the money you can draw back to this mix: …

  TARGET MIX
  ┌─────────────────────────────────────────┐
  │ Equity                         [80] %   │
  │ Today 46% · 44% of all                  │
  │ Median 5.0% a year                      │
  │ Bonds                          [20] %   │
  │ Today 0% · 5% of all                    │
  │ Median 1.5% a year                      │
  │ Crypto                         [  ] %   │
  │ Today 35% · 28% of all                  │
  │ Median 0.0% a year                      │
  │ ✓ Total 100%                            │
  └─────────────────────────────────────────┘
  Grows at a median of 4.5% a year, rebalanced every year (today's mix: 3.0%).
  Today: the share of the money you can draw, then of all the money in the plan.

  FROM RETIREMENT                         ⊖
  ┌─────────────────────────────────────────┐
  │ [ At an age | At retirement ]           │
  │ The year you stop working, whatever age │
  │ the plan finds: 55 in this plan.        │
  │ Equity                         [60] %   │
  │ Bonds                          [40] %   │
  │ ✓ Total 100%                            │
  └─────────────────────────────────────────┘
  Grows at a median of 3.6% a year, rebalanced every year.

  FROM 75                                 ⊖
  ┌─────────────────────────────────────────┐
  │ [ At an age | At retirement ]           │
  │ From 75                          [–|+]  │
  │ …                                       │
  └─────────────────────────────────────────┘

  ┌─────────────────────────────────────────┐
  │ + Add a change with age                 │
  └─────────────────────────────────────────┘
  Accounts available only from a later age, such as a pension fund, keep their own mix until then.
  ```

  - **Rebalance to: today's mix or a mix I choose.** *Today's mix* writes nothing (no `targetMix`): the money you can draw is rebalanced back to its own mix today, crypto included; the section's footer says so, with how that mix grows. *A mix I choose* starts from today's mix of the money you can draw in whole percentages, to edit; going back to *Today's mix* removes the mix and its changes with age.
  - **Per asset class** (equity, bonds, cash, gold, crypto, real estate, and any other class held today or named in the plan), a row of the *Target mix* section (*Today's mix* with today's mix): its name, with two lines under it: *Today*, its share of the money you can draw and of all the money in the plan ("Today 46% · 44% of all"), and its median real return from the assumptions ("Median 5.0% a year"), so what a class like crypto does to the mix is in view. With *A mix I choose*, the row ends with its target, a percentage typed as you go (an empty field or 0 leaves the class out). The fields have one width in every section, growing with the text size, so they line up. The footer says what *Today* counts.
  - **The total** is the section's last row: "✓ Total 100%", or an error line until it is ("Total 95%. Adds up to 95%: add 5% to reach 100%."); a plan saved short of 100% runs scaled, with a warning on the *Assumptions…* card. The footer has the mix's median growth, rebalanced every year, against today's mix's. A plan with changes with age but no mix from today says instead that each account keeps its own mix until the first change.
  - **Changes with age.** A section per change, after the target mix: its title as the header ("From retirement", "From 75") with a button that removes it; then *At an age* (a stepper kept after today's age and between the changes before and after it) or *At retirement* ("The year you stop working, whatever age the plan finds"), its own percentages and total, and its growth in the footer. *Add a change with age*, in a section of its own, adds one from retirement first, then ten years after the last, starting from the mix before it; its footer gives an example while there are none, and says that accounts available only from a later age keep their own mix. A change whose age has passed says "You're 56: this already applies from the start." with **Make it the target mix**, which makes it the target from today so every version reads the plan the same.
  - **VoiceOver** reads each class as its name, today's shares in words ("Equity today: 46% of the money you can draw, 44% of all the money in the plan"), its median ("Equity median return 5.0% a year") and its target field ("Equity target, percent"); each change's title is a heading, and its fields read as "Equity, From 75, percent".
  - **The *Assumptions…* card** shows the mix in words, the target ("Rebalance to") and a line per change ("From 75" with "Equity 40% · bonds 60%"), with *Edit Target Mix…*, which opens the sheet. Issues about the target mix (a total, ages that don't go up, a change after the plan's end) show on this card; the summary reads "Today's mix", or "Equity 80% · bonds 20% · changes at retirement and 75".
- **Simulation.** The number of runs, the confidence a "yes" needs, and the random seed.
- **Validation.** Issues appear on the row of the work phase, pension, contribution or event they're about, on the *Assumptions…* card they concern, and the rest (spending's, and those about a whole list) above the chapters:
  - ⚠︎ for warnings, e.g. "State pension starts after the plan's end age, so the plan never pays it.";
  - ⛔︎ for errors that stop the plan from running, e.g. "Employee: enter the income after tax for this phase (netIncome)."

### Export Calculations

When an answer looks wrong ("I need 2 million to withdraw 20,000 a year?"), *Export Calculations…* in the plan picker's menu (iPhone, iPad and Mac) and in the Mac's Plan menu writes every calculation behind it as Markdown ([PLANNER.md](PLANNER.md#calculations)), for the plan on screen (with the levers where they are, once one has moved), to check it or give to someone else. It's a small sheet:

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

A page in the sidebar on the Mac and iPad, a sheet on iPhone, with its steps along the top, as described in [IMPORT.md](IMPORT.md):

- **Mac and iPad:** the title is "Import", and the Mac window's subtitle says what's open ("3 statements", or the file's name). The steps are a capsule in the middle of the toolbar: each step's number in a circle and its name, the current one on a raised white chip, a done one with a check. Done isn't one of them. *Add Files…* is at the toolbar's trailing edge on the first step. A bar at the bottom says why Continue waits, at its leading edge in the warning color with a warning sign ("Choose the account of export (3).csv to continue."); then *Cancel* on the first step, which starts over (a sheet closes), or *Back* on the others, and *Continue* (*Import* on Review). On Income it says how lines count until they're answered. Done has neither the steps nor the bar.
- **iPhone:** the navigation bar has *Cancel* on the first step (*‹ Files* back to the step before on the others), "Step 1 of 3" and *Next*, which is dimmed while the step waits; under it the step's name as a large title. Review imports with a button across the bottom.

1. **File.** A drop zone, or the result of dragging a file onto the app. Bank statements are listed as in *Files* below.
2. **Format.** The detected settings, each a picker with a live sample: encoding, delimiter, header row, decimal and thousands separators, date format, and whether empty cells are skipped.
3. **Columns.** A table: the column header, sample values, *Imports as* (Balance of…, Quantity of…, Price of…, Ignore), and a per-column format override. The layout: a row per date, per record, per trade, or a bank statement.
4. **Accounts.** Names in the file matched to accounts (existing, new, or ignored), plus proposed closings, which are off until you turn them on.
5. **Preview.** The parsed grid with errors highlighted, counts (new, updated, identical, conflicting), and the conflict policy.
6. **Done.** A summary, **Undo import**, and **Save as profile**. When the import created instruments that have no price source (a broker's export gives an ISIN and a ticker, never a source), a **Price sources** section lists them with **Find Price Sources…**: a sheet searches Yahoo Finance for each one in turn by its ISIN, else its ticker, else its name, and chooses the first listing in its currency, as *Find…* in the instrument editor does ([Accounts](#accounts)). Each can take another listing, none, or another search; *Save* sets the chosen ones in one edit. When the import's positions are valued on dates without a price, a **Past prices** section lists them ("12 past values have no price for XAU") with **Fill In Past Prices…** ([Adding history](#adding-history)). Then the answer after an import, below.

**After an import.** Done (a section, or a card on bank statements' page) offers what an import changes about the answer, unless the import was opened from a check-in, which records the answer itself:

- **Your round amounts.** While first launch's starting estimates are open and the import brought in real accounts that can stand for them (current and savings accounts for cash, investment accounts for investments, pension funds and TFR for the pension, property for the home, a mortgage for the mortgage; `Library.accountsReplacing(_:)`), each is listed, ticked, with what replaces it ("Replaced by Conto Fineco and Directa"). *Replace Estimates* replaces the ticked ones in one edit with a backup labeled `replace-estimates`: an estimate is closed the day before the real values start, with the first of them as its successor so charts continue, or removed when the real values reach back to its day (`Library.replacement(of:)`). Then the main plan runs, and *Undo Import* is no longer offered: undoing would leave the replacement behind, and both edits have backups in *Sync & backups*.
- **Your answer.** The first import into a library with a main plan and no recorded answer runs the plan on its own, as the tour does, unless estimates wait to be replaced. Either way the run records the answer for the latest check-in date and shows it here, with its progress, then as "Your last Monday at work could be 14 May 2052" over "At 58, in 9 of 10 futures.", with how it moved from the first sketch ("2 years sooner than your first sketch."), and *Open Plan*.

A broker's transactions (Directa's or Fineco's movements, Degiro's or IBKR's exports) are recognised when the file is read and imported as trades, *A row per trade* ([IMPORT.md](IMPORT.md#broker-transactions)):

- **Format**'s note on empty cells says what they do to trades: each row is still a trade, recorded without the value; read as zero, an amount (net or gross) is 0, and a quantity, price, fee, tax or ratio is still left out, since 0 is no value for them.
- **Columns** offers the trade's fields (Date, Trade type, Instrument, Quantity, Price, Currency, Amount (net), Gross amount, Fees, Tax, Split ratio, Note) and *Account of every row* when the file has no account column. An amount column's format says how its signs are read.
- **Types**, between Columns and Accounts: each word the file uses for a transaction ("Acquisto", "Ritenuta su dividendo", "Giroconto") with its number of rows, where its type comes from (the usual word, set by you or the profile), and a picker of trade types, or *Leave out*. A word the importer doesn't know shows a warning and its rows are left out until you choose; nothing is guessed. Below, how amounts are signed (automatic, without signs: from the type, signed: as written) and notes on how the file's signs were read.
- **Accounts** proposes making an account record trades when the file has trades for one that doesn't, with what that changes. It's off until you turn it on; while off, its trades are left out. Or choose another account.
- **Preview** shows the trades like other records ("Directa, buy, 12 Jan 2026 · Buy 15 VWCE at 102,30 · −1.539,50 € · fees 5 €"), with how many of the records are trades; **Done** counts them, names the accounts now recording trades, and has **Undo import** as always.

A bank's statement of a current or savings account is recognized when the file is read and imported as the account's money in and out, *A bank statement* ([IMPORT.md](IMPORT.md#bank-statements)). Every statement opens as a list of files, one or many, so more can be added. Its steps are Files, Income and Review, then Done, with Accounts between Income and Review only when the import proposes opening the account earlier or closing it, other than a sale answered on Income:

- **Files** lists the statements, the same for one file or many:
  - **Mac and iPad:** "Your statements", under it what it's for ("Every account's CSV at once: a month's or ten years' worth. Each file's account is found for you."), and at the right *These files are* with *Bank Statements | Brokerage Transactions*. Then a table, a line per file: *File* (an icon, the name, and under it the bank and the lines read, "DKB · 311 lines", or "Bank not known · 58 lines"), *Covers* (the months it's read as covering, "Jan – Dec 2025", or its days when it starts or ends on a day of its own), *Balance* ("Adds up" with a check, "Doesn't add up on 3 days" in the warning color, or "No balance column") and *Account* (a menu of the cash and savings accounts that don't record trades, and under it how it was found: "Its balance follows on from 31 Dec 2024", "Remembered from last time" or "Named in the file"). A file nothing recognized is tinted, its menu reads *Choose…* in an orange ring, and under it "Which account is this a statement of?" in the warning color. Files that can't be read are lines with why. Under the table, a zone to drop more statements; dropping or *Add Files…* adds them to those listed, which keep their accounts and answers. Then *Between these files*, with two files or more: how many transfers were found in both files and paired, with *Show* listing each one's day, accounts and amount; and "No gaps or overlaps: each file's closing balance is the next one's opening balance.", or the days an account's files leave out or cover twice, in the warning color.
  - **iPhone:** *Bank Statements | Brokerage* across the width, then "3 statements": each file's name with its account, or *Choose Account ›* in the warning color, a menu of the accounts; under it what it covers and how its account was found ("Jan – Sep 2025 · remembered from last time"), or for a bank that isn't known "bank not known · 58 lines" and *How It's Read…*. Under them "Which account is export (3).csv a statement of?" while one waits, a row *Add Files…*, and *Between these files* in short: "14 transfers paired", "No gaps or overlaps".
  - A file's bank is the name of the saved profile it's read with, up to its first comma ("Fineco, movimenti" is Fineco), else its account's institution; otherwise it isn't known.
  - Each file has a menu (right-click or ⋯ on the Mac, a long press on iPhone, where a swipe removes it too): *How It's Read…*, *Days…*, and *Remove*. *Days…* opens a sheet with the days the file is read as covering, whole months by default: *Starts on a day of its own* and *Ends on a day of its own* give the first and last day of a file that covers part of a month; the last can't be after today. *Cancel* puts them back.
  - No later step opens until every file has its account, and Continue says which file waits.
  - *Brokerage Transactions* reads a broker's transactions instead, one file at a time: the file on screen alone, with the others given in a menu to read next; *Bank Statements* reads every file given as statements again.
- **How It's Read** is a sheet for one file, large enough for the file's columns (a page-sized sheet on the iPad, at least 900 by 640 points on the Mac): "How export (3).csv is read", and for a bank it doesn't know "The bank isn't one it knows. Say what each column holds; the next statement from this bank is read the same way." Three menus in a row, each shown by an example: *Dates* (31 December 2025 in each pattern, "31.12.2025"), *Numbers* ("1.234,56", "1,234.56", "1 234,56", "1'234.56", "1234,56", "1234.56") and *Columns split by* ("Semicolon", "Comma", "Tab", "Bar"); the first reads the file as detected. A guess still to confirm has an orange ring, and choosing one of its readings confirms it. *More Options…* has the rest: encoding, the header row, rows left out, separators and date formats one by one, month-only dates and empty cells. Below, the file's first rows as written, a column per file column, each headed by the file's heading and a menu of what it holds (Date, Amount (+ in, − out), Money in, Money out, Description, Counterparty, Balance, Ignore), in the accent color, gray while ignored; amounts are right-aligned. A line under it says what was read ("All 58 lines read. With no balance column, the balance follows on from Girokonto's last check-in.", or how many lines can't be read, in the warning color). Changes show at once; *Cancel* puts the file back as it was when the sheet opened, *Use* keeps them.
- **Income** shows every statement's lines on one page, however many files are open, and asks only about large lines: the rest is spending unless a rule, a trade or an account's name says it was moved between your accounts. On the Mac and iPad it's titled "What came in, and what went out?", with the lists on the left and the summary as a card on the right; the toolbar's *All 412 Lines…* opens All Lines. The bottom bar says "Until a line is answered, money in lowers what you spent, and money out counts as spent." On iPhone the summary is three figures on top, *Found for you* takes the place of the moved and income lists, and *All 412 Lines* pushes All Lines.
  - **The summary** ("2025 · 3 accounts": the years the files cover, and their accounts): *Came in*, *Tax, paid and set aside*, *Came in after tax* in large type, *Spent*, *Saved* and the *Savings rate* with a bar, worked out as Today's *This year* works out the savings rate ([PROGRESS.md](PROGRESS.md#money-in-and-out)) over the days the files cover, from the library as importing them would leave it. Saved comes from the balances, so answers move only what came in, the tax and what was spent. On iPhone: *After tax*, *Spent*, and *Saved* as the rate.
  - **Needs an answer · 1 of 3 left:** lines larger than a month's spending, or money in larger than a regular payer's usual amount, that nothing classified, largest first. An answered line stays in the list with its answer (`StatementLine.wasAsked`); the header counts those left, in the warning color, and reads "Answered · 3 lines" once none is. Each row has the sender and the amount, the description, the day and the account ("4 Mar 2025 · Conto Fineco") and what it was answered: "to a new account, Car", "to Tax pot", "the sale of Home", or for tax "paid straight from the account"; an answer the import can't record says why in the warning color ("not recorded: the file doesn't cover the value it counts in", for money moved into a tax pot outside the file's values). A move, a purchase or a sale is a link that opens its sheet again; on iPhone the whole row does. The answers, *Income*, *Spending*, *One-off*, *Tax* and *Moved…*, are a segmented control beside the line on the Mac and below it on iPhone, showing the answer chosen, and ringed in the warning color while the line waits. Until it's answered, a line counts as spending.
  - **Moved between your accounts**, a row per group with why, the amount and a link to its lines in All Lines: each rule's moves ("Steuer-Rücklage · to Tax pot · 9 lines", "your rule · counts as tax", *Change…*), the transfers paired between the files ("14 transfers · between these files", "paired by amount and day", *Show…*), the money that passed through each account, the same amount in and out within 4 days ([IMPORT.md](IMPORT.md#bank-statements)) ("2 lines · passed through Girokonto", "same amount in and out, 2 days apart", *Show…*), and lines moved one by one in All Lines. Lines answered in Needs an answer stay there.
  - **Income · 3 senders:** each sender whose money in is income and wasn't asked about, from every file, with how many payments and why ("12 payments · every month", "4 payments · your rule"), the total, and *Change…*, which opens All Lines with the sender's income.
  - **Found for you** (iPhone): the income and its senders, each rule's moves ("Moved to Tax pot · your rule"), and the rest of the money moved between your accounts, in whole amounts.
  - **Moved to or From**, the sheet *Moved…* opens, starts with the line's answer, if it has one: the line (sender, amount, day and account), "Money moved to something you own isn't spent. Which account did it go to?" (or, for money in, "…come from?"), then *Your accounts*, tax pots first, each with what it is ("counts as tax", "savings", "brokerage") ([IMPORT.md](IMPORT.md#moved-to-or-from-an-account)). For money in, *Sold* lists the accounts that could have been sold (open, valued by its balance, not cash, savings or a debt, in the statement's currency, with no values after the line; or the one this line sold when the file was imported before), and the new accounts a purchase on or before the line's day starts, in any of the files. For money out, *A New Account* is a purchase you keep, with its *Name*, *Kind* (*Belongings*, *Property* or *Other*) and what it's *Worth on* the line's day, what was paid. With one of your accounts picked, *Every line with “…”* makes a rule with the line's sender in every statement, so next month's lines move too. *Done* saves the answer.
  - **All Lines** lists every line of every file, newest first, to change any of them; on the Mac and iPad a sheet ("412 lines in 3 statements · change any of them") with a search of descriptions and senders, *Show* (All, Income, Spending, One-off, Tax, Moved) and *All Accounts* or one, and a table: *Date*, *Account*, *Description*, the *Amount* signed without a currency, *What it is* and *Why*. *What it is* is the class, or where the money moved ("Moved to Conto deposito", "Moved to Tax pot", "Sold: Home"); its menu, also the line's context menu, has *Income*, *Spending*, *One-off*, *Tax*, *Moved to or from* (your accounts, an account sold, *A New Account…* for money out, *Choose…* for the sheet), *Interest* and *Left Out* for the line alone, then *Every “Kleinanzeigen” Line…*, and *Undo This Line's Answer* or *Undo This Line's Choice* on a line answered or changed alone. *Why* is a few words: "pays every month", "chosen for this line", "paid them before", "by its sign", "the usual words", "your rule “Studio Verdi”", "a trade of Directa", "names Directa", "paired by amount and day", "same amount in and out, 2 days apart". The footer says "A change here applies to this line only. “Every … Line” makes a rule, kept for the next statement." On iPhone, All Lines is pushed: the lines by month, a search, chips for *Show*, and the account in the toolbar; each line says its day, what it is and why ("26 Sep · Income · pays every month"). Tap a line for the same answers as Needs an answer and *Every “…” Line…*; swipe it for *Left Out* or *Interest*.
  - **Every “…” Line**, the rule sheet: the words a line's text must have (starting from its sender, the merchant for a payment processor's line), what every such line is (a class, or *Moved to or from* one of your accounts) and how many lines of the statements it takes. Saving makes the rule in every statement's profile, so each file's next statement follows; *Remove Rule* takes away a rule with those words.
- **Review** checks every statement together before anything is written, under "Does this look right?" and what importing does ("26 months for 3 accounts, Jan 2025 to Feb 2027. Nothing is saved until you import."):
  - What stops the import comes first, when something does: the library's banners, what's in the way, formats to confirm, and a card per file that needs the balance before its first line, with its field (kept once a balance is given, so a mistyped one can be corrected).
  - **Came in and spent, 2026:** a pair of bars for each month of the import's last year, from January, as So far will count them with the files imported: what came in in the accent, what was spent in grey, the month not over yet lighter. No amounts on the axis.
  - **Conto Fineco, balance** (not on the iPhone): one account's balance through the year by the files as a line, and its values before the import as rings, *From the file* and *Your check-ins*: ink where the files give the same balance that day, orange where they don't. The account is the first whose values the files disagree with, else the first.
  - **A banner for each value the files disagree with:** "Conto Fineco, 31 Mar 2026: the file says 12.480,20 €, your check-in says 12.515,25 €", how much higher or lower yours is, and whether every other month agrees, with *Use the File's | Keep Mine*. Past three, the rest fold into "And 4 more values differ." with *Show All*, *Use the File's for All* and *Keep Mine for All*. On the iPhone, the title over "The file says … Your check-in says …", and the choice below.
  - **The accounts:** each account the import changes, with *New* when the import creates it or gives it its first values, its months ("21 · 1 kept as yours · from transfers"), its balance on the files' last day, and its change since the year began. On the iPhone, the balance over the change.
  - **The bar:** *Remember these banks and senders for next time* (on by default; "Remember banks and senders" on the iPhone), *Back* and *Import*. With it on, the import saves each file's profile with every file's rules and the classes chosen for single lines, as one undo with it ([IMPORT.md](IMPORT.md#remembering-banks-and-senders)).
- **Done** is a page of its own, with no steps along the top and no bar: a check, "Imported 26 months for 3 accounts", what was saved this year with the import ("In 2026 so far you saved 12.300 € of the 41.350 € that came in after tax: a savings rate of 30%."), the answer after an import (above), and **Remembered for next time**: how each new bank's statements are read ("How export (3).csv is read", for its bank's next statement), each new rule ("Notaio Bianchi is a one-off", for every account; "Steuer-Rücklage moves to Tax pot", every month) and each line answered ("Notaio Bianchi was a one-off", Mar 2025). Then *Undo Import*, which asks first and goes back to Review with the files as they were, *Open So Far*, which opens So far, and *Done*, which closes a sheet and starts a new import on the page. On the iPhone, a wide *Done* over the other two. Undone with later changes kept, it says what stayed.

Several bank statements chosen or dropped at once, of one account or many, import together ([IMPORT.md](IMPORT.md#several-statements-at-once)), with the same steps:

- **Files** lists them as above, in the order they're imported, then those waiting for their account.
- **Income** shows every statement's lines together, each with its account, and makes a rule in every statement's profile. **Review** shows them all together, and Import waits while two files cover the same days or another file needs a format confirmed or its balance before the first line.
- **Accounts**, when a file proposes opening an account earlier or closing one, shows one statement at a time too, opening on the first that proposes one.
- **Done** says "Imported 13 months for 2 accounts", with *Undo Import* for them all. Each file's profile is saved with the import when *Remember these banks and senders* is on.

The iPhone takes the same steps as the Mac, for every kind of file: a file a saved profile fits exactly is read with it, and Continue goes through the steps to Review.

## Settings

| Section | Contents |
| --- | --- |
| Library | Location (iCloud Drive or this device), Show in Files/Finder, for a library on this device *Move to iCloud Drive* (refused when iCloud Drive already has one) and *Use the iCloud Drive Library* (opens that one; this one stays on the device), sync status, merged conflicts, the newest 20 backups (*Show All N Backups* lists the rest; each with *Restore…*: after a confirmation that says how many files go back and to which day, the files as they are now are copied to a `restore` backup, then the backup's files are put back as they were, over any later changes, and the files it didn't have are deleted; a backup with a copy of an unreadable `library.json` can be restored while the library is read-only, which fixes it), the file format docs, and *Export as CSV…*: a sheet that writes the library as CSV files ([schema/README.md](schema/README.md#csv-export)), zipped as *Last Monday CSV 2026-09-30.zip*, with *Share…* and on the Mac *Save…* |
| You | Name, birth date, base currency, country (it picks the default inflation index), and **Inflation**: *Automatic: Italy* (the tax residence's index, else the base currency's; `inflationIndex` left out) or a choice of the euro area and every country with an index: an HICP, or the United States' and the United Kingdom's CPI |
| Prices | Price source per instrument kind: *Yahoo Finance (unofficial)* (so named wherever a price source is chosen or shown with an instrument; the footer says it has no official interface for apps and may stop working), also for crypto, gold-api.com, ECB via Frankfurter, and for inflation *Eurostat HICP, BLS (US), ONS (UK)*; fetch on check-in |
| Notifications | A screen of its own, with its summary ("Monthly and yearly", "Monthly", "Yearly", "Off"): see [Notifications](#notifications). |
| Privacy | Hide amounts, hide amounts when the app opens, and (iPhone and iPad) cover the app in the app switcher: the whole screen is covered while the app isn't active. The footer says only that. A Face ID lock is planned (M3), not built. |
| Plus | Whether you have [Plus](#plus) and until when ("Lifetime", "Yearly, renews 3 Oct 2027", "Free month, until 3 Nov 2026", "Yearly, renewal pending", "Not yet"; the dates are hidden in feedback screenshots), *Get Plus…* (the paywall) without it, and *Restore Purchases*. |
| Test profiles | Debug and TestFlight builds only, after tapping the version seven times, and while a profile is open: *Your library* and each test profile, the one open ticked (tapping one opens it), *New Profile…* (a name, then it opens at first launch), *Start “name” Over…* for the profile that's open (after a confirmation, its library and settings are deleted and it opens at first launch), *Delete* in a profile's context menu, and *Hide This Section*. A profile's library is on this device only, never in iCloud Drive, and its settings are its own; the widgets and notes stay the real library's. While one is open, a strip over the window says "Test profile “name”" with *Leave*. See [App/README.md](../App/README.md#test-profiles). |
| About | The version and the library's format, and under them: "Results are estimates from a simplified model with the returns, taxes and pensions you enter. Plans take your income and pensions after tax, and tax your investments at the rates you set. They aren't financial, tax or legal advice: check important decisions with a professional." |

## Plus

The app is a free download with a paid tier, Plus, bought in the app with StoreKit 2.

- **Free:** tracking, check-ins, import, widgets, and one plan with its answer, and So far (each year against the yearly baselines check-ins save).
- **Plus:** more plans (*New Plan* and *Duplicate* when there's a plan already, and *Save as a New Plan…*), the levers, and *Export Calculations…*. Without Plus the levers rest at the plan's values, with *Move the Levers…*.
- **Products:** *Yearly*, an auto-renewing subscription (about 35 EUR/USD) with the first month free for new subscribers, and *Lifetime*, a one-time purchase (about 100 EUR/USD). The trial is a month because the app's rhythm is the monthly check-in: a month lets you see Plus work once before you pay. The prices are the App Store's, in your storefront's currency.
- **The paywall** opens only from an action that needs Plus, or from Settings' *Get Plus…*; never at first launch or during the tour. Its title names what was asked for ("The levers come with Plus"), then what's free, what Plus adds (a line each), *Yearly* ("First month free, then 34,99 € a year", or "34,99 € a year" once you've had the month, asked again each time it opens) and *Lifetime* ("99,99 € once"), that the subscription renews until cancelled and that your plans and files stay yours either way, and *Restore Purchases*. *Not Now* closes it. Once Plus is bought, restored or approved, it closes and what was asked for goes on (the levers move, the plan is made).
- **Who has Plus** is one answer (`PlusStore`, from `Transaction.currentEntitlements`): the lifetime purchase, or the yearly subscription, its free month included, for as long as the App Store lists it. That includes a Billing Grace Period, while the App Store retries a renewal after the period has ended; Settings then says "Yearly, renewal pending". A refund ends it. Screens never ask StoreKit themselves.
- **When Plus ends,** every plan and file made with it stays: plans can still be opened, edited and calculated. Only Plus's actions open the paywall again.
- **Files stay free.** Nothing in the library's files depends on Plus, and the CLI has every feature.

## Notifications

Notes that remind you of your goal and the way there, never of the app: a few a month at most, local notifications on this device only (so you aren't told twice), worked out by `NotePlanner` (Glance) from the widgets' snapshot. They're scheduled again at launch, after a check-in or a new answer, and when the settings change. A note never shows an amount: ages, years, months and percentages only, and a milestone that is a round amount is named by what it is.

**Settings › Notifications.**

| Section | Contents |
| --- | --- |
| Each month | *Monthly note*, its *Day* (*Last day of the month*, the default; 1 to 6 days before the last; or day 1 to 21. A check-in in a month's last 7 days is for that month, and one before them for the month before, so later days count back from the month's end and a note never skips a month. A day saved past 21 counts back from the last of a 30-day month, at most 6 days) and *Time* (19:00). "When your check-in is due: where you stood at the last one, what's next, and the files to import." |
| Once a year | *Your year* ("Early January, your year in review"), *Birthday* ("How far your last Monday is"), *Records anniversary* ("How far you've come since you started"), *Plan check-up* ("A year after your plan last changed") |

The footer: "Notes show ages, years and percentages, never amounts. On this device only, so you aren't told twice." Turning a note on asks for permission first; when notifications aren't allowed, nothing turns on and the screen says "Notifications are off for this app. Turn them on in the system settings to get notes." Onboarding turns on the monthly note and *Your year*; Today offers the yearly ones once ([Today](#today), *Keep your goal in view*). First launch's *Keep it in view* step shows this month's note as it would come, with the answer in it, and turns on the monthly note and *Your year* when ticked (both are, at first).

**The notes.**

- **Monthly** (on the chosen day and time): "September check-in", "You could retire at 54, 2 years sooner than in January. 5 years of spending is 80% there. Import September's files to see where you stand." The age is compared with the year's first check-in, or with the one a year before when this is the year's first. The milestone sentence only when the next one is 80% there or more. Touched and held, it shows a picture: the age at the last 12 check-ins as a step line, and the next milestone when it's close. *Import Files* and *Open Today* are its actions; tapping it opens the check-in. Without an answer yet: "Import September's files, then calculate your plan to see when you could retire." The note asks for the month a check-in on its day is for: its own month in the month's last 7 days, else the month before, so with *Day* 5 the 5 November note is "October check-in", and none comes on a day when that month is done.
- **Catching up:** with 2 or 3 months owed, the monthly note asks for them together ("Catch up by importing August's, September's and October's files together."); from 4 months owed, one note a quarter, "The months since then import together, whenever it suits you." Never a growing pile of nags.
- **Your year** (3 January, 10:00): "Your 2026", "You could retire at 54, 2 years sooner than a year ago. You saved about 8 months of expenses and passed 3 milestones. See your year." It opens last year on [So far](#the-year). Before December's check-in: "Import December's files, then see how your 2026 went."
- **Birthday** (10:00, with a birth date): "42 today", "Your last Monday is about 15 years away: you could retire at 54, in March 2042, in 9 of 10 futures."
- **Records anniversary** (the first record's day, 10:00): "Five years of records", "Since October 2021 the age you could retire at went from 58 to 54, and you went from 21% to 58% of what retiring today needs."
- **Plan check-up** (a year after the main plan last changed, then each year, 10:00): "Base case, a year on", "Your plan last changed in October 2025. Do its pay, spending and retirement age still fit your life? A few minutes keeps the answer honest." It opens the plan.

At most one note a day: the monthly note keeps its day, and a yearly note that falls on it moves to the next free day. Notes are planned for the next 12 months.

## Design system

**Look.**

- System components and Liquid Glass on iOS 26 and macOS 26: a floating tab bar and toolbars, sheets with detents, and the sidebar.
- Glass is only for controls that float above content (the tab bar accessory, floating buttons). Content (numbers, charts, forms) sits on plain surfaces, where it's most legible.
- **Surfaces.** White cards on a light grey page (`#f2f2f7`), as the system's grouped lists draw them; black and `#1c1c1e` in dark mode. Cards have large corners (22 pt) and no border on iPhone and iPad, and smaller corners (12 pt) with a hairline edge on the Mac (`cardSurface()`). Everything on a screen sits on a card, a chart included; nothing floats on the page except the screen's title and its picker.
- **Rows before tiles.** Figures are rows on a card (`CardRows`, `CardRow`): the label on the left in ink, the value on the right in grey, a hairline between rows. No grids of figure tiles, except the tiles [Tiles](#tiles) lists. A card holds one idea; a screen has few cards.
- **One line.** A row's label and its value share a line when both fit in full; when they don't, the value goes under the label and both wrap, so neither is cut and a row never makes the page wider than the screen. A chip, a legend and a chart's labels stay on one line. Only sentences wrap, and a card keeps them to one or two.
- **Pages that give way.** Pages don't split into side columns: a wider page fits more tiles to a row ([Tiles](#tiles)), and a chart takes the page's width. Today's answer has net worth and what moved beside it, both tall, only when a row has four slots or six; the plan's levers go under the answer when both don't fit. A legend's items wrap onto more rows at their own widths (`FlowRows`).
- **Type.** The screen's title is a large title. The answer's date is the one hero: about 52 pt bold on iPhone, larger on the Mac. A card's title is a headline (17 pt semibold); rows are body text; secondary text is grey (`#55555e`), captions and axis labels lighter (`#8e8e96`). The accent is one blue (`#0a64d8`).

**Numbers.**

- The system font. Large standalone numbers use its default figures; columns that must line up (tables, axis labels) use tabular figures (`.monospacedDigit()`).
- Formatted for your locale and base currency: in Italian, `312.480 €`, with decimals only where they matter (account detail).
- **Quantities and unit prices** read the same everywhere (account holdings, the trades list, the instruments, the import's review; `QuantityFormat`): a quantity has up to 8 decimals, trailing zeros trimmed (`0,10383916 BTC`, `412,5 sh`); a unit price (or an average cost per unit) is money in its own currency, with the currency's symbol, 2 decimals from 1 up (`73.785,11 €`, `165,00 $`) and 4 significant digits below (`0,004312 €`). The import's preview shows prices as read from the file.
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
- **Everything else** is one hue (blue) with labels: allocation by account group, fan charts (the bands are lighter steps of blue).
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
- **A projection's value axis** fits the history and the median, its top about a tenth above the higher of them, and keeps the 25% line in view at the bottom. The bands may run off the top, cut at the chart's edge, and the legend says "↑ Bands continue above". No log scale.
- A value that couldn't be worked out (a price or exchange rate missing) is never drawn as zero: an account's line has a gap there, and a total that adds up what it could is drawn dashed and grey. A note under the chart says what's missing.
- Direct labels on the last point as well as the legend, where they don't collide.
- Every chart can be read by dragging across it (`chartXSelection`) and has a VoiceOver summary (`accessibilityChartDescriptor`); while amounts are hidden, neither it, its audio graph nor its marks read them. The callout stays inside the chart, never over what's above it.
- No dual axes. When two measures need comparing, they get two charts.

**Uncertainty** is always a band, never just the median. The words are "in 9 of 10 simulated futures", not "90% probability".

**Privacy.**

- An eye button hides every amount with SwiftUI's redaction. It's in the toolbar of Today, So far, Ahead, the accounts and an account's page; on iPhone, So far and Ahead have no toolbar, so it's beside their title. Each amount draws as a placeholder, a bar as wide as the amount, and names, dates and labels that aren't amounts stay readable. In a sentence only its amounts hide ("You saved ▬▬▬ and markets added ▬▬▬."), and VoiceOver reads "amount hidden" in their place. Amounts that are left out elsewhere show as placeholders too, so the layout doesn't move when the eye turns on. Quantities hide as amounts do; percentages don't, and the change since the last check-in shows in per cent. The fields you type into still show what you type.
- Charts keep their shape and a relative value axis: net worth (and an account's value) in multiples of today's (`0`, `1×`, `2×`), the money in the plan (Ahead's chart, the plan's fans) in multiples of today's money in the plan, retirement income in multiples of the spending. Those labels reveal no amount, so they're the one label left readable with the eye; every other label that would reveal an amount is a placeholder.
- It's the same redaction as the widgets' while the device is locked ([Widgets](#widgets)) and a feedback screenshot's: amounts are marked `.privacySensitive()`. A feedback screenshot (Debug builds) also hides the rest of the person's data: names, their records' dates, notes, the plan's ages and years, the words of sentences, and all of a chart's text; the app's own labels, headers, buttons and empty states stay readable.
- *Cover the app in the app switcher* (iPhone and iPad) covers the whole screen while the app isn't active.
- Optional Face ID lock (M3, not built yet).

**Accessibility.**

- Dynamic Type everywhere; the large date and net worth scale too, up to a cap.
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

**Empty states and first launch.** Every empty screen has one clear next step. First launch is a short tour, full screen from start to finish, that ends on an answer: a few rough questions, the main plan calculated in the tour, and only then files, as the way to sharpen it. *Back* and the primary button sit along the bottom; "Step 2 of 6", over a thin bar, sits at the top of every step after the welcome. Every question after your age can be left empty, and the app opens on a usable library either way:

1. **Welcome**: a blank calendar page, "When could your last Monday at work be?", and three lines with icons: *Your retirement age* (the earliest age, and how likely it is to work), *A monthly check-in* (import your statements to see how the answer changes), *Your data stays with you* (files in iCloud Drive or on the device, no account, no server). *Get Started*.
2. **About you**: your age ("The answer is an age, so the app needs yours."), a menu from 18 to 90 (below the plan's default end age, 95) that starts unset (none is made up), and *Continue* waits for it; the tour saves it as a birth date half a year past your last birthday, and "You can set your exact birth date later in Settings."; the country and currency, starting from the device's region, with what they set ("Totals in Euro, adjusted for inflation with Italy's prices."); and *Keep in iCloud Drive*, on when iCloud is available.
3. **Your money**: rough amounts of what you have today (cash and savings, investments, a pension you can't access yet with the age it's available from, and optionally the home's value, with the mortgage still owed on it once a value is entered; a mortgage without a home value is left out), and take-home pay and spending a month, with the saving worked out as you type ("You save about 1.200 € a month, a third of your pay."). *I've already stopped working* hides the pay: spending is then what you live on now. Each amount is a filled field with the currency inside it ("0 €"), so it reads as a place to type. A negative amount says "Amounts can't be negative." and keeps *See My Answer* off.
4. **Pension and retirement**: the state pension a month and from what age, empty for none (the more cautious plan); when to retire, *As early as possible* or *At a set age* (30 to 85), and spending in retirement a month, empty to spend what you spend now (its placeholder); neither once you've stopped working; and the tax on investment gains, prefilled for the country (`CountryDefaults`) and changeable, empty for none. A negative amount says "Amounts can't be negative." and keeps *See My Answer* off. *See My Answer* creates the library with the settings chosen, the starting amounts as estimates and the main plan, then shows the answer.
5. **The answer**: the main plan runs here, with its progress ("Calculating thousands of simulated futures…") under a blank calendar page, and records the first answer as a check-in does. Then "Your last Monday at work could be", the date as the screen's hero ("14 May 2052") and how sure, with that it's a sketch ("At 64, in 9 of 10 futures. It's a first sketch from the numbers you gave; adding your accounts makes it exact."), or without a date "Your first answer" with "Yes." or "Not yet." and the answer in a sentence. Under it one card: a small fan of futures marked at the age, and one lever worked out already ("Saving 340 € more a month would make it 2050.", two quick runs of the plan as it is and saving more). A small *What the answer stands on* (ⓘ) explains what the fan's bands are, the estimates and replacing them. Once you've stopped working, the plan retires at your age today and the answer is whether your money lasts: "Yes." or "Not quite.", "Your money lasts to 95 in at least 9 of 10 futures." (or "in 7 of 10 futures. Your plan aims for 9 of 10."), and what you could spend ("Spending up to 2.300 € a month lasts in 9 of 10 futures."), with no lever. A plan that can't be calculated says why, and "You can continue: Today calculates your plan once it can." *Add Your Accounts* (*Continue* for a library that was already there) goes on. Once the answer is there, *Back* returns to the questions while the library holds only what the tour added (no files imported yet); *See My Answer* then replaces those estimates and the plan, and *Keep in iCloud Drive* can no longer change. A library already in iCloud Drive without a birth date asks for your age here, the same menu, and without amounts or a plan it says what's missing.
6. **Import your accounts**: which files work and where they come from (bank statements, broker exports), the starter spreadsheet for a home, pension and debts that have no export (*Save Starter Spreadsheet…*, a CSV with today's row and the home, mortgage and pension estimates' amounts, the mortgage's as owed), and on the iPhone and iPad that importing is easier on the Mac, where an iCloud library already is. *Import Files…* pushes the import on the tour's own stack; *Later* is a real choice.
7. **Reminders**: this month's note as it would come, with the answer in it, and the *Monthly note* and *Your year* toggles, both on ([Notifications](#notifications)); where to add the widget; and the disclaimer in a line, with *Read More* showing the whole text. *Start* turns on the notes ticked and opens Today.

On the Mac, and on the iPad in a regular width, the money and pension steps show an estimate beside them that moves as you type: a few hundred futures of the library and plan *See My Answer* would create, in memory, with how the age moved since the last change; once you've stopped working, whether your money lasts ("Your money lasts", "Your money runs short"), with no change line.

**Starting estimates.** Each amount you have today becomes an account of its own, named "(estimate)" and tagged `estimate` (`StarterSetup`): cash and savings as a savings account, investments as equity, the pension as a pension fund available from its age, the home as property and its mortgage as a debt, both left out of the plan, so net worth counts the home's equity and the answer doesn't. Each has one value on the day, written in one edit with a backup labeled `starting-estimates`, so they show and undo like an import's. Until it's closed, an estimate's value can be corrected by hand with *Update Value…* on its page, or *Update* in the check-in, whatever its kind ([Accounts](#accounts)). The plan, "Base case", retires at the age chosen, as early as works, or at your age today once you've stopped working, spends what was entered (in retirement too, unless that was entered on its own), has a work phase paying the pay until retirement, the state pension from its age, and the tax rate. A library that already has accounts or plans (synced from another device) keeps them and gets neither; outside the euro a plan needs spending entered. The first answer stands on the estimates, and its day saves no yearly baseline. After an import, Done offers to replace them ([Import](#import-mac-first)).

A tour left before *Start* (the app closed after *See My Answer*) isn't shown again: the library opens as usual.

**Haptics.** A light tap on save, and when a lever moves the earliest retirement age.

## Tiles

Today's glance, made to be used elsewhere too: tiles sized on the home screen's grid of icons, as widgets are, 2 × 2 (small) or 2 × 4 (wide), in rows (`TileGrid`): two small tiles to a row on iPhone in portrait, and four or six on a wider page, never three or five, so a wide tile or two stacked half tiles always line up with the rows around them, and a tile stays near its iPhone size (at least 160 points wide) instead of growing with the page; a page with room for three but not four (the smaller iPhones in landscape) keeps two wider slots. A row that isn't full leaves its last slots empty. A row is as tall as a small tile is wide, at most 176 points, so a wider slot (the iPad upright, where a row still has two) doesn't make tiles taller; or taller when larger type needs it. Every tile reads the same way: a heading that says what the figure is on its own, the figure, and a line under the figure (`TileCaption`) that says what it's of or when, never beside it, so neither is cut. A line that pairs two parts ("▲ +36.210 € in a year", "91% there" and "early 2029", a bar's name and its amount) puts the second under the first in a slot too narrow for both (`LineOrStack`), and a milestone's name wraps, so no text is cut short. A figure that says it all with a few words is a half tile (1 × 2, `HalfTile`): its heading, the figure and its line, two stacked in a small tile's slot. A full tile takes its whole row, as a chart does. A tile has the card's corners and a pastel tint (`TileTint`: butter, mint, lilac, peach, sky and pink, each with its own ink and accent, in light and dark), or the plain card. Text is in the tint's ink, secondary text a little lighter; bars and lines are in its accent, which reaches 3:1 on the tint. A tile's label leads with an emoji that says what it is: one per kind of milestone, 🎉 when one is passed, and one for each figure (📊 net worth, 🐷 the savings rate, 💰 what was saved, 📈 or 📉 markets, 💶 what came in, 🛒 what was spent, 🎯 how sure, 🏁 what's left, 🛍️ what you could spend, 🌱 interest). The net worth tile is on the plain card, its line in the sky tint's accent (it shows no projection, so it needn't be ink). A tile that opens something is a button to where its numbers are explained. Where they are:
- **Today:** net worth, the next milestone and the savings rate; net worth change this year, the next check-in and if you stopped saving now (half), what moved (wide); the milestones coming up. Where a row has four slots or six, net worth and what moved stand tall beside the answer and the rest go under it.
- **So far:** what you saved over what markets did (half) beside your money now (or at the year's end), small; the year's savings rate over its spending a month (half), and the earliest age to stop over the check-ins this year (half). *All Milestones* has the next milestone and saving nothing more wide, and a wide tile for each kind of milestone.
- **Ahead:** spending you can afford, if you stopped saving now and saving as much as last year (half), needed to retire today, money left at the end and taxes from now to the end (half), and the ages you could stop at across the row.
- **An account** (iPhone and iPad): what its latest value saved, and its interest.

## Widgets

The glance: how am I doing, without opening the app. On the home screen of the iPhone and iPad, the iPhone's lock screen, and the Mac's desktop and Notification Center. Tapping one opens the app where it belongs: *Last Monday* and *Net worth* on Today, *Check-in* on the check-in, *Next milestone* on the main plan.

| Widget | Sizes | What it shows |
| --- | --- | --- |
| **Last Monday** | small, medium; lock screen inline and rectangular | your last Monday at work, as the main plan works it out: "27 Mar 2051", with "At 63, a year sooner" when the age moved since the check-in before, else "At 63, in 9 of 10 futures" ("You could stop today" or "Not yet" when there's no date). The small one sits on the app icon's dusk; the medium one has the date in full ("27 March 2051"), the age and how sure, and how it moved ("A year sooner since September"). On the lock screen: "Last Monday 27 Mar 2051" in a line, or "Last Monday", the date, and the age with how it moved |
| **Net worth** | small, medium, large; lock screen rectangular and circular | the total today, as on Today, this year's change (or the change at the latest check-in), and the last 12 months' month ends as a line in ink. The medium one adds "Last Monday 27 Mar 2051 · at 63" ("Your last Monday at work appears here." before there's one); the large one is everything at once, with the last Monday and how it moved. On the lock screen, the changes in per cent |
| **Check-in** | small; lock screen circular | the days to the next check-in, with how much of the month has gone ("Check-in · 8 days to go · October, due 31 Oct"); once it's due, the month and "Start check-in". On the lock screen, "26 days", or "Due" with the month |
| **Next milestone** | small; lock screen rectangular | the main plan's next milestone ([Milestones](#milestones)): "400.000 €", its bar, "78% there", "Typically by mid 2027". On the lock screen without its amount: "A round amount" |

- **Where the numbers come from:** Today's. Net worth today, as of the day the app last wrote the snapshot ("Today", or "8 Oct" when it hasn't been opened since: nothing changes your values without the app), and the main plan's latest results, or else the answer recorded at the last check-in. Results calculated before the base currency changed aren't shown, as in the app. The widgets never open the library or run the plan: the app writes a small snapshot of what they show into an App Group whenever the library or the answer changes, and they draw it. What depends on the day, like the days to the check-in, is worked out each day from its dates.
- *Last Monday* keeps the kind of the countdown widget it took the place of, so a widget already placed becomes it.
- **Locked:** amounts draw as placeholders and changes show in per cent, as with the eye button; bars and lines keep their shape. Lock screen widgets never show amounts.
- **Empty states** say what's missing in a sentence: open the app ("Open the app to see your answer"), the first check-in, the plan's answer.
- **Tone:** as in the app. The date comes with how sure it is, or with how it moved; an earliest age that moved sooner is green, one that moved later is said plainly, in grey.
- The widget gallery shows made-up numbers, never yours.

## How it's built

- **State.** `@Observable` stores, created once and injected through the environment:

  | Store | Holds |
  | --- | --- |
  | `LibraryStore` | the in-memory library, edits, how far opening it has come, sync status, merged conflicts |
  | `PlanStore` | runs, their progress, results and what they were calculated from (up to date or not), headlines and baselines |
  | `CheckInStore` | the open check-in: its date and the prices fetched for it |
  | `PriceStore` | price fetching (wraps `PriceService`) |
  | `AppPreferences`, `AppNavigation` | this device's settings and hidden amounts, where you are in the app |

  An import in progress belongs to the Import screen.
- **Navigation.** One root view chooses between `TabView` (compact width) and `NavigationSplitView` (regular width and Mac). The screens themselves don't know which one they're in.
- **Mac layouts.** A Mac window can't be smaller than the minimum size of its content, so every page's content scrolls, and what's pinned to a page scrolls when there's no room (`OverflowScrollView`). The window's minimum is a fixed size rather than measured through the content (`FixedMinimumSize`). Tables on a scrolling page are as tall as their rows (`PageTable`, also on iPad for the plan debugger), so the page scrolls them; a `Table` is used only as a whole page (Instruments, the import's columns). [App/README.md](../App/README.md#design-system) has the details.
- **Folders.** `App/Sources/` holds `App`, `Stores`, `Navigation`, `DesignSystem` (colours, number formats, spacing, amount text, cards), `Components/Charts`, `Features/<Feature>` (Today, SoFar, Accounts, CheckIn, Plan, Import, Settings, Onboarding, Library, Journey) and `Preview`. [App/README.md](../App/README.md) describes them and the stores' APIs.
- **Chart components**, reused everywhere: `NetWorthChart`, `FanChart`, `IncomeStackChart`, `WaterfallChart` (a headline and change bars), `BreakdownBars`, `Sparkline`. Their values, value scale and time span are Tracker's, tested on Linux; the layout in points (ticks, marker labels) is worked out in the app without SwiftUI.
- **The strips.** So far's years are one strip (`PlanCardStrip`): it scrolls, chooses a card and scrolls it into view, fits the money scale to the money between the screen's edges (Planner's `PlanStripScale`), and follows the pointer or a held finger for the read-out. The strip says where its cards are and what part of it is on screen (`PlanStripWindow`); Planner's `StripFit` treats the cards' lines as one graph and picks their values there, interpolated where the screen's edges cut them, falling back to the whole lines of the cards on screen when none has a point between the edges. The cards place their graphs alike (`PlanStripPlot`) and label their gridlines alike.
- **Previews.** Every screen has SwiftUI previews built from the made-up example library of the tests, which the app bundles.
