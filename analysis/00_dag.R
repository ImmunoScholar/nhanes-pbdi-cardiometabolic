# ---------------------------------------------------------------------------
# 00_dag.R
# Encode the frozen causal structure and DERIVE the adjustment set, rather
# than asserting it. The protocol's covariate list is treated as a hypothesis
# about the DAG and is machine-checked against it.
#
# Two DAGs are specified deliberately:
#
#   dag_structural  -- the honest causal structure, including latent
#                      constructs (SES, health-behaviour orientation, past
#                      cardiometabolic status) and the measurement model.
#                      This is what we BELIEVE. It is used to enumerate what
#                      the primary analysis cannot identify.
#
#   dag_operational -- the working DAG the primary model actually assumes:
#                      measured proxies stand in for their latent parents and
#                      reverse causation is assumed absent. This is what the
#                      primary model ESTIMATES UNDER. Its minimal sufficient
#                      adjustment set must equal the frozen covariate list.
#
# The gap between the two is not a defect to be hidden; it is the study's
# confounding structure, and it is written out for the Limitations section.
#
# This script derives and validates. It fits nothing and changes no data.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(here); library(dagitty)
})
source(here::here("R", "utils.R"))

log_dir <- here::here("outputs", "logs")
tab_dir <- here::here("outputs", "tables")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
logfile <- file.path(log_dir, "00_dag.log")

log_msg("=== 00_dag.R start ===", logfile = logfile)

# --- the frozen covariate list (Phase 2 protocol) --------------------------
PROTOCOL_ADJUSTMENT_SET <- sort(c(
  "Age", "Sex", "RaceEth", "Education", "Income",
  "Smoking", "Alcohol", "PhysAct", "Supplements", "Energy"
))

# --- structural DAG --------------------------------------------------------
dag_structural <- dagitty('dag {
  SES               [latent]
  HealthOrientation [latent]
  CMD_past          [latent]
  Misreport         [latent]
  hPDI              [exposure]
  CMD               [outcome]

  Age -> hPDI          Age -> CMD          Age -> Adiposity
  Sex -> hPDI          Sex -> CMD
  RaceEth -> hPDI      RaceEth -> CMD      RaceEth -> SES

  SES -> Education     SES -> Income       SES -> hPDI     SES -> CMD

  HealthOrientation -> hPDI
  HealthOrientation -> Smoking
  HealthOrientation -> Alcohol
  HealthOrientation -> PhysAct
  HealthOrientation -> Supplements

  Smoking -> CMD       Alcohol -> CMD
  PhysAct -> CMD       PhysAct -> Adiposity
  Supplements -> CMD

  Energy -> hPDI       Energy -> Adiposity Energy -> CMD

  hPDI -> Adiposity    Adiposity -> CMD    hPDI -> CMD

  CMD_past -> PrevDisease
  CMD_past -> CMD
  PrevDisease -> hPDI
  PrevDisease -> Meds
  Meds -> CMD_measured
  CMD -> CMD_measured

  Adiposity -> Misreport
  Misreport -> hPDI_measured
  hPDI -> hPDI_measured
  RecallDay  -> hPDI_measured
  RecallMode -> hPDI_measured
}')

stopifnot(isAcyclic(dag_structural))

sets_structural <- adjustmentSets(dag_structural, exposure = "hPDI",
                                  outcome = "CMD", type = "minimal")

log_msg("structural DAG: ", length(sets_structural),
        " adjustment set(s) from OBSERVED variables", logfile = logfile)

# --- operational DAG -------------------------------------------------------
# Differences from the structural DAG, each a stated assumption:
#   A1  Education and Income are treated as the confounders themselves rather
#       than as proxies for latent SES.
#   A2  Smoking, Alcohol, PhysAct and Supplements likewise stand in for latent
#       health-behaviour orientation.
#   A3  No reverse causation: the PrevDisease -> hPDI arrow is absent. The
#       protocol addresses this by EXCLUSION sensitivity, not by adjustment.
dag_operational <- dagitty('dag {
  hPDI [exposure]
  CMD  [outcome]

  Age -> hPDI          Age -> CMD          Age -> Adiposity
  Sex -> hPDI          Sex -> CMD
  RaceEth -> hPDI      RaceEth -> CMD
  Education -> hPDI    Education -> CMD
  Income -> hPDI       Income -> CMD

  Smoking -> hPDI      Smoking -> CMD
  Alcohol -> hPDI      Alcohol -> CMD
  PhysAct -> hPDI      PhysAct -> CMD      PhysAct -> Adiposity
  Supplements -> hPDI  Supplements -> CMD

  Energy -> hPDI       Energy -> Adiposity Energy -> CMD

  hPDI -> Adiposity    Adiposity -> CMD    hPDI -> CMD
}')

