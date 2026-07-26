#!/usr/bin/env Rscript

# C21 — Sparse-data bias sensitivity for the time-dependent shock estimate
#
# This is a standalone, optional sensitivity analysis.  It deliberately does
# not modify the primary-model script, its selected covariates, or its output.
# It refits the published time-dependent exposure model in each of the existing
# 20 imputed datasets with a smaller, prespecified adjustment set. Agreement
# with the primary estimate would make it less likely that the 13 exposed
# deaths are driving the shock coefficient through over-adjustment.
#
# Run from the repository root:
#   Rscript Study1/c21_sparse_data_bias_sensitivity.R
# Or, with local protected data:
#   STUDY1_LOCAL=1 Rscript Study1/c21_sparse_data_bias_sensitivity.R

required_packages <- c("data.table", "mice", "survival")
missing_packages <- required_packages[!vapply(
  required_packages, requireNamespace, logical(1), quietly = TRUE
)]
if (length(missing_packages)) {
  stop(
    "C21 requires installed R packages: ", paste(missing_packages, collapse = ", "),
    ". Install them in the analysis environment and rerun.",
    call. = FALSE
  )
}

invisible(lapply(required_packages, library, character.only = TRUE))

study1_paths_file <- file.path("Study1", "study1_paths.R")
if (!file.exists(study1_paths_file)) study1_paths_file <- "study1_paths.R"
if (!file.exists(study1_paths_file)) study1_paths_file <- file.path("..", "study1_paths.R")
if (!file.exists(study1_paths_file)) {
  stop("Could not locate Study1/study1_paths.R.", call. = FALSE)
}
source(study1_paths_file)

OUTDIR <- file.path(
  study1_output_path(), "Supplementary_data", "C21_sparse_data_bias_sensitivity"
)
dir.create(OUTDIR, recursive = TRUE, showWarnings = FALSE)

MIDS_FILE <- study1_derived_path("Imputed_data", "mice_full_object1.rds")
if (!file.exists(MIDS_FILE)) {
  stop("Required MICE object not found: ", MIDS_FILE, call. = FALSE)
}
mids_object <- readRDS(MIDS_FILE)
if (!inherits(mids_object, "mids") || mids_object$m < 2L) {
  stop("The supplied file is not a usable multiple-imputation (mids) object.", call. = FALSE)
}

# This deliberately small a priori set covers demographics (age and sex),
# cardiac disease severity (LVEF and NYHA), and renal function (eGFR). No
# data-driven selection is repeated here. DB remains a stratification factor,
# as in the primary model, rather than consuming a common baseline hazard.
core_covariates <- c(
  "Age", "bin_sex_male", "LVEF", "NYHA", "eGFR"
)
required_columns <- c(
  "ID", "DB", "Time_death_days", "Status_death", "Status_FIS", "Time_FIS_days",
  core_covariates
)
missing_columns <- setdiff(required_columns, names(mids_object$data))
if (length(missing_columns)) {
  stop(
    "C21 cannot be run because the MICE object lacks: ",
    paste(missing_columns, collapse = ", "),
    call. = FALSE
  )
}

standardise_c21_types <- function(data) {
  data <- data.table::as.data.table(data.table::copy(data))
  data[, Time_death_days := as.numeric(Time_death_days)]
  data[, Status_death := as.integer(Status_death)]
  data[, Status_FIS := as.integer(Status_FIS)]
  data[, Time_FIS_days := as.numeric(Time_FIS_days)]
  for (variable in grep("^bin_", names(data), value = TRUE)) {
    data[, (variable) := as.integer(get(variable))]
  }
  for (variable in intersect(c("Age", "LVEF", "eGFR"), names(data))) {
    data[, (variable) := as.numeric(get(variable))]
  }
  data[, NYHA := factor(as.character(NYHA))]
  data[, DB := factor(as.character(DB))]
  data
}

make_c21_time_dependent_data <- function(data) {
  data <- standardise_c21_types(data)
  data <- data[!is.na(Time_death_days) & !is.na(Status_death)]
  data <- data[order(ID)][, .SD[1L], by = ID]

  invalid_unexposed <- data[
    Status_FIS == 0L & !is.na(Time_FIS_days) & Time_FIS_days < Time_death_days,
    .N
  ]
  if (invalid_unexposed > 0L) {
    stop(
      sprintf(
        "QC failure: %d unexposed patients have a shock time before end of follow-up.",
        invalid_unexposed
      ),
      call. = FALSE
    )
  }

  data1 <- data[, c("ID", "Time_death_days", "Status_death", "DB", core_covariates),
                with = FALSE]
  data2 <- data[, c(
    "ID", "Time_death_days", "Status_death", "DB", core_covariates,
    "Status_FIS", "Time_FIS_days"
  ), with = FALSE]
  data2[, Time_FIS_td := data.table::fifelse(
    Status_FIS == 1L, Time_FIS_days, NA_real_
  )]

  long_data <- survival::tmerge(
    data1 = data1,
    data2 = data2,
    id = ID,
    death = event(Time_death_days, Status_death == 1L),
    FIS_td = tdc(Time_FIS_td)
  )
  long_data <- data.table::as.data.table(long_data)
  long_data[, tstop := pmax(tstop, 1e-7)]
  long_data <- long_data[tstop > tstart]
  data.table::setorder(long_data, ID, tstart, tstop)
  long_data
}

