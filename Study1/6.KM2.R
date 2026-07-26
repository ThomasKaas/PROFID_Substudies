###############################################################################

# KM 2: Comparison overall survival in patients who experienced inappropriate ICD shock 
#       and who did not.

###############################################################################
pkgs <- c(
  "tidyverse","dplyr" ,"survival", "data.table", "mice", "naniar", "grid","gridExtra",
  "openxlsx", "readxl", "gt", "ggplot2", "patchwork", "scales"
)

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

# ── Missing Status_FIS treated as unexposed ────────────────────────────────
d[is.na(Status_FIS), Status_FIS := 0L]

# ── Inclusion: valid Time_death_days and death status ─────────────────────
d_km <- d[
  !is.na(Status_death)    &
    !is.na(Time_death_days) &
    !is.na(Status_FIS)      &
    Time_death_days > 0
]
cat(sprintf("Patients included in KM: N = %d\n", nrow(d_km)))
cat(sprintf("Shocked (Status_FIS = 1):     N = %d (%.1f%%)\n",
            d_km[Status_FIS == 1L, .N],
            d_km[Status_FIS == 1L, .N] / nrow(d_km) * 100))
cat(sprintf("Not shocked (Status_FIS = 0): N = %d (%.1f%%)\n",
            d_km[Status_FIS == 0L, .N],
            d_km[Status_FIS == 0L, .N] / nrow(d_km) * 100))

# ── Convert Time_death_days to years ──────────────────────────────────────
d_km[, Time_death_years := Time_death_days / 365.25]

# ── Group label ───────────────────────────────────────────────────────────
d_km[, shock_group := fifelse(
  Status_FIS == 1L,
  "Inappropriate shock",
  "No inappropriate shock"
)]
d_km[, shock_group := factor(shock_group,
                             levels = c("No inappropriate shock",
                                        "Inappropriate shock"))]







# ── KM fit ─────────────────────────────────────────────────────────────────
fit <- survfit(Surv(Time_death_years, Status_death) ~ shock_group, data = d_km)

# ── Deaths by group — print for manuscript ────────────────────────────────
cat("\n--- Deaths by shock group ---\n")
death_tab <- d_km[, .(
  N      = .N,
  Deaths = sum(Status_death),
  Pct    = round(mean(Status_death) * 100, 1)
), by = shock_group]
print(death_tab)

# ── Build KM data frame for ggplot ─────────────────────────────────────────
s     <- summary(fit)
km_df <- data.table(
  time  = s$time,
  surv  = s$surv,
  lower = s$lower,
  upper = s$upper,
  group = s$strata
)

# Clean group labels
km_df[, group := gsub("shock_group=", "", group)]
km_df[, group := factor(group,
                        levels = c("No inappropriate shock",
                                   "Inappropriate shock"))]

# Add time = 0 rows for clean start
t0 <- data.table(
  time  = c(0, 0),
  surv  = c(1, 1),
  lower = c(1, 1),
  upper = c(1, 1),
  group = factor(c("No inappropriate shock", "Inappropriate shock"),
                 levels = c("No inappropriate shock", "Inappropriate shock"))
)
km_df <- rbind(t0, km_df)

# ── Colour scheme ──────────────────────────────────────────────────────────
col_map <- c("No inappropriate shock" = "#2c6e96",   # blue
             "Inappropriate shock"    = "#c0392b")   # red

# ── Plot ───────────────────────────────────────────────────────────────────
p_final <- ggplot(km_df, aes(x = time, y = surv,
                             group = group, colour = group)) +
  geom_step(linewidth = 0.9) +
  scale_colour_manual(values = col_map) +
  scale_x_continuous(
    breaks = 0:5,
    limits = c(0, 5),
    expand = c(0, 0)
  ) +
  scale_y_continuous(
    labels = percent_format(accuracy = 1),
    limits = c(0, 1),
    breaks = seq(0, 1, 0.25),    # 0, 25, 50, 75, 100%
    expand = c(0.02, 0)
  ) +
  coord_cartesian(xlim = c(0, 5), clip = "off") +
  labs(
    x      = "Years",
    y      = "Overall survival",
    colour = NULL
  ) +
  theme_classic(base_size = 12) +
  theme(
    axis.text         = element_text(size = 11, colour = "black"),
    axis.title        = element_text(size = 11),
    axis.title.x      = element_text(margin = margin(t = 6)),
    axis.title.y      = element_text(margin = margin(r = 8)),
    axis.line         = element_line(colour = "black"),
    legend.position   = c(0.75, 0.15),
    legend.text       = element_text(size = 10),
    legend.key.width  = unit(1.5, "cm"),
    legend.background = element_blank(),
    plot.margin       = margin(10, 15, 10, 15)
  )

# ── Save ───────────────────────────────────────────────────────────────────
out_png <- file.path(OUTDIR, "KM_FigB_survival_by_shock_fullcohort.png")
out_pdf <- file.path(OUTDIR, "KM_FigB_survival_by_shock_fullcohort.pdf")

