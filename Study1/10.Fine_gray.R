###############################################################################

# LANDMARK COMPETING-RISK SENSITIVITY (6/12/24m) WITH MICE — Fine & Gray (sHR)



# Description:

#   - Original and cohort-adjusted landmark Fine-Gray analyses at 6, 12,
#     and 24 months

#   - Rubin's rules pooling across 20 MICE imputations

#   - Styled conventional 1-KM and Aalen-Johansen curves per landmark (imp=1)

#   - POST-RUN QC summary and Table S2 (cohort derivation for Fine-Gray)

#

# Notes:

#   - Full cohort only (no train/test split)

#   - The original model is retained without cohort adjustment
#   - A second model adds fixed DB indicators and cohort-specific censoring
#     distributions because crr() does not support strata()

#   - NYHA binarised (III-IV=1, I-II=0); consistent with landmark Cox SAP

#   - Rule E: Time_FIS_days >= Survival_time_days => reclassified as unexposed

#   - Survival_time in MONTHS converted to DAYS (x 30.4375)

# - Continuous covariates rescaled for interpretability:

#     Age_10    = Age / 10        -> sHR per 10 years

#     LVEF_5    = LVEF / 5        -> sHR per 5% LVEF

#     eGFR_10   = eGFR / 10       -> sHR per 10 eGFR units

#     QRS_log1p = log1p(QRS)      -> sHR per unit increase in log1p(QRS)

###############################################################################

install.packages("cmprsk")

suppressPackageStartupMessages({
  
  library(mice)
  
  library(data.table)
  
  library(ggplot2)
  
  library(grid)
  
  library(gtable)
  
  library(gridExtra)
  
  library(cmprsk)  # crr, cuminc
  
})



# -------------------------- USER SETTINGS ------------------------------------



study1_paths_file <- file.path("Study1", "study1_paths.R")
if (!file.exists(study1_paths_file)) study1_paths_file <- "study1_paths.R"
if (!file.exists(study1_paths_file)) study1_paths_file <- file.path("..", "study1_paths.R")
source(study1_paths_file)

PATH_FULL <- study1_derived_path("Imputed_data", "mice_full_object1.rds")  # FULL COHORT MICE object


OUTDIR <- study1_output_path("Supplementary_data", "Fine_gray")

dir.create(OUTDIR, showWarnings = FALSE, recursive = TRUE)



# Which imputation to use for CIF figures

CIF_IMP <- 1



DAYS_PER_MONTH <- 30.4375

DB_LEVELS <- c("CERT", "HELS", "ISRL", "PRSE")



# Landmarks in months -> converted to days

LANDMARKS_MONTHS <- setNames(c(6, 12, 24), c("6m","12m","24m"))

LANDMARKS_DAYS   <- round(LANDMARKS_MONTHS * DAYS_PER_MONTH)



MIN_MODELS_FOR_POOL <- 2

MIN_EVENTS_CAUSE1   <- 2



# Variable names

VAR_TIME   <- "Survival_time"   # months (confirmed)

VAR_STATUS <- "Status"          # 0=censored, 1=appropriate shock, 2=non-sudden cardiac death

VAR_FIS    <- "Status_FIS"

VAR_TFIS   <- "Time_FIS_days"   # DAYS (confirmed: 95th pctile >> 120)



# Covariates (raw names as they appear in the imputed data)

# QRS  : raw QRS duration (ms) — log1p-transformed inside build_landmark_dt

# NYHA : raw NYHA class (numeric 1-4 OR factor/character "I","II","III","IV")

#        binarised inside build_landmark_dt to NYHA_bin (III-IV=1, I-II=0)

COVARS_RAW <- c(
  "Age", "LVEF", "eGFR",
  
  "bin_beta_blockers", "bin_diabetes", "bin_stroke_tia",
  
  "bin_af_atrial_flutter", "bin_sex_male",
  
  "QRS",   # raw — log1p transform applied inside build_landmark_dt
  
  "NYHA"   # raw — binarised inside build_landmark_dt
  
)



# Pretty labels (keyed on MODEL column names, not raw variable names)

PRETTY_LABELS <- c(
  
  "FIS_L"                  = "Inappropriate ICD shock by landmark (Yes vs No)",
  
  "Age_10"                 = "Age (per 10 years)",
  
  "LVEF_5"                 = "LVEF (per 5%)",
  
  "eGFR_10"                = "eGFR (per 10 units)",
  
  "bin_beta_blockers1"     = "Beta blockers (Yes vs No)",
  
  "bin_diabetes1"          = "Diabetes (Yes vs No)",
  
  "bin_stroke_tia1"        = "Stroke/TIA (Yes vs No)",
  
  "bin_af_atrial_flutter1" = "AF/Atrial flutter (Yes vs No)",
  
  "bin_sex_male"           = "Sex (Male vs Female)",
  
  "QRS_log1p"              = "QRS duration, log-transformed (per unit)",

  "NYHA_bin"               = "NYHA class III-IV (vs I-II)",

  "DBHELS"                 = "Cohort: HELIOS (vs EU-CERT-ICD)",

  "DBISRL"                 = "Cohort: ISRAEL-ICD (vs EU-CERT-ICD)",

  "DBPRSE"                 = "Cohort: PROSE-ICD (vs EU-CERT-ICD)"
  
)



# -------------------------- LOAD DATA ----------------------------------------



tt_full <- readRDS(PATH_FULL)

stopifnot(inherits(tt_full, "mids"))



m_full <- tt_full$m



cat(sprintf("\nLoaded: tt_full (m=%d)\n", m_full))

cat(sprintf("Output folder: %s\n\n", normalizePath(OUTDIR, winslash="/")))



# -------------------------- HELPERS ------------------------------------------



derive_FIS_L <- function(status_fis, time_fis_days, L_days) {
  
  # NOTE: Time_FIS_days is confirmed in DAYS — no unit conversion needed here.
  
  # Rule E is applied upstream in build_landmark_dt BEFORE this function runs,
  
  # so time_fis_days arriving here is already temporally valid.
  
  
  
  s <- suppressWarnings(as.integer(status_fis))
  
  t <- suppressWarnings(as.numeric(time_fis_days))
  
  
  
  # both missing => assume no inappropriate shock recorded
  
  s[is.na(s) & is.na(t)] <- 0L
  
  # status missing but time exists => assume event recorded
  
  s[is.na(s) & !is.na(t)] <- 1L
  
  
  
  # ambiguous: status says event but time missing => drop (returns NA)
  
  ambig <- (s == 1L & is.na(t))
  
  
  
  out <- as.integer(s == 1L & !is.na(t) & t <= L_days)
  
  out[ambig] <- NA_integer_
  
  out
  
}



