# ---------------------------------------------------------------------------
# 12_models_substitution.R
# LEAD CONTRIBUTION: isocaloric food-group substitution within the PDI
# framework.
#
# Method (Willett's all-components substitution model): fit one model
# containing ALL 17 food groups simultaneously plus total energy and the
# covariate set. Holding total energy constant, the effect of replacing one
# unit of food X with one unit of food Y is the linear contrast
#
#     beta_Y - beta_X
#
# with SE = sqrt(V_YY + V_XX - 2*V_XY), so the covariance between the two
# coefficients is used rather than ignored.
#
# UNIT COMPATIBILITY. Groups are measured in ounce-equivalents,
# cup-equivalents or grams, and a swap is only interpretable between groups
# sharing a unit. This is a real constraint, not a convenience: it means some
# scientifically interesting swaps (for example sweets/desserts for whole
# fruit) CANNOT be estimated here, because grams of confectionery and
# cup-equivalents of fruit are not exchangeable quantities. Those are reported
# as not estimable rather than approximated.
#
# Gram-unit groups are rescaled to PER 100 G so that coefficients are on an
# interpretable scale (1 g of a beverage is not a meaningful swap).
#
# ATTENUATION. These estimates are NAIVE with respect to measurement error.
# The correction in 10_calibration.R applies to the index, not to individual
# food groups, which are measured with MORE error than the index that
# aggregates them. Substitution estimates here are therefore attenuated,
# probably by more than the 2.58x factor found for hPDI. They are a lower
# bound on the magnitude of the association.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(here); library(survey); library(mitools)
})
source(here::here("R", "utils.R"))

int_dir <- here::here("data", "interim")
log_dir <- here::here("outputs", "logs")
tab_dir <- here::here("outputs", "tables")
logfile <- file.path(log_dir, "12_substitution.log")

log_msg("=== 12_models_substitution.R start ===", logfile = logfile)

exp <- readRDS(file.path(int_dir, "exposure_pdi.rds"))
imp <- readRDS(file.path(int_dir, "imputed_data.rds"))
COV <- imp$primary_covariates
GROUPS <- exp$groups; GNAMES <- names(GROUPS)
units <- vapply(GROUPS, `[[`, character(1), "unit")

# --- assemble, rescaling gram-unit groups to per 100 g --------------------
GRAM_GROUPS <- GNAMES[units == "grams"]
completed <- lapply(imp$completed, function(d) {
  m <- merge(d, exp$intake_day1, by = "SEQN")
  stopifnot(nrow(m) == nrow(d))
  for (g in GRAM_GROUPS) m[[g]] <- m[[g]] / 100
  m
})
unit_label <- ifelse(units == "grams", "per 100 g", paste("per", units))
names(unit_label) <- GNAMES
log_msg("gram-unit groups rescaled to per 100 g: ",
        paste(GRAM_GROUPS, collapse = ", "), logfile = logfile)

# --- all-components model, pooled across imputations ----------------------
f_sub <- as.formula(paste("cmd_score ~",
                          paste(c(GNAMES, "energy_kcal", COV), collapse = " + ")))
fits <- lapply(completed, function(d)
  svyglm(f_sub, design = svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA,
                                   weights = ~WTSAFPRP, nest = TRUE, data = d)))
pooled <- MIcombine(fits)
B <- coef(pooled); V <- vcov(pooled)
log_msg("all-components model fitted and pooled (m = ", length(fits), ")",
        logfile = logfile)

# individual coefficients, for transparency
coef_tab <- data.frame(
  pdi_group = GNAMES, unit = unit_label[GNAMES],
  class = vapply(GROUPS, `[[`, character(1), "class"),
  beta = round(B[GNAMES], 5), se = round(sqrt(diag(V)[GNAMES]), 5),
  row.names = NULL)
coef_tab$ci_low  <- round(coef_tab$beta - 1.96 * coef_tab$se, 5)
coef_tab$ci_high <- round(coef_tab$beta + 1.96 * coef_tab$se, 5)
write.csv(coef_tab, file.path(tab_dir, "12_all_components_coefficients.csv"),
          row.names = FALSE)

