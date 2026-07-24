# ---------------------------------------------------------------------------
# theme_manuscript.R
# A single visual system for every manuscript figure.
#
# Typography: Liberation Sans (metric-compatible with Helvetica/Arial, which is
# what most nutrition journals specify).
# Palette: Okabe-Ito, chosen because it remains distinguishable under all three
# common forms of colour-vision deficiency. No figure encodes information by
# colour alone -- position, shape or text always carries it too.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(ggplot2); library(scales); library(patchwork)
})

BASE_FONT <- "Liberation Sans"

# Okabe-Ito
OI <- c(black = "#000000", orange = "#E69F00", skyblue = "#56B4E9",
        green  = "#009E73", yellow = "#F0E442", blue    = "#0072B2",
        vermillion = "#D55E00", purple = "#CC79A7")

ACCENT   <- unname(OI["blue"])
MUTED    <- "grey45"
NULLLINE <- "grey60"

theme_manuscript <- function(base_size = 9) {
  theme_minimal(base_size = base_size, base_family = BASE_FONT) +
    theme(
      panel.grid.minor   = element_blank(),
      panel.grid.major.y = element_blank(),
      panel.grid.major.x = element_line(colour = "grey92", linewidth = 0.3),
      axis.line.x        = element_line(colour = "grey25", linewidth = 0.4),
      axis.ticks.x       = element_line(colour = "grey25", linewidth = 0.4),
      axis.ticks.y       = element_blank(),
      axis.text          = element_text(colour = "grey15"),
      axis.title         = element_text(colour = "grey15", size = rel(1)),
      plot.title         = element_text(face = "bold", size = rel(1.15),
                                        margin = margin(b = 3)),
      plot.subtitle      = element_text(colour = "grey35", size = rel(0.95),
                                        margin = margin(b = 8)),
      plot.caption       = element_text(colour = "grey40", size = rel(0.8),
                                        hjust = 0, margin = margin(t = 8)),
      plot.title.position   = "plot",
      plot.caption.position = "plot",
      strip.text         = element_text(face = "bold", size = rel(0.9),
                                        colour = "grey20", hjust = 0),
      # facet_grid rows default to vertical strip text, which truncates against
      # the panel edge. Horizontal, left-aligned strips stay readable.
      strip.text.y       = element_text(face = "bold", size = rel(0.9),
                                        colour = "grey20", angle = 0, hjust = 0,
                                        margin = margin(l = 6)),
      strip.background   = element_blank(),
      legend.position    = "bottom",
      legend.title       = element_text(size = rel(0.9)),
      legend.key.height  = unit(0.8, "lines"),
      plot.margin        = margin(8, 10, 6, 8))
}

theme_heatmap <- function(base_size = 9) {
  theme_manuscript(base_size) +
    theme(panel.grid = element_blank(),
          axis.line.x = element_blank(), axis.ticks.x = element_blank())
}

# Journal column widths in inches (89 mm and 183 mm)
W_SINGLE <- 3.50
W_DOUBLE <- 7.20

#' Write a figure as both a high-resolution raster and a vector file.
#' ragg is used rather than grDevices::png because its text rendering and
#' anti-aliasing are markedly better; svglite gives the vector format journals
#' request at submission.
save_fig <- function(plot, name, width, height, dir = here::here("outputs", "figures")) {
  ragg::agg_png(file.path(dir, paste0(name, ".png")), width = width,
                height = height, units = "in", res = 600, background = "white")
  print(plot); invisible(grDevices::dev.off())
  svglite::svglite(file.path(dir, paste0(name, ".svg")), width = width,
                   height = height, bg = "white")
  print(plot); invisible(grDevices::dev.off())
  invisible(NULL)
}

#' Shared forest-plot builder. `df` needs: label, estimate, ci_low, ci_high,
#' and optionally `family` (facet) and `flag` (logical, drives emphasis).
forest_gg <- function(df, xlab, title, subtitle = NULL, caption = NULL,
                      facet = FALSE, ref = NULL) {
  df$label <- factor(df$label, levels = rev(df$label))
  if (is.null(df$flag)) df$flag <- FALSE
  p <- ggplot(df, aes(x = estimate, y = label))
  if (!is.null(ref))
    p <- p + geom_vline(xintercept = ref, colour = "grey80",
                        linetype = "dotted", linewidth = 0.4)
  p <- p +
    geom_vline(xintercept = 0, colour = NULLLINE, linetype = "dashed",
               linewidth = 0.4) +
    # geom_errorbarh() is deprecated from ggplot2 4.0; horizontal intervals are
    # now geom_errorbar() with orientation = "y".
    geom_errorbar(aes(xmin = ci_low, xmax = ci_high, colour = flag),
                  orientation = "y", width = 0, linewidth = 0.55) +
    geom_point(aes(colour = flag, shape = flag, size = flag)) +
    scale_colour_manual(values = c(`FALSE` = MUTED, `TRUE` = ACCENT),
                        guide = "none") +
    scale_shape_manual(values = c(`FALSE` = 16, `TRUE` = 18), guide = "none") +
    scale_size_manual(values = c(`FALSE` = 1.7, `TRUE` = 3.0), guide = "none") +
    labs(x = xlab, y = NULL, title = title, subtitle = subtitle,
         caption = caption) +
    theme_manuscript()
  if (facet) p <- p + facet_grid(family ~ ., scales = "free_y", space = "free_y")
  p
}
