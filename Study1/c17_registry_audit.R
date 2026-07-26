#!/usr/bin/env Rscript

# C17 audit: registry-by-registry cohort audit table, leave-one-cohort-out
# sensitivity for the exposure coefficient, and a centre-clustering
# assessment.
#
# This is a standalone audit. It does not modify the analysis pipeline
# (scripts 1-10 or master_run.R) and it produces aggregate-only results: it
# never exports patient identifiers or patient-level data.
#
# Because it is standalone, it is also NOT re-run by master_run.R. Sections 6 and 7
# read the imputed object and replicate the primary model's specification, so both
# must be re-run after any change to script 7 or script 8. c17_provenance.csv
# records the inputs of each run so a stale audit can be spotted.
#
# Run from the repository root:
#   Rscript Study1/c17_registry_audit.R
#
# An alternative protected data root can be supplied with:
#   PROFID_LOCAL_DATA_ROOT=/path/to/data Rscript Study1/c17_registry_audit.R

suppressPackageStartupMessages({
  library(data.table)
  library(openxlsx)
  library(survival)
  library(mice)
})

# Month abbreviations are parsed below (ISRAEL IRPROCDT = "Jul 1, 2010"). Under a
# non-English LC_TIME every such date would silently become NA and the implant-year
# columns would be reported as empty, so the time locale is pinned.
suppressWarnings(Sys.setlocale("LC_TIME", "C"))

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

out_dir <- file.path(repo_root, "Study1", "outputs", "c17_registry_audit")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

msg <- function(...) cat(sprintf(...), "\n")

as_flag <- function(x, yes = "yes") {
  tolower(trimws(as.character(x))) %in% yes
}

numeric_or_na <- function(x) suppressWarnings(as.numeric(x))

EPS <- 1e-7

# ---------------------------------------------------------------------------
# 1) Load cohort products and per-registry source data
# ---------------------------------------------------------------------------

merged <- readRDS(file.path(data_root, "derived", "Study1", "FINAL_ICD_COHORT", "icd_merged1.rds"))
clean <- as.data.table(readRDS(file.path(data_root, "derived", "Study1", "master_clean_dataset1.rds")))
merged_ids <- as.character(merged$ID)
clean_ids <- as.character(clean$ID)

# Registry sources are read with the inclusion filters of the corresponding
# preprocessing script, so that "n after registry exclusions" reproduces the
# preprocessing chain. Note that these filters are NOT identical to those of the
# D4 audit: D4 applies no age filter, applies no PROSE device-type filter, and
# reads HELIOS from an "ICD queries" x "Outcome" merge rather than target_pop.
# The two audits' source counts are therefore not interchangeable.
#
# Every filter is applied through excl_step() so the ladder is written out and can
# be checked line by line against preprocessing_dataset_scripts/*_processing.R.
#
# Centre identifiers and implant years are taken from the source extracts because
# neither survives into the merged/clean datasets.

excl_log <- list()

excl_step <- function(dt, cohort, step, f) {
  n_before <- nrow(dt)
  out <- if (is.null(f)) dt else f(dt)
  excl_log[[length(excl_log) + 1L]] <<- data.table(
    cohort = cohort,
    step = step,
    n_before = n_before,
    n_after = nrow(out),
    n_excluded = if (is.null(f)) NA_integer_ else n_before - nrow(out)
  )
  out
}

# Resolve an age column by name. Used only where the raw extract column backing
# the preprocessing script's renamed `Age` is not known from the shared data
# dictionary; returns NA_character_ rather than guessing.
resolve_age_col <- function(dt, candidates) {
  hit <- intersect(candidates, names(dt))
  if (length(hit)) hit[[1]] else NA_character_
}

# EU-CERT — mirrors eucert_preprocessing.R (ischaemic; age >= 18; CRT-D excluded;
# overlap centre Karolinska excluded)
eu <- fread(file.path(
  data_root, "datasets", "local", "eu-cert-icd", "data", "original",
  "registry_data_eu-cert-icd_selection_161019-Data-sheet.csv"
))
eu_n_raw <- nrow(eu)
eu <- excl_step(eu, "CERT", "ischaemic aetiology (pat_diag_type)",
                function(d) d[pat_diag_type == "ischemic"])
eu <- excl_step(eu, "CERT", "age >= 18 (pat_implant_age)",
                function(d) d[pat_implant_age >= 18])
eu <- excl_step(eu, "CERT", "CRT-D excluded (icd_type)",
                function(d) d[icd_type != "CRT-D"])
eu <- excl_step(eu, "CERT", "overlap centre excluded (ctr_name)",
                function(d) d[ctr_name != "Karolinska Institute Stockholm"])
