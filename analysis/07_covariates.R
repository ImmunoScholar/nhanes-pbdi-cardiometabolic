# ---------------------------------------------------------------------------
# 07_covariates.R
# Harmonise the ten DAG-derived covariates, derive exclusion-sensitivity flags,
# assemble the analytic dataset, and report the achievable sample size and
# minimum detectable effect BEFORE any model is fitted.
#
# Every NHANES special code (refused / don't know) is mapped to NA explicitly
# and per-variable. Codes verified against the CDC codebooks, not assumed.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({ library(here); library(survey) })
source(here::here("R", "utils.R"))

int_dir <- here::here("data", "interim")
log_dir <- here::here("outputs", "logs")
tab_dir <- here::here("outputs", "tables")
logfile <- file.path(log_dir, "07_covariates.log")

log_msg("=== 07_covariates.R start ===", logfile = logfile)
dat <- readRDS(file.path(int_dir, "nhanes_raw_list.rds"))

# Map NHANES refused/don't-know codes to NA. Applied explicitly per variable so
# that a wrong code list is visible in the diff rather than buried in a helper.
na_if <- function(x, codes) { x[x %in% codes] <- NA; x }

demo <- dat$P_DEMO; smq <- dat$P_SMQ; alq <- dat$P_ALQ
paq  <- dat$P_PAQ;  dsq <- dat$P_DSQTOT; d1 <- dat$P_DR1TOT
diq  <- dat$P_DIQ;  mcq <- dat$P_MCQ;  whq <- dat$P_WHQ; bpq <- dat$P_BPQ

cov <- data.frame(SEQN = demo$SEQN)

# --- 1-5 demographics and socioeconomic position --------------------------
cov$age_years <- demo$RIDAGEYR
cov$sex <- factor(demo$RIAGENDR, levels = c(1, 2), labels = c("Male", "Female"))
cov$race_eth <- factor(demo$RIDRETH3, levels = c(3, 1, 2, 4, 6, 7),
  labels = c("NH White", "Mexican American", "Other Hispanic",
             "NH Black", "NH Asian", "Other/Multiracial"))
edu <- na_if(demo$DMDEDUC2, c(7, 9))               # 7 Refused, 9 Don't know
cov$education3 <- factor(ifelse(edu %in% 1:2, "<HS",
                        ifelse(edu == 3, "HS/GED",
                        ifelse(edu %in% 4:5, ">HS", NA))),
                        levels = c("<HS", "HS/GED", ">HS"))
cov$pir <- demo$INDFMPIR                            # topcoded at 5 by NHANES

# --- 6 smoking -------------------------------------------------------------
# SMQ020 1 = smoked >=100 cigarettes; SMQ040 1/2 = now smokes, 3 = not at all.
s20 <- na_if(smq$SMQ020, c(7, 9))[match(cov$SEQN, smq$SEQN)]
s40 <- na_if(smq$SMQ040, c(7, 9))[match(cov$SEQN, smq$SEQN)]
cov$smoking3 <- factor(ifelse(!is.na(s20) & s20 == 2, "Never",
                       ifelse(!is.na(s20) & s20 == 1 & !is.na(s40) & s40 == 3, "Former",
                       ifelse(!is.na(s20) & s20 == 1 & !is.na(s40) & s40 %in% 1:2, "Current", NA))),
                       levels = c("Never", "Former", "Current"))

# --- 7 alcohol -------------------------------------------------------------
# ALQ121 frequency codes verified against the P_ALQ codebook; converted to
# drinking days per year, then combined with ALQ130 (drinks per drinking day).
FREQ_DAYS <- c("0" = 0, "1" = 365, "2" = 350, "3" = 182, "4" = 104, "5" = 52,
               "6" = 30, "7" = 12, "8" = 9, "9" = 4.5, "10" = 1.5)
a121 <- na_if(alq$ALQ121, c(77, 99))[match(cov$SEQN, alq$SEQN)]
a130 <- na_if(alq$ALQ130, c(777, 999))[match(cov$SEQN, alq$SEQN)]  # 15 = "15 or more"
days_yr <- FREQ_DAYS[as.character(a121)]
cov$alcohol_dpd <- ifelse(!is.na(a121) & a121 == 0, 0,
                          as.numeric(days_yr) * a130 / 365)

# --- 8 physical activity (GPAQ) -------------------------------------------
# MET-min/week = sum over five domains of MET x days/week x minutes/day.
# Vigorous domains 8 METs, moderate and active transport 4 METs.
pget <- function(v, codes) na_if(paq[[v]], codes)[match(cov$SEQN, paq$SEQN)]
domain <- function(gate, days, mins, met) {
  g <- pget(gate, c(7, 9)); d <- pget(days, c(77, 99)); m <- pget(mins, c(7777, 9999))
  out <- rep(NA_real_, length(g))
  out[!is.na(g) & g == 2] <- 0                              # domain not performed
  ok <- !is.na(g) & g == 1 & !is.na(d) & !is.na(m)
  out[ok] <- met * d[ok] * m[ok]
  out
}
mets <- cbind(
  domain("PAQ605", "PAQ610", "PAD615", 8),   # vigorous work
  domain("PAQ620", "PAQ625", "PAD630", 4),   # moderate work
  domain("PAQ635", "PAQ640", "PAD645", 4),   # active transport
  domain("PAQ650", "PAQ655", "PAD660", 8),   # vigorous recreation
  domain("PAQ665", "PAQ670", "PAD675", 4))   # moderate recreation
# A domain that cannot be evaluated makes the total unknown, not zero.
cov$met_min_wk <- ifelse(rowSums(is.na(mets)) == 0, rowSums(mets), NA)