# Helper: binarise NYHA from raw variable

#   Accepts numeric (1/2/3/4) OR character/factor ("I","II","III","IV")

#   Returns integer: III-IV = 1, I-II = 0, NA preserved

binarise_nyha <- function(x) {
  
  if (is.numeric(x) || is.integer(x)) {
    
    out <- as.integer(x >= 3)
    
    out[is.na(x)] <- NA_integer_
    
    return(out)
    
  }
  
  # Factor or character form
  
  xc  <- trimws(toupper(as.character(x)))
  
  out <- as.integer(xc %in% c("III", "IV", "3", "4"))
  
  out[is.na(x) | xc == "NA" | xc == ""] <- NA_integer_
  
  out
  
}



# -------------------------------------------------------------------------

# Build landmark dataset (days since landmark), with rescaled covariates

#

# QC steps applied (in order):

#   NA-1: Missing or zero Survival_time => excluded (no follow-up time)

#   NA-2: Missing Status => treated as censored (Status = 0)

#   Rule E: Time_FIS_days >= Survival_time_days => reclassify as unexposed

#   Landmark filter: only patients surviving beyond landmark enter analysis

#

# Derived variables (new in this version):

#   QRS_log1p = log1p(QRS)               — in-script transform from raw QRS

#   NYHA_bin  = 1 if NYHA III-IV, else 0 — binary from raw NYHA

# -------------------------------------------------------------------------

build_landmark_dt <- function(df, L_days, include_cohort = FALSE) {
  
  dt <- as.data.table(copy(df))
  
  
  
  need <- unique(c(
    VAR_TIME,
    VAR_STATUS,
    VAR_FIS,
    VAR_TFIS,
    COVARS_RAW,
    if (include_cohort) "DB"
  ))
  
  miss <- setdiff(need, names(dt))
  
  if (length(miss)) stop("Missing variables: ", paste(miss, collapse=", "))
  
  
  
  # ── NA-1: Survival_time missing or zero => exclude ──────────────────────
  
  n_before_na <- nrow(dt)
  
  dt <- dt[!is.na(get(VAR_TIME)) & as.numeric(get(VAR_TIME)) > 0]
  
  n_excl_survtime <- n_before_na - nrow(dt)
  
  if (n_excl_survtime > 0) {
    
    cat(sprintf("    [QC NA-1] Excluded %d rows: missing/zero Survival_time\n",
                
                n_excl_survtime))
    
  }
  
  if (nrow(dt) == 0) return(data.table())
  
  
  
  # ── NA-2: Missing Status => treat as censored (Status = 0) ──────────────
  
  n_status_na <- sum(is.na(dt[[VAR_STATUS]]))
  
  if (n_status_na > 0) {
    
    cat(sprintf("    [QC NA-2] %d rows with missing Status => recoded as censored (0)\n",
                
                n_status_na))
    
    dt[is.na(get(VAR_STATUS)), (VAR_STATUS) := 0L]
    
  }
  
  
  
  # ── Convert Survival_time (months) to days ───────────────────────────────
  
  dt[, time_days := as.numeric(get(VAR_TIME)) * DAYS_PER_MONTH]
  
  
  
  # ── Time_FIS_days: confirm already in days ───────────────────────────────
  
  tfis_raw <- dt[[VAR_TFIS]]
  
  q95_tfis <- suppressWarnings(
    
    as.numeric(stats::quantile(tfis_raw[!is.na(tfis_raw)], 0.95))
    
  )
  
  if (is.finite(q95_tfis) && q95_tfis <= 120) {
    
    warning(sprintf(
      
      "[UNIT CHECK] 95th pctile of %s = %.1f — looks like MONTHS, not days! Check your data.",
      
      VAR_TFIS, q95_tfis
      
    ))
    
  }
  
  dt[, tfis_days := as.numeric(get(VAR_TFIS))]  # already in days
  
  
  
  # ── Rule E: tfis_days >= time_days => reclassify as unexposed ────────────
  
  n_rule_e <- dt[get(VAR_FIS) == 1L &
                   
                   !is.na(tfis_days) &
                   
                   !is.na(time_days) &
                   
                   tfis_days >= time_days, .N]
  
  if (n_rule_e > 0) {
    
    cat(sprintf(
      
      "    [Rule E] %d exposed patients: Time_FIS_days >= Survival_time_days => reclassified as unexposed\n",
      
      n_rule_e
      
    ))
    
    dt[get(VAR_FIS) == 1L & !is.na(tfis_days) & !is.na(time_days) &
         
         tfis_days >= time_days,
       
       `:=`(Status_FIS = 0L,
            
            tfis_days  = NA_real_)]
    
  }
  
  
  
  # ── Landmark filter: survive beyond landmark ─────────────────────────────
  
  dt <- dt[time_days > L_days]
  
  if (nrow(dt) == 0) return(data.table())
  
  
  
  # ── Exposure at landmark ─────────────────────────────────────────────────
  
  dt[, FIS_L := derive_FIS_L(get(VAR_FIS), tfis_days, L_days)]
  
  dt <- dt[!is.na(FIS_L)]
  
  if (nrow(dt) == 0) return(data.table())
  
  
  
  # ── Restart clock at landmark ────────────────────────────────────────────
  
  dt[, t_landmark := time_days - L_days]
  
  dt[, Status_fg  := as.integer(get(VAR_STATUS))]  # 0/1/2

  if (include_cohort) {
    dt[, DB := factor(as.character(DB), levels = DB_LEVELS)]
    if (anyNA(dt$DB)) stop("Missing or unrecognised DB cohort code.")
  }
  
  
  
  # ── Rescale continuous predictors ────────────────────────────────────────
  
  dt[, Age_10  := as.numeric(Age)  / 10]
  
  dt[, LVEF_5  := as.numeric(LVEF) / 5]
  
  dt[, eGFR_10 := as.numeric(eGFR) / 10]
  
  
  
  # ── [NEW] QRS: log1p-transform from raw QRS (ms) ─────────────────────────
  
  # log1p(x) = log(1+x), stable for x=0; QRS in ms so values typically 80-200
  
  dt[, QRS_log1p := log1p(as.numeric(QRS))]
  
  qrs_median <- median(dt$QRS_log1p, na.rm = TRUE)
  
  cat(sprintf("    [QRS] log1p(QRS) median = %.3f (back-transformed: %.1f ms)\n",
              
              qrs_median, exp(qrs_median) - 1))
  
  
  
  # ── [NEW] NYHA: binarise to III-IV (1) vs I-II (0) ───────────────────────
  
  # crr() does not support stratification; binary coding applied instead.
  
  # Consistent with landmark Cox sensitivity analyses and pre-specified SAP.
  
  dt[, NYHA_bin := binarise_nyha(NYHA)]
  
  n_nyha_hi <- sum(dt$NYHA_bin == 1L, na.rm = TRUE)
  
  n_nyha_lo <- sum(dt$NYHA_bin == 0L, na.rm = TRUE)
  
  n_nyha_na <- sum(is.na(dt$NYHA_bin))
  
  cat(sprintf("    [NYHA] III-IV: %d | I-II: %d | NA: %d\n",
              
              n_nyha_hi, n_nyha_lo, n_nyha_na))
  
  
  
  keep <- c(
    
    "t_landmark", "Status_fg", "FIS_L",
    
    "Age_10", "LVEF_5", "eGFR_10",
    
    "bin_beta_blockers", "bin_diabetes", "bin_stroke_tia",
    
    "bin_af_atrial_flutter", "bin_sex_male",
    
    "QRS_log1p",  # [NEW]
    
    "NYHA_bin"    # [NEW]
    
  )
  
  if (include_cohort) keep <- c(keep, "DB")

  dt[, ..keep]
  
}



