*** run_all.do — Lyle & Wang (2015 JFE) replication: all Stata stages, end to end.
***
*** PREREQUISITES (run these from the package root FIRST — they need your own WRDS login,
*** see README section 2):
***     Rscript pull/pull_gen4.R legacy2013        ->  data/capd_replica_legacy2013.dta
***     Rscript pull/get_market.R                  ->  data/qmkt.dta
***
*** Then, from the package root:
***     stata-mp -b do run_all.do
***
*** Approximate runtime on an 8-core machine: 35-45 minutes.

clear all
set more off
include "config.do"

do "stata/build_regdata.do"
do "stata/est_params.do"
do "stata/map_params.do"
do "stata/gen_term.do"
do "stata/psort_u.do"
do "stata/agg_predict.do"
do "stata/make_medianparams.do"

*** dependency check
cap which winsor
if _rc {
    di as error "SSC package -winsor- is required:  ssc install winsor"
    exit 111
}
confirm file "$DATA/capd_replica_legacy2013.dta"

*** 1. master regression dataset (port of "Create Basic Regression Dataset (March 10, 2014)")
build_regdata "$DATA/capd_replica_legacy2013.dta" "$DATA/termregdata_2014.dta" "2013q4"

*** 2. estimation inputs
use "$DATA/termregdata_2014.dta", clear
egen dateid = group(yearquarter)
qui su dateid
di as result "master: N=" _N "  dateid 1-" r(max) "  (expect 171 = 1971Q1-2013Q3)"
gen double ldrr_3 = log(1 + drr_3)
gen double llroe = l.lroe
gen sampleall = 1
gen samplenopenny = (price_m1 >= 1)

*** 3. parameter estimation: FF48 x quarter, rolling + cumulative, OLS + IV  (~15 min)
est_params $VINTAGE $SAMPLE

*** 4. structural mapping: kappa, omega, mu (+ clips, out-of-sample dateid shift)
map_params $VINTAGE $SAMPLE

*** 5. firm-level term structures + quantile ranks  (~15 min)
gen_term "$DATA/termregdata_2014.dta" $VINTAGE $SAMPLE "$DATA/final_${VINTAGE}${SAMPLE}.dta"

*** 6. portfolio sorts and hedge returns (paper Table 4 analogues)
psort_u "$DATA/final_${VINTAGE}${SAMPLE}.dta" $SAMPLE $OOS_START mean "" "$OUT/hedge" "${VINTAGE}${SAMPLE}"

*** 7. aggregate market prediction (paper Table 9, LW side)
cap confirm file "$DATA/qmkt.dta"
if !_rc agg_predict "$DATA/final_${VINTAGE}${SAMPLE}.dta" $VINTAGE 61 171
else    di as error "data/qmkt.dta missing — run  Rscript pull/get_market.R  to enable the aggregate test"

*** 8. Figure-2 data feed (per-quarter median parameters)
make_medianparams "$DATA/final_${VINTAGE}${SAMPLE}.dta" $VINTAGE $SAMPLE

*** =====================================================================
*** 9. HEADLINE VALIDATION — compare your numbers to these targets
*** =====================================================================
di as result _n "===================== VALIDATION SUMMARY ====================="
use "$OUT/parameters_roemodel_lroe_${VINTAGE}${SAMPLE}.dta", clear
di as result _n "--- industry-median parameters, dateid >= $OOS_START ---"
di as text    "targets (published Table 1 / 2026 fresh-data run):"
di as text    "  kappa ~ 0.985 / 0.9838   omega ~ 0.92 / 0.9175   mu ~ 0.013 / 0.0118 per quarter"
tabstat coeff_cons_pool2 coeff_btm_pool2 coeff_lroe_pool2 k_pool20_w w_pool20_w mu_pool2_w ///
    if dateid >= $OOS_START, stat(p50) col(stat) format(%9.4f)

di as result _n "--- EW decile hedge returns, market-adjusted log, cum estimates ---"
di as text    "targets (published / 2026 fresh-data run):"
di as text    "  3M 0.109/0.108   12M 0.329/0.326   24M 0.424/0.412   36M 0.448/0.414"
foreach h in 3 12 24 36 {
    use "$OUT/hedge/hedgeret_15yr_q10_match_roemodel_lroe_cum_${VINTAGE}${SAMPLE}.dta", clear
    qui reg ldbhar_`h'
    di as result "  ldbhar_`h': mean " %7.4f _b[_cons] "  (t = " %5.2f _b[_cons]/_se[_cons] ")"
}
di as result _n "Done. See reference/VALIDATION.md for the full validation methodology."
