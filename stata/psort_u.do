*** psort_u.do — unified portfolio-sort program.
*** Replaces the six legacy clones (psort, psort_ind, psort_a, psort_a_ind, psort_cumall,
*** psort_ind_cumall) and both their internal mean/median passes.
*** Design (faithful to psort.do, Mar-22-2014 vintage):
***   - horizon matching: mu1 -> 3m returns, mu4 -> 12m, mu8 -> 24m, mu12 -> 36m
***   - sorts on the RAW-mu quantile ranks assigned in gen_term (not the _w01 versions)
***   - equal-weighted (or median) per quantile-quarter; hedge = top minus bottom
***     (negate quantile 1, keep {1, top}, sum by quarter)
***   - long-horizon truncation derived from $RET_CUTOFF (config) instead of hard-coded
***     quarters — this reproduces psort.do's 2013q1/2012q1/2011q1 for the 2014 build and
***     silently FIXES the stale dates bug in legacy psort_ind/psort_cumall
*** Args: 1=input final panel path  2=sample  3=dateid floor  4=stat (mean|median)
***       5=ind ("" = overall ranks, "i" = within-industry ranks)  6=output stub dir
***       7=output tag (e.g. 20140310sampleall)
*** Outputs: `6'/hedgeret_... and `6'/quantret_... in legacy layouts (one file per
***          estimator x quantile-scheme, rolling and cum merged side by side).

program define psort_u
    args inpath sample dfloor stat ind outdir tag
    if "`stat'" == "" local stat "mean"
    local med = cond("`stat'" == "median", "med_", "")

    *** horizon truncation quarters implied by the returns cutoff
    local cutq = qofd(td($RET_CUTOFF))
    local t12 = `cutq' - 3    // first formation quarter whose 12m window passes the cutoff
    local t24 = `cutq' - 7
    local t36 = `cutq' - 11

    foreach x in "" _iv {
        foreach y in q5 q10 {
            local top = cond("`y'" == "q5", 5, 10)

            foreach w in "" _cum {
                use yearquarter dateid `sample' ///
                    mu1`x'`w'_15yr_`y'`ind' mu4`x'`w'_15yr_`y'`ind' ///
                    mu8`x'`w'_15yr_`y'`ind' mu12`x'`w'_15yr_`y'`ind' ///
                    mu1`x'_15yr_q5 dbhar_3 dbhsar_3 dbhar_12 dbhsar_12 ///
                    dbhar_24 dbhsar_24 dbhar_36 dbhsar_36 using "`inpath'", clear
                keep if `sample' == 1
                keep if dateid >= `dfloor'

                foreach z in 3 12 24 36 {
                    gen ldbhar_`z'  = log(1+dbhar_`z')
                    gen ldbhsar_`z' = log(1+dbhsar_`z')
                }
                gen N = mu1`x'_15yr_q5

                tempfile t1 t2 t3 t4
                preserve
                collapse (`stat') dbhar_3 dbhsar_3 ldbhar_3 ldbhsar_3 (count) N, by(mu1`x'`w'_15yr_`y'`ind' yearquarter)
                rename mu1`x'`w'_15yr_`y'`ind' quantile
                save `t1'
                restore, preserve
                collapse (`stat') dbhar_12 dbhsar_12 ldbhar_12 ldbhsar_12, by(mu4`x'`w'_15yr_`y'`ind' yearquarter)
                rename mu4`x'`w'_15yr_`y'`ind' quantile
                save `t2'
                restore, preserve
                collapse (`stat') dbhar_24 dbhsar_24 ldbhar_24 ldbhsar_24, by(mu8`x'`w'_15yr_`y'`ind' yearquarter)
                rename mu8`x'`w'_15yr_`y'`ind' quantile
                save `t3'
                restore
                collapse (`stat') dbhar_36 dbhsar_36 ldbhar_36 ldbhsar_36, by(mu12`x'`w'_15yr_`y'`ind' yearquarter)
                rename mu12`x'`w'_15yr_`y'`ind' quantile
                save `t4'

                use `t1', clear
                merge 1:1 quantile yearquarter using `t2', nogen
                merge 1:1 quantile yearquarter using `t3', nogen
                merge 1:1 quantile yearquarter using `t4', nogen

                *** hedge-return series
                preserve
                foreach z in 3 12 24 36 {
                    foreach v in dbhar dbhsar ldbhar ldbhsar {
                        replace `v'_`z' = -`v'_`z' if quantile == 1
                    }
                }
                drop if missing(quantile)
                keep if inlist(quantile, 1, `top')
                collapse (sum) dbhar* dbhsar* ldbhar* ldbhsar*, by(yearquarter)
                foreach v in dbhar dbhsar ldbhar ldbhsar {
                    replace `v'_12 = . if yearquarter >= `t12'
                    replace `v'_24 = . if yearquarter >= `t24'
                    replace `v'_36 = . if yearquarter >= `t36'
                }
                save "`outdir'/hedgeret_15yr_`y'`ind'_match_roemodel_`med'lroe`x'`w'_`tag'.dta", replace
                restore

                *** per-quantile time-series means
                drop if missing(quantile)
                collapse (mean) ldbhar* ldbhsar* dbhar* dbhsar* (sum) N, by(quantile)
                foreach z in ldbhar_3 ldbhar_12 ldbhar_24 ldbhar_36 ldbhsar_3 ldbhsar_12 ldbhsar_24 ldbhsar_36 dbhar_3 dbhar_12 dbhar_24 dbhar_36 dbhsar_3 dbhsar_12 dbhsar_24 dbhsar_36 N {
                    rename `z' `z'`w'
                }
                save "`outdir'/quantret_15yr_`y'`ind'_match_roemodel_`med'lroe`x'`w'_`tag'.dta", replace
            }

            *** merge rolling + cum side by side (legacy convention)
            use "`outdir'/quantret_15yr_`y'`ind'_match_roemodel_`med'lroe`x'_`tag'.dta", clear
            merge 1:1 quantile using "`outdir'/quantret_15yr_`y'`ind'_match_roemodel_`med'lroe`x'_cum_`tag'.dta", nogen
            save "`outdir'/quantret_15yr_`y'`ind'_match_roemodel_`med'lroe`x'_`tag'.dta", replace
        }
    }
end