eu[, `:=`(
  audit_id = paste0("CERT_", gsub("-", "_", trimws(as.character(pat_id)))),
  implant_year = as.integer(format(as.Date(icd_implant_date), "%Y")),
  centre_id = as.character(ctr_name)
)]

# HELIOS — mirrors helios_processing.R (age >= 18 only; EXCLUDE_CRT is FALSE there,
# so no device-type exclusion is applied).
#
# ASSUMPTION: UNT_DATUM.ICD in the target_pop sheet is the ICD implant year. The
# column is not referenced anywhere in helios_processing.R, so this reading comes
# from the column name plus the fact that the values are plain 4-digit years
# (2005-2020) rather than Excel date serials. Verify against the HELIOS dictionary
# before quoting the implant-year row for HELIOS in the manuscript.
he_file <- file.path(
  data_root, "datasets", "local", "helios-rdb", "data", "original",
  "Final_delivery.2021-05-20._Ali EDxlsx.xlsx"
)
he <- as.data.table(read.xlsx(he_file, sheet = "target_pop"))
he_n_raw <- nrow(he)
he <- excl_step(he, "HELS", "age >= 18 (Alter.ICD)",
                function(d) d[Alter.ICD >= 18])
he[, `:=`(
  audit_id = paste0("HELS_", gsub("-", "_", trimws(as.character(PAT_INDEX)))),
  implant_year = as.integer(numeric_or_na(UNT_DATUM.ICD)),
  centre_id = NA_character_
)]

# ISRAEL (IRPROCDT = procedure/implant date "Jul 1, 2010"; NCENT = centre)
isrl <- fread(file.path(
  data_root, "datasets", "local", "israeli-icd", "data", "original", "ICDALL_20170630.csv"
))
isrl_n_raw <- nrow(isrl)
isrl[, audit_id := paste0("ISRL_", trimws(as.character(ParentID)))]
# Adult-only exclusion — mirrors israel_processing.R (EXCLUDE_AGE_LT18 = TRUE,
# EXCLUDE_CRT = FALSE). israel_processing.R filters on its renamed `Age`; the raw
# extract column is taken to be AGEPROC0 (age at procedure). Asserted rather than
# guarded by an if(): a silent skip here would inflate the ISRAEL post-exclusion
# count from 9198 back to the raw 9256 with no error.
stopifnot("AGEPROC0" %in% names(isrl))
isrl <- excl_step(isrl, "ISRL", "age >= 18 (AGEPROC0; NA age dropped)",
                  function(d) d[numeric_or_na(AGEPROC0) >= 18])
isrl[, `:=`(
  implant_year = as.integer(format(as.Date(IRPROCDT, format = "%b %d, %Y"), "%Y")),
  centre_id = as.character(NCENT)
)]

# PROSE (no calendar dates in the extract, hence no implant year)
prose <- fread(file.path(
  data_root, "datasets", "local", "prose-icd", "data", "original",
  "FinaltoPROFID_PROSEonlysent_hopkins_prose_study.csv"
))
prose_n_raw <- nrow(prose)
prose_join <- fread(file.path(
  data_root, "datasets", "local", "prose-icd", "data", "original",
  "FinaltoPROFID_PROSEonlysent_coenrolled.csv"
))
if (all(c("V1", "V2") %in% names(prose_join))) {
  setnames(prose_join, c("V1", "V2"), c("ID_PROSE", "ID_LVSCD"))
}
# prose_processing.R applies, in this order: Age >= 18, then EXCLUDE_CRT on the
# renamed ICD_type, then the co-enrolled exclusion. The age filter was previously
# omitted here, which overstated the PROSE post-exclusion count.
#
# The raw column backing the renamed `Age` is not recorded in this repository (the
# mapping lives in the external PROSE dictionary xlsx), so it is resolved by name.
# If no candidate matches, the step is logged as NOT APPLIED rather than skipped
# silently or guessed.
prose_age_col <- resolve_age_col(
  prose, c("Age", "age", "age_implant", "age_at_implant", "ageatimplant", "age_icd")
)
prose <- excl_step(
  prose, "PRSE",
  if (is.na(prose_age_col)) {
    "age >= 18 (NOT APPLIED: no age column matched in extract)"
  } else {
    sprintf("age >= 18 (%s)", prose_age_col)
  },
  if (is.na(prose_age_col)) NULL else function(d) d[numeric_or_na(get(prose_age_col)) >= 18]
)
prose <- excl_step(prose, "PRSE", "CRT excluded (device_type = ICD_type)",
                   function(d) d[device_type %in% c("SINGLE - Single", "DUAL - Dual")])
