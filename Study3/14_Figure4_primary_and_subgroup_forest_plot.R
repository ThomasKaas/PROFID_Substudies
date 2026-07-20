# STUDY 3 — FIGURE 4: PRIMARY AND SUBGROUP FOREST PLOT
#
# Recreates the manuscript figure from the prespecified model estimates reported
# by the Study 3 pipeline. The estimates are entered explicitly so the figure
# remains reproducible without loading patient-level data.

study3_paths_file <- file.path("Study3", "study3_paths.R")
if (!file.exists(study3_paths_file)) study3_paths_file <- "study3_paths.R"
if (!file.exists(study3_paths_file)) study3_paths_file <- file.path("..", "study3_paths.R")
source(study3_paths_file)

dir.create(study3_output_root(), recursive = TRUE, showWarnings = FALSE)
output_file <- file.path(
  study3_output_root(),
  "figure_4_primary_and_subgroup_forest_plot.svg"
)
pdf_file <- file.path(
  study3_output_root(),
  "figure_4_primary_and_subgroup_forest_plot.pdf"
)
png_file <- file.path(
  study3_output_root(),
  "figure_4_primary_and_subgroup_forest_plot.png"
)

primary_results <- data.frame(
  label = c(
    "Cox model, pooled",
    "Cox model, dataset-stratified",
    "Fine-Gray model, unadjusted",
    "Fine-Gray model, dataset-adjusted"
  ),
  estimate = c(0.67, 0.63, 0.70, 0.64),
  lower = c(0.42, 0.39, 0.43, 0.39),
  upper = c(1.09, 1.03, 1.12, 1.04),
  p_value = c(0.11, 0.06, 0.13, 0.07),
  stringsAsFactors = FALSE
)

# Match the publication typography used for the Kaplan-Meier curve (Figure 1).
forest_text_cex <- 1.14
forest_annotation_cex <- 0.88
forest_column_header_cex <- forest_annotation_cex
forest_ci_lwd <- 2.0
forest_reference_lwd <- 1.4

interaction_results <- data.frame(
  label = c(
    "Age >=65 vs <65 years",
    "LVEF <30% vs >=30%",
    "AF/AFL present vs absent"
  ),
  estimate = c(1.03, 1.95, 0.44),
  lower = c(0.39, 0.71, 0.12),
  upper = c(2.69, 5.34, 1.57),
  p_value = c(0.96, 0.20, 0.20),
  stringsAsFactors = FALSE
)

