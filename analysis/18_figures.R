# ---------------------------------------------------------------------------
# 18_figures.R
# Generate every manuscript figure directly from stored analysis objects.
#
# Presentation only: this script reads results, it never estimates anything.
# Every figure is written as a 600 dpi raster (ragg) and as a vector file
# (svglite), at journal column widths.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(here); library(ggplot2); library(scales); library(patchwork)
})
source(here::here("R", "utils.R"))
source(here::here("R", "theme_manuscript.R"))

int_dir <- here::here("data", "interim")
tab_dir <- here::here("outputs", "tables")
fig_dir <- here::here("outputs", "figures")
log_dir <- here::here("outputs", "logs")
logfile <- file.path(log_dir, "18_figures.log")
log_msg("=== 18_figures.R start ===", logfile = logfile)

sens <- readRDS(file.path(int_dir, "sensitivity.rds"))
sub  <- readRDS(file.path(int_dir, "substitution.rds"))
pca  <- readRDS(file.path(int_dir, "pca.rds"))
exp_ <- readRDS(file.path(int_dir, "exposure_pdi.rds"))

# Every number in the manuscript describes the analytic sample, so figures that
# quote a descriptive statistic must be restricted to it. `exposure_pdi.rds`
# holds the whole day-1 recall population (7,629) and the whole replicate
# population (6,575 pairs), which are NOT what the models were fitted on
# (Amendment 13). This is the authoritative list of the analytic SEQNs.
ANALYTIC <- readRDS(file.path(int_dir, "imputed_data.rds"))$completed[[1]]$SEQN
stopifnot(length(ANALYTIC) > 0, !anyDuplicated(ANALYTIC))
log_msg("analytic sample for figure statistics: n = ", length(ANALYTIC),
        logfile = logfile)

XLAB <- expression(paste("Difference in cardiometabolic dysfunction score (SD) per SD higher hPDI"))
DIRN <- "← lower dysfunction        higher dysfunction →"

# --- F1: sensitivity audit -------------------------------------------------
a <- sens$audit
a$ci_low  <- as.numeric(sub(" to.*", "", a$ci))
a$ci_high <- as.numeric(sub(".*to ", "", a$ci))
a$label   <- sprintf("%s  (n = %s)", sub("^[0-9a-c]+\\. ", "", a$analysis),
                     format(a$n, big.mark = ","))
a$flag    <- a$analysis == "PRIMARY (reference)"
a$family  <- c("Primary", "Survey weight",
               rep("Reverse causation", 3), rep("Medication handling", 3),
               "Exposure scoring", "Energy reporting")
a$family  <- factor(a$family, levels = c("Primary", "Survey weight",
                                         "Reverse causation", "Medication handling",
                                         "Exposure scoring", "Energy reporting"))

a$estimate <- a$beta
PRIMARY_REF <- a$beta[1]

f1 <- forest_gg(a, xlab = XLAB, ref = PRIMARY_REF,
  title = "Primary estimate and pre-specified sensitivity analyses",
  subtitle = paste("Every pre-specified analysis is shown, whether or not it was",
                   "favourable.\nAll intervals overlap the primary estimate and no",
                   "inference changes."),
  caption = paste0(DIRN,
    "\nDotted line, primary estimate; dashed line, null. Survey-weighted linear",
    " regression, m = 20 imputations pooled by Rubin's rules."),
  facet = TRUE)
save_fig(f1, "F1_sensitivity_forest", W_DOUBLE, 5.4)
log_msg("F1 written", logfile = logfile)

# --- F2: pre-specified substitutions --------------------------------------
p <- sub$prespec
nice <- c(whole_grains = "Whole grains", fruits = "Whole fruit",
          vegetables = "Vegetables", nuts = "Nuts", legumes = "Legumes",
          vegetable_oils = "Vegetable oils", tea_coffee = "Tea and coffee",
          fruit_juices = "Fruit juice", refined_grains = "Refined grains",
          potatoes = "Potatoes", ssb = "Sugar-sweetened beverages",
          sweets_desserts = "Sweets and desserts", animal_fat = "Animal fat",
          dairy = "Dairy", eggs = "Eggs", fish_seafood = "Fish and seafood",
          meat = "Meat")
p$label <- sprintf("%s → %s\n(%s)", nice[p$from], nice[p$to], p$unit)
p$flag  <- p$p_fdr < 0.05
p <- p[order(p$estimate), ]

# The zero-inflation that explains the wide legume intervals is a property of
# the sample this model was fitted on, so it is computed there rather than
# quoted from `05_group_diagnostics.csv`, whose pct_zero (75.7) is over the
# whole day-1 recall population and answers a different question (Amendment 13).
lg <- exp_$intake_day1$legumes[exp_$intake_day1$SEQN %in% ANALYTIC]
stopifnot(length(lg) == length(ANALYTIC))
legume_zero <- 100 * mean(lg == 0)

