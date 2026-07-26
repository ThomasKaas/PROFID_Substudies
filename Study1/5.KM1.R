###############################################################################

# Descriptive time to first inappropriate ICD shock:
# legacy Kaplan-Meier failure estimate and Aalen-Johansen cumulative incidence

###############################################################################
pkgs <- c("survival", "data.table", "ggplot2", "patchwork", "scales")

invisible(lapply(pkgs, function(p) {
  if (!requireNamespace(p, quietly = TRUE)) install.packages(p)
  library(p, character.only = TRUE)
}))
# ── Paths ──────────────────────────────────────────────────────────────────
study1_paths_file <- file.path("Study1", "study1_paths.R")
if (!file.exists(study1_paths_file)) study1_paths_file <- "study1_paths.R"
if (!file.exists(study1_paths_file)) study1_paths_file <- file.path("..", "study1_paths.R")
source(study1_paths_file)

INFILE <- study1_derived_path("master_clean_dataset1.rds")
OUTDIR <- study1_output_path("Supplementary_data")

dir.create(OUTDIR, showWarnings = FALSE, recursive = TRUE)

# ── Load full cohort ───────────────────────────────────────────────────────
d <- as.data.table(readRDS(INFILE))
cat(sprintf("Full cohort loaded: N = %d\n", nrow(d)))

# ── Missing Status_FIS treated as unexposed (consistent with main analysis) ─
#d[is.na(Status_FIS), Status_FIS := 0L]

# ── Inclusion: valid follow-up time only ───────────────────────────────────
d_km <- d[!is.na(Time_FIS_days) & Time_FIS_days > 0]
cat(sprintf("Patients included in KM: N = %d\n", nrow(d_km)))
cat(sprintf("Exposed (Status_FIS = 1): N = %d (%.1f%%)\n",
            sum(d_km$Status_FIS),
            mean(d_km$Status_FIS) * 100))

# ── Convert days to years ──────────────────────────────────────────────────
d_km[, Time_FIS_years := Time_FIS_days / 365.25]

# ── KM fit ─────────────────────────────────────────────────────────────────
fit <- survfit(Surv(Time_FIS_years, Status_FIS) ~ 1, data = d_km)

# ── CHECK 1: Median estimability ───────────────────────────────────────────
# Median = time at which survival drops to 0.50 (i.e. 1 - KM reaches 50%)
# If the curve never reaches a 50% failure estimate, quantile() returns NA
med <- quantile(fit, probs = 0.5)$quantile

cat("\n--- Median estimability check ---\n")
cat(sprintf("Maximum Kaplan-Meier failure estimate reached: %.1f%%\n",
            (1 - min(fit$surv)) * 100))
cat(sprintf("Required for median estimability:     50.0%%\n"))

if (is.na(med)) {
  cat("RESULT: Median NOT estimable — curve never reached a 50% failure estimate\n")
  cat("        This is expected given the low event rate (~2.2%)\n")
  median_text <- "not estimable (Kaplan-Meier failure estimate did not reach 50%)"
} else {
  cat(sprintf("RESULT: Median estimable = %.2f years\n", med))
  median_text <- sprintf("%.2f years", med)
}

# ── CHECK 2: KM failure estimate at 1, 3, 5 years ─────────────────────────
cat("\n--- Kaplan-Meier failure estimate (1 - KM) at 1, 3, 5 years ---\n")
sm <- summary(fit, times = c(1, 3, 5), extend = TRUE)

ci_tbl <- data.table(
  Year              = c(1, 3, 5),
  N_at_risk         = sm$n.risk,
  Cum_incidence_pct = round((1 - sm$surv)  * 100, 1),
  CI_lower_pct      = round((1 - sm$upper) * 100, 1),
  CI_upper_pct      = round((1 - sm$lower) * 100, 1)
)
print(ci_tbl)

