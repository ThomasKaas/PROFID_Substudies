###################### ISRAEL — Study 3: Cleaning, Events, Exclusions & Descriptives ######################

rm(list = ls())
study3_paths_file <- file.path("Study3", "study3_paths.R")
if (!file.exists(study3_paths_file)) study3_paths_file <- "study3_paths.R"
if (!file.exists(study3_paths_file)) study3_paths_file <- file.path("..", "study3_paths.R")
source(study3_paths_file)

library(data.table)
library(readxl)
library(stringr)
library(lubridate)

parse_israel_date <- function(x) {
  raw <- trimws(as.character(x))
  raw[raw == ""] <- NA_character_
  parsed <- as.IDate(rep(NA_character_, length(raw)))

  for (date_format in c("%b %d, %Y", "%d-%b-%y", "%d%b%Y", "%Y-%m-%d")) {
    missing <- is.na(parsed) & !is.na(raw)
    parsed[missing] <- suppressWarnings(as.IDate(raw[missing], format = date_format))
  }

  parsed
}

###################### 1. PATHS ######################

path_israel   <- study3_raw_path("israeli.csv")
path_smallmap <- study3_metadata_path("02_small_map.xlsx")
path_israel_endpoints <- profid_dataset_path(
  "local", "israeli-icd", "data", "working",
  "03-stage-1-endpoints-and-comp-risks.csv"
)

dt_israel <- fread(path_israel)

if (study3_debugging_enabled()) {
  study3_debug_section("Israel raw input (first duplicated preprocessing block)")
  cat("Source path: ", path_israel, "\n", sep = "")
  cat("Rows: ", nrow(dt_israel), "; columns: ", ncol(dt_israel), "\n", sep = "")
}

###################### 2. RENAME USING SMALL MAP ######################

map_small <- as.data.table(read_excel(path_smallmap, sheet = 1))

map_israel <- map_small[
  !is.na(ISRAEL) & ISRAEL != "" &
    !is.na(harmonised_name) & harmonised_name != ""
]

rename_map <- map_israel[, .(original = ISRAEL, new = harmonised_name)]

for (i in seq_len(nrow(rename_map))) {
  old <- rename_map$original[i]
  new <- rename_map$new[i]
  if (old %in% names(dt_israel)) setnames(dt_israel, old, new)
}

if (study3_debugging_enabled()) {
  study3_debug_columns(
    dt_israel,
    c("patient_id", "icd_type", "icd_implant_date", "death_date", "last_fu_date"),
    "Israel harmonised fields before date parsing (first duplicated block)"
  )
  study3_debug_section("Israel representative date strings before parsing (first duplicated block)")
  for (v in intersect(c("icd_implant_date", "death_date", "last_fu_date"), names(dt_israel))) {
    values <- unique(trimws(as.character(dt_israel[[v]])))
    values <- values[!is.na(values) & values != ""]
    cat(v, ": ", paste(utils::head(values, 15L), collapse = " | "), "\n", sep = "")
  }
}

###################### 3. ADD DEATH FLAG ######################

dt_israel[, death_flag :=
            ifelse(is.na(death_date) | death_date == "" | str_trim(death_date) == "",
                   "no", "yes")]

###################### 4. DATE PARSING ######################

dt_israel[, icd_implant_date := parse_israel_date(icd_implant_date)]
dt_israel[, death_date := parse_israel_date(death_date)]
dt_israel[, last_fu_date := parse_israel_date(last_fu_date)]

###################### 5. TIME VARIABLES ######################

dt_israel[, days_to_death := as.numeric(death_date - icd_implant_date)]

dt_israel[death_flag == "no",
          days_to_death := as.numeric(last_fu_date - icd_implant_date)]

dt_israel[days_to_death < 0, days_to_death := NA]

dt_israel[, last_fu_days := as.numeric(last_fu_date - icd_implant_date)]

###################### 6. STATUS ######################
# 0 = alive/censored
# 1 = cardiac death
# 2 = non-cardiac death

dt_israel[, status := NA_integer_]

dt_israel[death_flag == "yes" &
            sudden_cardiac_death_flag %chin% c("NO","no","No"),
          status := 2]

dt_israel[death_flag == "yes" &
            sudden_cardiac_death_flag %chin% c("YES","yes","Yes"),
          status := 1]

dt_israel[death_flag == "no", status := 0]

###################### 7. FOLLOW-UP ######################

dt_israel[, t_followup_days :=
            fifelse(death_flag %chin% c("yes","YES","Yes"),
                    days_to_death,
                    last_fu_days)
]

dt_israel[t_followup_days < 0, t_followup_days := NA]

