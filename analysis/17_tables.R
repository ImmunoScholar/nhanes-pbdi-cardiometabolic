# ---------------------------------------------------------------------------
# 17_tables.R
# Generate every manuscript table directly from stored analysis objects.
# No number in the manuscript is transcribed by hand; each table here is the
# single source for its corresponding table in the paper.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({ library(here); library(survey) })
source(here::here("R", "utils.R"))

int_dir <- here::here("data", "interim")
tab_dir <- here::here("outputs", "tables")
log_dir <- here::here("outputs", "logs")
logfile <- file.path(log_dir, "17_tables.log")
log_msg("=== 17_tables.R start ===", logfile = logfile)

imp  <- readRDS(file.path(int_dir, "imputed_data.rds"))
ad   <- readRDS(file.path(int_dir, "analytic_dataset.rds"))
sens <- readRDS(file.path(int_dir, "sensitivity.rds"))
cal  <- readRDS(file.path(int_dir, "calibration.rds"))
sub  <- readRDS(file.path(int_dir, "substitution.rds"))
COV  <- imp$primary_covariates

md_table <- function(df, path) {
  hdr <- paste("|", paste(names(df), collapse = " | "), "|")
  sep <- paste("|", paste(rep("---", ncol(df)), collapse = " | "), "|")
  rows <- apply(df, 1, function(r) paste("|", paste(r, collapse = " | "), "|"))
  writeLines(c(hdr, sep, rows), path)
}

# --- Table 1: weighted characteristics by hPDI quintile --------------------
# Described with OBSERVED values, not imputed, so the table reports the sample
# as measured; missingness is reported alongside rather than filled in.
an <- ad$analytic
an <- an[an$SEQN %in% imp$completed[[1]]$SEQN, ]
an$hPDI_q <- cut(an$hPDI, quantile(an$hPDI, 0:5 / 5), include.lowest = TRUE,
                 labels = paste0("Q", 1:5))
des <- svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WTSAFPRP,
                 nest = TRUE, data = an)

cont_vars <- c("age_years", "pir", "energy_kcal", "met_min_wk", "alcohol_dpd",
               "BMXBMI", "waist_cm", "map_mmhg", "cmd_score", "hPDI")
cat_vars  <- c("sex", "race_eth", "education3", "smoking3", "supplement_any")

t1_cont <- do.call(rbind, lapply(cont_vars, function(v) {
  f <- as.formula(paste0("~", v))
  ov <- svymean(f, des, na.rm = TRUE)
  by <- svyby(f, ~hPDI_q, des, svymean, na.rm = TRUE)
  data.frame(characteristic = paste0(v, ", mean (SE)"),
             overall = sprintf("%.2f (%.2f)", coef(ov), SE(ov)),
             setNames(as.list(sprintf("%.2f (%.2f)", by[[2]], by[[3]])),
                      paste0("Q", 1:5)),
             pct_missing = round(100 * mean(is.na(an[[v]])), 1),
             row.names = NULL, check.names = FALSE)
}))

t1_cat <- do.call(rbind, lapply(cat_vars, function(v) {
  f <- as.formula(paste0("~", v))
  ov <- svymean(f, des, na.rm = TRUE)
  by <- svyby(f, ~hPDI_q, des, svymean, na.rm = TRUE)
  lv <- levels(an[[v]])
  do.call(rbind, lapply(seq_along(lv), function(i) {
    data.frame(characteristic = paste0(v, " = ", lv[i], ", %"),
               overall = sprintf("%.1f", 100 * coef(ov)[i]),
               setNames(as.list(sprintf("%.1f", 100 * by[[1 + i]])), paste0("Q", 1:5)),
               pct_missing = round(100 * mean(is.na(an[[v]])), 1),
               row.names = NULL, check.names = FALSE)
  }))
}))