prose <- excl_step(prose, "PRSE", "co-enrolled patients excluded",
                   function(d) d[!(ID %in% prose_join$ID_PROSE)])
prose[, `:=`(
  audit_id = paste0("PRSI_", gsub("-", "_", trimws(as.character(ID)))),
  implant_year = NA_integer_,
  centre_id = NA_character_
)]

source_registries <- list(
  CERT = eu, HELS = he, ISRL = isrl, PRSE = prose
)
raw_counts <- c(CERT = eu_n_raw, HELS = he_n_raw, ISRL = isrl_n_raw, PRSE = prose_n_raw)

# Centre IDs for included patients only (used for the clustering assessment)
centre_lookup <- rbindlist(lapply(names(source_registries), function(db) {
  dt <- source_registries[[db]]
  dt[, .(audit_id, centre_id)]
}))
centre_lookup <- centre_lookup[audit_id %in% clean_ids & !is.na(centre_id) & nzchar(centre_id)]
centre_lookup <- unique(centre_lookup, by = "audit_id")

# ---------------------------------------------------------------------------
# 2) Cohort-level audit table
# ---------------------------------------------------------------------------

clean[, DB := as.character(DB)]

cohort_rows <- lapply(c("CERT", "HELS", "ISRL", "PRSE"), function(db) {
  d <- clean[DB == db]
  src <- source_registries[[db]]
  src_included <- src[audit_id %in% d$ID]

  # Join-quality assertion: implant-year summaries and centre counts below are
  # computed from src_included. Without this check a partial ID join would silently
  # summarise a subset of the analysed cohort.
  if (nrow(src_included) != nrow(d)) {
    stop(sprintf(
      paste0("Cohort %s: %d analysed patients but only %d matched back to the source ",
             "extract by audit_id. Implant-year and centre columns would be computed ",
             "on a subset; fix the audit_id construction for this registry."),
      db, nrow(d), nrow(src_included)
    ))
  }

  fis <- d$Status_FIS == 1L
  fis[is.na(fis)] <- FALSE
  # Exposed patients must have a non-missing death status, otherwise the
  # post-shock death count below silently becomes NA.
  stopifnot(!any(is.na(d$Status_death[fis])))
  post_fis_death <- fis & d$Status_death == 1L &
    !is.na(d$Time_death_days) & !is.na(d$Time_FIS_days) &
    d$Time_death_days >= d$Time_FIS_days

  implant_years <- src_included$implant_year
  implant_years <- implant_years[!is.na(implant_years)]

  data.table(
    cohort = db,
    n_raw_extract = unname(raw_counts[db]),
    n_source_after_registry_exclusions = nrow(src),
    n_merged_master_cohort = sum(merged$DB == db, na.rm = TRUE),
    n_included_analysis = nrow(d),
    implant_year_median = if (length(implant_years)) median(implant_years) else NA_real_,
    implant_year_min = if (length(implant_years)) min(implant_years) else NA_real_,
    implant_year_max = if (length(implant_years)) max(implant_years) else NA_real_,
    n_inappropriate_shocks = sum(fis),
    pct_inappropriate_shocks = round(100 * mean(fis), 2),
    n_inappropriate_shock_status_missing = sum(is.na(d$Status_FIS)),
    n_post_shock_deaths = sum(post_fis_death),
    # `Status` is the competing-risks FIRST-event variable of 10.Fine_gray.R:116
    # (0 = censored, 1 = appropriate shock, 2 = non-sudden cardiac death), so this
    # is not "patients who ever had an appropriate shock": a patient whose first
    # event was a non-sudden cardiac death is coded 2 and excluded here. The
    # denominator for the percentage excludes patients with `Status` missing,
    # unlike the inappropriate-shock and death percentages above/below, which use
    # the full cohort.
    n_first_event_appropriate_shock = sum(d$Status == 1L, na.rm = TRUE),
    pct_first_event_appropriate_shock =
      round(100 * sum(d$Status == 1L, na.rm = TRUE) / sum(!is.na(d$Status)), 2),
    n_appropriate_shock_status_missing = sum(is.na(d$Status)),
    n_deaths = sum(d$Status_death == 1L, na.rm = TRUE),
    pct_deaths = round(100 * mean(d$Status_death == 1L, na.rm = TRUE), 2),
    followup_years_median = round(median(d$Time_death_days, na.rm = TRUE) / 365.25, 2),
    followup_years_min = round(min(d$Time_death_days, na.rm = TRUE) / 365.25, 2),
    followup_years_max = round(max(d$Time_death_days, na.rm = TRUE) / 365.25, 2),
    n_centres_identified = uniqueN(centre_lookup[audit_id %in% d$ID]$centre_id)
  )
})