out_km_csv <- file.path(OUTDIR, "KM_Failure_FIS_1_3_5yr.csv")
fwrite(ci_tbl, out_km_csv)
cat(sprintf("✓ Saved: %s\n", out_km_csv))

# Build caption text from results
ci_caption <- paste(
  sprintf("%s%% (95%% CI %s\u2013%s%%) at %d year%s",
          ci_tbl$Cum_incidence_pct,
          ci_tbl$CI_lower_pct,
          ci_tbl$CI_upper_pct,
          ci_tbl$Year,
          ifelse(ci_tbl$Year == 1, "", "s")),
  collapse = ", "
)

caption_text <- paste0(
  "Full analysis cohort (N = ", nrow(d_km), "). ",
  "Median time to first inappropriate ICD shock: ", median_text, ". ",
  "Kaplan-Meier failure estimate (1 - KM; deaths treated as censored): ",
  ci_caption, "."
)

cat(sprintf("\nCaption text:\n%s\n", caption_text))
# ── Build KM data frame for ggplot ─────────────────────────────────────────
km_df <- data.table(
  time  = c(0, fit$time),
  surv  = c(1, fit$surv),
  lower = c(1, fit$lower),
  upper = c(1, fit$upper)
)
km_df[, `:=`(
  cuminc = 1 - surv,
  ci_lo  = 1 - upper,
  ci_hi  = 1 - lower
)]

# ── Risk table data ────────────────────────────────────────────────────────
risk_times <- 0:5
sm_risk    <- summary(fit, times = risk_times, extend = TRUE)

risk_df <- data.table(
  time   = sm_risk$time,
  n_risk = sm_risk$n.risk
)

# ── Main KM plot ───────────────────────────────────────────────────────────
p_main <- ggplot(km_df, aes(x = time, y = cuminc)) +
  geom_step(aes(y = ci_lo), colour = "black",
            linewidth = 0.5, linetype = "dashed") +
  geom_step(aes(y = ci_hi), colour = "black",
            linewidth = 0.5, linetype = "dashed") +
  geom_step(colour = "black", linewidth = 0.9) +
  scale_x_continuous(
    breaks = 0:5,
    expand = c(0, 0)
  ) +
  scale_y_continuous(
    labels = percent_format(accuracy = 1),
    limits = c(0, NA),
    expand = c(0.02, 0)
  ) +
  coord_cartesian(xlim = c(0, 5), clip = "off") +  # clip = "off" key fix
  labs(
    x = NULL,
    y = "Kaplan-Meier failure estimate\nof first inappropriate ICD shock"
  ) +
  theme_classic(base_size = 12) +
  theme(
    axis.text        = element_text(size = 11, colour = "black"),
    axis.title.y     = element_text(size = 11, margin = margin(r = 8)),
    axis.text.x      = element_blank(),
    axis.ticks.x     = element_blank(),
    axis.line        = element_line(colour = "black")
  )

# ── Risk table panel ───────────────────────────────────────────────────────
p_risk <- ggplot(risk_df, aes(x = time, y = 0.5, label = n_risk)) +
  geom_text(size = 3.8, fontface = "plain", colour = "black") +
  annotate("text", x = -0.35, y = 0.5,
           label = "Number\nat risk",
           size = 3.5, hjust = 1, fontface = "plain",
           colour = "grey30") +
  scale_x_continuous(
    breaks = 0:5,
    labels = c("0", "1", "2", "3", "4", "5"),
    expand = c(0, 0)
  ) +
  scale_y_continuous(limits = c(0, 1)) +
  coord_cartesian(xlim = c(0, 5), clip = "off") +  # clip = "off" key fix
  labs(x = "Years", y = NULL) +
  theme_classic(base_size = 12) +
  theme(
    axis.text.x      = element_text(size = 11, colour = "black"),
    axis.title.x     = element_text(size = 11, margin = margin(t = 6)),
    axis.text.y      = element_blank(),
    axis.ticks.y     = element_blank(),
    axis.line.y      = element_blank(),
    axis.line.x      = element_line(colour = "black"),
    panel.grid       = element_blank()
  )

