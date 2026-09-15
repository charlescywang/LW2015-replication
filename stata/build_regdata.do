*** build_regdata.do — port of "Create Basic Regression Dataset (March 10, 2014).do".
*** Input: a Gen-4-style panel (.dta, lowercase names — the pull_gen4.R replica or a
*** converted frozen SAS file). Output: the master regression dataset (termregdata).
*** Faithful constructions: bk=ceqq; btm=ln(bk/(mcap/1000)); lroe=log(1+eps*cshprq/L.bk)
*** (missing if L.bk<0); keep cyear>=1971; drop 2013Q4 (parameterized via $RET_CUTOFF-implied
*** last full quarter is NOT applied here — the legacy hard drop is kept for legacy tags and
*** generalized through the `lastq' arg).
*** Args: 1=input path  2=output path  3=last-quarter-to-drop as %tq string (e.g. "2013q4"),
***       "" to keep everything

program define build_regdata
    args inpath outpath dropq

    use "`inpath'", clear
    rename *, lower
    keep if inlist(month(fcdate), 3, 6, 9, 12)

    gen yearmonth = ym(year(fcdate), month(fcdate))
    format yearmonth %tm
    gen yearquarter = yq(year(fcdate), quarter(fcdate))
    format yearquarter %tq

    cap rename fyr fmonth
    cap rename fyearq fyear
    cap rename curncdq curncd
    gen cyear = year(fcdate)

    egen ffcd = group(ffin)
    cap egen gics6cd = group(gics6)
    label var ffcd "Fama-French 48 Industry Grouping"

    cap drop diff
    gen diffdate = fcdate - compdate

    sort permno yearquarter diffdate
    duplicates drop permno yearquarter, force
    tsset permno yearquarter

    *** key variables
    gen bk = ceqq
    gen bkgr = ln(bk/l.bk)
    gen btm0 = bk/(mcap/1000)
    gen btm = ln(btm0)
    gen lroe = log(1 + (eps*cshprq)/(l.bk))
    replace lroe = . if l.bk < 0 & !missing(l.bk)

    gen size = ln(mcap/1000)
    gen size_m1 = ln(mcap_m1/1000)
    gen btm_m1 = ln(bk/(mcap_m1/1000))

    gen lrr_3 = ln(1+rr_3)
    gen lrr_12 = ln(1+rr_12)
    cap gen lrrx_3 = ln(1+rrx_3)
    cap gen lrrx_12 = ln(1+rrx_12)
    cap gen ldivy3 = log((1+rr_3)/(1+rrx_3))

    keep if cyear >= 1971
    if "`dropq'" != "" drop if yearquarter == tq(`dropq')

    save "`outpath'", replace
end
