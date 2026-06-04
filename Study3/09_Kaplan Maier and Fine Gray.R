#
# install.packages("data.table")
# install.packages("cmprsk")
# install.packages("survival")
# install.packages("readxl")
# install.packages ("mice")

study3_paths_file <- file.path("Study3", "study3_paths.R")
if (!file.exists(study3_paths_file)) study3_paths_file <- "study3_paths.R"
if (!file.exists(study3_paths_file)) study3_paths_file <- file.path("..", "study3_paths.R")
source(study3_paths_file)

library(data.table)
library(cmprsk)
library(survival)
library(readxl)
library (mice)

dt_final <- as.data.table(readRDS(study3_derived_path("study3_analysis_final.rds")))
study3_add_inapp_shock_event(dt_final)

valid_survival_input <- !is.na(dt_final$t_followup_days_final) &
  is.finite(dt_final$t_followup_days_final) &
  dt_final$t_followup_days_final > 0 &
  !is.na(dt_final$device_group)

if (any(!valid_survival_input)) {
  cat(
    "Excluding ",
    sum(!valid_survival_input),
    " row(s) with missing/non-positive follow-up or missing device group before KM/Fine-Gray analyses.\n",
    sep = ""
  )
  print(
    dt_final[
      !valid_survival_input,
      .N,
      by = .(
        dataset,
        missing_followup = is.na(t_followup_days_final),
        nonpositive_followup = !is.na(t_followup_days_final) & t_followup_days_final <= 0,
        missing_device_group = is.na(device_group)
      )
    ][order(dataset)]
  )
  dt_final <- dt_final[valid_survival_input]
}

km_fit <- survfit(
  Surv(t_followup_days_final, event_inapp_shock) ~ device_group,
  data = dt_final
)

logrank_fit <- survdiff(
  Surv(t_followup_days_final, event_inapp_shock) ~ device_group,
  data = dt_final
)
logrank_fit

study3_format_p <- function(p) {
  if (is.na(p)) return("NA")
  if (p < 0.001) return("<0.001")
  sprintf("%.2f", p)
}

study3_km_risk_table <- function(fit, times, labels) {
  risk_summary <- summary(fit, times = times, extend = TRUE)

  risk_table <- matrix(
    NA_integer_,
    nrow = length(labels),
    ncol = length(times),
    dimnames = list(labels, as.character(times))
  )

  strata_labels <- sub("^device_group=", "", as.character(risk_summary$strata))
  if (length(strata_labels) == 0L && length(labels) == 1L) {
    strata_labels <- rep(labels, length(risk_summary$time))
  }

  for (i in seq_along(risk_summary$time)) {
    risk_table[
      strata_labels[[i]],
      as.character(risk_summary$time[[i]])
    ] <- risk_summary$n.risk[[i]]
  }

  risk_table
}

study3_km_risk_table_long <- function(fit, times, labels) {
  risk_table <- study3_km_risk_table(fit, times, labels)

  data.table(
    device_group = rep(rownames(risk_table), each = length(times)),
    time_days = rep(times, times = nrow(risk_table)),
    n_risk = as.integer(as.vector(t(risk_table)))
  )
}

study3_km_curve_data <- function(fit, labels, x_limit = 3000) {
  curve_summary <- summary(fit, censored = TRUE)
  initial_risk <- study3_km_risk_table(fit, 0, labels)

  initial_dt <- data.table(
    device_group = labels,
    time_days = 0,
    n_risk = as.integer(initial_risk[, "0"]),
    n_event = 0L,
    n_censor = 0L,
    survival = 1,
    std_error = 0,
    lower_95 = 1,
    upper_95 = 1
  )

  if (length(curve_summary$time) == 0L) {
    return(initial_dt)
  }

  strata_labels <- sub("^device_group=", "", as.character(curve_summary$strata))
  if (length(strata_labels) == 0L && length(labels) == 1L) {
    strata_labels <- rep(labels, length(curve_summary$time))
  }

  curve_dt <- data.table(
    device_group = strata_labels,
    time_days = curve_summary$time,
    n_risk = curve_summary$n.risk,
    n_event = curve_summary$n.event,
    n_censor = curve_summary$n.censor,
    survival = curve_summary$surv,
    std_error = curve_summary$std.err,
    lower_95 = curve_summary$lower,
    upper_95 = curve_summary$upper
  )

  curve_dt <- rbind(initial_dt, curve_dt, fill = TRUE)
  curve_dt[time_days <= x_limit][order(device_group, time_days)]
}

