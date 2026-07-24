# ---------------------------------------------------------------------------
# 04_wweia_conflicts.R
# Adjudication gate for WWEIA food-category disagreements between FNDDS
# releases.
#
# Both FNDDS 2017-2018 and 2019-2020 are required to cover the pre-pandemic
# food codes (95.2% and 75.6% individually; 100% together). Where a food code
# appears in both releases with DIFFERENT WWEIA category assignments, the
# disagreement must be resolved -- but only a disagreement that changes a PDI
# food-group assignment can change the exposure.
#
# Policy (set by the protocol, implemented here):
#   * conflict does NOT change a PDI group  -> document and proceed
#   * conflict DOES change a PDI group      -> HALT for manual adjudication;
#                                              the decision is then recorded in
#                                              docs/wweia_adjudications.csv so
#                                              every future run is identical
#
# There is deliberately no automatic precedence rule for exposure-relevant
# conflicts. A silent tie-break is exactly the kind of invisible decision this
# pipeline is built to prevent.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(here); library(readxl)
})
source(here::here("R", "utils.R"))

raw_dir <- here::here("data", "raw")
log_dir <- here::here("outputs", "logs")
tab_dir <- here::here("outputs", "tables")
doc_dir <- here::here("docs")
logfile <- file.path(log_dir, "04_wweia_conflicts.log")
adjudication_file <- file.path(doc_dir, "wweia_adjudications.csv")

log_msg("=== 04_wweia_conflicts.R start ===", logfile = logfile)

read_fndds <- function(path, release) {
  d <- suppressMessages(read_excel(path, sheet = 1, skip = 1))
  data.frame(food_code   = as.numeric(d[[1]]),
             description = as.character(d[[2]]),
             category    = as.numeric(d[[4]]),
             cat_desc    = as.character(d[[5]]),
             release     = release, stringsAsFactors = FALSE)
}

f17 <- read_fndds(file.path(raw_dir, "FNDDS_2017-2018_FoodsBeverages.xlsx"), "2017-2018")
f19 <- read_fndds(file.path(raw_dir, "FNDDS_2019-2020_FoodsBeverages.xlsx"), "2019-2020")
log_msg("FNDDS 2017-2018: ", nrow(f17), " codes | 2019-2020: ", nrow(f19), " codes",
        logfile = logfile)

# --- PDI mapping (version-controlled) --------------------------------------
map <- read.csv(file.path(doc_dir, "pdi_food_group_mapping.csv"),
                stringsAsFactors = FALSE)
pdi_of <- function(cat) {
  g <- map$pdi_group[match(cat, map$wweia_category)]
  # Categories absent from the mapping are not PDI-relevant via WWEIA: their
  # PDI groups are derived from FPED pattern equivalents instead.
  g[is.na(g)] <- "not_wweia_derived"
  g[startsWith(g, "EXCLUDED")] <- "not_wweia_derived"
  g
}

# --- conflict detection ----------------------------------------------------
both <- merge(f17[, c("food_code", "description", "category", "cat_desc")],
              f19[, c("food_code", "category", "cat_desc")],
              by = "food_code", suffixes = c("_1718", "_1920"))
log_msg("food codes present in both releases: ", nrow(both), logfile = logfile)

conf <- both[both$category_1718 != both$category_1920, ]
conf$pdi_group_1718 <- pdi_of(conf$category_1718)
conf$pdi_group_1920 <- pdi_of(conf$category_1920)
conf$changes_pdi_group  <- conf$pdi_group_1718 != conf$pdi_group_1920
# A conflict affects the computed exposure only if at least one side of the
# disagreement lands in a PDI group that WWEIA actually supplies.
conf$affects_exposure <- conf$changes_pdi_group &
  (conf$pdi_group_1718 != "not_wweia_derived" | conf$pdi_group_1920 != "not_wweia_derived")

report <- conf[, c("food_code", "description",
                   "category_1718", "cat_desc_1718",
                   "category_1920", "cat_desc_1920",
                   "pdi_group_1718", "pdi_group_1920",
                   "changes_pdi_group", "affects_exposure")]
report <- report[order(-report$affects_exposure, report$food_code), ]

write.csv(report, file.path(tab_dir, "04_wweia_category_conflicts.csv"),
          row.names = FALSE)

log_msg("conflicts: ", nrow(report),
        " | changing a PDI group: ", sum(report$changes_pdi_group),
        " | affecting the exposure: ", sum(report$affects_exposure),
        logfile = logfile)

# --- coverage check --------------------------------------------------------
# Every FPED food code must receive a WWEIA category from the union of the two
# releases, or the three WWEIA-derived PDI groups would be silently incomplete.
fped <- suppressMessages(read_excel(file.path(raw_dir, "FPED_1720.xls"),
                                    sheet = "FPED_1720_"))
fped_codes <- unique(as.numeric(fped[[1]]))
covered <- fped_codes %in% union(f17$food_code, f19$food_code)
log_msg("FPED codes covered by the FNDDS union: ", sum(covered), "/",
        length(fped_codes), sprintf(" (%.1f%%)", 100 * mean(covered)),
        logfile = logfile)
if (!all(covered)) {
  write.csv(data.frame(food_code = fped_codes[!covered]),
            file.path(log_dir, "04_uncovered_food_codes.csv"), row.names = FALSE)
  stop(sum(!covered), " FPED food codes have no WWEIA category in either ",
       "FNDDS release. See outputs/logs/04_uncovered_food_codes.csv.")
}

# --- adjudication gate -----------------------------------------------------
needs <- report[report$affects_exposure, ]

if (nrow(needs) == 0) {
  log_msg("NO conflict changes a PDI food-group assignment; proceeding automatically",
          logfile = logfile)
  if (!file.exists(adjudication_file)) {
    write.csv(
      data.frame(food_code = integer(), description = character(),
                 category_1718 = integer(), category_1920 = integer(),
                 adjudicated_category = integer(), decided_by = character(),
                 decided_on = character(), rationale = character()),
      adjudication_file, row.names = FALSE)
    log_msg("empty adjudication table created (schema fixed for future runs)",
            logfile = logfile)
  }
} else {
  resolved <- FALSE
  if (file.exists(adjudication_file)) {
    adj <- read.csv(adjudication_file, stringsAsFactors = FALSE)
    resolved <- all(needs$food_code %in% adj$food_code) && nrow(adj) > 0
  }
  if (resolved) {
    log_msg("all ", nrow(needs), " exposure-relevant conflicts already ",
            "adjudicated in docs/wweia_adjudications.csv", logfile = logfile)
  } else {
    log_msg(nrow(needs), " conflicts change a PDI group and are NOT adjudicated",
            level = "ERROR", logfile = logfile)
    print(needs[, c("food_code", "description", "pdi_group_1718", "pdi_group_1920")])
    stop(nrow(needs), " WWEIA conflicts change a PDI food-group assignment and ",
         "require manual adjudication. Review ",
         "outputs/tables/04_wweia_category_conflicts.csv, record each decision ",
         "in docs/wweia_adjudications.csv, then re-run. No automatic ",
         "precedence rule is applied to exposure-relevant conflicts.")
  }
}

log_msg("=== 04_wweia_conflicts.R complete ===", logfile = logfile)
cat("\n--- conflicts affecting the exposure ---\n")
print(if (nrow(needs)) needs else "none")
cat("\n--- all conflicts (first 12) ---\n")
print(head(report[, c("food_code", "cat_desc_1718", "cat_desc_1920",
                      "changes_pdi_group", "affects_exposure")], 12),
      row.names = FALSE)
