# ---------------------------------------------------------------------------
# 05_exposure_pdi.R
# Construct PDI, hPDI and uPDI from NHANES 24-hour recalls.
#
# GOVERNING PRINCIPLE: every edible gram contributes to the index exactly once.
#
# Hierarchical assignment:
#   1. Items in the three WWEIA-exclusive groups (tea/coffee, SSB,
#      sweets/desserts) are assigned wholly to those groups, in grams.
#   2. All remaining items are decomposed through FPED into the other groups.
#
# See docs/methods_note_hierarchical_assignment.md for the conceptual argument
# and for the deviations from the published 18-group structure.
#
# The naive OVERLAPPING implementation is also computed, solely so that the two
# can be correlated as a transparency check. It is never used downstream.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(here); library(readxl)
})
source(here::here("R", "utils.R"))

raw_dir <- here::here("data", "raw")
int_dir <- here::here("data", "interim")
log_dir <- here::here("outputs", "logs")
tab_dir <- here::here("outputs", "tables")
doc_dir <- here::here("docs")
logfile <- file.path(log_dir, "05_exposure_pdi.log")

log_msg("=== 05_exposure_pdi.R start ===", logfile = logfile)

dat <- readRDS(file.path(int_dir, "nhanes_raw_list.rds"))
map <- read.csv(file.path(doc_dir, "pdi_food_group_mapping.csv"), stringsAsFactors = FALSE)
adj <- read.csv(file.path(doc_dir, "wweia_adjudications.csv"), stringsAsFactors = FALSE)

if (any(grepl("PROPOSED", adj$decided_by))) {
  stop("docs/wweia_adjudications.csv still contains PROPOSED (unconfirmed) ",
       "decisions. Exposure construction must not run on unadjudicated ",
       "classifications.")
}

# --- WWEIA lookup ----------------------------------------------------------
# Rule: prefer the later USDA release where a food code appears in both, since
# USDA revisions incorporate updated product information. Exposure-relevant
# conflicts are additionally required to carry an explicit adjudication (gate
# enforced in 04_wweia_conflicts.R); those adjudications override.
read_fndds <- function(f) {
  d <- suppressMessages(read_excel(file.path(raw_dir, f), sheet = 1, skip = 1))
  data.frame(food_code = as.numeric(d[[1]]), category = as.numeric(d[[4]]),
             stringsAsFactors = FALSE)
}
f17 <- read_fndds("FNDDS_2017-2018_FoodsBeverages.xlsx")
f19 <- read_fndds("FNDDS_2019-2020_FoodsBeverages.xlsx")

wweia <- merge(f17, f19, by = "food_code", all = TRUE, suffixes = c("_17", "_19"))
wweia$category <- ifelse(!is.na(wweia$category_19), wweia$category_19, wweia$category_17)
i <- match(wweia$food_code, adj$food_code)
wweia$category[!is.na(i)] <- adj$adjudicated_category[i[!is.na(i)]]
wweia <- wweia[, c("food_code", "category")]

wweia$wweia_group <- map$pdi_group[match(wweia$category, map$wweia_category)]
wweia$wweia_group[is.na(wweia$wweia_group) |
                  startsWith(as.character(wweia$wweia_group), "EXCLUDED")] <- NA
log_msg("WWEIA lookup: ", nrow(wweia), " codes; ",
        sum(!is.na(wweia$wweia_group)), " in a WWEIA-exclusive PDI group",
        logfile = logfile)

# --- FPED lookup -----------------------------------------------------------
fped <- as.data.frame(suppressMessages(
  read_excel(file.path(raw_dir, "FPED_1720.xls"), sheet = "FPED_1720_")))
names(fped)[1] <- "food_code"
names(fped) <- sub(" \\(.*$", "", names(fped))   # drop " (cup eq)" suffixes
fped$food_code <- as.numeric(fped$food_code)
FPED_COMPONENTS <- setdiff(names(fped), c("food_code", "DESCRIPTION"))
log_msg("FPED lookup: ", nrow(fped), " codes x ", length(FPED_COMPONENTS),
        " components", logfile = logfile)

