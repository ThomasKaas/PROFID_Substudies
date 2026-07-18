###################### HELIOS — Study 3: Cleaning, Events, Exclusions ######################

rm(list = ls())
study3_paths_file <- file.path("Study3", "study3_paths.R")
if (!file.exists(study3_paths_file)) study3_paths_file <- "study3_paths.R"
if (!file.exists(study3_paths_file)) study3_paths_file <- file.path("..", "study3_paths.R")
source(study3_paths_file)

library(data.table)
library(readxl)

###################### 1. PATHS ######################

path_helios   <- study3_raw_path("Helius.xlsx")
path_smallmap <- study3_metadata_path("02_small_map.xlsx")

###################### 2. READ AND MERGE HELIOS SHEETS ######################

read_sheet_dt <- function(sheet_name) {
  as.data.table(read_excel(path_helios, sheet = sheet_name))
}

merge_unique_pat_sheet <- function(dt_main, sheet_name) {
  x <- read_sheet_dt(sheet_name)
  stopifnot("PAT_INDEX" %in% names(x))
  stopifnot(!anyDuplicated(x$PAT_INDEX))
  merge(dt_main, x, by = "PAT_INDEX", all = TRUE)
}

dt_target <- read_sheet_dt("target_pop")
stopifnot("PAT_INDEX" %in% names(dt_target))
stopifnot(!anyDuplicated(dt_target$PAT_INDEX))

dt_base <- read_sheet_dt("Baseline Characteristics")
stopifnot("PAT_INDEX" %in% names(dt_base))
stopifnot(!anyDuplicated(dt_base$PAT_INDEX))

dt_full <- merge(dt_target, dt_base, by = "PAT_INDEX", all = TRUE)
dt_full <- merge_unique_pat_sheet(dt_full, "Past Medical History (ICD10)")
dt_full <- merge_unique_pat_sheet(dt_full, "Past Medical History (OPS)")
dt_full <- merge_unique_pat_sheet(dt_full, "Medication (ATC)")
dt_full <- merge_unique_pat_sheet(dt_full, "Lab Data")
dt_full <- merge_unique_pat_sheet(dt_full, "ECG")
dt_full <- merge_unique_pat_sheet(dt_full, "ICD queries")
dt_full <- merge_unique_pat_sheet(dt_full, "Outcome")
dt_full <- merge_unique_pat_sheet(dt_full, "CMR-Scar and GZ")

# Match Study 1 duplicate handling: Imaging may have multiple rows per patient,
# so keep the first row per PAT_INDEX before merging.
dt_imaging <- read_sheet_dt("Imaging")
stopifnot("PAT_INDEX" %in% names(dt_imaging))
dt_imaging_first <- dt_imaging[order(PAT_INDEX)][, lapply(.SD, function(v) v[1]), by = PAT_INDEX]
dt_full <- merge(dt_full, dt_imaging_first, by = "PAT_INDEX", all = TRUE)

required_followup_source_vars <- c(
  "Death",
  "DAYS2DEATH.ICD",
  "DAYS2LastFU.ICD"
)
missing_followup_source_vars <- setdiff(
  required_followup_source_vars,
  names(dt_full)
)
if (length(missing_followup_source_vars)) {
  stop(
    sprintf(
      "Required HELIOS source follow-up variable(s) missing: %s",
      paste(missing_followup_source_vars, collapse = ", ")
    ),
    call. = FALSE
  )
}

# Preserve the direct source fields before the small-map renaming step.
dt_full[, helios_death_flag_source := as.character(Death)]
dt_full[, helios_death_days_source := suppressWarnings(as.numeric(DAYS2DEATH.ICD))]
dt_full[, helios_last_fu_days_source := suppressWarnings(as.numeric(DAYS2LastFU.ICD))]

###################### 3. RENAME USING SMALL MAP ######################

map_small <- as.data.table(read_excel(path_smallmap, sheet = 1))

map_helios <- map_small[
  !is.na(Helios) & Helios != "" &
    !is.na(harmonised_name) & harmonised_name != ""
]

