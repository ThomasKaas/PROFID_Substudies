# STUDY 3 — FIGURE 3: ROBUSTNESS FOREST PLOT

study3_paths_file <- file.path("Study3", "study3_paths.R")
if (!file.exists(study3_paths_file)) study3_paths_file <- "study3_paths.R"
if (!file.exists(study3_paths_file)) study3_paths_file <- file.path("..", "study3_paths.R")
source(study3_paths_file)

library(data.table)
library(survival)
library(cmprsk)
library(ggplot2)

dir.create(study3_output_root(), recursive = TRUE, showWarnings = FALSE)

analysis_file <- study3_derived_path("study3_analysis_final.rds")
if (!file.exists(analysis_file)) {
  stop(sprintf("Figure 3 input not found: %s", analysis_file), call. = FALSE)
}

dt <- as.data.table(readRDS(analysis_file))
study3_add_inapp_shock_event(dt)

required <- c(
  "dataset", "device_group", "inapp_shock_flag", "death_flag",
  "t_followup_days_final", "t_inapp_shock_or_censor_days",
  "event_inapp_shock"
)
missing_required <- setdiff(required, names(dt))
if (length(missing_required)) {
  stop(
    sprintf("Figure 3 input is missing: %s", paste(missing_required, collapse = ", ")),
    call. = FALSE
  )
}

dt[, device_group := factor(as.character(device_group), levels = c("Dual", "Single"))]
dt[, dataset := factor(as.character(dataset))]

primary_datasets <- c("EUCERT", "HELIOS", "ISRAEL", "PROSE")
dt_primary <- dt[
  as.character(dataset) %in% primary_datasets &
    !is.na(device_group) &
    !is.na(t_inapp_shock_or_censor_days) &
    is.finite(t_inapp_shock_or_censor_days) &
    t_inapp_shock_or_censor_days > 0
]
dt_primary[, dataset := droplevels(dataset)]

if (nrow(dt_primary) == 0L || length(unique(dt_primary$device_group)) < 2L) {
  stop("Figure 3 requires non-empty data from both device groups.", call. = FALSE)
}

make_result <- function(block, analysis, model, effect_measure, estimate, lci_95,
                        uci_95, p_value, n, events, datasets_included,
                        display_order) {
  data.table(
    block = block,
    analysis = analysis,
    model = model,
    effect_measure = effect_measure,
    estimate = unname(estimate),
    lci_95 = unname(lci_95),
    uci_95 = unname(uci_95),
    p_value = unname(p_value),
    n = as.integer(n),
    inappropriate_shocks = as.integer(events),
    datasets_included = datasets_included,
    display_order = as.integer(display_order)
  )
}

extract_cox <- function(fit, block, analysis, model, data, display_order) {
  term <- "device_groupSingle"
  model_summary <- summary(fit)
  if (!term %in% rownames(model_summary$coefficients)) {
    stop(sprintf("Term '%s' not found for '%s'.", term, analysis), call. = FALSE)
  }

  make_result(
    block = block,
    analysis = analysis,
    model = model,
    effect_measure = "HR",
    estimate = model_summary$conf.int[term, "exp(coef)"],
    lci_95 = model_summary$conf.int[term, "lower .95"],
    uci_95 = model_summary$conf.int[term, "upper .95"],
    p_value = model_summary$coefficients[term, "Pr(>|z|)"],
    n = model_summary$n,
    events = model_summary$nevent,
    datasets_included = paste(sort(unique(as.character(data$dataset))), collapse = ";"),
    display_order = display_order
  )
}

add_fine_gray_event <- function(data) {
  data <- copy(data)
  data[, fg_event := 0L]
  data[event_inapp_shock == 1L, fg_event := 1L]
  data[
    event_inapp_shock == 0L &
      tolower(trimws(as.character(death_flag))) == "yes",
    fg_event := 2L
  ]
  data
}