# --- 17-group definition ---------------------------------------------------
# Units differ ACROSS groups; this is acceptable because each group is quintile
# scored independently. Units are consistent WITHIN each group.
GROUPS <- list(
  whole_grains   = list(class="healthy_plant",   unit="oz eq",  src="fped", expr=function(d) d$G_WHOLE),
  fruits         = list(class="healthy_plant",   unit="cup eq", src="fped", expr=function(d) d$F_TOTAL - d$F_JUICE),
  vegetables     = list(class="healthy_plant",   unit="cup eq", src="fped", expr=function(d) d$V_TOTAL - d$V_STARCHY_POTATO),
  nuts           = list(class="healthy_plant",   unit="oz eq",  src="fped", expr=function(d) d$PF_NUTSDS),
  legumes        = list(class="healthy_plant",   unit="cup eq", src="fped", expr=function(d) d$V_LEGUMES + d$PF_SOY/4),
  vegetable_oils = list(class="healthy_plant",   unit="grams",  src="fped", expr=function(d) d$OILS),
  tea_coffee     = list(class="healthy_plant",   unit="grams",  src="wweia",expr=NULL),
  fruit_juices   = list(class="unhealthy_plant", unit="cup eq", src="fped", expr=function(d) d$F_JUICE),
  refined_grains = list(class="unhealthy_plant", unit="oz eq",  src="fped", expr=function(d) d$G_REFINED),
  potatoes       = list(class="unhealthy_plant", unit="cup eq", src="fped", expr=function(d) d$V_STARCHY_POTATO),
  ssb            = list(class="unhealthy_plant", unit="grams",  src="wweia",expr=NULL),
  sweets_desserts= list(class="unhealthy_plant", unit="grams",  src="wweia",expr=NULL),
  animal_fat     = list(class="animal",          unit="grams",  src="fped", expr=function(d) d$SOLID_FATS),
  dairy          = list(class="animal",          unit="cup eq", src="fped", expr=function(d) d$D_TOTAL),
  eggs           = list(class="animal",          unit="oz eq",  src="fped", expr=function(d) d$PF_EGGS),
  fish_seafood   = list(class="animal",          unit="oz eq",  src="fped", expr=function(d) d$PF_SEAFD_HI + d$PF_SEAFD_LOW),
  meat           = list(class="animal",          unit="oz eq",  src="fped", expr=function(d) d$PF_MEAT + d$PF_CUREDMEAT + d$PF_ORGAN + d$PF_POULT)
)
WWEIA_GROUPS <- names(GROUPS)[vapply(GROUPS, function(g) g$src == "wweia", logical(1))]

write.csv(data.frame(
  pdi_group = names(GROUPS),
  pdi_class = vapply(GROUPS, `[[`, character(1), "class"),
  unit      = vapply(GROUPS, `[[`, character(1), "unit"),
  source    = vapply(GROUPS, `[[`, character(1), "src")),
  file.path(doc_dir, "pdi_group_definitions.csv"), row.names = FALSE)

