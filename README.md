# Replication package — Lyle & Wang (2015)

**Paper:** Matthew R. Lyle and Charles C.Y. Wang, "The cross section of expected holding
period returns and their dynamics: A present value approach," *Journal of Financial
Economics* 116 (2015) 505–525.

This package rebuilds the paper's core results from raw WRDS data: the pooled
industry-level estimation of the present-value model, firm-level expected-return term
structures, the decile portfolio sorts (Table 4), the aggregate market-prediction test
(Table 9, LW side), and the expected-return-curve surface (Figure 2). It is a modernized,
consolidated port of the original 2014 SAS + Stata code, **validated against the original**:
run on the frozen 2014 data, the estimation layer reproduces the original parameter files
to float precision and the firm-level term structures bit-identically (see
`reference/VALIDATION.md`). No CRSP/Compustat data are included — you pull them with your
own WRDS account.

## 1. Requirements

- **WRDS account** with access to CRSP, Compustat, and the CRSP/Compustat Merged links
  (standard academic subscription).
- **Stata 17+** (MP recommended; a full run is ~35–45 minutes on 8 cores).
  One SSC package: `ssc install winsor`.
- **R 4.x** with packages `DBI`, `RPostgres`, `data.table`, `haven`.
- **Python 3.10+** with `pandas`, `numpy`, `matplotlib`, `openpyxl` (figures only).
- ~6 GB free disk for the pulled data.

## 2. One-time setup: WRDS credentials

The pull scripts expect an R connection object named `wrds` created at R startup.
Add this to your `~/.Rprofile` (replace with your own WRDS username):

```r
library(RPostgres)
wrds <- dbConnect(Postgres(),
                  host = "wrds-pgdata.wharton.upenn.edu",
                  port = 9737,
                  user = "YOUR_WRDS_USERNAME",
                  password = "YOUR_WRDS_PASSWORD",   # or use ~/.pgpass instead
                  sslmode = "require",
                  dbname = "wrds")
```

(Storing the password in `~/.pgpass` with mode 600 is better practice than putting it in
`.Rprofile`; see the WRDS documentation.)

## 3. Running it

From the **package root**, three commands:

```bash
# (1) data pull: Compustat fundq + CCM link + CRSP returns, RDQ-based merge (~20 min)
Rscript pull/pull_gen4.R legacy2013

# (2) market index series for the aggregate test (~1 min)
Rscript pull/get_market.R

# (3) all Stata stages: build -> estimate -> term structures -> sorts -> aggregate (~40 min)
stata-mp -b do run_all.do
```

Then optionally render Figure 2:

```bash
python3 figs/fig2_surface.py
```

Outputs land in `out/` (parameters, hedge returns, median-parameter series, figures);
large intermediates in `data/`. The end of `run_all.log` prints a **validation summary**
comparing your numbers against the published targets and against our 2026 fresh-data run.

## 4. What you should get

Industry-median parameters (recursive estimates, 1986Q1–2013Q3):

| | κ | ω | μ (per quarter) |
|---|---|---|---|
| published Table 1 | ≈0.985 | ≈0.92 | ≈0.013 |
| 2026 fresh-data run | 0.9838 | 0.9175 | 0.0118 |

EW decile hedge returns (market-adjusted log, horizon-matched, 1986Q1–2013Q3):

| horizon | published | 2026 fresh-data run |
|---|---|---|
| 3M | 0.109 | 0.108 (t=10.8) |
| 12M | 0.329 | 0.326 (t=16.0) |
| 24M | 0.424 | 0.412 (t=16.1) |
| 36M | 0.448 | 0.414 (t=15.0) |

Aggregate prediction (Table 9, LW side, robust spec): slope ≈ 0.49 (t≈1.9), R² ≈ 3%,
ENC-NEW ≫ 1% critical value. Your numbers will differ slightly from both columns —
CRSP/Compustat are living databases (link revisions, restatements, index recomputations);
`reference/VALIDATION.md` quantifies that drift (≈0.8% of firm-quarter keys, ≈2% of
return windows, 4.3% of FF48 assignments as of 2026).

## 5. Package layout

```
run_all.do            master Stata driver (run from package root)
config.do             every constant of the estimation design, in one place
pull/pull_gen4.R      WRDS pull replicating the original SAS "Gen-4" build
                      (RDQ-timed merge, delisting-adjusted returns, horizon windows)
pull/get_market.R     CRSP index quarterly log returns
pull/README_pull.md   pull design notes: modes, intentional deviations from the SAS
stata/build_regdata.do   master dataset construction (btm, log ROE, filters)
stata/est_params.do      FF48 x quarter rolling + cumulative OLS & IV estimation
stata/map_params.do      structural mapping to kappa, omega, mu (+ clips, OOS shift)
stata/gen_term.do        firm-level term structures mu{1,4,8,12} + quantile ranks
stata/psort_u.do         portfolio sorts and hedge returns (Table 4)
stata/agg_predict.do     aggregate market prediction (Table 9, LW side)
stata/make_medianparams.do  Figure-2 data feed
figs/fig2_surface.py     Figure 2 surface (Python port of the original Matlab)
reference/               validation methodology + published Figure-2 inputs
```

## 6. Design notes for students

- **Timing:** accounting data enter on RDQ earnings-announcement dates (missing/early RDQ
  → datadate + 90 days); forecasts form at calendar quarter-ends; parameters estimated
  through quarter *t* are only used from *t+1* (strictly out-of-sample).
- **Estimation:** within each FF48 industry and quarter, pooled OLS of next-quarter log
  return on log book-to-market and log gross ROE, inputs winsorized 0.5%/tail within each
  estimation window; both a 60-quarter rolling and an expanding window; an IV variant
  instruments ROE with its own lag. Structural mapping: κ=(1−β₁)/ρ, ω=(β₂/β₁)/(1+(β₂/β₁)ρ),
  μ=β₀/(1−β₂) with ρ=0.99.
- **Known original-code quirks intentionally not reproduced:** the SAS trailing-window
  DBHAR overwrite bug; inconsistent long-horizon truncation dates across the six original
  psort variants (this package derives truncation from `RET_CUTOFF`); positional (unkeyed)
  merges. See `pull/README_pull.md` and `reference/VALIDATION.md`.
- **Data license:** CRSP and Compustat data may not be redistributed. This package
  contains code and published-paper aggregates only.

## 7. Optional stage: Table 7 — expected net (simple) returns

After `run_all.do`, `stata-mp -b do run_table7.do` estimates the paper's Section 4.4
calibration: a constrained nonlinear SUR per FF48 industry x expanding window that adds a
level-return equation and identifies `A = exp(sigma^2/2)`, giving expected NET returns
`E[R] = A*exp(mu)-1`. It then sorts portfolios on the expected simple return. Runtime:
~45-75 minutes single-threaded (see the header for how to shard). Validation targets are
printed at the end (Panel A: A 1.0346, kappa 0.9767, omega 0.7230, mu 0.0116 — exact on
the frozen 2014 data; ER-sorted simple-return decile hedge 0.0594/q (t=8.3) market-adjusted
on the 2026 fresh pull). Note the published Table 7 uses the RAW-regressor NLSUR spec
(only the level dependent variable winsorized within window); `est_er`'s last argument
switches to the winsorized-regressor variant.

## 8. Provenance

Package assembled 2026-09 from the rationalized replication codebase, which was validated
in two stages: (i) against the frozen March-2014 estimation outputs (float-exact
coefficients; bit-identical firm-level term structures), and (ii) end-to-end on a fresh
2026 WRDS pull (tables above). Questions: Charles C.Y. Wang.