n_by_q <- data.frame(characteristic = "n (unweighted)",
                     overall = as.character(nrow(an)),
                     setNames(as.list(as.character(table(an$hPDI_q))), paste0("Q", 1:5)),
                     pct_missing = 0, check.names = FALSE)
T1 <- rbind(n_by_q, t1_cont, t1_cat)
write.csv(T1, file.path(tab_dir, "T1_characteristics.csv"), row.names = FALSE)
md_table(T1, file.path(tab_dir, "T1_characteristics.md"))

# --- Table 2: primary and secondary associations ---------------------------
T2 <- read.csv(file.path(tab_dir, "09_primary_models.csv"))
T2$estimate_ci <- sprintf("%.3f (%.3f, %.3f)", T2$estimate, T2$ci_low, T2$ci_high)
T2 <- T2[, c("model", "outcome", "term", "estimate_ci")]
sec <- read.csv(file.path(tab_dir, "09_secondary_outcomes.csv"))
sec$estimate_ci <- sprintf("%.3f (%.3f, %.3f)", sec$estimate, sec$ci_low, sec$ci_high)
T2b <- data.frame(model = sec$model, outcome = sec$outcome, term = "hPDI_sd",
                  estimate_ci = sec$estimate_ci, p_fdr = signif(sec$p_fdr, 3))
T2$p_fdr <- NA
T2 <- rbind(T2, T2b)
write.csv(T2, file.path(tab_dir, "T2_primary_secondary.csv"), row.names = FALSE)
md_table(T2, file.path(tab_dir, "T2_primary_secondary.md"))

# --- Table 3: substitution -------------------------------------------------
T3 <- sub$prespec
T3$estimate_ci <- sprintf("%.4f (%.4f, %.4f)", T3$estimate, T3$ci_low, T3$ci_high)
T3 <- data.frame(replace = T3$from, with = T3$to, unit = T3$unit,
                 estimate_ci = T3$estimate_ci, p_fdr = signif(T3$p_fdr, 3))
write.csv(T3, file.path(tab_dir, "T3_substitution.csv"), row.names = FALSE)
md_table(T3, file.path(tab_dir, "T3_substitution.md"))

# --- Table 4: measurement-error calibration --------------------------------
T4 <- read.csv(file.path(tab_dir, "10_calibration_results.csv"))
T4$estimate_ci <- sprintf("%.4f (%.4f, %.4f)", T4$estimate, T4$ci_low, T4$ci_high)
T4 <- T4[, c("quantity", "estimate_ci")]
write.csv(T4, file.path(tab_dir, "T4_calibration.csv"), row.names = FALSE)
md_table(T4, file.path(tab_dir, "T4_calibration.md"))

# --- Table 5: sensitivity audit --------------------------------------------
T5 <- sens$audit[, c("analysis", "n", "exposure", "weight", "beta", "ci",
                     "pct_change_vs_primary", "inference_unchanged")]
write.csv(T5, file.path(tab_dir, "T5_sensitivity_audit.csv"), row.names = FALSE)
md_table(T5, file.path(tab_dir, "T5_sensitivity_audit.md"))

# --- Table 6: axis-specific associations (exploratory) ---------------------
T6 <- read.csv(file.path(tab_dir, "14_pca_associations.csv"))
T6$estimate_ci <- sprintf("%.4f (%.4f, %.4f)", T6$estimate, T6$ci_low, T6$ci_high)
T6 <- T6[, c("analysis", "component", "n", "estimate_ci")]
write.csv(T6, file.path(tab_dir, "T6_axis_associations.csv"), row.names = FALSE)
md_table(T6, file.path(tab_dir, "T6_axis_associations.md"))

log_msg("=== 17_tables.R complete ===", logfile = logfile)
cat("\n--- Table 1 (head) ---\n"); print(head(T1[, 1:7], 8), row.names = FALSE)
cat("\n--- Table 3: substitution ---\n"); print(T3, row.names = FALSE)
cat("\n--- Table 4: calibration ---\n"); print(T4, row.names = FALSE)
