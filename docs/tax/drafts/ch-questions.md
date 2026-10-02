# Switzerland: decisions and open questions

What needs deciding before `TaxSwitzerland` is built, and what the law or the sources left open. The design is in [CH.md](../CH.md).

## Decisions for you

1. **Which cantons, and which communes?** The tariffs are the expensive part. Zurich is complete; Zug and Ticino need their tariffs copied from the official documents; the other six have only their multipliers. Which ones would you actually consider?
   - Zurich (jobs; high capital-withdrawal tax), Zug (low taxes, high rents), Ticino (Italian-speaking, close to Italy; capital tax capped at 3% cantonal), Schwyz (very low taxes in Wollerau and Freienbach), Geneva or Vaud (French-speaking).
   - For each, the commune: its multiplier is all the module needs (e.g. Lugano 80%, Bellinzona 93%).
2. **Where you'd retire.** The biggest lever in the plans is where you live when the pensions are paid:
   - in Switzerland, BVG and 3a lump sums cost 4–8% (Zurich), and annuities and AHV are taxed as income;
   - back in Italy, AHV and BVG benefits, annuities and lump sums alike, are taxed at a flat **5%**; the pillar 3a's Italian treatment is unclear.

   So a plan will often be "work in Switzerland, retire to Italy". Do you want such a timeline (residence `ch` then `it`) as the default comparison? It needs the `it` module to learn the `ch.ahv` and `ch.bvg` pensions.
3. **Employee or self-employed in Switzerland.** Self-employed: no compulsory BVG, but 3a up to 20% of income (CHF 36,288). Both regimes are in the design; which matters first?
4. **Your pension fund.** Once employed, your pension certificate gives the assets, the conversion rate and the lump-sum rules. Until then the defaults are the legal minimum for contributions and a 5.4% conversion rate at 65 for the annuity. Are those acceptable placeholders?
5. **Base currency.** Your library is in euros. While you live in Switzerland, should plans still be shown in euros (the module converts at the start date's rate, held constant in real terms), or should the library switch to francs? Exchange-rate risk isn't modelled either way; should it be, later?
6. **AHV claim age.** With `claim: "earliest"` the planner would take the AHV at 63 with a lifelong −13.6%. Should the `ch.ahv` default be 65 instead?
7. **Lump-sum taxation.** Only relevant if you'd live in Switzerland without working there (e.g. retiring there with large wealth). Worth building now, or later?
8. **Your home.** Owning in Switzerland brings the imputed rent until 2028 and wealth tax on the home. Until TaxKit passes excluded assets, the home goes in as system options. Is that enough for now?
9. **Church tax.** Off by default. Are you a member of a church that would be recognised in Switzerland (Catholic or Reformed)?
10. **Which TaxKit changes to make first.** Needed for a usable Swiss module: currency (gap 1), a lump sum from a pension scheme (2), funds' yearly income (5). Useful soon: buy-ins (3), forced and staggered payouts (8), indexed-by-law values (9). Later: the rest. Agree?

## Open legal and factual questions

Each is marked *verify* in CH.md or the parameter draft.

1. **Federal tariff 2026.** The draft reproduces the ESTV's figure at CHF 185,100 exactly, but the lower limits (15,200 to 58,000) are the 2025 ones; check them against Form. 58c 2026.
2. **Zug.** The full Grundtarif 2026 (income and wealth), the wealth allowance (CHF 200,000 or 101,000: the sources disagree), the capital-benefit method, the professional-expense and insurance deductions, the city of Zug's 2026 multiplier (52% proposed) and the lump-sum minimum.
3. **Ticino.** The 2026 income scale (top rate 14%), the wealth scale, the insurance deduction, whether the 3% cap on capital benefits applies to the simple rate before the communal multiplier, Lugano's multiplier (80% or 75%), and the deemed wealth under lump-sum taxation.
4. **Other cantons.** Geneva's structure (centimes additionnels and other reductions), Lucerne's and Schwyz's units (the extracts disagree), Basel-Stadt's tariff, and every lump-sum minimum.
5. **Zurich details.** The insurance deduction (CHF 2,900), the church multipliers in the city, the personal tax, the trigger for indexing the tariff, and the 2026 wealth tariff (one extract mentions an extra CHF 204,000 deduction that doesn't fit).
6. **AHV.** The new early-withdrawal and deferral rates (at the earliest from 2027); the rounding of the partial scales; how a non-employed contribution converts into income for the average (the AHV share × 100 / 8.7 is assumed); whether the revaluation factor stays at 1.000.
7. **Self-employed.** The sliding scale's official steps (the draft interpolates); whether the 20% 3a limit is on income after AHV contributions; the compensation offices' admin costs.
8. **BVG after moving to Italy retired.** Whether the mandatory part can be paid out if you don't work in Italy (the Guarantee Fund's check with INPS).
9. **Italian side.** How Italy taxes pillar 3a payouts to a resident; whether a TFR paid to a Swiss resident stays taxable in Italy (Art. 15) and how Switzerland treats it; how Switzerland taxes an Italian pension-fund lump sum (capital benefit or income); the form INPS needs to pay a pension gross.
10. **Lump-sum taxation and the treaty.** Whether Italy grants treaty benefits to someone taxed on expenditure only under the "modified" lump-sum taxation, which taxes Italian-source income in full.
11. **The 3-year lock in a yearly model.** The law counts 3 years from the buy-in; the draft blocks the buy-in year and the 3 calendar years after it, which may be one year too strict.
12. **Expatriate deductions** in each canton.
13. **Coming changes** that later parameter files need: individual taxation of married couples and a new federal tariff by 2032; the 2027 AHV and BVG amounts (minimum pension CHF 1,280, 3a CHF 7,373); the federal tariff +0.47% in 2027; Ticino's top rate falling to 12% by 2030; the imputed rent ending in 2029; the VAT increase for the 13th pension (a vote is pending; it's spending, not a tax-system parameter).