# The raw Israel extract has sparse implant dates, so date subtraction cannot
# recover follow-up for most Study 3 participants. Use the validated Israel
# endpoint file's all-cause follow-up time (days to death or last contact).
if (!file.exists(path_israel_endpoints)) {
  stop(
    sprintf(
      "Israel endpoint file required for follow-up was not found: %s",
      path_israel_endpoints
    ),
    call. = FALSE
  )
}

dt_israel_endpoints <- fread(
  path_israel_endpoints,
  select = c("ID", "Alive_last_FU_days", "Status_death")
)
setnames(
  dt_israel_endpoints,
  c("ID", "Alive_last_FU_days", "Status_death"),
  c("patient_id", "t_followup_days_israel", "death_status_israel")
)
dt_israel_endpoints[, patient_id := suppressWarnings(as.integer(patient_id))]
dt_israel_endpoints[, t_followup_days_israel := as.numeric(t_followup_days_israel)]
dt_israel_endpoints <- unique(dt_israel_endpoints, by = "patient_id")

dt_israel[
  dt_israel_endpoints,
  on = "patient_id",
  `:=`(
    t_followup_days_israel = i.t_followup_days_israel,
    death_status_israel = i.death_status_israel
  )
]
dt_israel[
  !is.na(t_followup_days_israel) & t_followup_days_israel > 0,
  t_followup_days := t_followup_days_israel
]
dt_israel[
  !is.na(death_status_israel),
  death_flag := fifelse(death_status_israel == 1L, "yes", "no")
]
dt_israel[
  death_status_israel == 1L & !is.na(t_followup_days_israel),
  days_to_death := t_followup_days_israel
]

###################### 8. DIAGNOSTICS (UNCHANGED) ######################

dt_israel[
  death_flag == "yes",
  summary(t_followup_days == days_to_death)
]

dt_israel[
  death_flag == "no",
  summary(t_followup_days == last_fu_days)
]

###################### 9. EVENT VARIABLE SELECTION ######################

event_vars <- c(
  "patient_id",
  "status",
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
  "t_followup_days_israel",
  "sudden_cardiac_death_flag"
)

event_vars <- event_vars[event_vars %in% names(dt_israel)]
dt <- dt_israel[, ..event_vars]

###################### 10. STUDY-3 EXCLUSIONS ######################

dt <- dt[!grepl(";", icd_type)]

include_patterns <- c("single","dual","dx","icd_1","icd_2")
exclude_patterns <- c("crt","biv","bi-v","triple","plug","3")

dt <- dt[
  grepl(paste(include_patterns, collapse="|"), tolower(icd_type)) &
    !grepl(paste(exclude_patterns, collapse="|"), tolower(icd_type))
]

if ("age_icd" %in% names(dt)) {
  dt <- dt[age_icd >= 18 | is.na(age_icd)]
}
###################### ISRAEL — Study 3: Cleaning, Events, Exclusions & Descriptives ######################

rm(list = ls())
study3_paths_file <- file.path("Study3", "study3_paths.R")
if (!file.exists(study3_paths_file)) study3_paths_file <- "study3_paths.R"
if (!file.exists(study3_paths_file)) study3_paths_file <- file.path("..", "study3_paths.R")
source(study3_paths_file)

library(data.table)
library(readxl)
library(stringr)
library(lubridate)

parse_israel_date <- function(x) {
  raw <- trimws(as.character(x))
  raw[raw == ""] <- NA_character_
  parsed <- as.IDate(rep(NA_character_, length(raw)))

  for (date_format in c("%b %d, %Y", "%d-%b-%y", "%d%b%Y", "%Y-%m-%d")) {
    missing <- is.na(parsed) & !is.na(raw)
    parsed[missing] <- suppressWarnings(as.IDate(raw[missing], format = date_format))
  }

  parsed
}

###################### 1. PATHS ######################

path_israel   <- study3_raw_path("israeli.csv")
path_smallmap <- study3_metadata_path("02_small_map.xlsx")
path_israel_endpoints <- profid_dataset_path(
  "local", "israeli-icd", "data", "working",
  "03-stage-1-endpoints-and-comp-risks.csv"
)

dt_israel <- fread(path_israel)

if (study3_debugging_enabled()) {
  study3_debug_section("Israel raw input (export-producing preprocessing block)")
  cat("Source path: ", path_israel, "\n", sep = "")
  cat("Rows: ", nrow(dt_israel), "; columns: ", ncol(dt_israel), "\n", sep = "")
}

###################### 2. RENAME USING SMALL MAP ######################

map_small <- as.data.table(read_excel(path_smallmap, sheet = 1))

