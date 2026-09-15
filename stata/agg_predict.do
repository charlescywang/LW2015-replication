*** agg_predict.do — port of the aggregate market-prediction test (JFE Table 9, LW side).
*** Legacy production file: "Test Model in Aggregate (Mar 2014) (CumAll) (New Approach).do".
*** Design: aggregate the state variables (EW means of btm, lroe across sample firms per
*** quarter), estimate recursive time-series predictive regressions of next-quarter CRSP
*** EW-index log return on the aggregates, forecast with LAGGED coefficients (strictly OOS),
*** benchmark = expanding mean of the target from 1971, evaluate with R2_OS and ENC-NEW
*** (Clark-McCracken 2001: ENC = P * sum(u1^2 - u1*u2)/sum(u2^2)).
*** Variants: OLS on raw aggregates (lw), OLS on winsorized aggregates (lw2), robust rreg
*** on raw aggregates (lw4 — the paper's stated "robust linear regressions").
*** Args: 1=final panel path  2=tag  3=eval start dateid  4=eval end dateid

program define agg_predict
    args finalpath tag ev0 ev1

    *** 1. aggregates per dateid
    use permno yearquarter dateid btm lroe mcap using "`finalpath'", clear
    sort permno yearquarter
    tsset permno yearquarter
    gen double lmcap = l.mcap
    foreach v in btm lroe {
        egen double hi_`v' = pctile(`v'), p(99.5) by(dateid)
        egen double lo_`v' = pctile(`v'), p(0.5)  by(dateid)
        gen double `v'_w = max(min(`v', hi_`v'), lo_`v') if !missing(`v')
    }
    collapse (mean) ebtm=btm elroe=lroe ebtm_w=btm_w elroe_w=lroe_w, by(dateid yearquarter)
    sort dateid
    tempfile agg
    save `agg'

    *** 2. target: next-quarter CRSP EW log index return
    use "$DATA/qmkt.dta", clear
    sort yearquarter
    gen lewret = lewret_q[_n+1]
    merge 1:1 yearquarter using `agg', keep(3) nogen
    sort dateid
    qui su dateid
    local T = r(max)

    *** 3. recursive coefficient paths (min 10 obs), forecasts with lagged coefficients
    foreach s in "" "_w" {
        gen double c_cons`s' = .
        gen double c_btm`s'  = .
        gen double c_roe`s'  = .
        gen double cr_cons`s' = .
        gen double cr_btm`s'  = .
        gen double cr_roe`s'  = .
    }
    forvalues t = 10/`T' {
        qui cap reg lewret ebtm elroe if dateid <= `t'
        if !_rc {
            qui replace c_cons = _b[_cons] if dateid == `t'
            qui replace c_btm  = _b[ebtm]  if dateid == `t'
            qui replace c_roe  = _b[elroe] if dateid == `t'
        }
        qui cap reg lewret ebtm_w elroe_w if dateid <= `t'
        if !_rc {
            qui replace c_cons_w = _b[_cons]  if dateid == `t'
            qui replace c_btm_w  = _b[ebtm_w] if dateid == `t'
            qui replace c_roe_w  = _b[elroe_w] if dateid == `t'
        }
        qui cap rreg lewret ebtm elroe if dateid <= `t'
        if !_rc {
            qui replace cr_cons = _b[_cons] if dateid == `t'
            qui replace cr_btm  = _b[ebtm]  if dateid == `t'
            qui replace cr_roe  = _b[elroe] if dateid == `t'
        }
    }
    sort dateid
    gen double erhat_lw  = c_cons[_n-1]  + c_btm[_n-1]*ebtm    + c_roe[_n-1]*elroe
    gen double erhat_lw2 = c_cons_w[_n-1]+ c_btm_w[_n-1]*ebtm_w+ c_roe_w[_n-1]*elroe_w
    gen double erhat_lw4 = cr_cons[_n-1] + cr_btm[_n-1]*ebtm   + cr_roe[_n-1]*elroe

    *** 4. benchmark: expanding mean of lewret over dateids 1..t-1 (data from 1971)
    gen double _cs = sum(cond(missing(lewret),0,lewret))
    gen double _cn = sum(!missing(lewret))
    gen double bench = _cs[_n-1]/_cn[_n-1]

    *** 5. evaluation
    keep if dateid >= `ev0' & dateid <= `ev1' & !missing(lewret)
    di as result _n "=== agg_predict `tag': eval dateid `ev0'-`ev1' (N=" _N ") ==="
    foreach m in lw lw2 lw4 {
        qui gen double u1 = lewret - bench
        qui gen double u2 = lewret - erhat_`m'
        qui gen double u1sq = u1^2
        qui gen double u2sq = u2^2
        qui gen double u1u2 = u1*u2
        qui su u1sq if !missing(u2sq)
        local mse1 = r(mean)
        local P = r(N)
        qui su u2sq
        local mse2 = r(mean)
        qui su u1u2
        local s12 = r(sum)
        qui su u1sq if !missing(u2sq)
        local s11 = r(sum)
        qui su u2sq
        local s22 = r(sum)
        local r2os = 100*(1 - `mse2'/`mse1')
        local encnew = `P' * (`s11' - `s12')/`s22'
        qui reg lewret erhat_`m', robust
        di as text "`m': R2_OS = " %6.3f `r2os' "%   ENC-NEW = " %7.3f `encnew' "   PanelB slope = " %7.4f _b[erhat_`m'] " (t=" %5.2f _b[erhat_`m']/_se[erhat_`m'] ", R2=" %5.3f e(r2) ")"
        drop u1 u2 u1sq u2sq u1u2
    }
end
