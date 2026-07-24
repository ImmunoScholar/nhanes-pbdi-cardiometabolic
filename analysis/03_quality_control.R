# ---------------------------------------------------------------------------
# 03_quality_control.R
# MANDATORY GATE between import and exposure construction.
#
# Seven check families, per the frozen protocol:
#   QC1 duplicate participant identifiers
#   QC2 merge integrity
#   QC3 missingness
#   QC4 impossible values
#   QC5 survey-weight integrity
#   QC6 distributional checks
#   QC7 outlier diagnostics
#
# Checks are BLOCKING (a real threat to validity -- halt) or ADVISORY
# (recorded, inspected by a human, does not halt). No downstream script may
# run until every blocking check passes.
#
# This script derives NOTHING that later scripts consume. It only inspects.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({ library(here) })
source(here::here("R", "utils.R"))

interim_dir <- here::here("data", "interim")
log_dir     <- here::here("outputs", "logs")
logfile     <- file.path(log_dir, "03_quality_control.log")

log_msg("=== 03_quality_control.R start ===", logfile = logfile)

dat <- readRDS(file.path(interim_dir, "nhanes_raw_list.rds"))
qc  <- data.frame(check = character(), result = character(),
                  detail = character(), blocking = logical(),
                  stringsAsFactors = FALSE)

ITEM_LEVEL <- c("P_DR1IFF", "P_DR2IFF", "P_RXQ_RX", "P_DSQTOT")  # >1 row/person

# --- QC1 duplicate identifiers ---------------------------------------------
for (nm in setdiff(names(dat), ITEM_LEVEL)) {
  d <- dat[[nm]]
  if (!"SEQN" %in% names(d)) {
    qc <- qc_add(qc, "QC1.no_seqn", "FAIL", nm, blocking = TRUE); next
  }
  ndup <- sum(duplicated(d$SEQN))
  qc <- qc_add(qc, paste0("QC1.dup_seqn.", nm),
               if (ndup == 0) "PASS" else "FAIL",
               sprintf("%d duplicate SEQN", ndup), blocking = TRUE)
}
for (nm in intersect(ITEM_LEVEL, names(dat))) {
  d <- dat[[nm]]
  qc <- qc_add(qc, paste0("QC1.itemlevel.", nm), "INFO",
               sprintf("%d rows / %d unique SEQN (item-level, duplicates expected)",
                       nrow(d), length(unique(d$SEQN))), blocking = FALSE)
}

# --- analytic spine --------------------------------------------------------
# Adults 20+, not pregnant, MEC-examined. Built here for QC only.
demo <- dat[["P_DEMO"]]
spine <- demo[demo$RIDAGEYR >= 20 &
              (is.na(demo$RIDEXPRG) | demo$RIDEXPRG != 1) &
              demo$RIDSTATR == 2, ]
qc <- qc_add(qc, "QC2.spine_n", "INFO",
             sprintf("adults 20+, non-pregnant, MEC-examined: n = %d", nrow(spine)),
             blocking = FALSE)

# --- QC2 merge integrity ---------------------------------------------------
# A left join onto a unique key must never change the row count. If it does,
# the right-hand table was not one-row-per-person and the join silently
# fanned out -- the single most damaging and most invisible NHANES error.
merged <- spine[, c("SEQN", "SDMVSTRA", "SDMVPSU", "WTMECPRP", "WTINTPRP",
                    "RIDAGEYR", "RIAGENDR", "RIDRETH3", "DMDEDUC2", "INDFMPIR")]
n0 <- nrow(merged)

for (nm in setdiff(names(dat), c("P_DEMO", ITEM_LEVEL))) {
  d <- dat[[nm]]
  add <- setdiff(names(d), names(merged))
  merged <- merge(merged, d[, c("SEQN", add), drop = FALSE],
                  by = "SEQN", all.x = TRUE)
  qc <- qc_add(qc, paste0("QC2.join.", nm),
               if (nrow(merged) == n0) "PASS" else "FAIL",
               sprintf("rows %d -> %d (expected %d)", n0, nrow(merged), n0),
               blocking = TRUE)
  n0 <- nrow(merged)
}

# item-level files: every SEQN must exist in the spine's source (P_DEMO)
for (nm in intersect(ITEM_LEVEL, names(dat))) {
  orphan <- setdiff(unique(dat[[nm]]$SEQN), demo$SEQN)
  qc <- qc_add(qc, paste0("QC2.orphans.", nm),
               if (!length(orphan)) "PASS" else "FAIL",
               sprintf("%d SEQN absent from P_DEMO", length(orphan)),
               blocking = TRUE)
}

