*** make_medianparams.do — per-quarter cross-firm medians of parameters, btm, lroe, plus
*** the expanding firm-level variance of quarterly log returns (firms with >= 30 quarters).
*** This is the data feed behind the paper's Figure 2 ("Expected return curves").
*** Args: 1 = final panel path  2 = tag  3 = sample

program define make_medianparams
    args finalpath tag sample

    use permno yearquarter dateid btm lroe drr_3 mu_pool_w k_pool0_w coeff_cons_pool coeff_btm_pool coeff_lroe_pool ///
        mu_pool2_w k_pool20_w coeff_cons_pool2 coeff_btm_pool2 coeff_lroe_pool2 using "`finalpath'", clear
    gen double ldrr_3 = log(1 + drr_3)
    sort permno dateid
    by permno: gen double _cn  = sum(!missing(ldrr_3))
    by permno: gen double _cs  = sum(cond(missing(ldrr_3), 0, ldrr_3))
    by permno: gen double _css = sum(cond(missing(ldrr_3), 0, ldrr_3^2))
    gen double var_cum = (_css - _cs^2/_cn)/(_cn - 1) if _cn >= 30
    drop _cn _cs _css
    keep if dateid >= $OOS_START
    collapse (p50) mu_pool_w k_pool0_w coeff_cons_pool coeff_btm_pool coeff_lroe_pool ///
                   mu_pool2_w k_pool20_w coeff_cons_pool2 coeff_btm_pool2 coeff_lroe_pool2 ///
                   btm lroe var_cum, by(yearquarter)
    gen year = year(dofq(yearquarter))
    gen quarter = quarter(dofq(yearquarter))
    order yearquarter year quarter
    save "$OUT/medianparams_`tag'`sample'.dta", replace
    export delimited using "$OUT/MedianParams_`tag'`sample'.csv", replace
    di as result "medianparams: $OUT/MedianParams_`tag'`sample'.csv (" _N " quarters)"
end