overall <- clean[, {
  fis <- Status_FIS == 1L
  fis[is.na(fis)] <- FALSE
  stopifnot(!any(is.na(Status_death[fis])))
  .(
    cohort = "OVERALL",
    n_raw_extract = sum(raw_counts),
    n_source_after_registry_exclusions = sum(vapply(source_registries, nrow, integer(1))),
    n_merged_master_cohort = nrow(merged),
    n_included_analysis = .N,
    implant_year_median = NA_real_,
    implant_year_min = NA_real_,
    implant_year_max = NA_real_,
    n_inappropriate_shocks = sum(fis),
    pct_inappropriate_shocks = round(100 * mean(fis), 2),
    n_inappropriate_shock_status_missing = sum(is.na(Status_FIS)),
    n_post_shock_deaths = sum(fis & Status_death == 1L &
                                !is.na(Time_death_days) & !is.na(Time_FIS_days) &
                                Time_death_days >= Time_FIS_days),
    # See the per-cohort block above: competing-risks first-event coding.
    n_first_event_appropriate_shock = sum(Status == 1L, na.rm = TRUE),
    pct_first_event_appropriate_shock =
      round(100 * sum(Status == 1L, na.rm = TRUE) / sum(!is.na(Status)), 2),
    n_appropriate_shock_status_missing = sum(is.na(Status)),
    n_deaths = sum(Status_death == 1L, na.rm = TRUE),
    pct_deaths = round(100 * mean(Status_death == 1L, na.rm = TRUE), 2),
    followup_years_median = round(median(Time_death_days, na.rm = TRUE) / 365.25, 2),
    followup_years_min = round(min(Time_death_days, na.rm = TRUE) / 365.25, 2),
    followup_years_max = round(max(Time_death_days, na.rm = TRUE) / 365.25, 2),
    n_centres_identified = uniqueN(centre_lookup$centre_id)
  )
}]

cohort_audit <- rbindlist(c(cohort_rows, list(overall)))
fwrite(cohort_audit, file.path(out_dir, "c17_cohort_audit_table.csv"))

# Exclusion ladder backing the n_source_after_registry_exclusions column, so the
# claim that these filters mirror the preprocessing scripts can be checked.
fwrite(rbindlist(excl_log), file.path(out_dir, "c17_registry_exclusion_ladder.csv"))

# ---------------------------------------------------------------------------
# 3) Missingness of every primary-model covariate, by cohort
# ---------------------------------------------------------------------------
# Primary model covariates (script 8, 07_primary_model_strata_DB.csv). For
# QRS_log1p the missingness of the raw QRS measurement is reported (the
# transform is derived passively after imputation, as in script 8/C16).

primary_covariates <- c(
  Age = "Age",
  bin_sex_male = "bin_sex_male",
  LVEF = "LVEF",
  NYHA = "NYHA",
  bin_diabetes = "bin_diabetes",
  eGFR = "eGFR",
  bin_beta_blockers = "bin_beta_blockers",
  bin_af_atrial_flutter = "bin_af_atrial_flutter",
  QRS_log1p = "QRS",
  bin_stroke_tia = "bin_stroke_tia"
)

missingness <- rbindlist(lapply(c("CERT", "HELS", "ISRL", "PRSE", "OVERALL"), function(db) {
  d <- if (db == "OVERALL") clean else clean[DB == db]
  rbindlist(lapply(names(primary_covariates), function(cv) {
    col <- primary_covariates[[cv]]
    n_miss <- if (col %in% names(d)) sum(is.na(d[[col]])) else NA_integer_
    data.table(
      cohort = db,
      model_covariate = cv,
      source_column_checked = col,
      n = nrow(d),
      n_missing = n_miss,
      pct_missing = if (is.na(n_miss)) NA_real_ else round(100 * n_miss / nrow(d), 2)
    )
  }))
}))
fwrite(missingness, file.path(out_dir, "c17_covariate_missingness_by_cohort.csv"))

# ---------------------------------------------------------------------------
# 4) Documentation matrix: follow-up sources, feature availability,
#    adjudication process (static, from the registry extracts/dictionaries)
# ---------------------------------------------------------------------------

