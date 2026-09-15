# Out-of-sample update — phase 1 (data through 2024Q4)

Run: 2026-09-05, `stata/run_oos_update.do` + `make_medianparams.do`, tag `CURR`, sampleall.
Master: 1,008,332 firm-quarters, 1971Q1–2024Q4 (dateid 1–216). SIZ CRSP tables (frozen at
2024-12); the 2025 tail requires the CIZ migration (`crsp.msf_v2`; size-decile benchmark
must be rebuilt — no ermport1 v2).

## Headline: the strategy survived the post-publication decade

EW decile hedge returns (market-adjusted log, recursive/cum estimates, q10−q1):

| Horizon | Full 1986–2024 | **True OOS 2014Q1–2024Q4** | JFE published (1986–2013) |
|---|---|---|---|
| 3M  | 0.1077 (t=12.4) | **0.1079 (t=6.2)** | 0.109 |
| 12M | 0.3148 (t=18.0) | **0.2979 (t=8.1)** | 0.329 |
| 24M | 0.3837 (t=15.7) | **0.3357 (t=5.0)** | 0.424 |
| 36M | 0.3424 (t=13.4) | **0.1880 (t=3.0)** | 0.448 |

The 3-month spread in the 11-year window the published model never saw is *identical* to
the in-sample estimate (0.108); 12M/24M retain ~90% of their magnitudes; 36M roughly halves
but stays significant at the 1% level.

## Parameter drift worth flagging (for the update draft)

Industry-quarter medians (cumulative spec):

| | 1986–2024 | post-2014 only | JFE 1986–2013 |
|---|---|---|---|
| κ | 0.9872 | 0.9932 | 0.985 |
| ω | 0.9249 | 0.9459 | 0.92 |
| μ (q) | 0.0086 | 0.0024 | ~0.013 |
| b_btm | 0.0226 | 0.0168 | 0.025 |
| b_roe | 0.2405 | 0.2207 | 0.232 |

- Long-run expected **log** return μ has compressed toward zero post-2014 (firm-level
  median even turns slightly negative by 2024, with the ½·σ² adjustment keeping expected
  simple returns positive) — the equity-yield-curve level shifts down materially in the
  updated Fig 2.
- κ estimates drift toward the 0.9999 clip in recent rolling windows (b_btm near zero in
  15-year windows dominated by the post-2007 "value winter").

## Fig-2 feed

`out/medianparams_CURRsampleall.dta` + `out/MedianParams_CURRsampleall.csv`: 156 quarters
(1986Q1–2024Q4) of per-quarter cross-firm medians — rolling and cum parameter sets,
median btm and lroe, and `var_cum` (expanding firm-level variance of quarterly log returns,
firms with ≥30 quarters) — same columns the legacy `plots_code.m` consumed, ready for the
equity-yield-curve web tool.

## Aggregate market prediction (Table 9, LW side) — 2026-09-05