study1_save_plot(p_final, out_png, out_pdf, width = 7.5, height = 5.5)

cat(sprintf("\n✓ Saved:\n  %s\n  %s\n", out_png, out_pdf))

# ── Figure legend text for manuscript (NOT embedded in figure) ─────────────
cat("\n--- Figure legend (paste into manuscript) ---\n")
cat(sprintf(
  "Figure S1. Kaplan-Meier curves comparing overall survival between patients
who experienced inappropriate ICD shock (N = %d) and those who did not
(N = %d). Full analysis cohort (N = %d). Follow-up time measured from
ICD implantation. Blue line = no inappropriate shock; red line =
inappropriate shock. These curves do not account for the time-dependent
nature of the exposure and should be interpreted as descriptive
summaries only.\n",
  d_km[Status_FIS == 1L, .N],
  d_km[Status_FIS == 0L, .N],
  nrow(d_km)
))

###############################################################################

# KM 2 — EXTENSION (2026-07-26, roadmap task C13):
# Kaplan-Meier survival curve anchored at the time of first inappropriate
# ICD shock (t = 0 = shock), followed to death or censoring, among the
# patients who experienced inappropriate shock.
#
# Rationale: the primary time-dependent Cox model assumes a constant hazard
# multiplier from the moment of shock onward and cannot distinguish a
# transient early risk spike from a persistent one. With only a handful of
# deaths among the exposed patients, a formal piecewise (0-30d/31-180d/
# >180d) Cox model on this subgroup is not reliably estimable. This purely
# descriptive, within-group curve instead shows the shape of risk after
# shock (front-loaded vs. flat) without splitting the few events across
# strata. It has no unexposed comparator and does not itself establish an
# excess risk versus non-shocked patients — that comparison remains the
# role of the primary Cox model above.
#
# New output (nothing above is overwritten):
#   - KM_FigC_survival_after_shock.png/.pdf (survival from shock, risk table)
#   - console: N/events and Supplementary Figure caption text

###############################################################################

d_post_shock <- d_km[
  Status_FIS == 1L &
    !is.na(Time_FIS_days) &
    Time_death_days > Time_FIS_days
]
stopifnot(nrow(d_post_shock) > 0)
d_post_shock[, Time_since_shock_days := Time_death_days - Time_FIS_days]

cat(sprintf("\nPatients with inappropriate shock included in post-shock KM: N = %d\n",
            nrow(d_post_shock)))
cat(sprintf("Deaths after shock: %d\n", sum(d_post_shock$Status_death)))

fit_post_shock <- survfit(Surv(Time_since_shock_days, Status_death) ~ 1,
                          data = d_post_shock)

# ── Risk table, truncated once the risk set thins to < 10 patients ─────────
# Reported alongside cumulative deaths and cumulative censoring so that a
# drop in the number at risk can be attributed to death vs. censoring
# rather than read as death alone. "At risk" is derived as N minus the two
# cumulative counts (rather than taken from survfit's n.risk) so the three
# rows always reconcile exactly, including patients censored/dying exactly
# on a grid day.
n_death_at_post <- function(t) {
  sum(d_post_shock$Status_death == 1L & d_post_shock$Time_since_shock_days <= t)
}
n_censor_at_post <- function(t) {
  sum(d_post_shock$Status_death == 0L & d_post_shock$Time_since_shock_days <= t)
}
# Nominal grid in days, labelled in years below (180 d -> 0.5 y, 365 d -> 1 y, ...)
risk_times_days <- c(0, 180, 365, 545, 730, 1095, 1460, 1825, 2190)
year_label_lookup <- c(`0` = "0", `180` = "0.5", `365` = "1", `545` = "1.5",
                       `730` = "2", `1095` = "3", `1460` = "4", `1825` = "5",
                       `2190` = "6")
risk_df_post <- data.table(
  time     = risk_times_days,
  n_death  = vapply(risk_times_days, n_death_at_post, integer(1)),
  n_censor = vapply(risk_times_days, n_censor_at_post, integer(1))
)
risk_df_post[, n_risk := nrow(d_post_shock) - n_death - n_censor]
stopifnot(all(risk_df_post$n_risk + risk_df_post$n_death + risk_df_post$n_censor
             == nrow(d_post_shock)))
max_time_shown <- max(risk_df_post[n_risk >= 10, time])
risk_df_post <- risk_df_post[time <= max_time_shown]
risk_long_post <- rbind(
  risk_df_post[, .(time, row_label = "Number at risk", value = n_risk)],
  risk_df_post[, .(time, row_label = "Deaths",         value = n_death)],
  risk_df_post[, .(time, row_label = "Censored",       value = n_censor)]
)
risk_long_post[, row_label := factor(
  row_label, levels = c("Censored", "Deaths", "Number at risk")
)]