# --- person-day group intakes ---------------------------------------------
build_day <- function(day, mode = c("exclusive", "overlapping")) {
  mode <- match.arg(mode)
  iff <- dat[[paste0("P_DR", day, "IFF")]]
  v <- list(seqn = "SEQN", code = paste0("DR", day, "IFDCD"),
            gram = paste0("DR", day, "IGRMS"), stat = paste0("DR", day, "DRSTZ"))
  it <- data.frame(SEQN = iff[[v$seqn]], food_code = iff[[v$code]],
                   grams = iff[[v$gram]], status = iff[[v$stat]],
                   stringsAsFactors = FALSE)
  it <- it[!is.na(it$status) & it$status == 1 & !is.na(it$grams) & it$grams > 0, ]
  it$wweia_group <- wweia$wweia_group[match(it$food_code, wweia$food_code)]

  # (1) WWEIA-exclusive groups: whole gram weight of the item
  w_part <- do.call(rbind, lapply(WWEIA_GROUPS, function(g) {
    s <- it[!is.na(it$wweia_group) & it$wweia_group == g, ]
    if (!nrow(s)) return(NULL)
    a <- aggregate(list(value = s$grams), by = list(SEQN = s$SEQN), FUN = sum)
    a$pdi_group <- g; a
  }))

  # (2) FPED decomposition. Under "exclusive", items already claimed in (1) are
  #     withheld; under "overlapping", every item is decomposed as well.
  fp <- if (mode == "exclusive") it[is.na(it$wweia_group), ] else it
  m  <- merge(fp, fped[, c("food_code", FPED_COMPONENTS)], by = "food_code")
  # FPED values are per 100 g of food.
  for (cc in FPED_COMPONENTS) m[[cc]] <- m[[cc]] * m$grams / 100
  agg <- aggregate(m[, FPED_COMPONENTS], by = list(SEQN = m$SEQN), FUN = sum)

  f_part <- do.call(rbind, lapply(setdiff(names(GROUPS), WWEIA_GROUPS), function(g) {
    data.frame(SEQN = agg$SEQN, value = GROUPS[[g]]$expr(agg), pdi_group = g)
  }))

  long <- rbind(w_part, f_part)
  out <- reshape(long, idvar = "SEQN", timevar = "pdi_group", direction = "wide")
  names(out) <- sub("^value\\.", "", names(out))
  for (g in names(GROUPS)) {
    if (!g %in% names(out)) out[[g]] <- 0
    out[[g]][is.na(out[[g]])] <- 0   # not reported == zero intake
  }
  out[, c("SEQN", names(GROUPS))]
}

# --- analytic sample for quintile cutpoints -------------------------------
# Cutpoints are defined in the day-1 dietary analytic sample (adults 20+,
# non-pregnant, MEC-examined, reliable recall), weighted by WTDRD1PP. This is
# a larger and more stable reference than the fasting subsample in which the
# outcome models run; a sensitivity analysis re-derives cutpoints within the
# fasting subsample.
demo <- dat[["P_DEMO"]]; d1 <- dat[["P_DR1TOT"]]
spine <- demo[demo$RIDAGEYR >= 20 & demo$RIDSTATR == 2 &
              (is.na(demo$RIDEXPRG) | demo$RIDEXPRG != 1), "SEQN", drop = FALSE]
w <- d1[, c("SEQN", "WTDRD1PP", "DR1DRSTZ")]
samp <- merge(spine, w, by = "SEQN")
samp <- samp[!is.na(samp$DR1DRSTZ) & samp$DR1DRSTZ == 1 &
             !is.na(samp$WTDRD1PP) & samp$WTDRD1PP > 0, ]
log_msg("quintile-reference sample: n = ", nrow(samp), logfile = logfile)

# --- weighted quintile scoring --------------------------------------------
# Midpoint-adjusted weighted ECDF computed over DISTINCT VALUES, so that every
# participant reporting the same intake receives the same score.
#
# This must be done at the distinct-value level. Computing the ECDF over sorted
# observations instead lets cumsum() increase across a block of tied values,
# which silently spreads participants who all reported ZERO intake across
# different quintiles according to arbitrary sort order. For a group such as
# fish/seafood, where ~82% report zero, that is a large and invisible error.
# Values are grouped with factor(), NOT by matching on tapply()'s names.
# tapply() names are character representations of the numeric values, and
# as.numeric(as.character(x)) does not reliably round-trip a double, so
# match(x, vals) silently returns NA for affected observations.
# Distinct values are identified by INTEGER INDEX POSITION into sort(unique(x)).
# Neither factor() nor tapply() names may be used to group the raw doubles:
# both convert levels to character, and two doubles that differ beyond ~15
# significant digits collide into one label (or, in reverse, fail to match).
# match() on doubles compares the values exactly, so it is safe here.
wtd_quintile <- function(x, w) {
  stopifnot(!anyNA(x), !anyNA(w), length(x) == length(w))
  u   <- sort(unique(x))
  idx <- match(x, u)                                    # exact, integer 1..k
  wv  <- as.numeric(tapply(w, factor(idx, levels = seq_along(u)), sum))
  wv[is.na(wv)] <- 0
  p   <- (cumsum(wv) - wv / 2) / sum(w)                 # midpoint of each block
  q   <- as.integer(cut(p[idx], c(-Inf, .2, .4, .6, .8, Inf), labels = 1:5))
  if (anyNA(q)) stop("wtd_quintile produced NA scores -- investigate before use.")
  q
}