# Original Fine-Gray fitting function, restored verbatim.

fit_crr_return <- function(dt) {

  if (sum(dt$Status_fg == 1L, na.rm = TRUE) < MIN_EVENTS_CAUSE1) return(NULL)



  X <- model.matrix(

    ~ FIS_L + Age_10 + LVEF_5 + eGFR_10 +

      bin_beta_blockers + bin_diabetes + bin_stroke_tia +

      bin_af_atrial_flutter + bin_sex_male +

      QRS_log1p + NYHA_bin,   # [NEW]

    data = dt

  )

  if (ncol(X) >= 1 && colnames(X)[1] == "(Intercept)") X <- X[, -1, drop=FALSE]



  fit <- try(cmprsk::crr(

    ftime    = dt$t_landmark,

    fstatus  = dt$Status_fg,

    cov1     = X,

    failcode = 1,

    cencode  = 0

  ), silent = TRUE)

  if (inherits(fit, "try-error")) return(NULL)



  b     <- fit$coef

  vdiag <- diag(fit$var)

  names(vdiag) <- names(b)

  list(coef = b, vdiag = vdiag)

}



# Separate cohort-adjusted Fine-Gray fitting function.

fit_crr_return_cohort_adjusted <- function(dt) {

  if (sum(dt$Status_fg == 1L, na.rm = TRUE) < MIN_EVENTS_CAUSE1) return(NULL)

  X <- model.matrix(
    ~ FIS_L + Age_10 + LVEF_5 + eGFR_10 +
      bin_beta_blockers + bin_diabetes + bin_stroke_tia +
      bin_af_atrial_flutter + bin_sex_male +
      QRS_log1p + NYHA_bin + DB,
    data = dt
  )

  if (ncol(X) >= 1 && colnames(X)[1] == "(Intercept)") X <- X[, -1, drop=FALSE]

  fit <- try(cmprsk::crr(
    ftime = dt$t_landmark,
    fstatus = dt$Status_fg,
    cov1 = X,
    failcode = 1,
    cencode = 0,
    cengroup = dt$DB
  ), silent = TRUE)

  if (inherits(fit, "try-error")) return(NULL)
  
  
  
  b     <- fit$coef
  
  vdiag <- diag(fit$var)
  
  names(vdiag) <- names(b)
  
  list(coef = b, vdiag = vdiag)
  
}



# Rubin pooling: q_i = log(sHR), u_i = var(log(sHR))

pool_rubin <- function(q, u) {
  
  m    <- length(q)
  
  qbar <- mean(q)
  
  ubar <- mean(u)
  
  b    <- stats::var(q)
  
  Tvar <- ubar + (1 + 1/m) * b
  
  list(est = qbar, se = sqrt(Tvar))
  
}



make_pooled_table <- function(coef_list, vdiag_list) {
  
  terms <- names(coef_list[[1]])
  
  
  
  out <- rbindlist(lapply(terms, function(term) {
    
    q <- vapply(coef_list, function(b) unname(b[term]), numeric(1))
    
    u <- vapply(vdiag_list, function(v) unname(v[term]), numeric(1))
    
    if (any(!is.finite(q)) || any(!is.finite(u))) return(NULL)
    
    
    
    pu    <- pool_rubin(q, u)
    
    logHR <- pu$est
    
    se    <- pu$se
    
    
    
    HR <- exp(logHR)
    
    lo <- exp(logHR - 1.96 * se)
    
    hi <- exp(logHR + 1.96 * se)
    
    z  <- logHR / se
    
    p  <- 2 * stats::pnorm(abs(z), lower.tail = FALSE)
    
    
    
    data.table(term = term, HR = HR, CI_low = lo, CI_high = hi, p_value = p)
    
  }), fill = TRUE)
  
  
  
  if (nrow(out) == 0) return(data.table())
  
  
  
  out[, label := term]
  
  out[term %in% names(PRETTY_LABELS), label := PRETTY_LABELS[term]]
  
  out[, HR_CI  := sprintf("%.2f (%.2f-%.2f)", HR, CI_low, CI_high)]
  
  out[, p_fmt  := ifelse(p_value < 0.001, "<0.001", sprintf("%.3f", p_value))]
  
  out[]
  
}



save_table_pdf <- function(tidy_dt, file, title) {

  tab <- tidy_dt[, .(
    Variable = label,
    `sHR for cumulative incidence (95% CI)` = HR_CI,
    `p-value` = p_fmt
  )]
  
  tg  <- tableGrob(
    
    tab, rows = NULL,
    
    theme = ttheme_minimal(
      
      base_size = 11,
      
      core    = list(fg_params = list(hjust = 0, x = 0.02)),
      
      colhead = list(fg_params = list(fontface = "bold"))
      
    )
    
  )
  
  tg <- gtable_add_rows(tg,
                        
                        heights = grobHeight(textGrob(title)) + unit(3, "mm"),
                        
                        pos = 0)
  
  tg <- gtable_add_grob(tg,
                        
                        textGrob(title, gp = gpar(fontface = "bold", fontsize = 13)),
                        
                        t = 1, l = 1, r = ncol(tg))
  
  
  
  grDevices::pdf(file, width = 9,
                 
                 height = max(3.2, 0.35 * nrow(tab) + 1.2),
                 
                 useDingbats = FALSE)
  
  grid::grid.draw(tg)
  
  grDevices::dev.off()
  
}