# ── Build KM data frame for ggplot ─────────────────────────────────────────
km_df_post <- data.table(
  time  = c(0, fit_post_shock$time),
  surv  = c(1, fit_post_shock$surv),
  lower = c(1, fit_post_shock$lower),
  upper = c(1, fit_post_shock$upper)
)
km_df_post <- km_df_post[time <= max_time_shown]
if (max(km_df_post$time) < max_time_shown) {
  edge_row <- km_df_post[which.max(time)]
  edge_row[, time := max_time_shown]
  km_df_post <- rbind(km_df_post, edge_row)
}

# ── Main KM plot ────────────────────────────────────────────────────────────
p_post_main <- ggplot(km_df_post, aes(x = time, y = surv)) +
  geom_step(aes(y = lower), colour = "black", linewidth = 0.5, linetype = "dashed") +
  geom_step(aes(y = upper), colour = "black", linewidth = 0.5, linetype = "dashed") +
  geom_step(colour = "#c0392b", linewidth = 0.9) +
  scale_x_continuous(
    breaks = risk_df_post$time,
    limits = c(0, max_time_shown),
    expand = c(0, 0)
  ) +
  scale_y_continuous(
    labels = percent_format(accuracy = 1),
    limits = c(0, 1),
    breaks = seq(0, 1, 0.25),
    expand = c(0.02, 0)
  ) +
  coord_cartesian(xlim = c(0, max_time_shown), clip = "off") +
  labs(x = NULL, y = "Survival after inappropriate\nICD shock") +
  theme_classic(base_size = 12) +
  theme(
    axis.text    = element_text(size = 11, colour = "black"),
    axis.title.y = element_text(size = 11, margin = margin(r = 8)),
    axis.text.x  = element_blank(),
    axis.ticks.x = element_blank(),
    axis.line    = element_line(colour = "black")
  )

# ── Risk table panel (numbers at risk + cumulative deaths + censoring) ─────
p_post_risk <- ggplot(risk_long_post, aes(x = time, y = row_label, label = value)) +
  geom_text(size = 3.8, fontface = "plain", colour = "black") +
  scale_x_continuous(
    breaks = risk_df_post$time,
    labels = year_label_lookup[as.character(risk_df_post$time)],
    limits = c(0, max_time_shown),
    expand = c(0, 0)
  ) +
  scale_y_discrete(expand = c(0.4, 0.4)) +
  coord_cartesian(xlim = c(0, max_time_shown), clip = "off") +
  labs(x = "Years since inappropriate ICD shock", y = NULL) +
  theme_classic(base_size = 12) +
  theme(
    axis.text.x  = element_text(size = 11, colour = "black"),
    axis.title.x = element_text(size = 11, margin = margin(t = 6)),
    axis.text.y  = element_text(size = 9, colour = "grey30",
                                hjust = 1, margin = margin(r = 20)),
    axis.ticks.y = element_blank(),
    axis.line.y  = element_blank(),
    axis.line.x  = element_line(colour = "black"),
    panel.grid   = element_blank()
  )

# ── Combine with forced alignment via & operator ───────────────────────────
p_post_final <- p_post_main / p_post_risk +
  plot_layout(heights = c(5, 1.6)) &
  theme(plot.margin = margin(5, 15, 5, 15))

# ── Save ───────────────────────────────────────────────────────────────────
out_post_png <- file.path(OUTDIR, "KM_FigC_survival_after_shock.png")
out_post_pdf <- file.path(OUTDIR, "KM_FigC_survival_after_shock.pdf")

study1_save_plot(p_post_final, out_post_png, out_post_pdf, width = 9, height = 5.5)

cat(sprintf("\n✓ Saved:\n  %s\n  %s\n", out_post_png, out_post_pdf))

# ── Figure legend text for manuscript (NOT embedded in figure) ─────────────
cat("\n--- Figure legend (paste into manuscript) ---\n")
cat(sprintf(
  "Supplementary Figure S1C. Kaplan-Meier survival curve anchored at the time
of first inappropriate ICD shock (t = 0), among the N = %d patients who
experienced inappropriate shock (%d deaths). The x-axis is shown in years;
follow-up is shown to %.0f days (%.1f years), the point beyond which fewer
than 10 patients remained at risk. Dashed lines represent 95%% confidence
intervals; numbers at risk, cumulative deaths, and cumulative censoring
are shown below the curve so that declines in the number at risk can be
attributed to death vs. censoring. This descriptive, within-group curve
illustrates the shape of risk after shock (e.g. front-loaded vs. flat
decline) and is exploratory given the small number of post-shock deaths.
It has no unexposed comparator and does not itself establish an excess
risk of death after shock relative to patients without shock; that
comparison is addressed by the primary time-dependent Cox model.\n",
  nrow(d_post_shock),
  sum(d_post_shock$Status_death),
  max_time_shown,
  max_time_shown / 365.25
))