study3_figure1_label <- function(labels) {
  display_labels <- labels
  display_labels[grepl("single", labels, ignore.case = TRUE)] <- "Single Lead Device"
  display_labels[grepl("dual|double", labels, ignore.case = TRUE)] <- "Double Lead Device"
  display_labels
}

study3_figure1_year_axis <- function(x_limit) {
  years <- seq(0, floor(x_limit / 365.25), by = 1)
  list(
    days = round(years * 365.25),
    labels = as.character(years)
  )
}

study3_export_figure1_data <- function(fit, labels, x_limit = 2200) {
  x_axis <- study3_figure1_year_axis(x_limit)
  x_suffix <- paste0(round(x_limit), "d")
  out_dir <- study3_output_path()
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  curve_dt <- study3_km_curve_data(fit, labels, x_limit)
  risk_long <- study3_km_risk_table_long(fit, x_axis$days, labels)
  risk_long[, time_years := as.numeric(time_days) / 365.25]
  risk_wide <- dcast(risk_long, device_group ~ time_days, value.var = "n_risk")
  setnames(
    risk_wide,
    old = setdiff(names(risk_wide), "device_group"),
    new = paste0("day_", setdiff(names(risk_wide), "device_group"))
  )

  fwrite(
    curve_dt,
    study3_output_path(sprintf("figure_1_km_curve_data_%s.csv", x_suffix))
  )
  fwrite(
    risk_long,
    study3_output_path(sprintf("figure_1_km_number_at_risk_long_%s.csv", x_suffix))
  )
  fwrite(
    risk_wide,
    study3_output_path(sprintf("figure_1_km_number_at_risk_wide_%s.csv", x_suffix))
  )

  invisible(
    list(
      curve_data = curve_dt,
      number_at_risk_long = risk_long,
      number_at_risk_wide = risk_wide
    )
  )
}

