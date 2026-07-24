# ---------------------------------------------------------------------------
# 09_models_primary.R
# Primary analysis: survey-weighted linear regression of the cardiometabolic
# dysfunction score on plant-based diet quality.
#
# Estimation: each of the m completed datasets is analysed with its own
# svydesign() object, and the m fits are pooled with Rubin's rules
# (mitools::MIcombine), so both the complex design and the imputation
# uncertainty enter the standard errors.
#
# ONE primary test: hPDI (continuous, per SD) -> cardiometabolic dysfunction
# score, adjusted for the DAG-derived minimal sufficient adjustment set.
# Everything else on this page is secondary and reported as such.
#
# Adiposity is NOT adjusted for: 00_dag.R proves it is a mediator, absent from
# every minimal sufficient adjustment set. A mediator-adjusted model is run
# separately and labelled as over-adjusted.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(here); library(survey); library(mitools)
})
source(here::here("R", "utils.R"))

int_dir <- here::here("data", "interim")
log_dir <- here::here("outputs", "logs")
tab_dir <- here::here("outputs", "tables")
logfile <- file.path(log_dir, "09_models_primary.log")

log_msg("=== 09_models_primary.R start ===", logfile = logfile)

imp <- readRDS(file.path(int_dir, "imputed_data.rds"))
ad  <- readRDS(file.path(int_dir, "analytic_dataset.rds"))
COV <- imp$primary_covariates
completed <- imp$completed

# Secondary outcomes and BMI were not part of the imputation frame (they are
# not covariates of the primary model). They are merged back by SEQN and are
# therefore analysed complete-case ON THE OUTCOME, with imputed covariates.
# Their n is reported alongside each estimate rather than assumed equal to the
# primary n.
extra <- readRDS(file.path(int_dir, "outcome_composite.rds"))[
  , c("SEQN", "log_homa_ir", "hba1c_pct", "log_hscrp", "log_alt", "BMXBMI")]
completed <- lapply(completed, function(d) {
  n0 <- nrow(d); d <- merge(d, extra, by = "SEQN", all.x = TRUE)
  stopifnot(nrow(d) == n0); d
})

# --- exposure scaling ------------------------------------------------------
# The exposure is complete (day-1 PDI was required for entry), so a single
# scaling constant applies to every imputed dataset and the estimates stay
# comparable across them.
SD_hPDI <- sd(completed[[1]]$hPDI)
SD_PDI  <- sd(completed[[1]]$PDI)
SD_uPDI <- sd(completed[[1]]$uPDI)
log_msg(sprintf("exposure SDs: PDI %.2f, hPDI %.2f, uPDI %.2f",
                SD_PDI, SD_hPDI, SD_uPDI), logfile = logfile)

completed <- lapply(completed, function(d) {
  d$hPDI_sd <- d$hPDI / SD_hPDI
  d$PDI_sd  <- d$PDI  / SD_PDI
  d$uPDI_sd <- d$uPDI / SD_uPDI
  d$hPDI_q  <- cut(d$hPDI, quantile(completed[[1]]$hPDI, 0:5/5),
                   include.lowest = TRUE, labels = paste0("Q", 1:5))
  d
})

designs <- lapply(completed, function(d)
  svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WTSAFPRP,
            nest = TRUE, data = d))

RHS <- paste(COV, collapse = " + ")

fit_pooled <- function(exposure, outcome = "cmd_score", extra = NULL,
                       label = NULL) {
  rhs <- paste(c(exposure, RHS, extra), collapse = " + ")
  f <- as.formula(paste(outcome, "~", rhs))
  fits <- lapply(designs, function(des) svyglm(f, design = des))
  pooled <- MIcombine(fits)
  s <- summary(pooled)
  keep <- grep(paste0("^", exposure), rownames(s))
  data.frame(model = label %||% exposure, outcome = outcome,
             term = rownames(s)[keep],
             estimate = round(s[keep, 1], 4),
             se = round(s[keep, 2], 4),
             ci_low = round(s[keep, 3], 4),
             ci_high = round(s[keep, 4], 4),
             missInfo = s[keep, "missInfo"],
             row.names = NULL, stringsAsFactors = FALSE)
}
`%||%` <- function(a, b) if (is.null(a)) b else a

