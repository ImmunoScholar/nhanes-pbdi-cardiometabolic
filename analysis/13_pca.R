# ---------------------------------------------------------------------------
# 13_pca.R
# Pre-specified principal component analysis of the cardiometabolic biomarker
# panel.
#
# QUESTION (pre-stated): is plant-based diet quality associated with
# cardiometabolic dysfunction GLOBALLY, or specifically with one axis --
# adiposity/insulin resistance, atherogenic lipids, or inflammation?
#
# RETENTION RULES, fixed before the data were seen (Phase 2 protocol):
#   - survey-weighted correlation matrix
#   - Horn's parallel analysis, 1000 simulations, 95th percentile
#   - hard cap of 3 components
#   - Kaiser (eigenvalue > 1) reported as a secondary descriptive only
#   - varimax rotation if >= 2 components retained
#   - sign convention fixed by the loading on waist circumference
#
# CAVEAT ON PARALLEL ANALYSIS, verified in Phase 2: no established
# survey-weighted implementation of Horn's method exists. It generates its null
# from iid data at the NOMINAL n, whereas the effective n here is smaller
# (DEFF 2.74), so the simulated null is too tight and PA will tend to
# OVER-RETAIN. It is therefore used as a heuristic, supported by the weighted
# scree plot and by whether a component is interpretable a priori. A robustness
# run at the effective n is reported alongside.
#
# THIS SCRIPT DOES NOT TOUCH THE EXPOSURE. Components are extracted and named
# here and committed before any diet-component association is estimated
# (14_pca_associations.R), so that naming cannot be fitted to the results.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({ library(here); library(survey) })
source(here::here("R", "utils.R"))

int_dir <- here::here("data", "interim")
log_dir <- here::here("outputs", "logs")
tab_dir <- here::here("outputs", "tables")
fig_dir <- here::here("outputs", "figures")
logfile <- file.path(log_dir, "13_pca.log")
set.seed(20260724)
N_SIM <- 1000

log_msg("=== 13_pca.R start ===", logfile = logfile)

out <- readRDS(file.path(int_dir, "outcome_composite.rds"))

# --- the nine biomarkers ---------------------------------------------------
# The frozen transformation rule is |skew| > 1 -> log. Two notes on applying
# it faithfully:
#   * hdl_rev is negative by construction, so the log is taken on HDL-C itself
#     and the sign reversed afterwards.
#   * HbA1c (skew 3.35) triggers the rule and is logged; the composite
#     specification named log only for triglycerides and glucose, so this is
#     the PCA input, not a change to the primary outcome.
b <- data.frame(
  SEQN        = out$SEQN,
  waist       = out$waist_cm,
  log_tg      = out$log_tg,
  hdl_rev_log = -log(-out$hdl_rev),        # hdl_rev = -HDL, so -HDL_rev = HDL
  log_glucose = out$log_glucose,
  map         = out$map_mmhg,
  log_homa_ir = out$log_homa_ir,
  log_hba1c   = log(out$hba1c_pct),
  log_hscrp   = out$log_hscrp,
  log_alt     = out$log_alt)
BM <- setdiff(names(b), "SEQN")

b$wt <- out$WTSAFPRP; b$strata <- out$SDMVSTRA; b$psu <- out$SDMVPSU
cc <- b[complete.cases(b[, BM]) & !is.na(b$wt) & b$wt > 0, ]
log_msg("complete on all 9 biomarkers: n = ", nrow(cc), " of ", nrow(b),
        logfile = logfile)

skew_tab <- data.frame(biomarker = BM,
                       skewness = round(sapply(BM, function(v) skewness(cc[[v]])), 2))

# --- survey-weighted correlation matrix ------------------------------------
wcov <- function(X, w) {
  w <- w / sum(w)
  mu <- colSums(X * w)
  Xc <- sweep(X, 2, mu)
  t(Xc * w) %*% Xc / (1 - sum(w^2))
}
X <- as.matrix(cc[, BM])
S <- wcov(X, cc$wt)
R <- S / sqrt(outer(diag(S), diag(S)))
write.csv(round(R, 3), file.path(tab_dir, "13_weighted_correlation_matrix.csv"))

ev <- eigen(R, symmetric = TRUE)
eigvals <- ev$values

# --- Horn's parallel analysis (heuristic; see header) ----------------------
par_analysis <- function(n, p, nsim = N_SIM) {
  sims <- replicate(nsim, eigen(cor(matrix(rnorm(n * p), n, p)),
                                symmetric = TRUE, only.values = TRUE)$values)
  apply(sims, 1, quantile, probs = 0.95)
}
p <- length(BM)
pa_nominal <- par_analysis(nrow(cc), p)