# Write the figure directly as SVG. This avoids dependence on the Cairo SVG
# device, which is unavailable in some minimal R installations.
{
  svg_escape <- function(x) {
    x <- gsub("&", "&amp;", x, fixed = TRUE)
    x <- gsub("<", "&lt;", x, fixed = TRUE)
    gsub(">", "&gt;", x, fixed = TRUE)
  }
  svg_text <- function(x, y, label, anchor = "start", size = 23, weight = "400",
                       colour = "#111111") {
    sprintf(
      '<text x="%.1f" y="%.1f" text-anchor="%s" font-size="%d" font-weight="%s" fill="%s">%s</text>',
      x, y, anchor, size, weight, colour, svg_escape(label)
    )
  }
  svg_line <- function(x1, y1, x2, y2, colour = "#111111", width = 2, dash = NULL) {
    dash_attr <- if (is.null(dash)) "" else sprintf(' stroke-dasharray="%s"', dash)
    sprintf(
      '<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="%.1f"%s/>',
      x1, y1, x2, y2, colour, width, dash_attr
    )
  }
  svg_circle <- function(x, y) {
    sprintf('<circle cx="%.1f" cy="%.1f" r="7" fill="#7a7a7a" stroke="#111111" stroke-width="1.5"/>', x, y)
  }
  svg_x <- function(x, limits) {
    390 + (log(x) - log(limits[1])) / diff(log(limits)) * 300
  }
  svg_panel <- function(results, letter, title, estimate_title, result_title,
                        limits, header_y, row_y, footnote) {
    ticks <- 2 ^ seq(floor(log2(limits[1])), ceiling(log2(limits[2])))
    ticks <- ticks[ticks >= limits[1] & ticks <= limits[2]]
    x_ticks <- svg_x(ticks, limits)
    grid_top <- header_y + 36
    grid_bottom <- max(row_y) + 20
    out <- c(
      svg_text(16, header_y, paste(letter, title), size = 25, weight = "600"),
      svg_text(540, header_y, estimate_title, anchor = "middle", size = 17, weight = "600"),
      svg_text(1084, header_y, result_title, anchor = "end", size = 17, weight = "600"),
      svg_line(16, header_y + 16, 1084, header_y + 16, colour = "#b8b8b8", width = 1.2),
      vapply(x_ticks, function(x) svg_line(x, grid_top, x, grid_bottom, colour = "#dedede", width = 1.2), character(1)),
      svg_line(svg_x(1, limits), grid_top - 10, svg_x(1, limits), grid_bottom,
               colour = "#666666", width = 1.6, dash = "5 4")
    )
    for (i in seq_len(nrow(results))) {
      x_lower <- svg_x(results$lower[i], limits)
      x_estimate <- svg_x(results$estimate[i], limits)
      x_upper <- svg_x(results$upper[i], limits)
      y <- row_y[i]
      out <- c(
        out,
        svg_text(16, y + 5, results$label[i]),
        svg_line(x_lower, y, x_upper, y, width = 2.5),
        svg_line(x_lower, y - 8, x_lower, y + 8, width = 2.5),
        svg_line(x_upper, y - 8, x_upper, y + 8, width = 2.5),
        svg_circle(x_estimate, y),
        svg_text(920, y + 5,
                 sprintf("%.2f (%.2f–%.2f); p = %.2f", results$estimate[i], results$lower[i],
                         results$upper[i], results$p_value[i]), anchor = "end", size = 23)
      )
    }
    tick_y <- grid_bottom + 24
    c(
      out,
      mapply(function(x, label) svg_text(x, tick_y, label, anchor = "middle", size = 23, colour = "#555555"),
             x_ticks, format(ticks, trim = TRUE), USE.NAMES = FALSE),
      svg_text(540, tick_y + 35,
               if (letter == "A") "Lower hazard with single-chamber ICD  ←   →  Lower hazard with dual-chamber ICD" else "No effect modification  ←   →  Greater device-type HR in the second subgroup level",
               anchor = "middle", size = 23, colour = "#555555"),
      svg_text(16, tick_y + 55, footnote, size = 17, colour = "#555555")
    )
  }
  svg_elements <- c(
    '<svg xmlns="http://www.w3.org/2000/svg" width="1100" height="640" viewBox="0 0 1100 640" role="img" aria-labelledby="title description">',
    '<title id="title">Primary and subgroup analyses of device type and first inappropriate shock</title>',
    '<desc id="description">Panel A shows four time-to-event model estimates. Panel B shows interaction ratios for age, left ventricular ejection fraction, and atrial fibrillation or flutter. All point estimates are drawn as grey circles.</desc>',
    '<rect width="1100" height="640" fill="white"/>',
    '<g font-family="Arial, Helvetica, sans-serif">',
    svg_panel(primary_results, "A", "Time-to-event analyses", "Single- vs dual-chamber ICD",
              "HR/sHR (95% CI); p value", c(0.25, 4), 28, c(86, 126, 166, 206), ""),
    svg_panel(interaction_results, "B", "Exploratory effect modification",
              "Ratio of device-type HR (second level / reference level)", "Ratio (95% CI); p interaction",
              c(0.125, 8), 350, c(408, 450, 492), "AF/AFL interaction model: N = 1,590; 47 events."),
    '</g>', '</svg>'
  )
  writeLines(svg_elements, output_file, useBytes = TRUE)
}

pdf_forest_x <- function(x, limits, left = 0.35, right = 0.66) {
  left + (log(x) - log(limits[1])) / diff(log(limits)) * (right - left)
}