Port: `stata/agg_predict.do` (recursive OLS + robust rreg on EW aggregates of btm/lroe,
forecasts with lagged coefficients, expanding-mean benchmark from 1971, ENC-NEW + R2_OS).
Evaluation on 1986Q1–2013Q3 (111 forecasts), robust spec (the paper's stated design):

| | replication | published |
|---|---|---|
| Panel B slope | 0.4888 (t=1.87) | 0.4936 (t≈1.9) |
| Panel B R² | 3.1% | 3.2% |
| ENC-NEW | 7.76 (≫1% CV ≈2.1 → p<0.01) | p<0.01 |
| R²_OS | 0.21% | 0.62% |

Slope/R²/ENC-NEW verdicts replicate; the R²_OS level is benchmark-sensitive (same sign
and order). **Update**: full 1986–2024 R²_OS 1.3–1.6%, ENC-NEW ≈ 11; **true OOS 2014Q1–2024Q4:
R²_OS 5.6–9.1%, slope 0.86–0.92 (t≈2.2)** — the aggregate predictor strengthened materially
after publication. Kelly-Pruitt comparison side not yet ported.

## Figure 2 (expected return curves) — 2026-09-05

Data chain validated: per-quarter medians from the regenerated frozen panel match the
published `Excel/MedianParams(20140310).csv` **to float precision on all 12 parameter/median
columns** (max reldif ≈ 5e-8); `var_cum` within 0.6% (different-but-equivalent expanding
variance routine; ≈0.04pp effect on the curve). `figs/fig2_surface.py` (Python port of
plots_code.m) renders:
- `fig2_replication_1986_2013.(png|pdf)` from the published `Graphs/data.xlsx` — range
  5.6–16.4% annualized, same topology as the published surface.pdf;
- `fig2_updated_1986_2024.(png|pdf)` from `out/MedianParams_CURRsampleall.csv` — range
  5.2–17.4%; overlap-period medians differ from published inputs by ~1pp on average
  (vendor drift + var routine).

## Frozen-parameter split ("world changed" vs "estimates changed") — 2026-09-05

`figs/fig2_frozen_split.py`: parameters frozen at the published 2013Q3 values
(μ=0.64%/q, κ=0.9913, cbm=0.0186, croe=0.1937 from the published data.xlsx) applied to
updated states; identical var_cum series in both versions, so the gap isolates parameter
drift. 2024Q4 curve:

| | 3M | 30Y | 30Y−3M |
|---|---|---|---|
| frozen (published) params | 8.03% | 9.52% | **+1.49pp** |
| re-estimated | 5.37% | 5.45% | +0.08pp |

Mean 30Y−3M slope 2014–2024: frozen +1.61pp vs re-estimated +0.60pp. Conclusion: under the
*published* model, today's states (elevated valuations → low btm) imply a curve still at
~8% and clearly upward-sloping; the 2024 flatness-at-5.4% in the re-estimated version is
mostly **parameter drift** (μ compression toward/below zero, κ at the clip, near-zero
b_btm in post-2007 windows), not a change in the states. Outputs:
`figs/fig2_frozen_surface_2014_2024.*`, `figs/fig2_split_lines.*`.

## Diagnosing the parameter drift (`stata/diag_covid.do` / `diag_covid2.do`) — 2026-09-05

Three findings on what moved the estimates:

1. **b_btm (and hence κ) collapse predates COVID.** Rolling-60q industry-median b_btm:
   0.015 (2005) → ~0.010 (2008–12) → 0.006–0.008 (2014–17) → **bottom 0.0009–0.0021 in
   2018–19** → recovers to 0.003–0.0075 in 2020–23 (2021–22 value rally). Classic value
   winter; COVID-era cross-sections actually *rebuilt* some slope. κ→clip is mechanical
   (κ = (1−b_btm)/ρ).
2. **COVID did damage b_lroe.** 2024Q4 cumulative estimation excluding COVID return-quarters
   (2020Q1–2021Q4): b_lroe rises 0.216 → **0.251** (its historical level); b_btm unchanged
   (0.0142). Lockdown/reopening earnings chaos made current roe a temporarily bad predictor.
3. **μ compression is a return-level + dispersion story, mostly 2022–24.** Era means of
   pooled quarterly firm log returns: −1.8% (1986–2007), −1.1% (2008–13), **−3.9% (2014–19)**,
   **+4.7% (2020–21)**, **−7.2% (2022–24, SD 0.395 = sample max)**. Excluding COVID makes μ
   *more* negative (−0.28% → −0.59%/q); excluding 2015–2020 restores μ to ~0 and b_btm to
   0.016. Record cross-sectional dispersion in 2022–24 is variance drag on mean log returns
   (var_cum 0.032 → 0.047), widening the wedge between log-μ and simple expected returns.

## Remaining for task 6
1. CIZ migration for 2025 returns (msf_v2 mthret embeds delistings; rebuild size-decile
   benchmark returns from stkmthsecuritydata + cap deciles).
2. Analysis-stage port: validation regressions (cluster2/xtfmb, slope-vs-1 tests),
   summarizeparam/term Excel exhibits, aggregate (Kelly-Pruitt/ENC-NEW) update.
3. samplenopenny variant; IV columns of all exhibits.