f2 <- forest_gg(p,
  xlab = "Difference in cardiometabolic dysfunction score (SD) per unit substituted",
  title = "Pre-specified isocaloric food-group substitutions",
  subtitle = paste("Holding total energy constant. Filled diamonds survive",
                   "Benjamini–Hochberg control at 5%."),
  caption = paste0(DIRN,
    "\nEstimates are differences of coefficients from a single model containing",
    " all 17 food groups, total energy and covariates.\nWide intervals for fruit",
    " juice and potatoes reflect low power, not evidence of no association: ",
    sprintf("%.0f%% of the analytic sample\nreported no legumes on the recall day.",
            legume_zero)))
save_fig(f2, "F2_substitution_forest", W_DOUBLE, 3.6)
log_msg("F2 written", logfile = logfile)

# --- F3: all-components model, 17 food groups ------------------------------
cf <- sub$coef_tab
cf$label <- sprintf("%s  (%s)", nice[cf$pdi_group], cf$unit)
cf$flag  <- cf$ci_low > 0 | cf$ci_high < 0
cf$family <- factor(cf$class,
                    levels = c("healthy_plant", "unhealthy_plant", "animal"),
                    labels = c("Healthy plant foods", "Less-healthy plant foods",
                               "Animal foods"))
cf <- cf[order(cf$family, cf$beta), ]
cf$estimate <- cf$beta

f3 <- forest_gg(cf,
  xlab = "Difference in cardiometabolic dysfunction score (SD) per unit/day",
  title = "Individual food-group associations from the all-components model",
  subtitle = "Mutually exclusive groups; every edible gram contributes exactly once.",
  caption = paste0(DIRN,
    "\nUnits differ across groups and are shown beside each label; coefficients",
    " are NOT comparable across units. Vegetable oils and animal fat are\nexpressed",
    " per 100 g, an unusually large serving, which is why their intervals are the",
    " widest on the plot."),
  facet = TRUE)
save_fig(f3, "F3_food_group_coefficients", W_DOUBLE, 5.8)
log_msg("F3 written", logfile = logfile)

# --- F4: PCA loadings and scree -------------------------------------------
L <- pca$loadings
ld <- data.frame(
  biomarker = rep(rownames(L), ncol(L)),
  component = rep(colnames(L), each = nrow(L)),
  loading   = as.vector(L))
pretty_bm <- c(waist = "Waist circumference", log_tg = "Triglycerides (log)",
               hdl_rev_log = "HDL-C (reversed, log)", log_glucose = "Fasting glucose (log)",
               map = "Mean arterial pressure", log_homa_ir = "HOMA-IR (log)",
               log_hba1c = "HbA1c (log)", log_hscrp = "hs-CRP (log)",
               log_alt = "ALT (log)")
ld$biomarker <- factor(pretty_bm[ld$biomarker],
                       levels = rev(pretty_bm[rownames(L)]))
ld$component <- factor(ld$component,
                       labels = c("PC1\nAdiposity–lipid–inflammation",
                                  "PC2\nGlycaemic")[seq_len(ncol(L))])

pA <- ggplot(ld, aes(component, biomarker, fill = loading)) +
  geom_tile(colour = "white", linewidth = 0.8) +
  geom_text(aes(label = sprintf("%.2f", loading),
                colour = abs(loading) > 0.55), size = 2.9,
            family = BASE_FONT, show.legend = FALSE) +
  scale_colour_manual(values = c(`TRUE` = "white", `FALSE` = "grey20")) +
  scale_fill_gradient2(low = unname(OI["vermillion"]), mid = "white",
                       high = ACCENT, midpoint = 0, limits = c(-1, 1),
                       name = "Rotated loading") +
  labs(x = NULL, y = NULL, title = "Rotated component loadings") +
  theme_heatmap() +
  theme(legend.position = "bottom", legend.key.width = unit(1.4, "lines"))

ret <- pca$retention
sc <- data.frame(
  component = rep(ret$component, 3),
  value = c(ret$eigenvalue, ret$pa_threshold_nominal_n, ret$pa_threshold_effective_n),
  series = rep(c("Observed", "Parallel analysis (nominal n)",
                 "Parallel analysis (effective n)"), each = nrow(ret)))
sc$series <- factor(sc$series, levels = unique(sc$series))

pB <- ggplot(sc, aes(component, value, colour = series, linetype = series,
                     shape = series)) +
  geom_line(linewidth = 0.5) + geom_point(size = 1.8) +
  scale_colour_manual(values = c(ACCENT, MUTED, MUTED), name = NULL) +
  scale_linetype_manual(values = c("solid", "dashed", "dotted"), name = NULL) +
  scale_shape_manual(values = c(16, 1, 2), name = NULL) +
  scale_x_continuous(breaks = ret$component) +
  labs(x = "Component", y = "Eigenvalue",
       title = "Scree plot with retention thresholds") +
  theme_manuscript() +
  theme(panel.grid.major.y = element_line(colour = "grey92", linewidth = 0.3),
        legend.position = "bottom", legend.direction = "vertical",
        legend.key.height = unit(0.7, "lines"))

