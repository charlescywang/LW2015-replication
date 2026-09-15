*** t7_est_er.do — Table 7 branch: constrained NLSUR estimation (ER pipeline).
*** Legacy sources:
***   "Term Structure in ER - Create Data ... (ER) (Jan 26 2014).do"  -> non-b spec
***       nlsur (ldrr_3 = {b0}+{b1}*btm+{b2}*lroe)
***             (DRR_3_w01 = {A}*exp({b0}+{b1}*btm+{b2}*lroe))
***       i.e. regressors RAW, only the level-return dep var winsorized. The frozen
***       workbook "Results (20140310) (RDQ) (ROE Model) (ER) (sampleall).xlsx"
***       (= the non-b run on 2014 data) matches the PUBLISHED Table 7 Panel A exactly.
***   "Term Structure in ER - Create Data ... (ER) (Mar 10 2014).do"  -> "b" spec
***       same system with btm/lroe ALSO winsorized within window (winsreg=="yes").
*** Per FF48 industry x CUMULATIVE (expanding) window only; DRR_3 = 1+drr_3
*** winsorized at $WINSOR_IN per tail within the industry-window sample in both specs.
***
*** Inputs : current frame must hold ffcd dateid btm lroe ldrr_3 DRR_3 + sample flag
*** Args   : 1=tag 2=sample 3=ff_lo 4=ff_hi 5=winsreg ("yes"="b" spec, "no"=published)
*** Output : $OUT/er/_res_er_<tag><sample>_<ff_lo>_<ff_hi>.dta (legacy pool2 layout + _rc)

program define est_er
    args tag sample ff_lo ff_hi winsreg
    if "`ff_lo'" == "" local ff_lo 1
    if "`ff_hi'" == "" local ff_hi 48
    if "`winsreg'" == "" local winsreg "no"

    qui su dateid, meanonly
    local maxd = r(max)

    tempname H
    postfile `H' ffcd dateid _rc_parm_pool2 ///
        double(coeff_cons_pool2 coeff_btm_pool2 coeff_lroe_pool2 coeff_CONSA_pool2) ///
        n_pool2 using "$OUT/er/_res_er_`tag'`sample'_`ff_lo'_`ff_hi'.dta", replace

    forvalues ff = `ff_lo'/`ff_hi' {
        timer clear 90
        timer on 90
        cap frame drop __work
        frame put dateid btm lroe ldrr_3 DRR_3 if ffcd == `ff' & `sample' == 1, into(__work)
        frame __work {
            forvalues d = 1/`maxd' {
                *** regressors: raw (published/non-b) or window-winsorized ("b")
                if "`winsreg'" == "yes" {
                    cap winsor btm if dateid <= `d', gen(x_btm) p($WINSOR_IN)
                    if _rc != 0 gen double x_btm = btm
                    cap winsor lroe if dateid <= `d', gen(x_lroe) p($WINSOR_IN)
                    if _rc != 0 gen double x_lroe = lroe
                }
                else {
                    gen double x_btm  = btm
                    gen double x_lroe = lroe
                }
                *** eq-2 dependent var always winsorized within window (both legacy specs)
                cap winsor DRR_3 if dateid <= `d', gen(DRR_3_w) p($WINSOR_IN)
                if _rc != 0 gen double DRR_3_w = DRR_3

                cap qui nlsur (ldrr_3  = {b0}+{b1}*x_btm+{b2}*x_lroe) ///
                              (DRR_3_w = {A}*exp({b0}+{b1}*x_btm+{b2}*x_lroe)) ///
                              if missing(x_lroe) == 0 & missing(x_btm) == 0 & dateid <= `d'
                local rc = _rc
                if `rc' == 0 post `H' (`ff') (`d') (0) (_b[/b0]) (_b[/b1]) (_b[/b2]) (_b[/A]) (e(N))
                else         post `H' (`ff') (`d') (`rc') (.) (.) (.) (.) (.)

                drop x_btm x_lroe DRR_3_w
            }
        }
        frame drop __work
        timer off 90
        qui timer list 90
        di as result "est_er[`tag']: industry `ff' done in " %8.1f r(t90) "s   " c(current_date) " " c(current_time)
    }
    postclose `H'
end
