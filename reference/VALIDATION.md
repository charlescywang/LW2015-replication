# Replication engine validation log

## 2026-09-05 — FRESH-DATA REPLICATION (task 5) ✅

Full chain on the fresh WRDS pull (`run_fresh_replication.do`, tag FRESH, sampleall):
master 799,645 firm-quarters, dateid 1–171 (1971Q1–2013Q3; frozen master: 800,247).

**Parameter medians (dateid ≥ 61, cumulative), FRESH vs frozen-engine vs published:**
| | cons | btm | lroe | κ | ω | μ |
|---|---|---|---|---|---|---|
| FRESH (2026 data) | 0.0080 | 0.0260 | 0.2514 | 0.9838 | 0.9175 | 0.0118 |
| frozen data, new engine | 0.0081 | 0.0257 | 0.2469 | 0.9841 | 0.9180 | 0.0117 |
| published Table 1 | ~0.009 | ~0.025 | ~0.232 | 0.985 | 0.92 | ~0.013 |

Vendor drift at the industry-quarter level: coefficient p50 reldif ≈ 7–9e-04, correlations
0.98–0.99 (μ's corr 0.57 is outlier-driven; its median reldif is 9.4e-04).

**EW decile market-adjusted log hedge returns (cum estimates, q10, dateid ≥ 61) vs published
JFE targets 0.109 / 0.329 / 0.424 / 0.448:**
- 3M: **0.1084** (t=10.8) · 12M: **0.3256** (t=16.0) · 24M: **0.4118** (t=16.1) · 36M: **0.4142** (t=15.0)

Decile means are cleanly monotone (−0.115 → −0.008 at 3M). Verdict: the JFE results
replicate on 2026-vintage WRDS data through the rationalized pipeline; 3M/12M essentially
exact, 24M/36M within 3–8% of published (consistent with the measured CRSP/link drift).

## 2026-09-05 — estimation layer vs frozen 2014 files (`sampleall`)

Engine (`stata/est_params.do` + `map_params.do`) run on inputs extracted from the frozen
`termregdata_compstat_final_rdq_roemodel_20140310sampleall.dta` (800,247 firm-quarters,
dateid 1–171 = 1971Q1–2013Q3), compared 1:1 against the frozen
`parameters_roemodel_lroe_20140310sampleall.dta` (48 industries × 170 dateids = 8,160 rows).

**Result: float-exact match.**
- All OLS coefficient columns (rolling `_pool` + cumulative `_pool2`): zero diffs beyond
  float-storage granularity (max reldif ≤ 1.9e-07; frozen files stored floats via `svmat`).
- All IV columns and first-stage Fs: same, except **24 windows at dateid 3–6 with N=2–3
  obs** where legacy `ivreg` produced just-identified estimates on 2–3 observations and
  modern `ivregress 2sls` correctly refuses. All are 14+ years before the analysis window
  (dateid ≥ 61), so no published number is affected. Documented, accepted.
- Structural parameters (κ, ω, μ, clipped versions): match; 2 borderline rows
  (ffcd 13/dateid 3, ffcd 40/dateid 45, reldif 1–3e-06) are float-input rounding amplified
  by near-zero denominators in the mapping (b0/(1−b2) with b2≈1.01; b2/b1 with b1≈0.003).

**Published-target medians** (ffcd×dateid level, dateid ≥ 61):
- cumulative: cons 0.0081, btm 0.0257, lroe 0.2469 → κ 0.9841, ω 0.9180, μ 0.0117/q
- rolling:    cons 0.0067, btm 0.0217, lroe 0.2278 → κ 0.9882, ω 0.9223, μ 0.0097/q
- Paper Table 1 headline (κ≈0.985, ω≈0.92, μ≈0.013) reproduced to reported precision on
  κ and ω; coefficient-level medians differ slightly from the published table because the
  paper summarizes at the firm level via the analysis file — to be nailed when the
  summarize/analysis stage is ported.

## Fresh WRDS pull vs frozen 2014 SAS panel — 2026-09-05

`pull/pull_gen4.R` (legacy2013 mode) produced 837,357 rows vs the frozen panel's 838,135.
Diff (`stata/diff_replica.do`), key = permno×fcdate:
- **99.23% of keys match** (2,864 replica-only, 3,642 frozen-only; thin spread across all
  years — CCM link and Compustat coverage revisions).
- Fundamentals near-identical on matched rows: ceqq 99.97% (tol 1e-6), eps 99.8%,
  cshprq 99.96%, rdq 99.95%, compdate 99.95%.
- Raw/delisting-adjusted returns: 97–98% agreement per era; the flagged "diffs" have
  median reldif ≈ 1.1–1.8e-06 → mostly float-storage granularity of the frozen file, with
  a real CRSP-revision tail of roughly 2% of windows (slightly larger in 2005–2013).
- **Genuine drift channels**: (1) FF48 industry differs on 4.3% of rows (Compustat header
  SIC changed since 2014 → some firms re-assigned; affects industry pooling composition);
  (2) market-/size-adjusted abnormal returns shift by median |Δ| ≈ 2e-5 (dbhar) to 2e-4
  (dbhsar) from CRSP index and size-decile revisions — immaterial vs hedge spreads.

## gen_term layer — 2026-09-05

`stata/validate_genterm.do`: gen_term run on frozen-panel inputs (btm, lroe, mcap) with the
frozen parameter file, compared 1:1 on permno×yearquarter against the frozen final panel
(N = 800,247). **Bit-identical**: max reldif 0.00e+00 on mu1/mu4/mu12 rolling, cumulative,
IV, and winsorized (_w01) term-structure variables; zero missing-status mismatches; zero
quantile-rank mismatches (q5, q10, within-industry q5i). The firm-level layer of the engine
is exact.