# --- 9 supplements ---------------------------------------------------------
dsc <- na_if(dsq$DSDCOUNT, c(77, 99))[match(cov$SEQN, dsq$SEQN)]
cov$supplement_any <- factor(ifelse(is.na(dsc), NA, ifelse(dsc > 0, "Yes", "No")),
                             levels = c("No", "Yes"))

# --- 10 energy -------------------------------------------------------------
cov$energy_kcal <- d1$DR1TKCAL[match(cov$SEQN, d1$SEQN)]
cov$recall1_weekend <- factor(ifelse(d1$DR1DAY[match(cov$SEQN, d1$SEQN)] %in% c(1, 7),
                                     "Weekend", "Weekday"))

# --- exclusion-sensitivity flags (never primary covariates; see 00_dag.R) --
g <- function(df, v, codes = c(7, 9)) na_if(df[[v]], codes)[match(cov$SEQN, df$SEQN)]
cov$diabetes_dx <- g(diq, "DIQ010") == 1                     # 3 = borderline, not "yes"
cvd <- sapply(c("MCQ160B","MCQ160C","MCQ160D","MCQ160E","MCQ160F"),
              function(v) g(mcq, v) == 1)
cov$cvd_dx        <- ifelse(rowSums(cvd, na.rm = TRUE) > 0, TRUE,
                            ifelse(rowSums(is.na(cvd)) == ncol(cvd), NA, FALSE))
cov$tried_lose_wt <- g(whq, "WHQ070") == 1
cov$bp_med        <- g(bpq, "BPQ050A") == 1
cov$lipid_med     <- g(bpq, "BPQ100D") == 1

PRIMARY_COVARIATES <- c("age_years","sex","race_eth","education3","pir",
                        "smoking3","alcohol_dpd","met_min_wk","supplement_any",
                        "energy_kcal")

# --- assemble the analytic dataset ----------------------------------------
out <- readRDS(file.path(int_dir, "outcome_composite.rds"))
exp <- readRDS(file.path(int_dir, "exposure_pdi.rds"))

an <- merge(out, exp$pdi_day1, by = "SEQN")
an <- merge(an, cov, by = "SEQN")
log_msg("outcome x exposure x covariates: n = ", nrow(an), logfile = logfile)

# --- attrition and missingness --------------------------------------------
steps <- data.frame(
  step = c("Fasting subsample, adults 20+, non-pregnant, MEC-examined",
           "  + day-1 PDI available",
           "  + complete composite outcome",
           "  + complete primary covariates (complete-case)"),
  n = c(nrow(out), nrow(an), sum(!is.na(an$cmd_score)),
        sum(!is.na(an$cmd_score) & complete.cases(an[, PRIMARY_COVARIATES]))))
steps$lost <- c(NA, -diff(steps$n))

miss <- data.frame(
  variable = PRIMARY_COVARIATES,
  pct_missing = round(100 * sapply(PRIMARY_COVARIATES,
                                   function(v) mean(is.na(an[[v]]))), 1))
miss <- miss[order(-miss$pct_missing), ]

write.csv(steps, file.path(tab_dir, "07_attrition.csv"), row.names = FALSE)
write.csv(miss,  file.path(tab_dir, "07_covariate_missingness.csv"), row.names = FALSE)

# --- design effect and minimum detectable effect --------------------------
# The design object is built on the FULL analytic frame and then subset with
# subset(). Filtering rows before svydesign() removes whole PSUs from strata
# and distorts variance estimation -- it does not merely shrink the sample.
an$in_cc <- !is.na(an$cmd_score) & complete.cases(an[, PRIMARY_COVARIATES])
cc <- an[an$in_cc, ]
des_full <- svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WTSAFPRP,
                      nest = TRUE, data = an)
des <- subset(des_full, in_cc)
mn <- svymean(~cmd_score, des, deff = TRUE)
deff <- as.numeric(attr(mn, "deff"))
n_eff <- nrow(cc) / deff
# Two-sided alpha 0.05, 80% power, standardised exposure and outcome.
# Assumes the covariate set explains a share R2x of exposure variance, which
# inflates the SE of the exposure coefficient by 1/sqrt(1 - R2x).
mde <- function(ne, r2x) (qnorm(0.975) + qnorm(0.80)) / sqrt(ne * (1 - r2x))
mde_tab <- data.frame(r2_exposure_on_covariates = c(0, .1, .2, .3),
                      mde_sd_per_sd = round(sapply(c(0, .1, .2, .3),
                                                   function(r) mde(n_eff, r)), 4))
write.csv(mde_tab, file.path(tab_dir, "07_minimum_detectable_effect.csv"),
          row.names = FALSE)

saveRDS(list(analytic = an, complete_case = cc,
             primary_covariates = PRIMARY_COVARIATES),
        file.path(int_dir, "analytic_dataset.rds"))

log_msg("complete-case analytic n = ", nrow(cc), " | DEFF = ", round(deff, 2),
        " | effective n = ", round(n_eff), logfile = logfile)
log_msg("=== 07_covariates.R complete ===", logfile = logfile)

cat("\n--- attrition ---\n");            print(steps, row.names = FALSE)
cat("\n--- covariate missingness ---\n"); print(miss, row.names = FALSE)
cat("\n--- design ---\n")
cat(sprintf("  complete-case n = %d\n  design effect  = %.2f\n  effective n    = %.0f\n",
            nrow(cc), deff, n_eff))
cat("\n--- minimum detectable effect (SD outcome per SD exposure, 80%% power) ---\n")
print(mde_tab, row.names = FALSE)