fit_fine_gray <- function(data, block, analysis, display_order) {
  data <- add_fine_gray_event(data)
  design <- model.matrix(~ device_group + dataset, data = data)[, -1, drop = FALSE]
  fit <- crr(
    ftime = data$t_inapp_shock_or_censor_days,
    fstatus = data$fg_event,
    cov1 = design,
    cengroup = data$dataset
  )

  term <- "device_groupSingle"
  term_index <- match(term, names(fit$coef))
  if (is.na(term_index)) {
    stop(sprintf("Term '%s' not found for '%s'.", term, analysis), call. = FALSE)
  }

  beta <- unname(fit$coef[term_index])
  se <- sqrt(fit$var[term_index, term_index])
  make_result(
    block = block,
    analysis = analysis,
    model = paste(
      "Fine-Gray; death competing event; dataset fixed effects;",
      "dataset-specific censoring"
    ),
    effect_measure = "sHR",
    estimate = exp(beta),
    lci_95 = exp(beta - 1.96 * se),
    uci_95 = exp(beta + 1.96 * se),
    p_value = 2 * pnorm(-abs(beta / se)),
    n = nrow(data),
    events = sum(data$fg_event == 1L),
    datasets_included = paste(sort(unique(as.character(data$dataset))), collapse = ";"),
    display_order = display_order
  )
}

results <- list()

cox_primary <- coxph(
  Surv(t_inapp_shock_or_censor_days, event_inapp_shock) ~
    device_group + strata(dataset),
  data = dt_primary
)
results[[length(results) + 1L]] <- extract_cox(
  cox_primary, "Primary analysis", "Primary Cox model, stratified by dataset",
  "Cause-specific Cox model; dataset-stratified", dt_primary, 1L
)

cox_pooled <- coxph(
  Surv(t_inapp_shock_or_censor_days, event_inapp_shock) ~ device_group,
  data = dt_primary
)
results[[length(results) + 1L]] <- extract_cox(
  cox_pooled, "Primary analysis", "Pooled Cox model, unstratified",
  "Cause-specific Cox model; pooled", dt_primary, 2L
)

results[[length(results) + 1L]] <- fit_fine_gray(
  dt_primary, "Competing-risk analyses",
  "Fine-Gray model, death as competing event", 3L
)

dt_180d <- dt_primary[t_followup_days_final >= 180]
dt_180d[, dataset := droplevels(dataset)]
results[[length(results) + 1L]] <- fit_fine_gray(
  dt_180d, "Competing-risk analyses",
  "Fine-Gray model, >=6 months follow-up", 4L
)

loo_order <- 5L
for (excluded_dataset in sort(unique(as.character(dt_primary$dataset)))) {
  loo_data <- dt_primary[as.character(dataset) != excluded_dataset]
  loo_data[, dataset := droplevels(dataset)]
  loo_fit <- coxph(
    Surv(t_inapp_shock_or_censor_days, event_inapp_shock) ~
      device_group + strata(dataset),
    data = loo_data
  )
  results[[length(results) + 1L]] <- extract_cox(
    loo_fit,
    "Sensitivity analyses",
    paste0("  Excluding ", excluded_dataset),
    "Leave-one-dataset-out cause-specific Cox model; dataset-stratified",
    loo_data,
    loo_order
  )
  loo_order <- loo_order + 1L
}

figure_data <- rbindlist(results, use.names = TRUE, fill = TRUE)
setorder(figure_data, display_order)
figure_data[, comparison := "Single-chamber versus dual-chamber ICD"]
figure_data[, reference_group := "Dual-chamber ICD"]

if (any(!is.finite(figure_data$estimate)) ||
    any(!is.finite(figure_data$lci_95)) ||
    any(!is.finite(figure_data$uci_95)) ||
    any(figure_data$lci_95 <= 0)) {
  stop("Figure 3 contains invalid effect estimates or confidence intervals.", call. = FALSE)
}

csv_file <- study3_output_path("figure_3_forest_plot_results.csv")
fwrite(figure_data, csv_file)

format_p <- function(x) {
  ifelse(x < 0.001, "<0.001", sprintf("%.3f", x))
}

