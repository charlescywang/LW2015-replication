*** t7_map_er.do — Table 7 branch: map NLSUR coefficients to structural parameters.
*** Faithful to Step 4 of the legacy ER Create Data files: dateid+1 shift (parameters
*** estimated through t are usable at t+1), rho = $RHO, kappa/omega clipped to
*** [0, $KCLIP], mu clipped to +/- $MUCLIP, sigma2 = 2*ln(A); last shifted dateid dropped.
*** Input : $OUT/er/roemodel_ols_pool2_lroe_ER_<tag><sample>.dta
*** Output: $OUT/er/parameters_roemodel_lroe_ER_<tag><sample>.dta

program define map_er
    args tag sample
    use "$OUT/er/roemodel_ols_pool2_lroe_ER_`tag'`sample'.dta", clear

    *** legacy cleaning: parameters from failed windows set missing (postfile already
    *** posts missing on failure; keep the flag drop for the legacy layout)
    foreach v in coeff_cons_pool2 coeff_btm_pool2 coeff_lroe_pool2 coeff_CONSA_pool2 n_pool2 {
        qui replace `v' = . if _rc_parm_pool2 != 0
    }

    qui su dateid, meanonly
    local dropd = r(max) + 1
    replace dateid = dateid + 1

    gen double k_pool20   = (1 - coeff_btm_pool2) / $RHO
    gen double k_pool20_w = max(min($KCLIP, k_pool20), 0) if missing(k_pool20) == 0

    gen double w_pool20   = (coeff_lroe_pool2/coeff_btm_pool2) / (1 + (coeff_lroe_pool2/coeff_btm_pool2)*$RHO)
    gen double w_pool20_w = max(min($KCLIP, w_pool20), 0) if missing(w_pool20) == 0

    gen double mu_pool2   = coeff_cons_pool2 / (1 - coeff_lroe_pool2)
    gen double mu_pool2_w = max(min($MUCLIP, mu_pool2), -$MUCLIP) if missing(mu_pool2) == 0

    gen double sigma2 = 2*log(coeff_CONSA_pool2)

    drop if dateid == `dropd'
    drop _rc_parm_pool2
    sort ffcd dateid
    save "$OUT/er/parameters_roemodel_lroe_ER_`tag'`sample'.dta", replace
end