documentation <- data.table(
  cohort = c("CERT", "HELS", "ISRL", "PRSE"),
  follow_up_source = c(
    "Registry-reported length_fu_mortality; cross-checked against lastfu_date - icd_implant_date",
    "Outcome sheet: DAYS2DEATH.ICD for deaths, DAYS2LastFU.ICD otherwise",
    "TIME / Alive_last_FU_days with STATLST (national status time)",
    "t_death; no calendar follow-up dates in the extract"
  ),
  last_device_follow_up_source = c(
    "length_fu_inap_shock (endpoint-specific shock follow-up)",
    "DAYS2LastQuery.ICD (last ICD interrogation)",
    "TIMEFU (last known follow-up / interrogation)",
    "t_inappshock (last ICD interrogation for patients without an event)"
  ),
  atp_availability = c(
    "Not available in extract",
    "Available (appropriate_ATP / inappropriate_ATP, ICD queries sheet)",
    "Available (APPATP1/INAATP1 first ATP; TOTAPATP/TOTINATP totals)",
    "Available (zones_atpused = ATP)"
  ),
  device_type_availability = c(
    "Available (icd_type; CRT-D excluded at preprocessing)",
    "Not available in extract",
    "Available (IRDEVT = Device_type; manufacturer/model also present)",
    "Available (device_type = ICD_type; CRT excluded at preprocessing)"
  ),
  programming_availability = c(
    "Not available in extract",
    "Not available in extract",
    "Available (tachy therapy zones IRTZ1-IRTZ3 with rate limits)",
    "Partial (zones_atpused therapy-zone/ATP use)"
  ),
  adjudication_process = c(
    "Not documented in the shared extract",
    "Not documented in the shared extract",
    "Not documented in the shared extract",
    "Not documented in the shared extract"
  )
)
fwrite(documentation, file.path(out_dir, "c17_documentation_matrix.csv"))

# ---------------------------------------------------------------------------
# 5) Model helpers replicated from 8.full_cohort_cox_model_and_development.R
#    (unchanged logic: standardise_types, make_td_tmerge, Rubin's rules)
# ---------------------------------------------------------------------------

standardise_types <- function(dt) {
  dt <- as.data.table(dt)
  dt[, Time_death_days := as.numeric(Time_death_days)]
  dt[, Status_death := as.integer(Status_death)]
  dt[, Status_FIS := as.integer(Status_FIS)]
  dt[, Time_FIS_days := as.numeric(Time_FIS_days)]
  for (v in grep("^bin_", names(dt), value = TRUE)) dt[, (v) := as.integer(get(v))]
  num_candidates <- c("Age", "LVEF", "eGFR", "Haemoglobin", "SBP", "BMI", "HR", "CRP_log1p")
  for (v in intersect(names(dt), num_candidates)) dt[, (v) := as.numeric(get(v))]
  if ("NYHA" %in% names(dt)) {
    nyha_levels <- levels(factor(dt$NYHA))
    dt[, NYHA := factor(as.character(NYHA), levels = nyha_levels, ordered = FALSE)]
    contrasts(dt$NYHA) <- contr.treatment(nlevels(dt$NYHA))
  }
  if ("DB" %in% names(dt)) dt[, DB := factor(as.character(DB))]
  if ("QRS" %in% names(dt) && !"QRS_log1p" %in% names(dt)) {
    dt[, QRS_log1p := log1p(as.numeric(QRS))]
  }
  dt
}

make_td_tmerge <- function(dt, vars_base) {
  dt <- as.data.table(dt)
  dt <- dt[!is.na(Time_death_days) & !is.na(Status_death)]
  dt <- dt[order(ID)][, .SD[1], by = ID]

  n_fis_qc <- dt[!is.na(Status_FIS) & Status_FIS == 0L &
                   !is.na(Time_FIS_days) &
                   Time_FIS_days < Time_death_days, .N]
  if (n_fis_qc > 0) {
    stop(sprintf("QC failure: %d unexposed patients (Status_FIS == 0) have Time_FIS_days < Time_death_days",
                 n_fis_qc))
  }

  base_cols <- c("ID", "Time_death_days", "Status_death", vars_base)
  data1 <- dt[, ..base_cols]
  d2_cols <- c("ID", "Time_death_days", "Status_death", vars_base,
               "Status_FIS", "Time_FIS_days")
  data2 <- dt[, ..d2_cols]
  data2[, Time_FIS_td := fifelse(Status_FIS == 1L, Time_FIS_days, NA_real_)]

  td <- tmerge(
    data1 = data1,
    data2 = data2,
    id = ID,
    death = event(Time_death_days, Status_death == 1),
    FIS_td = tdc(Time_FIS_td)
  )
  td <- as.data.table(td)
  td[, tstop := pmax(tstop, EPS)]
  td <- td[tstop > tstart]
  setorder(td, ID, tstart, tstop)
  td
}

