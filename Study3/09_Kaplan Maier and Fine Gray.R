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

if (study3_debugging_enabled()) {
  study3_debug_section("KM/Fine-Gray survival-readiness before filtering")
  print(dt_final[, .(
    n = .N,
    missing_device_group = sum(is.na(device_group)),
    missing_followup = sum(is.na(t_followup_days_final)),
    nonpositive_followup = sum(!is.na(t_followup_days_final) & t_followup_days_final <= 0),
    inappropriate_shocks = sum(event_inapp_shock == 1L, na.rm = TRUE),
    shocks_missing_followup = sum(event_inapp_shock == 1L & is.na(t_followup_days_final), na.rm = TRUE),
    deaths_case_insensitive = sum(tolower(as.character(death_flag)) == "yes", na.rm = TRUE),
    deaths_exact_Yes = sum(as.character(death_flag) == "Yes", na.rm = TRUE)
  ), by = dataset][order(dataset)])
}

valid_survival_input <- !is.na(dt_final$t_inapp_shock_or_censor_days) &
  is.finite(dt_final$t_inapp_shock_or_censor_days) &
  !is.na(dt_final$t_followup_days_final) &
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
  Surv(t_inapp_shock_or_censor_days, event_inapp_shock) ~ device_group,
  data = dt_final
)

