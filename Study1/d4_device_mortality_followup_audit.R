#!/usr/bin/env Rscript

# D4 audit: device-therapy ascertainment versus mortality ascertainment.
#
# Produces aggregate-only results. It never exports patient identifiers or
# patient-level data. Run from the repository root:
#   Rscript Study1/d4_device_mortality_followup_audit.R
#
# An alternative protected data root can be supplied with:
#   PROFID_LOCAL_DATA_ROOT=/path/to/data Rscript Study1/d4_device_mortality_followup_audit.R

suppressPackageStartupMessages({
  library(data.table)
  library(openxlsx)
  library(readxl)
})

repo_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
if (!dir.exists(file.path(repo_root, "Study1"))) {
  stop("Run this audit from the repository root.", call. = FALSE)
}

data_root <- Sys.getenv("PROFID_LOCAL_DATA_ROOT", unset = "")
if (!nzchar(data_root)) {
  data_root <- normalizePath(
    file.path(repo_root, "..", "..", "PROFID_RAW_DATA"),
    winslash = "/", mustWork = TRUE
  )
}

out_dir <- file.path(repo_root, "Study1", "outputs", "d4_device_mortality_followup_audit")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

as_flag <- function(x, yes = "yes") {
  tolower(trimws(as.character(x))) %in% yes
}

numeric_or_na <- function(x) suppressWarnings(as.numeric(x))

fmt_stat <- function(x, fun) {
  if (!length(x) || all(is.na(x))) return(NA_real_)
  unname(fun(x, na.rm = TRUE))
}

summarise_gap <- function(dt, cohort, population, subset, mortality_time, device_time) {
  x <- copy(dt)
  x[, gap_days := get(mortality_time) - get(device_time)]
  observed <- x[!is.na(gap_days)]

  data.table(
    cohort = cohort,
    population = population,
    subset = subset,
    mortality_time = mortality_time,
    device_time = device_time,
    n = nrow(x),
    n_gap_observed = nrow(observed),
    pct_gap_observed = if (nrow(x)) 100 * nrow(observed) / nrow(x) else NA_real_,
    n_device_before_mortality = sum(observed$gap_days > 0),
    pct_device_before_mortality = if (nrow(observed)) {
      100 * mean(observed$gap_days > 0)
    } else {
      NA_real_
    },
    n_gap_ge_30_days = sum(observed$gap_days >= 30),
    n_gap_ge_90_days = sum(observed$gap_days >= 90),
    n_gap_ge_180_days = sum(observed$gap_days >= 180),
    n_gap_ge_365_days = sum(observed$gap_days >= 365),
    total_gap_days = sum(pmax(observed$gap_days, 0)),
    median_positive_gap_days = fmt_stat(observed[gap_days > 0]$gap_days, median),
    q1_positive_gap_days = fmt_stat(observed[gap_days > 0]$gap_days, function(z, na.rm) quantile(z, .25, na.rm = na.rm)),
    q3_positive_gap_days = fmt_stat(observed[gap_days > 0]$gap_days, function(z, na.rm) quantile(z, .75, na.rm = na.rm)),
    p90_positive_gap_days = fmt_stat(observed[gap_days > 0]$gap_days, function(z, na.rm) quantile(z, .90, na.rm = na.rm)),
    max_positive_gap_days = fmt_stat(observed[gap_days > 0]$gap_days, max)
  )
}

make_analysis_flags <- function(dt, id_col, id_prefix, merged_ids, clean_ids) {
  dt[, audit_id := paste0(id_prefix, as.character(get(id_col)))]
  dt[, `:=`(
    in_merged_cohort = audit_id %in% merged_ids,
    in_clean_cohort = audit_id %in% clean_ids
  )]
  dt
}

collect_summaries <- function(dt, cohort, mortality_time, device_time) {
  groups <- list(
    source = dt,
    merged = dt[in_merged_cohort == TRUE],
    clean = dt[in_clean_cohort == TRUE]
  )

  rbindlist(lapply(names(groups), function(population) {
    d <- groups[[population]]
    rbindlist(list(
      summarise_gap(d[status_death & !status_fis], cohort, population,
                    "died with no recorded inappropriate shock", mortality_time, device_time),
      summarise_gap(d[!status_death & !status_fis], cohort, population,
                    "alive/censored with no recorded inappropriate shock", mortality_time, device_time)
    ))
  }))
}

merged <- readRDS(file.path(data_root, "derived", "Study1", "FINAL_ICD_COHORT", "icd_merged1.rds"))
clean <- readRDS(file.path(data_root, "derived", "Study1", "master_clean_dataset1.rds"))
merged_ids <- as.character(merged$ID)
clean_ids <- as.character(clean$ID)

# EU-CERT: endpoint-specific survival time for first inappropriate shock.
eu <- fread(file.path(
  data_root, "datasets", "local", "eu-cert-icd", "data", "original",
  "registry_data_eu-cert-icd_selection_161019-Data-sheet.csv"
))
eu <- eu[
  pat_diag_type == "ischemic" & pat_implant_age >= 18 &
    icd_type != "CRT-D" & ctr_name != "Karolinska Institute Stockholm"
]
eu[, `:=`(
  status_death = as_flag(death),
  status_fis = as_flag(inap_shock),
  mortality_days = numeric_or_na(length_fu_mortality),
  device_days = numeric_or_na(length_fu_inap_shock)
)]
eu <- make_analysis_flags(eu, "pat_id", "CERT_", merged_ids, clean_ids)