pool_single_coef <- function(coef_vector, variance_vector) {
  m <- length(coef_vector)
  coef_pooled <- mean(coef_vector)
  var_within <- mean(variance_vector)
  var_between <- var(coef_vector)
  var_total <- var_within + (1 + 1 / m) * var_between
  se_pooled <- sqrt(var_total)
  z_stat <- coef_pooled / se_pooled
  p_value <- 2 * pnorm(abs(z_stat), lower.tail = FALSE)
  list(estimate = coef_pooled, se = se_pooled, p = p_value)
}

result_row <- function(beta, se) {
  data.table(
    term = "FIS_td", estimate = beta, se = se, HR = exp(beta),
    lower = exp(beta - 1.96 * se), upper = exp(beta + 1.96 * se),
    p.value = 2 * pnorm(abs(beta / se), lower.tail = FALSE)
  )
}

# Primary-model specification (script 8, Step 5b/7)
final_vars <- c("Age", "bin_sex_male", "LVEF", "NYHA", "bin_diabetes", "eGFR",
                "bin_beta_blockers", "bin_af_atrial_flutter", "QRS_log1p",
                "bin_stroke_tia")
vars_for_td_primary <- unique(c(final_vars, "DB"))
rhs_primary <- paste("FIS_td +", paste(final_vars, collapse = " + "), "+ strata(DB)")

# Drift guard. final_vars above is a copy of the set that script 8 arrives at by
# backward selection at run time; this audit deliberately does not re-run the
# selection. If script 8's adjustment set changes (C15 is queued to do exactly
# that), the copy must change with it, so the two are compared against script 8's
# own output rather than trusted. This does not alter what is fitted below.
primary_csv <- file.path(repo_root, "Study1", "outputs", "07_primary_model_strata_DB.csv")
if (file.exists(primary_csv)) {
  pm_terms <- setdiff(fread(primary_csv)$term, "FIS_td")
  pm_vars <- unique(sub("^NYHA[0-9]+$", "NYHA", pm_terms))
  if (!setequal(pm_vars, final_vars)) {
    stop(sprintf(
      paste0("C17 adjustment set is stale.\n  Script 8 fitted: %s\n  This audit has: %s\n",
             "Update final_vars in this audit to match ",
             "8.full_cohort_cox_model_and_development.R, then re-run."),
      paste(sort(pm_vars), collapse = ", "), paste(sort(final_vars), collapse = ", ")
    ))
  }
} else {
  warning("07_primary_model_strata_DB.csv not found; adjustment set could not be ",
          "checked against script 8.", call. = FALSE)
}

mice_path <- file.path(data_root, "derived", "Study1", "Imputed_data", "mice_full_object1.rds")
t_full <- readRDS(mice_path)

# ---------------------------------------------------------------------------
# 6) Leave-one-cohort-out sensitivity for the FIS_td coefficient
# ---------------------------------------------------------------------------
# Same fitting approach as the C16 sensitivity block in script 8: per
# imputation, drop one cohort, refit the primary formula, pool FIS_td with
# Rubin's rules. strata(DB) is retained; with one cohort omitted it simply
# stratifies on the remaining cohorts.

fit_fis_pooled <- function(mids_obj, formula_rhs, omit_cohort = NA_character_) {
  betas <- numeric(0)
  variances <- numeric(0)

  for (i in seq_len(mids_obj$m)) {
    dt <- standardise_types(as.data.table(complete(mids_obj, i)))
    if (!is.na(omit_cohort)) dt <- dt[as.character(DB) != omit_cohort]
    td <- try(make_td_tmerge(dt, vars_for_td_primary), silent = TRUE)
    if (inherits(td, "try-error")) next

    f <- as.formula(paste("Surv(tstart,tstop,death) ~", formula_rhs))
    fit <- try(coxph(f, data = td, ties = "efron"), silent = TRUE)
    if (inherits(fit, "try-error") || !("FIS_td" %in% names(coef(fit)))) next

    betas <- c(betas, unname(coef(fit)["FIS_td"]))
    variances <- c(variances, vcov(fit)["FIS_td", "FIS_td"])
  }

  if (length(betas) < 2L) return(NULL)
  pooled <- pool_single_coef(betas, variances)
  list(model_based = result_row(pooled$estimate, pooled$se),
       n_imputations = length(betas))
}

loco_results <- list()

full_fit <- fit_fis_pooled(t_full, rhs_primary)
loco_results[["Full cohort (primary model)"]] <- data.table(
  analysis = "Full cohort (primary model)",
  omitted_cohort = NA_character_,
  n_imputations = full_fit$n_imputations,
  full_fit$model_based[, .(HR, lower, upper, p.value)]
)

