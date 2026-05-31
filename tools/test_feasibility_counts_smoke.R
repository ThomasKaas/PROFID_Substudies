#!/usr/bin/env Rscript

###############################################################################
# Smoke test for tools/profid_feasibility_counts.R
###############################################################################

`%||%` <- function(x, y) if (is.null(x)) y else x

cmd_args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", cmd_args, value = TRUE)
this_file <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else file.path(getwd(), "tools", "test_feasibility_counts_smoke.R")
repo_root <- normalizePath(file.path(dirname(this_file), ".."), mustWork = FALSE)
script_path <- file.path(repo_root, "tools", "profid_feasibility_counts.R")
if (!file.exists(script_path)) {
  script_path <- file.path(getwd(), "tools", "profid_feasibility_counts.R")
}

required_packages <- c(
  "data.table", "dplyr", "tidyr", "readr",
  "stringr", "purrr", "ggplot2", "digest"
)
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))
]
if (length(missing_packages)) {
  stop(
    "Smoke test requires the same packages as the production script: ",
    paste(missing_packages, collapse = ", "),
    call. = FALSE
  )
}

tmp <- tempfile("profid_feasibility_smoke_")
data_root <- file.path(tmp, "data")
output_root <- file.path(tmp, "out")
transfer_dir <- file.path(data_root, "Data_Transfer_to_Charite")
dir.create(transfer_dir, recursive = TRUE)
dir.create(output_root, recursive = TRUE)

mk <- function(ids, lvef_values) {
  data.frame(
    id = ids,
    dataset = rep(c("DB1", "DB2"), length.out = length(ids)),
    status = c(0, 1, 2, 1, 0, 2, 1, 0)[seq_along(ids)],
    survival_time = c(12, 24, -1, 48, 60, 72, 84, 96)[seq_along(ids)],
    time_zero_y = c(2001, 2002, 2003, 2004, 2010, 2011, 2016, 2017)[seq_along(ids)],
    Age = c(45, 52, 56, 49, 70, 62, 44, 54)[seq_along(ids)],
    Sex = c("M", "F", "M", "F", "M", "F", "M", "F")[seq_along(ids)],
    LVEF = lvef_values,
    eGFR = c(60, 55, 45, 70, 90, 85, 50, 65)[seq_along(ids)],
    Haemoglobin = c(13, 12, 14, 11, 15, 10, 16, 12.5)[seq_along(ids)],
    BMI = c(25, 26, 31, 28, 24, 32, 22, 27)[seq_along(ids)],
    LBBB = c(1, 0, 0, 1, 0, 0, 1, 0)[seq_along(ids)],
    RBBB = c(0, 1, 0, 0, 0, 1, 0, 0)[seq_along(ids)],
    Beta_blockers = c(1, 0, 1, 0, 1, 1, 0, 0)[seq_along(ids)],
    Digitalis = c(1, 0, 0, 1, 0, 1, 0, 0)[seq_along(ids)],
    AF = c(1, 0, 0, 1, 0, 1, 0, 0)[seq_along(ids)],
    PCI = c(1, 0, 1, 0, 0, 1, 0, 0)[seq_along(ids)],
    CABG = c(0, 1, 1, 0, 0, 0, 1, 0)[seq_along(ids)],
    PCI_acute = c(1, 0, 0, 0, 0, 1, 0, 0)[seq_along(ids)],
    CABG_acute = c(0, 1, 0, 0, 0, 0, 1, 0)[seq_along(ids)],
    fh_scd = c(1, 0, 0, 1, 0, 0, 1, 0)[seq_along(ids)],
    mi_location_anterior = c(1, 0, 1, 0, 1, 0, 1, 0)[seq_along(ids)]
  )
}

nonicd_reduced <- mk(1:4, c(0.30, 0.33, 0.28, 0.35))
nonicd_preserved <- mk(5:8, c(55, 60, 0.58, 65))
icd <- mk(101:104, c(30, 40, 45, 50))
nonicd_reduced$ICD_status <- 0
nonicd_preserved$ICD_status <- 0
icd$ICD_status <- 1
icd_all <- rbind(icd, nonicd_reduced[1, ])

utils::write.csv(nonicd_reduced, file.path(transfer_dir, "NonICD_reduced.csv"), row.names = FALSE)
utils::write.csv(nonicd_preserved, file.path(transfer_dir, "NonICD_preserved.csv"), row.names = FALSE)
utils::write.csv(icd, file.path(transfer_dir, "ICD.csv"), row.names = FALSE)
utils::write.csv(icd_all, file.path(transfer_dir, "ICD_all.csv"), row.names = FALSE)

cmd <- c(
  shQuote(script_path),
  "--data-root", shQuote(data_root),
  "--output-root", shQuote(output_root),
  "--date-stamp", "no"
)
status <- system2("Rscript", cmd)
if (!identical(status, 0L)) stop("Feasibility script failed in smoke test.", call. = FALSE)

out_dir <- file.path(output_root, "feasibility_counts")
required_outputs <- c(
  "feasibility_summary.csv",
  "global_cohort_census.csv",
  "data_contract_report.csv",
  "patient_overlap_report.csv",
  "complete_case_retention_by_idea.csv",
  "variable_map.csv",
  "red_flags.csv",
  "idea_A_egfr_hb_counts.csv",
  "idea_B_lbbb_rbbb_counts.csv",
  "idea_C_beta_blocker_preserved_counts.csv",
  "idea_D_digitalis_counts.csv",
  "idea_E_revascularization_counts.csv",
  "idea_F_young_phenotype_counts.csv",
  "run_metadata.json"
)
missing_outputs <- required_outputs[!file.exists(file.path(out_dir, required_outputs))]
if (length(missing_outputs)) {
  stop("Missing expected output(s): ", paste(missing_outputs, collapse = ", "), call. = FALSE)
}

summary <- utils::read.csv(file.path(out_dir, "feasibility_summary.csv"))
if (!all(c("A_egfr_hb", "B_lbbb_rbbb", "C_beta_blocker_preserved", "D_digitalis", "E_revascularization", "F_young_phenotype") %in% summary$idea)) {
  stop("Feasibility summary does not contain all six ideas.", call. = FALSE)
}

census <- utils::read.csv(file.path(out_dir, "global_cohort_census.csv"))
if (!any(census$source == "NonICD_reduced" & census$rows == 4)) {
  stop("Census did not preserve expected NonICD_reduced row count.", call. = FALSE)
}

red_flags <- utils::read.csv(file.path(out_dir, "red_flags.csv"))
if (!any(red_flags$type == "followup_nonpositive" & red_flags$n >= 1)) {
  stop("Expected nonpositive follow-up red flag was not emitted.", call. = FALSE)
}
if (!any(red_flags$type == "lvef_0_1_scale")) {
  stop("Expected LVEF scale audit red flag was not emitted.", call. = FALSE)
}

cc <- utils::read.csv(file.path(out_dir, "complete_case_retention_by_idea.csv"))
if (!all(cc$retention >= 0 & cc$retention <= 1, na.rm = TRUE)) {
  stop("Complete-case retention outside [0, 1].", call. = FALSE)
}

message("Smoke test passed: ", out_dir)