study3_draw_km_with_risk_table <- function(fit, labels, x_limit = 2200,
                                           logrank_p = NA_real_) {
  x_axis <- study3_figure1_year_axis(x_limit)
  x_breaks <- x_axis$days
  risk_table <- study3_km_risk_table(fit, x_breaks, labels)
  display_labels <- study3_figure1_label(labels)
  n_groups <- length(labels)
  is_dual <- grepl("dual|double", labels, ignore.case = TRUE)
  curve_col <- ifelse(is_dual, "#C00000", "#003F9E")
  curve_lty <- ifelse(is_dual, 2, 1)
  legend_order <- c(which(!is_dual), which(is_dual))
  if (!length(legend_order)) legend_order <- seq_along(labels)
  left_margin <- 11.0
  risk_label_x <- -0.045 * x_limit
  main_axis_cex <- 1.08
  main_label_cex <- 1.08
  legend_cex <- 0.96
  risk_axis_cex <- 1.02
  risk_label_cex <- 0.93
  risk_group_cex <- 0.86
  risk_number_cex <- 1.03
  censor_tick_half_height <- 0.004
  censor_tick_lwd <- 0.45
  inset_x <- c(0.47, 0.97) * x_limit
  inset_y <- c(0.33, 0.76)
  inset_ylim <- c(0.8, 1.0)
  logrank_label <- paste0("Log-rank p = ", study3_format_p(logrank_p))

  old_par <- par(no.readonly = TRUE)
  on.exit(par(old_par), add = TRUE)

  layout(matrix(c(1, 2), nrow = 2), heights = c(3.3, 1.5))

  par(mar = c(0.5, left_margin, 4.0, 1.0), las = 1, bty = "l", xaxs = "i", yaxs = "i")
  plot(
    fit,
    col = curve_col,
    lty = curve_lty,
    lwd = 1.35,
    xlab = "",
	    ylab = "Event-free survival (inappropriate shock)",
	    xlim = c(0, x_limit),
	    ylim = c(0, 1.0),
	    xaxt = "n",
	    yaxt = "n",
	    mark.time = FALSE,
    conf.int = FALSE,
    cex.axis = main_axis_cex,
    cex.lab = main_label_cex
  )
  censor_summary <- summary(fit, censored = TRUE)
	  if (length(censor_summary$time)) {
    censor_strata <- sub("^device_group=", "", as.character(censor_summary$strata))
    if (length(censor_strata) == 0L && length(labels) == 1L) {
      censor_strata <- rep(labels, length(censor_summary$time))
    }

    for (i in seq_along(labels)) {
      tick_idx <- which(
        censor_strata == labels[[i]] &
          censor_summary$n.censor > 0 &
          censor_summary$time >= 0 &
          censor_summary$time <= x_limit &
          !is.na(censor_summary$surv)
      )

      if (length(tick_idx)) {
	        segments(
	          x0 = censor_summary$time[tick_idx],
	          y0 = pmax(0, censor_summary$surv[tick_idx] - censor_tick_half_height),
	          x1 = censor_summary$time[tick_idx],
	          y1 = pmin(1.0, censor_summary$surv[tick_idx] + censor_tick_half_height),
	          col = curve_col[[i]],
          lwd = censor_tick_lwd,
          lend = "butt"
        )
	      }
	    }
	  }
	  axis(2, at = seq(0, 1.0, by = 0.2), las = 1, cex.axis = main_axis_cex)
	  axis(1, at = x_breaks, labels = FALSE, tck = -0.015)
	  title(
    main = "Figure 1. Kaplan-Meier Estimates of Time to First Inappropriate ICD Shock by Device Type",
    line = 2.5,
    cex.main = 1.05,
    font.main = 2
  )
	  mtext(
	    sprintf("Follow-up truncated at %s days (%.1f years)", format(x_limit, big.mark = ","), x_limit / 365.25),
	    side = 3,
	    line = 1.0,
    cex = 0.95,
    font = 3,
    col = "#1E3557"
  )
	  legend(
	    x = 70,
	    y = 0.24,
	    legend = display_labels[legend_order],
	    col = curve_col[legend_order],
	    lty = curve_lty[legend_order],
    lwd = 2,
    bty = "n",
    cex = legend_cex
  )
	  text(
	    x = 0.53 * x_limit,
	    y = 0.08,
	    labels = paste(logrank_label, "(Descriptive comparison only)", sep = "\n"),
	    adj = c(0, 0),
	    cex = 0.83
	  )

  curve_dt <- study3_km_curve_data(fit, labels, x_limit)
  to_inset_x <- function(x) inset_x[[1]] + (x / x_limit) * diff(inset_x)
  to_inset_y <- function(y) {
    inset_y[[1]] + ((y - inset_ylim[[1]]) / diff(inset_ylim)) * diff(inset_y)
  }

  rect(inset_x[[1]], inset_y[[1]], inset_x[[2]], inset_y[[2]], col = "white", border = NA)
  clip(inset_x[[1]], inset_x[[2]], inset_y[[1]], inset_y[[2]])
  for (i in seq_along(labels)) {
    group_curve <- curve_dt[device_group == labels[[i]]][order(time_days)]
    if (nrow(group_curve)) {
      lines(
        to_inset_x(group_curve$time_days),
        to_inset_y(group_curve$survival),
        type = "s",
        col = curve_col[[i]],
        lty = curve_lty[[i]],
        lwd = 1.35
      )
    }

    if (length(censor_summary$time)) {
      tick_idx <- which(
        censor_strata == labels[[i]] &
          censor_summary$n.censor > 0 &
          censor_summary$time >= 0 &
          censor_summary$time <= x_limit &
          !is.na(censor_summary$surv)
      )

      if (length(tick_idx)) {
        segments(
          x0 = to_inset_x(censor_summary$time[tick_idx]),
          y0 = to_inset_y(censor_summary$surv[tick_idx] - censor_tick_half_height),
          x1 = to_inset_x(censor_summary$time[tick_idx]),
          y1 = to_inset_y(censor_summary$surv[tick_idx] + censor_tick_half_height),
          col = curve_col[[i]],
          lwd = censor_tick_lwd,
          lend = "butt"
        )
      }
    }
  }
  clip(par("usr")[[1]], par("usr")[[2]], par("usr")[[3]], par("usr")[[4]])
  rect(inset_x[[1]], inset_y[[1]], inset_x[[2]], inset_y[[2]], border = "grey25", lwd = 0.8)
  axis_x_ticks <- round(seq(0, floor(x_limit / 365.25), by = 2) * 365.25)
  axis_x_labels <- as.character(seq(0, floor(x_limit / 365.25), by = 2))
  axis_y_ticks <- seq(0.8, 1.0, by = 0.1)
  segments(to_inset_x(axis_x_ticks), inset_y[[1]], to_inset_x(axis_x_ticks), inset_y[[1]] - 0.015)
  text(to_inset_x(axis_x_ticks), inset_y[[1]] - 0.045, axis_x_labels, cex = 0.67, xpd = NA)
  segments(inset_x[[1]], to_inset_y(axis_y_ticks), inset_x[[1]] - 0.018 * x_limit, to_inset_y(axis_y_ticks))
  text(inset_x[[1]] - 0.028 * x_limit, to_inset_y(axis_y_ticks), sprintf("%.1f", axis_y_ticks), cex = 0.67, adj = 1, xpd = NA)
  text(inset_x[[1]], inset_y[[2]] + 0.035, "Zoom: 0.8-1.0", adj = c(0, 0), cex = 0.72, font = 2, xpd = NA)

	  par(mar = c(3.2, left_margin, 0.2, 1.0), las = 1, bty = "n", xaxs = "i", yaxs = "i")
	  plot(
    NA,
    xlim = c(0, x_limit),
    ylim = c(0, n_groups + 1.45),
    axes = FALSE,
    xlab = "",
	    ylab = ""
	  )
	  axis(1, at = x_breaks, labels = x_axis$labels, tck = -0.06, line = 0, cex.axis = risk_axis_cex)
	  mtext("Years since ICD implantation", side = 1, line = 2.0, cex = 1.05)

  row_y <- rev(seq_len(n_groups)) * 0.78 + 0.35
  par(xpd = NA)
  text(
    risk_label_x,
    max(row_y) + 0.90,
    "Number\nat risk",
    adj = 1,
    font = 1,
    cex = risk_label_cex,
    col = "grey30"
  )
	  text(
	    risk_label_x,
	    row_y,
	    display_labels,
	    adj = 1,
	    cex = risk_group_cex,
    col = curve_col
  )

  for (j in seq_along(x_breaks)) {
    text(x_breaks[[j]], row_y, risk_table[, j], cex = risk_number_cex)
  }
  par(xpd = FALSE)
}