logrank_fit <- survdiff(
  Surv(t_inapp_shock_or_censor_days, event_inapp_shock) ~ device_group,
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

study3_km_ci_intervals <- function(curve_data, x_limit) {
  if (!nrow(curve_data)) {
    return(data.table(
      x_left = numeric(),
      x_right = numeric(),
      lower_95 = numeric(),
      upper_95 = numeric()
    ))
  }

  interval_dt <- copy(curve_data)[order(time_days)]
  interval_dt[, x_right := c(time_days[-1], x_limit)]
  interval_dt[
    !is.na(lower_95) &
      !is.na(upper_95) &
      x_right > time_days &
      time_days < x_limit,
    .(
      x_left = time_days,
      x_right = pmin(x_right, x_limit),
      lower_95 = pmax(0, lower_95),
      upper_95 = pmin(1, upper_95)
    )
  ][x_right > x_left]
}

study3_draw_km_ci <- function(curve_data, x_limit, col,
                              transform_x = identity,
                              transform_y = identity) {
  ci_dt <- study3_km_ci_intervals(curve_data, x_limit)
  if (!nrow(ci_dt)) return(invisible(NULL))

  rect(
    xleft = transform_x(ci_dt$x_left),
    ybottom = transform_y(ci_dt$lower_95),
    xright = transform_x(ci_dt$x_right),
    ytop = transform_y(ci_dt$upper_95),
    col = col,
    border = NA
  )

  invisible(NULL)
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
                                           logrank_p = NA_real_,
                                           show_inset = FALSE) {
  x_axis <- study3_figure1_year_axis(x_limit)
  x_breaks <- x_axis$days
  panel_xlim <- c(0, x_limit)
  risk_table <- study3_km_risk_table(fit, x_breaks, labels)
  curve_dt <- study3_km_curve_data(fit, labels, x_limit)
  display_labels <- study3_figure1_label(labels)
  n_groups <- length(labels)
  is_dual <- grepl("dual|double", labels, ignore.case = TRUE)
  curve_col <- ifelse(is_dual, "#C00000", "#003F9E")
  ci_fill_col <- ifelse(
    is_dual,
    grDevices::adjustcolor("#C00000", alpha.f = 0.14),
    grDevices::adjustcolor("#003F9E", alpha.f = 0.14)
  )
  curve_lty <- ifelse(is_dual, 2, 1)
  legend_order <- c(which(!is_dual), which(is_dual))
  if (!length(legend_order)) legend_order <- seq_along(labels)
  left_margin <- 11.0
  risk_label_x <- -0.045 * x_limit
  text_cex <- 1.14
  main_axis_cex <- text_cex
  main_label_cex <- text_cex
  legend_cex <- text_cex
  risk_axis_cex <- text_cex
  risk_label_cex <- text_cex
  risk_group_cex <- text_cex
  risk_number_cex <- text_cex
  censor_tick_half_height <- 0.004
  censor_tick_lwd <- 0.45
  inset_censor_tick_half_height <- 0.0018
  inset_censor_tick_lwd <- 0.3
  inset_x <- c(0.31, 0.998) * x_limit
  inset_y <- c(0.18, 0.86)
  inset_ylim <- c(0.9, 1.0)
  inset_axis_x_tick_length <- 0.01
  inset_axis_y_tick_length <- 0.012 * x_limit
  inset_axis_tick_lwd <- 0.6
  logrank_label <- paste0("Log-rank p = ", study3_format_p(logrank_p))

  old_par <- par(no.readonly = TRUE)
  on.exit(par(old_par), add = TRUE)

  layout(matrix(c(1, 2), nrow = 2), heights = c(3.3, 1.5))

  par(mar = c(0.5, left_margin, 4.0, 1.0), las = 1, bty = "l", xaxs = "i", yaxs = "i")
  plot(
    NA,
    xlab = "",
    ylab = "Event-free survival (inappropriate shock)",
    xlim = panel_xlim,
    ylim = c(0, 1.0),
    xaxt = "n",
    yaxt = "n",
    type = "n",
    cex.axis = main_axis_cex,
    cex.lab = main_label_cex
  )
  for (i in seq_along(labels)) {
    group_curve <- curve_dt[device_group == labels[[i]]][order(time_days)]
    study3_draw_km_ci(
      curve_data = group_curve,
      x_limit = x_limit,
      col = ci_fill_col[[i]]
    )
  }
  for (i in seq_along(labels)) {
    group_curve <- curve_dt[device_group == labels[[i]]][order(time_days)]
    if (nrow(group_curve)) {
      lines(
        group_curve$time_days,
        group_curve$survival,
        type = "s",
        col = curve_col[[i]],
        lty = curve_lty[[i]],
        lwd = 1.35
      )
    }
  }
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
    cex.main = text_cex,
    font.main = 2
  )
	  mtext(
	    sprintf("Follow-up truncated at %s days (%.1f years)", format(x_limit, big.mark = ","), x_limit / 365.25),
	    side = 3,
	    line = 1.0,
    cex = text_cex,
    font = 3,
    col = "#1E3557"
  )

  if (isTRUE(show_inset)) {
    to_inset_x <- function(x) inset_x[[1]] + (x / x_limit) * diff(inset_x)
    to_inset_y <- function(y) {
      inset_y[[1]] + ((y - inset_ylim[[1]]) / diff(inset_ylim)) * diff(inset_y)
    }

    rect(inset_x[[1]], inset_y[[1]], inset_x[[2]], inset_y[[2]], col = "white", border = NA)
    clip(inset_x[[1]], inset_x[[2]], inset_y[[1]], inset_y[[2]])
    for (i in seq_along(labels)) {
      group_curve <- curve_dt[device_group == labels[[i]]][order(time_days)]
      study3_draw_km_ci(
        curve_data = group_curve,
        x_limit = x_limit,
        col = ci_fill_col[[i]],
        transform_x = to_inset_x,
        transform_y = to_inset_y
      )
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
            y0 = to_inset_y(censor_summary$surv[tick_idx] - inset_censor_tick_half_height),
            x1 = to_inset_x(censor_summary$time[tick_idx]),
            y1 = to_inset_y(censor_summary$surv[tick_idx] + inset_censor_tick_half_height),
            col = curve_col[[i]],
            lwd = inset_censor_tick_lwd,
            lend = "butt"
          )
        }
      }
    }
    clip(par("usr")[[1]], par("usr")[[2]], par("usr")[[3]], par("usr")[[4]])
    rect(inset_x[[1]], inset_y[[1]], inset_x[[2]], inset_y[[2]], border = "grey25", lwd = 0.8)
    legend(
      x = inset_x[[1]] + 0.03 * diff(inset_x),
      y = inset_y[[1]] + 0.40 * diff(inset_y),
      legend = display_labels[legend_order],
      col = curve_col[legend_order],
      lty = curve_lty[legend_order],
      lwd = 2,
      bg = grDevices::adjustcolor("white", alpha.f = 0.78),
      box.col = NA,
      y.intersp = 0.95,
      x.intersp = 0.85,
      cex = legend_cex,
      xpd = NA
    )
    rect(
      xleft = inset_x[[1]] + 0.02 * diff(inset_x),
      ybottom = inset_y[[1]] + 0.06 * diff(inset_y),
      xright = inset_x[[1]] + 0.34 * diff(inset_x),
      ytop = inset_y[[1]] + 0.16 * diff(inset_y),
      col = grDevices::adjustcolor("white", alpha.f = 0.78),
      border = NA,
      xpd = NA
    )
    text(
      x = inset_x[[1]] + 0.065 * diff(inset_x),
      y = inset_y[[1]] + 0.08 * diff(inset_y),
      labels = logrank_label,
      adj = c(0, 0),
      cex = text_cex,
      xpd = NA
    )
    axis_x_ticks <- round(seq(0, floor(x_limit / 365.25), by = 2) * 365.25)
    axis_x_labels <- as.character(seq(0, floor(x_limit / 365.25), by = 2))
    axis_y_ticks <- seq(0.9, 1.0, by = 0.05)
    segments(
      to_inset_x(axis_x_ticks), inset_y[[1]],
      to_inset_x(axis_x_ticks), inset_y[[1]] - inset_axis_x_tick_length,
      lwd = inset_axis_tick_lwd
    )
    text(to_inset_x(axis_x_ticks), inset_y[[1]] - 0.040, axis_x_labels, cex = text_cex, xpd = NA)
    segments(
      inset_x[[1]], to_inset_y(axis_y_ticks),
      inset_x[[1]] - inset_axis_y_tick_length, to_inset_y(axis_y_ticks),
      lwd = inset_axis_tick_lwd
    )
    text(
      inset_x[[1]] - 0.021 * x_limit,
      to_inset_y(axis_y_ticks),
      sprintf("%.2f", axis_y_ticks),
      cex = text_cex,
      adj = 1,
      xpd = NA
    )
  } else {
    legend(
      x = panel_xlim[[1]] + 0.86 * diff(panel_xlim),
      y = 0.22,
      legend = display_labels[legend_order],
      col = curve_col[legend_order],
      lty = curve_lty[legend_order],
      lwd = 2,
      bg = grDevices::adjustcolor("white", alpha.f = 0.78),
      box.col = NA,
      y.intersp = 0.95,
      x.intersp = 0.85,
      cex = legend_cex,
      xjust = 1
    )
    text(
      x = panel_xlim[[1]] + 0.22 * diff(panel_xlim),
      y = 0.09,
      labels = logrank_label,
      adj = c(0, 0),
      cex = text_cex
    )
  }

	  par(mar = c(3.2, left_margin, 0.2, 1.0), las = 1, bty = "n", xaxs = "i", yaxs = "i")
	  plot(
    NA,
    xlim = panel_xlim,
    ylim = c(0, n_groups + 1.65),
    axes = FALSE,
    xlab = "",
	    ylab = ""
	  )
	  axis(1, at = x_breaks, labels = x_axis$labels, tck = -0.06, line = 0, cex.axis = risk_axis_cex)
	  mtext("Years since ICD implantation", side = 1, line = 2.35, cex = text_cex)

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
dt_final[
  event_inapp_shock == 0 &
    tolower(trimws(as.character(death_flag))) == "yes",
  fg_event := 2L
]