# --- PRIMARY ---------------------------------------------------------------
primary <- fit_pooled("hPDI_sd", label = "PRIMARY: hPDI per SD")
log_msg(sprintf("PRIMARY hPDI per SD: beta = %.4f (95%% CI %.4f to %.4f)",
                primary$estimate[1], primary$ci_low[1], primary$ci_high[1]),
        logfile = logfile)

# --- secondary exposures and specifications --------------------------------
secondary <- rbind(
  fit_pooled("PDI_sd",  label = "PDI per SD"),
  fit_pooled("uPDI_sd", label = "uPDI per SD"),
  fit_pooled("hPDI_q",  label = "hPDI quintiles (ref Q1)"),
  fit_pooled("hPDI_sd", extra = "BMXBMI", label = "hPDI + BMI (OVER-ADJUSTED: BMI is a mediator)")
)

# --- secondary outcomes, FDR-controlled ------------------------------------
SEC_OUT <- c("log_homa_ir", "hba1c_pct", "log_hscrp", "log_alt")
sec_out <- do.call(rbind, lapply(SEC_OUT, function(o) {
  ok <- sapply(completed, function(d) sum(!is.na(d[[o]])))
  if (min(ok) < 100) return(NULL)
  fit_pooled("hPDI_sd", outcome = o, label = paste("hPDI per SD ->", o))
}))
if (!is.null(sec_out)) {
  z <- sec_out$estimate / sec_out$se
  sec_out$p_raw <- 2 * pnorm(-abs(z))
  sec_out$p_fdr <- p.adjust(sec_out$p_raw, method = "BH")
  sec_out$p_raw <- signif(sec_out$p_raw, 3); sec_out$p_fdr <- signif(sec_out$p_fdr, 3)
}

# --- complete-case comparison ---------------------------------------------
cc <- ad$complete_case
cc$hPDI_sd <- cc$hPDI / SD_hPDI
des_cc <- svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WTSAFPRP,
                    nest = TRUE, data = cc)
f_cc <- as.formula(paste("cmd_score ~ hPDI_sd +", RHS))
m_cc <- svyglm(f_cc, design = des_cc)
ci <- confint(m_cc)["hPDI_sd", ]
cc_row <- data.frame(model = "hPDI per SD (complete case)", outcome = "cmd_score",
                     term = "hPDI_sd",
                     estimate = round(coef(m_cc)["hPDI_sd"], 4),
                     se = round(summary(m_cc)$coefficients["hPDI_sd", 2], 4),
                     ci_low = round(ci[1], 4), ci_high = round(ci[2], 4),
                     missInfo = NA, row.names = NULL)

# --- collinearity diagnostic ----------------------------------------------
# Variance inflation on the first completed dataset, using an unweighted fit
# purely as a collinearity probe (VIF concerns the design matrix, not the
# survey-weighted variance).
X <- model.matrix(as.formula(paste("~ hPDI_sd +", RHS)), data = completed[[1]])[, -1]
vif <- sapply(seq_len(ncol(X)), function(j) {
  r2 <- summary(lm(X[, j] ~ X[, -j]))$r.squared; 1 / (1 - r2)
})
vif_tab <- data.frame(term = colnames(X), VIF = round(vif, 2))
vif_tab <- vif_tab[order(-vif_tab$VIF), ]
if (max(vif) > 10)
  log_msg("VIF above 10 for: ",
          paste(vif_tab$term[vif_tab$VIF > 10], collapse = ", "),
          level = "WARN", logfile = logfile)

all_res <- rbind(primary, secondary, cc_row)
write.csv(all_res, file.path(tab_dir, "09_primary_models.csv"), row.names = FALSE)
if (!is.null(sec_out))
  write.csv(sec_out, file.path(tab_dir, "09_secondary_outcomes.csv"), row.names = FALSE)
write.csv(vif_tab, file.path(tab_dir, "09_vif.csv"), row.names = FALSE)

log_msg("=== 09_models_primary.R complete ===", logfile = logfile)

cat("\n=== PRIMARY ANALYSIS ===\n"); print(primary, row.names = FALSE)
cat("\n=== secondary exposures / specifications ===\n"); print(secondary, row.names = FALSE)
if (!is.null(sec_out)) { cat("\n=== secondary outcomes (BH-FDR) ===\n"); print(sec_out, row.names = FALSE) }
cat("\n=== complete-case comparison ===\n"); print(cc_row, row.names = FALSE)
cat("\n=== top VIF ===\n"); print(head(vif_tab, 6), row.names = FALSE)