rename_map <- map_helios[, .(original = Helios, new = harmonised_name)]

for (i in seq_len(nrow(rename_map))) {
  old <- rename_map$original[i]
  new <- rename_map$new[i]
  if (old %in% names(dt_full)) setnames(dt_full, old, new)
}

###################### 4. FOLLOW-UP DEFINITION (DIRECT DAYS) ######################

# Use the validated HELIOS day-offset variables also used in Study 1. Calendar
# year subtraction loses within-year follow-up and can therefore create
# artificial zero-day observations.
dt_full[, days_to_death := helios_death_days_source]
dt_full[, last_fu_days := helios_last_fu_days_source]

dt_full[, t_followup_days := fcase(
  tolower(trimws(helios_death_flag_source)) == "yes", days_to_death,
  tolower(trimws(helios_death_flag_source)) == "no",  last_fu_days,
  default = NA_real_
)]

dt_full[
  !is.na(t_followup_days) & !is.finite(t_followup_days),
  t_followup_days := NA_real_
]

str(dt_full)
unique(dt_full$icd_type)
###################### 5. STUDY-3 EXCLUSIONS ######################

dt <- copy(dt_full)

# Device type: KEEP ONLY exact ICD_1 (single) and ICD_2 (dual)
dt <- dt[icd_type %in% c("ICD_1", "ICD_2")]

nrow(dt)

# Age ≥ 18 (if available)
if ("age_icd" %in% names(dt)) {
  dt <- dt[age_icd >= 18 | is.na(age_icd)]
}

invalid_followup <- is.na(dt$t_followup_days) |
  !is.finite(dt$t_followup_days) |
  dt$t_followup_days <= 0

if (any(invalid_followup)) {
  cat(
    "Excluding ",
    sum(invalid_followup),
    " HELIOS row(s) with missing or non-positive direct follow-up time.\n",
    sep = ""
  )
  dt <- dt[!invalid_followup]
}

stopifnot(
  all(!is.na(dt$t_followup_days)),
  all(is.finite(dt$t_followup_days)),
  all(dt$t_followup_days > 0)
)

###################### 6. SELECT STUDY-3 EVENT VARIABLES ######################

event_vars <- c(
  "patient_id",
  "age_icd",
  "icd_type",
  "icd_implant_date",
  "inapp_shock_flag",
  "inapp_therapy",
  "Inapp_ATP",
  "days_to_inapp_shock",
  "inapp_shock_date",
  "time_to_inap_therapy",
  "time_to_inap_atp",
  "app_shock_flag",
  "app_therapy_flag",
  "app_atp_flag",
  "app_shock_date",
  "time_to_ap_atp",
  "days_to_app_shock",
  "time_to_app_therapy",
  "total_ATP",
  "total_app_shock",
  "total_inapp_ATP",
  "total_inapp_shock",
  "death_date",
  "death_type",
  "death_flag",
  "days_to_death",
  "last_fu_date",
  "last_fu_days",
  "t_followup_days",
  "sudden_cardiac_death_flag"
)

event_vars <- event_vars[event_vars %in% names(dt)]
dt_helios_final <- dt[, ..event_vars]
###################### 7. DESCRIPTIVE SNAPSHOT ######################

desc_overview <- data.table(
  n_total        = nrow(dt_helios_final),
  n_deaths       = sum(dt_helios_final$death_flag %chin% c("yes","YES","Yes"), na.rm = TRUE),
  median_fu_days = median(dt_helios_final$t_followup_days, na.rm = TRUE),
  mean_fu_days   = mean(dt_helios_final$t_followup_days, na.rm = TRUE),
  missing_fu     = sum(is.na(dt_helios_final$t_followup_days))
)

desc_overview

###################### 8. EXPORT ######################

dir.create(study3_derived_root(), recursive = TRUE, showWarnings = FALSE)
saveRDS(dt_helios_final, study3_derived_path("helios_events_clean.rds"))

