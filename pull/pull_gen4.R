#!/usr/bin/env Rscript
###############################################################################
# pull_gen4.R
#
# R / WRDS-Postgres translation of the legacy SAS "Gen-4" data pull:
#   Codes/SAS/Obtain Data to Estimate Term Structure
#            (CompuStat Only and RDQ Based Merge) (2014 Update).sas
# which produced Data/capd_analysis_compstat_rdq_2014.sas7bdat for
# Lyle & Wang (2015 JFE 116:505-525).
#
# Authoritative audit of the SAS ground truth:
#   docs/deep-read-2026-08-31/sas_code.md  (sections 1, 2.5, 6)
#
# Each numbered STEP below cites the SAS block it replicates.
#
# INTENTIONAL DEVIATIONS from the SAS (see pull/README.md):
#   - No trailing-window return sums (SAS r_m11..r_m0) and therefore no
#     trailing BHAR/DBHAR/XBHAR/BHSAR; in particular the SAS DBHAR_m*
#     overwrite bug (size-adjusted values silently clobbering the
#     market-adjusted ones) is NOT reproduced. Downstream Stata code does
#     not consume any trailing abnormal returns.
#   - Forward horizons +48 and +60 months are omitted (not used downstream).
#   - EQVOL / EQTO / Spread (volume, turnover, bid-ask) are not pulled.
#   - crsp.msf is pulled from 1969-01-01 only (guardrail); FCDates before
#     1969 get missing returns/prices. Downstream sample starts 1971.
#   - cusip is always the Compustat 8-char cusip. (In the SAS, a merge
#     order quirk let the CRSP msf cusip from the vol_* datasets overwrite
#     the Compustat cusip on most rows.)
#   - FFIN is truncated to 5 characters ('Rubber' -> 'Rubbe') because the
#     SAS data step fixed FFIN's length at 5 from its first assignment
#     ('Agric'); we replicate the truncation so values match the frozen file.
#
# USAGE:
#   Rscript pull_gen4.R                 # uses `mode` / `test_subsample` below
#   Rscript pull_gen4.R legacy2013      # override mode
#   Rscript pull_gen4.R current
#   Rscript pull_gen4.R legacy2013 test # tiny hash subsample (permno %% 997 == 0)
#
# Requires: ~/.Rprofile that creates a live WRDS Postgres connection `wrds`.
###############################################################################

## ===========================================================================
## CONFIG
## ===========================================================================

mode           <- "legacy2013"   # "legacy2013" or "current"
test_subsample <- FALSE          # TRUE -> permno %% 997 == 0, tiny test output
outdir         <- Sys.getenv("ERTERM_DATA", "./data")

## command-line overrides: Rscript pull_gen4.R [legacy2013|current] [test]
cargs <- commandArgs(trailingOnly = TRUE)
if (length(cargs) >= 1 && cargs[1] %in% c("legacy2013", "current")) mode <- cargs[1]
if (any(cargs == "test")) test_subsample <- TRUE

## packages -------------------------------------------------------------------
ulib <- Sys.getenv("R_LIBS_USER")
if (dir.exists(ulib)) .libPaths(c(ulib, .libPaths()))
suppressPackageStartupMessages({
  library(DBI)
  library(data.table)
  library(haven)
})
stopifnot(exists("wrds"))        # created by ~/.Rprofile (never print it)

dir.create(path.expand(outdir), recursive = TRUE, showWarnings = FALSE)
outfile <- file.path(path.expand(outdir),
                     if (test_subsample) "capd_replica_test.dta"
                     else sprintf("capd_replica_%s.dta", mode))

## mode-dependent parameters --------------------------------------------------
## legacy2013 replicates the March-2014 production run:
##   - returns cutoff '30DEC2013'D  (SAS: ddd = intck('MONTH',FCDate,'30DEC2013'D))
##   - fundq statements through 2013-09-30 (2013Q3, the last quarter the
##     Stata builder keeps; the frozen pull had a partial 2013Q4)
##   - quarter-end grid through 2013Q4
## current: same legacy SIZ-format CRSP tables, cutoff = last available msi
##   month (2024-12-31 as of this writing); see the CIZ TODO at the bottom
##   for data beyond the SIZ terminal date.
if (mode == "legacy2013") {
  cutoff        <- as.Date("2013-12-30")
  fundq_maxdate <- as.Date("2013-09-30")
  grid_maxdate  <- as.Date("2013-12-31")
} else {
  cutoff        <- dbGetQuery(wrds, "select max(date) as d from crsp.msi")$d
  fundq_maxdate <- cutoff
  grid_maxdate  <- cutoff
}

