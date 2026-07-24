# ---------------------------------------------------------------------------
# 02_import.R
# Read raw .XPT files into R and validate them against the FROZEN variable
# specification (docs/variable_specification.csv).
#
# Design decision: we import EVERY column from each file rather than
# subsetting here. Subsetting happens at derivation time. Import's single
# job is to prove that every variable the protocol depends on actually
# exists, with the name the protocol claims.
#
# The specification marks each variable name as
#   VERIFIED  -- confirmed against CDC/USDA documentation
#   EXPECTED  -- not individually checked; THIS SCRIPT is the check
#   TO_VERIFY -- external source not yet resolved (skipped here)
# A missing EXPECTED name is a protocol defect, not a runtime inconvenience,
# so it is reported in full and halts the pipeline.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(here); library(haven)
})
source(here::here("R", "utils.R"))

raw_dir     <- here::here("data", "raw")
interim_dir <- here::here("data", "interim")
log_dir     <- here::here("outputs", "logs")
dir.create(interim_dir, recursive = TRUE, showWarnings = FALSE)
logfile <- file.path(log_dir, "02_import.log")

log_msg("=== 02_import.R start ===", logfile = logfile)

spec <- read.csv(here::here("docs", "variable_specification.csv"),
                 stringsAsFactors = FALSE)

xpt <- list.files(raw_dir, pattern = "\\.xpt$", ignore.case = TRUE,
                  full.names = TRUE)
if (!length(xpt)) stop("No .xpt files in data/raw/. Run 01_download.R first.")

# --- read ------------------------------------------------------------------
dat <- list(); dims <- list()
for (p in xpt) {
  nm <- toupper(sub("\\.xpt$", "", basename(p), ignore.case = TRUE))
  d  <- haven::read_xpt(p)
  d  <- as.data.frame(d)
  names(d) <- toupper(names(d))
  dat[[nm]] <- d
  dims[[nm]] <- data.frame(file = nm, rows = nrow(d), cols = ncol(d),
                           stringsAsFactors = FALSE)
  log_msg(sprintf("read %-12s %6d rows x %4d cols", nm, nrow(d), ncol(d)),
          logfile = logfile)
}
dims <- do.call(rbind, dims)

# --- validate specified variable names -------------------------------------
# Ranges written "A:B" in the spec are checked at their endpoints only;
# the intervening columns are family members verified at derivation time.
expand_spec_var <- function(v) trimws(unlist(strsplit(v, ":", fixed = TRUE)))

check <- spec[!spec$name_status %in% c("TO_VERIFY", "DERIVED") &
              spec$source_file %in% names(dat), ]

missing <- do.call(rbind, lapply(seq_len(nrow(check)), function(i) {
  f    <- check$source_file[i]
  vars <- toupper(expand_spec_var(check$nhanes_var[i]))
  gone <- setdiff(vars, names(dat[[f]]))
  if (!length(gone)) return(NULL)
  data.frame(source_file = f, expected = paste(gone, collapse = ", "),
             name_status = check$name_status[i],
             derived_var = check$derived_var[i], stringsAsFactors = FALSE)
}))

if (!is.null(missing) && nrow(missing)) {
  log_msg("VARIABLE NAME VALIDATION FAILED for ", nrow(missing), " entries",
          level = "ERROR", logfile = logfile)
  print(missing)
  write.csv(missing, file.path(log_dir, "02_missing_variables.csv"),
            row.names = FALSE)
  stop("Specified variables absent from the data. See ",
       "outputs/logs/02_missing_variables.csv. Amend the protocol ",
       "explicitly -- do not silently substitute a different variable.")
}
log_msg("all VERIFIED/EXPECTED variable names present", logfile = logfile)

# --- persist ---------------------------------------------------------------
saveRDS(dat, file.path(interim_dir, "nhanes_raw_list.rds"))
write.csv(dims, file.path(log_dir, "02_file_dimensions.csv"), row.names = FALSE)

writeLines(capture.output(sessionInfo()),
           file.path(log_dir, "02_sessionInfo.txt"))

log_msg("=== 02_import.R complete ===", logfile = logfile)
print(dims)