figure_data[, value_label := sprintf(
  "%s %.2f (%.2f-%.2f); p=%s",
  effect_measure, estimate, lci_95, uci_95, format_p(p_value)
)]

# Compact labels and row positions target a two-column journal figure.
figure_data[, display_label := c(
  "Primary Cox (dataset-stratified)",
  "Pooled Cox (unstratified)",
  "Fine-Gray (death competing event)",
  "Fine-Gray (>=6-month follow-up)",
  "Excluding EUCERT",
  "Excluding HELIOS",
  "Excluding ISRAEL",
  "Excluding PROSE"
)]
figure_data[, y := c(
  9.50, 8.85,
  7.25, 6.60,
  5.00, 4.35, 3.70, 3.05
)]
block_headers <- data.table(
  label = c(
    "Primary analysis",
    "Competing-risk analyses",
    "Sensitivity analyses: leave-one-dataset-out"
  ),
  y = c(10.20, 7.95, 5.70)
)

forest_blue <- "#1F5A85"
ink <- "#20262E"
muted_ink <- "#5E6872"
quiet_grid <- "#D9DEE3"
header_fill <- "#F1F3F5"

forest_plot <- ggplot(figure_data, aes(y = y)) +
  geom_rect(
    data = block_headers,
    aes(xmin = 0.11, xmax = 5.0, ymin = y - 0.28, ymax = y + 0.28),
    inherit.aes = FALSE, fill = header_fill, colour = NA
  ) +
  geom_vline(xintercept = c(0.31, 2.15), colour = quiet_grid, linewidth = 0.35) +
  geom_vline(xintercept = 1, colour = "#4F5963", linewidth = 0.48) +
  geom_segment(
    aes(x = lci_95, xend = uci_95, yend = y),
    colour = forest_blue, linewidth = 0.62
  ) +
  geom_point(
    data = figure_data[effect_measure == "HR"],
    aes(x = estimate), shape = 16, size = 2.15, colour = forest_blue
  ) +
  geom_point(
    data = figure_data[effect_measure == "sHR"],
    aes(x = estimate), shape = 23, size = 2.55,
    colour = forest_blue, fill = "white", stroke = 0.8
  ) +
  geom_text(
    aes(x = 0.115, label = display_label),
    hjust = 0, colour = ink, size = 2.45
  ) +
  geom_text(
    aes(x = 2.30, label = value_label),
    hjust = 0, colour = ink, size = 2.25
  ) +
  geom_text(
    data = block_headers,
    aes(x = 0.115, y = y, label = label),
    inherit.aes = FALSE, hjust = 0, fontface = "bold", colour = ink, size = 2.65
  ) +
  annotate(
    "text", x = 0.115, y = 10.95, label = "Analysis",
    hjust = 0, fontface = "bold", colour = ink, size = 2.50
  ) +
  annotate(
    "text", x = 0.75, y = 10.95, label = "HR / sHR (95% CI)",
    hjust = 0.5, fontface = "bold", colour = ink, size = 2.50
  ) +
  annotate(
    "text", x = 2.30, y = 10.95,
    label = "Estimate (95% CI); p value",
    hjust = 0, fontface = "bold", colour = ink, size = 2.50
  ) +
  scale_x_log10(
    limits = c(0.11, 5.0),
    breaks = c(0.25, 0.5, 1, 2),
    labels = c("0.25", "0.5", "1", "2"),
    expand = expansion(mult = c(0, 0))
  ) +
  scale_y_continuous(limits = c(2.60, 11.30), expand = expansion(mult = c(0, 0))) +
  labs(
    title = "Association between device type and first inappropriate ICD shock",
    subtitle = "Single-chamber versus dual-chamber ICD (reference: dual-chamber)",
    x = "Effect estimate (log scale)",
    y = NULL,
    caption = paste(
      "HR, hazard ratio; sHR, subdistribution hazard ratio.",
      "Values <1 favor single-chamber ICD; two-sided Wald p values."
    )
  ) +
  coord_cartesian(clip = "off") +
  theme_minimal(base_size = 8) +
  theme(
    plot.background = element_rect(fill = "white", colour = NA),
    panel.background = element_rect(fill = "white", colour = NA),
    panel.grid.major.y = element_blank(),
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_line(colour = "#E7EAED", linewidth = 0.28),
    axis.text.y = element_blank(),
    axis.ticks.y = element_blank(),
    axis.title.x = element_text(colour = ink, size = 7.5, margin = margin(t = 5)),
    axis.text.x = element_text(colour = muted_ink, size = 7),
    plot.title = element_text(face = "bold", colour = ink, size = 10.5, margin = margin(b = 2)),
    plot.subtitle = element_text(colour = muted_ink, size = 8, margin = margin(b = 5)),
    plot.caption = element_text(colour = muted_ink, size = 6.6, hjust = 0, margin = margin(t = 5)),
    plot.margin = margin(t = 8, r = 10, b = 7, l = 9)
  )