msf_mindate <- as.Date("1969-01-01")   # performance guardrail (see deviations)
horizons    <- c(3L, 12L, 24L, 36L)    # forward windows in months (+48/+60 omitted)

## helpers --------------------------------------------------------------------
midx  <- function(d) year(d) * 12L + month(d)          # SAS intck('MONTH',...) arithmetic
sumna <- function(x) if (all(is.na(x))) NA_real_ else sum(x, na.rm = TRUE)  # proc summary sum()
logg  <- function(x) { r <- suppressWarnings(log1p(x)); r[!is.finite(r)] <- NA_real_; r }

cutoff_midx <- midx(cutoff)

cat(sprintf("pull_gen4.R  mode=%s  test_subsample=%s\n", mode, test_subsample))
cat(sprintf("cutoff=%s  fundq<=%s  grid<=%s  ->  %s\n\n",
            cutoff, fundq_maxdate, grid_maxdate, outfile))

## ===========================================================================
## STEP 1 - CCM link table
##   SAS: data mydir.ccmlink; set ccm.Ccmxpf_lnkhist
##          (where = (linktype in ('LC','LU') & (year(linkenddt)>=1950 or missing)));
##        missing linkenddt -> today's date.
##   (Pulled first so test mode can restrict the fundq pull to linked gvkeys.)
## ===========================================================================
ccm <- setDT(dbGetQuery(wrds, "
  select gvkey, lpermno as permno, lpermco as permco, liid, linkdt, linkenddt
  from crsp.ccmxpf_lnkhist
  where linktype in ('LC','LU') and lpermco is not null
"))
ccm[is.na(linkenddt), linkenddt := Sys.Date()]
if (test_subsample) ccm <- ccm[permno %% 997L == 0L]
cat(sprintf("STEP 1  ccmlink: %d rows (%d gvkeys)\n", nrow(ccm), uniqueN(ccm$gvkey)))

## ===========================================================================
## STEP 2 - Compustat quarterly fundamentals (SAS DS1 Step 1: mydir.comp)
##   select distinct substr(CUSIP,1,8), gvkey, datadate, fyr, fyearq, rdq,
##     ATQ ... LCTQ  from comp.fundq
##   where fyearq>=0 & Consol='C' & Indfmt='INDL' & Datafmt='STD' & Popsrc='D'
##     & exchg in (11..15,17..19) & curncdq='USD'
## ===========================================================================
gvkey_filter <- if (test_subsample)
  sprintf("and gvkey in (%s)", paste(sprintf("'%s'", unique(ccm$gvkey)), collapse = ",")) else ""

comp <- setDT(dbGetQuery(wrds, sprintf("
  select distinct substr(cusip,1,8) as cusip, gvkey, datadate, fyr, fyearq, rdq,
         atq, pstkq, seqq, ceqq, ltq, mibq, txditcq, cshprq, curncdq,
         epspxq as eps, oibdpq, ibq, dlttq, saleq, xrdq, ppentq, actq, lctq
  from comp.fundq
  where fyearq >= 0
    and consol = 'C' and indfmt = 'INDL' and datafmt = 'STD' and popsrc = 'D'
    and exchg in (11,12,13,14,15,17,18,19)
    and curncdq = 'USD'
    and datadate <= '%s'
    %s
", fundq_maxdate, gvkey_filter)))
cat(sprintf("STEP 2  fundq: %d rows\n", nrow(comp)))

## ===========================================================================
## STEP 3 - Current (header) SIC from comp.namesq (SAS Step 2: DNUM = B.SIC)
## ===========================================================================
namesq <- setDT(dbGetQuery(wrds, "select distinct gvkey, sic from comp.namesq"))
namesq[, dnum := as.integer(sic)][, sic := NULL]
if (anyDuplicated(namesq$gvkey)) {
  warning("comp.namesq has multiple SICs for some gvkeys; keeping first")
  namesq <- unique(namesq, by = "gvkey")
}
comp <- merge(comp, namesq, by = "gvkey", all.x = FALSE)  # SAS inner join (A,B where match)
comp[, sic := dnum]
cat(sprintf("STEP 3  + namesq SIC: %d rows\n", nrow(comp)))

## ===========================================================================
## STEP 4 - Fama-French 48 industry label from current SIC
##   (SAS Step 3 hard-coded block, ported verbatim; first match wins.
##    SAS fixed FFIN's length at 5 from the first literal 'Agric', so
##    'Rubber' is stored as 'Rubbe' -- replicated via the 5-char truncation.)
## ===========================================================================
ff48_map <- list(
  Agric  = c(100,799, 2048,2048),
  Food   = c(2000,2046, 2050,2063, 2070,2079, 2090,2095, 2098,2099),
  Soda   = c(2064,2068, 2086,2087, 2096,2097),
  Beer   = c(2080,2085),
  Smoke  = c(2100,2199),
  Toys   = c(900,999, 3650,3652, 3732,3732, 3930,3949),
  Fun    = c(7800,7841, 7900,7999),
  Books  = c(2700,2749, 2770,2799),
  Hshld  = c(2047,2047, 2391,2392, 2510,2519, 2590,2599, 2840,2844, 3160,3199,
             3229,3231, 3260,3260, 3262,3263, 3269,3269, 3630,3639, 3750,3751,
             3800,3800, 3860,3879, 3910,3919, 3960,3961, 3991,3991, 3995,3995),
  Clths  = c(2300,2390, 3020,3021, 3100,3111, 3130,3159, 3965,3965),
  Hlth   = c(8000,8099),
  MedEq  = c(3693,3693, 3840,3851),
  Drugs  = c(2830,2836),
  Chems  = c(2800,2829, 2850,2899),
  Rubber = c(3000,3000, 3050,3099),
  Txtls  = c(2200,2295, 2297,2299, 2393,2395, 2397,2399),
  BldMt  = c(800,899, 2400,2439, 2450,2459, 2490,2499, 2950,2952, 3200,3219,
             3240,3259, 3261,3261, 3264,3264, 3270,3299, 3420,3442, 3446,3452,
             3490,3499, 3996,3996),
  Cnstr  = c(1500,1549, 1600,1699, 1700,1799),
  Steel  = c(3300,3369, 3390,3399),
  FabPr  = c(3400,3400, 3443,3444, 3460,3479),
  Mach   = c(3510,3536, 3540,3569, 3580,3599),
  ElcEq  = c(3600,3621,                                   # two SAS branches, same label
             3623,3629, 3640,3646, 3648,3649, 3660,3660, 3691,3692, 3699,3699),
  Misc   = c(3690,3690, 3900,3900, 3970,3970, 3990,3990, 3999,3999, 9900,9999),
  Autos  = c(2296,2296, 2396,2396, 3010,3011, 3537,3537, 3647,3647, 3694,3694,
             3700,3716, 3790,3792, 3799,3799),
  Aero   = c(3720,3729),
  Ships  = c(3730,3731, 3740,3743),
  Guns   = c(3480,3489, 3760,3769, 3795,3795),
  Gold   = c(1040,1049),
  Mines  = c(1000,1039, 1060,1099, 1400,1499),
  Coal   = c(1200,1299),
  Enrgy  = c(1310,1389, 2900,2911, 2990,2999),
  Util   = c(4900,4999),
  Telcm  = c(4800,4899),
  PerSv  = c(7020,7021, 7030,7039, 7200,7212, 7215,7299, 7395,7395, 7500,7500,
             7520,7549, 7600,7699, 8100,8199, 8200,8299, 8300,8399, 8400,8499,
             8600,8699, 8800,8899),
  BusSv  = c(2750,2759, 3993,3993, 7300,7372, 7374,7394, 7397,7397, 7399,7399,
             7510,7519, 8700,8748, 8900,8999),
  Comps  = c(3570,3579, 3680,3689, 3695,3695, 7373,7373),
  Chips  = c(3622,3622, 3661,3679, 3810,3810, 3812,3812),
  LabEq  = c(3811,3811, 3820,3830),
  Paper  = c(2520,2549, 2600,2639, 2670,2699, 2760,2761, 3950,3955),
  Boxes  = c(2440,2449, 2640,2659, 3220,3221, 3410,3412),
  Trans  = c(4000,4099, 4100,4199, 4200,4299, 4400,4499, 4500,4599, 4600,4699,
             4700,4799),
  Whlsl  = c(5000,5099, 5100,5199),
  Rtail  = c(5200,5299, 5300,5399, 5400,5499, 5500,5599, 5600,5699, 5700,5736,
             5900,5999),
  Meals  = c(5800,5813, 5890,5890, 7000,7019, 7040,7049, 7213,7213),
  Banks  = c(6000,6099, 6100,6199),
  Insur  = c(6300,6399, 6400,6411),
  RlEst  = c(6500,6553),
  Fin    = c(6200,6299, 6700,6799)
)
ff48 <- function(sic) {
  out <- rep("", length(sic))
  for (lab in names(ff48_map)) {
    rg  <- matrix(ff48_map[[lab]], ncol = 2, byrow = TRUE)
    hit <- rep(FALSE, length(sic))
    for (j in seq_len(nrow(rg)))
      hit <- hit | (!is.na(sic) & sic >= rg[j, 1] & sic <= rg[j, 2])
    out[hit & out == ""] <- substr(lab, 1, 5)   # SAS length-5 truncation
  }
  out
}
comp[, ffin := ff48(sic)]
cat(sprintf("STEP 4  FF48 assigned (blank: %d rows)\n", comp[ffin == "", .N]))

## ===========================================================================
## STEP 5 - CCM intersection (SAS: mydir.comp4)
##   where gvkey match & lpermco non-missing & linkdt <= compdate <= linkenddt
##   (at this stage the SAS "compdate" is still datadate)
##   + header GICS gind as gics6 (SAS used ccm.comphead; modern source is
##     comp.company) + nodupkey by gvkey permno datadate (SAS: ~479 dropped,
##     fiscal-year-end changes).
## ===========================================================================
comp <- ccm[comp,
            on = .(gvkey, linkdt <= datadate, linkenddt >= datadate),
            nomatch = NULL,
            .(gvkey, permno, permco, liid,
              cusip, datadate = i.datadate, fyr, fyearq, rdq,
              atq, pstkq, seqq, ceqq, ltq, mibq, txditcq, cshprq, curncdq, eps,
              oibdpq, ibq, dlttq, saleq, xrdq, ppentq, actq, lctq,
              dnum, sic, ffin)]

gics <- setDT(dbGetQuery(wrds,
  "select gvkey, gind as gics6 from comp.company where gind is not null"))
comp <- merge(comp, gics, by = "gvkey", all.x = TRUE)

setorder(comp, gvkey, permno, datadate)
n0 <- nrow(comp)
comp <- unique(comp, by = c("gvkey", "permno", "datadate"))
cat(sprintf("STEP 5  CCM link + GICS: %d rows (nodupkey dropped %d)\n",
            nrow(comp), n0 - nrow(comp)))

## ===========================================================================
## STEP 6 - RDQ-based availability date (Gen-4 rules; SAS data mydir.comp5)
##   compdate = rdq
##   missing rdq            -> datadate + 90 days
##   rdq <  datadate        -> datadate + 90 days
##   rdq - datadate > 90    -> datadate + 90 days
## ===========================================================================
comp[, compdate := rdq]
comp[is.na(rdq),                              compdate := datadate + 90L]
comp[!is.na(rdq) & (rdq - datadate) < 0,      compdate := datadate + 90L]
comp[!is.na(rdq) & (rdq - datadate) > 90,     compdate := datadate + 90L]
cat(sprintf("STEP 6  compdate set (missing rdq: %d; early rdq: %d; late rdq: %d)\n",
            comp[is.na(rdq), .N],
            comp[!is.na(rdq) & (rdq - datadate) < 0, .N],
            comp[!is.na(rdq) & (rdq - datadate) > 90, .N]))

## ===========================================================================
## STEP 7 - Quarter-end grid + closest-match merge (SAS: trddt, comp6, comp7)
##   grid  = distinct crsp.msi dates in months 3,6,9,12 (last trading days)
##   match = 0 <= intck('MONTH', compdate, prc_date) <= 3, closest by
##           diff = days(compdate -> prc_date)
##   dedup 1: by gvkey permno compdate diff  (closest grid date per statement)
##   dedup 2: by permno prc_date diff        (freshest statement per firm-qtr;
##            the Gen-4 merger fix -- key is permno, NOT gvkey-permno)
## ===========================================================================
grid <- setDT(dbGetQuery(wrds, sprintf("
  select distinct date as prc_date from crsp.msi
  where extract(month from date) in (3,6,9,12) and date <= '%s'
", grid_maxdate)))
grid[, gmidx := midx(prc_date)]
cat(sprintf("STEP 7  grid: %d quarter-end trading days (%s .. %s)\n",
            nrow(grid), min(grid$prc_date), max(grid$prc_date)))

comp[, rid := .I]
comp[, cmidx := midx(compdate)]
cand <- comp[, .(rid, cmidx)][rep(seq_len(.N), each = 4L)]
cand[, gmidx := cmidx + rep(0:3, times = nrow(comp))]
cand <- merge(cand, grid, by = "gmidx")            # keeps only quarter months
m <- comp[cand[, .(rid, prc_date)], on = "rid"]
m[, diff := as.integer(prc_date - compdate)]

setorder(m, gvkey, permno, compdate, diff)
n1 <- uniqueN(m, by = c("gvkey", "permno", "compdate"))
m  <- unique(m, by = c("gvkey", "permno", "compdate"))
setorder(m, permno, prc_date, diff)
n2 <- nrow(m)
m  <- unique(m, by = c("permno", "prc_date"))
comp7 <- m; rm(m, cand)
comp7[, c("rid", "cmidx") := NULL]
setnames(comp7, "prc_date", "fcdate")
comp7[, fcm := midx(fcdate)]
cat(sprintf("STEP 7  matched: %d rows after dedup1; %d after dedup2 (permno x fcdate)\n",
            n1, nrow(comp7)))

## ===========================================================================
## STEP 8 - Monthly returns panel (SAS: mydir.oreturns)
##   crsp.msf x crsp.msi x crsp.ermport1, inner joins on date (and permno for
##   ermport1). NOTE the SAS inner join to ermport1 means permno-months with
##   no size-decile row drop out of ALL horizon sums (including raw RR) --
##   replicated exactly.
##   rr = log(1+ret), rrx = log(1+retx), mr = log(1+vwretd), sdr = log(1+decret)
## ===========================================================================
pfilt <- if (test_subsample) "and permno % 997 = 0" else ""

msf <- setDT(dbGetQuery(wrds, sprintf("
  select permno, date, ret, retx, prc, shrout
  from crsp.msf
  where date >= '%s' %s
", msf_mindate, pfilt)))
msi <- setDT(dbGetQuery(wrds, "select date, vwretd from crsp.msi"))
erm <- setDT(dbGetQuery(wrds, sprintf("
  select permno, date, decret
  from crsp.ermport1
  where date >= '%s' %s
", msf_mindate, pfilt)))
cat(sprintf("STEP 8  msf: %d rows; msi: %d; ermport1: %d\n",
            nrow(msf), nrow(msi), nrow(erm)))

monthly <- merge(msf, msi, by = "date")                       # inner (msi covers all)
monthly <- merge(monthly, erm, by = c("permno", "date"))      # inner: SAS ermport1 join
monthly[, `:=`(rr  = logg(ret),
               rrx = logg(retx),
               mr  = logg(vwretd),
               sdr = logg(decret),
               mindex = midx(date),
               yearmonth = year(date) * 100L + month(date))]

## ===========================================================================
## STEP 9 - Delisting returns (SAS "NEW STEP", Beaver-McNichols-Price 2007)
##   crsp.msedelist, year(dlstdt) >= 1960.
##   If dlstdt is a month-end trading day -> assign to that yearmonth,
##   else -> prior month (January -> December of prior year).
##   drr_month = log(1+dlret); dlret = -1 -> log(1+dlret+.0001); missing -> 0.
##   Then per monthly row: DRR = RR + drr_month if delisted there, else RR.
##   (If RR itself is missing, DRR stays missing -- SAS missing propagation.)
## ===========================================================================
delist <- setDT(dbGetQuery(wrds, "
  select permno, dlstdt, dlret from crsp.msedelist
  where extract(year from dlstdt) >= 1960
"))
lastdays <- msi$date                                # month-end trading-day dictionary
delist[, lastday := dlstdt %in% lastdays]
delist[, yearmonth := ifelse(lastday,
         year(dlstdt) * 100L + month(dlstdt),
         ifelse(month(dlstdt) == 1L,
                (year(dlstdt) - 1L) * 100L + 12L,
                year(dlstdt) * 100L + (month(dlstdt) - 1L)))]
delist[,               drr_month := logg(dlret)]
delist[dlret == -1,    drr_month := log(1 + dlret + 1e-4)]
delist[is.na(dlret),   drr_month := 0]
if (anyDuplicated(delist, by = c("permno", "yearmonth"))) {
  warning("multiple delist events per permno-yearmonth; keeping first (SAS would duplicate rows)")
  delist <- unique(delist, by = c("permno", "yearmonth"))
}
monthly <- merge(monthly, delist[, .(permno, yearmonth, drr_month)],
                 by = c("permno", "yearmonth"), all.x = TRUE)
monthly[, drr := fifelse(is.na(drr_month), rr, rr + drr_month)]
cat(sprintf("STEP 9  delist events: %d; monthly rows with delist adj: %d\n",
            nrow(delist), monthly[!is.na(drr_month), .N]))

## ===========================================================================
## STEP 10 - Forward horizon sums in log space (SAS %sname forward macro:
##   proc summary, class PERMNO FCDate, where 1 <= TM_Month <= h,
##   sum(RR MR SDR DRR RRX)). sum() ignores missings; a group whose window
##   has rows but only missing values sums to missing (sumna); a permno-fcdate
##   with no rows in the window at all is absent -> NA after the left merge.
##   Done locally in data.table via a non-equi join on the month index,
##   chunked by permno to bound memory.
## ===========================================================================
setkey(monthly, permno, mindex)
pairs <- comp7[, .(permno, fcdate, fcm)]

permnos    <- sort(unique(pairs$permno))
chunk_size <- max(1L, floor(500000 / max(1L, nrow(pairs) / length(permnos))))
chunks     <- split(permnos, ceiling(seq_along(permnos) / chunk_size))

sums_list <- vector("list", length(chunks))
for (ci in seq_along(chunks)) {
  pc <- pairs[permno %in% chunks[[ci]]]
  out <- pc[, .(permno, fcdate)]
  for (h in horizons) {
    pc[, fcmh := fcm + h]
    agg <- monthly[pc, on = .(permno, mindex > fcm, mindex <= fcmh),
                   .(rr  = sumna(rr),  mr  = sumna(mr), sdr = sumna(sdr),
                     drr = sumna(drr), rrx = sumna(rrx)),
                   by = .EACHI]
    set(out, j = paste0(c("rr_", "mr_", "sdr_", "drr_", "rrx_"), h),
        value = agg[, .(rr, mr, sdr, drr, rrx)])
  }
  sums_list[[ci]] <- out
}
sums <- rbindlist(sums_list); rm(sums_list)
cat(sprintf("STEP 10 horizon sums: %d permno-fcdate rows, %d chunks\n",
            nrow(sums), length(chunks)))

## ===========================================================================
## STEP 11 - Merge sums onto comp7; exp()-1; cutoff blanking; abnormal returns
##   (SAS data mydir.RET). ORDER MATTERS and mirrors the SAS exactly:
##     1. exp(sum)-1 for EVERY summed series incl. MR_h and SDR_h;
##     2. blank RR_h/DRR_h/RRX_h when ddd = intck('MONTH', FCDate, cutoff) < h
##        (MR_h/SDR_h are NOT blanked in the SAS);
##     3. abnormal returns as differences of SIMPLE returns:
##        DBHAR_h = DRR_h - MR_h, DBHSAR_h = DRR_h - SDR_h
##        (blanked DRR_h makes them missing, as in SAS).
## ===========================================================================
final <- merge(comp7, sums, by = c("permno", "fcdate"), all.x = TRUE)  # SAS merge; if a;
final[, ddd := cutoff_midx - fcm]

for (h in horizons) {
  for (v in paste0(c("rr_", "mr_", "sdr_", "drr_", "rrx_"), h))
    set(final, j = v, value = exp(final[[v]]) - 1)                     # 1. exp()-1
  blank <- final$ddd < h                                               # 2. blanking
  for (v in paste0(c("rr_", "drr_", "rrx_"), h))
    set(final, i = which(blank), j = v, value = NA_real_)
  set(final, j = paste0("dbhar_",  h),                                 # 3. abnormal
      value = final[[paste0("drr_", h)]] - final[[paste0("mr_",  h)]])
  set(final, j = paste0("dbhsar_", h),
      value = final[[paste0("drr_", h)]] - final[[paste0("sdr_", h)]])
}
cat(sprintf("STEP 11 final panel: %d rows; nonmissing rr_3: %d, rr_12: %d\n",
            nrow(final), final[!is.na(rr_3), .N], final[!is.na(rr_12), .N]))

## ===========================================================================
## STEP 12 - Identifiers from crsp.msenames (SAS: mydir.Ret2)
##   exchcd, ticker, comnam where NAMEDT <= FCDate <= NAMEENDT (left join)
## ===========================================================================
msenames <- setDT(dbGetQuery(wrds, sprintf("
  select permno, namedt, nameendt, exchcd, ticker, comnam
  from crsp.msenames %s
", if (test_subsample) "where permno % 997 = 0" else "")))
final[, c("exchcd", "ticker", "comnam") :=
        msenames[final, on = .(permno, namedt <= fcdate, nameendt >= fcdate),
                 mult = "first", .(x.exchcd, x.ticker, x.comnam)]]

## ===========================================================================
## STEP 13 - Formation-date and previous-month price/shares/mcap
##   (SAS: mydir.RET3) from raw crsp.msf (NOT ermport1-filtered):
##   PRICE/SHROUT/mcap at FCDate (exact date match) and at FCDate - 1 month.
##   mcap = abs(prc * shrout), in $1000s.
## ===========================================================================
px <- msf[, .(permno, date, mindex = midx(date),
              price = abs(prc), shrout = abs(shrout), mcap = abs(prc * shrout))]
final[, c("price", "shrout", "mcap") :=
        px[final, on = .(permno, date = fcdate), .(x.price, x.shrout, x.mcap)]]
final[, fcm1 := fcm - 1L]
final[, c("price_m1", "shrout_m1", "mcap_m1") :=
        px[final, on = .(permno, mindex = fcm1), .(x.price, x.shrout, x.mcap)]]

## ===========================================================================
## STEP 14 - Output (haven::write_dta, Stata 14), lowercase names matching the
##   frozen capd_analysis_compstat_rdq_2014 file where variables overlap.
## ===========================================================================
outcols <- c("exchcd", "ticker", "comnam", "permno", "cusip", "fcdate",
             "gvkey", "datadate", "fyr", "fyearq", "rdq",
             "atq", "pstkq", "seqq", "ceqq", "ltq", "mibq", "txditcq",
             "cshprq", "curncdq", "eps", "oibdpq", "ibq", "dlttq", "saleq",
             "xrdq", "ppentq", "actq", "lctq",
             "dnum", "sic", "ffin", "permco", "liid", "gics6", "compdate",
             "rr_3", "drr_3", "rrx_3", "rr_12", "drr_12", "rrx_12",
             "rr_24", "drr_24", "rr_36", "drr_36",
             "dbhar_3", "dbhar_12", "dbhar_24", "dbhar_36",
             "dbhsar_3", "dbhsar_12", "dbhsar_24", "dbhsar_36",
             "price", "shrout", "mcap", "price_m1", "shrout_m1", "mcap_m1")
out <- final[, ..outcols]
setorder(out, permno, fcdate)
write_dta(out, outfile, version = 14)
cat(sprintf("\nSTEP 14 wrote %d rows x %d cols -> %s\n", nrow(out), ncol(out), outfile))

## ===========================================================================
## TODO (NOT IMPLEMENTED): CIZ migration for data past 2024-12-31
## ===========================================================================
## The legacy SIZ-format CRSP monthly tables used above (crsp.msf, crsp.msi,
## crsp.msedelist, crsp.ermport1) terminate at 2024-12-31 and will not be
## extended. To pull data beyond that date, migrate STEP 7-13 to the CIZ
## (CRSP Stock and Indexes Version 2) tables:
##   - crsp.msf_v2 (a view of stkmthsecuritydata): mthcaldt, mthret, mthretx,
##     mthprc, shrout. KEY DIFFERENCE: mthret ALREADY INCLUDES the delisting
##     return, so STEP 9 (msedelist logic, drr construction) must be DROPPED
##     and drr := rr; delisting-month partial returns are handled by CRSP.
##   - Quarter-end grid + market return: replace crsp.msi with the v2 monthly
##     index table (e.g. crsp.msi_v2 / mthcalind value-weighted total return).
##   - Size-decile returns: ermport1 has no direct v2 twin; rebuild decile
##     assignments from stkmthsecuritydata market caps (NYSE breakpoints,
##     prior year-end membership) or source CRSP's v2 cap-decile index files.
##   - Share/exchange screens: exchcd/shrcd live in different fields
##     (primaryexch, sharetype/securitytype) -- the Compustat exchg screen
##     used here is unaffected.
## A hybrid run (SIZ through 2024-12, CIZ after) must splice on permno-month
## and re-verify that log-return compounding matches across the seam.
###############################################################################
