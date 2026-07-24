# ---------------------------------------------------------------------------
# 06_outcome_composite.R
# Primary outcome: continuous cardiometabolic dysfunction score.
#
#   equally weighted mean of survey-weighted, SEX-STANDARDISED z-scores of
#     waist circumference, log-triglycerides, HDL-C (sign-reversed),
#     log fasting glucose, and mean arterial pressure
#
# Higher = worse for every component, so the composite is directionally
# interpretable without further recoding.
#
# Secondary outcomes: log HOMA-IR, HbA1c, log hs-CRP, log ALT.
#
# Blood-pressure medication is a descendant of the outcome (see 00_dag.R), so
# no handling is unbiased. All three pre-specified variants are constructed
# here and the model scripts select among them; none is chosen silently.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({ library(here) })
source(here::here("R", "utils.R"))

int_dir <- here::here("data", "interim")
log_dir <- here::here("outputs", "logs")
tab_dir <- here::here("outputs", "tables")
logfile <- file.path(log_dir, "06_outcome_composite.log")

log_msg("=== 06_outcome_composite.R start ===", logfile = logfile)
dat <- readRDS(file.path(int_dir, "nhanes_raw_list.rds"))

pull <- function(f, vars) {
  d <- dat[[f]]
  miss <- setdiff(vars, names(d))
  if (length(miss)) stop("missing in ", f, ": ", paste(miss, collapse = ", "))
  d[, c("SEQN", vars), drop = FALSE]
}

demo <- pull("P_DEMO", c("RIDAGEYR","RIAGENDR","RIDSTATR","RIDEXPRG","SDMVSTRA","SDMVPSU"))
bmx  <- pull("P_BMX",  c("BMXWAIST","BMXBMI"))
bpxo <- pull("P_BPXO", c("BPXOSY1","BPXOSY2","BPXOSY3","BPXODI1","BPXODI2","BPXODI3"))
tri  <- pull("P_TRIGLY", c("LBXTR","WTSAFPRP"))
hdl  <- pull("P_HDL",  c("LBDHDD"))
glu  <- pull("P_GLU",  c("LBXGLU"))
ins  <- pull("P_INS",  c("LBXIN"))
ghb  <- pull("P_GHB",  c("LBXGH"))
crp  <- pull("P_HSCRP",c("LBXHSCRP"))
bio  <- pull("P_BIOPRO",c("LBXSATSI"))
bpq  <- pull("P_BPQ",  c("BPQ050A"))

d <- demo
for (x in list(bmx, bpxo, tri, hdl, glu, ins, ghb, crp, bio, bpq)) {
  n0 <- nrow(d); d <- merge(d, x, by = "SEQN", all.x = TRUE)
  stopifnot(nrow(d) == n0)              # a join must never change row count
}

# --- analytic population ---------------------------------------------------
d <- d[d$RIDAGEYR >= 20 & d$RIDSTATR == 2 &
       (is.na(d$RIDEXPRG) | d$RIDEXPRG != 1) &
       !is.na(d$WTSAFPRP) & d$WTSAFPRP > 0, ]
log_msg("fasting analytic population: n = ", nrow(d), logfile = logfile)

# --- components ------------------------------------------------------------
# Reading 1 is discarded by convention (white-coat effect); readings 2 and 3
# are averaged. Participants with only one usable reading keep that reading.
d$sbp <- rowMeans(d[, c("BPXOSY2","BPXOSY3")], na.rm = TRUE)
d$dbp <- rowMeans(d[, c("BPXODI2","BPXODI3")], na.rm = TRUE)
d$sbp[is.nan(d$sbp)] <- NA; d$dbp[is.nan(d$dbp)] <- NA
d$dbp[!is.na(d$dbp) & d$dbp == 0] <- NA        # 0 mmHg diastolic is not a reading

# Variant (b): additive constants for treated blood pressure.
d$bp_treated <- !is.na(d$BPQ050A) & d$BPQ050A == 1
d$sbp_adj <- d$sbp + ifelse(d$bp_treated, 15, 0)
d$dbp_adj <- d$dbp + ifelse(d$bp_treated, 10, 0)

map_of <- function(s, dd) dd + (s - dd) / 3
d$map_mmhg     <- map_of(d$sbp,     d$dbp)
d$map_mmhg_adj <- map_of(d$sbp_adj, d$dbp_adj)

d$waist_cm    <- d$BMXWAIST
d$log_tg      <- log(d$LBXTR)
d$hdl_rev     <- -d$LBDHDD
d$log_glucose <- log(d$LBXGLU)

# Secondary
d$homa_ir     <- d$LBXIN * d$LBXGLU / 405
d$log_homa_ir <- ifelse(!is.na(d$homa_ir) & d$homa_ir > 0, log(d$homa_ir), NA)
d$hba1c_pct   <- d$LBXGH
d$log_hscrp   <- log(d$LBXHSCRP)
d$log_alt     <- log(d$LBXSATSI)