# ── Combine with forced alignment via & operator ───────────────────────────
p_final <- p_main / p_risk +
  plot_layout(heights = c(5, 1)) &
  theme(plot.margin = margin(5, 15, 5, 100))

# ── Save ───────────────────────────────────────────────────────────────────
out_png <- file.path(OUTDIR, "KM_FigA_time_to_FIS_fullcohort.png")
out_pdf <- file.path(OUTDIR, "KM_FigA_time_to_FIS_fullcohort.pdf")

unlink(c(out_png, out_pdf))
study1_save_plot(p_final, out_png, out_pdf, width = 10, height = 5.5)

cat(sprintf("\n✓ Saved:\n  %s\n  %s\n", out_png, out_pdf))
# ── Figure legend text for manuscript (NOT embedded in figure) ─────────────
cat("\n--- Figure legend (paste into manuscript) ---\n")
cat(sprintf(
  "Supplementary Figure S1A. Kaplan-Meier failure estimate (1 - KM) for first
inappropriate ICD shock over time, with deaths treated as censored. Full
analysis cohort (N = %d).
Median time to first inappropriate ICD shock was not estimable, as the
failure estimate did not reach 50%% during follow-up, consistent with
the low overall event rate. Kaplan-Meier failure estimates at 1, 3, and 5 years
were %.1f%% (95%% CI %.1f%%\u2013%.1f%%), %.1f%% (95%% CI %.1f%%\u2013%.1f%%),
and %.1f%% (95%% CI %.1f%%\u2013%.1f%%), respectively. Dashed lines represent
95%% confidence intervals. Because death is censored, these values are shown
as a conventional sensitivity analysis and not interpreted as real-world
cumulative incidence.\n",
  nrow(d_km),
  ci_tbl[Year==1, Cum_incidence_pct],
  ci_tbl[Year==1, CI_lower_pct],
  ci_tbl[Year==1, CI_upper_pct],
  ci_tbl[Year==3, Cum_incidence_pct],
  ci_tbl[Year==3, CI_lower_pct],
  ci_tbl[Year==3, CI_upper_pct],
  ci_tbl[Year==5, Cum_incidence_pct],
  ci_tbl[Year==5, CI_lower_pct],
  ci_tbl[Year==5, CI_upper_pct]
))

###############################################################################

# KM 1 — EXTENSION (2026-07-26, roadmap task C7):
# Aalen-Johansen cumulative incidence of first inappropriate ICD shock
# with death as a competing event.
#
# The legacy Kaplan-Meier analysis above is intentionally retained.
# This section adds the competing-risk-correct estimate: 1 - KM treats the
# deaths before shock as ordinary censoring and therefore overstates the
# real-world probability of shock (a patient who dies can no longer experience
# one). Of 603 total deaths, 590 occurred before inappropriate shock.
#
# New outputs (nothing from the KM analysis above is overwritten):
#   - AJ_FigA_CIF_FIS_fullcohort.png/.pdf  (shock CIF + competing death CIF,
#                                          risk table with numbers at risk
#                                          and cumulative competing deaths)
#   - AJ_CIF_FIS_1_3_5yr.csv               (1/3/5-year CIFs with 95% CIs
#                                          for shock and competing death)
#   - console: KM vs AJ comparison, updated Results sentence and
#     Supplementary Figure S1B caption

###############################################################################

# ── Three-level competing-risk status ────────────────────────────────────────
# 0 = censored (alive and shock-free at last follow-up)
# 1 = first inappropriate ICD shock
# 2 = death without prior inappropriate shock (competing event)
# Cleaning rule E5 guarantees Status_FIS == 1 only when
# Time_FIS_days < Time_death_days, so no shock/death ties can occur;
# for unexposed patients Time_FIS_days == Time_death_days (rules E1/E6),
# hence event times are identical to the KM analysis — only the status of
# deaths changes (censored -> competing event).
d_cr <- copy(d_km)
d_cr[, `:=`(
  Time_CR_years = fifelse(Status_FIS == 1L,
                          Time_FIS_days, Time_death_days) / 365.25,
  Status_CR     = fifelse(Status_FIS == 1L, 1L,
                          fifelse(Status_death == 1L, 2L, 0L))
)]