km_labels <- sub("^device_group=", "", names(km_fit$strata))
if (!length(km_labels)) km_labels <- levels(factor(dt_final$device_group))
km_logrank_p <- pchisq(
  logrank_fit$chisq,
  df = length(logrank_fit$n) - 1,
  lower.tail = FALSE
)

study3_export_figure1_data(
  fit = km_fit,
  labels = km_labels,
  x_limit = 2200
)

study3_save_grid(
  draw = function() {
	    study3_draw_km_with_risk_table(
	      fit = km_fit,
	      labels = km_labels,
	      x_limit = 2200,
	      logrank_p = km_logrank_p
	    )
	  },
  png_file = study3_output_path("figure_1_km_inapp_shock_by_device_2200d_risk_table.png"),
  pdf_file = study3_output_path("figure_1_km_inapp_shock_by_device_2200d_risk_table.pdf"),
  png_width = 3000,
  png_height = 2100,
  png_res = 300,
  pdf_width = 10.0,
  pdf_height = 7.0
)


study3_draw_km_with_risk_table(
  fit = km_fit,
  labels = km_labels,
  x_limit = 2200,
  logrank_p = km_logrank_p
)



##### quality check 

table(
  dt_final$device_group,
  is.na(dt_final$inapp_shock_flag)
)
summary(dt_final[event_inapp_shock == 1, t_followup_days_final])