save_finegray_plot <- function(plot, png_file, pdf_file, width, height,
                               dpi = 350) {
  unlink(c(png_file, pdf_file))

  ggplot2::ggsave(
    filename = pdf_file,
    plot = plot,
    width = width,
    height = height,
    device = grDevices::pdf
  )

  if (requireNamespace("ragg", quietly = TRUE)) {
    ggplot2::ggsave(
      filename = png_file,
      plot = plot,
      width = width,
      height = height,
      dpi = dpi,
      device = ragg::agg_png,
      bg = "white"
    )
  } else if (nzchar(Sys.which("gs"))) {
    gs_status <- system2(
      Sys.which("gs"),
      args = c(
        "-q",
        "-dSAFER",
        "-dBATCH",
        "-dNOPAUSE",
        sprintf("-r%d", dpi),
        "-sDEVICE=pngalpha",
        sprintf("-sOutputFile=%s", shQuote(png_file)),
        shQuote(pdf_file)
      )
    )
    if (!identical(gs_status, 0L) || !study1_file_ready(png_file)) {
      stop("Ghostscript failed to render PNG from the verified PDF.")
    }
  } else {
    ggplot2::ggsave(
      filename = png_file,
      plot = plot,
      width = width,
      height = height,
      dpi = dpi,
      device = grDevices::png,
      bg = "white"
    )
  }

  invisible(TRUE)
}



save_forest_plot <- function(tidy_dt, title, subtitle, out_prefix) {
  dt <- copy(tidy_dt)
  clip_max <- 10

  dt[, `:=`(
    CI_low_plot = pmax(CI_low, 1 / clip_max),
    CI_high_plot = pmin(CI_high, clip_max),
    estimate_type = ifelse(term == "FIS_L", "Exposure", "Adjustment covariate")
  )]
  dt[, label_wrapped := vapply(
    label,
    function(s) paste(strwrap(s, width = 46), collapse = "\n"),
    character(1)
  )]
  dt[, label_wrapped := factor(
    label_wrapped,
    levels = rev(unique(label_wrapped))
  )]

  p <- ggplot(dt, aes(x = HR, y = label_wrapped, color = estimate_type)) +
    geom_vline(
      xintercept = 1,
      linetype = "dashed",
      linewidth = 0.7,
      color = "#7A7A7A"
    ) +
    geom_segment(
      aes(x = CI_low_plot, xend = CI_high_plot, yend = label_wrapped),
      linewidth = 1.0,
      lineend = "round"
    ) +
    geom_point(aes(shape = estimate_type), size = 3.2, stroke = 0.9) +
    scale_x_log10(
      limits = c(1 / clip_max, clip_max),
      breaks = c(0.1, 0.25, 0.5, 1, 2, 4, 10)
    ) +
    scale_color_manual(values = c(
      "Exposure" = "#1F4E79",
      "Adjustment covariate" = "#5B6573"
    )) +
    scale_shape_manual(values = c(
      "Exposure" = 18,
      "Adjustment covariate" = 16
    )) +
    labs(
      title = title,
      subtitle = subtitle,
      x = "sHR for appropriate-shock cumulative incidence (log scale)",
      y = NULL,
      color = NULL,
      shape = NULL,
      caption = paste(
        paste0(
          "Points are pooled estimates; horizontal bars are 95% confidence ",
          "intervals.\n"
        ),
        "The Fine-Gray sHR concerns the cumulative incidence function;\n",
        "it is not an instantaneous biological hazard ratio."
      )
    ) +
    theme_classic(base_size = 12, base_family = "Helvetica") +
    theme(
      plot.title = element_text(face = "bold", size = 15, color = "#172B3A"),
      plot.subtitle = element_text(
        size = 10.5,
        color = "#4A5560",
        margin = margin(b = 10)
      ),
      plot.caption = element_text(
        size = 8.5,
        color = "#5B6573",
        hjust = 0,
        margin = margin(t = 10)
      ),
      axis.title.x = element_text(face = "bold", margin = margin(t = 8)),
      axis.text.y = element_text(size = 10.5, color = "#252A30"),
      panel.grid.major.x = element_line(color = "#E2E6EA", linewidth = 0.4),
      legend.position = "bottom",
      legend.justification = "left",
      legend.box.margin = margin(t = 5),
      plot.margin = margin(12, 16, 12, 12)
    )

  png_file <- file.path(OUTDIR, paste0(out_prefix, ".png"))
  pdf_file <- file.path(OUTDIR, paste0(out_prefix, ".pdf"))
  save_finegray_plot(
    p,
    png_file,
    pdf_file,
    width = 9.2,
    height = 7.0,
    dpi = 350
  )
}



# Landmark curves: conventional 1-KM failure estimates and
# nonparametric Aalen-Johansen cumulative-incidence estimates.

clean_curve_dt <- function(dt) {
  dt <- as.data.table(copy(dt))
  dt <- dt[
    is.finite(t_landmark) & t_landmark >= 0 &
      !is.na(Status_fg) & !is.na(FIS_L)
  ]
  if (nrow(dt) == 0) stop("Landmark curve dataset is empty.")
  dt
}

curve_group_label <- function(x) {
  ifelse(
    x == 1L,
    "Inappropriate ICD shock: Yes",
    "Inappropriate ICD shock: No"
  )
}

curve_event_label <- function(x) {
  ifelse(
    x == 1L,
    "Appropriate shock (Status = 1)",
    "Non-sudden cardiac death (Status = 2)"
  )
}

make_aj_curve_data <- function(dt) {
  dt <- clean_curve_dt(dt)

  # cuminc() returns nonparametric cumulative-incidence estimates equivalent
  # to Aalen-Johansen estimates in this competing-risk setting.
  ci <- cmprsk::cuminc(
    ftime = dt$t_landmark,
    fstatus = dt$Status_fg,
    group = dt$FIS_L
  )
  keep <- names(ci)[grepl("^[01] [12]$", names(ci))]

  long <- rbindlist(lapply(keep, function(k) {
    parts <- strsplit(k, " ")[[1]]
    obj <- ci[[k]]
    data.table(
      time = obj$time,
      estimate = obj$est,
      FIS_L = as.integer(parts[1]),
      cause = as.integer(parts[2])
    )
  }), fill = TRUE)

  long[, `:=`(
    Group = curve_group_label(FIS_L),
    Event = curve_event_label(cause)
  )]
  long[]
}