# QC  
cat("N =", nrow(dt_final), "\n")
print(table(dt_final$fg_event)) 

stopifnot(all(!is.na(dt_final$t_inapp_shock_or_censor_days)))
stopifnot(all(dt_final$t_inapp_shock_or_censor_days >= 0))
stopifnot(all(dt_final$fg_event %in% c(0L, 1L, 2L)))

# Fine–Gray: sHR for Single vs Dual (Dual reference)
X <- model.matrix(~ device_group, data = dt_final)[, -1, drop = FALSE]

fg_fit <- crr(
  ftime   = dt_final$t_inapp_shock_or_censor_days,
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

if (study3_debugging_enabled()) {
  study3_debug_section("Dataset-adjusted Fine-Gray design")
  cat("Datasets entering Fine-Gray: ",
      paste(sort(unique(as.character(dt_final$dataset))), collapse = "; "),
      "\n", sep = "")
  cat("Design-matrix columns: ", paste(colnames(X_dataset), collapse = "; "), "\n", sep = "")
  cat("Dataset reference level implied by model.matrix: ",
      levels(factor(dt_final$dataset))[[1]], "\n", sep = "")
  print(dt_final[, .(
    n = .N,
    event_0_censored = sum(fg_event == 0L),
    event_1_inappropriate_shock = sum(fg_event == 1L),
    event_2_competing_death = sum(fg_event == 2L)
  ), by = dataset][order(dataset)])
}

fg_fit_dataset <- crr(
  ftime    = dt_final$t_inapp_shock_or_censor_days,
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

study3_fit_fg_device_results <- function(data, analysis) {
  if (!nrow(data)) {
    stop("Cannot fit Fine-Gray subgroup model on an empty dataset.", call. = FALSE)
  }

  if (length(unique(as.character(data$device_group))) < 2L) {
    stop(
      sprintf(
        "Cannot fit Fine-Gray subgroup model for '%s'; fewer than two device groups are present.",
        analysis
      ),
      call. = FALSE
    )
  }

  X_device <- model.matrix(~ device_group, data = data)[, -1, drop = FALSE]
  fit_unadjusted <- crr(
    ftime   = data$t_inapp_shock_or_censor_days,
    fstatus = data$fg_event,
    cov1    = X_device
  )

  X_dataset <- model.matrix(~ device_group + dataset, data = data)[, -1, drop = FALSE]
  fit_adjusted <- crr(
    ftime    = data$t_inapp_shock_or_censor_days,
    fstatus  = data$fg_event,
    cov1     = X_dataset,
    cengroup = data$dataset
  )

  rbindlist(
    list(
      study3_extract_crr_device_result(
        fit = fit_unadjusted,
        term = "device_groupSingle",
        model = "original_crr_device_only",
        dataset_handling = "none",
        data = data,
        analysis = analysis
      ),
      study3_extract_crr_device_result(
        fit = fit_adjusted,
        term = "device_groupSingle",
        model = "dataset_adjusted_crr",
        dataset_handling = "dataset fixed covariates + dataset-specific censoring via cengroup",
        data = data,
        analysis = analysis
      )
    )
  )
}

study3_fit_cox_device_results <- function(data, analysis) {
  if (!nrow(data)) {
    stop("Cannot fit Cox subgroup model on an empty dataset.", call. = FALSE)
  }

  if (length(unique(as.character(data$device_group))) < 2L) {
    stop(
      sprintf(
        "Cannot fit Cox subgroup model for '%s'; fewer than two device groups are present.",
        analysis
      ),
      call. = FALSE
    )
  }

  fit_unadjusted <- coxph(
    Surv(t_inapp_shock_or_censor_days, event_inapp_shock) ~ device_group,
    data = data
  )
  fit_adjusted <- coxph(
    Surv(t_inapp_shock_or_censor_days, event_inapp_shock) ~ device_group + strata(dataset),
    data = data
  )

  extract_one <- function(fit, model_label) {
    s <- summary(fit)
    term <- "device_groupSingle"
    term_idx <- match(term, rownames(s$coef))
    if (is.na(term_idx)) {
      stop(
        sprintf(
          "Term '%s' not found in Cox subgroup model coefficients for '%s'.",
          term,
          analysis
        ),
        call. = FALSE
      )
    }

    data.table(
      analysis = analysis,
      model = model_label,
      term = term,
      n = s$n,
      events = s$nevent,
      HR = s$coef[term_idx, "exp(coef)"],
      lci_95 = s$conf.int[term_idx, "lower .95"],
      uci_95 = s$conf.int[term_idx, "upper .95"],
      p_value = s$coef[term_idx, "Pr(>|z|)"]
    )
  }

  rbindlist(
    list(
      extract_one(fit_unadjusted, "cox_unadjusted"),
      extract_one(fit_adjusted, "cox_dataset_adjusted")
    )
  )
}

study3_format_fg_annotation <- function(result_dt, short = TRUE) {
  format_p <- function(p) {
    if (is.na(p)) return("NA")
    if (p < 0.001) return("<0.001")
    sprintf("%.3f", p)
  }

  unadjusted <- result_dt[model == "original_crr_device_only"][1]
  adjusted <- result_dt[model == "dataset_adjusted_crr"][1]

  c(
    sprintf(
      "%s: sHR %.2f (%.2f-%.2f), p=%s",
      if (short) "FG unadj" else "FG unadjusted",
      unadjusted$sHR,
      unadjusted$lci_95,
      unadjusted$uci_95,
      format_p(unadjusted$p_value)
    ),
    sprintf(
      "%s: sHR %.2f (%.2f-%.2f), p=%s",
      if (short) "FG adj" else "FG adjusted",
      adjusted$sHR,
      adjusted$lci_95,
      adjusted$uci_95,
      format_p(adjusted$p_value)
    )
  )
}

study3_format_cox_annotation <- function(result_dt, short = TRUE) {
  format_p <- function(p) {
    if (is.na(p)) return("NA")
    if (p < 0.001) return("<0.001")
    sprintf("%.3f", p)
  }

  unadjusted <- result_dt[model == "cox_unadjusted"][1]
  adjusted <- result_dt[model == "cox_dataset_adjusted"][1]

  c(
    sprintf(
      "%s: HR %.2f (%.2f-%.2f), p=%s",
      if (short) "Cox unadj" else "Cox unadjusted",
      unadjusted$HR,
      unadjusted$lci_95,
      unadjusted$uci_95,
      format_p(unadjusted$p_value)
    ),
    sprintf(
      "%s: HR %.2f (%.2f-%.2f), p=%s",
      if (short) "Cox adj" else "Cox adjusted",
      adjusted$HR,
      adjusted$lci_95,
      adjusted$uci_95,
      format_p(adjusted$p_value)
    )
  )
}

study3_normalize_yes_no <- function(x, var_name) {
  raw <- trimws(as.character(x))
  out <- rep(NA_character_, length(raw))

  out[tolower(raw) %in% c("yes", "y", "1", "true")] <- "Yes"
  out[tolower(raw) %in% c("no", "n", "0", "false")] <- "No"

  unknown_levels <- sort(unique(raw[!is.na(raw) & nzchar(raw) & is.na(out)]))
  if (length(unknown_levels)) {
    stop(
      sprintf(
        "Unexpected values in %s: %s",
        var_name,
        paste(unknown_levels, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  out
}

study3_cif_curve_data <- function(cif_object, x_limit = 3000) {
  curve_names <- names(cif_object)
  device_group <- sub(" 1$", "", curve_names)
  keep <- device_group %in% c("Dual", "Single")

  cif_object <- cif_object[keep]
  device_group <- device_group[keep]

  device_order <- c("Single", "Dual")
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

study3_build_figure2_cif_data <- function(data, x_limit = 2200) {
  if (!"AF_atrial_flutter" %in% names(data)) {
    stop("Column 'AF_atrial_flutter' not found in Study 3 analysis dataset.", call. = FALSE)
  }

  plot_data <- copy(data)
  plot_data[, af_status := study3_normalize_yes_no(AF_atrial_flutter, "AF_atrial_flutter")]

  missing_af_rows <- is.na(plot_data$af_status)
  if (any(missing_af_rows)) {
    cat(
      "Excluding ",
      sum(missing_af_rows),
      " row(s) with missing AF_atrial_flutter before Figure 2 plotting.\n",
      sep = ""
    )
    plot_data <- plot_data[!missing_af_rows]
  }

  af_order <- c("No", "Yes")
  af_labels <- c(
    No = "Without atrial fibrillation",
    Yes = "With atrial fibrillation"
  )
  af_analysis_labels <- c(
    No = "primary_without_af",
    Yes = "primary_with_af"
  )
  annotation_list <- vector("list", length(af_order))
  names(annotation_list) <- unname(af_labels[af_order])

  cif_panel_dt <- rbindlist(
    lapply(seq_along(af_order), function(idx) {
      af_level <- af_order[[idx]]
      panel_data <- plot_data[af_status == af_level]
      if (!nrow(panel_data)) {
        stop(
          sprintf("Cannot draw Figure 2; no patients available for AF subgroup '%s'.", af_level),
          call. = FALSE
        )
      }

      cif_panel <- with(
        panel_data,
        cuminc(
          t_inapp_shock_or_censor_days,
          fg_event,
          group = device_group
        )
      )

      panel_curves <- study3_cif_curve_data(
        cif_object = cif_panel[grep(" 1$", names(cif_panel))],
        x_limit = x_limit
      )
      panel_cox_results <- study3_fit_cox_device_results(
        data = panel_data,
        analysis = af_analysis_labels[[af_level]]
      )
      panel_fg_results <- study3_fit_fg_device_results(
        data = panel_data,
        analysis = af_analysis_labels[[af_level]]
      )
      annotation_list[[idx]] <<- c(
        study3_format_cox_annotation(panel_cox_results, short = TRUE),
        study3_format_fg_annotation(panel_fg_results, short = TRUE)
      )
      panel_curves[, af_status := af_level]
      panel_curves[, af_panel_label := af_labels[[af_level]]]
      panel_curves
    }),
    use.names = TRUE
  )

  cif_panel_dt[, af_panel_label := factor(
    af_panel_label,
    levels = unname(af_labels[af_order])
  )]

  list(
    curves = cif_panel_dt,
    panel_annotations = annotation_list
  )
}

study3_draw_cif_figure2 <- function(data, x_limit = 2200) {
  figure2_data <- study3_build_figure2_cif_data(data, x_limit = x_limit)
  cif_dt <- figure2_data$curves
  panel_annotations <- figure2_data$panel_annotations
  text_cex <- 1.14
  device_labels <- c(
    Single = "1-Lead Device",
    Dual = "2-Lead Device"
  )
  curve_col <- c(
    Single = "#003F9E",
    Dual = "#C00000"
  )
  curve_lty <- c(
    Single = 1,
    Dual = 2
  )
  x_axis <- study3_figure1_year_axis(x_limit)
  x_breaks <- x_axis$days
  y_breaks <- seq(0, 1, by = 0.1)
  af_panels <- levels(cif_dt$af_panel_label)
  effect_box_fill <- grDevices::adjustcolor("white", alpha.f = 0.84)

  old_par <- par(no.readonly = TRUE)
  on.exit(par(old_par), add = TRUE)

  par(
    mfrow = c(1, 2),
    mar = c(4.2, 1.2, 3.0, 1.0),
    oma = c(2.2, 5.2, 3.0, 0.6),
    las = 1,
    bty = "l",
    xaxs = "i",
    yaxs = "i"
  )

  for (panel_idx in seq_along(af_panels)) {
    panel_label <- af_panels[[panel_idx]]
    panel_dt <- cif_dt[af_panel_label == panel_label]

    plot(
      NA,
      xlim = c(0, x_limit),
      ylim = c(0, 1),
      axes = FALSE,
      xlab = "",
      ylab = ""
    )

    axis(1, at = x_breaks, labels = x_axis$labels, cex.axis = 1.05)
    if (panel_idx == 1L) {
      axis(2, at = y_breaks, labels = sprintf("%.1f", y_breaks), cex.axis = 1.05)
    } else {
      axis(2, at = y_breaks, labels = FALSE, tck = -0.015)
    }

    for (device in c("Single", "Dual")) {
      d <- panel_dt[device_group == device]
      lines(
        d$time_days,
        d$estimate,
        type = "s",
        col = curve_col[[device]],
        lty = curve_lty[[device]],
        lwd = 2
      )
    }

    title(main = panel_label, line = 1.0, cex.main = 1.15, font.main = 2)

    if (panel_idx == 1L) {
      legend(
        "topleft",
        legend = unname(device_labels[c("Single", "Dual")]),
        col = curve_col[c("Single", "Dual")],
        lty = curve_lty[c("Single", "Dual")],
        lwd = 2,
        bty = "n",
        cex = 1.05,
        inset = c(0.03, 0.04)
      )
    }

    panel_text <- panel_annotations[[panel_label]]
    if (length(panel_text)) {
      box_left <- 0.40 * x_limit
      box_right <- 0.985 * x_limit
      box_top <- 0.95
      box_bottom <- 0.64
      rect(
        xleft = box_left,
        ybottom = box_bottom,
        xright = box_right,
        ytop = box_top,
        col = effect_box_fill,
        border = NA,
        xpd = NA
      )
      text(
        x = box_left + 0.018 * x_limit,
        y = c(0.91, 0.84, 0.77, 0.70),
        labels = panel_text,
        adj = c(0, 0.5),
        cex = 0.74,
        xpd = NA
      )
    }
  }

  mtext("Years since ICD implantation", side = 1, outer = TRUE, line = -0.30, cex = 1.12)
  mtext(
    "Cumulative incidence for inappropriate shock",
    side = 2,
    outer = TRUE,
    line = 2.6,
    cex = text_cex,
    las = 0
  )
  mtext(
    "Figure 2. Cumulative Incidence of First Inappropriate ICD Shock by Device Type, Stratified by Atrial Fibrillation",
    side = 3,
    outer = TRUE,
    line = 1.2,
    cex = 1.15,
    font = 2
  )
  mtext(
    sprintf("Follow-up truncated at %s days (%.1f years)", format(x_limit, big.mark = ","), x_limit / 365.25),
    side = 3,
    outer = TRUE,
    line = 0.1,
    cex = 1.02,
    font = 3,
    col = "#1E3557"
  )
}

study3_save_grid(
  draw = function() {
    study3_draw_cif_figure2(
      data = dt_final,
      x_limit = 2200
    )
  },
  png_file = study3_output_path("figure_cif_inapp_shock_by_device.png"),
  pdf_file = study3_output_path("figure_cif_inapp_shock_by_device.pdf"),
  png_width = 3600,
  png_height = 1900,
  png_res = 300,
  pdf_width = 12.0,
  pdf_height = 6.4
)

study3_draw_cif_figure2(
  data = dt_final,
  x_limit = 2200
)
