# ---------------------------------------------------------------------------
# 11_collinearity_check.R
# GATE for the substitution models.
#
# The substitution estimand is a DIFFERENCE OF COEFFICIENTS from a model that
# contains all 17 food groups simultaneously plus total energy. That design is
# exactly where collinearity does damage: food-group intakes are correlated
# with each other and, by construction, with total energy. A difference of two
# unstable coefficients is far more unstable than either alone, and the
# instability is invisible in the point estimates.
#
# This script reports the diagnostics BEFORE any swap is estimated, so the
# decision to proceed is made on evidence rather than on hope.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({ library(here); library(survey) })
source(here::here("R", "utils.R"))

int_dir <- here::here("data", "interim")
log_dir <- here::here("outputs", "logs")
tab_dir <- here::here("outputs", "tables")
logfile <- file.path(log_dir, "11_collinearity.log")

log_msg("=== 11_collinearity_check.R start ===", logfile = logfile)

exp <- readRDS(file.path(int_dir, "exposure_pdi.rds"))
imp <- readRDS(file.path(int_dir, "imputed_data.rds"))
COV <- imp$primary_covariates
GROUPS <- exp$groups
GNAMES <- names(GROUPS)

d <- merge(imp$completed[[1]], exp$intake_day1, by = "SEQN")
stopifnot(nrow(d) == nrow(imp$completed[[1]]))
log_msg("analytic sample with food-group intakes: n = ", nrow(d), logfile = logfile)

units <- vapply(GROUPS, `[[`, character(1), "unit")
unit_tab <- data.frame(pdi_group = GNAMES, unit = units,
                       class = vapply(GROUPS, `[[`, character(1), "class"),
                       row.names = NULL)

# --- 1. condition number ---------------------------------------------------
# Computed on the centred and scaled design matrix; the raw-scale condition
# number is dominated by unit differences (grams vs cup-equivalents) and is
# uninformative about actual dependency.
X <- as.matrix(d[, c(GNAMES, "energy_kcal")])
Xs <- scale(X)
sv <- svd(Xs)$d
kappa_scaled <- max(sv) / min(sv)
log_msg(sprintf("condition number (scaled, groups + energy) = %.1f", kappa_scaled),
        logfile = logfile)

# Same, with the covariate block included -- this is the actual model matrix.
Xfull <- model.matrix(as.formula(paste("~", paste(c(GNAMES, COV), collapse = " + "))),
                      data = d)[, -1]
sv_full <- svd(scale(Xfull))$d
kappa_full <- max(sv_full) / min(sv_full)
log_msg(sprintf("condition number (scaled, full model matrix) = %.1f", kappa_full),
        logfile = logfile)

# --- 2. VIF per food group -------------------------------------------------
vif_of <- function(mat) {
  vapply(seq_len(ncol(mat)), function(j) {
    r2 <- summary(lm(mat[, j] ~ mat[, -j]))$r.squared
    1 / (1 - r2)
  }, numeric(1))
}
vif_groups <- data.frame(
  term = colnames(X), VIF = round(vif_of(X), 2), row.names = NULL)
vif_groups$unit <- c(units, "kcal")[match(vif_groups$term, c(GNAMES, "energy_kcal"))]
vif_groups <- vif_groups[order(-vif_groups$VIF), ]

vif_full <- data.frame(term = colnames(Xfull), VIF = round(vif_of(Xfull), 2),
                       row.names = NULL)
vif_full <- vif_full[order(-vif_full$VIF), ]

# --- 3. correlation structure ---------------------------------------------
cmat <- cor(X)
diag(cmat) <- NA
top_pairs <- which(abs(cmat) > 0.4, arr.ind = TRUE)
top_pairs <- top_pairs[top_pairs[, 1] < top_pairs[, 2], , drop = FALSE]
pairs_tab <- if (nrow(top_pairs)) data.frame(
  var1 = colnames(X)[top_pairs[, 1]], var2 = colnames(X)[top_pairs[, 2]],
  r = round(cmat[top_pairs], 3), row.names = NULL) else
  data.frame(var1 = character(), var2 = character(), r = numeric())
