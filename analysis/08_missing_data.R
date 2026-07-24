# ---------------------------------------------------------------------------
# 08_missing_data.R
# Multiple imputation of covariates under the complex survey design.
#
# Strategy: MULTIPLE IMPUTATION THEN DELETION (von Hippel). Everything is
# imputed -- including the outcome, so that outcome information is used to
# impute covariates without discarding it -- and records whose OUTCOME was
# imputed are then deleted. Imputing an outcome adds noise without adding
# information when no auxiliary predictors of it exist; using it as a predictor
# of the covariates does add information.
#
# Design information enters the imputation model directly (log survey weight
# and stratum), per standard practice for imputation under complex designs.
# The design is then fully respected again at the analysis stage: each
# completed dataset is analysed with svydesign() and results pooled with
# Rubin's rules. Imputing without design information and then analysing with
# it would be uncongenial.
#
# This script imputes and diagnoses only. No model of scientific interest is
# fitted here.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({ library(here); library(mice) })
source(here::here("R", "utils.R"))

int_dir <- here::here("data", "interim")
log_dir <- here::here("outputs", "logs")
tab_dir <- here::here("outputs", "tables")
fig_dir <- here::here("outputs", "figures")
logfile <- file.path(log_dir, "08_missing_data.log")

set.seed(20260724)          # reproducibility: imputation is stochastic
M_IMPUTATIONS <- 20
MAXIT <- 20

log_msg("=== 08_missing_data.R start ===", logfile = logfile)

ad  <- readRDS(file.path(int_dir, "analytic_dataset.rds"))
an  <- ad$analytic
COV <- ad$primary_covariates

# --- assemble the imputation frame ----------------------------------------
FLAGS <- c("diabetes_dx", "cvd_dx", "bp_med", "lipid_med", "tried_lose_wt")
imp_df <- an[, c("SEQN", "cmd_score", "PDI", "hPDI", "uPDI", COV, FLAGS)]
for (f in FLAGS) imp_df[[f]] <- factor(imp_df[[f]], levels = c(FALSE, TRUE),
                                       labels = c("No", "Yes"))

# Design information as predictors. The weight enters on the log scale because
# NHANES weights are strongly right-skewed.
imp_df$log_wt <- log(an$WTSAFPRP)
imp_df$strata <- factor(an$SDMVSTRA)
log_msg("imputation frame: n = ", nrow(imp_df), ", ",
        nlevels(imp_df$strata), " strata", logfile = logfile)

pre <- data.frame(variable = setdiff(names(imp_df), "SEQN"),
                  pct_missing = round(100 * sapply(setdiff(names(imp_df), "SEQN"),
                                      function(v) mean(is.na(imp_df[[v]]))), 2))
pre <- pre[order(-pre$pct_missing), ]
log_msg("variables with missing data: ",
        sum(pre$pct_missing > 0), logfile = logfile)

# --- imputation model ------------------------------------------------------
ini <- mice(imp_df, maxit = 0, printFlag = FALSE)
meth <- ini$method
pred <- ini$predictorMatrix

pred[, "SEQN"] <- 0; pred["SEQN", ] <- 0; meth["SEQN"] <- ""
# Design variables predict, but are never themselves imputed (they are complete).
meth[c("log_wt", "strata")] <- ""

log_msg("methods: ", paste(sprintf("%s=%s", names(meth)[meth != ""],
                                   meth[meth != ""]), collapse = ", "),
        logfile = logfile)

t0 <- Sys.time()
imp <- mice(imp_df, m = M_IMPUTATIONS, maxit = MAXIT, method = meth,
            predictorMatrix = pred, printFlag = FALSE, seed = 20260724)
log_msg("imputation complete in ", round(difftime(Sys.time(), t0, units = "mins"), 1),
        " min", logfile = logfile)

if (length(imp$loggedEvents)) {
  write.csv(imp$loggedEvents, file.path(log_dir, "08_mice_logged_events.csv"),
            row.names = FALSE)
  log_msg(nrow(imp$loggedEvents), " logged events (collinearity / constants) ",
          "-- see 08_mice_logged_events.csv", level = "WARN", logfile = logfile)
}