pool_rubin_single_coefficient <- function(estimates, variances) {
  m <- length(estimates)
  estimate <- mean(estimates)
  within_variance <- mean(variances)
  between_variance <- stats::var(estimates)
  total_variance <- within_variance + (1 + 1 / m) * between_variance
  standard_error <- sqrt(total_variance)

  data.table::data.table(
    term = "FIS_td",
    estimate = estimate,
    se = standard_error,
    HR = exp(estimate),
    lower = exp(estimate - 1.96 * standard_error),
    upper = exp(estimate + 1.96 * standard_error),
    p.value = 2 * stats::pnorm(abs(estimate / standard_error), lower.tail = FALSE),
    n_imputations = m,
    within_variance = within_variance,
    between_variance = between_variance,
    total_variance = total_variance
  )
}

formula_c21 <- stats::as.formula(paste(
  "survival::Surv(tstart, tstop, death) ~ FIS_td +",
  paste(core_covariates, collapse = " + "),
  "+ strata(DB)"
))

per_imputation <- vector("list", mids_object$m)
for (imputation in seq_len(mids_object$m)) {
  long_data <- make_c21_time_dependent_data(mice::complete(mids_object, imputation))
  fit <- try(survival::coxph(formula_c21, data = long_data, ties = "efron"), silent = TRUE)
  if (inherits(fit, "try-error") || !("FIS_td" %in% names(stats::coef(fit)))) {
    stop(
      sprintf("C21 model failed or omitted FIS_td in imputation %d.", imputation),
      call. = FALSE
    )
  }

  beta <- unname(stats::coef(fit)["FIS_td"])
  variance <- unname(stats::vcov(fit)["FIS_td", "FIS_td"])
  per_imputation[[imputation]] <- data.table::data.table(
    imputation = imputation,
    n_patients = data.table::uniqueN(long_data$ID),
    total_deaths = sum(long_data$death == 1L),
    exposed_deaths = sum(long_data$death == 1L & long_data$FIS_td == 1L),
    estimate = beta,
    se = sqrt(variance),
    HR = exp(beta),
    lower = exp(beta - 1.96 * sqrt(variance)),
    upper = exp(beta + 1.96 * sqrt(variance)),
    p.value = 2 * stats::pnorm(abs(beta / sqrt(variance)), lower.tail = FALSE)
  )
}

per_imputation <- data.table::rbindlist(per_imputation)
pooled <- pool_rubin_single_coefficient(
  estimates = per_imputation$estimate,
  variances = per_imputation$se^2
)
pooled[, `:=`(
  model = "Reduced covariate sensitivity",
  adjustment_set = paste(core_covariates, collapse = "; "),
  cohort_handling = "strata(DB)",
  exposure = "Time-dependent first inappropriate ICD shock (FIS_td)"
)]
data.table::setcolorder(pooled, c(
  "model", "exposure", "adjustment_set", "cohort_handling", "term", "estimate", "se",
  "HR", "lower", "upper", "p.value", "n_imputations", "within_variance",
  "between_variance", "total_variance"
))

data.table::fwrite(per_imputation, file.path(OUTDIR, "C21_per_imputation_FIS_td.csv"))
data.table::fwrite(pooled, file.path(OUTDIR, "C21_reduced_covariate_FIS_td.csv"))

report_file <- file.path(OUTDIR, "C21_sparse_data_bias_sensitivity.txt")
writeLines(c(
  "C21 — Sparse-data bias sensitivity for the time-dependent shock estimate",
  "",
  "Purpose: assess whether the primary FIS_td hazard ratio may be unstable because only 13 deaths occurred after exposure.",
  "This standalone sensitivity leaves the primary model and its outputs unchanged.",
  "",
  paste("Formula:", deparse(formula_c21)),
  paste("Core adjustment set:", paste(core_covariates, collapse = ", ")),
  "Cohort handling: strata(DB).",
  "Pooling: Rubin's rules across the existing multiple imputations.",
  "",
  "Pooled FIS_td result:",
  sprintf("  HR %.3f (95%% CI %.3f to %.3f), p = %.4g; %d imputations.",
          pooled$HR, pooled$lower, pooled$upper, pooled$p.value, pooled$n_imputations),
  "",
  "Interpretation: compare this estimate and interval with the primary-model FIS_td result.",
  "A materially different result signals sensitivity to covariate adjustment; agreement does not remove the intrinsic imprecision from sparse exposed deaths."
), report_file)

cat("C21 sparse-data bias sensitivity completed.\n")
cat("Pooled FIS_td HR:", sprintf("%.3f", pooled$HR),
    sprintf("(95%% CI %.3f to %.3f; p = %.4g)\n", pooled$lower, pooled$upper, pooled$p.value))
cat("Outputs:", OUTDIR, "\n")
