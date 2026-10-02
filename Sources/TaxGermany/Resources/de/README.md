# German tax parameters

One file per tax year: `<year>.json`, e.g. `2026.json`, in nominal EUR of that year. The code reads every rate and threshold from here and hard-codes none (see [TAXES.md](../../../../docs/TAXES.md#parameters) and [tax/DE.md](../../../../docs/tax/DE.md)).

- **Sources.** Every value is covered by a `source` on its object or an enclosing one. `ParameterFileTests.everyValueHasASource` checks it.
- **Verify.** Objects flagged `"verify": true` hold values that no ruling settles, or that came only from secondary sources. `note` explains why; `ParameterFileTests.valuesToVerifyAreFlagged` lists them.
- **Indexing.** An object's `"indexed"` says how its amounts follow prices after the file's year: `"plan"` (the plan's `indexThresholds`: the tariff and the Soli's limit), `"fixed"` (nominal by law: the lump sums, the savers' allowance, Riester, trade tax, inheritance allowances; the residence option `indexFixedAllowances` treats them as `plan`), or `"wages"` (this system's own rule: contribution ceilings, the minimum base, the bAV limits and the other amounts set from average wages grow with the residence option `realWageGrowth`). `ParameterSet.indexingRule(at:)` reads it.
- **Overrides.** A plan's `overrides` replace values by dotted path with the system prefix, e.g. `"de.incomeTax.tariff.zones.4.rate": "0.47"` or `"de.socialInsurance.health.averageAdditionalRate": "0.031"`.

Adding a year: copy the latest file to `<year>.json`, change what the law changed (with sources), and add reference cases in `Tests/TaxGermanyTests/cases/`. No code changes are needed unless the law's structure changes. The 2027 income-tax reform (a fourth rate of 47%) is an extra linear zone.