# --- MID: delete records whose OUTCOME was imputed -------------------------
outcome_observed <- !is.na(imp_df$cmd_score)
log_msg("outcome observed in ", sum(outcome_observed), " of ", nrow(imp_df),
        "; records with imputed outcome are deleted (MID)", logfile = logfile)

completed <- lapply(seq_len(M_IMPUTATIONS), function(i) {
  d <- complete(imp, i)
  d <- cbind(d, an[, c("SDMVSTRA", "SDMVPSU", "WTSAFPRP")])
  d[outcome_observed, ]
})
log_msg("each completed dataset: n = ", nrow(completed[[1]]), logfile = logfile)

# --- diagnostics -----------------------------------------------------------
# 1. Convergence: chains should mix, with no trend across iterations.
png(file.path(fig_dir, "08_mice_convergence.png"), width = 2000, height = 1400, res = 160)
print(plot(imp, layout = c(2, 4)))
dev.off()

# 2. Observed vs imputed distributions for the continuous variables that
#    actually had missing data. Systematic divergence is not proof of error --
#    MAR implies imputed values may differ -- but a gross shift warrants review.
cont_missing <- intersect(c("pir", "alcohol_dpd", "met_min_wk", "energy_kcal"),
                          pre$variable[pre$pct_missing > 0])
png(file.path(fig_dir, "08_observed_vs_imputed.png"), width = 1800, height = 1200, res = 160)
print(densityplot(imp, ~ pir + alcohol_dpd + met_min_wk))
dev.off()

obs_imp <- do.call(rbind, lapply(cont_missing, function(v) {
  obs <- imp_df[[v]][!is.na(imp_df[[v]])]
  im  <- unlist(lapply(seq_len(M_IMPUTATIONS), function(i) {
    d <- complete(imp, i); d[[v]][is.na(imp_df[[v]])] }))
  data.frame(variable = v, n_observed = length(obs), n_imputed_cells = length(im) / M_IMPUTATIONS,
             mean_observed = round(mean(obs), 3), mean_imputed = round(mean(im), 3),
             sd_observed = round(sd(obs), 3), sd_imputed = round(sd(im), 3))
}))
write.csv(obs_imp, file.path(tab_dir, "08_observed_vs_imputed.csv"), row.names = FALSE)

# 3. Complete-case vs imputed covariate distributions. A material difference
#    indicates the complete-case sample is selected, i.e. that imputation is
#    doing real work rather than cosmetic work.
cc <- ad$complete_case
cmp <- do.call(rbind, lapply(intersect(c("pir","alcohol_dpd","met_min_wk","energy_kcal","age_years"), COV),
  function(v) {
    pooled <- mean(sapply(completed, function(d) mean(d[[v]], na.rm = TRUE)))
    data.frame(variable = v,
               complete_case_mean = round(mean(cc[[v]], na.rm = TRUE), 3),
               imputed_mean = round(pooled, 3),
               difference = round(pooled - mean(cc[[v]], na.rm = TRUE), 3))
  }))
write.csv(cmp, file.path(tab_dir, "08_completecase_vs_imputed.csv"), row.names = FALSE)

saveRDS(list(mids = imp, completed = completed,
             outcome_observed = outcome_observed,
             m = M_IMPUTATIONS, primary_covariates = COV),
        file.path(int_dir, "imputed_data.rds"))

write.csv(pre, file.path(tab_dir, "08_premputation_missingness.csv"), row.names = FALSE)
log_msg("=== 08_missing_data.R complete ===", logfile = logfile)

cat("\n--- pre-imputation missingness ---\n"); print(pre[pre$pct_missing > 0, ], row.names = FALSE)
cat("\n--- observed vs imputed ---\n");         print(obs_imp, row.names = FALSE)
cat("\n--- complete-case vs imputed means ---\n"); print(cmp, row.names = FALSE)
cat(sprintf("\nanalysis datasets: m = %d, each n = %d\n",
            M_IMPUTATIONS, nrow(completed[[1]])))