names(dt_final)


# Fine–Gray event variable
# 0 = censored
# 1 = inappropriate shock 
# 2 = death before inapproiate shock - competing
dt_final[, fg_event := 0L]
dt_final[event_inapp_shock == 1, fg_event := 1L]
dt_final[event_inapp_shock == 0 & death_flag == "Yes", fg_event := 2L]

# QC  
cat("N =", nrow(dt_final), "\n")
print(table(dt_final$fg_event)) 

stopifnot(all(!is.na(dt_final$t_followup_days_final)))
stopifnot(all(dt_final$t_followup_days_final > 0))
stopifnot(all(dt_final$fg_event %in% c(0L, 1L, 2L)))

# Fine–Gray: sHR for Single vs Dual (Dual reference)
X <- model.matrix(~ device_group, data = dt_final)[, -1, drop = FALSE]

fg_fit <- crr(
  ftime   = dt_final$t_followup_days_final,
  fstatus = dt_final$fg_event,
  cov1    = X
)

fg_sum <- summary(fg_fit)
print(fg_sum)

# Extract subdistribution HR (sHR), 95% CI, and p-value
beta <- fg_fit$coef[1]
se   <- sqrt(fg_fit$var[1, 1])

sHR  <- exp(beta)
lci  <- exp(beta - 1.96 * se)
uci  <- exp(beta + 1.96 * se)
pval <- 2 * pnorm(-abs(beta / se))

cat(
  "\nFine–Gray (Single vs Dual): ",
  "sHR = ", round(sHR, 2),
  ", 95% CI [", round(lci, 2), ", ", round(uci, 2), "]",
  ", p = ", signif(pval, 3),
  "\n", sep = ""
)

study3_extract_crr_device_result <- function(fit, term, model, dataset_handling,
                                             data, analysis) {
  term_idx <- match(term, names(fit$coef))
  if (is.na(term_idx)) {
    stop(
      sprintf(
        "Term '%s' not found in Fine-Gray model coefficients: %s",
        term,
        paste(names(fit$coef), collapse = ", ")
      ),
      call. = FALSE
    )
  }

  beta <- unname(fit$coef[term_idx])
  se <- sqrt(fit$var[term_idx, term_idx])

  data.table(
    analysis = analysis,
    model = model,
    term = term,
    dataset_handling = dataset_handling,
    n = nrow(data),
    inappropriate_shocks = sum(data$fg_event == 1L, na.rm = TRUE),
    competing_deaths = sum(data$fg_event == 2L, na.rm = TRUE),
    censored = sum(data$fg_event == 0L, na.rm = TRUE),
    log_sHR = beta,
    se = se,
    sHR = exp(beta),
    lci_95 = exp(beta - 1.96 * se),
    uci_95 = exp(beta + 1.96 * se),
    p_value = 2 * pnorm(-abs(beta / se)),
    datasets_included = paste(sort(unique(as.character(data$dataset))), collapse = ";")
  )
}

X_dataset <- model.matrix(~ device_group + dataset, data = dt_final)[, -1, drop = FALSE]

fg_fit_dataset <- crr(
  ftime    = dt_final$t_followup_days_final,
  fstatus  = dt_final$fg_event,
  cov1     = X_dataset,
  cengroup = dt_final$dataset
)

cat("\n--- Fine–Gray dataset-adjusted (dataset fixed covariates + cengroup) ---\n")
print(summary(fg_fit_dataset))

fg_primary_results <- rbindlist(
  list(
    study3_extract_crr_device_result(
      fit = fg_fit,
      term = "device_groupSingle",
      model = "original_crr_device_only",
      dataset_handling = "none",
      data = dt_final,
      analysis = "primary"
    ),
    study3_extract_crr_device_result(
      fit = fg_fit_dataset,
      term = "device_groupSingle",
      model = "dataset_adjusted_crr",
      dataset_handling = "dataset fixed covariates + dataset-specific censoring via cengroup",
      data = dt_final,
      analysis = "primary"
    )
  )
)