# --- QC3 missingness -------------------------------------------------------
key_vars <- c("RIDAGEYR","RIAGENDR","RIDRETH3","DMDEDUC2","INDFMPIR",
              "BMXWAIST","BMXBMI","BPXOSY2","BPXOSY3","BPXODI2","BPXODI3",
              "LBXTR","LBDHDD","LBXGLU","LBXIN","LBXGH","LBXHSCRP",
              "DR1TKCAL","DR2TKCAL","DR1DRSTZ","DR2DRSTZ",
              "WTSAFPRP","WTDRD1PP","WTDR2DPP")
key_vars <- intersect(key_vars, names(merged))

miss <- data.frame(
  variable = key_vars,
  n_missing = vapply(key_vars, function(v) sum(is.na(merged[[v]])), integer(1)),
  pct_missing = round(100 * vapply(key_vars, function(v)
    mean(is.na(merged[[v]])), numeric(1)), 1),
  row.names = NULL, stringsAsFactors = FALSE
)
write.csv(miss, file.path(log_dir, "03_missingness.csv"), row.names = FALSE)
qc <- qc_add(qc, "QC3.missingness", "INFO",
             sprintf("max missing %.1f%% (%s); see 03_missingness.csv",
                     max(miss$pct_missing),
                     miss$variable[which.max(miss$pct_missing)]),
             blocking = FALSE)

# --- QC4 impossible values -------------------------------------------------
# Deliberately WIDE bounds. These detect DATA CORRUPTION -- sentinel codes,
# unit errors, sign errors -- and nothing else. Biological extremes are NOT
# corruption; they are handled by the frozen log-transform rule and reported
# advisorily by QC7. Bounds are therefore set at true assay/physiological
# ceilings, not at clinical-normality limits.
#
# Amendment 3 (see docs/protocol_amendments.md): LBXIN and LBXHSCRP upper
# bounds were initially set at clinical rather than physiological ceilings and
# wrongly flagged 3 genuine measurements.
bounds <- list(
  RIDAGEYR = c(20, 150),   BMXWAIST = c(40, 200),  BMXBMI   = c(10, 100),
  BPXOSY2  = c(60, 300),   BPXOSY3  = c(60, 300),
  BPXODI2  = c(20, 200),   BPXODI3  = c(20, 200),
  LBXTR    = c(10, 5000),  LBDHDD   = c(5, 200),   LBXGLU   = c(20, 800),
  LBXIN    = c(0.1, 1000), LBXGH    = c(2, 20),    LBXHSCRP = c(0.01, 500),
  DR1TKCAL = c(0, 30000),  DR2TKCAL = c(0, 30000)
)
imp <- lapply(names(bounds), function(v) {
  if (!v %in% names(merged)) return(NULL)
  x <- merged[[v]]; b <- bounds[[v]]
  bad <- which(!is.na(x) & (x < b[1] | x > b[2]))
  if (!length(bad)) return(NULL)
  data.frame(variable = v, n_impossible = length(bad),
             lower = b[1], upper = b[2],
             observed_min = min(x[bad]), observed_max = max(x[bad]),
             stringsAsFactors = FALSE)
})
imp <- do.call(rbind, imp)
if (is.null(imp)) {
  qc <- qc_add(qc, "QC4.impossible_values", "PASS",
               "no values outside plausible physiological bounds", blocking = TRUE)
} else {
  write.csv(imp, file.path(log_dir, "03_impossible_values.csv"), row.names = FALSE)
  qc <- qc_add(qc, "QC4.impossible_values", "FAIL",
               sprintf("%d variables contain impossible values; see 03_impossible_values.csv",
                       nrow(imp)), blocking = TRUE)
}

# --- QC5 survey-weight integrity -------------------------------------------
wts <- intersect(c("WTINTPRP","WTMECPRP","WTSAFPRP","WTDRD1PP","WTDR2DPP"),
                 names(merged))
for (w in wts) {
  x <- merged[[w]]
  qc <- qc_add(qc, paste0("QC5.negative.", w),
               if (!any(x < 0, na.rm = TRUE)) "PASS" else "FAIL",
               sprintf("%d negative weights", sum(x < 0, na.rm = TRUE)),
               blocking = TRUE)
  qc <- qc_add(qc, paste0("QC5.zero_or_na.", w), "INFO",
               sprintf("%d zero, %d NA, sum = %s",
                       sum(x == 0, na.rm = TRUE), sum(is.na(x)),
                       format(sum(x, na.rm = TRUE), big.mark = ",", scientific = FALSE)),
               blocking = FALSE)
}

