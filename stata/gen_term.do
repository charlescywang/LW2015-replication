*** gen_term.do — firm-level term structures + quantile ranks (replaces legacy genterm.do)
*** Faithful port of genterm.do (2014-03-10 vintage) with:
***   - keyed 1:1 merge on ffcd dateid (legacy used sorted old-syntax merge — same result, asserted here)
***   - constants from config.do instead of inline .99 / horizon literals
***   - input/output paths explicit; no cwd dependence
*** Args: 1 = path to master regression dataset (.dta with permno yearquarter ffcd btm lroe
***           price_m1 + fundq items + dbhar/dbhsar returns), 2 = parameter tag, 3 = sample,
***        4 = output path
*** The master is expected WITHOUT dateid; it is derived as group(yearquarter) exactly as legacy.

program define gen_term
    args masterpath ptag sample outpath
    local rho = $RHO

    use "`masterpath'", clear
    cap drop dateid
    egen dateid = group(yearquarter)
    gen flroe = f.lroe

    cap confirm variable sampleall
    if _rc gen sampleall = 1
    cap confirm variable samplenopenny
    if _rc gen samplenopenny = (price_m1 >= 1)
    keep if `sample' == 1

    sort permno yearquarter
    tsset permno yearquarter

    *** additional characteristics (guarded: only if the fundq items are on the master)
    cap confirm variable ibq
    if !_rc {
        gen pb  = mcap / ceqq
        gen evs = (mcap + dlttq)/saleq
        gen pe  = mcap / (ibq*1000)
        gen rnoa = oibdpq / (ppentq + actq - lctq)
        gen roe = ibq / ceqq
        gen at  = atq / saleq
        gen lev = dlttq/seqq
        gen salesgrowth = f.saleq/saleq - 1
        gen rdpersales = xrdq / saleq if !missing(xrdq)
        replace rdpersales = 0 if missing(xrdq)
        local charlist "btm mcap pb evs pe rnoa roe at lev salesgrowth rdpersales"
    }
    else local charlist "btm mcap"

    *** merge parameters (estimated through t-1; dateid already shifted +1 in map_params)
    merge m:1 ffcd dateid using "$OUT/parameters_roemodel_lroe_`ptag'`sample'.dta", keep(1 3) nogen

    sort permno yearquarter
    tsset permno yearquarter

    *** implied coefficients from clipped parameters
    foreach x in "" _iv {
        gen coeff1`x' = 1 - k`x'_pool0_w*`rho'
        gen coeff2`x' = (w`x'_pool0_w*coeff1`x')/(1 - w`x'_pool0_w*`rho')
        gen coeff1`x'_cum = 1 - k`x'_pool20_w*`rho'
        gen coeff2`x'_cum = (w`x'_pool20_w*coeff1`x'_cum)/(1 - w`x'_pool20_w*`rho')
    }

    *** term structure: cumulative expected log return over x quarters
    forvalues x = 1/$NHORIZON {
        foreach y in "" _iv {
            gen mu`x'`y'_15yr      = mu`y'_pool_w*`x'  + ((1-k`y'_pool0_w^`x')/(1-k`y'_pool0_w)) *(coeff_btm`y'_pool*btm  + coeff_lroe`y'_pool*(lroe - mu`y'_pool_w))
            gen mu`x'`y'_15yrw     = mu`y'_pool_w*`x'  + ((1-k`y'_pool0_w^`x')/(1-k`y'_pool0_w)) *(coeff1`y'*btm + coeff2`y'*(lroe - mu`y'_pool_w))
            gen mu`x'`y'_cum_15yr  = mu`y'_pool2_w*`x' + ((1-k`y'_pool20_w^`x')/(1-k`y'_pool20_w))*(coeff_btm`y'_pool2*btm + coeff_lroe`y'_pool2*(lroe - mu`y'_pool2_w))
            gen mu`x'`y'_cum_15yrw = mu`y'_pool2_w*`x' + ((1-k`y'_pool20_w^`x')/(1-k`y'_pool20_w))*(coeff1`y'_cum*btm + coeff2`y'_cum*(lroe - mu`y'_pool2_w))
        }
    }

    *** quantile ranks (quintiles + deciles, overall and within-industry), legacy cutoff logic
    local sortvars ""
    foreach h in 1 4 8 12 {
        local sortvars "`sortvars' mu`h'_15yr mu`h'_cum_15yr mu`h'_iv_15yr mu`h'_iv_cum_15yr"
    }
    local sortvars "`sortvars' `charlist' lroe"

    foreach x of local sortvars {
        *** quintiles, overall + within industry
        foreach suf in "" "i" {
            if "`suf'" == "" local bylist "yearquarter"
            else             local bylist "yearquarter ffcd"
            forvalues p = 1/4 {
                local pp = `p'*20
                egen `x'_p`p'`suf' = pctile(`x'), by(`bylist') p(`pp')
            }
            gen     `x'_q5`suf' = 1 if `x' < `x'_p1`suf' & !missing(`x')
            replace `x'_q5`suf' = 2 if `x'_p1`suf' <= `x' & `x' < `x'_p2`suf' & !missing(`x')
            replace `x'_q5`suf' = 3 if `x'_p2`suf' <= `x' & `x' < `x'_p3`suf' & !missing(`x')
            replace `x'_q5`suf' = 4 if `x'_p3`suf' <= `x' & `x' < `x'_p4`suf' & !missing(`x')
            replace `x'_q5`suf' = 5 if `x'_p4`suf' <= `x' & !missing(`x')
            drop `x'_p1`suf' `x'_p2`suf' `x'_p3`suf' `x'_p4`suf'
        }
        *** deciles, overall + within industry
        foreach suf in "" "i" {
            if "`suf'" == "" local bylist "yearquarter"
            else             local bylist "yearquarter ffcd"
            forvalues p = 1/9 {
                local pp = `p'*10
                egen `x'_p`p'`suf' = pctile(`x'), by(`bylist') p(`pp')
            }
            gen     `x'_q10`suf' = 1 if `x' < `x'_p1`suf' & !missing(`x')
            forvalues q = 2/9 {
                local lo = `q'-1
                replace `x'_q10`suf' = `q' if `x'_p`lo'`suf' <= `x' & `x' < `x'_p`q'`suf' & !missing(`x')
            }
            replace `x'_q10`suf' = 10 if `x'_p9`suf' <= `x' & !missing(`x')
            forvalues p = 1/9 {
                drop `x'_p`p'`suf'
            }
        }
    }

    *** winsorize term-structure variables 1%/99% by quarter (clip, not drop)
    foreach y in "" _iv {
        forvalues x = 1/$NHORIZON {
            foreach stub in mu`x'`y'_15yr mu`x'`y'_cum_15yr {
                egen hi_`stub' = pctile(`stub'), p(99) by(yearquarter)
                egen lo_`stub' = pctile(`stub'), p(1)  by(yearquarter)
                gen `stub'_w01 = max(min(`stub', hi_`stub'), lo_`stub') if !missing(`stub')
                drop hi_`stub' lo_`stub'
            }
        }
    }
    compress
    save "`outpath'", replace
end
