# ---------------------------------------------------------------------------
# 14_pca_associations.R
# Is the hPDI association GLOBAL or AXIS-SPECIFIC?
#
# The interpretation rule was fixed in docs/pca_component_names.md and
# committed BEFORE this script existed:
#   similar magnitude on both axes -> global
#   concentrated on PC1            -> adiposity/inflammation-mediated
#   concentrated on PC2            -> glycaemia-specific
#
# Component scores are standardised to unit weighted variance so that
# coefficients on PC1 and PC2 are directly comparable, and so that they are on
# the same scale as the primary composite result (SD outcome per SD exposure).
#
# A sensitivity analysis re-extracts the components with log(fasting insulin)
# in place of log(HOMA-IR), removing the algebraic entanglement between
# HOMA-IR and fasting glucose flagged in the naming document.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(here); library(survey); library(mitools)
})
source(here::here("R", "utils.R"))

int_dir <- here::here("data", "interim")
log_dir <- here::here("outputs", "logs")
tab_dir <- here::here("outputs", "tables")
logfile <- file.path(log_dir, "14_pca_associations.log")

log_msg("=== 14_pca_associations.R start ===", logfile = logfile)

pca <- readRDS(file.path(int_dir, "pca.rds"))
imp <- readRDS(file.path(int_dir, "imputed_data.rds"))
COV <- imp$primary_covariates
SD_hPDI <- sd(imp$completed[[1]]$hPDI)

fit_axis <- function(score_df, label) {
  sets <- lapply(imp$completed, function(d) {
    m <- merge(d, score_df, by = "SEQN")
    m$hPDI_sd <- m$hPDI / SD_hPDI
    m
  })
  n_used <- nrow(sets[[1]])
  pcs <- setdiff(names(score_df), "SEQN")
  do.call(rbind, lapply(pcs, function(pc) {
    sets2 <- lapply(sets, function(m) {
      w <- m$WTSAFPRP
      mu <- sum(w * m[[pc]]) / sum(w)
      s  <- sqrt(sum(w * (m[[pc]] - mu)^2) / sum(w))
      m[[pc]] <- (m[[pc]] - mu) / s
      m
    })
    fits <- lapply(sets2, function(m)
      svyglm(as.formula(paste(pc, "~ hPDI_sd +", paste(COV, collapse = " + "))),
             design = svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA,
                                weights = ~WTSAFPRP, nest = TRUE, data = m)))
    # summary.MIresult prints as a side effect as well as returning; capture it
    # so the console shows only what this script chooses to report.
    s <- NULL
    invisible(utils::capture.output(s <- summary(MIcombine(fits))))
    data.frame(analysis = label, component = pc, n = n_used,
               estimate = round(s["hPDI_sd", 1], 4),
               se = round(s["hPDI_sd", 2], 4),
               ci_low = round(s["hPDI_sd", 3], 4),
               ci_high = round(s["hPDI_sd", 4], 4),
               row.names = NULL)
  }))
}

primary <- fit_axis(cbind(SEQN = pca$SEQN, pca$scores), "primary (HOMA-IR)")
log_msg("primary axis associations estimated", logfile = logfile)

# --- sensitivity: log(insulin) in place of log(HOMA-IR) -------------------
raw <- readRDS(file.path(int_dir, "nhanes_raw_list.rds"))
out <- readRDS(file.path(int_dir, "outcome_composite.rds"))
ins <- raw$P_INS[, c("SEQN", "LBXIN")]
o2 <- merge(out, ins, by = "SEQN", all.x = TRUE)

b <- data.frame(
  SEQN        = o2$SEQN,
  waist       = o2$waist_cm,
  log_tg      = o2$log_tg,
  hdl_rev_log = -log(-o2$hdl_rev),
  log_glucose = o2$log_glucose,
  map         = o2$map_mmhg,
  log_insulin = ifelse(!is.na(o2$LBXIN) & o2$LBXIN > 0, log(o2$LBXIN), NA),
  log_hba1c   = log(o2$hba1c_pct),
  log_hscrp   = o2$log_hscrp,
  log_alt     = o2$log_alt)
BM <- setdiff(names(b), "SEQN")
b$wt <- o2$WTSAFPRP
cc <- b[complete.cases(b[, BM]) & !is.na(b$wt) & b$wt > 0, ]
log_msg("sensitivity PCA complete cases: n = ", nrow(cc), logfile = logfile)

wcov <- function(X, w) {
  w <- w / sum(w); mu <- colSums(X * w); Xc <- sweep(X, 2, mu)
  t(Xc * w) %*% Xc / (1 - sum(w^2))
}
X <- as.matrix(cc[, BM]); S <- wcov(X, cc$wt)
R <- S / sqrt(outer(diag(S), diag(S)))
ev <- eigen(R, symmetric = TRUE)
K <- pca$K                                   # same number of components as primary
L <- unclass(varimax(ev$vectors[, 1:K, drop = FALSE] %*%
                     diag(sqrt(ev$values[1:K]), K, K))$loadings)
rownames(L) <- BM
for (k in seq_len(ncol(L))) if (L[which.max(abs(L[, k])), k] < 0) L[, k] <- -L[, k]
colnames(L) <- paste0("PC", seq_len(K))

Z <- scale(X, center = colSums(X * cc$wt / sum(cc$wt)), scale = sqrt(diag(S)))
sc <- as.data.frame(Z %*% solve(R) %*% L); names(sc) <- colnames(L)
sens <- fit_axis(cbind(SEQN = cc$SEQN, sc), "sensitivity (insulin)")

sens_load <- data.frame(biomarker = BM, round(as.data.frame(L), 3), row.names = NULL)
write.csv(sens_load, file.path(tab_dir, "14_sensitivity_loadings.csv"), row.names = FALSE)

res <- rbind(primary, sens)
write.csv(res, file.path(tab_dir, "14_pca_associations.csv"), row.names = FALSE)

# --- apply the pre-stated interpretation rule ------------------------------
p1 <- primary$estimate[primary$component == "PC1"]
p2 <- primary$estimate[primary$component == "PC2"]
ratio <- abs(p1) / max(abs(p2), 1e-8)
verdict <- {
  if (ratio > 2) "concentrated on PC1 (adiposity/inflammation axis)"
  else if (ratio < 0.5) "concentrated on PC2 (glycaemic axis)"
  else "similar magnitude on both axes -> global association"
}
log_msg("interpretation rule: |PC1|/|PC2| = ", round(ratio, 2), " -> ", verdict,
        logfile = logfile)

log_msg("=== 14_pca_associations.R complete ===", logfile = logfile)
cat("\n=== hPDI (per SD) -> component scores (per SD) ===\n")
print(res, row.names = FALSE)
cat("\n=== sensitivity loadings (insulin in place of HOMA-IR) ===\n")
print(sens_load, row.names = FALSE)
cat(sprintf("\n=== PRE-STATED INTERPRETATION RULE ===\n|PC1|/|PC2| = %.2f -> %s\n",
            ratio, verdict))