png_file <- study3_output_path("figure_3_forest_primary_competing_risk_sensitivity.png")
pdf_file <- study3_output_path("figure_3_forest_primary_competing_risk_sensitivity.pdf")
temporary_png <- tempfile("figure3_", tmpdir = study3_output_root(), fileext = ".png")
temporary_pdf <- tempfile("figure3_", tmpdir = study3_output_root(), fileext = ".pdf")
study3_save_plot(
  plot = forest_plot,
  png_file = temporary_png,
  pdf_file = temporary_pdf,
  width = 7.2,
  height = 4.5,
  dpi = 300
)

# Poppler provides a reliable PNG fallback on systems where R's cairo/X11
# stack is unavailable. On HPC systems with a working cairo/ragg device, the
# directly rendered PNG remains the fallback if pdftoppm is not installed.
pdftoppm <- Sys.which("pdftoppm")
if (nzchar(pdftoppm) && study3_file_ready(temporary_pdf)) {
  poppler_prefix <- tempfile("figure3_poppler_", tmpdir = study3_output_root())
  poppler_png <- paste0(poppler_prefix, ".png")
  poppler_log <- suppressWarnings(system2(
    pdftoppm,
    args = c(
      "-singlefile", "-png", "-r", "300",
      shQuote(temporary_pdf), shQuote(poppler_prefix)
    ),
    stdout = TRUE,
    stderr = TRUE
  ))
  if (study3_file_ready(poppler_png)) {
    file.copy(poppler_png, temporary_png, overwrite = TRUE)
  } else if (length(poppler_log)) {
    warning(
      paste("pdftoppm could not create the Figure 3 PNG:", paste(poppler_log, collapse = " ")),
      call. = FALSE
    )
  }
  unlink(poppler_png)
}

if (!study3_file_ready(temporary_png) || !study3_file_ready(temporary_pdf)) {
  unlink(c(temporary_png, temporary_pdf))
  stop("Figure 3 rendering did not produce both PNG and PDF outputs.", call. = FALSE)
}
png_copied <- file.copy(temporary_png, png_file, overwrite = TRUE)
pdf_copied <- file.copy(temporary_pdf, pdf_file, overwrite = TRUE)
unlink(c(temporary_png, temporary_pdf))
if (!png_copied || !pdf_copied) {
  stop("Figure 3 temporary outputs could not be moved into the output directory.", call. = FALSE)
}

cat("\n--- Figure 3 results (Single vs Dual; Dual reference) ---\n")
print(figure_data[, .(
  block, analysis, effect_measure, estimate, lci_95, uci_95,
  p_value, n, inappropriate_shocks
)])
cat("\nFigure 3 data: ", csv_file, "\n", sep = "")
if (study3_file_ready(png_file)) cat("Figure 3 PNG:  ", png_file, "\n", sep = "")
if (study3_file_ready(pdf_file)) cat("Figure 3 PDF:  ", pdf_file, "\n", sep = "")