for (cohort in sort(unique(as.character(clean$DB)))) {
  fit <- fit_fis_pooled(t_full, rhs_primary, omit_cohort = cohort)
  loco_results[[cohort]] <- data.table(
    analysis = paste("Leave out cohort", cohort),
    omitted_cohort = cohort,
    n_imputations = if (is.null(fit)) 0L else fit$n_imputations,
    HR = if (is.null(fit)) NA_real_ else fit$model_based$HR,
    lower = if (is.null(fit)) NA_real_ else fit$model_based$lower,
    upper = if (is.null(fit)) NA_real_ else fit$model_based$upper,
    p.value = if (is.null(fit)) NA_real_ else fit$model_based$p.value
  )
}

loco_table <- rbindlist(loco_results, fill = TRUE)
fwrite(loco_table, file.path(out_dir, "c17_leave_one_cohort_out.csv"))

# ---------------------------------------------------------------------------
# 7) Centre-clustering assessment
# ---------------------------------------------------------------------------
# Harmonised centre IDs do not exist across cohorts: only CERT (ctr_name)
# and ISRAEL (NCENT = Centre_procedure) carry a centre identifier in the
# source extracts. Cluster-robust models are therefore fitted within those
# two cohorts only, and the limitation is recorded for the manuscript.

cluster_results <- list()
cluster_notes <- c(
  "No harmonised centre/site identifier exists across the four cohorts.",
  "Centre IDs are available only for EU-CERT (ctr_name) and ISRAEL-ICD (NCENT); HELIOS and PROSE carry no centre field in the shared extracts.",
  "Cohort-wide cluster-robust SEs on DB are not meaningful because DB has only 4 levels; the primary model instead uses strata(DB), which absorbs between-cohort differences in baseline hazard.",
  "Within-cohort sensitivity models with cluster(centre) are fitted for CERT and ISRAEL below."
)

# The loop variable is deliberately NOT called `cohort`: `cohort` is a column of
# cohort_audit, and inside `[.data.table` a column of that name would shadow the
# loop variable and silently match every row.
for (cohort_id in intersect(c("CERT", "ISRL"), unique(as.character(clean$DB)))) {
  n_centres <- uniqueN(centre_lookup[audit_id %in% clean[DB == cohort_id]$ID]$centre_id)
  betas <- numeric(0); vars_mb <- numeric(0); vars_rb <- numeric(0); n_imp <- 0L
  n_coef_cluster <- NA_integer_
  n_imp_warned <- 0L
  for (i in seq_len(t_full$m)) {
    dt <- standardise_types(as.data.table(complete(t_full, i)))
    dt <- dt[as.character(DB) == cohort_id]
    dt <- merge(dt, centre_lookup, by.x = "ID", by.y = "audit_id",
                all.x = TRUE, sort = FALSE)
    dt <- dt[!is.na(centre_id)]
    td <- try(make_td_tmerge(dt, unique(c(vars_for_td_primary, "centre_id"))),
              silent = TRUE)
    if (inherits(td, "try-error")) next
    f <- as.formula(paste("Surv(tstart,tstop,death) ~ FIS_td +",
                          paste(final_vars, collapse = " + "),
                          "+ cluster(centre_id)"))
    # Warnings are counted rather than suppressed: coxph signals possible infinite
    # coefficients (separation) here, and how often it does so is part of the
    # finding, so it is recorded instead of being described from memory.
    fit_warned <- FALSE
    cf <- withCallingHandlers(
      try(coxph(f, data = td, ties = "efron"), silent = TRUE),
      warning = function(w) {
        fit_warned <<- TRUE
        invokeRestart("muffleWarning")
      }
    )
    if (fit_warned) n_imp_warned <- n_imp_warned + 1L
    if (inherits(cf, "try-error") || !("FIS_td" %in% names(coef(cf)))) next
    # With a cluster term, cf$var is the cluster-robust variance and
    # cf$naive.var the model-based one; both lack dimnames in this survival
    # version, so extract by coefficient position.
    fis_idx <- match("FIS_td", names(coef(cf)))
    betas <- c(betas, unname(coef(cf)[fis_idx]))
    vars_mb <- c(vars_mb, cf$naive.var[fis_idx, fis_idx])
    vars_rb <- c(vars_rb, cf$var[fis_idx, fis_idx])
    n_coef_cluster <- length(coef(cf))
    n_imp <- n_imp + 1L
  }

  # Sparse-data caveat, computed from the audit table rather than written out by
  # hand, so it cannot go stale relative to the cohort it describes. Applied to
  # every fitted cohort, not only ISRAEL: CERT is equally sparse in exposed events.
  ar <- cohort_audit[which(cohort_audit$cohort == cohort_id)]
  cluster_notes <- c(cluster_notes, sprintf(
    paste0("%s within-cohort model: %d inappropriate shocks and %d post-shock deaths ",
           "across %d centres, against %s estimated coefficients. The FIS_td estimate ",
           "is descriptive only."),
    cohort_id, ar$n_inappropriate_shocks, ar$n_post_shock_deaths, n_centres,
    if (is.na(n_coef_cluster)) "the model's" else as.character(n_coef_cluster)
  ))
  if (n_imp_warned > 0L) {
    cluster_notes <- c(cluster_notes, sprintf(
      paste0("%s: coxph raised a fitting warning (typically possibly infinite ",
             "coefficients, i.e. separation) in %d of %d imputations."),
      cohort_id, n_imp_warned, t_full$m
    ))
  }

  if (length(betas) >= 2L) {
    mb <- pool_single_coef(betas, vars_mb)
    rb <- pool_single_coef(betas, vars_rb)
    cluster_results[[cohort_id]] <- data.table(
      cohort = cohort_id,
      n_centres = n_centres,
      n_imputations = n_imp,
      HR = exp(mb$estimate),
      se_model_based = mb$se,
      lower_model_based = exp(mb$estimate - 1.96 * mb$se),
      upper_model_based = exp(mb$estimate + 1.96 * mb$se),
      se_cluster_robust = rb$se,
      lower_cluster_robust = exp(rb$estimate - 1.96 * rb$se),
      upper_cluster_robust = exp(rb$estimate + 1.96 * rb$se)
    )
    # A cluster-robust SE smaller than the model-based SE is not evidence of a
    # tighter estimate: with this few clusters the sandwich estimator is
    # downward-biased, so the narrower interval must not be read as reassurance.
    if (rb$se < mb$se) {
      cluster_notes <- c(cluster_notes, sprintf(
        paste0("%s: the cluster-robust SE (%.3f) is SMALLER than the model-based SE ",
               "(%.3f). With only %d clusters and %s coefficients the sandwich ",
               "estimator is anti-conservative (no small-G correction applied), so the ",
               "narrower robust interval is an artefact of the cluster count and not a ",
               "more precise estimate."),
        cohort_id, rb$se, mb$se, n_centres,
        if (is.na(n_coef_cluster)) "the model's" else as.character(n_coef_cluster)
      ))
    }
  } else {
    cluster_notes <- c(cluster_notes, sprintf(
      "%s: cluster model could not be fitted (too few successful imputations).", cohort_id))
  }
}