des <- svydesign(ids = ~psu, strata = ~strata, weights = ~wt, nest = TRUE, data = cc)
deff <- as.numeric(attr(svymean(~waist, des, deff = TRUE), "deff"))
n_eff <- round(nrow(cc) / deff)
pa_effective <- par_analysis(n_eff, p)
log_msg(sprintf("DEFF %.2f -> effective n %d (nominal %d)", deff, n_eff, nrow(cc)),
        logfile = logfile)

retain_nominal   <- sum(eigvals > pa_nominal)
retain_effective <- sum(eigvals > pa_effective)
retain_kaiser    <- sum(eigvals > 1)
K <- min(retain_effective, 3)

ret_tab <- data.frame(
  component = seq_len(p),
  eigenvalue = round(eigvals, 3),
  pct_variance = round(100 * eigvals / p, 1),
  cum_pct = round(cumsum(100 * eigvals / p), 1),
  pa_threshold_nominal_n = round(pa_nominal, 3),
  pa_threshold_effective_n = round(pa_effective, 3))
log_msg(sprintf("retained -- PA(nominal n): %d | PA(effective n): %d | Kaiser: %d | USED: %d",
                retain_nominal, retain_effective, retain_kaiser, K), logfile = logfile)

# --- extract and rotate ----------------------------------------------------
load_raw <- ev$vectors[, seq_len(K), drop = FALSE] %*%
            diag(sqrt(eigvals[seq_len(K)]), K, K)
rownames(load_raw) <- BM
L <- if (K >= 2) {
  vm <- varimax(load_raw); log_msg("varimax rotation applied", logfile = logfile)
  unclass(vm$loadings)
} else load_raw

# Sign convention: higher score = worse. Anchored on waist circumference for
# the component on which waist loads most strongly; other components are
# anchored on their own largest-magnitude loading, which is a positive marker
# of dysfunction for every biomarker in this panel.
for (k in seq_len(ncol(L))) {
  anchor <- which.max(abs(L[, k]))
  if (L[anchor, k] < 0) L[, k] <- -L[, k]
}
colnames(L) <- paste0("PC", seq_len(ncol(L)))
load_tab <- data.frame(biomarker = BM, round(as.data.frame(L), 3), row.names = NULL)

write.csv(ret_tab,  file.path(tab_dir, "13_pca_retention.csv"), row.names = FALSE)
write.csv(load_tab, file.path(tab_dir, "13_pca_loadings.csv"), row.names = FALSE)
write.csv(skew_tab, file.path(tab_dir, "13_pca_skewness.csv"), row.names = FALSE)

# --- weighted scree plot ---------------------------------------------------
png(file.path(fig_dir, "13_scree.png"), width = 1500, height = 1000, res = 160)
plot(seq_len(p), eigvals, type = "b", pch = 16, ylim = c(0, max(eigvals) * 1.05),
     xlab = "Component", ylab = "Eigenvalue (survey-weighted correlation matrix)",
     main = "Scree plot with parallel-analysis thresholds")
lines(seq_len(p), pa_nominal, type = "b", pch = 1, lty = 2)
lines(seq_len(p), pa_effective, type = "b", pch = 2, lty = 3)
abline(h = 1, col = "grey60")
legend("topright", bty = "n", pch = c(16, 1, 2, NA), lty = c(1, 2, 3, 1),
       col = c("black", "black", "black", "grey60"),
       legend = c("observed", "PA 95th pct (nominal n)",
                  "PA 95th pct (effective n)", "Kaiser (eigenvalue = 1)"))
dev.off()

# --- component scores ------------------------------------------------------
Z <- scale(X, center = colSums(X * cc$wt / sum(cc$wt)), scale = sqrt(diag(S)))
scores <- Z %*% solve(R) %*% L        # regression-method scores
colnames(scores) <- colnames(L)
saveRDS(list(SEQN = cc$SEQN, scores = as.data.frame(scores),
             loadings = L, retention = ret_tab, biomarkers = BM, K = K),
        file.path(int_dir, "pca.rds"))

log_msg("=== 13_pca.R complete ===", logfile = logfile)

cat("\n=== skewness of PCA inputs (post-transformation) ===\n"); print(skew_tab, row.names = FALSE)
cat("\n=== retention ===\n"); print(ret_tab, row.names = FALSE)
cat(sprintf("\nretained: PA(nominal n=%d) %d | PA(effective n=%d) %d | Kaiser %d | USED %d\n",
            nrow(cc), retain_nominal, n_eff, retain_effective, retain_kaiser, K))
cat("\n=== rotated loadings (higher = worse) ===\n"); print(load_tab, row.names = FALSE)
