# ---------------------------------------------------------------------------
# 10_calibration.R
# Regression calibration for within-person 24-hour recall error (H2).
#
# A single 24-hour recall measures one day, not usual intake. Under a classical
# error model X_ij = T_i + e_ij, the naive regression coefficient is attenuated
# toward the null by the reliability ratio
#
#     lambda = sigma2_between / (sigma2_between + sigma2_within)
#
# and the corrected coefficient is beta_naive / lambda.
#
# TWO REFINEMENTS, both necessary here:
#
# 1. MULTIVARIABLE attenuation. When the error-prone exposure sits in a model
#    with other covariates measured without error, the relevant attenuation
#    factor is the reliability of the exposure RESIDUALISED ON THOSE COVARIATES
#    (Rosner/Spiegelman), not its marginal reliability. Using the marginal
#    lambda would over-correct.
#
# 2. DAY EFFECTS. In this sample 41.2% of day-1 recalls fall on a weekend
#    versus 22.2% of day-2 recalls, and the two days differ in mode (day 1
#    in person, day 2 by telephone). Left unadjusted, that systematic
#    difference is absorbed into the within-person variance and biases lambda
#    downward, which would inflate the correction.
#
# WHAT THIS CORRECTION CANNOT DO, stated up front: classical regression
# calibration assumes error that is additive, non-differential, and
# uncorrelated with true intake. 00_dag.R encodes the opposite
# (Adiposity -> Misreport -> hPDI_measured), so recall error here is
# differential with respect to a cause of the outcome. The corrected estimate
# is therefore a partial correction and remains conservative. It is not an
# unbiased estimate of the usual-intake association.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(here); library(survey)
})
source(here::here("R", "utils.R"))

int_dir <- here::here("data", "interim")
log_dir <- here::here("outputs", "logs")
tab_dir <- here::here("outputs", "tables")
logfile <- file.path(log_dir, "10_calibration.log")
set.seed(20260724)
N_BOOT <- 500

log_msg("=== 10_calibration.R start ===", logfile = logfile)

raw <- readRDS(file.path(int_dir, "nhanes_raw_list.rds"))
exp <- readRDS(file.path(int_dir, "exposure_pdi.rds"))
imp <- readRDS(file.path(int_dir, "imputed_data.rds"))
COV <- imp$primary_covariates

# --- replicate-subsample long format --------------------------------------
wknd <- function(x) as.integer(x %in% c(1, 7))
d1 <- raw$P_DR1TOT[, c("SEQN", "DR1DRSTZ", "DR1DAY")]
d2 <- raw$P_DR2TOT[, c("SEQN", "DR2DRSTZ", "DR2DAY")]

h1 <- merge(exp$pdi_day1[, c("SEQN", "hPDI")], d1, by = "SEQN")
h2 <- merge(exp$pdi_day2[, c("SEQN", "hPDI")], d2, by = "SEQN")
h1 <- h1[h1$DR1DRSTZ == 1, ]; h2 <- h2[h2$DR2DRSTZ == 1, ]

rep_wide <- merge(
  data.frame(SEQN = h1$SEQN, x1 = h1$hPDI, wknd1 = wknd(h1$DR1DAY)),
  data.frame(SEQN = h2$SEQN, x2 = h2$hPDI, wknd2 = wknd(h2$DR2DAY)),
  by = "SEQN")

# --- reliability ratio -----------------------------------------------------
# Method-of-moments with two replicates, on residuals from the day-effect and
# covariate adjustment. sigma2_w from the paired differences; sigma2_b from
# the variance of the person means, corrected for the within-person component.
lambda_of <- function(dd, w) {
  # dd: SEQN, r1, r2 (adjusted residuals); w: person-level weights
  dif <- dd$r1 - dd$r2
  s2w <- sum(w * dif^2 / 2) / sum(w)
  mn  <- (dd$r1 + dd$r2) / 2
  mbar <- sum(w * mn) / sum(w)
  s2m  <- sum(w * (mn - mbar)^2) / sum(w)
  s2b  <- max(s2m - s2w / 2, 1e-8)
  list(lambda = s2b / (s2b + s2w), s2b = s2b, s2w = s2w)
}

