# ---------------------------------------------------------------------------
# 15_sensitivity.R
# Pre-specified sensitivity suite, run in the order fixed by the PI.
#
# The question every analysis here answers is the same:
#   would reasonable alternative assumptions materially change the conclusion?
#
# No analysis in this script is a candidate for the primary result. The primary
# specification is fixed and reported in 09_models_primary.R. Everything here
# is reported whether or not it is favourable, and all rows land in one audit
# table so that selective reporting is not possible after the fact.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(here); library(survey); library(mitools); library(splines)
})
source(here::here("R", "utils.R"))

int_dir <- here::here("data", "interim")
log_dir <- here::here("outputs", "logs")
tab_dir <- here::here("outputs", "tables")
logfile <- file.path(log_dir, "15_sensitivity.log")

log_msg("=== 15_sensitivity.R start ===", logfile = logfile)

imp <- readRDS(file.path(int_dir, "imputed_data.rds"))
exp <- readRDS(file.path(int_dir, "exposure_pdi.rds"))
out <- readRDS(file.path(int_dir, "outcome_composite.rds"))
raw <- readRDS(file.path(int_dir, "nhanes_raw_list.rds"))
COV <- imp$primary_covariates
RHS <- paste(COV, collapse = " + ")

SD_hPDI     <- sd(imp$completed[[1]]$hPDI)
SD_hPDI_alt <- sd(exp$pdi_day1_sensitivity$hPDI)

# --- assemble everything the suite needs -----------------------------------
d1w  <- raw$P_DR1TOT[, c("SEQN", "WTDRD1PP")]
bmx  <- raw$P_BMX[,   c("SEQN", "BMXWT", "BMXHT")]
alt  <- exp$pdi_day1_sensitivity[, c("SEQN", "hPDI")]; names(alt)[2] <- "hPDI_alt"
bpadj<- out[, c("SEQN", "cmd_score_bpadj", "BMXBMI")]

sets <- lapply(imp$completed, function(d) {
  n0 <- nrow(d)
  d <- merge(d, d1w,   by = "SEQN", all.x = TRUE)
  d <- merge(d, bmx,   by = "SEQN", all.x = TRUE)
  d <- merge(d, alt,   by = "SEQN", all.x = TRUE)
  d <- merge(d, bpadj, by = "SEQN", all.x = TRUE)
  stopifnot(nrow(d) == n0)
  d$hPDI_sd     <- d$hPDI / SD_hPDI
  d$hPDI_alt_sd <- d$hPDI_alt / SD_hPDI_alt
  # Mifflin-St Jeor basal metabolic rate, for the Goldberg-type ratio
  d$bmr <- ifelse(d$sex == "Male",
                  10 * d$BMXWT + 6.25 * d$BMXHT - 5 * d$age_years + 5,
                  10 * d$BMXWT + 6.25 * d$BMXHT - 5 * d$age_years - 161)
  d$ei_bmr <- d$energy_kcal / d$bmr
  d$plausible <- !is.na(d$ei_bmr) & d$ei_bmr >= 0.87 & d$ei_bmr <= 2.75
  d
})

# --- generic pooled runner -------------------------------------------------
run <- function(label, exposure = "hPDI_sd", outcome = "cmd_score",
                weight = "WTSAFPRP", keep = NULL, extra = NULL,
                exposure_label = "hPDI per SD (non-consumer rule)",
                interpretation = "") {
  fits <- lapply(sets, function(d) {
    d$.w <- d[[weight]]
    d$.keep <- if (is.null(keep)) TRUE else eval(keep, d)
    d$.keep <- d$.keep & !is.na(d$.w) & d$.w > 0 & !is.na(d[[outcome]])
    des <- svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~.w,
                     nest = TRUE, data = d)
    svyglm(as.formula(paste(outcome, "~", paste(c(exposure, RHS, extra),
                                                collapse = " + "))),
           design = subset(des, .keep))
  })
  n_used <- sum({ d <- sets[[1]]
                  k <- if (is.null(keep)) TRUE else eval(keep, d)
                  k & !is.na(d[[weight]]) & d[[weight]] > 0 & !is.na(d[[outcome]]) })
  s <- NULL; invisible(capture.output(s <- summary(MIcombine(fits))))
  data.frame(analysis = label, n = n_used, exposure = exposure_label,
             weight = weight,
             beta = round(s[exposure, 1], 4), se = round(s[exposure, 2], 4),
             ci_low = round(s[exposure, 3], 4), ci_high = round(s[exposure, 4], 4),
             interpretation = interpretation, row.names = NULL)
}