draw_pdf_panel <- function(results, letter, title, estimate_title, result_title,
                           limits, footnote = NULL) {
  n_rows <- nrow(results)
  plot.new()
  plot.window(xlim = c(0, 1), ylim = c(0, n_rows + 2.3), xaxs = "i", yaxs = "i")
  heading_y <- n_rows + 1.95
  separator_y <- n_rows + 1.62
  row_y <- rev(seq_len(n_rows)) + 0.58
  axis_y <- 0.72

  text(0.015, heading_y, paste(letter, title), adj = c(0, 0.5), font = 2, cex = forest_text_cex)
  text(0.505, heading_y, estimate_title, adj = c(0.5, 0.5), font = 2, cex = forest_column_header_cex)
  text(0.90, heading_y, result_title, adj = c(1, 0.5), font = 2, cex = forest_column_header_cex)
  segments(0.015, separator_y, 0.90, separator_y, col = "grey70", lwd = 1.2)

  ticks <- 2 ^ seq(floor(log2(limits[1])), ceiling(log2(limits[2])))
  ticks <- ticks[ticks >= limits[1] & ticks <= limits[2]]
  tick_x <- pdf_forest_x(ticks, limits)
  segments(tick_x, axis_y + 0.2, tick_x, separator_y - 0.2, col = "grey88", lwd = 1.2)
  segments(pdf_forest_x(1, limits), axis_y + 0.2, pdf_forest_x(1, limits), separator_y - 0.2,
           col = "grey45", lty = 2, lwd = forest_reference_lwd)

  for (i in seq_len(n_rows)) {
    y <- row_y[i]
    x_lower <- pdf_forest_x(results$lower[i], limits)
    x_estimate <- pdf_forest_x(results$estimate[i], limits)
    x_upper <- pdf_forest_x(results$upper[i], limits)
    text(0.015, y, results$label[i], adj = c(0, 0.5), cex = forest_text_cex)
    segments(x_lower, y, x_upper, y, lwd = forest_ci_lwd)
    segments(x_lower, y - 0.12, x_lower, y + 0.12, lwd = forest_ci_lwd)
    segments(x_upper, y - 0.12, x_upper, y + 0.12, lwd = forest_ci_lwd)
    points(x_estimate, y, pch = 16, cex = 1.2, col = "grey45")
    text(0.90, y,
         sprintf("%.2f (%.2f-%.2f); p = %.2f", results$estimate[i], results$lower[i],
                 results$upper[i], results$p_value[i]),
         adj = c(1, 0.5), cex = forest_text_cex)
  }

  text(tick_x, axis_y, format(ticks, trim = TRUE), adj = c(0.5, 0.5), cex = forest_text_cex)
  text(0.505, 0.40,
       if (identical(letter, "A")) {
         "Lower hazard with single-chamber ICD  <-   ->  Lower hazard with dual-chamber ICD"
       } else {
         "No effect modification  <-   ->  Greater device-type HR in the second subgroup level"
       },
       adj = c(0.5, 0.5), cex = forest_text_cex, col = "grey35")
  if (!is.null(footnote)) {
    text(0.015, 0.60, footnote, adj = c(0, 0.5), cex = forest_annotation_cex, col = "grey35")
  }
}

draw_forest_plot <- function() {
  layout(matrix(c(1, 0, 2), ncol = 1), heights = c(1.05, 0.06, 0.95))
  par(mar = c(0, 0, 0, 0), oma = c(0, 0, 0, 0), xpd = NA)
  draw_pdf_panel(
    primary_results, "A", "Time-to-event analyses", "Single- vs dual-chamber ICD",
    "HR/sHR (95% CI); p value", c(0.25, 4)
  )
  draw_pdf_panel(
    interaction_results, "B", "Exploratory effect modification",
    "Ratio of device-type HR (second level / reference level)", "Ratio (95% CI); p interaction",
    c(0.125, 8), footnote = "AF/AFL interaction model: N = 1,590; 47 events."
  )
}

pdf(width = 11, height = 6.5, file = pdf_file, pointsize = 14)
draw_forest_plot()
dev.off()

png(filename = png_file, width = 3300, height = 1950, res = 300, pointsize = 14)
draw_forest_plot()
dev.off()

message("Wrote ", output_file, ", ", pdf_file, " and ", png_file)
