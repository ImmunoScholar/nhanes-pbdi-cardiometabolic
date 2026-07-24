# ---------------------------------------------------------------------------
# 18_figures.R
# Generate every manuscript figure directly from stored analysis objects.
# Base graphics only -- no plotting package is added to the locked environment.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({ library(here) })
source(here::here("R", "utils.R"))

int_dir <- here::here("data", "interim")
tab_dir <- here::here("outputs", "tables")
fig_dir <- here::here("outputs", "figures")
log_dir <- here::here("outputs", "logs")
logfile <- file.path(log_dir, "18_figures.log")
log_msg("=== 18_figures.R start ===", logfile = logfile)

sens <- readRDS(file.path(int_dir, "sensitivity.rds"))
sub  <- readRDS(file.path(int_dir, "substitution.rds"))
pca  <- readRDS(file.path(int_dir, "pca.rds"))
cal  <- readRDS(file.path(int_dir, "calibration.rds"))

PT <- 200   # resolution

forest <- function(labels, est, lo, hi, xlab, main, ref = NULL,
                   highlight = 1, xlim = NULL) {
  n <- length(est); y <- rev(seq_len(n))
  if (is.null(xlim)) {
    r <- range(c(lo, hi, 0), na.rm = TRUE); pad <- diff(r) * 0.08
    xlim <- c(r[1] - pad, r[2] + pad)
  }
  par(mar = c(4.5, 17, 3, 1.5), xpd = FALSE)
  plot(NA, xlim = xlim, ylim = c(0.4, n + 0.6), axes = FALSE,
       xlab = xlab, ylab = "", main = main)
  abline(v = 0, col = "grey55", lty = 2)
  if (!is.null(ref)) abline(v = ref, col = "grey80", lty = 3)
  segments(lo, y, hi, y, lwd = 2,
           col = ifelse(seq_len(n) %in% highlight, "black", "grey35"))
  points(est, y, pch = ifelse(seq_len(n) %in% highlight, 18, 16),
         cex = ifelse(seq_len(n) %in% highlight, 1.9, 1.25),
         col = ifelse(seq_len(n) %in% highlight, "black", "grey20"))
  axis(1); axis(2, at = y, labels = labels, las = 1, tick = FALSE, cex.axis = 0.82)
  box(bty = "l")
}

# --- Figure 1: sensitivity audit forest -----------------------------------
a <- sens$audit
png(file.path(fig_dir, "F1_sensitivity_forest.png"), width = 2100, height = 1500, res = PT)
forest(a$analysis, a$beta, a$ci_low <- as.numeric(sub(" to.*", "", a$ci)),
       a$ci_high <- as.numeric(sub(".*to ", "", a$ci)),
       xlab = "Difference in cardiometabolic dysfunction score (SD) per SD higher hPDI",
       main = "Primary estimate and pre-specified sensitivity analyses",
       ref = a$beta[1], highlight = 1)
dev.off()
log_msg("F1 written", logfile = logfile)

# --- Figure 2: pre-specified substitutions --------------------------------
p <- sub$prespec
lab <- sprintf("%s → %s (%s)", p$from, p$to, p$unit)
png(file.path(fig_dir, "F2_substitution_forest.png"), width = 2100, height = 1200, res = PT)
forest(lab, p$estimate, p$ci_low, p$ci_high,
       xlab = "Difference in cardiometabolic dysfunction score (SD) per unit substituted",
       main = "Pre-specified isocaloric food-group substitutions",
       highlight = which(p$p_fdr < 0.05))
dev.off()
log_msg("F2 written", logfile = logfile)

# --- Figure 3: PCA loadings + scree ---------------------------------------
L <- pca$loadings; ret <- pca$retention
png(file.path(fig_dir, "F3_pca.png"), width = 2200, height = 1100, res = PT)
layout(matrix(1:2, 1, 2), widths = c(1.15, 1))
par(mar = c(4.5, 9, 3, 1))
cols <- colorRampPalette(c("white", "grey20"))(100)
image(x = seq_len(ncol(L)), y = seq_len(nrow(L)), z = t(abs(L))[, nrow(L):1],
      col = cols, axes = FALSE, xlab = "", ylab = "",
      main = "Rotated loadings (|value|)")
axis(1, at = seq_len(ncol(L)), labels = colnames(L), tick = FALSE)
axis(2, at = seq_len(nrow(L)), labels = rev(rownames(L)), las = 1,
     tick = FALSE, cex.axis = 0.8)
for (i in seq_len(nrow(L))) for (j in seq_len(ncol(L)))
  text(j, nrow(L) - i + 1, sprintf("%.2f", L[i, j]),
       col = ifelse(abs(L[i, j]) > 0.55, "white", "black"), cex = 0.8)
par(mar = c(4.5, 4.5, 3, 1))
plot(ret$component, ret$eigenvalue, type = "b", pch = 16,
     ylim = c(0, max(ret$eigenvalue) * 1.05),
     xlab = "Component", ylab = "Eigenvalue", main = "Scree with PA thresholds")
lines(ret$component, ret$pa_threshold_nominal_n, type = "b", pch = 1, lty = 2)
lines(ret$component, ret$pa_threshold_effective_n, type = "b", pch = 2, lty = 3)
legend("topright", bty = "n", cex = 0.8, pch = c(16, 1, 2), lty = c(1, 2, 3),
       legend = c("observed", "PA (nominal n)", "PA (effective n)"))
dev.off()
log_msg("F3 written", logfile = logfile)

# --- Figure 4: measurement-error calibration ------------------------------
cr <- read.csv(file.path(tab_dir, "10_calibration_results.csv"))
cr <- cr[cr$quantity != "lambda (reliability ratio)", ]
png(file.path(fig_dir, "F4_calibration.png"), width = 1900, height = 900, res = PT)
forest(c("Naive (single day-1 recall)", "Regression-calibrated"),
       cr$estimate, cr$ci_low, cr$ci_high,
       xlab = "Difference in cardiometabolic dysfunction score (SD) per SD higher hPDI",
       main = "Effect of correcting for within-person recall error",
       highlight = 2)
dev.off()
log_msg("F4 written", logfile = logfile)

# --- Figure 5: exposure distribution and day-1/day-2 agreement ------------
exp <- readRDS(file.path(int_dir, "exposure_pdi.rds"))
h <- merge(exp$pdi_day1[, c("SEQN", "hPDI")], exp$pdi_day2[, c("SEQN", "hPDI")],
           by = "SEQN", suffixes = c("_d1", "_d2"))
png(file.path(fig_dir, "F5_exposure_reliability.png"), width = 2000, height = 950, res = PT)
par(mfrow = c(1, 2), mar = c(4.5, 4.5, 3, 1))
hist(exp$pdi_day1$hPDI, breaks = 30, col = "grey80", border = "white",
     xlab = "hPDI (day 1)", main = "Distribution of hPDI")
plot(jitter(h$hPDI_d1), jitter(h$hPDI_d2), pch = 16, col = "#00000018",
     xlab = "hPDI, day 1", ylab = "hPDI, day 2",
     main = sprintf("Day-1 vs day-2 (r = %.2f)", cor(h$hPDI_d1, h$hPDI_d2)))
abline(0, 1, col = "grey40", lty = 2)
dev.off()
log_msg("F5 written", logfile = logfile)

log_msg("=== 18_figures.R complete ===", logfile = logfile)
cat("figures written:\n"); print(list.files(fig_dir, pattern = "\\.png$"))