A <- list()

# --- 0. reference ----------------------------------------------------------
A$primary <- run("PRIMARY (reference)", interpretation = "pre-specified primary specification")

# --- 1. weight sensitivity -------------------------------------------------
A$w_diet <- run("1. Weight: day-1 dietary weight", weight = "WTDRD1PP",
                interpretation = "WTDRD1PP does not adjust for fasting-subsample selection")
log_msg("weight sensitivity done", logfile = logfile)

# --- 2. reverse causation --------------------------------------------------
A$no_cvd <- run("2a. Exclude prevalent CVD", keep = quote(cvd_dx == "No"),
                interpretation = "attenuation would suggest reverse causation")
A$no_dm  <- run("2b. Exclude prevalent diabetes", keep = quote(diabetes_dx == "No"),
                interpretation = "attenuation would suggest reverse causation")
A$no_both<- run("2c. Exclude CVD and diabetes",
                keep = quote(cvd_dx == "No" & diabetes_dx == "No"),
                interpretation = "attenuation would suggest reverse causation")
log_msg("reverse-causation exclusions done", logfile = logfile)

# --- 3. medication handling ------------------------------------------------
A$med_adj <- run("3a. Medication as covariates", extra = c("bp_med", "lipid_med"),
                 interpretation = "conditions on a descendant of the outcome")
A$med_con <- run("3b. Additive BP constants (+15/+10)", outcome = "cmd_score_bpadj",
                 interpretation = "corrects the measured biomarker instead of adjusting")
A$med_exc <- run("3c. Exclude treated participants",
                 keep = quote(bp_med == "No" & lipid_med == "No"),
                 interpretation = "removes treatment effects on biomarkers, at a cost in n")
log_msg("medication variants done", logfile = logfile)

# --- 4. dietary scoring rule -----------------------------------------------
A$score_q <- run("4. Plain weighted-quintile scoring", exposure = "hPDI_alt_sd",
                 exposure_label = "hPDI per SD (plain quintile rule)",
                 interpretation = "pre-specified alternative scoring rule")
log_msg("scoring sensitivity done", logfile = logfile)

# --- 5. implausible energy reporters ---------------------------------------
# Goldberg-type criterion applied at the individual level: reported energy
# intake divided by Mifflin-St Jeor BMR outside [0.87, 2.75]. Participants
# excluded here are NOT "bad data" -- misreporting is a property of the
# instrument, and it is patterned by adiposity (see 00_dag.R, the Misreport
# node), which is exactly why this is a sensitivity analysis and not a
# data-cleaning step.
A$plaus <- run("5. Exclude implausible energy reporters", keep = quote(plausible),
               interpretation = "EI:BMR outside [0.87, 2.75] excluded")

d0 <- sets[[1]]
excl_cmp <- data.frame(
  characteristic = c("n", "age (mean)", "female (%)", "BMI (mean)",
                     "energy kcal (mean)", "EI:BMR (mean)", "hPDI (mean)"),
  included = c(sum(d0$plausible), round(mean(d0$age_years[d0$plausible]), 1),
               round(100 * mean(d0$sex[d0$plausible] == "Female"), 1),
               round(mean(d0$BMXBMI[d0$plausible], na.rm = TRUE), 1),
               round(mean(d0$energy_kcal[d0$plausible]), 0),
               round(mean(d0$ei_bmr[d0$plausible]), 2),
               round(mean(d0$hPDI[d0$plausible]), 1)),
  excluded = c(sum(!d0$plausible), round(mean(d0$age_years[!d0$plausible]), 1),
               round(100 * mean(d0$sex[!d0$plausible] == "Female"), 1),
               round(mean(d0$BMXBMI[!d0$plausible], na.rm = TRUE), 1),
               round(mean(d0$energy_kcal[!d0$plausible]), 0),
               round(mean(d0$ei_bmr[!d0$plausible], na.rm = TRUE), 2),
               round(mean(d0$hPDI[!d0$plausible]), 1)))
write.csv(excl_cmp, file.path(tab_dir, "15_implausible_reporter_comparison.csv"),
          row.names = FALSE)
