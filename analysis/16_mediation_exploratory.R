# ---------------------------------------------------------------------------
# 16_mediation_exploratory.R
# EXPLORATORY analysis of adiposity-related pathways.
#
# This is NOT a causal mediation analysis and does not estimate a natural
# indirect effect. Exposure, adiposity and outcome are all measured at the same
# examination, so the temporal ordering that mediation requires is ASSUMED, not
# observed, and the reverse pathway (adiposity influencing diet) is entirely
# plausible. Under those conditions a "proportion mediated" would be a number
# without an interpretation, so none is computed.
#
# What IS reported:
#   - the hPDI coefficient with and without adjustment for adiposity
#   - the difference between them, with a design-based bootstrap interval
#   - the two component associations, descriptively
#
# Permitted conclusion, and the strongest one these data support:
#   "The cross-sectional data were compatible with adiposity-related pathways
#    contributing to the observed association."
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(here); library(survey); library(mitools)
})
source(here::here("R", "utils.R"))

int_dir <- here::here("data", "interim")
log_dir <- here::here("outputs", "logs")
tab_dir <- here::here("outputs", "tables")
logfile <- file.path(log_dir, "16_mediation.log")
set.seed(20260724)
N_BOOT <- 500

log_msg("=== 16_mediation_exploratory.R start ===", logfile = logfile)

imp <- readRDS(file.path(int_dir, "imputed_data.rds"))
out <- readRDS(file.path(int_dir, "outcome_composite.rds"))
COV <- imp$primary_covariates
RHS <- paste(COV, collapse = " + ")
SD_hPDI <- sd(imp$completed[[1]]$hPDI)

sets <- lapply(imp$completed, function(d) {
  n0 <- nrow(d)
  d <- merge(d, out[, c("SEQN", "BMXBMI", "waist_cm")], by = "SEQN", all.x = TRUE)
  stopifnot(nrow(d) == n0)
  d$hPDI_sd <- d$hPDI / SD_hPDI
  d
})

pooled_coef <- function(formula, term) {
  fits <- lapply(sets, function(d)
    svyglm(formula, design = svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA,
                                       weights = ~WTSAFPRP, nest = TRUE, data = d)))
  s <- NULL; invisible(capture.output(s <- summary(MIcombine(fits))))
  c(est = s[term, 1], se = s[term, 2], lo = s[term, 3], hi = s[term, 4])
}

f_no  <- as.formula(paste("cmd_score ~ hPDI_sd +", RHS))
f_adj <- as.formula(paste("cmd_score ~ hPDI_sd + BMXBMI +", RHS))
f_a   <- as.formula(paste("BMXBMI ~ hPDI_sd +", RHS))
f_b   <- as.formula(paste("cmd_score ~ BMXBMI + hPDI_sd +", RHS))

r_no  <- pooled_coef(f_no,  "hPDI_sd")
r_adj <- pooled_coef(f_adj, "hPDI_sd")
r_a   <- pooled_coef(f_a,   "hPDI_sd")
r_b   <- pooled_coef(f_b,   "BMXBMI")

# --- bootstrap interval for the DIFFERENCE ---------------------------------
# The two coefficients come from nested models on the same participants, so the
# difference has a variance that depends on their covariance. A design-based
# replicate bootstrap is used rather than treating them as independent.
d1 <- sets[[1]]
des <- svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WTSAFPRP,
                 nest = TRUE, data = d1)
RW <- weights(as.svrepdesign(des, type = "subbootstrap", replicates = N_BOOT),
              "analysis")
boot_diff <- vapply(seq_len(ncol(RW)), function(k) {
  dk <- d1; dk$.repw <- as.numeric(RW[, k])
  tryCatch({
    b1 <- coef(lm(f_no,  data = dk, weights = .repw))["hPDI_sd"]
    b2 <- coef(lm(f_adj, data = dk, weights = .repw))["hPDI_sd"]
    unname(b1 - b2)
  }, error = function(e) NA_real_)
}, numeric(1))
boot_diff <- boot_diff[is.finite(boot_diff)]
log_msg(length(boot_diff), " of ", N_BOOT, " bootstrap replicates usable",
        logfile = logfile)

diff_est <- unname(r_no["est"] - r_adj["est"])
diff_ci  <- quantile(boot_diff, c(.025, .975))

res <- data.frame(
  quantity = c("hPDI -> dysfunction, NOT adjusted for adiposity",
               "hPDI -> dysfunction, adjusted for BMI",
               "Difference on adjustment (attenuation)",
               "hPDI -> BMI (kg/m2 per SD hPDI)",
               "BMI -> dysfunction (per kg/m2, adjusted for hPDI)"),
  estimate = round(c(r_no["est"], r_adj["est"], diff_est, r_a["est"], r_b["est"]), 4),
  ci_low   = round(c(r_no["lo"], r_adj["lo"], diff_ci[1], r_a["lo"], r_b["lo"]), 4),
  ci_high  = round(c(r_no["hi"], r_adj["hi"], diff_ci[2], r_a["hi"], r_b["hi"]), 4),
  row.names = NULL)

write.csv(res, file.path(tab_dir, "16_mediation_exploratory.csv"), row.names = FALSE)

interpretation <- c(
  "EXPLORATORY ANALYSIS -- NOT CAUSAL MEDIATION.",
  "",
  "Adjusting for adiposity attenuates the hPDI coefficient. Under a causal DAG",
  "in which diet influences adiposity which influences cardiometabolic status,",
  "that is the pattern adjustment for a mediator produces. But the same pattern",
  "arises if adiposity influences diet, or if an unmeasured common cause affects",
  "both -- and this study cannot distinguish those, because exposure, adiposity",
  "and outcome are measured at one examination.",
  "",
  "No proportion mediated is reported: with temporal ordering assumed rather",
  "than observed, and with residual confounding by latent socioeconomic position",
  "that the observed variables cannot fully remove (see 00_dag.R), such a figure",
  "would carry no interpretation.",
  "",
  "Supported statement:",
  "  The cross-sectional data were compatible with adiposity-related pathways",
  "  contributing to the observed association.")
writeLines(interpretation, file.path(tab_dir, "16_mediation_interpretation.txt"))

log_msg("=== 16_mediation_exploratory.R complete ===", logfile = logfile)
cat("\n=== EXPLORATORY: adiposity-related pathways ===\n")
print(res, row.names = FALSE)
cat("\n"); cat(interpretation, sep = "\n"); cat("\n")