cat("\n--- Competing-risk status (Aalen-Johansen input) ---\n")
print(table(factor(d_cr$Status_CR,
                   levels = c(0, 1, 2),
                   labels = c("Censored", "Shock", "Death"))))
stopifnot(d_cr[Status_FIS == 1L, all(Time_FIS_days < Time_death_days)])
stopifnot(!anyNA(d_cr$Time_CR_years), all(d_cr$Time_CR_years > 0))

# ── Aalen-Johansen fit ───────────────────────────────────────────────────────
# survfit() with a factor status computes the Aalen-Johansen estimator.
fit_aj <- survfit(
  Surv(Time_CR_years, factor(Status_CR,
                             levels = c(0, 1, 2),
                             labels = c("censor", "shock", "death"))) ~ 1,
  data = d_cr
)

# ── Cumulative incidence at 1, 3, 5 years with 95% CIs ──────────────────────
sm_aj <- summary(fit_aj, times = c(1, 3, 5), extend = TRUE)

n_at_risk_at <- function(t) sum(d_cr$Time_CR_years >= t)
n_death_at   <- function(t) sum(d_cr$Status_CR == 2L & d_cr$Time_CR_years <= t)

aj_tbl <- data.table(
  Year               = c(1, 3, 5),
  N_at_risk          = vapply(c(1, 3, 5), n_at_risk_at, integer(1)),
  Cum_deaths         = vapply(c(1, 3, 5), n_death_at, integer(1)),
  Shock_CIF_pct      = round(100 * sm_aj$pstate[, "shock"], 1),
  Shock_CI_lower_pct = round(100 * sm_aj$lower[,  "shock"], 1),
  Shock_CI_upper_pct = round(100 * sm_aj$upper[,  "shock"], 1),
  Death_CIF_pct      = round(100 * sm_aj$pstate[, "death"], 1),
  Death_CI_lower_pct = round(100 * sm_aj$lower[,  "death"], 1),
  Death_CI_upper_pct = round(100 * sm_aj$upper[,  "death"], 1)
)

cat("\n--- Aalen-Johansen cumulative incidence at 1, 3, 5 years ---\n")
print(aj_tbl)

out_aj_csv <- file.path(OUTDIR, "AJ_CIF_FIS_1_3_5yr.csv")
fwrite(aj_tbl, out_aj_csv)
cat(sprintf("✓ Saved: %s\n", out_aj_csv))

# ── KM (death censored) vs Aalen-Johansen comparison ─────────────────────────
cat("\n--- Comparison: 1 - KM (death censored) vs Aalen-Johansen CIF ---\n")
cmp_km_aj <- data.table(
  Year   = c(1, 3, 5),
  KM_pct = ci_tbl$Cum_incidence_pct,
  AJ_pct = aj_tbl$Shock_CIF_pct
)
cmp_km_aj[, Overstatement_pp := round(KM_pct - AJ_pct, 2)]
print(cmp_km_aj)

# ── AJ curve data frame for ggplot ───────────────────────────────────────────
aj_df <- data.table(
  time     = c(0, fit_aj$time),
  shock    = c(0, fit_aj$pstate[, "shock"]),
  shock_lo = c(0, fit_aj$lower[,  "shock"]),
  shock_hi = c(0, fit_aj$upper[,  "shock"]),
  death    = c(0, fit_aj$pstate[, "death"]),
  death_lo = c(0, fit_aj$lower[,  "death"]),
  death_hi = c(0, fit_aj$upper[,  "death"])
)

