# Study 3 — Continuous covariate data-quality audit
#
# Audits age, BMI, LVEF, and eGFR in the final primary Cox analysis cohort.
# It writes registry-level aggregate statistics only; no identifier field is
# selected, printed, or written.

study3_paths_file <- file.path("Study3", "study3_paths.R")
if (!file.exists(study3_paths_file)) study3_paths_file <- "study3_paths.R"
if (!file.exists(study3_paths_file)) study3_paths_file <- file.path("..", "study3_paths.R")
source(study3_paths_file)

library(data.table)

input_file <- study3_derived_path("study3_analysis_final.rds")
output_file <- study3_output_path("continuous_covariate_audit_final_cohort.csv")
completeness_output_file <- study3_output_path("continuous_covariate_completeness_final_cohort.csv")
device_missingness_output_file <- study3_output_path("continuous_covariate_missingness_by_device_final_cohort.csv")
if (!file.exists(input_file)) {
  stop(sprintf("Final Study 3 analysis dataset was not found: %s", input_file), call. = FALSE)
}

continuous_vars <- c("age_icd", "BMI", "LVEF", "eGFR")
plausibility_limits <- data.table(
  variable = continuous_vars,
  lower_bound = c(18, 8, 0, 0),
  upper_bound = c(120, 100, 100, 250)
)

# Retain only final-cohort fields and audited covariates. No identifier field
# is selected, printed, or written to the output.
dt <- as.data.table(readRDS(input_file))
required <- c(
  "dataset", "device_group", "icd_type", "t_followup_days_final",
  "t_inapp_shock_or_censor_days", continuous_vars
)
missing_required <- setdiff(required, names(dt))
if (length(missing_required)) {
  stop(
    sprintf("Required field(s) missing: %s", paste(missing_required, collapse = ", ")),
    call. = FALSE
  )
}
dt <- dt[, ..required]

# Match the primary Cox cohort definition.
dt[
  tolower(icd_type) %in% c("vvi", "icd_1", "single - single", "single chamber"),
  device_group := "Single"
]
dt[
  tolower(icd_type) %in% c("ddd", "icd_2", "dual - dual", "dual chamber"),
  device_group := "Dual"
]
dt[, t_followup_days_final := suppressWarnings(as.numeric(t_followup_days_final))]
dt[, t_inapp_shock_or_censor_days := suppressWarnings(as.numeric(t_inapp_shock_or_censor_days))]
dt <- dt[
  dataset %in% c("EUCERT", "HELIOS", "PROSE", "ISRAEL") &
    !is.na(device_group) &
    t_followup_days_final > 0 &
    !is.na(t_inapp_shock_or_censor_days)
]

audit_one <- function(x, variable, lower_bound, upper_bound) {
  raw <- trimws(as.character(x))
  numeric <- suppressWarnings(as.numeric(raw))
  blank <- is.na(x) | raw == ""
  non_numeric <- !blank & is.na(numeric)
  non_finite <- !is.na(numeric) & !is.finite(numeric)
  valid_numeric <- !is.na(numeric) & is.finite(numeric)

  data.table(
    variable = variable,
    n = length(x),
    missing_n = sum(blank),
    missing_pct = round(100 * mean(blank), 1),
    non_numeric_n = sum(non_numeric),
    non_finite_n = sum(non_finite),
    observed_numeric_n = sum(valid_numeric),
    observed_numeric_pct = round(100 * mean(valid_numeric), 1),
    below_plausible_n = sum(valid_numeric & numeric < lower_bound),
    above_plausible_n = sum(valid_numeric & numeric > upper_bound),
    minimum = if (any(valid_numeric)) min(numeric[valid_numeric]) else NA_real_,
    q1 = if (any(valid_numeric)) as.numeric(quantile(numeric[valid_numeric], 0.25)) else NA_real_,
    median = if (any(valid_numeric)) median(numeric[valid_numeric]) else NA_real_,
    mean = if (any(valid_numeric)) mean(numeric[valid_numeric]) else NA_real_,
    q3 = if (any(valid_numeric)) as.numeric(quantile(numeric[valid_numeric], 0.75)) else NA_real_,
    maximum = if (any(valid_numeric)) max(numeric[valid_numeric]) else NA_real_
  )
}

registry_audit <- rbindlist(lapply(unique(dt$dataset), function(registry) {
  d <- dt[dataset == registry]
  rbindlist(lapply(seq_len(nrow(plausibility_limits)), function(i) {
    limits <- plausibility_limits[i]
    cbind(
      data.table(registry = registry),
      audit_one(d[[limits$variable]], limits$variable, limits$lower_bound, limits$upper_bound)
    )
  }))
}))

overall_audit <- rbindlist(lapply(seq_len(nrow(plausibility_limits)), function(i) {
  limits <- plausibility_limits[i]
  cbind(
    data.table(registry = "Overall"),
    audit_one(dt[[limits$variable]], limits$variable, limits$lower_bound, limits$upper_bound)
  )
}))

audit <- rbindlist(list(overall_audit, registry_audit))
audit[, registry_order := match(registry, c("Overall", "EUCERT", "HELIOS", "ISRAEL", "PROSE"))]
setorderv(audit, c("registry_order", "variable"))
audit[, registry_order := NULL]

dt[, complete_all_four := complete.cases(.SD), .SDcols = continuous_vars]
dt[, missing_continuous_count := rowSums(is.na(.SD)), .SDcols = continuous_vars]
completeness_by_registry <- dt[
  ,
  .(
    n = .N,
    complete_all_four_n = sum(complete_all_four),
    complete_all_four_pct = round(100 * mean(complete_all_four), 1),
    any_missing_n = sum(!complete_all_four),
    any_missing_pct = round(100 * mean(!complete_all_four), 1),
    median_missing_continuous_variables = median(missing_continuous_count)
  ),
  by = dataset
]
completeness_overall <- dt[
  ,
  .(
    dataset = "Overall",
    n = .N,
    complete_all_four_n = sum(complete_all_four),
    complete_all_four_pct = round(100 * mean(complete_all_four), 1),
    any_missing_n = sum(!complete_all_four),
    any_missing_pct = round(100 * mean(!complete_all_four), 1),
    median_missing_continuous_variables = median(missing_continuous_count)
  )
]
completeness <- rbindlist(list(completeness_overall, completeness_by_registry))
completeness[, dataset_order := match(dataset, c("Overall", "EUCERT", "HELIOS", "ISRAEL", "PROSE"))]
setorderv(completeness, "dataset_order")
completeness[, dataset_order := NULL]

device_missingness <- rbindlist(lapply(c("Overall", "Dual", "Single"), function(group) {
  d <- if (group == "Overall") dt else dt[device_group == group]
  rbindlist(lapply(continuous_vars, function(variable) {
    raw <- trimws(as.character(d[[variable]]))
    missing <- is.na(d[[variable]]) | raw == ""
    data.table(
      cohort = group,
      variable = variable,
      n = nrow(d),
      missing_n = sum(missing),
      missing_pct = round(100 * mean(missing), 1),
      observed_n = sum(!missing),
      observed_pct = round(100 * mean(!missing), 1)
    )
  }))
}))
device_missingness[, cohort_order := match(cohort, c("Overall", "Dual", "Single"))]
setorderv(device_missingness, c("cohort_order", "variable"))
device_missingness[, cohort_order := NULL]

dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
fwrite(audit, output_file)
fwrite(completeness, completeness_output_file)
fwrite(device_missingness, device_missingness_output_file)
print(audit)
print(completeness)
print(device_missingness)