# --- sex-standardised, survey-weighted z-scores ---------------------------
wmean <- function(x, w) sum(w * x) / sum(w)
wsd   <- function(x, w) sqrt(sum(w * (x - wmean(x, w))^2) / sum(w))

zscore_by_sex <- function(x, sex, w) {
  z <- rep(NA_real_, length(x))
  for (s in unique(sex)) {
    k <- sex == s & !is.na(x)
    if (sum(k) < 2) next
    z[k] <- (x[k] - wmean(x[k], w[k])) / wsd(x[k], w[k])
  }
  z
}

COMPONENTS <- c("waist_cm", "log_tg", "hdl_rev", "log_glucose", "map_mmhg")
for (v in c(COMPONENTS, "map_mmhg_adj"))
  d[[paste0("z_", v)]] <- zscore_by_sex(d[[v]], d$RIAGENDR, d$WTSAFPRP)

zc <- paste0("z_", COMPONENTS)
d$n_components  <- rowSums(!is.na(d[, zc]))
d$cmd_score     <- ifelse(d$n_components == 5, rowMeans(d[, zc]), NA)
# Variant (b): identical but with medication-adjusted blood pressure
zc_b <- c(paste0("z_", COMPONENTS[1:4]), "z_map_mmhg_adj")
d$cmd_score_bpadj <- ifelse(rowSums(!is.na(d[, zc_b])) == 5, rowMeans(d[, zc_b]), NA)

# --- validation ------------------------------------------------------------
# Each z-score must have weighted mean ~0 and weighted SD ~1 within sex.
chk <- do.call(rbind, lapply(zc, function(v) {
  do.call(rbind, lapply(unique(d$RIAGENDR), function(s) {
    k <- d$RIAGENDR == s & !is.na(d[[v]])
    data.frame(component = v, sex = s, n = sum(k),
               wtd_mean = round(wmean(d[[v]][k], d$WTSAFPRP[k]), 8),
               wtd_sd   = round(wsd(d[[v]][k],  d$WTSAFPRP[k]), 8))
  }))
}))
if (any(abs(chk$wtd_mean) > 1e-6) || any(abs(chk$wtd_sd - 1) > 1e-6))
  stop("Sex-standardisation failed: z-scores are not weighted mean 0 / SD 1.")
log_msg("standardisation verified: all z-scores weighted mean 0, SD 1 by sex",
        logfile = logfile)

summ <- data.frame(
  variable = c(COMPONENTS, "cmd_score", "cmd_score_bpadj",
               "log_homa_ir", "hba1c_pct", "log_hscrp", "log_alt"),
  n_obs = NA_integer_, pct_missing = NA_real_, mean = NA_real_,
  sd = NA_real_, skewness = NA_real_)
for (i in seq_len(nrow(summ))) {
  x <- d[[summ$variable[i]]]
  summ$n_obs[i] <- sum(!is.na(x))
  summ$pct_missing[i] <- round(100 * mean(is.na(x)), 1)
  summ$mean[i] <- round(mean(x, na.rm = TRUE), 3)
  summ$sd[i]   <- round(sd(x, na.rm = TRUE), 3)
  summ$skewness[i] <- round(skewness(x[!is.na(x)]), 2)
}
write.csv(summ, file.path(tab_dir, "06_outcome_summary.csv"), row.names = FALSE)
write.csv(chk,  file.path(tab_dir, "06_standardisation_check.csv"), row.names = FALSE)

# Correlations among components: the composite assumes they measure a shared
# construct. Weak or negative correlations would undermine equal weighting.
cmat <- round(cor(d[, COMPONENTS], use = "pairwise.complete.obs"), 3)
write.csv(cmat, file.path(tab_dir, "06_component_correlations.csv"))

keep <- c("SEQN","SDMVSTRA","SDMVPSU","WTSAFPRP","RIAGENDR","RIDAGEYR",
          "bp_treated","n_components", COMPONENTS, "map_mmhg_adj",
          "cmd_score","cmd_score_bpadj",
          "log_homa_ir","hba1c_pct","log_hscrp","log_alt","BMXBMI")
saveRDS(d[, keep], file.path(int_dir, "outcome_composite.rds"))

log_msg("complete composite: n = ", sum(!is.na(d$cmd_score)), " of ", nrow(d),
        logfile = logfile)
log_msg("=== 06_outcome_composite.R complete ===", logfile = logfile)

cat("\n--- outcome summary ---\n");        print(summ, row.names = FALSE)
cat("\n--- component correlations ---\n"); print(cmat)
cat("\n--- composite completeness ---\n")
print(table(`n components present` = d$n_components))
