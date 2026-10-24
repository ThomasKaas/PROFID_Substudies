# Study 3 — Registry-level inappropriate-shock indicator completeness audit
#
# Produces aggregate registry counts for the final primary Cox analysis cohort.
# This script neither prints nor writes participant identifiers. The output
# contains only registry-level denominators and outcome-indicator completeness.

study3_paths_file <- file.path("Study3", "study3_paths.R")
if (!file.exists(study3_paths_file)) study3_paths_file <- "study3_paths.R"
if (!file.exists(study3_paths_file)) study3_paths_file <- file.path("..", "study3_paths.R")
source(study3_paths_file)

library(data.table)

input_file <- study3_derived_path("study3_analysis_final.rds")
output_file <- study3_output_path("endpoint_indicator_completeness_final_cohort.csv")

if (!file.exists(input_file)) {
  stop(sprintf("Final Study 3 analysis dataset was not found: %s", input_file), call. = FALSE)
}

# Retain only fields needed for aggregate endpoint completeness. No identifier
# field is selected, printed, or written to the output.
dt <- as.data.table(readRDS(input_file))
required <- c(
  "dataset", "device_group", "icd_type", "t_followup_days_final",
  "t_inapp_shock_or_censor_days", "inapp_shock_flag"
)
missing_required <- setdiff(required, names(dt))
if (length(missing_required)) {
  stop(
    sprintf("Required field(s) missing: %s", paste(missing_required, collapse = ", ")),
    call. = FALSE
  )
}
dt <- dt[, ..required]

# Match the primary Cox model's device harmonisation and cohort definition.
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

dt_primary <- dt[
  dataset %in% c("EUCERT", "HELIOS", "PROSE", "ISRAEL") &
    !is.na(device_group) &
    t_followup_days_final > 0 &
    !is.na(t_inapp_shock_or_censor_days)
]

raw_indicator_value <- tolower(trimws(as.character(dt_primary$inapp_shock_flag)))
dt_primary[, raw_indicator_missing := is.na(raw_indicator_value) |
             raw_indicator_value == ""]
dt_primary[, raw_indicator_unknown := !raw_indicator_missing &
             raw_indicator_value == "unknown"]
dt_primary[, raw_indicator_recognised := !raw_indicator_missing &
             raw_indicator_value %chin% c("yes", "no")]

summary <- dt_primary[
  ,
  .(
    eligible_final_n = .N,
    missing_indicator_n = sum(raw_indicator_missing),
    missing_indicator_pct = round(100 * mean(raw_indicator_missing), 1),
    unknown_indicator_n = sum(raw_indicator_unknown),
    unknown_indicator_pct = round(100 * mean(raw_indicator_unknown), 1),
    recognised_yes_no_n = sum(raw_indicator_recognised),
    recognised_yes_no_pct = round(100 * mean(raw_indicator_recognised), 1),
    recorded_indicator_n = sum(!raw_indicator_missing),
    recorded_indicator_pct = round(100 * mean(!raw_indicator_missing), 1)
  ),
  by = dataset
][match(c("EUCERT", "HELIOS", "ISRAEL", "PROSE"), dataset)]

dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
fwrite(summary, output_file)
print(summary)