map_israel <- map_small[
  !is.na(ISRAEL) & ISRAEL != "" &
    !is.na(harmonised_name) & harmonised_name != ""
]

rename_map <- map_israel[, .(original = ISRAEL, new = harmonised_name)]

for (i in seq_len(nrow(rename_map))) {
  old <- rename_map$original[i]
  new <- rename_map$new[i]
  if (old %in% names(dt_israel)) setnames(dt_israel, old, new)
}

if (study3_debugging_enabled()) {
  study3_debug_columns(
    dt_israel,
    c("patient_id", "icd_type", "icd_implant_date", "death_date", "last_fu_date"),
    "Israel harmonised fields before date parsing (export-producing block)"
  )
  study3_debug_section("Israel representative date strings before parsing (export-producing block)")
  for (v in intersect(c("icd_implant_date", "death_date", "last_fu_date"), names(dt_israel))) {
    values <- unique(trimws(as.character(dt_israel[[v]])))
    values <- values[!is.na(values) & values != ""]
    cat(v, ": ", paste(utils::head(values, 15L), collapse = " | "), "\n", sep = "")
  }
}

###################### 3. ADD DEATH FLAG ######################

dt_israel[, death_flag :=
            ifelse(is.na(death_date) | death_date == "" | str_trim(death_date) == "",
                   "no", "yes")]

###################### 4. DATE PARSING ######################

dt_israel[, icd_implant_date := parse_israel_date(icd_implant_date)]
dt_israel[, death_date := parse_israel_date(death_date)]
dt_israel[, last_fu_date := parse_israel_date(last_fu_date)]

###################### 5. TIME VARIABLES ######################

dt_israel[, days_to_death := as.numeric(death_date - icd_implant_date)]

dt_israel[death_flag == "no",
          days_to_death := as.numeric(last_fu_date - icd_implant_date)]

dt_israel[days_to_death < 0, days_to_death := NA]

dt_israel[, last_fu_days := as.numeric(last_fu_date - icd_implant_date)]

###################### 6. STATUS ######################
# 0 = alive/censored
# 1 = cardiac death
# 2 = non-cardiac death

dt_israel[, status := NA_integer_]

dt_israel[death_flag == "yes" &
            sudden_cardiac_death_flag %chin% c("NO","no","No"),
          status := 2]

dt_israel[death_flag == "yes" &
            sudden_cardiac_death_flag %chin% c("YES","yes","Yes"),
          status := 1]

dt_israel[death_flag == "no", status := 0]

###################### 7. FOLLOW-UP ######################

dt_israel[, t_followup_days :=
            fifelse(death_flag %chin% c("yes","YES","Yes"),
                    days_to_death,
                    last_fu_days)
]

dt_israel[t_followup_days < 0, t_followup_days := NA]

# The raw Israel extract has sparse implant dates, so date subtraction cannot
# recover follow-up for most Study 3 participants. Use the validated Israel
# endpoint file's all-cause follow-up time (days to death or last contact).
if (!file.exists(path_israel_endpoints)) {
  stop(
    sprintf(
      "Israel endpoint file required for follow-up was not found: %s",
      path_israel_endpoints
    ),
    call. = FALSE
  )
}

dt_israel_endpoints <- fread(
  path_israel_endpoints,
  select = c("ID", "Alive_last_FU_days", "Status_death")
)
setnames(
  dt_israel_endpoints,
  c("ID", "Alive_last_FU_days", "Status_death"),
  c("patient_id", "t_followup_days_israel", "death_status_israel")
)
dt_israel_endpoints[, patient_id := suppressWarnings(as.integer(patient_id))]
dt_israel_endpoints[, t_followup_days_israel := as.numeric(t_followup_days_israel)]
dt_israel_endpoints <- unique(dt_israel_endpoints, by = "patient_id")

dt_israel[
  dt_israel_endpoints,
  on = "patient_id",
  `:=`(
    t_followup_days_israel = i.t_followup_days_israel,
    death_status_israel = i.death_status_israel
  )
]
dt_israel[
  !is.na(t_followup_days_israel) & t_followup_days_israel > 0,
  t_followup_days := t_followup_days_israel
]
dt_israel[
  !is.na(death_status_israel),
  death_flag := fifelse(death_status_israel == 1L, "yes", "no")
]
dt_israel[
  death_status_israel == 1L & !is.na(t_followup_days_israel),
  days_to_death := t_followup_days_israel
]

###################### 8. DIAGNOSTICS (UNCHANGED) ######################

dt_israel[
  death_flag == "yes",
  summary(t_followup_days == days_to_death)
]

dt_israel[
  death_flag == "no",
  summary(t_followup_days == last_fu_days)
]