# Truncate display at 5 years; carry the year-5 value to the right edge so
# the step lines reach x = 5 (also keeps the y-axis scaled to the 0-5y window)
edge5 <- data.table(
  time     = 5,
  shock    = sm_aj$pstate[3, "shock"],
  shock_lo = sm_aj$lower[3,  "shock"],
  shock_hi = sm_aj$upper[3,  "shock"],
  death    = sm_aj$pstate[3, "death"],
  death_lo = sm_aj$lower[3,  "death"],
  death_hi = sm_aj$upper[3,  "death"]
)
aj_plot_df <- rbind(aj_df[time < 5], edge5)

# Use separate, zero-anchored axes so the much smaller shock CIF remains
# readable. ggplot2 secondary axes require a one-to-one linear transformation.
shock_axis_max <- 0.10
death_axis_max <- 0.35
shock_axis_scale <- death_axis_max / shock_axis_max
death_axis_break <- 0.05
stopifnot(shock_axis_max > 0, death_axis_max > 0, shock_axis_scale > 0)

# ── Risk table data: numbers at risk + cumulative competing deaths ───────────
risk_df_aj <- data.table(
  time    = risk_times,
  n_risk  = vapply(risk_times, n_at_risk_at, integer(1)),
  n_death = vapply(risk_times, n_death_at, integer(1))
)
risk_long_aj <- rbind(
  risk_df_aj[, .(time, row_label = "Number at risk", value = n_risk)],
  risk_df_aj[, .(time, row_label = "Competing deaths", value = n_death)]
)
risk_long_aj[, row_label := factor(
  row_label,
  levels = c("Competing deaths", "Number at risk")
)]

# ── Main AJ plot ─────────────────────────────────────────────────────────────
p_aj_main <- ggplot(aj_plot_df) +
  geom_step(aes(x = time, y = death_lo), colour = "grey55",
            linewidth = 0.5, linetype = "dashed") +
  geom_step(aes(x = time, y = death_hi), colour = "grey55",
            linewidth = 0.5, linetype = "dashed") +
  geom_step(aes(x = time, y = shock_lo * shock_axis_scale), colour = "black",
            linewidth = 0.5, linetype = "dashed") +
  geom_step(aes(x = time, y = shock_hi * shock_axis_scale), colour = "black",
            linewidth = 0.5, linetype = "dashed") +
  geom_step(aes(x = time, y = death,
                colour = "Death (left axis)"), linewidth = 0.9) +
  geom_step(aes(x = time, y = shock * shock_axis_scale,
                colour = "Inappropriate ICD shock (right axis)"), linewidth = 0.9) +
  scale_colour_manual(
    values = c("Death (left axis)" = "grey55",
               "Inappropriate ICD shock (right axis)" = "black"),
    breaks = c("Death (left axis)", "Inappropriate ICD shock (right axis)")
  ) +
  scale_x_continuous(
    breaks = 0:5,
    expand = c(0, 0)
  ) +
  scale_y_continuous(
    labels = percent_format(accuracy = 1),
    breaks = seq(0, death_axis_max, by = death_axis_break),
    limits = c(0, death_axis_max),
    expand = c(0.02, 0),
    sec.axis = sec_axis(
      ~ . / shock_axis_scale,
      name = "Cumulative incidence of first\ninappropriate ICD shock",
      breaks = seq(0, shock_axis_max, by = 0.01),
      labels = percent_format(accuracy = 1)
    )
  ) +
  coord_cartesian(xlim = c(0, 5), clip = "off") +
  labs(
    x      = NULL,
    y      = "Cumulative incidence of\ncompeting death",
    colour = NULL
  ) +
  theme_classic(base_size = 12) +
  theme(
    axis.text            = element_text(size = 11, colour = "black"),
    axis.title.y.left    = element_text(size = 11, colour = "grey35",
                                        margin = margin(r = 2)),
    axis.title.y.right   = element_text(size = 11, colour = "black",
                                        margin = margin(l = 8)),
    axis.text.y.left     = element_text(size = 11, colour = "grey35"),
    axis.ticks.y.left    = element_line(colour = "grey55"),
    axis.line.y.left     = element_line(colour = "grey55"),
    axis.text.x          = element_blank(),
    axis.ticks.x         = element_blank(),
    axis.line            = element_line(colour = "black"),
    legend.position      = c(0.03, 0.97),
    legend.justification = c(0, 1),
    legend.background    = element_blank(),
    legend.text          = element_text(size = 10, colour = "black")
  )

