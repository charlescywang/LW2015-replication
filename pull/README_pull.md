# replication2026/pull — WRDS data pull for the Lyle & Wang (2015 JFE) replication

## `pull_gen4.R`

R / WRDS-Postgres translation of the legacy SAS "Gen-4" pull

> `Codes/SAS/Obtain Data to Estimate Term Structure (CompuStat Only and RDQ Based Merge) (2014 Update).sas`

which produced the frozen `Data/capd_analysis_compstat_rdq_2014.sas7bdat`, the input to
`Create Basic Regression Dataset (March 10, 2014).do`. The authoritative audit of the SAS
ground truth is `docs/deep-read-2026-08-31/sas_code.md` (sections 1, 2.5, 6); every numbered
step in the script cites the SAS block it replicates.

### What it replicates

1. **Compustat fundq pull** — C/INDL/STD/D, `exchg` 11–19 excl. 16, `curncdq='USD'`,
   `fyearq>=0`; the full Gen-4 item list (incl. the folded-in `oibdpq…lctq` extras).
2. **Header SIC** from `comp.namesq` (`dnum`, copied to `sic`) and the hard-coded **FF48**
   block (`ffin`), ported range-for-range.
3. **CCM link** (`crsp.ccmxpf_lnkhist`, LC/LU, `linkdt <= date <= coalesce(linkenddt, today)`,
   non-missing `lpermco`), header GICS `gind` as `gics6` (from `comp.company`, the successor
   to the SAS `ccm.comphead`), and the nodupkey by gvkey–permno–datadate.
4. **Gen-4 RDQ availability date**: `compdate = rdq`; missing rdq, rdq < datadate, or
   rdq − datadate > 90 all → `datadate + 90 days`.
5. **Quarter-end grid** (last trading day of Mar/Jun/Sep/Dec from `crsp.msi`) and the
   closest-match merge (`0 <= months(compdate→prc_date) <= 3`, closest by signed day count),
   with **both dedups** — including the Gen-4 merger fix (final dedup by `permno × prc_date`,
   not gvkey–permno).
6. **Returns machinery** in log space from `crsp.msf` × `crsp.msi` × `crsp.ermport1`
   (inner join to ermport1, so permno-months without a size-decile row drop out of *all*
   horizon sums — a deliberate SAS quirk we preserve), Beaver–McNichols–Price delisting
   returns from `crsp.msedelist` (month-end vs mid-month timing, `dlret=-1 → log(1e-4)`,
   missing → 0, compounded into `drr`), forward sums over +3/+12/+24/+36 months,
   `exp(sum)−1` conversion of **every** series (incl. market and size-decile) *before*
   differencing, cutoff blanking (`ddd < h`), and `dbhar_h = drr_h − mr_h`,
   `dbhsar_h = drr_h − sdr_h` as differences of simple returns — the exact SAS order.
7. **Identifiers and prices**: `exchcd/ticker/comnam` from `crsp.msenames`
   (`namedt <= fcdate <= nameendt`); `price/shrout/mcap` at `fcdate` and `_m1`
   (prior month) from raw `crsp.msf`.

Output: `~/ErTerm_bigdata/capd_replica_<mode>.dta` (haven, Stata 14), lowercase names
matching the frozen file where they overlap.

### Two modes

| | `legacy2013` | `current` |
|---|---|---|
| returns cutoff (`ddd`) | 2013-12-30 (as in the SAS) | max `crsp.msi` date (2024-12-31 as of writing) |
| fundq datadate | ≤ 2013-09-30 | ≤ cutoff |
| quarter-end grid | ≤ 2013-12-31 | ≤ cutoff |
| CRSP tables | legacy SIZ (`msf`, `msi`, `msedelist`, `ermport1`) | same SIZ tables |

Run: `Rscript pull_gen4.R [legacy2013|current] [test]`. The `test` flag restricts to
`permno %% 997 == 0` (a ~26-permno hash subsample) and writes `capd_replica_test.dta` —
use it to smoke-test after any edit. Requires `~/.Rprofile` to provide a live WRDS
Postgres connection object named `wrds`.

### Known intentional deviations from the SAS

- **No trailing-window return sums** (SAS `r_m11…r_m0`) and no trailing abnormal returns;
  consequently the SAS **`DBHAR_m*` overwrite bug** (size-adjusted values silently clobbering
  the market-adjusted trailing series; `DBHSAR_m*` never created) is **not** reproduced.
  Nothing downstream consumes trailing abnormal returns. `price_m1/shrout_m1/mcap_m1`
  (which the Stata builder does use) are kept.
- **+48 and +60 month horizons omitted** (not used downstream).
- `eqvol`, `eqto`, `spread` (volume/turnover/bid-ask) not pulled.
- `crsp.msf` pulled from **1969-01-01** (performance guardrail): FCDates before 1969 have
  missing returns/prices; the estimation sample starts 1971, so nothing downstream is affected.
- `cusip` is always the Compustat 8-char cusip. (In the SAS, a merge-order quirk let the CRSP
  msf header cusip from the `vol_*` datasets overwrite the Compustat cusip on most rows.)
- `ffin` labels truncated to 5 characters (`'Rubber'` → `'Rubbe'`) — this *matches* the frozen
  file: the SAS data step fixed FFIN's length at 5 from its first literal (`'Agric'`).
- If `crsp.msedelist` ever had two delist events in the same permno-month the script keeps the
  first and warns (the SAS left join would have duplicated the row and double-counted returns).
- Dedup tie-breaks (`nodupkey` keep-first) follow a deterministic sort in R; SAS tie order was
  arbitrary. Affects only the handful of near-identical duplicate rows (~479 + ~421 in the SAS logs).

### TODO — CIZ migration (data past 2024-12-31)

The SIZ-format CRSP monthly tables end at **2024-12-31** and will not be extended. A stub at
the bottom of `pull_gen4.R` documents the migration path (not yet implemented):

- `crsp.msf_v2` / `stkmthsecuritydata`: `mthcaldt`, `mthret` (**already includes delisting
  returns** — the entire `msedelist` step must be dropped, `drr := rr`), `mthretx`, `mthprc`, `shrout`.
- Market return: v2 monthly index tables replace `crsp.msi`.
- Size-decile returns: `ermport1` has no direct v2 twin — rebuild decile assignments from v2
  market caps (NYSE breakpoints, prior year-end membership) or use CRSP's v2 cap-decile indexes.
- A hybrid SIZ→CIZ splice must be verified permno-month by permno-month across the seam.

### Verification performed (2026-09-05)

- Table/column names confirmed by LIMIT-1 queries: `crsp.ermport1(permno,date,capn,decret)`,
  `crsp.msedelist(dlstdt,dlret)`, `crsp.msenames`, `crsp.msi` (max 2024-12-31), `crsp.msf`
  (1925-12 – 2024-12), `crsp.ccmxpf_lnkhist`, `comp.fundq`, `comp.namesq(sic)`, `comp.company(gind)`.
- Tiny end-to-end run (`legacy2013 test`): 1,139 rows × 60 cols, 26 permnos, fcdates
  1962-03-30 – 2013-12-31. Checks all passed: mcap ≡ price×shrout; compdate rules exact;
  0–3-month match window; cutoff blanking for all horizons; `rr_3`/`rr_12` equal to
  hand-compounded raw msf values to machine precision (incl. a firm with a 9-month truncated
  window); `price_m1` equals the raw prior-month `abs(prc)`; delisting compounding verified on
  permno 19940 (mid-month delist assigned to prior month) and permno 66799 (acquisition dlret
  0.012402 reconciles `dbhar_12` to 8 decimals).
