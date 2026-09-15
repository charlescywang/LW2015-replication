*** config.do — Lyle & Wang (2015 JFE) replication package
*** Single source of truth for every estimation constant.
*** IMPORTANT: run everything from the PACKAGE ROOT (paths derive from the working dir):
***     /Applications/Stata/StataMP.app/Contents/MacOS/stata-mp -b do run_all.do
*** (or your platform's Stata batch invocation)

global ROOT "`c(pwd)'"
global DATA "$ROOT/data"      // WRDS pulls + large intermediates (never redistributed)
global OUT  "$ROOT/out"       // parameters, hedge returns, exhibits
cap mkdir "$DATA"
cap mkdir "$OUT"
cap mkdir "$OUT/hedge"

*** Model / estimation constants (values from the published 2014 design)
global RHO        = 0.99      // log-linearization constant k1 (paper Sec. 3.1)
global WINDOW     = 60        // rolling estimation window, quarters ("15yr")
global WINSOR_IN  "0.005"     // per-window input winsorization, each tail
global KCLIP      = 0.9999    // persistence clip for kappa and omega
global MUCLIP     = 0.3       // long-run mean clip, quarterly
global NHORIZON   = 12        // term-structure horizons: 1..12 quarters
global OOS_START  = 61        // first analysis dateid (1986Q1 in the 1971Q1-based build)
global RET_CUTOFF "30dec2013" // last date with return data (drives long-horizon truncation)

global VINTAGE  "REP"         // tag stamped on this run's outputs
global SAMPLE   "sampleall"   // headline sample; alternative: samplenopenny (price_m1 >= 1)