score_pdi <- function(intake, samp) {
  d <- merge(samp[, c("SEQN", "WTDRD1PP")], intake, by = "SEQN")
  qs <- sapply(names(GROUPS), function(g) wtd_quintile(d[[g]], d$WTDRD1PP))
  qs <- as.data.frame(qs)
  rev <- 6 - qs
  cls <- vapply(GROUPS, `[[`, character(1), "class")
  hp <- names(GROUPS)[cls == "healthy_plant"]
  up <- names(GROUPS)[cls == "unhealthy_plant"]
  an <- names(GROUPS)[cls == "animal"]
  data.frame(
    SEQN = d$SEQN,
    PDI  = rowSums(qs[, c(hp, up)]) + rowSums(rev[, an]),
    hPDI = rowSums(qs[, hp]) + rowSums(rev[, c(up, an)]),
    uPDI = rowSums(qs[, up]) + rowSums(rev[, c(hp, an)])
  )
}

log_msg("building day-1 intakes (exclusive)...", logfile = logfile)
int_excl <- build_day(1, "exclusive")
log_msg("building day-1 intakes (overlapping, for comparison only)...", logfile = logfile)
int_over <- build_day(1, "overlapping")
log_msg("building day-2 intakes (exclusive, for calibration)...", logfile = logfile)
int_excl_d2 <- build_day(2, "exclusive")

pdi_excl <- score_pdi(int_excl, samp)
pdi_over <- score_pdi(int_over, samp)

# --- diagnostics: did any group collapse? ---------------------------------
d <- merge(samp[, c("SEQN", "WTDRD1PP")], int_excl, by = "SEQN")
diag <- do.call(rbind, lapply(names(GROUPS), function(g) {
  q <- wtd_quintile(d[[g]], d$WTDRD1PP)
  data.frame(pdi_group = g, class = GROUPS[[g]]$class, unit = GROUPS[[g]]$unit,
             pct_zero = round(100 * mean(d[[g]] == 0), 1),
             n_score_levels = length(unique(q[!is.na(q)])),
             mean_intake = round(mean(d[[g]]), 3))
}))
write.csv(diag, file.path(tab_dir, "05_group_diagnostics.csv"), row.names = FALSE)

collapsed <- diag[diag$n_score_levels < 5, ]
if (nrow(collapsed)) {
  log_msg("NOTE: ", nrow(collapsed), " group(s) yielded <5 distinct score ",
          "levels because of zero-inflation: ",
          paste(collapsed$pdi_group, collapse = ", "), level = "WARN",
          logfile = logfile)
}

# --- transparency comparison ----------------------------------------------
cmp <- merge(pdi_excl, pdi_over, by = "SEQN", suffixes = c("_excl", "_over"))
comparison <- do.call(rbind, lapply(c("PDI", "hPDI", "uPDI"), function(s) {
  a <- cmp[[paste0(s, "_excl")]]; b <- cmp[[paste0(s, "_over")]]
  data.frame(score = s,
             pearson  = round(cor(a, b, method = "pearson"), 4),
             spearman = round(cor(a, b, method = "spearman"), 4),
             mean_exclusive = round(mean(a), 2), mean_overlapping = round(mean(b), 2),
             sd_exclusive = round(sd(a), 2), sd_overlapping = round(sd(b), 2),
             mean_abs_diff = round(mean(abs(a - b)), 2))
}))
write.csv(comparison, file.path(tab_dir, "05_exclusive_vs_overlapping.csv"),
          row.names = FALSE)

saveRDS(list(intake_day1 = int_excl, intake_day2 = int_excl_d2,
             pdi_day1 = pdi_excl, groups = GROUPS,
             quintile_sample = samp$SEQN),
        file.path(int_dir, "exposure_pdi.rds"))

log_msg("=== 05_exposure_pdi.R complete ===", logfile = logfile)
cat("\n--- group diagnostics ---\n"); print(diag, row.names = FALSE)
cat("\n--- exclusive vs overlapping ---\n"); print(comparison, row.names = FALSE)
cat("\n--- PDI score distributions (exclusive) ---\n")
print(summary(pdi_excl[, c("PDI", "hPDI", "uPDI")]))