fwrite(
  fg_primary_results,
  study3_output_path("finegray_primary_device_results.csv")
)

cif <- with(
  dt_final,
  cuminc(
    t_followup_days_final,
    fg_event,
    group = device_group
  )
)

cif_inapp <- cif[grep(" 1$", names(cif))]

study3_cif_curve_data <- function(cif_object, x_limit = 3000) {
  curve_names <- names(cif_object)
  device_group <- sub(" 1$", "", curve_names)
  keep <- device_group %in% c("Dual", "Single")

  cif_object <- cif_object[keep]
  device_group <- device_group[keep]

  device_order <- c("Dual", "Single")
  missing_devices <- setdiff(device_order, device_group)
  if (length(missing_devices)) {
    stop(
      sprintf(
        "Cannot draw Figure 2; missing CIF curve(s) for: %s",
        paste(missing_devices, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  cif_object <- cif_object[match(device_order, device_group)]

  rbindlist(
    lapply(seq_along(cif_object), function(i) {
      curve <- cif_object[[i]]
      time_days <- c(0, curve$time)
      estimate <- c(0, curve$est)
      keep_time <- time_days <= x_limit

      time_days <- time_days[keep_time]
      estimate <- estimate[keep_time]

      if (!length(time_days) || tail(time_days, 1) < x_limit) {
        time_days <- c(time_days, x_limit)
        estimate <- c(estimate, tail(estimate, 1))
      }

      data.table(
        device_group = device_order[[i]],
        time_days = time_days,
        estimate = estimate
      )
    }),
    use.names = TRUE
  )
}

study3_draw_cif_figure2 <- function(cif_object, x_limit = 3000) {
  cif_dt <- study3_cif_curve_data(cif_object, x_limit = x_limit)
  device_labels <- c(
    Dual = "Dual-chamber ICD",
    Single = "Single-chamber ICD"
  )
  curve_col <- c(
    Dual = "#003F9E",
    Single = "#C00000"
  )
  curve_lty <- c(
    Dual = 1,
    Single = 2
  )
  x_breaks <- seq(0, x_limit, by = 500)
  y_breaks <- seq(0, 1, by = 0.1)

  old_par <- par(no.readonly = TRUE)
  on.exit(par(old_par), add = TRUE)

  par(mar = c(5.0, 6.2, 1.0, 1.0), las = 1, bty = "l", xaxs = "i", yaxs = "i")
  plot(
    NA,
    xlim = c(0, x_limit),
    ylim = c(0, 1),
    axes = FALSE,
    xlab = "Days since ICD implantation",
    ylab = "Cumulative incidence of\ninappropriate ICD shock",
    cex.lab = 1.18
  )
  axis(1, at = x_breaks, cex.axis = 1.05)
  axis(2, at = y_breaks, labels = sprintf("%.1f", y_breaks), cex.axis = 1.05)

  for (device in c("Dual", "Single")) {
    d <- cif_dt[device_group == device]
    lines(
      d$time_days,
      d$estimate,
      type = "s",
      col = curve_col[[device]],
      lty = curve_lty[[device]],
      lwd = 2
    )
  }

  legend(
    "topleft",
    legend = unname(device_labels[c("Dual", "Single")]),
    col = curve_col[c("Dual", "Single")],
    lty = curve_lty[c("Dual", "Single")],
    lwd = 2,
    bty = "n",
    cex = 1.12,
    inset = c(0.03, 0.04)
  )
}

study3_save_grid(
  draw = function() {
    study3_draw_cif_figure2(
      cif_object = cif_inapp,
      x_limit = 3000
    )
  },
  png_file = study3_output_path("figure_cif_inapp_shock_by_device.png"),
  pdf_file = study3_output_path("figure_cif_inapp_shock_by_device.pdf"),
  png_width = 3000,
  png_height = 1500,
  png_res = 300,
  pdf_width = 10.0,
  pdf_height = 5.0
)

study3_draw_cif_figure2(
  cif_object = cif_inapp,
  x_limit = 3000
)
