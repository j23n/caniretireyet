# Italian tax parameters

One file per tax year: `<year>.json`, e.g. `2026.json`, in nominal euros of that year. The code reads every rate and threshold from here and hard-codes none (see [TAXES.md](../../../../docs/TAXES.md#parameters) and [tax/IT.md](../../../../docs/tax/IT.md)).

- **Sources.** Every value is covered by a `source` on its object or an enclosing one. `ParameterFileTests.everyValueHasASource` checks it.
- **Verify.** Objects flagged `"verify": true` hold values that no ruling settles, or that came only from press summaries. `note` explains why.
- **Which file applies.** A simulated year uses the latest file at or before it; later years reuse the latest file, with thresholds indexed or not as the plan says (`indexThresholds`). INPS amounts (maximum and minimum bases, assegno sociale, minimum pension) are indexed by law, so they're always kept in today's euros.
- **Overrides.** A plan's `overrides` replace values by dotted path with the system prefix, e.g. `"it.forfettario.rate": "0.1"` or `"it.irpef.brackets.1.rate": "0.35"`. A schedule also takes `rates` and `limits` lists: `"it.irpef.rates": ["0.23", "0.35", "0.43"]`.

Adding a year: copy the latest file to `<year>.json`, change what the budget law changed (with sources), and add reference cases in `Tests/TaxItalyTests/cases/`. No code changes are needed unless the law's structure changes.
