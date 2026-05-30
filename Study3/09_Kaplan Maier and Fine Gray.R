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

survdiff(
  Surv(t_followup_days_final, event_inapp_shock) ~ device_group,
  data = dt_final
)

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

study3_draw_km_with_risk_table <- function(fit, labels, x_limit = 3000) {
  x_breaks <- seq(0, x_limit, by = 500)
  risk_table <- study3_km_risk_table(fit, x_breaks, labels)
  n_groups <- length(labels)
  curve_col <- rep(c("red", "blue"), length.out = n_groups)
  curve_lty <- rep(1, n_groups)

  old_par <- par(no.readonly = TRUE)
  on.exit(par(old_par), add = TRUE)

  layout(matrix(c(1, 2), nrow = 2), heights = c(3.4, 1.25))

  par(mar = c(0.3, 5.4, 1.0, 1.0), las = 1, bty = "l", xaxs = "i", yaxs = "i")
  plot(
    fit,
    col = curve_col,
    lty = curve_lty,
    lwd = 2,
    xlab = "",
    ylab = "Event-free survival (inappropriate shock)",
    xlim = c(0, x_limit),
    xaxt = "n",
    mark.time = TRUE,
    conf.int = FALSE
  )
  axis(1, at = x_breaks, labels = FALSE, tck = -0.015)
  legend(
    "bottomleft",
    legend = labels,
    col = curve_col,
    lty = curve_lty,
    lwd = 2,
    bty = "n",
    inset = 0.01
  )

  par(mar = c(3.2, 5.4, 0.2, 1.0), las = 1, bty = "n", xaxs = "i", yaxs = "i")
  plot(
    NA,
    xlim = c(0, x_limit),
    ylim = c(0.5, n_groups + 1.0),
    axes = FALSE,
    xlab = "",
    ylab = ""
  )
  axis(1, at = x_breaks, labels = x_breaks, tick = FALSE, line = 0.2, cex.axis = 0.9)
  mtext("Days since ICD implantation", side = 1, line = 2.0, cex = 0.95)

  row_y <- rev(seq_len(n_groups))
  par(xpd = NA)
  text(-0.09 * x_limit, n_groups + 0.65, "Number at risk", adj = 1, font = 2, cex = 0.9)
  text(-0.09 * x_limit, row_y, labels, adj = 1, cex = 0.85)

  for (j in seq_along(x_breaks)) {
    text(x_breaks[[j]], row_y, risk_table[, j], cex = 0.85)
  }
  par(xpd = FALSE)
}

km_labels <- sub("^device_group=", "", names(km_fit$strata))
if (!length(km_labels)) km_labels <- levels(factor(dt_final$device_group))

study3_save_grid(
  draw = function() {
    study3_draw_km_with_risk_table(
      fit = km_fit,
      labels = km_labels,
      x_limit = 3000
    )
  },
  png_file = study3_output_path("figure_1_km_inapp_shock_by_device_3000d_risk_table.png"),
  pdf_file = study3_output_path("figure_1_km_inapp_shock_by_device_3000d_risk_table.pdf"),
  png_width = 1800,
  png_height = 1350,
  png_res = 300,
  pdf_width = 6.0,
  pdf_height = 4.5
)


study3_draw_km_with_risk_table(
  fit = km_fit,
  labels = km_labels,
  x_limit = 3000
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

cif <- with(
  dt_final,
  cuminc(
    t_followup_days_final,
    fg_event,
    group = device_group
  )
)

cif_inapp <- cif[grep(" 1$", names(cif))]

plot(
  cif_inapp,
  lwd = 2,
  lty = c(1, 2),
  curvlab = c("Dual-chamber ICD", "Single-chamber ICD"),
  xlab = "Days since ICD implantation",
  ylab = "Cumulative incidence of inappropriate shock",
  xlim = c(0, 5500),
  ylim = c(0, 1)
)

