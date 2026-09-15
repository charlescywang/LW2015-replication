*** map_params.do — structural parameter mapping (replaces legacy cleanvars.do / cleanvars_a.do)
*** kappa = (1 - b_btm)/RHO, clipped to [0, KCLIP]
*** omega = (b_lroe/b_btm) / (1 + (b_lroe/b_btm)*RHO), clipped to [0, KCLIP]
*** mu    = b_cons / (1 - b_lroe), clipped to [-MUCLIP, MUCLIP]
*** dateid shifted +1 (parameters estimated with returns through t are usable at t+1),
*** max dateid dropped. Legacy fidelity notes: legacy cleanvars merged the four files
*** POSITIONALLY (first merge had no key vars); here all merges are keyed 1:1 ffcd dateid.
*** Args: 1=tag 2=sample. In/out: $OUT/roemodel_* -> $OUT/parameters_roemodel_lroe_<tag><sample>.dta

program define map_params
    args tag sample

    use "$OUT/roemodel_ols_pool_lroe_`tag'`sample'.dta", clear
    merge 1:1 ffcd dateid using "$OUT/roemodel_ols_pool2_lroe_`tag'`sample'.dta", assert(3) nogen
    merge 1:1 ffcd dateid using "$OUT/roemodel_iv_pool_lroe_`tag'`sample'.dta", assert(3) nogen
    merge 1:1 ffcd dateid using "$OUT/roemodel_iv_pool2_lroe_`tag'`sample'.dta", assert(3) nogen

    drop _rc_parm*
    replace dateid = dateid + 1

    local rho   = $RHO
    local kclip = $KCLIP
    local mclip = $MUCLIP

    foreach x in "" iv_ {
        gen k_`x'pool0    = (1 - coeff_btm_`x'pool) /`rho'
        gen k_`x'pool0_w  = max(min(`kclip', k_`x'pool0), 0) if !missing(k_`x'pool0)
        gen k_`x'pool20   = (1 - coeff_btm_`x'pool2)/`rho'
        gen k_`x'pool20_w = max(min(`kclip', k_`x'pool20), 0) if !missing(k_`x'pool20)
    }
    foreach x in "" iv_ {
        gen w_`x'pool0    = (coeff_lroe_`x'pool /coeff_btm_`x'pool ) / (1 + (coeff_lroe_`x'pool /coeff_btm_`x'pool )*`rho')
        gen w_`x'pool0_w  = max(min(`kclip', w_`x'pool0), 0) if !missing(w_`x'pool0)
        gen w_`x'pool20   = (coeff_lroe_`x'pool2/coeff_btm_`x'pool2) / (1 + (coeff_lroe_`x'pool2/coeff_btm_`x'pool2)*`rho')
        gen w_`x'pool20_w = max(min(`kclip', w_`x'pool20), 0) if !missing(w_`x'pool20)
    }
    foreach x in "" iv_ {
        gen mu_`x'pool    = coeff_cons_`x'pool / (1 - coeff_lroe_`x'pool)
        gen mu_`x'pool_w  = max(min(`mclip', mu_`x'pool), -`mclip') if !missing(mu_`x'pool)
        gen mu_`x'pool2   = coeff_cons_`x'pool2/ (1 - coeff_lroe_`x'pool2)
        gen mu_`x'pool2_w = max(min(`mclip', mu_`x'pool2), -`mclip') if !missing(mu_`x'pool2)
    }

    qui su dateid, meanonly
    drop if dateid == r(max)
    sort ffcd dateid
    save "$OUT/parameters_roemodel_lroe_`tag'`sample'.dta", replace
end