f4 <- (pA | pB) + plot_annotation(
  tag_levels = "A",
  title = "Biomarker principal component analysis (exploratory)",
  caption = paste("Two components were retained at both the nominal (n = 3,269)",
                  "and the effective (n = 1,162) sample size; Kaiser's criterion",
                  "would have retained three.\nParallel analysis has no",
                  "survey-weighted implementation: it generates its null at the",
                  "nominal n and therefore tends to over-retain, so it is used as",
                  "a heuristic\nsupported by the scree plot and by whether a",
                  "component is interpretable a priori."),
  theme = theme_manuscript() +
    theme(plot.title = element_text(face = "bold", size = rel(1.2)),
          plot.caption = element_text(colour = "grey40", size = rel(0.78),
                                      hjust = 0)))
save_fig(f4, "F4_pca", W_DOUBLE, 4.6)
log_msg("F4 written", logfile = logfile)

# --- F5: measurement-error calibration ------------------------------------
cr <- read.csv(file.path(tab_dir, "10_calibration_results.csv"))
cr <- cr[cr$quantity != "lambda (reliability ratio)", ]
cr$label <- c("Naive\n(single day-1 recall)", "Regression-calibrated\n(day-2 replicate)")
cr$flag  <- c(FALSE, TRUE)

f5 <- forest_gg(cr, xlab = XLAB,
  title = "Correcting for within-person recall error",
  subtitle = "Reliability ratio λ = 0.39; deattenuation factor 2.58",
  caption = paste0(DIRN,
    "\nWithin-person variance (23.4) exceeded between-person variance (14.9).",
    " The correction is PARTIAL: recall error here is\ndifferential with respect",
    " to adiposity, violating the classical assumption, so the corrected estimate",
    " remains conservative."))
save_fig(f5, "F5_calibration", W_DOUBLE, 2.9)
log_msg("F5 written", logfile = logfile)

# --- F6: exposure distribution and day-to-day reliability -----------------
# Both panels describe the analytic sample. Before Amendment 13 they were drawn
# straight from the exposure files: panel A showed 7,629 day-1 respondents and
# panel B 6,575 replicate pairs, while the caption -- and the Results, Abstract
# and Methods -- said n = 2,739. The printed correlation was 0.50 against the
# 0.49 reported everywhere else, because it was the correlation of a different
# population. n and r are now derived from the rows actually plotted.
d1 <- exp_$pdi_day1[exp_$pdi_day1$SEQN %in% ANALYTIC, ]
h  <- merge(d1[, c("SEQN", "hPDI")],
            exp_$pdi_day2[exp_$pdi_day2$SEQN %in% ANALYTIC, c("SEQN", "hPDI")],
            by = "SEQN", suffixes = c("_d1", "_d2"))
r  <- cor(h$hPDI_d1, h$hPDI_d2)
# the replicate subsample is a strict subset of the analytic sample, and the
# calibration in 10_calibration.R is fitted on exactly these rows
stopifnot(nrow(d1) == length(ANALYTIC),
          nrow(h) > 0, nrow(h) <= nrow(d1),
          all(h$SEQN %in% ANALYTIC))

qA <- ggplot(d1, aes(hPDI)) +
  geom_histogram(binwidth = 1, fill = ACCENT, colour = "white", linewidth = 0.2) +
  labs(x = "hPDI, day 1", y = "Participants",
       title = "Distribution of healthful plant-based diet index",
       caption = sprintf("Analytic sample, n = %s.",
                         format(nrow(d1), big.mark = ","))) +
  theme_manuscript() +
  theme(panel.grid.major.y = element_line(colour = "grey92", linewidth = 0.3))

qB <- ggplot(h, aes(hPDI_d1, hPDI_d2)) +
  geom_bin2d(bins = 34) +
  scale_fill_gradient(low = "grey90", high = ACCENT, name = "Participants") +
  geom_abline(slope = 1, intercept = 0, colour = "grey35", linetype = "dashed",
              linewidth = 0.4) +
  annotate("text", x = min(h$hPDI_d1) + 4, y = max(h$hPDI_d2) - 2,
           label = sprintf("r = %.2f", r), family = BASE_FONT, size = 3.2,
           colour = "grey15", fontface = "bold") +
  labs(x = "hPDI, day 1", y = "hPDI, day 2",
       title = "Day-to-day agreement (replicate subsample)",
       caption = sprintf(paste("n = %s. A single 24-hour recall captures less than",
                               "half the reliable\nsignal in usual plant-based diet quality."),
                         format(nrow(h), big.mark = ","))) +
  theme_manuscript() +
  theme(panel.grid.major.y = element_line(colour = "grey92", linewidth = 0.3))

f6 <- (qA | qB) + plot_annotation(tag_levels = "A")
save_fig(f6, "F6_exposure_reliability", W_DOUBLE, 3.4)
log_msg("F6 written", logfile = logfile)

log_msg("=== 18_figures.R complete ===", logfile = logfile)
cat("figures written (png + svg):\n")
print(list.files(fig_dir, pattern = "^F[0-9]"))
