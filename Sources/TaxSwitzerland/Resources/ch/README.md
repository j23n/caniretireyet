# Swiss tax parameters

One file per tax year: `<year>.json`, e.g. `2026.json`, in nominal CHF of that year. The code will read every rate and threshold from here and hard-code none (see [TAXES.md](../../../../docs/TAXES.md#parameters) and [tax/CH.md](../../../../docs/tax/CH.md)). The draft for 2026 is in `docs/tax/drafts/ch-2026.json`.

- **Sources.** Every value is covered by a `source` on its object or an enclosing one (`ParameterAudit.unsourcedPaths`).
- **Verify.** Objects flagged `"verify": true` hold values that still need checking against an official text.
- **Indexing.** An object's `"indexed"` says how its amounts follow prices after the file's year: `"law"` (indexed by law, whatever the plan says), `"fixed"` (fixed in nominal terms by law), `"plan"` (the plan's `indexThresholds`, the default), or a rule of this system's own. `ParameterSet.indexingRule(at:)` reads it, and `ThresholdIndexing.scale(for:parameterYear:rule:)` applies it.
- **Overrides.** A plan's `overrides` replace values by dotted path with the system prefix, e.g. `"ch.<path>": "0.1"`.