# Residualise each day's hPDI on the weekend indicator and, for the
# multivariable factor, on the covariate set as well. The day/mode contrast is
# absorbed by fitting the two days jointly with a day indicator.
build_residuals <- function(dat_person, w, adjust_covariates) {
  m <- merge(rep_wide, dat_person, by = "SEQN")
  long <- rbind(
    data.frame(SEQN = m$SEQN, x = m$x1, weekend = m$wknd1, day2 = 0, m[, COV, drop = FALSE]),
    data.frame(SEQN = m$SEQN, x = m$x2, weekend = m$wknd2, day2 = 1, m[, COV, drop = FALSE]))
  ww <- rep(w[match(m$SEQN, dat_person$SEQN)], 2)
  rhs <- if (adjust_covariates) paste(c("weekend", "day2", COV), collapse = " + ")
         else paste(c("weekend", "day2"), collapse = " + ")
  fit <- lm(as.formula(paste("x ~", rhs)), data = long, weights = ww)
  long$r <- residuals(fit)
  w1 <- long[long$day2 == 0, c("SEQN", "r")]; names(w1)[2] <- "r1"
  w2 <- long[long$day2 == 1, c("SEQN", "r")]; names(w2)[2] <- "r2"
  list(dd = merge(w1, w2, by = "SEQN"),
       w  = w[match(merge(w1, w2, by = "SEQN")$SEQN, dat_person$SEQN)])
}

# --- point estimates across all imputations --------------------------------
SD_hPDI <- sd(imp$completed[[1]]$hPDI)
per_imp <- do.call(rbind, lapply(seq_along(imp$completed), function(i) {
  d <- imp$completed[[i]]
  d$hPDI_sd <- d$hPDI / SD_hPDI
  des <- svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WTSAFPRP,
                   nest = TRUE, data = d)
  b <- coef(svyglm(as.formula(paste("cmd_score ~ hPDI_sd +",
                                    paste(COV, collapse = " + "))), design = des))["hPDI_sd"]
  rc <- build_residuals(d, d$WTSAFPRP, adjust_covariates = TRUE)
  rm_ <- build_residuals(d, d$WTSAFPRP, adjust_covariates = FALSE)
  L  <- lambda_of(rc$dd, rc$w); Lm <- lambda_of(rm_$dd, rm_$w)
  data.frame(imputation = i, beta_naive = b,
             lambda_adj = L$lambda, lambda_marginal = Lm$lambda,
             s2b = L$s2b, s2w = L$s2w,
             beta_corrected = b / L$lambda, row.names = NULL)
}))

pt <- colMeans(per_imp[, -1])
log_msg(sprintf("lambda (covariate-adjusted) = %.4f | marginal = %.4f",
                pt["lambda_adj"], pt["lambda_marginal"]), logfile = logfile)
log_msg(sprintf("beta naive = %.4f -> corrected = %.4f (factor %.2fx)",
                pt["beta_naive"], pt["beta_corrected"], 1 / pt["lambda_adj"]),
        logfile = logfile)
log_msg(sprintf("across-imputation SD of corrected beta = %.5f",
                sd(per_imp$beta_corrected)), logfile = logfile)

# --- bootstrap CI ----------------------------------------------------------
# Replicate weights respect the stratified two-stage design. Rao-Wu-Yue-Beaumont
# ("subbootstrap") is used rather than BRR because one stratum contains three
# PSUs, which BRR cannot accommodate.
#
# Both beta_naive AND lambda are recomputed within every replicate, so the
# uncertainty in the correction factor propagates into the interval rather
# than being treated as known.
d1c <- imp$completed[[1]]; d1c$hPDI_sd <- d1c$hPDI / SD_hPDI
des  <- svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WTSAFPRP,
                  nest = TRUE, data = d1c)
