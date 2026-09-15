# Lyle & Wang (2015 JFE) — complete replication scorecard

Assembled 2026-09-13. Every exhibit in the paper replicated on a fresh 2026 WRDS pull
through the rationalized pipeline (`Codes/replication2026/`), after first validating the
engine float-exactly / bit-identically against the frozen March-2014 build (VALIDATION.md).
Full per-branch reports: `docs/exhibit-branches-2026-09-13/` and `out/exhibits/`.

| Exhibit | Published headline | Fresh-data replication | Verdict |
|---|---|---|---|
| **T1** parameter stats | κ mean .9834, ω .9036, μ .0099 | .9834 / .9043 / .0113 (medians match to 3-4 dec) | ✅ exact |
| **T2** ER summaries | mu1..mu12 cs-means −.0070..−.0616 | −.0071..−.0547; sds match to 3 dec | ✅ (one LT-mean tail caveat) |
| **T3** validation regs | cum slopes .8555/.7162/.5954/.5244 | .8219/.6760/.5453/.4614 (same sig pattern, β=1 rejections identical) | ✅ within drift |
| **T4** portfolio sorts | EW q10 hedge .109/.329/.424/.448 | .108/.326/.412/.414 (t 10.8–16.1) | ✅ |
| **T5** IV | Panel B .6102/.5006/.4056/.3485 | .5768/.4697/.3781/.3225; params + first-stage F match | ✅ within drift |
| **T6** annual | Panel A κ .9821 etc.; Panel B .5832/.5132/.4620 | Panel A exact to 4 dec vs frozen workbook; Panel B .62/.51/.46 (roll15/cum bracket published) | ✅ (published Panel B N traced to pre-freeze vintage) |
| **T7** NLSUR net returns | A 1.0346, E[R] 12.07% ann., κ .9767, ω .7230; Panel B 3M .5973 (N=550,320) | **all stats exact on frozen inputs incl. N**; FRESH within drift | ✅ perfect (+ resolved spec ambiguity: published = raw-regressor variant) |
| **T8** factor comparison | LW .5620 vs CAPM −.7034/FF3 −.6133/FF4 −.5240; LW 10−1 .0538 | .5523 / −.7007 / −.5793 / −.5034 (SUR er1, N 484,931 vs 485,222); 10−1 .0487 | ✅ |
| **T9** aggregate + KP | LW R²_OS .62%, slope .4936; KP 4.78%/1.3518 and .53%/.4512 | **.619%/.4937; 4.777%/1.3516; .529%/.4509** | ✅ exact (9/9 stats) |
| **F1** cutoff robustness | slopes ~.80–.93; hedges .03–.065 | .78–.89; .033–.064; marginal cutoffs match published 10% diamonds | ✅ |
| **F2** ER curve surface | 6–16% ann., recession flattenings | data feed float-exact vs published CSV; surface reproduced | ✅ exact inputs |
| **F3** ER vs Treasury spreads | means 1.59/3.19pp, 1987 peaks 4.1/7.6 | line-for-line (update corr .996 on overlap) | ✅ (published 2002–06 Treasury hump = legacy interpolation bug, documented) |

## Out-of-sample update (through 2025Q4, spliced SIZ+CIZ, tag CIZ)

- Panel: 1,027,274 firm-quarters, 1971Q1–2025Q4 (dateid 1–220).
- **True OOS hedge returns 2014Q1+ (EW q10, cum): 3M 0.1115 (t=6.6) — above the published
  in-sample 0.109; 12M 0.3200 (t=9.0); 24M 0.3418 (t=5.7); 36M 0.1600 (t=2.6).**
- Validation-regression slopes post-2014 exceed in-sample at every horizon (3M 0.91).
- Aggregate predictor true-OOS R²_OS 5.6–9.1% (vs 0.62% in-sample).
- Parameter drift continues: 2024Q1+ medians κ .9958, μ −0.28%/q (see OOS_UPDATE.md
  diagnostics: value-winter + 2022–24 dispersion, not COVID; ROE channel COVID-dented).
- Updated Fig-2/3/web feed: `out/MedianParams_CIZsampleall.csv` (1986Q1–2025Q4).

## Provenance findings for the record
1. Published T7 numbers come from the raw-regressor NLSUR spec (Jan-2014 file), not the
   winsorized-regressor Mar-2014 variant.
2. Published T6 Panel B N (173,802) matches no surviving artifact; frozen Apr-2014 workbook
   matches this pipeline to Δ6 obs — published came from an earlier vintage.
3. Published T9 Panel B SEs are classical OLS despite the do-file's `, robust`.
4. Published F3's 2002–06 Treasury 30y "hump" is a legacy Matlab interpolation artifact.
5. Machine gotcha: SSC `cluster2` today is an unrelated power calculator — two-way
   clustered SEs must be computed via CGM decomposition or reghdfe.