stopifnot(isAcyclic(dag_operational))

sets_operational <- adjustmentSets(dag_operational, exposure = "hPDI",
                                   outcome = "CMD", type = "minimal")
derived <- lapply(sets_operational, function(s) sort(as.character(s)))

log_msg("operational DAG: ", length(derived), " minimal adjustment set(s)",
        logfile = logfile)
for (i in seq_along(derived))
  log_msg("  set ", i, ": ", paste(derived[[i]], collapse = ", "), logfile = logfile)

# --- VALIDATION: does the protocol match the machine-derived set? ----------
match_idx <- which(vapply(derived, identical, logical(1), PROTOCOL_ADJUSTMENT_SET))

if (!length(match_idx)) {
  log_msg("ADJUSTMENT SET MISMATCH", level = "ERROR", logfile = logfile)
  cat("\nProtocol set:\n  ", paste(PROTOCOL_ADJUSTMENT_SET, collapse = ", "), "\n")
  cat("Machine-derived minimal set(s):\n")
  for (s in derived) cat("  ", paste(s, collapse = ", "), "\n")
  stop("The frozen covariate list is not a minimal sufficient adjustment set ",
       "of the operational DAG. Either the DAG or the protocol is wrong. ",
       "Resolve explicitly -- do not adjust the covariate list silently.")
}
log_msg("VALIDATED: frozen covariate list == minimal sufficient adjustment set ",
        "(set ", match_idx, ")", logfile = logfile)

# --- Adiposity is a mediator, not a confounder: prove it -------------------
# If Adiposity were a confounder it would appear in some minimal set.
adiposity_in_any <- any(vapply(derived, function(s) "Adiposity" %in% s, logical(1)))
stopifnot(!adiposity_in_any)
log_msg("VALIDATED: Adiposity absent from every minimal set (mediator, not confounder)",
        logfile = logfile)

# --- testable implications -------------------------------------------------
# Conditional independencies implied by the operational DAG. Those involving
# only measured variables are testable against the data in Phase 5 and are
# the DAG's falsifiable content.
ici <- impliedConditionalIndependencies(dag_operational)
ici_txt <- vapply(ici, function(x) paste(format(x), collapse = " "), character(1))
writeLines(ici_txt, file.path(tab_dir, "00_dag_implied_independencies.txt"))
log_msg(length(ici), " implied conditional independencies written",
        logfile = logfile)

# --- what the primary analysis cannot identify -----------------------------
unidentified <- c(
  "Latent SES: Education and Income are proxies. Conditioning on children of a latent common cause does not close the backdoor hPDI <- SES -> CMD. Residual socioeconomic confounding cannot be fully eliminated using the observed variables available in NHANES, because important determinants are represented only imperfectly by measured proxies.",
  "Latent health-behaviour orientation: the same argument applies to Smoking, Alcohol, PhysAct and Supplements, which are imperfect proxies for an unmeasured behavioural disposition.",
  "Reverse causation: the structural DAG contains hPDI <- PrevDisease <- CMD_past -> CMD. The operational DAG assumes this arrow away. The pre-specified exclusion of prevalent CVD/diabetes is the analysis that actually closes this path, which is why it is a sensitivity analysis and not an optional extra.",
  "Differential exposure error: Adiposity -> Misreport -> hPDI_measured means recall error depends on a cause of the outcome. Classical regression calibration assumes non-differential error, so the Phase 4 correction is partial and its corrected estimate remains conservative."
)
writeLines(unidentified, file.path(tab_dir, "00_dag_unidentified_paths.txt"))

saveRDS(list(structural = dag_structural, operational = dag_operational,
             derived_sets = derived, protocol_set = PROTOCOL_ADJUSTMENT_SET),
        here::here("data", "interim", "dag.rds"))

writeLines(capture.output(sessionInfo()), file.path(log_dir, "00_sessionInfo.txt"))
log_msg("=== 00_dag.R complete ===", logfile = logfile)

cat("\n--- structural DAG: adjustment sets from observed variables ---\n")
print(sets_structural)
cat("\n--- operational DAG: minimal sufficient adjustment set ---\n")
print(sets_operational)