make_km_curve_data <- function(dt) {
  dt <- clean_curve_dt(dt)

  long <- rbindlist(lapply(c(1L, 2L), function(cause) {
    fit <- survival::survfit(
      survival::Surv(t_landmark, Status_fg == cause) ~ FIS_L,
      data = dt
    )
    sf <- summary(fit)
    data.table(
      time = sf$time,
      estimate = 1 - sf$surv,
      FIS_L = as.integer(sub("^FIS_L=", "", as.character(sf$strata))),
      cause = cause
    )
  }), fill = TRUE)

  baseline <- CJ(FIS_L = c(0L, 1L), cause = c(1L, 2L))[
    , `:=`(time = 0, estimate = 0)
  ]
  long <- rbindlist(list(baseline, long), use.names = TRUE, fill = TRUE)
  setorder(long, cause, FIS_L, time)
  long[, `:=`(
    Group = curve_group_label(FIS_L),
    Event = curve_event_label(cause)
  )]
  long[]
}

make_landmark_curve_plot <- function(curve_dt, dt, lm_label, method) {
  method <- match.arg(method, c("km", "aj"))

  group_levels <- c(
    "Inappropriate ICD shock: No",
    "Inappropriate ICD shock: Yes"
  )
  curve_dt[, Group := factor(Group, levels = group_levels)]
  curve_dt[, Event := factor(
    Event,
    levels = c(
      "Appropriate shock (Status = 1)",
      "Non-sudden cardiac death (Status = 2)"
    )
  )]

  cols <- c(
    "Inappropriate ICD shock: No" = "#1f77b4",
    "Inappropriate ICD shock: Yes" = "#d62728"
  )
  plot_title <- if (method == "aj") {
    sprintf("CIF (Full Cohort) - Landmark %s", lm_label)
  } else {
    sprintf("1-KM (Full Cohort) - Landmark %s", lm_label)
  }
  y_label <- if (method == "aj") {
    "Cumulative incidence (CIF)"
  } else {
    "1 - Kaplan-Meier estimate"
  }

  ggplot(curve_dt, aes(x = time, y = estimate, color = Group)) +
    geom_step(linewidth = 1.05) +
    facet_wrap(~ Event, ncol = 1, scales = "free_y") +
    scale_color_manual(values = cols) +
    labs(
      title = plot_title,
      x = "Time since landmark (days)",
      y = y_label,
      color = NULL
    ) +
    theme_minimal(base_size = 14) +
    theme(
      plot.title = element_text(face = "bold"),
      legend.position = "right",
      panel.grid.minor = element_blank()
    )
}



# -------------------------------------------------------------------------

# Landmark summary: N, exposed count, cause-1 events — logged per imputation

# -------------------------------------------------------------------------

landmark_summary <- function(d, lm_label, imp_i) {
  
  cat(sprintf(
    
    "    imp=%d | N=%d | FIS_L=1: %d | Cause-1 events: %d | Cause-2 events: %d\n",
    
    imp_i,
    
    nrow(d),
    
    sum(d$FIS_L == 1L, na.rm = TRUE),
    
    sum(d$Status_fg == 1L, na.rm = TRUE),
    
    sum(d$Status_fg == 2L, na.rm = TRUE)
    
  ))
  
}



# -------------------------- FULL COHORT POOLING ------------------------------



pool_fg_full <- function(L_days, lm_label, cohort_adjusted = FALSE) {

  coef_list  <- list()

  vdiag_list <- list()

  model_label <- if (cohort_adjusted) {
    "Cohort-adjusted Fine-Gray model"
  } else {
    "Original Fine-Gray model (no cohort adjustment)"
  }

  output_suffix <- if (cohort_adjusted) {
    sprintf("cohort_adjusted_%s", lm_label)
  } else {
    lm_label
  }

  fit_function <- if (cohort_adjusted) {
    fit_crr_return_cohort_adjusted
  } else {
    fit_crr_return
  }



  cat(sprintf("  Running %s across %d imputations...\n", model_label, m_full))
  
  
  
  for (i in 1:m_full) {
    
    d <- build_landmark_dt(
      complete(tt_full, i),
      L_days,
      include_cohort = cohort_adjusted
    )
    
    if (nrow(d) == 0) {
      
      cat(sprintf("    imp=%d: empty dataset after QC/landmark filter — skipped\n", i))
      
      next
      
    }
    
    
    
    landmark_summary(d, lm_label, i)
    
    
    
    fit_obj <- fit_function(d)
    
    if (is.null(fit_obj)) {
      
      cat(sprintf("    imp=%d: Fine-Gray not feasible (< %d cause-1 events) — skipped\n",
                  
                  i, MIN_EVENTS_CAUSE1))
      
      next
      
    }
    
    
    
    coef_list[[length(coef_list)  + 1]] <- fit_obj$coef
    
    vdiag_list[[length(vdiag_list) + 1]] <- fit_obj$vdiag
    
  }
  
  
  
  cat(sprintf("  Successful models: %d / %d\n", length(coef_list), m_full))
  
  
  
  # ── Fallback: single imputation if pooling not feasible ──────────────────
  
  if (length(coef_list) < MIN_MODELS_FOR_POOL) {
    
    cat("  Pooling not feasible — fitting imp=1 only.\n")
    
    
    
    d1 <- build_landmark_dt(
      complete(tt_full, 1),
      L_days,
      include_cohort = cohort_adjusted
    )

    fit1 <- fit_function(d1)
    
    
    
    if (is.null(fit1)) {
      
      cat("  imp=1: Fine-Gray not feasible (too few cause-1 events).\n")
      
      return(invisible(FALSE))
      
    }
    
    
    
    b  <- fit1$coef
    
    se <- sqrt(fit1$vdiag)
    
    sh <- exp(b)
    
    lo <- exp(b - 1.96 * se)
    
    hi <- exp(b + 1.96 * se)
    
    p  <- 2 * pnorm(abs(b / se), lower.tail = FALSE)
    
    
    
    res <- data.table(term = names(b), HR = sh, CI_low = lo, CI_high = hi, p_value = p)
    
    res[, label := term]
    
    res[term %in% names(PRETTY_LABELS), label := PRETTY_LABELS[term]]
    
    res[, HR_CI := sprintf("%.2f (%.2f-%.2f)", HR, CI_low, CI_high)]
    
    res[, p_fmt := ifelse(p_value < 0.001, "<0.001", sprintf("%.3f", p_value))]
    
    
    
    cat("  imp=1 results (single imputation):\n")
    
    print(res[, .(label, HR_CI, p_fmt)], row.names = FALSE)
    
    return(invisible(TRUE))
    
  }
  
  
  
  # ── Pool with Rubin's rules ───────────────────────────────────────────────
  
  pooled_dt <- make_pooled_table(coef_list, vdiag_list)
  
  
  
  title_tab <- sprintf(
    "%s: %s landmark (NYHA binary, QRS log1p, m=%d)",
    model_label,
    lm_label,
    length(coef_list)
  )

  pdf_file <- file.path(
    OUTDIR,
    sprintf("FULL_sHR_table_%s.pdf", output_suffix)
  )
  
  
  
  save_table_pdf(pooled_dt, pdf_file, title_tab)
  
  save_forest_plot(
    
    pooled_dt,
    
    title = sprintf("Fine-Gray estimates: %s landmark", lm_label),

    subtitle = if (cohort_adjusted) {
      "Adjusted for clinical covariates and cohort; cohort-specific censoring distributions"
    } else {
      "Adjusted for clinical covariates; original specification without cohort adjustment"
    },

    out_prefix = sprintf("FULL_forest_%s", output_suffix)
    
  )
  
  
  
  fis <- pooled_dt[term == "FIS_L"]
  
  if (nrow(fis) == 1) {
    
    cat(sprintf(
      "  FIS_L sHR for appropriate-shock cumulative incidence: %s, p=%s\n",
      fis$HR_CI, fis$p_fmt
    ))
    
  }
  
  cat(sprintf("  Saved table: %s\n", pdf_file))
  
  invisible(pooled_dt)

}



