# Germany: decisions and open questions

What the `de` design in [DE.md](../DE.md) needs from you, and what the law or the sources leave open. Each open question says what the module assumes until it's settled.

## Decisions for you

| # | Decision | Why it matters | Default in the design |
| --- | --- | --- | --- |
| 1 | **Your citizenship**: German, Italian, both, or other. | The Italy–Germany treaty taxes state pensions by citizenship (Art. 19(4)). An Italian-only citizen living in Germany pays Italian tax on an INPS pension; a German-only citizen living in Italy pays German tax on a DRV pension, without the Grundfreibetrag unless 90% of income is German. | `other`, with a warning on each pension |
| 2 | **GKV or PKV** while working, if you'll earn above €77,400 or be a freelancer. | PKV is often cheaper while young, but its premium rises with age and doesn't depend on income; returning to GKV after 55 is nearly impossible. GKV charges voluntary members on all income, capital gains included. | GKV |
| 3 | **Health insurance in retirement**: will you qualify for KVdR (9/10 of the second half of your working life in statutory health insurance)? Years in Italy count only if they count as insurance periods (question 2 below). | Under KVdR, capital income is free of contributions. As a voluntary member, an early retiree pays about 21% on realised gains (after the partial exemption) up to €69,750, on top of income tax, and at least €3,338 a year. | KVdR from the first pension; voluntary before it |
| 4 | **Church membership** and **federal state**. | Church tax is 8% (Bavaria, Baden-Württemberg) or 9% of income tax, and lowers the flat rate on investment income to 24.45–24.51% (27.82–27.99% in all). | Not a member; Berlin |
| 5 | **As a freelancer**: voluntary or compulsory DRV contributions, Rürup, or neither. And is your work a profession (Freiberufler) or a trade? | Rürup contributions are deductible up to €30,826 (saving about 40% at €80,000 profit) but pay only a lifelong annuity, from 62. DRV points also count toward the waiting times. IT consulting is often classed as a trade, which adds trade tax (mostly credited back up to a multiplier of 4.0). | `de.freelancer`, no DRV |
| 6 | **Children.** | Childless people pay 0.6 points more care insurance from 23; Riester and the Altersvorsorgedepot pay child grants. | Childless |
| 7 | **Plan assumptions**: real wage growth (1%), real growth of the pension value (0.5%), the future Basiszins (3.20%), PKV premium growth (1% above prices), a rising retirement age (none). | They move the DRV pension in today's euros, the Vorabpauschale, and the PKV cost in old age. | As listed; all marked *verify* |
| 8 | **Whether fixed allowances keep their value** (the €1,000 savers' allowance, the lump sums, inheritance allowances). | The law changes them rarely (the inheritance allowances not since 2009), so in today's euros they shrink. | They shrink (`indexFixedAllowances: false`) |
| 9 | **Fund structure, if you might leave Germany again** after 7 or more years. | Since 2025 the exit tax covers a fund (ETFs included) whose shares cost €500,000 or more, counted per fund. Several funds below that avoid it. | A warning only |
| 10 | **Which TaxKit gaps to close with the module.** | G1 (fund types), G2 (Vorabpauschale cost basis) and G5 (pension kinds and start years) change results the most; G1 and G5 touch Model and the planner. G4, G6–G12 can wait. | G1, G2 and G5 with the module |

## Open legal and factual questions

| # | Question | Assumed until settled |
| --- | --- | --- |
| 1 | From 2026 the Lohnsteuer deducts the unemployment contribution, which the assessment doesn't. Must employees with wages only now file a return (§46 Abs. 2 Nr. 3 EStG), or is that part exempt? | The planner computes the assessed tax; it doesn't matter for the model, only for what you'll see on payslips. |
| 2 | Do years covered by Italy's residence-based health service count as insurance periods for the KVdR 9/10 rule (Art. 6 of Regulation 883/2004)? | They count (`italianResidencePeriods: true`). Ask the Krankenkasse; a refusal means voluntary GKV in retirement. |
| 3 | For voluntary members: does the fund apply the partial exemption to fund gains, and does it charge the Vorabpauschale and Riester and Rürup payouts? | Yes to all three (secondary sources only). |
| 4 | Is care insurance charged at the full rate on a foreign statutory pension? | Yes. |
| 5 | Are health and care contributions on a pension Italy taxes (Art. 19(4)) deductible in Germany (§10 Abs. 2 Satz 1 Nr. 1 and its EU exception)? | Not deductible (case 17b). |
| 6 | How Germany taxes payouts from an Italian pension fund (*previdenza complementare*), and whether Italy withholds at source. | Treaty Art. 18 (Germany). Annuities at the *Ertragsanteil*; lump sums on the gain, half of it after 12 years and from 62. |
| 7 | Is the TFR paid after moving to Germany taxed by Italy (Art. 15) or by Germany (Art. 18)? | Italy; Germany applies the progression clause at one fifth. |
| 8 | Is interest on Italian government bonds paid to a German resident free of Italian tax (D.Lgs. 239/1996), with your broker? | Yes; no foreign tax to credit. |
| 9 | For the exit tax on funds (§19 Abs. 3 InvStG): do the 7-year instalments and the return-within-7-years cancellation of §6 AStG apply the same way? | Yes; the planner only warns. |
| 10 | Do Italy's flat-tax regimes (7% for pensioners in the south; the €200,000 lump sum) make Italy a low-tax country for the extended limited tax liability of §2 AStG? | Not modelled; flagged in DE.md. |
| 11 | Do Italian compulsory contribution years count toward the 45 years for the pension at 65? | Yes (Art. 6), subject to the 18-year rule for voluntary periods. |
| 12 | Does a bAV lump sum get the one-fifth rule? | No (the BFH allowed it only where the contract didn't provide for a lump sum). |
| 13 | Aktivrente: is the €1,230 lump sum deducted in full from the taxable part of the salary? Is an employee past the standard age free of unemployment contributions, and still in the pension insurance while not drawing a pension? | Yes to all three (case 20). |
| 14 | How is Riester's 30% lump sum at the start of payout taxed (all in that year, no one-fifth rule)? | All in that year, no one-fifth rule. |
| 15 | The *Ertragsanteil* table for private annuities was written from the statutory table without re-reading it. | As in the draft parameter file, flagged *verify*. |
| 16 | The Altersvorsorgedepot from 2027: can the self-employed join; the exact grants and payout rules. | As in DE.md, from the BMF FAQ and press extracts. |
| 17 | Crypto staking: the €256 threshold and the BMF letter of 6 March 2025. | As in DE.md. |
| 18 | Laws still in progress: the Einkommensteuerreformgesetz 2027 (new tariff, €1,430 lump sum, 47% from €280,000); the pension reform following the Alterssicherungskommission (retirement age linked to life expectancy, the 45-year pension, the 35-year pension from 64); compulsory pension provision for the self-employed; the Constitutional Court on inheritance tax (hearing 12–13 October 2026); the Frühstartrente. | 2026 law. A `2027.json` follows once the tariff passes; the rest are plan assumptions or not modelled. |

## Corrections to the brief

- The Besteuerungsanteil for a 2025 start is **83.5%**, not 83% (83% was 2024): after the Wachstumschancengesetz it rises by 0.5 points a year from 82.5% in 2023, to 84% in 2026 and 100% in 2058.
- **ETFs are no longer outside the exit tax**: since 1 January 2025, §19 Abs. 3 InvStG applies to fund holdings of at least 1% of a fund or €500,000 of purchase cost per fund (JStG 2024).