log_msg("energy-plausibility sensitivity done; ", sum(!d0$plausible), " excluded",
        logfile = logfile)

# --- 6. non-linearity ------------------------------------------------------
# ONE pre-specified knot structure: natural cubic spline, 3 knots at the 10th,
# 50th and 90th percentiles of hPDI. No search over alternatives.
kn <- quantile(sets[[1]]$hPDI_sd, c(.10, .50, .90))
spl_fits <- lapply(sets, function(d) {
  des <- svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WTSAFPRP,
                   nest = TRUE, data = d)
  list(lin = svyglm(as.formula(paste("cmd_score ~ hPDI_sd +", RHS)), design = des),
       spl = svyglm(as.formula(paste(
         "cmd_score ~ ns(hPDI_sd, knots = c(", paste(kn[2], collapse = ","),
         "), Boundary.knots = c(", kn[1], ",", kn[3], ")) +", RHS)), design = des))
})
lin_p <- sapply(spl_fits, function(f) {
  a <- anova(f$spl, f$lin, method = "Wald")
  as.numeric(a$p)
})
nonlin <- data.frame(test = "Wald test of non-linearity (spline vs linear)",
                     knots = paste(round(kn, 3), collapse = ", "),
                     median_p_across_imputations = signif(median(lin_p, na.rm = TRUE), 3))
write.csv(nonlin, file.path(tab_dir, "15_nonlinearity.csv"), row.names = FALSE)
log_msg("non-linearity: median p = ", signif(median(lin_p, na.rm = TRUE), 3),
        logfile = logfile)

# --- 7. E-value ------------------------------------------------------------
# VanderWeele & Ding, for a standardised mean difference: approximate the
# effect on the risk-ratio scale as RR = exp(0.91 * d), then
# E = RR + sqrt(RR * (RR - 1)).
#
# The E-value is the MINIMUM strength of association, on the risk-ratio scale,
# that an unmeasured confounder would need to have with BOTH the exposure and
# the outcome, conditional on the measured covariates, to explain away the
# observed association. It does NOT demonstrate robustness to confounding, and
# it says nothing about whether such a confounder exists.
evalue <- function(d) { rr <- exp(0.91 * abs(d)); rr + sqrt(rr * (rr - 1)) }
pr <- A$primary
ev_tab <- data.frame(
  quantity = c("point estimate", "CI limit closest to the null"),
  beta = c(pr$beta, pr$ci_high),
  e_value = round(c(evalue(pr$beta), evalue(pr$ci_high)), 3))
write.csv(ev_tab, file.path(tab_dir, "15_evalue.csv"), row.names = FALSE)

# --- audit table -----------------------------------------------------------
audit <- do.call(rbind, A)
audit$ci <- sprintf("%.4f to %.4f", audit$ci_low, audit$ci_high)
audit$pct_change_vs_primary <- round(100 * (audit$beta - pr$beta) / abs(pr$beta), 1)
audit$ci_overlaps_primary <- !(audit$ci_low > pr$ci_high | audit$ci_high < pr$ci_low)
audit$inference_unchanged <- (audit$ci_high < 0) == (pr$ci_high < 0)
AUDIT <- audit[, c("analysis", "n", "exposure", "weight", "beta", "ci",
                   "pct_change_vs_primary", "ci_overlaps_primary",
                   "inference_unchanged", "interpretation")]
write.csv(AUDIT, file.path(tab_dir, "15_audit_table.csv"), row.names = FALSE)
saveRDS(list(audit = AUDIT, evalue = ev_tab, nonlin = nonlin,
             excl = excl_cmp), file.path(int_dir, "sensitivity.rds"))

log_msg("=== 15_sensitivity.R complete ===", logfile = logfile)

cat("\n================ SENSITIVITY AUDIT TABLE ================\n")
print(AUDIT[, c("analysis", "n", "beta", "ci", "pct_change_vs_primary",
                "ci_overlaps_primary", "inference_unchanged")], row.names = FALSE)
cat("\n--- implausible energy reporters: included vs excluded ---\n")
print(excl_cmp, row.names = FALSE)
cat("\n--- non-linearity ---\n"); print(nonlin, row.names = FALSE)
cat("\n--- E-value ---\n"); print(ev_tab, row.names = FALSE)
