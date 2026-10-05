# Tax research

Research from an earlier version of the planner, which modelled the Italian, Swiss and German tax systems in detail: work income and social contributions, pensions and their payout rules, pension funds, investments, wealth taxes and treaties. That version was replaced by a simpler model ([PLANNER.md](../../PLANNER.md#the-model-in-brief)): you enter income and pensions after tax, and set a tax rate on investments and an optional wealth tax by hand.

Nothing here is used by the app. It's kept as background for choosing those rates, and for a future version that might model a country again.

| File | What it covers |
| --- | --- |
| [IT.md](IT.md), `it-2026.json` | Italy: IRPEF, forfettario, impatriati, INPS, pension fund, TFR, investments, the 0.2% wealth tax |
| [CH.md](CH.md), `ch-2026.json` | Switzerland (Zurich and Ticino): income and wealth taxes, AHV, BVG, pillar 3a, investments |
| [DE.md](DE.md), `de-2026.json` | Germany: income tax, social insurance, statutory and private pensions, investment funds |
| `*-parameters-README.md` | How each country's yearly parameter file was laid out |

Links inside these files point to documents and source files that no longer exist (TAXES.md, the `Tax…` modules). Values are for 2026, as checked in September and October 2026, and are not kept up to date.

For the rates the planner asks for, as a starting point:

- **Italy:** 26% on investments (12.5% on government bonds, which a single rate can't tell apart), and a 0.2% wealth tax (bollo and IVAFE) with no allowance.
- **Germany:** 26.375% on investments (25% plus the solidarity surcharge, before church tax), with a yearly allowance the single rate ignores; no wealth tax.
- **Switzerland:** no tax on private capital gains, but dividends and interest are taxed as income, at your marginal rate. The single rate applies to both, so it's a compromise: 0% understates the tax on income, your marginal rate overstates it on sales. The cantonal wealth tax depends on the canton, the municipality and your wealth (roughly 0.1% to 1% a year), above an allowance.