###################### 9. EVENT VARIABLE SELECTION ######################

event_vars <- c(
  "patient_id",
  "status",
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
  "t_followup_days_israel",
  "sudden_cardiac_death_flag"
)

event_vars <- event_vars[event_vars %in% names(dt_israel)]
dt <- dt_israel[, ..event_vars]

###################### 10. STUDY-3 EXCLUSIONS ######################

dt <- dt[!grepl(";", icd_type)]

include_patterns <- c("single","dual","dx","icd_1","icd_2")
exclude_patterns <- c("crt","biv","bi-v","triple","plug","3")

dt <- dt[
  grepl(paste(include_patterns, collapse="|"), tolower(icd_type)) &
    !grepl(paste(exclude_patterns, collapse="|"), tolower(icd_type))
]

if ("age_icd" %in% names(dt)) {
  dt <- dt[age_icd >= 18 | is.na(age_icd)]
}

###################### 11. EXPORT ######################

dt_israel_final <- copy(dt)
if (study3_debugging_enabled()) {
  study3_debug_columns(
    dt_israel,
    c(
      "icd_implant_date", "death_date", "last_fu_date", "last_fu_days",
      "days_to_death", "t_followup_days", "days_to_inapp_shock"
    ),
    "Israel fields after date parsing and follow-up derivation"
  )
  study3_debug_section("Israel final cleaned export summary")
  print(dt_israel_final[, .(
    n = .N,
    implant_date_nonmissing = sum(!is.na(icd_implant_date)),
    last_fu_date_nonmissing = sum(!is.na(last_fu_date)),
    death_date_nonmissing = sum(!is.na(death_date)),
    followup_nonmissing = sum(!is.na(t_followup_days)),
    followup_positive = sum(!is.na(t_followup_days) & t_followup_days > 0),
    followup_nonpositive = sum(!is.na(t_followup_days) & t_followup_days <= 0),
    inapp_shock_events = sum(tolower(as.character(inapp_shock_flag)) == "yes", na.rm = TRUE),
    deaths = sum(tolower(as.character(death_flag)) == "yes", na.rm = TRUE)
  )])
  print(dt_israel_final[, .(
    n = .N,
    followup_nonmissing = sum(!is.na(t_followup_days)),
    followup_positive = sum(!is.na(t_followup_days) & t_followup_days > 0)
  ), by = death_flag][order(death_flag)])
}
dir.create(study3_derived_root(), recursive = TRUE, showWarnings = FALSE)
saveRDS(dt_israel_final, study3_derived_path("israel_events_clean.rds"))

###################### DESCRIPTIVE SNAPSHOT ######################

desc_overview <- data.table(
  n_total        = nrow(dt_israel_final),
  n_deaths       = sum(dt_israel_final$death_flag %chin% c("yes","YES","Yes"), na.rm = TRUE),
  n_cardiac      = sum(dt_israel_final$status == 1, na.rm = TRUE),
  n_noncardiac   = sum(dt_israel_final$status == 2, na.rm = TRUE),
  median_fu_days = median(dt_israel_final$t_followup_days, na.rm = TRUE),
  mean_fu_days   = mean(dt_israel_final$t_followup_days, na.rm = TRUE),
  missing_fu     = sum(is.na(dt_israel_final$t_followup_days))
)

desc_overview

########### diagnostic 

## Inappropriate shock vs follow-up
dt_israel_final[
  !is.na(days_to_inapp_shock) & !is.na(last_fu_days),
  summary(days_to_inapp_shock <= last_fu_days)
]

## Inappropriate therapy vs follow-up
dt_israel_final[
  !is.na(time_to_inap_therapy) & !is.na(last_fu_days),
  summary(time_to_inap_therapy <= last_fu_days)
]

## Death vs follow-up
dt_israel_final[
  !is.na(days_to_death) & !is.na(last_fu_days),
  summary(days_to_death <= last_fu_days)
]


# Inappropriate shock violations
dt_israel_final[
  !is.na(days_to_inapp_shock) &
  !is.na(last_fu_days) &
  days_to_inapp_shock > last_fu_days,
  .(patient_id, days_to_inapp_shock, last_fu_days)
]

# Inappropriate therapy violations
dt_israel_final[
  !is.na(time_to_inap_therapy) &
  !is.na(last_fu_days) &
  time_to_inap_therapy > last_fu_days,
  .(patient_id, time_to_inap_therapy, last_fu_days)
]

# Death violations
dt_israel_final[
  !is.na(days_to_death) &
  !is.na(last_fu_days) &
  days_to_death > last_fu_days,
  .(patient_id, days_to_death, last_fu_days)
]

