# ---------------------------------------------------------------------------
# 19_freeze_provenance.R
# Final preservation step. Freezes the analytic dataset, hashes every artefact,
# and records the exact conditions under which the results were produced.
#
# Run LAST. Everything it hashes must already exist.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({ library(here); library(digest) })
source(here::here("R", "utils.R"))

int_dir  <- here::here("data", "interim")
proc_dir <- here::here("data", "processed")
tab_dir  <- here::here("outputs", "tables")
fig_dir  <- here::here("outputs", "figures")
log_dir  <- here::here("outputs", "logs")
doc_dir  <- here::here("docs")
logfile  <- file.path(log_dir, "19_freeze.log")
dir.create(proc_dir, recursive = TRUE, showWarnings = FALSE)

log_msg("=== 19_freeze_provenance.R start ===", logfile = logfile)

# --- 1. freeze the analytic dataset ---------------------------------------
imp <- readRDS(file.path(int_dir, "imputed_data.rds"))
ad  <- readRDS(file.path(int_dir, "analytic_dataset.rds"))
exp <- readRDS(file.path(int_dir, "exposure_pdi.rds"))
out <- readRDS(file.path(int_dir, "outcome_composite.rds"))

frozen <- list(
  description = paste(
    "Frozen analytic dataset for: plant-based diet quality and cardiometabolic",
    "dysfunction, NHANES 2017-March 2020 pre-pandemic. Observational,",
    "cross-sectional. All estimates are associations."),
  # NOTE: no timestamp is stored in this object. A frozen dataset should be
  # CONTENT-ADDRESSED -- its hash must be a pure function of the data, so that
  # two runs producing the same data produce the same hash. Embedding
  # Sys.time() here made the hash change on every run and defeated the
  # verification. The freeze time is recorded in docs/PROVENANCE.md, which is
  # where a timestamp belongs.
  analytic_frame     = ad$analytic,
  completed_datasets = imp$completed,
  m_imputations      = imp$m,
  primary_covariates = imp$primary_covariates,
  exposure_day1      = exp$pdi_day1,
  exposure_day2      = exp$pdi_day2,
  food_group_intakes = exp$intake_day1,
  outcome            = out,
  scoring_rule       = exp$scoring_rule,
  n_analytic         = nrow(imp$completed[[1]]))
saveRDS(frozen, file.path(proc_dir, "analytic_frozen.rds"))
frozen_hash <- file_sha256(file.path(proc_dir, "analytic_frozen.rds"))
log_msg("frozen dataset written; n = ", frozen$n_analytic,
        "; SHA-256 ", substr(frozen_hash, 1, 16), "...", logfile = logfile)

# --- 2. hash every artefact ------------------------------------------------
hash_dir <- function(dir, pattern) {
  f <- list.files(dir, pattern = pattern, full.names = TRUE)
  if (!length(f)) return(NULL)
  data.frame(file = file.path(basename(dir), basename(f)),
             bytes = file.size(f),
             sha256 = vapply(f, file_sha256, character(1)),
             row.names = NULL)
}
artefacts <- rbind(
  data.frame(file = "data/processed/analytic_frozen.rds",
             bytes = file.size(file.path(proc_dir, "analytic_frozen.rds")),
             sha256 = frozen_hash),
  hash_dir(tab_dir, "\\.(csv|md|txt)$"),
  hash_dir(fig_dir, "\\.png$"))
artefacts <- artefacts[order(artefacts$file), ]
write.csv(artefacts, file.path(doc_dir, "artefact_checksums.csv"), row.names = FALSE)
log_msg(nrow(artefacts), " artefacts hashed", logfile = logfile)

# --- 3. environment and source provenance ---------------------------------
git <- function(args) {
  o <- suppressWarnings(tryCatch(system2("git", args, stdout = TRUE, stderr = FALSE),
                                 error = function(e) NA_character_))
  if (!length(o) || all(is.na(o))) "unavailable" else paste(o, collapse = " ")
}
commit  <- git(c("rev-parse", "HEAD"))
branch  <- git(c("rev-parse", "--abbrev-ref", "HEAD"))
dirty   <- git(c("status", "--porcelain"))
manifest <- read.csv(here::here("data", "raw", "MANIFEST.csv"), stringsAsFactors = FALSE)
lock <- jsonlite::fromJSON(here::here("renv.lock"))

`%||%` <- function(a, b) if (is.null(a)) b else a
si <- capture.output(sessionInfo())
pkgs <- data.frame(package = names(lock$Packages),
                   version = vapply(lock$Packages, function(p) p$Version, character(1)),
                   source  = vapply(lock$Packages, function(p) p$Source %||% "", character(1)),
                   row.names = NULL)
write.csv(pkgs, file.path(doc_dir, "package_versions.csv"), row.names = FALSE)

prov <- c(
  "# Provenance record",
  "",
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  "",
  "## Study",
  "",
  "Plant-based diet quality and cardiometabolic dysfunction in US adults,",
  "NHANES 2017-March 2020 pre-pandemic. **Observational and cross-sectional.**",
  "All reported estimates are associations; no causal effect is estimated.",
  "",
  "## Git",
  "",
  paste0("- Commit: `", commit, "`"),
  paste0("- Branch: `", branch, "`"),
  paste0("- Working tree at freeze: ",
         if (identical(dirty, "unavailable") || nchar(dirty) == 0)
           "clean" else "**MODIFIED** (see below)"),
  if (nchar(dirty) > 0 && !identical(dirty, "unavailable"))
    paste0("  - `", dirty, "`") else NULL,
  "",
  "## Analytic dataset",
  "",
  paste0("- File: `data/processed/analytic_frozen.rds`"),
  paste0("- SHA-256: `", frozen_hash, "`"),
  paste0("- Analytic n: ", frozen$n_analytic),
  paste0("- Imputations: m = ", frozen$m_imputations),
  paste0("- Exposure scoring rule: `", frozen$scoring_rule, "`"),
  "",
  "## Source data",
  "",
  paste0("All inputs are public and were fetched from CDC and USDA. Integrity is",
         " pinned in `docs/checksums.lock` (", nrow(manifest), " files)."),
  "",
  paste0("- NHANES 2017-March 2020 pre-pandemic public-use files (CDC/NCHS)"),
  paste0("- FPED for use with WWEIA, NHANES 2017-March 2020 Prepandemic (USDA ARS)"),
  paste0("- FNDDS 2017-2018 and 2019-2020, At A Glance: Foods and Beverages (USDA ARS)"),
  "",
  "## Environment",
  "",
  paste0("- R: ", lock$R$Version),
  paste0("- Packages pinned in `renv.lock`: ", nrow(pkgs),
         " (full list in `docs/package_versions.csv`)"),
  paste0("- Platform: ", R.version$platform),
  "",
  "## Artefact checksums",
  "",
  paste0("SHA-256 for all ", nrow(artefacts),
         " generated tables and figures: `docs/artefact_checksums.csv`."),
  "",
  "## sessionInfo()",
  "",
  "```",
  si,
  "```")
writeLines(Filter(Negate(is.null), prov), file.path(doc_dir, "PROVENANCE.md"))

log_msg("=== 19_freeze_provenance.R complete ===", logfile = logfile)
cat("\nfrozen dataset SHA-256:", frozen_hash, "\n")
cat("artefacts hashed      :", nrow(artefacts), "\n")
cat("git commit            :", commit, "\n")
cat("working tree          :",
    if (nchar(dirty) == 0) "clean" else "MODIFIED", "\n")
