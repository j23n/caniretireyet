# Overview header: four directions

A design note for the top of the Overview, above the history chart ([UI.md](../UI.md#overview), "The answer", "Hero number", "Can I retire yet?"). It proposes four directions to choose from. Nothing here is built yet. The chosen direction is built in a follow-up, which also updates UI.md's "Overview" section.

The history chart and everything below it stay as they are in every direction. The answer's card below the chart, shown before there's an answer, stays too. All values are made up, from UI.md's wireframes.

## Today

When the main plan has an answer, the header stacks the answer, its details and net worth. Here it is with every piece showing, with results out of date:

```
┌──────────────────────────────────────────┐
│ Overview                        👁   ⚙︎   │
│                                          │
│ Can I retire yet?                      › │  ← subheadline
│ Not yet · earliest                       │  ← largeTitle: may wrap on an iPhone
│ at 54                                    │
│ About 15 years to go · March 2042        │  ← body
│ The first age that works in 9 of 10      │  ← footnote
│ simulated futures                        │
│ ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇░░░░░░░░░░░░░░░░░ │
│ 58% of what you'd need to retire today ⓘ │  ← footnote
│ On plan · 12.400 € ahead of your Jan     │  ← subheadline
│ baseline                                 │
│ Calculated before your latest changes    │  ← caption
│ [Calculate]                              │
│ Estimates, not financial or tax advice.  │  ← caption
│                                          │
│ Net worth                                │  ← subheadline
│ 312.480 €                                │  ← title
│ ▲ 4.210 € in September    ▲ 6,2% this yr │  ← subheadline
│                                          │
│ 3Y ▾                            Future ◯ │  ← the chart starts here
└──────────────────────────────────────────┘
```

What makes it heavy:

- **Too many sentences.** The answer is followed by five more lines of prose (the time to go, the confidence, the readiness, the baseline, the run status) before the disclaimer. Each one is useful, but they all have about the same weight.
- **Six text styles** (largeTitle, title, body, subheadline, footnote, caption), with little difference between the smaller ones.
- **Two heroes.** Net worth, in title, competes with the answer for the eye.
- **Readiness and the baseline** are two separate sentences, although both say how far along you are.
- **The run status and the disclaimer** come between the answer and net worth, in the same column as the rest.

On an iPhone at a larger text size, the chart starts about two-thirds of the way down the first screen.

### Inventory

These are the pieces each direction keeps, moves or drops:

| # | Piece | Today |
| --- | --- | --- |
| 1 | "Can I retire yet?" and the chevron | label row |
| 2 | The answer: "Not yet · earliest at 54", "Yes", "Not yet" | largeTitle |
| 3 | Time to go: "About 15 years to go · March 2042" | body |
| 4 | Confidence: "The first age that works in 9 of 10 simulated futures" | footnote |
| 5 | Readiness: the bar, "58% of what you'd need to retire today" and its ⓘ | footnote |
| 6 | Baseline standing: "On plan · 12.400 € ahead of your Jan baseline" | subheadline |
| 7 | Run status: recorded at a check-in, calculating, out of date with *Calculate*, can't be calculated | caption |
| 8 | Disclaimer: "Estimates, not financial or tax advice." | caption |
| 9 | Net worth, its amount and its two changes (and the partial-total note) | title |

## Choices every direction shares

Two pieces can go in more than one place, independent of the layout. Each direction below picks one option, but any option works with any direction.

**Run status (7).** It's needed only when the answer isn't current.

- **R1, in the label row.** The status sits at the right of "Can I retire yet?", before the chevron: "◷ 30 Sep" for an answer recorded at a check-in (VoiceOver reads "As recorded at the check-in on 30 Sep 2026"), a small *Calculate* button when results are out of date, "Calculating 29%" while it runs. Out-of-date lines dim slightly, as the Plan screen dims out-of-date results. It adds no line.
- **R2, a row in the answer's card or tile.** The same words and button, as the card's last row, only when there's a status. It adds a line only when it's needed.

In both, "Base case can't be calculated: …" with *Try Again* and *Open Plan* keeps a line of its own under the answer, as today. It's rare and needs action.

**Disclaimer (8).** It's already on the welcome screen and at the end of the Plan screen, under the chapters.

- **D1, in the answer's ⓘ.** One ⓘ explains the whole answer: the readiness (today's text), what "9 of 10 futures" means, and the disclaimer at the end. The Overview keeps it one tap away.
- **D2, one caption under the header.** As today, but the header's only caption, after everything else.
- **D3, on the Plan screen only.** The Overview leaves it out; it stays on the Plan screen and in the welcome.

Whether the disclaimer must stay visible on the Overview (D2) is an open question for the owner, below.

## A. Trimmed

Today's order and hierarchy, with each piece said once and shorter. The answer is the only hero. Everything under it is one of two smaller styles.

```
┌──────────────────────────────────────────┐
│ Overview                        👁   ⚙︎   │
│                                          │
│ Can I retire yet?                    ⓘ › │  ← subheadline, secondary
│ Not yet                                  │  ← largeTitle
│ Earliest at 54 · March 2042              │  ← title3
│ About 15 years · in 9 of 10 futures      │  ← subheadline, secondary
│ ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇░░░░░░░░░░░░░░░░░ │
│ 58% of what retiring today needs         │  ← subheadline, secondary
│ On plan · 12.400 € ahead of January      │  ← subheadline
│                                          │
│ Net worth 312.480 €                      │  ← title3
│ ▲ 4.210 € in September  ▲ 6,2% this year │  ← subheadline
│                                          │
│ 3Y ▾                            Future ◯ │
└──────────────────────────────────────────┘
```

- **Keeps:** every piece but the disclaimer. The answer splits into "Not yet" (the hero) and "Earliest at 54 · March 2042"; the time to go and the confidence share a line. The baseline is named as Progress names it ("ahead of January").
- **Moves:** the readiness ⓘ to the label row, where it explains the whole answer and holds the disclaimer (D1). The run status to the label row (R1).
- **Drops:** "of your … baseline" and "simulated" from the wording; nothing else.
- **Type styles:** three (largeTitle, title3, subheadline), down from six. Net worth's amount is the same size as the earliest age: both are the second tier.

**Why.** It's the smallest change, and nothing a reader relies on goes missing. The header becomes a headline, two numbers and a few quiet lines. It still reads as text, though, just less of it.

### States

| State | What the header shows |
| --- | --- |
| Not yet, with an age | as above |
| Yes | "Yes" / "You could retire today" / "In at least 9 of 10 futures"; the bar is full and reads "130% of what retiring today needs" |
| No age works out | "Not yet" / "No age works in 9 of 10 futures yet"; the bar and the baseline as usual |
| Recorded at a check-in | the label row reads "Can I retire yet?  ◷ 30 Sep  ⓘ ›"; an answer recorded before readiness existed shows "Calculate the plan to see how close you are to retiring today." in the bar's place |
| Out of date | the label row reads "Can I retire yet?  [Calculate]  ⓘ ›"; the answer's lines dim; the ⓘ also says "Calculated before your latest changes" |
| Calculating | the label row reads "Can I retire yet?  Calculating 29%  ›" |
| No answer yet | net worth leads, as today: "Net worth", the amount in largeTitle, its changes. The answer's card stays below the chart |
| Hidden amounts | "Net worth •••••", the changes in per cent, "On plan · ••••• ahead of January" |
| Large text | the same lines, wrapped. The label row's status moves under the answer when it doesn't fit beside it |

```
Out of date                                  Calculating
┌──────────────────────────────────────────┐ ┌──────────────────────────────────────────┐
│ Can I retire yet?        [Calculate] ⓘ › │ │ Can I retire yet?      Calculating 29% › │
│ Not yet                       (dimmed)   │ │ Not yet                                  │
│ Earliest at 54 · March 2042   (dimmed)   │ │ Earliest at 54 · March 2042              │
│ ┆                                        │ │ ┆                                        │
```

### iPad and Mac

The content is up to 760 points wide, which has room for two columns: the answer on the left, net worth on the right, at the same height. The readiness and the baseline run under both.

```
┌────────────────────────────────────────────────────────────────┐
│ Can I retire yet?                  ⓘ ›   Net worth             │
│ Not yet                                  312.480 €             │
│ Earliest at 54 · March 2042              ▲ 4.210 € in September│
│ About 15 years · in 9 of 10 futures      ▲ 6,2% this year      │
│ ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ 58% of what retiring today needs                               │
│ On plan · 12.400 € ahead of January                            │
│                                                                │
│ 3Y · retirement +15 ▾                                 Future ◯ │
└────────────────────────────────────────────────────────────────┘
```

## B. Two tiles

The answer and net worth side by side, as two tiles, like the small *Time to retire* and *Net worth* widgets. Each tile has one big value, and the two read as equals.

```
┌──────────────────────────────────────────┐
│ Overview                        👁   ⚙︎   │
│                                          │
│ ╭────────────────────╮╭────────────────╮ │
│ │ Can I retire yet?  ││ Net worth      │ │  ← subheadline, secondary
│ │ Not yet            ││ 312.480 €      │ │  ← title
│ │ At 54 · Mar 2042   ││ ▲ 4.210 €      │ │  ← subheadline
│ │ in 9 of 10 futures ││ in September   │ │  ← subheadline, secondary
│ │ ▇▇▇▇▇▇▇▇▇░░░░░ 58% ││ ▲ 6,2% this yr │ │
│ ╰────────────────────╯╰────────────────╯ │
│ On plan · 12.400 € ahead of January    › │  ← subheadline
│ Estimates, not financial or tax advice.  │  ← caption
│                                          │
│ 3Y ▾                            Future ◯ │
└──────────────────────────────────────────┘
```

- **Keeps:** the answer, the earliest age and month, the confidence, the readiness as a bar and its percentage, the baseline, net worth and its changes, the disclaimer (D2).
- **Moves:** the readiness sentence and its ⓘ into the answer tile's ⓘ, opened from the tile's label (VoiceOver reads the sentence with the bar). The baseline becomes a row of its own under the tiles that opens Progress, as the Plan screen's "18.400 € ahead ›" does. The run status becomes a row in the answer tile (R2).
- **Drops:** the time to go ("About 15 years to go"). The month says when, and the *Time to retire* widget and Progress's "To go" say how long.
- **Type styles:** three (title, subheadline, caption).

**Why.** Two tiles are the quickest to scan: "Not yet" and "312.480 €" read at once, in the same place every month. They match the widgets, so the app and the home screen look alike. The tiles give each tile's numbers a clear owner, where today net worth floats under the answer's sentences. The cost: half a width is narrow, so some words get shorter ("Mar 2042"), and the tiles stack at large text sizes.

### States

| State | What the header shows |
| --- | --- |
| Not yet, with an age | as above |
| Yes | "Yes" / "Retire today" / "in 9 of 10 futures"; a full bar, "130%" |
| No age works out | "Not yet" / "No age works yet" / "in 9 of 10 futures"; the bar |
| Recorded at a check-in | the answer tile gets a last row, "◷ 30 Sep check-in"; the net worth tile grows to match |
| Out of date | the answer tile's last row is *Calculate*; its lines dim |
| Calculating | the answer tile's last row is "Calculating 29%" |
| No answer yet | net worth leads as today, full width, with no tiles; the answer's card stays below the chart |
| Hidden amounts | the net worth tile reads "•••••", "▲ 1,4% in September", "▲ 6,2% this yr"; the baseline row reads "On plan ›" without its amount |
| Large text | the tiles stack, each the full width (below) |

```
Large text: the tiles stack
┌──────────────────────────────────────────┐
│ ╭──────────────────────────────────────╮ │
│ │ Can I retire yet?                    │ │
│ │ Not yet                              │ │
│ │ At 54 · Mar 2042                     │ │
│ │ in 9 of 10 futures                   │ │
│ │ ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇░░░░░░░░░░░ 58% │ │
│ ╰──────────────────────────────────────╯ │
│ ╭──────────────────────────────────────╮ │
│ │ Net worth                            │ │
│ │ 312.480 €                            │ │
│ │ ▲ 4.210 € in September               │ │
│ │ ▲ 6,2% this year                     │ │
│ ╰──────────────────────────────────────╯ │
│ ┆                                        │
```

### iPad and Mac

Three tiles across: the answer, the readiness with its whole sentence, ⓘ and the baseline, and net worth. The readiness gets a tile of its own because there's room for its words.

```
┌────────────────────────────────────────────────────────────────┐
│ ╭───────────────────╮ ╭──────────────────╮ ╭─────────────────╮ │
│ │ Can I retire yet? │ │ 58% of what      │ │ Net worth       │ │
│ │ Not yet           │ │ retiring today   │ │ 312.480 €       │ │
│ │ At 54 · Mar 2042  │ │ needs ⓘ          │ │ ▲ 4.210 €       │ │
│ │ in 9 of 10 futures│ │ ▇▇▇▇▇▇▇▇▇░░░░░░░ │ │ in September    │ │
│ │                   │ │ On plan ›        │ │ ▲ 6,2% this year│ │
│ ╰───────────────────╯ ╰──────────────────╯ ╰─────────────────╯ │
│ Estimates, not financial or tax advice.                        │
│                                                                │
│ 3Y · retirement +15 ▾                                 Future ◯ │
└────────────────────────────────────────────────────────────────┘
```

## C. One gauge

The answer, then one picture of how far along you are: the readiness bar with the baseline drawn on it. Readiness and the baseline become one visual instead of two sentences.

```
┌──────────────────────────────────────────┐
│ Overview                        👁   ⚙︎   │
│                                          │
│ Can I retire yet?                      › │  ← subheadline, secondary
│ Not yet · earliest at 54                 │  ← title2, bold
│ About 15 years · in 9 of 10 futures      │  ← subheadline, secondary
│                                          │
│ 58% of what retiring today needs       ⓘ │  ← subheadline
│ ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇░░░░░░░░░░░░░░░░░ │  ← readiness, 0 to 100%
│                     └Jan┘        On plan │  ← the baseline's range
│                                          │
│ Net worth 312.480 €                      │  ← title3
│ ▲ 4.210 € in September  ▲ 6,2% this year │  ← subheadline
│                                          │
│ 3Y ▾                            Future ◯ │
└──────────────────────────────────────────┘
```

**The gauge.** The bar is the readiness, as today: it fills to 58% and is full at 100%, where retiring today works. Under it, a bracket marks where the baseline expected you to be today: its 25–75% futures, which is where *Are you on track?* draws the line between ahead, on and behind plan ([UI.md](../UI.md#progress)). The bar ends inside the bracket when you're on plan, past it when ahead, short of it when behind. The word at the right says the same ("On plan", in its color; "Behind plan" in orange), so color is never alone. Without a baseline there's no bracket and no word.

The bracket turns the baseline's range from money into readiness: each end is the baseline's amount for today, in today's money, divided by what retiring today needs (plan assets ÷ readiness). That assumes what retiring today needs doesn't depend on what you have, which holds only roughly: money locked in pension funds stays as it is. The follow-up checks this against the planner ([PLANNER.md](../PLANNER.md#assets-needed-to-retire-today)) before building it, and falls back to the word alone if it doesn't hold.

- **Keeps:** the answer, the time to go, the confidence, the readiness sentence and bar, the standing, net worth and its changes.
- **Moves:** the baseline's amount ("12.400 € ahead of January") to the gauge's ⓘ, with the readiness explanation and the disclaimer (D1); Progress's *Are you on track?* has it too. The run status to the label row (R1).
- **Drops:** the baseline sentence; the bracket says it.
- **Type styles:** three (title2, title3, subheadline). The answer drops from largeTitle to title2 so "Not yet · earliest at 54" fits on one line on an iPhone.

**Why.** "How close am I" is the part of the header that changes every month, and a picture says it faster than two sentences. The gauge has no amounts, so it looks the same with amounts hidden. The cost: the bracket is new, and needs the ⓘ to explain it the first time.

### States

| State | What the header shows |
| --- | --- |
| Not yet, with an age | as above |
| Yes | "Yes · you could retire today" / "In at least 9 of 10 futures"; the bar is full, with "130% of what retiring today needs" |
| No age works out | "Not yet" / "No age works in 9 of 10 futures yet"; the gauge as usual |
| Recorded at a check-in | as A: "◷ 30 Sep" in the label row; an answer recorded before readiness existed shows "Calculate the plan to see how close you are to retiring today." in the gauge's place, and no bracket |
| Out of date | as A: *Calculate* in the label row, the answer and the gauge dimmed |
| Calculating | as A: "Calculating 29%" in the label row |
| No answer yet | net worth leads as today; the answer's card stays below the chart |
| Hidden amounts | only net worth changes: "Net worth •••••", the changes in per cent. The gauge is unchanged |
| Large text | the bracket's label and the standing move to a line of their own under the bar; the rest wraps |

```
Ahead of plan                                Behind plan
┌──────────────────────────────────────────┐ ┌──────────────────────────────────────────┐
│ 66% of what retiring today needs       ⓘ │ │ 49% of what retiring today needs       ⓘ │
│ ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇░░░░░░░░░░░░░░ │ │ ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇░░░░░░░░░░░░░░░░░░░░░ │
│                     └Jan┘  Ahead of plan │ │                     └Jan┘    Behind plan │
```

### iPad and Mac

The answer on the left and net worth on the right, then the gauge across the whole width, where the bracket has more room.

```
┌────────────────────────────────────────────────────────────────┐
│ Can I retire yet?                    ›   Net worth             │
│ Not yet · earliest at 54                 312.480 €             │
│ About 15 years · in 9 of 10 futures      ▲ 4.210 € in September│
│                                          ▲ 6,2% this year      │
│ 58% of what retiring today needs                             ⓘ │
│ ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│                                 └─Jan─┘                On plan │
│                                                                │
│ 3Y · retirement +15 ▾                                 Future ◯ │
└────────────────────────────────────────────────────────────────┘
```

## D. Net worth first

Net worth leads, as it does before there's an answer, and the answer is a compact card under it that opens the plan. The top of the screen looks the same whether the plan has an answer or not.

```
┌──────────────────────────────────────────┐
│ Overview                        👁   ⚙︎   │
│                                          │
│ Net worth                                │  ← subheadline, secondary
│ 312.480 €                                │  ← largeTitle
│ ▲ 4.210 € in September  ▲ 6,2% this year │  ← subheadline
│ ╭──────────────────────────────────────╮ │
│ │ Can I retire yet?          On plan › │ │  ← subheadline
│ │ Not yet · earliest at 54             │ │  ← title3
│ │ March 2042 · in 9 of 10 futures      │ │  ← subheadline, secondary
│ │ ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇░░░░░░░░░░░░░ 58% │ │
│ ╰──────────────────────────────────────╯ │
│                                          │
│ 3Y ▾                            Future ◯ │
└──────────────────────────────────────────┘
```

- **Keeps:** net worth and its changes, the answer, the month, the confidence, the readiness as a bar and its percentage, the standing as a word.
- **Moves:** the baseline's amount, the readiness sentence and its explanation, and the disclaimer to the Plan screen, which the card opens (D3); the Plan screen's answer already shows "18.400 € ahead ›", and its key numbers "You have 58%". The run status to a row in the card (R2).
- **Drops:** the time to go ("About 15 years"), as in B.
- **Type styles:** three (largeTitle, title3, subheadline).

**Why.** Net worth is what changes at every check-in; the answer moves a year at a time. Leading with the number that moves, and keeping the answer one tap from its details, makes the header shortest. The screen also stops changing shape when an answer appears, goes out of date or is calculated. The cost: the app's question is no longer the first thing on its home screen, which UI.md chose on purpose ("The screen leads with the app's question"). Choosing D reverses that decision.

### States

| State | What the header shows |
| --- | --- |
| Not yet, with an age | as above |
| Yes | the card reads "Yes · you could retire today" / "In at least 9 of 10 futures", a full bar and "130%" |
| No age works out | "Not yet" / "No age works in 9 of 10 futures yet", the bar |
| Recorded at a check-in | the card's last row: "◷ Recorded at the check-in on 30 Sep" |
| Out of date | the card's last row: "Calculated before your latest changes" and *Calculate*; the card's other lines dim |
| Calculating | the card's last row: "Calculating 29%" |
| No answer yet | net worth as above, and no card; the answer's card stays below the chart, as today. Another option is to move that card up into this place, which changes what's below the chart, so it's left out here |
| Hidden amounts | "•••••" and the changes in per cent; the card has no amounts |
| Large text | the card's label row wraps, with "On plan ›" on a line of its own; the bar's percentage moves under the bar |

### iPad and Mac

Net worth on the left, the answer's card on the right, at the same height.

```
┌────────────────────────────────────────────────────────────────┐
│ Net worth                  ╭─────────────────────────────────╮ │
│ 312.480 €                  │ Can I retire yet?     On plan › │ │
│ ▲ 4.210 € in September     │ Not yet · earliest at 54        │ │
│ ▲ 6,2% this year           │ March 2042 · in 9 of 10 futures │ │
│                            │ ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇░░░░░░░░░░░ 58% │ │
│                            ╰─────────────────────────────────╯ │
│                                                                │
│ 3Y · retirement +15 ▾                                 Future ◯ │
└────────────────────────────────────────────────────────────────┘
```

## Side by side

| | Today | A. Trimmed | B. Two tiles | C. One gauge | D. Net worth first |
| --- | --- | --- | --- | --- | --- |
| Leads with | the answer | the answer | both, as equals | the answer | net worth |
| Rows above the chart on an iPhone (wireframes) | 18 | 11 | 10 | 11 | 10 |
| Text styles | 6 | 3 | 3 | 3 | 3 |
| Time to go | ✓ | ✓ | – | ✓ | – |
| Readiness sentence | ✓ | ✓ | in the ⓘ | ✓ | on the Plan screen |
| Baseline amount | ✓ | ✓ | ✓ | in the ⓘ | on the Plan screen |
| Run status | own line | label row (R1) | tile row (R2) | label row (R1) | card row (R2) |
| Disclaimer | own line | in the ⓘ (D1) | own line (D2) | in the ⓘ (D1) | Plan screen (D3) |

Rows are counted from the wireframes, from "Can I retire yet?" or "Net worth" to the line before the chart's controls, blank lines included. They're a guide to the height, not a measurement.

## Open questions

- **Which direction to build?** Or which parts of more than one: the run status (R1, R2) and the disclaimer (D1–D3) go with any layout, and C's gauge would fit into A or D in place of their bar.
- **Must the disclaimer stay visible on the Overview?** If so, D2 (B's choice); a footer under the allocation would also work, but it adds to what's below the chart.
- **Can the time to go leave the Overview** (B, D)? The *Time to retire* widget and Progress's "To go" keep it.
- **Can the baseline's amount leave the Overview** (C, D)? The word "On plan" stays.