# Conventional 1-KM and nonparametric Aalen-Johansen figures from imp=1.

save_plot_variants <- function(plot, output_prefixes, width = 7.8, height = 7.8) {
  for (output_prefix in output_prefixes) {
    png_file <- file.path(OUTDIR, paste0(output_prefix, ".png"))
    pdf_file <- file.path(OUTDIR, paste0(output_prefix, ".pdf"))
    save_finegray_plot(
      plot,
      png_file,
      pdf_file,
      width = width,
      height = height,
      dpi = 350
    )
  }
}

save_landmark_figures_full <- function(L_days, lm_label) {

  d <- build_landmark_dt(complete(tt_full, CIF_IMP), L_days)

  if (nrow(d) > 0) {

    km_plot <- make_landmark_curve_plot(
      make_km_curve_data(d),
      d,
      lm_label,
      method = "km"
    )
    aj_plot <- make_landmark_curve_plot(
      make_aj_curve_data(d),
      d,
      lm_label,
      method = "aj"
    )

    save_plot_variants(
      km_plot,
      sprintf("FULL_KM_CIF_%s", lm_label)
    )
    save_plot_variants(
      aj_plot,
      c(
        sprintf("FULL_AJ_CIF_%s", lm_label),
        sprintf("FULL_CIF_%s", lm_label)
      )
    )

    cat(sprintf(
      paste0(
        "  Saved conventional 1-KM curves: FULL_KM_CIF_%s.png/.pdf\n",
        "  Saved Aalen-Johansen curves: FULL_AJ_CIF_%s.png/.pdf ",
        "(legacy alias FULL_CIF_%s.png/.pdf)\n"
      ),
      lm_label,
      lm_label,
      lm_label
    ))

  } else {

    cat("  Landmark curves: empty dataset — skipped.\n")

  }
  
}



# -------------------------- RUN ----------------------------------------------



cat("=== Fine-Gray Landmark Competing Risks — Full Cohort ===\n")

cat(sprintf("Rule E:  Time_FIS_days >= Survival_time_days => reclassified as unexposed\n"))

cat(sprintf("NA-1:    Missing/zero Survival_time => excluded\n"))

cat(sprintf("NA-2:    Missing Status => recoded as censored (0)\n"))

cat(sprintf("QRS:     log1p-transformed inside build_landmark_dt from raw QRS\n"))

cat(sprintf("NYHA:    binarised to III-IV (1) vs I-II (0) inside build_landmark_dt\n"))

cat(sprintf("Models:  original specification retained; cohort-adjusted specification added\n"))

cat(sprintf("Cohort:  adjusted model uses DB indicators and cohort-specific censoring distributions\n"))

cat(sprintf(
  "sHR:     association with the cumulative incidence function, not an instantaneous biological hazard\n\n"
))



for (lm_label in names(LANDMARKS_DAYS)) {
  
  L_days <- unname(LANDMARKS_DAYS[[lm_label]])
  
  cat(sprintf("=== Landmark %s (L=%d days; %.0f months) ===\n",
              
              lm_label, L_days, LANDMARKS_MONTHS[[lm_label]]))
  
  
  
  pool_fg_full(L_days, lm_label, cohort_adjusted = FALSE)

  pool_fg_full(L_days, lm_label, cohort_adjusted = TRUE)

  save_landmark_figures_full(L_days, lm_label)
  
  cat("\n")
  
}



cat("Done.\n")

cat(sprintf("All outputs saved to: %s\n", normalizePath(OUTDIR, winslash = "/")))






# -------------------------------------------------------------------------
# POST-RUN QC SUMMARY
# Runs after all modelling is complete — does NOT modify any model objects,
# imputed data, or outputs. Read-only diagnostic using imp=1 only.
# Safe to remove or comment out without affecting any results.
# -------------------------------------------------------------------------
cat("\n\n=== POST-RUN QC SUMMARY (read-only, imp=1) ===\n")