# HELIOS: last ICD query is explicitly distinct from clinical/mortality follow-up.
he_file <- file.path(
  data_root, "datasets", "local", "helios-rdb", "data", "original",
  "Final_delivery.2021-05-20._Ali EDxlsx.xlsx"
)
he_query <- as.data.table(read.xlsx(he_file, sheet = "ICD queries"))
he_outcome <- as.data.table(read.xlsx(he_file, sheet = "Outcome"))
he <- merge(
  he_query[, .(PAT_INDEX, inappropriate_shock, DAYS2LastQuery.ICD, DAYS2LastFU.ICD)],
  he_outcome[, .(PAT_INDEX, Death, DAYS2DEATH.ICD)],
  by = "PAT_INDEX", all = FALSE
)
he[, `:=`(
  status_death = as_flag(Death),
  status_fis = as_flag(inappropriate_shock),
  mortality_days = fifelse(as_flag(Death), numeric_or_na(DAYS2DEATH.ICD), numeric_or_na(DAYS2LastFU.ICD)),
  device_days = numeric_or_na(DAYS2LastQuery.ICD)
)]
he <- make_analysis_flags(he, "PAT_INDEX", "HELS_", merged_ids, clean_ids)

# Israeli registry: TIMEFU is last known follow-up / interrogation and TIME is
# status time. The original source workflow labels the gap in deceased patients
# as time after last ICD interrogation.
isrl <- fread(file.path(
  data_root, "datasets", "local", "israeli-icd", "data", "original", "ICDALL_20170630.csv"
))
isrl[, `:=`(
  status_death = as_flag(STATLST, yes = "died"),
  status_fis = as_flag(INASHCK1),
  mortality_days = numeric_or_na(TIME),
  device_days = numeric_or_na(TIMEFU)
)]
isrl <- make_analysis_flags(isrl, "ParentID", "ISRL_", merged_ids, clean_ids)

# PROSE: the source data field t_inappshock is the shock-endpoint censoring
# time. The original source workflow identifies this as the last ICD
# interrogation for patients without an event.
prose <- fread(file.path(
  data_root, "datasets", "local", "prose-icd", "data", "original",
  "FinaltoPROFID_PROSEonlysent_hopkins_prose_study.csv"
))
prose_join <- fread(file.path(
  data_root, "datasets", "local", "prose-icd", "data", "original",
  "FinaltoPROFID_PROSEonlysent_coenrolled.csv"
))
if (all(c("V1", "V2") %in% names(prose_join))) {
  setnames(prose_join, c("V1", "V2"), c("ID_PROSE", "ID_LVSCD"))
}
prose <- prose[!(ID %in% prose_join$ID_PROSE)]
prose[, `:=`(
  status_death = as_flag(death),
  status_fis = as_flag(inappshock),
  mortality_days = numeric_or_na(t_death),
  device_days = numeric_or_na(t_inappshock)
)]
prose <- make_analysis_flags(prose, "ID", "PRSI_", merged_ids, clean_ids)

summary_table <- rbindlist(list(
  collect_summaries(eu, "EU-CERT", "mortality_days", "device_days"),
  collect_summaries(he, "HELIOS", "mortality_days", "device_days"),
  collect_summaries(isrl, "ISRAEL", "mortality_days", "device_days"),
  collect_summaries(prose, "PROSE", "mortality_days", "device_days")
), fill = TRUE)

membership <- rbindlist(list(
  eu[, .(cohort = "EU-CERT", n_source = .N, n_merged = sum(in_merged_cohort), n_clean = sum(in_clean_cohort))],
  he[, .(cohort = "HELIOS", n_source = .N, n_merged = sum(in_merged_cohort), n_clean = sum(in_clean_cohort))],
  isrl[, .(cohort = "ISRAEL", n_source = .N, n_merged = sum(in_merged_cohort), n_clean = sum(in_clean_cohort))],
  prose[, .(cohort = "PROSE", n_source = .N, n_merged = sum(in_merged_cohort), n_clean = sum(in_clean_cohort))]
))

source_notes <- data.table(
  cohort = c("EU-CERT", "HELIOS", "ISRAEL", "PROSE"),
  mortality_source = c(
    "length_fu_mortality; death status/date fields",
    "DAYS2DEATH.ICD for deaths; DAYS2LastFU.ICD otherwise",
    "TIME / national status time; STATLST",
    "t_death / death status"
  ),
  device_followup_proxy = c(
    "length_fu_inap_shock for no recorded inappropriate shock",
    "DAYS2LastQuery.ICD",
    "TIMEFU (last known follow-up / interrogation)",
    "t_inappshock for no recorded inappropriate shock"
  ),
  data_inference = c(
    "Endpoint-specific source fields permit a direct comparison, but schedule/remote monitoring are not documented in the extract.",
    "Separate last-query and clinical-follow-up fields permit a direct comparison; remote monitoring is not documented in the extract.",
    "Direct gap comparison is possible; the legacy source script explicitly calls TIMEFU the last ICD interrogation for this purpose.",
    "Direct gap comparison is possible for no-event patients; the legacy source script explicitly calls the endpoint censoring time the last ICD interrogation."
  )
)

fwrite(summary_table, file.path(out_dir, "d4_gap_summary.csv"))
fwrite(membership, file.path(out_dir, "d4_cohort_membership.csv"))
fwrite(source_notes, file.path(out_dir, "d4_source_notes.csv"))

cat("Wrote aggregate D4 audit outputs to", out_dir, "\n")
print(membership)
print(summary_table)