if (length(cluster_results)) {
  cluster_table <- rbindlist(cluster_results, fill = TRUE)
  fwrite(cluster_table, file.path(out_dir, "c17_centre_clustering.csv"))
}

writeLines(c(
  "C17 centre-clustering assessment",
  "================================",
  "",
  cluster_notes
), file.path(out_dir, "c17_centre_clustering_limitation.txt"))

# ---------------------------------------------------------------------------
# 8) Provenance / staleness stamp
# ---------------------------------------------------------------------------
# This audit is not part of master_run.R, so a pipeline re-run regenerates
# scripts 1-10 without regenerating these outputs. The leave-one-cohort-out and
# centre-clustering tables are downstream of the imputed object and of the primary
# model's adjustment set, so both go stale silently. Recording the inputs each run
# makes a stale audit detectable by comparing timestamps.

file_mtime <- function(p) {
  if (file.exists(p)) format(file.mtime(p), "%Y-%m-%d %H:%M:%S") else NA_character_
}

provenance <- data.table(
  item = c(
    "audit_run_time",
    "mice_object_path",
    "mice_object_mtime",
    "mice_m_imputations",
    "clean_dataset_mtime",
    "merged_cohort_mtime",
    "primary_model_output_mtime",
    "adjustment_set"
  ),
  value = c(
    format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    mice_path,
    file_mtime(mice_path),
    as.character(t_full$m),
    file_mtime(file.path(data_root, "derived", "Study1", "master_clean_dataset1.rds")),
    file_mtime(file.path(data_root, "derived", "Study1", "FINAL_ICD_COHORT", "icd_merged1.rds")),
    file_mtime(primary_csv),
    paste(final_vars, collapse = " + ")
  )
)
fwrite(provenance, file.path(out_dir, "c17_provenance.csv"))

# ---------------------------------------------------------------------------
# 9) Console summary
# ---------------------------------------------------------------------------

cat("Wrote aggregate C17 audit outputs to", out_dir, "\n")
print(cohort_audit)
print(loco_table)
if (exists("cluster_table")) print(cluster_table)
cat("\nRe-run this audit after any change to script 7 (imputation) or script 8",
    "\n(primary model specification); see c17_provenance.csv.\n")