pairs_tab <- pairs_tab[order(-abs(pairs_tab$r)), ]

energy_cor <- data.frame(
  pdi_group = GNAMES,
  r_with_energy = round(sapply(GNAMES, function(g) cor(d[[g]], d$energy_kcal)), 3),
  row.names = NULL)
energy_cor <- energy_cor[order(-abs(energy_cor$r_with_energy)), ]

# --- 4. stability of a difference of coefficients --------------------------
# The quantity of interest is beta_Y - beta_X, so its SE depends on the
# COVARIANCE of the two estimates, not only their individual variances.
# Strongly negatively covarying coefficients make the difference more precise
# than either coefficient; positively covarying ones make it worse.
d$hPDI_sd <- d$hPDI / sd(d$hPDI)
des <- svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WTSAFPRP,
                 nest = TRUE, data = d)
f_all <- as.formula(paste("cmd_score ~",
                          paste(c(GNAMES, "energy_kcal", COV), collapse = " + ")))
m_all <- svyglm(f_all, design = des)
V <- vcov(m_all)

unit_pairs <- do.call(rbind, lapply(unique(units), function(u) {
  g <- GNAMES[units == u]
  if (length(g) < 2) return(NULL)
  cb <- t(combn(g, 2))
  data.frame(unit = u, from = cb[, 2], to = cb[, 1], row.names = NULL)
}))
unit_pairs$se_diff <- round(vapply(seq_len(nrow(unit_pairs)), function(i) {
  a <- unit_pairs$to[i]; b <- unit_pairs$from[i]
  sqrt(V[a, a] + V[b, b] - 2 * V[a, b])
}, numeric(1)), 5)
unit_pairs$se_a <- round(sqrt(diag(V)[unit_pairs$to]), 5)
unit_pairs$se_b <- round(sqrt(diag(V)[unit_pairs$from]), 5)
unit_pairs$ratio_to_max_single <- round(unit_pairs$se_diff /
                                        pmax(unit_pairs$se_a, unit_pairs$se_b), 2)

write.csv(unit_tab,   file.path(tab_dir, "11_group_units.csv"), row.names = FALSE)
write.csv(vif_groups, file.path(tab_dir, "11_vif_groups.csv"), row.names = FALSE)
write.csv(vif_full,   file.path(tab_dir, "11_vif_full_model.csv"), row.names = FALSE)
write.csv(pairs_tab,  file.path(tab_dir, "11_group_correlations.csv"), row.names = FALSE)
write.csv(energy_cor, file.path(tab_dir, "11_energy_correlations.csv"), row.names = FALSE)
write.csv(unit_pairs, file.path(tab_dir, "11_substitution_pair_precision.csv"), row.names = FALSE)

log_msg("=== 11_collinearity_check.R complete ===", logfile = logfile)

cat("\n=== CONDITION NUMBERS (scaled) ===\n")
cat(sprintf("  17 food groups + energy : %.1f\n", kappa_scaled))
cat(sprintf("  full model matrix       : %.1f\n", kappa_full))
cat("  (>30 indicates moderate, >100 serious ill-conditioning)\n")

cat("\n=== VIF: food groups + energy ===\n"); print(vif_groups, row.names = FALSE)
cat("\n=== correlations |r| > 0.4 among groups/energy ===\n")
print(if (nrow(pairs_tab)) pairs_tab else "none", row.names = FALSE)
cat("\n=== correlation of each group with total energy (top 8) ===\n")
print(head(energy_cor, 8), row.names = FALSE)
cat("\n=== unit-compatible substitution pairs: SE of the difference ===\n")
print(unit_pairs, row.names = FALSE)
