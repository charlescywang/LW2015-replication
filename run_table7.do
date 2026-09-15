*** run_table7.do — OPTIONAL stage: Table 7 of the paper (expected NET/simple returns via
*** constrained nonlinear SUR), plus portfolio sorts on the expected-simple-return measure.
***
*** PREREQUISITE: run_all.do has completed (needs $DATA/termregdata_2014.dta).
*** Run from the package root:   stata-mp -b do run_table7.do
***
*** RUNTIME WARNING: the NLSUR system is fit per FF48 industry x expanding window
*** (48 x 171 fits) — expect roughly 45-75 minutes single-threaded. To parallelize,
*** call est_er in industry-range shards from separate Stata sessions
*** (est_er REP sampleall <ff_lo> <ff_hi> no) and append the shard files before map_er.
***
*** Published Table 7 Panel A targets (validated exactly on the frozen 2014 data):
***   mean:   Cons 0.0101  btm 0.0330  roe 0.1258  A 1.0346  k 0.9767  w 0.7230  mu 0.0116
***   median: Cons 0.0115  btm 0.0314  roe 0.0871  A 1.0334  k 0.9784  w 0.7595  mu 0.0124
***   E(R): mean 0.0289/q (12.07% annualized), median 0.0291/q
*** 2026 fresh-data ER-sorted decile hedge (simple returns, 1986Q1-2013Q3):
***   market-adjusted 0.0594/q (t=8.3); size-adjusted 0.0506/q (t=7.6)

clear all
set more off
include "config.do"
cap mkdir "$OUT/er"

do "stata/est_er.do"
do "stata/map_er.do"
do "stata/gen_er.do"

cap which winsor
if _rc {
    di as error "SSC package -winsor- is required:  ssc install winsor"
    exit 111
}
confirm file "$DATA/termregdata_2014.dta"

*** 1. estimation inputs
use "$DATA/termregdata_2014.dta", clear
egen dateid = group(yearquarter)
gen double ldrr_3 = log(1 + drr_3)
gen sampleall = 1
gen samplenopenny = (price_m1 >= 1)
gen double DRR_3 = 1 + drr_3

*** 2. NLSUR estimation (published spec: raw regressors, level dep var winsorized)
est_er REP $SAMPLE 1 48 no

*** 3. collect + structural mapping + firm-level ER panel
use "$OUT/er/_res_er_REP${SAMPLE}_1_48.dta", clear
sort ffcd dateid
save "$OUT/er/roemodel_ols_pool2_lroe_ER_REP${SAMPLE}.dta", replace
map_er REP $SAMPLE
gen_er "$DATA/termregdata_2014.dta" REP $SAMPLE "$DATA/final_ER_REP${SAMPLE}.dta"

*** 4. Panel A summary vs published targets
use "$OUT/er/parameters_roemodel_lroe_ER_REP${SAMPLE}.dta", clear
keep if dateid >= $OOS_START
di as result _n "=== Table 7 Panel A analogue (industry-quarter estimates, dateid >= $OOS_START) ==="
di as text    "targets: A 1.0346/1.0334  kappa 0.9767/0.9784  omega 0.7230/0.7595  mu 0.0116/0.0124 (mean/median)"
tabstat coeff_cons_pool2 coeff_btm_pool2 coeff_lroe_pool2 coeff_CONSA_pool2 k_pool20_w w_pool20_w mu_pool2_w, ///
    stat(mean p50) col(stat) format(%9.4f)

*** 5. portfolio sorts on the expected SIMPLE return (er1), realized simple spreads
use permno yearquarter dateid er1_cum_15yr dbhar_3 dbhsar_3 using "$DATA/final_ER_REP${SAMPLE}.dta", clear
keep if dateid >= $OOS_START & !missing(er1_cum_15yr)
forvalues p = 1/9 {
    local pp = `p'*10
    egen p`p' = pctile(er1_cum_15yr), by(yearquarter) p(`pp')
}
gen d10 = 1 if er1_cum_15yr < p1
forvalues q = 2/9 {
    local lo = `q'-1
    replace d10 = `q' if p`lo' <= er1_cum_15yr & er1_cum_15yr < p`q'
}
replace d10 = 10 if er1_cum_15yr >= p9 & !missing(er1_cum_15yr)
collapse (mean) dbhar_3 dbhsar_3, by(d10 yearquarter)
keep if inlist(d10, 1, 10)
foreach v in dbhar_3 dbhsar_3 {
    replace `v' = -`v' if d10 == 1
}
collapse (sum) dbhar_3 dbhsar_3, by(yearquarter)
replace dbhar_3  = . if yearquarter >= qofd(td($RET_CUTOFF))
replace dbhsar_3 = . if yearquarter >= qofd(td($RET_CUTOFF))
save "$OUT/er/hedgeret_ER_simple_REP${SAMPLE}.dta", replace
di as result _n "=== ER-sorted decile hedge, realized SIMPLE returns (targets 0.0594 t=8.3; 0.0506 t=7.6) ==="
foreach v in dbhar_3 dbhsar_3 {
    qui reg `v'
    di as result "`v': " %6.4f _b[_cons] "/q  (t = " %4.1f _b[_cons]/_se[_cons] ")"
}
di as result _n "Done. Firm-level ER panel: $DATA/final_ER_REP${SAMPLE}.dta"