# ── Risk table panel (numbers at risk + cumulative competing deaths) ─────────
p_aj_risk <- ggplot(risk_long_aj,
                    aes(x = time, y = row_label, label = value)) +
  geom_text(size = 3.8, fontface = "plain", colour = "black") +
  scale_x_continuous(
    breaks = 0:5,
    labels = c("0", "1", "2", "3", "4", "5"),
    expand = c(0, 0)
  ) +
  scale_y_discrete(expand = c(0.6, 0.6)) +
  coord_cartesian(xlim = c(0, 5), clip = "off") +
  labs(x = "Years", y = NULL) +
  theme_classic(base_size = 12) +
  theme(
    axis.text.x       = element_text(size = 11, colour = "black"),
    axis.title.x      = element_text(size = 11, margin = margin(t = 6)),
    axis.text.y       = element_text(size = 9, colour = "grey30",
                                     hjust = 1, margin = margin(r = 20)),
    axis.ticks.y      = element_blank(),
    axis.line.y       = element_blank(),
    axis.line.x       = element_line(colour = "black"),
    panel.grid        = element_blank()
  )

# ── Combine with forced alignment via & operator ─────────────────────────────
p_aj_final <- p_aj_main / p_aj_risk +
  plot_layout(heights = c(5, 1.2)) &
  theme(plot.margin = margin(5, 15, 5, 15))

# ── Save ─────────────────────────────────────────────────────────────────────
out_aj_png <- file.path(OUTDIR, "AJ_FigA_CIF_FIS_fullcohort.png")
out_aj_pdf <- file.path(OUTDIR, "AJ_FigA_CIF_FIS_fullcohort.pdf")

unlink(c(out_aj_png, out_aj_pdf))
study1_save_plot(p_aj_final, out_aj_png, out_aj_pdf, width = 10, height = 5.5)

cat(sprintf("\n✓ Saved:\n  %s\n  %s\n", out_aj_png, out_aj_pdf))

# ── Updated manuscript text ──────────────────────────────────────────────────
cat("\n--- Updated Results sentence (paste into manuscript) ---\n")
cat(sprintf(
  "With deaths treated as censored, the conventional Kaplan-Meier failure
estimates (1 - KM) for first inappropriate ICD shock were %.1f%% (95%% CI
%.1f%%–%.1f%%), %.1f%% (95%% CI %.1f%%–%.1f%%), and %.1f%% (95%% CI
%.1f%%–%.1f%%) at 1, 3, and 5 years, respectively. Accounting for death as a
competing event, the corresponding Aalen-Johansen cumulative incidences were
%.1f%% (95%% CI %.1f%%–%.1f%%), %.1f%% (95%% CI %.1f%%–%.1f%%), and %.1f%%
(95%% CI %.1f%%–%.1f%%); cumulative incidences of competing death before
inappropriate shock were %.1f%%
(95%% CI %.1f%%–%.1f%%), %.1f%% (95%% CI %.1f%%–%.1f%%), and %.1f%% (95%% CI
%.1f%%–%.1f%%), respectively.\n",
  ci_tbl[Year == 1, Cum_incidence_pct],
  ci_tbl[Year == 1, CI_lower_pct],
  ci_tbl[Year == 1, CI_upper_pct],
  ci_tbl[Year == 3, Cum_incidence_pct],
  ci_tbl[Year == 3, CI_lower_pct],
  ci_tbl[Year == 3, CI_upper_pct],
  ci_tbl[Year == 5, Cum_incidence_pct],
  ci_tbl[Year == 5, CI_lower_pct],
  ci_tbl[Year == 5, CI_upper_pct],
  aj_tbl[Year == 1, Shock_CIF_pct],
  aj_tbl[Year == 1, Shock_CI_lower_pct],
  aj_tbl[Year == 1, Shock_CI_upper_pct],
  aj_tbl[Year == 3, Shock_CIF_pct],
  aj_tbl[Year == 3, Shock_CI_lower_pct],
  aj_tbl[Year == 3, Shock_CI_upper_pct],
  aj_tbl[Year == 5, Shock_CIF_pct],
  aj_tbl[Year == 5, Shock_CI_lower_pct],
  aj_tbl[Year == 5, Shock_CI_upper_pct],
  aj_tbl[Year == 1, Death_CIF_pct],
  aj_tbl[Year == 1, Death_CI_lower_pct],
  aj_tbl[Year == 1, Death_CI_upper_pct],
  aj_tbl[Year == 3, Death_CIF_pct],
  aj_tbl[Year == 3, Death_CI_lower_pct],
  aj_tbl[Year == 3, Death_CI_upper_pct],
  aj_tbl[Year == 5, Death_CIF_pct],
  aj_tbl[Year == 5, Death_CI_lower_pct],
  aj_tbl[Year == 5, Death_CI_upper_pct]
))

