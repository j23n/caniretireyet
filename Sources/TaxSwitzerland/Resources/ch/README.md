# Swiss tax parameters

One file per tax year: `<year>.json`, e.g. `2026.json`, in nominal CHF of that year. The code reads every rate and threshold from here and hard-codes none (see [TAXES.md](../../../../docs/TAXES.md#parameters) and [tax/CH.md](../../../../docs/tax/CH.md)).

- **Sources.** Every value is covered by a `source` on its object or an enclosing one (`ParameterAudit.unsourcedPaths`).
- **Verify.** Objects flagged `"verify": true` hold values that still need checking against an official text; CH.md's open questions list them.
- **Indexing.** An object's `"indexed"` says how its amounts follow prices after the file's year: `"law"` (indexed by law, whatever the plan says: the federal tariff and deductions, AHV and BVG amounts, the 3a maximums, the Zurich and Ticino tariffs and deductions), `"fixed"` (fixed in nominal terms by law: the personal taxes, the federal tax's 25-franc minimum, the expatriate flat deduction, the mortgage-interest cap), or none, for the plan's `indexThresholds` (Ticino's wealth tariff, whose indexation wasn't found). `ParameterSet.indexingRule(at:)` reads it, and `ThresholdIndexing.scale(for:parameterYear:rule:)` applies it.
- **Cantons.** The `canton` option offers the cantons under `cantons`; a canton is added with its tariffs, deductions, multipliers and capital-benefit method (CH.md, "Cantons and communes"). `cantonsNotOffered` keeps what was found for others.
- **Overrides.** A plan's `overrides` replace values by dotted path with the system prefix, e.g. `"ch.cantons.ZH.multipliers.canton": "0.98"` or `"ch.cantons.TI.income.maximumCategoryRate.value": "0.145"`.