rep_des <- as.svrepdesign(des, type = "subbootstrap", replicates = N_BOOT)
RW <- weights(rep_des, "analysis")
f_naive <- as.formula(paste("cmd_score ~ hPDI_sd +", paste(COV, collapse = " + ")))

boot_err <- character(0)
boot <- t(vapply(seq_len(ncol(RW)), function(k) {
  w <- as.numeric(RW[, k])
  out <- tryCatch({
    # The replicate weight is attached to the data frame rather than passed as
    # a local variable. lm() resolves `weights` in `data` and then in
    # environment(formula) -- which for a top-level as.formula() is the global
    # environment, not this function -- so a local `w` is invisible to it.
    dk <- d1c; dk$.repw <- w
    b <- unname(coef(lm(f_naive, data = dk, weights = .repw))["hPDI_sd"])
    rc <- build_residuals(d1c, w, TRUE)
    L <- lambda_of(rc$dd, rc$w)
    c(b, L$lambda, b / L$lambda)
  }, error = function(e) {
    boot_err <<- c(boot_err, conditionMessage(e))
    c(NA_real_, NA_real_, NA_real_)
  })
  as.numeric(out)
}, numeric(3)))
colnames(boot) <- c("beta_naive", "lambda", "beta_corrected")
if (length(boot_err))
  log_msg("bootstrap errors (first): ", boot_err[1], level = "WARN", logfile = logfile)
boot <- boot[complete.cases(boot), , drop = FALSE]
log_msg(nrow(boot), " of ", N_BOOT, " bootstrap replicates usable", logfile = logfile)

qs <- function(v) quantile(v, c(.025, .975), na.rm = TRUE)
res <- data.frame(
  quantity = c("beta_naive (day-1 only)", "lambda (reliability ratio)",
               "beta_corrected (regression calibration)"),
  estimate = c(pt["beta_naive"], pt["lambda_adj"], pt["beta_corrected"]),
  ci_low   = c(qs(boot[, 1])[1], qs(boot[, 2])[1], qs(boot[, 3])[1]),
  ci_high  = c(qs(boot[, 1])[2], qs(boot[, 2])[2], qs(boot[, 3])[2]),
  row.names = NULL)
res[, 2:4] <- round(res[, 2:4], 4)

# --- comparison: 2-day mean exposure --------------------------------------
# The mean of two days has reliability 2*lambda/(1+lambda); reported as an
# intermediate between the naive and fully corrected estimates.
two_day_lambda <- 2 * pt["lambda_adj"] / (1 + pt["lambda_adj"])

extra <- data.frame(
  quantity = c("implied reliability of a 2-day mean",
               "deattenuation factor (1/lambda)",
               "across-imputation SD of corrected beta",
               "replicate subsample n"),
  value = round(c(two_day_lambda, 1 / pt["lambda_adj"],
                  sd(per_imp$beta_corrected),
                  length(intersect(rep_wide$SEQN, imp$completed[[1]]$SEQN))), 4),
  row.names = NULL)

write.csv(res,     file.path(tab_dir, "10_calibration_results.csv"), row.names = FALSE)
write.csv(extra,   file.path(tab_dir, "10_calibration_extra.csv"), row.names = FALSE)
write.csv(per_imp, file.path(tab_dir, "10_calibration_per_imputation.csv"), row.names = FALSE)
saveRDS(list(point = pt, boot = boot, per_imp = per_imp),
        file.path(int_dir, "calibration.rds"))

log_msg("=== 10_calibration.R complete ===", logfile = logfile)
cat("\n=== REGRESSION CALIBRATION (H2) ===\n"); print(res, row.names = FALSE)
cat("\n--- supporting quantities ---\n");        print(extra, row.names = FALSE)
cat(sprintf("\nvariance components: between = %.4f, within = %.4f\n",
            pt["s2b"], pt["s2w"]))
