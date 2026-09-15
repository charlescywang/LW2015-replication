*** est_params.do — unified parameter estimation
*** Replaces legacy estimate.do / estimate2.do / estimate_a.do / estimate_cumall.do.
*** Faithful to estimate.do semantics: per (FF48 industry x dateid) window,
***   - inputs winsorized WITHIN the industry-window sample at $WINSOR_IN per tail
***     via SSC winsor; on winsor failure (small samples) fall back to raw values
***   - rolling window = [date-($WINDOW-1), date]; cumulative = (-inf, date]
***   - OLS: reg ldrr_3 btm_w lroe_w ; IV: lroe instrumented by its lag (llroe)
***   - first-stage F saved from reg lroe_w llroe_w btm_w on the IV e(sample)
*** Differences from legacy (intentional): postfile instead of matrix accumulation
*** (no -9999 sentinels; failed windows get missing directly), per-industry frames
*** (fast subsetting), ivregress 2sls instead of retired ivreg (same estimator).
***
*** Inputs : current frame holding ffcd dateid btm lroe llroe ldrr_3 + sample flag
*** Args   : 1=tag 2=sample 3=ff_lo 4=ff_hi   (3/4 optional, default 1 48)
*** Outputs: $OUT/roemodel_{ols,iv}_pool{,2}_lroe_<tag><sample>.dta  (legacy layouts)

program define est_params
    args tag sample ff_lo ff_hi
    if "`ff_lo'" == "" local ff_lo 1
    if "`ff_hi'" == "" local ff_hi 48
    local W = $WINDOW - 1

    qui su dateid, meanonly
    local maxd = r(max)

    tempname hOR hOC hIR hIC
    postfile `hOR' ffcd dateid _rc_parm_pool double(coeff_btm_pool coeff_lroe_pool coeff_cons_pool) n_pool using "$OUT/_res_ols_pool.dta", replace
    postfile `hOC' ffcd dateid _rc_parm_pool2 double(coeff_btm_pool2 coeff_lroe_pool2 coeff_cons_pool2) n_pool2 using "$OUT/_res_ols_pool2.dta", replace
    postfile `hIR' ffcd dateid _rc_parm_iv_pool double(coeff_btm_iv_pool coeff_lroe_iv_pool coeff_cons_iv_pool) n_iv_pool double(FirstStageF_iv_pool) using "$OUT/_res_iv_pool.dta", replace
    postfile `hIC' ffcd dateid _rc_parm_iv_pool2 double(coeff_btm_iv_pool2 coeff_lroe_iv_pool2 coeff_cons_iv_pool2) n_iv_pool2 double(FirstStageF_iv_pool2) using "$OUT/_res_iv_pool2.dta", replace

    forvalues ff = `ff_lo'/`ff_hi' {
        di as text "est_params: industry `ff' / `ff_hi'  " c(current_time)
        cap frame drop __work
        frame put dateid btm lroe llroe ldrr_3 if ffcd == `ff' & `sample' == 1, into(__work)
        frame __work {
            forvalues d = 1/`maxd' {
                foreach wtype in roll cum {
                    if "`wtype'" == "roll" local wcond "dateid <= `d' & dateid >= `d'-`W'"
                    else                   local wcond "dateid <= `d'"

                    cap winsor btm if `wcond', gen(btm_w) p($WINSOR_IN)
                    if _rc != 0 gen btm_w = btm
                    cap winsor lroe if `wcond', gen(lroe_w) p($WINSOR_IN)
                    if _rc != 0 gen lroe_w = lroe
                    cap winsor llroe if `wcond', gen(llroe_w) p($WINSOR_IN)
                    if _rc != 0 gen llroe_w = llroe

                    *** OLS
                    cap qui reg ldrr_3 btm_w lroe_w if `wcond'
                    local rc = _rc
                    if "`wtype'" == "roll" local h `hOR'
                    else                   local h `hOC'
                    if `rc' == 0 post `h' (`ff') (`d') (0) (_b[btm_w]) (_b[lroe_w]) (_b[_cons]) (e(N))
                    else         post `h' (`ff') (`d') (`rc') (.) (.) (.) (.)

                    *** IV (lroe instrumented by its own lag)
                    cap qui ivregress 2sls ldrr_3 btm_w (lroe_w = llroe_w) if `wcond'
                    local rc = _rc
                    if `rc' == 0 {
                        local bb = _b[btm_w]
                        local bl = _b[lroe_w]
                        local bc = _b[_cons]
                        local nn = e(N)
                        cap qui reg lroe_w llroe_w btm_w if e(sample)
                        if _rc == 0 local FF = e(F)
                        else        local FF = .
                        if "`wtype'" == "roll" post `hIR' (`ff') (`d') (0) (`bb') (`bl') (`bc') (`nn') (`FF')
                        else                   post `hIC' (`ff') (`d') (0) (`bb') (`bl') (`bc') (`nn') (`FF')
                    }
                    else {
                        if "`wtype'" == "roll" post `hIR' (`ff') (`d') (`rc') (.) (.) (.) (.) (.)
                        else                   post `hIC' (`ff') (`d') (`rc') (.) (.) (.) (.) (.)
                    }

                    drop btm_w lroe_w llroe_w
                }
            }
        }
        frame drop __work
    }

    postclose `hOR'
    postclose `hOC'
    postclose `hIR'
    postclose `hIC'

    *** save in legacy file layouts
    preserve
    use "$OUT/_res_ols_pool.dta", clear
    sort ffcd dateid
    save "$OUT/roemodel_ols_pool_lroe_`tag'`sample'.dta", replace
    use "$OUT/_res_ols_pool2.dta", clear
    sort ffcd dateid
    save "$OUT/roemodel_ols_pool2_lroe_`tag'`sample'.dta", replace
    use "$OUT/_res_iv_pool.dta", clear
    sort ffcd dateid
    save "$OUT/roemodel_iv_pool_lroe_`tag'`sample'.dta", replace
    use "$OUT/_res_iv_pool2.dta", clear
    sort ffcd dateid
    save "$OUT/roemodel_iv_pool2_lroe_`tag'`sample'.dta", replace
    foreach f in _res_ols_pool _res_ols_pool2 _res_iv_pool _res_iv_pool2 {
        erase "$OUT/`f'.dta"
    }
    restore
end
