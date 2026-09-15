*** t7_gen_er.do — Table 7 branch: firm-level expected NET return term structures.
*** Faithful to Step 5 of the legacy ER Create Data files, horizons {1,4,8,12}:
***   mu{x}_cum_15yr = mu*x + ((1-k^x)/(1-k)) * (b1*btm + b2*(lroe-mu))
***   er{x}_cum_15yr = A*exp(mu{x}_cum_15yr) - 1            (same A across horizons)
***   er{x}_cum_15yr_sigma = exp(0.5*x*sigma2)*exp(mu{x}) - 1  (horizon-scaled variance)
***   er_cum_15yr    = A*exp(mu_pool2_w) - 1                (long-run mean level ER)
*** each winsorized 1%/99% by yearquarter -> _w01 (legacy suffix).
*** Args: 1=srcfile (master panel) 2=tag 3=sample 4=outfile

program define gen_er
    args srcfile tag sample outfile
    use "`srcfile'", clear
    cap confirm variable dateid
    if _rc egen dateid = group(yearquarter)
    cap confirm variable sampleall
    if _rc {
        gen sampleall = 1
        gen samplenopenny = (price_m1 >= 1)
    }

    sort permno yearquarter
    merge m:1 ffcd dateid using "$OUT/er/parameters_roemodel_lroe_ER_`tag'`sample'.dta", keep(1 3) nogen

    foreach x in 1 4 8 12 {
        gen double mu`x'_cum_15yr = mu_pool2_w*`x' + ((1-k_pool20_w^`x')/(1-k_pool20_w)) * ///
            (coeff_btm_pool2*btm + coeff_lroe_pool2*(lroe - mu_pool2_w))
        gen double er`x'_cum_15yr       = coeff_CONSA_pool2*exp(mu`x'_cum_15yr) - 1
        gen double er`x'_cum_15yr_sigma = exp(0.5*`x'*sigma2)*exp(mu`x'_cum_15yr) - 1
    }
    gen double er_cum_15yr       = coeff_CONSA_pool2*exp(mu_pool2_w) - 1
    gen double er_cum_15yr_sigma = exp(0.5*sigma2)*exp(mu_pool2_w) - 1

    foreach v in mu1_cum_15yr mu4_cum_15yr mu8_cum_15yr mu12_cum_15yr ///
                 er1_cum_15yr er4_cum_15yr er8_cum_15yr er12_cum_15yr ///
                 er1_cum_15yr_sigma er4_cum_15yr_sigma er8_cum_15yr_sigma er12_cum_15yr_sigma ///
                 er_cum_15yr er_cum_15yr_sigma {
        egen double __hi = pctile(`v'), p(99) by(yearquarter)
        egen double __lo = pctile(`v'), p(1)  by(yearquarter)
        gen double `v'_w01 = max(min(`v', __hi), __lo) if missing(`v') == 0
        drop __hi __lo
    }
    compress
    save "`outfile'", replace
end