# --- substitution contrast -------------------------------------------------
swap <- function(from, to) {
  stopifnot(units[from] == units[to])
  est <- B[to] - B[from]
  se  <- sqrt(V[to, to] + V[from, from] - 2 * V[to, from])
  z   <- est / se
  data.frame(from = from, to = to, unit = unlist(unit_label[from]),
             estimate = unname(est), se = unname(se),
             ci_low = unname(est - 1.96 * se), ci_high = unname(est + 1.96 * se),
             p_raw = unname(2 * pnorm(-abs(z))), row.names = NULL)
}

# --- PRE-SPECIFIED swaps (H3) ---------------------------------------------
PRESPEC <- list(
  c("refined_grains", "whole_grains"),
  c("fruit_juices",   "fruits"),
  c("potatoes",       "legumes"),
  c("ssb",            "tea_coffee"),
  c("meat",           "nuts"))
prespec <- do.call(rbind, lapply(PRESPEC, function(p) swap(p[1], p[2])))
prespec$p_fdr <- p.adjust(prespec$p_raw, method = "BH")

# --- EXPLORATORY: every other unit-compatible pair -------------------------
# Each UNORDERED pair is tested once. Reversing a swap only flips the sign of
# the same contrast, so including both directions would double the number of
# tests without adding information and would make the FDR correction
# needlessly conservative. The reverse direction is recoverable by negation.
all_pairs <- do.call(rbind, lapply(unique(units), function(u) {
  g <- GNAMES[units == u]
  if (length(g) < 2) return(NULL)
  cb <- t(combn(g, 2))
  data.frame(from = cb[, 1], to = cb[, 2])
}))
prekey <- vapply(PRESPEC, function(p) paste(sort(p), collapse = "|"), character(1))
key <- vapply(seq_len(nrow(all_pairs)),
              function(i) paste(sort(c(all_pairs$from[i], all_pairs$to[i])),
                                collapse = "|"), character(1))
explore <- all_pairs[!key %in% prekey, ]
exploratory <- do.call(rbind, Map(swap, explore$from, explore$to))
exploratory$p_fdr <- p.adjust(exploratory$p_raw, method = "BH")
exploratory <- exploratory[order(exploratory$p_fdr), ]

rnd <- function(df) { num <- sapply(df, is.numeric)
  df[num] <- lapply(df[num], function(x) signif(x, 3)); df }

write.csv(rnd(prespec),     file.path(tab_dir, "12_substitution_prespecified.csv"), row.names = FALSE)
write.csv(rnd(exploratory), file.path(tab_dir, "12_substitution_exploratory.csv"), row.names = FALSE)

# --- swaps that CANNOT be estimated ---------------------------------------
not_estimable <- data.frame(
  intended_swap = c("sweets/desserts -> whole fruit",
                    "sweets/desserts -> nuts",
                    "SSB -> whole fruit",
                    "refined grains -> legumes",
                    "meat -> legumes"),
  reason = c("grams vs cup-equivalents", "grams vs ounce-equivalents",
             "grams vs cup-equivalents", "ounce- vs cup-equivalents",
             "ounce- vs cup-equivalents"))
write.csv(not_estimable, file.path(tab_dir, "12_not_estimable_swaps.csv"), row.names = FALSE)

saveRDS(list(pooled = pooled, coef_tab = coef_tab,
             prespec = prespec, exploratory = exploratory),
        file.path(int_dir, "substitution.rds"))

log_msg("=== 12_models_substitution.R complete ===", logfile = logfile)

cat("\n=== PRE-SPECIFIED SUBSTITUTIONS (H3) ===\n")
cat("negative = replacing 'from' with 'to' is associated with LOWER dysfunction\n\n")
print(rnd(prespec), row.names = FALSE)
cat("\n=== ALL-COMPONENTS MODEL: individual group coefficients ===\n")
print(coef_tab, row.names = FALSE)
cat("\n=== EXPLORATORY SWAPS: top 10 by FDR ===\n")
print(head(rnd(exploratory), 10), row.names = FALSE)
cat("\n=== SWAPS NOT ESTIMABLE (unit incompatibility) ===\n")
print(not_estimable, row.names = FALSE)