cat("\n--- Updated Supplementary Figure S1 caption (paste into manuscript) ---\n")
cat(sprintf(
  "Supplementary Figure S1B. Aalen-Johansen cumulative incidence of first
inappropriate ICD shock (black, right y-axis) with 95%% confidence intervals
(dashed black lines), accounting for the competing risk of death (grey,
left y-axis; 95%% confidence intervals shown as dashed grey lines), in the
full analysis cohort (N = %d). The two y-axes use different scales (left,
0–%.0f%%; right, 0–%.0f%%) and both begin at zero; values must be read against
the corresponding axis.
Cumulative incidence of first inappropriate shock was %.1f%% (95%% CI
%.1f%%–%.1f%%) at 1 year, %.1f%% (95%% CI %.1f%%–%.1f%%) at 3 years, and
%.1f%% (95%% CI %.1f%%–%.1f%%) at 5 years. The corresponding cumulative
incidence of competing death was %.1f%% (95%% CI %.1f%%–%.1f%%), %.1f%%
(95%% CI %.1f%%–%.1f%%), and %.1f%% (95%% CI %.1f%%–%.1f%%), respectively.
Numbers at risk and cumulative numbers of competing deaths are shown below
the curves.\n",
  nrow(d_cr),
  100 * death_axis_max,
  100 * shock_axis_max,
  aj_tbl[Year == 1, Shock_CIF_pct],
  aj_tbl[Year == 1, Shock_CI_lower_pct],
  aj_tbl[Year == 1, Shock_CI_upper_pct],
  aj_tbl[Year == 3, Shock_CIF_pct],
  aj_tbl[Year == 3, Shock_CI_lower_pct],
  aj_tbl[Year == 3, Shock_CI_upper_pct],
  aj_tbl[Year == 5, Shock_CIF_pct],
  aj_tbl[Year == 5, Shock_CI_lower_pct],
  aj_tbl[Year == 5, Shock_CI_upper_pct],
  aj_tbl[Year == 1, Death_CIF_pct],
  aj_tbl[Year == 1, Death_CI_lower_pct],
  aj_tbl[Year == 1, Death_CI_upper_pct],
  aj_tbl[Year == 3, Death_CIF_pct],
  aj_tbl[Year == 3, Death_CI_lower_pct],
  aj_tbl[Year == 3, Death_CI_upper_pct],
  aj_tbl[Year == 5, Death_CIF_pct],
  aj_tbl[Year == 5, Death_CI_lower_pct],
  aj_tbl[Year == 5, Death_CI_upper_pct]
))
