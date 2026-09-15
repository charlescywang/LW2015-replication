#!/usr/bin/env Rscript
## get_market.R — CRSP EW/VW index quarterly log returns (input to the aggregate
## prediction test, paper Table 9). Requires a live `wrds` connection from ~/.Rprofile.
## Output: data/qmkt.dta  (yearquarter in Stata %tq units, lewret_q, lvwret_q)

ulib <- Sys.getenv("R_LIBS_USER")
if (dir.exists(ulib)) .libPaths(c(ulib, .libPaths()))
suppressPackageStartupMessages({ library(DBI); library(haven) })
stopifnot(exists("wrds"))

outdir <- Sys.getenv("ERTERM_DATA", "./data")
dir.create(outdir, recursive = TRUE, showWarnings = FALSE)

res <- dbSendQuery(wrds, "select date, ewretd, vwretd from crsp.msi where date >= '1925-01-01' order by date")
m <- dbFetch(res); dbClearResult(res); dbDisconnect(wrds)

m$yq  <- as.integer(format(m$date, "%Y")) * 4 + (as.integer(format(m$date, "%m")) - 1) %/% 3
agg   <- aggregate(cbind(lew = log(1 + m$ewretd), lvw = log(1 + m$vwretd)),
                   by = list(yq = m$yq), FUN = sum)
agg$year <- agg$yq %/% 4
agg$q    <- agg$yq %% 4 + 1
agg$yearquarter <- (agg$year - 1960) * 4 + (agg$q - 1)   # Stata %tq

write_dta(data.frame(yearquarter = agg$yearquarter,
                     lewret_q = agg$lew, lvwret_q = agg$lvw),
          file.path(outdir, "qmkt.dta"))
cat("saved", nrow(agg), "quarters ->", file.path(outdir, "qmkt.dta"), "\n")