tryCatch({
  
  qcr_raw  <- as.data.table(complete(tt_full, 1))
  N_total  <- nrow(qcr_raw)
  
  # ── Step 1: Survival_time exclusions ──────────────────────────────────────
  n_excl_st <- qcr_raw[is.na(get(VAR_TIME)) | as.numeric(get(VAR_TIME)) <= 0, .N]
  qcr       <- qcr_raw[!is.na(get(VAR_TIME)) & as.numeric(get(VAR_TIME)) > 0]
  N_base    <- nrow(qcr)
  
  # ── Step 2: Missing Status — recoded, not excluded ────────────────────────
  n_status_na <- qcr[is.na(get(VAR_STATUS)), .N]
  qcr[is.na(get(VAR_STATUS)), (VAR_STATUS) := 0L]
  
  # ── Step 3: Time conversion ───────────────────────────────────────────────
  qcr[, time_days := as.numeric(get(VAR_TIME)) * DAYS_PER_MONTH]
  qcr[, tfis_days := as.numeric(get(VAR_TFIS))]
  qcr_pre_rule_e <- copy(qcr)
  
  # ── Step 4: Rule E — reclassify, not exclude ──────────────────────────────
  n_rule_e <- qcr[get(VAR_FIS) == 1L &
                    !is.na(tfis_days) & !is.na(time_days) &
                    tfis_days >= time_days, .N]
  qcr[get(VAR_FIS) == 1L & !is.na(tfis_days) & !is.na(time_days) &
        tfis_days >= time_days,
      `:=`(Status_FIS = 0L, tfis_days = NA_real_)]
  
  # ── Step 5: Ambiguous FIS ─────────────────────────────────────────────────
  n_ambig  <- qcr[get(VAR_FIS) == 1L & is.na(tfis_days), .N]
  n_exposed <- qcr[get(VAR_FIS) == 1L & !is.na(tfis_days), .N]

  # ── C5 audit: same-day FIS versus the secondary endpoint ───────────────
  # Counts are taken before Rule E, among patients eligible at each landmark.
  # Survival time and exposure are not imputed, so imp=1 is sufficient for
  # this aggregate-only audit. Rule E then reclassifies these ties as
  # unexposed; no ordering is inferred from same-day records.
  c5_same_day_audit <- rbindlist(lapply(names(LANDMARKS_DAYS), function(lm_label) {
    L_days <- unname(LANDMARKS_DAYS[[lm_label]])
    eligible <- qcr_pre_rule_e[
      get(VAR_FIS) == 1L & !is.na(tfis_days) & !is.na(time_days) &
        time_days > L_days
    ]

    n_same_day <- eligible[tfis_days == time_days, .N]
    n_after    <- eligible[tfis_days > time_days, .N]

    data.table(
      Landmark = lm_label,
      Landmark_days = L_days,
      N_same_day_FIS_secondary_endpoint = n_same_day,
      N_FIS_after_secondary_endpoint = n_after,
      N_FIS_at_or_after_secondary_endpoint = n_same_day + n_after
    )
  }))
  fwrite(c5_same_day_audit,
         file.path(OUTDIR, "C5_same_day_FIS_secondary_endpoint_audit.csv"))
  cat("✓ C5 same-day FIS audit saved: C5_same_day_FIS_secondary_endpoint_audit.csv\n")
  print(c5_same_day_audit)
  
  # ── Print full-cohort summary ─────────────────────────────────────────────
  cat(sprintf("\n%-50s %6d\n", "Full imputed cohort (imp=1):",         N_total))
  cat(sprintf("%-50s %6d\n",   "  Excluded: missing/zero Survival_time:", n_excl_st))
  cat(sprintf("%-50s %6d\n",   "  Remaining base cohort:",              N_base))
  cat(sprintf("%-50s %6d\n",   "  Missing Status => censored (kept):",  n_status_na))
  cat(sprintf("%-50s %6d\n",   "  Rule E => reclassified unexposed (kept):", n_rule_e))
  cat(sprintf("%-50s %6d\n",   "  Ambiguous FIS => dropped per landmark:", n_ambig))
  cat(sprintf("%-50s %6d\n",   "  Valid exposed patients:",             n_exposed))
  
  
  # -------------------------------------------------------------------------
  
  # Table S2 — Cohort derivation for Fine-Gray analyses (gt)
  
  # -------------------------------------------------------------------------
  
  if (exists("N_total") && exists("n_exposed")) {
    
    
    
    library(gt)
    
    
    
    table_S2 <- data.frame(
      
      Step   = c("1", "2", "3", "4", "5", "6"),
      
      Reason = c(
        
        "Starting cohort from primary analysis",
        
        "Missing or zero survival time",
        
        "Remaining cohort available for Fine-Gray analyses",
        
        "Missing outcome status but valid survival time",
        
        "First inappropriate shock recorded at or after end of survival time",
        
        "Valid exposed patients available for Fine-Gray landmark analyses"
        
      ),
      
      `How patients were handled` = c(
        
        "All patients carried forward to Fine-Gray analysis",
        
        "Excluded \u2014 survival time is required to define the competing risks outcome",
        
        "Retained",
        
        "Treated as censored and retained",
        
        "Reclassified as unexposed and retained \u2014 shock was not recorded before the secondary endpoint",
        
        "Final exposed count used in all Fine-Gray models"
        
      ),
      
      `N patients` = c(format(N_total, big.mark=","), as.character(n_excl_st),
                       
                       format(N_base, big.mark=","),  as.character(n_status_na),
                       
                       as.character(n_rule_e),         as.character(n_exposed)),
      
      check.names = FALSE, stringsAsFactors = FALSE
      
    ) |>
      
      gt() |>
      
      tab_header(title = "Table S2. Cohort derivation for Fine\u2013Gray competing risks analyses") |>
      
      cols_align(align = "center", columns = c(Step, `N patients`)) |>
      
      cols_align(align = "left",   columns = c(Reason, `How patients were handled`)) |>
      
      tab_style(style = cell_borders(sides = "top",    color = "black", weight = px(2)), locations = cells_column_labels()) |>
      
      tab_style(style = cell_borders(sides = "bottom", color = "black", weight = px(2)), locations = cells_column_labels()) |>
      
      tab_style(style = cell_borders(sides = "bottom", color = "black", weight = px(2)), locations = cells_body(rows = 6)) |>
      
      tab_footnote(
        
        footnote = paste0(
          
          "All steps applied prior to landmark competing risks analyses. Survival time represents the time from ICD implantation ",
          
          "to the first recorded event (appropriate ICD therapy or death) or censoring. The final exposed count of ", n_exposed,
          
          " differs from the 67 exposed patients in the primary Cox analysis because ", n_rule_e,
          
          " patients had their first inappropriate shock recorded at or beyond their survival time and were therefore reclassified as unexposed. ",
          
          "Counts are based on the first imputed dataset; minor variation across imputations is possible due to covariate imputation, ",
          
          "as exposure and survival time were not imputed."
          
        ),
        
        locations = cells_column_labels(columns = Reason)
        
      ) |>
      
      tab_options(table.font.names = "Arial", table.font.size = px(11), table.width = px(620),
                  
                  column_labels.font.weight = "bold", footnotes.font.size = px(9))
    
    
    
    gtsave(table_S2, file.path(OUTDIR, "TableS2_FineGray_CohortDerivation.html"), inline_css = TRUE)
    
    cat("\u2713 Table S2 saved: TableS2_FineGray_CohortDerivation.html\n")
    
    
    
  }

  # ── C9 supplementary table: landmark event counts and follow-up ─────────
  # Read-only reporting overlay based on the same imp=1 data used for CIFs.
  # It does not alter Fine-Gray eligibility, model fitting, or CIF figures.
  cif_at_one_year <- function(d, group, cause) {
    ci <- cmprsk::cuminc(
      ftime = d$t_landmark,
      fstatus = d$Status_fg,
      group = d$FIS_L
    )
    key <- sprintf("%d %d", group, cause)
    if (!(key %in% names(ci))) return(NA_real_)

    curve <- ci[[key]]
    index <- findInterval(365, curve$time)
    if (index == 0L) return(0)
    curve$est[[index]]
  }

  qcr_for_report <- copy(qcr)
  qcr_for_report[, (VAR_TFIS) := tfis_days]

  c9_finegray_table <- rbindlist(lapply(names(LANDMARKS_DAYS), function(lm_label) {
    L_days <- unname(LANDMARKS_DAYS[[lm_label]])
    d <- build_landmark_dt(qcr_for_report, L_days)
    n_prior_appropriate <- qcr[
      get(VAR_STATUS) == 1L & time_days <= L_days,
      .N
    ]

    rbindlist(lapply(c(0L, 1L), function(group) {
      d_group <- d[FIS_L == group]
      followup <- d_group$t_landmark
      data.table(
        Landmark = lm_label,
        `Eligible N` = nrow(d),
        `Prior inappropriate shock, n` = sum(d$FIS_L == 1L),
        `Prior appropriate shock excluded, n` = n_prior_appropriate,
        `Exposure group` = ifelse(group == 1L, "Prior inappropriate shock", "No prior inappropriate shock"),
        `N in exposure group` = nrow(d_group),
        `Subsequent appropriate-shock events, n` = sum(d_group$Status_fg == 1L),
        `Non-sudden cardiac deaths, n` = sum(d_group$Status_fg == 2L),
        `Follow-up from landmark, median days (IQR)` = sprintf(
          "%.0f (%.0f–%.0f)",
          stats::median(followup),
          stats::quantile(followup, 0.25, names = FALSE),
          stats::quantile(followup, 0.75, names = FALSE)
        ),
        `1-year cumulative incidence of appropriate shock, %` = round(
          100 * cif_at_one_year(d, group, 1L), 1
        ),
        `1-year cumulative incidence of non-sudden cardiac death, %` = round(
          100 * cif_at_one_year(d, group, 2L), 1
        )
      )
    }))
  }))

  fwrite(c9_finegray_table,
         file.path(OUTDIR, "TableS7_C9_FineGray_LandmarkEventCounts.csv"))
  gtsave(
    gt::gt(c9_finegray_table) |>
      gt::tab_header(
        title = "Table S7. Landmark competing-risk event counts and follow-up"
      ) |>
      gt::tab_source_note(
        source_note = paste(
          "Read-only reporting summary from imputation 1.",
          paste(
            "Appropriate-shock cumulative incidence treats non-sudden cardiac",
            "death (Status = 2) as the competing event."
          ),
          "Prior appropriate shock is identified from Status = 1 at or before the landmark."
        )
      ),
    filename = file.path(OUTDIR, "TableS7_C9_FineGray_LandmarkEventCounts.html"),
    inline_css = TRUE
  )
  cat("✓ C9 table saved: TableS7_C9_FineGray_LandmarkEventCounts.csv/.html\n")

  # ── Per-landmark at-risk table ────────────────────────────────────────────
  cat(sprintf(
    "\n%-8s  %9s  %9s  %9s  %13s  %13s\n",
    "Landmark", "N_at_risk", "N_unexpos", "N_exposed",
    "Cause1_events", "Cause2_events"
  ))
  cat(strrep("-", 72), "\n")
  
  for (lm_label in names(LANDMARKS_DAYS)) {
    L_days <- unname(LANDMARKS_DAYS[[lm_label]])
    lm_dt  <- qcr[time_days > L_days]
    
    # derive FIS_L
    s <- suppressWarnings(as.integer(lm_dt[[VAR_FIS]]))
    t <- lm_dt$tfis_days
    s[is.na(s) & is.na(t)]  <- 0L
    s[is.na(s) & !is.na(t)] <- 1L
    fis_l <- as.integer(s == 1L & !is.na(t) & t <= L_days)
    fis_l[s == 1L & is.na(t)] <- NA_integer_
    
    lm_dt[, FIS_L_q     := fis_l]
    lm_dt[, Status_fg_q := as.integer(get(VAR_STATUS))]
    lm_valid <- lm_dt[!is.na(FIS_L_q)]
    
    n_at_risk  <- nrow(lm_valid)
    n_exp      <- sum(lm_valid$FIS_L_q == 1L, na.rm = TRUE)
    n_unexp    <- sum(lm_valid$FIS_L_q == 0L, na.rm = TRUE)
    n_cause1   <- sum(lm_valid$Status_fg_q == 1L, na.rm = TRUE)
    n_cause2   <- sum(lm_valid$Status_fg_q == 2L, na.rm = TRUE)
    
    cat(sprintf("%-8s  %9d  %9d  %9d  %13d  %13d\n",
                lm_label, n_at_risk, n_unexp, n_exp, n_cause1, n_cause2))
  }
  
  cat(strrep("-", 72), "\n")
  cat("NOTE: Based on imp=1 only. Counts may vary slightly across imputations\n")
  cat("      due to imputation of covariates (not outcomes or exposure).\n")
  cat("      Exposure (Status_FIS) and Survival_time are not imputed.\n")
  cat("=== END POST-RUN QC SUMMARY ===\n")
  
}, error = function(e) {
  cat(sprintf("POST-RUN QC SUMMARY failed: %s\n", conditionMessage(e)))
  cat("This does not affect any model results.\n")
})