# Design-based variance requires >= 2 PSUs in every stratum. A singleton
# stratum silently breaks SE estimation rather than erroring.
psu_tab <- tapply(merged$SDMVPSU, merged$SDMVSTRA, function(z) length(unique(z)))
singleton <- names(psu_tab)[psu_tab < 2]
qc <- qc_add(qc, "QC5.psu_per_stratum",
             if (!length(singleton)) "PASS" else "FAIL",
             sprintf("%d strata with <2 PSUs%s", length(singleton),
                     if (length(singleton)) paste0(": ", paste(singleton, collapse = ",")) else ""),
             blocking = TRUE)

# Which subsample actually binds? The protocol ASSUMES the fasting subsample
# is smallest and therefore that WTSAFPRP is the least-common-denominator
# weight. That assumption is tested here, not trusted.
if (all(c("WTSAFPRP", "WTDRD1PP") %in% names(merged))) {
  n_fast <- sum(!is.na(merged$WTSAFPRP) & merged$WTSAFPRP > 0)
  n_diet <- sum(!is.na(merged$WTDRD1PP) & merged$WTDRD1PP > 0)
  qc <- qc_add(qc, "QC5.binding_subsample",
               if (n_fast <= n_diet) "PASS" else "FAIL",
               sprintf("fasting n = %d, day-1 dietary n = %d -> %s is the least common denominator",
                       n_fast, n_diet, if (n_fast <= n_diet) "WTSAFPRP" else "WTDRD1PP"),
               blocking = TRUE)
}

# --- QC6 distributional checks ---------------------------------------------
# Also fixes the log-transform decisions under the frozen rule |skew| > 1.
dist_vars <- intersect(c("BMXWAIST","LBXTR","LBDHDD","LBXGLU","LBXIN",
                         "LBXGH","LBXHSCRP","DR1TKCAL"), names(merged))
w_desc <- if ("WTSAFPRP" %in% names(merged)) merged$WTSAFPRP else merged$WTMECPRP
dist <- do.call(rbind, lapply(dist_vars, function(v) {
  x <- merged[[v]]
  q <- wtd_quantile(x, w_desc)
  data.frame(variable = v, n_obs = sum(!is.na(x)),
             skewness = round(skewness(x), 2),
             log_transform = abs(skewness(x)) > 1,
             p1 = q[1], p25 = q[2], p50 = q[3], p75 = q[4], p99 = q[5],
             row.names = NULL, stringsAsFactors = FALSE)
}))
write.csv(dist, file.path(log_dir, "03_distributions.csv"), row.names = FALSE)
qc <- qc_add(qc, "QC6.distributions", "INFO",
             sprintf("%d variables profiled; %d flagged for log-transform",
                     nrow(dist), sum(dist$log_transform)), blocking = FALSE)

# --- QC7 outlier diagnostics -----------------------------------------------
# Advisory by design. NHANES values are real measurements; we report extremes
# for human inspection and NEVER delete them automatically.
out <- do.call(rbind, lapply(dist_vars, function(v) {
  x <- merged[[v]]; x <- x[!is.na(x)]
  if (length(x) < 10) return(NULL)
  qs <- quantile(x, c(.25, .75)); iqr <- qs[2] - qs[1]
  data.frame(variable = v,
             n_beyond_3iqr = sum(x < qs[1] - 3*iqr | x > qs[2] + 3*iqr),
             pct_beyond_3iqr = round(100*mean(x < qs[1] - 3*iqr | x > qs[2] + 3*iqr), 2),
             max_value = max(x), row.names = NULL, stringsAsFactors = FALSE)
}))
write.csv(out, file.path(log_dir, "03_outliers.csv"), row.names = FALSE)
qc <- qc_add(qc, "QC7.outliers", "INFO",
             "extreme-value counts written to 03_outliers.csv (advisory; no automatic deletion)",
             blocking = FALSE)

# --- report and gate -------------------------------------------------------
write.csv(qc, file.path(log_dir, "03_qc_ledger.csv"), row.names = FALSE)

rep_md <- c("# Quality Control Report",
            paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
            "", sprintf("Analytic spine: n = %d", nrow(spine)), "",
            "| Check | Result | Detail | Blocking |",
            "|---|---|---|---|",
            sprintf("| %s | %s | %s | %s |", qc$check, qc$result,
                    gsub("|", "/", qc$detail, fixed = TRUE), qc$blocking))
writeLines(rep_md, file.path(log_dir, "03_qc_report.md"))

failed <- qc[qc$blocking & qc$result == "FAIL", ]
print(qc[qc$result != "INFO", ])

if (nrow(failed)) {
  log_msg(nrow(failed), " BLOCKING checks failed", level = "ERROR", logfile = logfile)
  print(failed)
  stop("QUALITY CONTROL GATE FAILED. Resolve every blocking failure before ",
       "running 04_* onward. Report: outputs/logs/03_qc_report.md")
}

log_msg("all blocking checks passed", logfile = logfile)
log_msg("=== 03_quality_control.R complete ===", logfile = logfile)
