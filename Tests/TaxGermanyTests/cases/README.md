# German reference cases

One JSON file per case: a year's inputs and the expected itemised result, worked out by hand with the arithmetic in `workings`. `ReferenceCaseTests` runs them all; adding a case needs no code. The format is the Italian one (`Tests/TaxItalyTests/ReferenceCase.swift`) with what the German rules read besides: `birthDate`, `citizenships`, the `residence` timeline, a pension's `kind`, `startYear`, `sourceCountry`, `form` and `mandatoryShare`, `currencyRate`, a balance's `startValue` and `nominalReturn`, and the expected `costBasisAdjustments` and `nextState`. `kind: pensionClaims` checks the `de.drv` claim options for a record. The folder is bundled with the test target (`Bundle.module`, `cases/`).

The people in them are made up. Expected values come from the documented arithmetic, cross-checked with an independent calculation of the tariff, not from the module's output.
