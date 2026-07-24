# ---------------------------------------------------------------------------
# 01_download.R
# Acquire raw public data, record provenance, and verify integrity.
#
# Sources (all official, all public, none requiring credentials)
#   1. CDC NHANES 2017-March 2020 pre-pandemic public-use files (.XPT)
#   2. USDA FPED 2017-March 2020 Prepandemic, food-code level (.xls)
#   3. USDA FNDDS 2017-2018 and 2019-2020 "At A Glance - Foods and Beverages"
#      (.xlsx), which carry the official WWEIA food-code -> category crosswalk
#
# Why BOTH FNDDS releases (verified empirically, not assumed):
#   FPED_1720 contains 7,444 food codes. FNDDS 2017-2018 covers 95.2% of them;
#   FNDDS 2019-2020 covers 75.6%; their UNION covers exactly 100%. Using either
#   release alone would silently drop food codes from the SSB, tea/coffee and
#   sweets/desserts groups, which are the three PDI components that FPED cannot
#   supply. Both are therefore mandatory inputs.
#
# Integrity model:
#   First run writes docs/checksums.lock, pinning the SHA-256 of every input.
#   Every later run verifies against that lock and FAILS on any mismatch, so a
#   silent upstream revision cannot change results unnoticed. Re-pinning is
#   deliberate and explicit: NHANES_REPIN=1 Rscript analysis/01_download.R
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(here); library(digest)
})
source(here::here("R", "utils.R"))

raw_dir <- here::here("data", "raw")
log_dir <- here::here("outputs", "logs")
doc_dir <- here::here("docs")
for (d in c(raw_dir, log_dir, doc_dir)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
logfile  <- file.path(log_dir, "01_download.log")
lockfile <- file.path(doc_dir, "checksums.lock")

log_msg("=== 01_download.R start ===", logfile = logfile)

# --- source registry -------------------------------------------------------
NHANES_BASE <- "https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017/DataFiles"
USDA_APPS   <- "https://www.ars.usda.gov/ARSUserFiles/80400530/apps"

nhanes_files <- c(
  "P_DEMO",                                                    # demographics/design
  "P_DR1TOT", "P_DR2TOT", "P_DR1IFF", "P_DR2IFF", "P_DSQTOT",  # dietary
  "P_BMX", "P_BPXO",                                           # examination
  "P_HDL", "P_TCHOL", "P_TRIGLY", "P_GLU", "P_INS",
  "P_GHB", "P_HSCRP", "P_BIOPRO",                              # laboratory
  "P_SMQ", "P_ALQ", "P_PAQ", "P_DIQ", "P_BPQ", "P_MCQ",
  "P_RXQ_RX", "P_WHQ", "P_DBQ"                                 # questionnaire
)

registry <- rbind(
  data.frame(url  = sprintf("%s/%s.xpt", NHANES_BASE, nhanes_files),
             dest = paste0(nhanes_files, ".xpt"), stringsAsFactors = FALSE),
  data.frame(
    # Food-code-level FPED, NOT the day-level release: the day-level FPED files
    # ship only as Windows self-extracting .EXE archives and are not
    # reproducible on Linux. Item-level detail is required for the substitution
    # models regardless.
    url  = file.path(USDA_APPS, "FPED_1720.xls"),
    dest = "FPED_1720.xls", stringsAsFactors = FALSE),
  data.frame(
    url  = c(file.path(USDA_APPS, utils::URLencode("2017-2018 FNDDS At A Glance - Foods and Beverages.xlsx")),
             file.path(USDA_APPS, utils::URLencode("2019-2020 FNDDS At A Glance - Foods and Beverages.xlsx"))),
    dest = c("FNDDS_2017-2018_FoodsBeverages.xlsx",
             "FNDDS_2019-2020_FoodsBeverages.xlsx"), stringsAsFactors = FALSE)
)

# --- fetch -----------------------------------------------------------------
manifest <- do.call(rbind, lapply(seq_len(nrow(registry)), function(i) {
  download_if_needed(registry$url[i], file.path(raw_dir, registry$dest[i]),
                     logfile = logfile)
}))
manifest$downloaded_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
write.csv(manifest, file.path(raw_dir, "MANIFEST.csv"), row.names = FALSE)

n_fail <- sum(manifest$status == "failed")
if (n_fail > 0) {
  log_msg(n_fail, " downloads failed", level = "ERROR", logfile = logfile)
  print(manifest[manifest$status == "failed", c("file", "url")])
  stop("Download incomplete. Do not proceed to 02_import.R.")
}

# --- integrity gate --------------------------------------------------------
current <- manifest[, c("file", "sha256")]
current <- current[order(current$file), ]

repin <- identical(Sys.getenv("NHANES_REPIN"), "1")

if (!file.exists(lockfile) || repin) {
  write.csv(current, lockfile, row.names = FALSE)
  log_msg(if (repin) "checksums RE-PINNED (NHANES_REPIN=1)" else
          "checksums pinned for the first time", " -> docs/checksums.lock",
          logfile = logfile)
} else {
  locked <- read.csv(lockfile, stringsAsFactors = FALSE)
  cmp <- merge(locked, current, by = "file", all = TRUE,
               suffixes = c("_locked", "_actual"))
  bad <- cmp[is.na(cmp$sha256_locked) | is.na(cmp$sha256_actual) |
             cmp$sha256_locked != cmp$sha256_actual, ]
  if (nrow(bad)) {
    log_msg("CHECKSUM VERIFICATION FAILED for ", nrow(bad), " files",
            level = "ERROR", logfile = logfile)
    print(bad)
    write.csv(bad, file.path(log_dir, "01_checksum_mismatches.csv"), row.names = FALSE)
    stop("Input files do not match docs/checksums.lock. Either an upstream ",
         "file was revised or a download is corrupt. Investigate before ",
         "proceeding; re-pin only deliberately with NHANES_REPIN=1.")
  }
  log_msg("checksum verification passed for all ", nrow(locked), " inputs",
          logfile = logfile)
}

log_msg("=== 01_download.R complete ===", logfile = logfile)
print(manifest[, c("file", "bytes", "status")])
