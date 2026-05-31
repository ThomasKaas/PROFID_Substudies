#!/usr/bin/env Rscript

###############################################################################
# PROFID feasibility counts
#
# Counts data availability and event support for proposed Non-ICD follow-up
# analyses. The script writes aggregate feasibility reports only; it does not fit
# models, impute data, or export patient-level extracts.
###############################################################################

args <- commandArgs(trailingOnly = TRUE)

print_usage <- function() {
  cat(
    "Usage:\n",
    "  Rscript tools/profid_feasibility_counts.R \\\n",
    "    --data-root /path/to/profid-data \\\n",
    "    --output-root /path/to/profid-outputs \\\n",
    "    --date-stamp yes\n",
    "\nOptions:\n",
    "  --data-root       Root containing Data_Transfer_to_Charite.\n",
    "  --output-root     Root for generated feasibility output.\n",
    "  --transfer-dir    Override transfer directory directly.\n",
    "  --out-dir         Override final output directory directly.\n",
    "  --date-stamp      yes/no; append timestamp to default out-dir. Default yes.\n",
    "  --help            Show this message.\n",
    sep = ""
  )
}

if ("--help" %in% args || "-h" %in% args) {
  print_usage()
  quit(status = 0)
}

get_arg <- function(name, default = NULL) {
  flag <- paste0("--", name)
  hit <- which(args == flag)
  if (!length(hit)) return(default)
  if (hit[[1]] == length(args)) return(default)
  args[[hit[[1]] + 1L]]
}

yes_arg <- function(name, default = FALSE) {
  value <- get_arg(name, if (default) "yes" else "no")
  tolower(trimws(value)) %in% c("yes", "true", "1", "y")
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
    paste0(
      "Missing required R package(s): ",
      paste(missing_packages, collapse = ", "),
      ". Install them in the active R library before running this script."
    ),
    call. = FALSE
  )
}

timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")

resolve_roots <- function() {
  data_root <- get_arg(
    "data-root",
    Sys.getenv(
      "PROFID_DATA_ROOT",
      unset = "/sc-projects/sc-proj-dhzc-profid/PROFID_Substudies/data"
    )
  )
  output_root <- get_arg(
    "output-root",
    Sys.getenv("PROFID_OUTPUT_ROOT", unset = file.path(data_root, "derived"))
  )
  transfer_dir <- get_arg(
    "transfer-dir",
    file.path(data_root, "Data_Transfer_to_Charite")
  )
  out_dir <- get_arg("out-dir", NULL)
  if (is.null(out_dir)) {
    leaf <- if (yes_arg("date-stamp", TRUE)) {
      file.path("feasibility_counts", timestamp)
    } else {
      "feasibility_counts"
    }
    out_dir <- file.path(output_root, leaf)
  }
  list(
    data_root = normalizePath(data_root, winslash = "/", mustWork = FALSE),
    output_root = normalizePath(output_root, winslash = "/", mustWork = FALSE),
    transfer_dir = normalizePath(transfer_dir, winslash = "/", mustWork = FALSE),
    out_dir = normalizePath(out_dir, winslash = "/", mustWork = FALSE)
  )
}

roots <- resolve_roots()

is_placeholder_path <- function(path) {
  grepl("^/pfad/zum|^/path/to", path)
}

if (is_placeholder_path(roots$data_root) || is_placeholder_path(roots$output_root)) {
  stop(
    paste(
      "PROFID_DATA_ROOT/PROFID_OUTPUT_ROOT still contain example placeholder paths.",
      "Set them to the real mounted HPC directories before running.",
      "Example discovery command:",
      "find /sc-projects -type d -name Data_Transfer_to_Charite 2>/dev/null | head",
      sep = "\n"
    ),
    call. = FALSE
  )
}

if (!dir.exists(roots$transfer_dir)) {
  stop(
    paste(
      "Transfer directory does not exist:",
      roots$transfer_dir,
      "Set --data-root to the parent directory that contains Data_Transfer_to_Charite,",
      "or pass --transfer-dir directly.",
      sep = "\n"
    ),
    call. = FALSE
  )
}

dir.create(roots$out_dir, recursive = TRUE, showWarnings = FALSE)

message("Data root: ", roots$data_root)
message("Transfer dir: ", roots$transfer_dir)
message("Output dir: ", roots$out_dir)

read_any_table <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (ext == "csv") {
    return(as.data.frame(data.table::fread(path, data.table = FALSE, showProgress = FALSE)))
  }
  if (ext == "rds") {
    obj <- readRDS(path)
    if (!is.data.frame(obj)) stop("RDS is not a data frame: ", path, call. = FALSE)
    return(as.data.frame(obj))
  }
  stop("Unsupported input extension: ", path, call. = FALSE)
}

write_csv <- function(x, path) {
  data.table::fwrite(as.data.frame(x), path, na = "")
}

as_num_safely <- function(x) {
  suppressWarnings(as.numeric(as.character(x)))
}

lvef_percent <- function(x) {
  xx <- as_num_safely(x)
  ifelse(!is.na(xx) & xx > 0 & xx <= 1.5, xx * 100, xx)
}

min_or_na <- function(x) {
  if (is.null(x) || !length(x) || all(is.na(x))) return(NA_real_)
  min(x, na.rm = TRUE)
}

max_or_na <- function(x) {
  if (is.null(x) || !length(x) || all(is.na(x))) return(NA_real_)
  max(x, na.rm = TRUE)
}

quantile_or_na <- function(x, prob) {
  xx <- x[!is.na(x)]
  if (!length(xx)) return(NA_real_)
  as.numeric(stats::quantile(xx, prob, na.rm = TRUE, names = FALSE))
}

make_quartile <- function(x) {
  xx <- as_num_safely(x)
  breaks <- unique(stats::quantile(xx, probs = seq(0, 1, 0.25), na.rm = TRUE, names = FALSE))
  if (length(breaks) < 2) return(factor(rep("All", length(xx))))
  cut(xx, breaks, include.lowest = TRUE)
}

not_blank <- function(x) {
  !is.na(x) & trimws(as.character(x)) != ""
}

to_bin01 <- function(x) {
  if (is.null(x)) return(integer(0))
  if (is.logical(x)) return(ifelse(is.na(x), NA_integer_, as.integer(x)))
  if (is.numeric(x)) return(ifelse(is.na(x), NA_integer_, as.integer(x > 0)))
  xx <- tolower(trimws(as.character(x)))
  out <- rep(NA_integer_, length(xx))
  out[xx %in% c("1", "y", "yes", "true", "t", "present", "event", "icd", "male", "m")] <- 1L
  out[xx %in% c("0", "n", "no", "false", "f", "absent", "none", "female", "f")] <- 0L
  out
}

normalise_name <- function(x) {
  x <- tolower(trimws(as.character(x)))
  x <- gsub("[^a-z0-9]+", "_", x)
  gsub("^_|_$", "", x)
}

alias_registry <- list(
  ID = c("ID", "id", "patient_id", "Patient_ID", "pat_id", "subject_id"),
  DB = c("DB", "DBP", "dataset", "Database", "db", "source", "site", "centre", "center"),
  ICD_status = c("ICD_status", "icd_status", "ICD", "ICD_bin", "icd_bin"),
  Status = c("Status", "status", "STATUS"),
  SCD_event = c("SCD_event", "SCD_bin", "scd_event", "scd_bin", "SCD", "scd"),
  Survival_time = c("Survival_time", "survival_time", "ftime_mo_int", "followup_mo", "fu_mo", "FU_time", "follow_up"),
  py = c("py", "person_years", "personyears", "person_year"),
  Time_zero_Y = c("Time_zero_Y", "time_zero_y", "Year_index", "year_index", "Year", "year"),
  Time_zero_Ym = c("Time_zero_Ym", "time_zero_ym", "yearmonth", "ym"),
  Age = c("Age", "AGE", "age", "Age_years", "age_yrs"),
  Sex = c("Sex", "sex", "SEX", "Gender", "gender", "Male"),
  LVEF = c("LVEF", "lvef", "LVEF_num", "lvef_num", "MRI_LVEF", "LVEF_ESC", "LVEF_percent", "LVEF_pct", "EF", "EjectionFraction"),
  eGFR = c("eGFR", "egfr", "eGFR_num", "egfr_num", "GFR", "gfr"),
  Haemoglobin = c("Haemoglobin", "Hemoglobin", "haemoglobin", "hemoglobin", "Hb", "hb"),
  BMI = c("BMI", "bmi"),
  LBBB = c("LBBB", "lbbb"),
  RBBB = c("RBBB", "rbbb"),
  Beta_blockers = c("Beta_blockers", "beta_blockers", "Beta_blocker", "beta_blocker", "BB", "bb"),
  Digitalis_glycosides = c("Digitalis_glycosides", "digitalis_glycosides", "Digitalis", "digitalis", "Digoxin", "digoxin"),
  AF_atrial_flutter = c("AF_atrial_flutter", "af_atrial_flutter", "AF", "af", "Atrial_fibrillation", "atrial_fibrillation"),
  PCI = c("PCI", "pci"),
  CABG = c("CABG", "cabg"),
  PCI_acute = c("PCI_acute", "pci_acute"),
  CABG_acute = c("CABG_acute", "cabg_acute"),
  Revascularisation_acute = c("Revascularisation_acute", "Revascularization_acute", "revascularisation_acute", "revascularization_acute"),
  Thrombolysis_acute = c("Thrombolysis_acute", "thrombolysis_acute"),
  fh_scd = c("fh_scd", "FH_SCD", "family_history_scd", "Family_history_SCD"),
  mi_location_anterior = c("mi_location_anterior", "MI_location_anterior", "anterior_mi", "Anterior_MI")
)

pick_alias <- function(nm, aliases) {
  hit <- aliases[aliases %in% nm]
  if (length(hit)) return(hit[[1]])
  nm_norm <- normalise_name(nm)
  alias_norm <- normalise_name(aliases)
  idx <- match(alias_norm, nm_norm, nomatch = 0)
  idx <- idx[idx > 0]
  if (length(idx)) return(nm[[idx[[1]]]])
  NA_character_
}

standardize_columns <- function(df, source_name = "data") {
  nm <- names(df)
  map <- data.frame(
    source = source_name,
    canonical = names(alias_registry),
    source_column = NA_character_,
    found = FALSE,
    stringsAsFactors = FALSE
  )
  for (canonical in names(alias_registry)) {
    source_col <- pick_alias(nm, alias_registry[[canonical]])
    map$source_column[map$canonical == canonical] <- source_col
    map$found[map$canonical == canonical] <- !is.na(source_col)
    if (!is.na(source_col) && !(canonical %in% names(df))) {
      df[[canonical]] <- df[[source_col]]
    }
  }
  attr(df, "variable_map") <- map
  df
}

source_map <- function(df) {
  out <- attr(df, "variable_map")
  if (is.null(out)) data.frame() else out
}

get_col <- function(df, col, default = NA) {
  if (col %in% names(df)) df[[col]] else rep(default, nrow(df))
}

infer_time_unit <- function(x) {
  xx <- as_num_safely(x)
  xx <- xx[is.finite(xx) & !is.na(xx)]
  if (!length(xx)) return("missing")
  mx <- max(xx, na.rm = TRUE)
  p99 <- as.numeric(stats::quantile(xx, 0.99, na.rm = TRUE, names = FALSE))
  if (mx <= 240 && p99 <= 180) return("likely_months")
  if (mx > 1000 || p99 > 900) return("likely_days")
  if (mx > 240) return("ambiguous_days_or_long_months")
  "likely_months"
}

derive_person_years <- function(df) {
  if ("py" %in% names(df)) {
    py <- as_num_safely(df$py)
    if (sum(!is.na(py) & py > 0) > 0) return(py)
  }
  if (!("Survival_time" %in% names(df))) return(rep(NA_real_, nrow(df)))
  tt <- as_num_safely(df$Survival_time)
  unit <- infer_time_unit(tt)
  if (unit %in% c("likely_days", "ambiguous_days_or_long_months")) {
    tt / 365.25
  } else {
    tt / 12
  }
}

status_num <- function(df) {
  if (!("Status" %in% names(df))) return(rep(NA_integer_, nrow(df)))
  suppressWarnings(as.integer(as.character(df$Status)))
}

scd_bin <- function(df) {
  if ("SCD_event" %in% names(df)) {
    out <- to_bin01(df$SCD_event)
    if (sum(!is.na(out)) > 0) return(out)
  }
  st <- status_num(df)
  ifelse(is.na(st), NA_integer_, as.integer(st == 1L))
}

non_scd_bin <- function(df) {
  st <- status_num(df)
  ifelse(is.na(st), NA_integer_, as.integer(st == 2L))
}

all_death_bin <- function(df) {
  st <- status_num(df)
  scd <- scd_bin(df)
  out <- ifelse(!is.na(st), as.integer(st %in% c(1L, 2L)), NA_integer_)
  out[is.na(out) & !is.na(scd)] <- scd[is.na(out) & !is.na(scd)]
  out
}

count_events <- function(df) {
  py <- derive_person_years(df)
  data.frame(
    n = nrow(df),
    scd_events = sum(scd_bin(df) == 1L, na.rm = TRUE),
    non_scd_deaths = sum(non_scd_bin(df) == 1L, na.rm = TRUE),
    all_deaths = sum(all_death_bin(df) == 1L, na.rm = TRUE),
    person_years = sum(py[py > 0], na.rm = TRUE),
    stringsAsFactors = FALSE
  )
}

summarise_missingness <- function(df, vars, idea = NA_character_) {
  vars <- unique(vars)
  if (!length(vars)) {
    return(data.frame(
      idea = character(0),
      variable = character(0),
      available = logical(0),
      n = integer(0),
      missing = integer(0),
      nonmissing = integer(0),
      missing_pct = numeric(0),
      stringsAsFactors = FALSE
    ))
  }
  data.frame(
    idea = idea,
    variable = vars,
    available = vars %in% names(df),
    n = nrow(df),
    missing = vapply(vars, function(v) {
      if (!(v %in% names(df))) return(nrow(df))
      sum(!not_blank(df[[v]]))
    }, numeric(1)),
    stringsAsFactors = FALSE
  ) |>
    transform(nonmissing = n - missing, missing_pct = ifelse(n > 0, missing / n, NA_real_))
}

complete_case_summary <- function(df, vars, idea) {
  vars_available <- vars[vars %in% names(df)]
  if (!length(vars_available)) {
    cc <- rep(FALSE, nrow(df))
  } else {
    cc <- stats::complete.cases(df[, vars_available, drop = FALSE])
  }
  all_events <- count_events(df)
  cc_events <- count_events(df[cc, , drop = FALSE])
  data.frame(
    idea = idea,
    variables_requested = paste(vars, collapse = ";"),
    variables_available = paste(vars_available, collapse = ";"),
    n_total = all_events$n,
    n_complete = cc_events$n,
    retention = ifelse(all_events$n > 0, cc_events$n / all_events$n, NA_real_),
    scd_events_total = all_events$scd_events,
    scd_events_complete = cc_events$scd_events,
    all_deaths_total = all_events$all_deaths,
    all_deaths_complete = cc_events$all_deaths,
    stringsAsFactors = FALSE
  )
}

bind_rows_safe <- function(items) {
  items <- items[vapply(items, is.data.frame, logical(1))]
  items <- items[vapply(items, nrow, integer(1)) > 0]
  if (!length(items)) return(data.frame())
  dplyr::bind_rows(items)
}

transfer_files <- c(
  ICD = "ICD.csv",
  ICD_all = "ICD_all.csv",
  NonICD_reduced = "NonICD_reduced.csv",
  NonICD_preserved = "NonICD_preserved.csv"
)

read_optional <- function(path, source_name) {
  if (!file.exists(path)) {
    warning("Input not found, skipping: ", path, call. = FALSE)
    return(NULL)
  }
  df <- read_any_table(path)
  df <- standardize_columns(df, source_name)
  attr(df, "input_path") <- path
  df
}

transfer_data <- lapply(names(transfer_files), function(nm) {
  read_optional(file.path(roots$transfer_dir, transfer_files[[nm]]), nm)
})
names(transfer_data) <- names(transfer_files)
transfer_data <- transfer_data[!vapply(transfer_data, is.null, logical(1))]

handled_candidates <- c(
  file.path(roots$transfer_dir, "df_handled.rds"),
  file.path(roots$transfer_dir, "df_handled.csv"),
  file.path(roots$output_root, "Study5", "df_handled.rds"),
  file.path(roots$output_root, "Study5", "df_handled.csv")
)
handled_path <- handled_candidates[file.exists(handled_candidates)][1]
df_handled <- NULL
if (!is.na(handled_path)) {
  df_handled <- standardize_columns(read_any_table(handled_path), "df_handled")
  attr(df_handled, "input_path") <- handled_path
}

all_maps <- c(lapply(transfer_data, source_map), list(source_map(df_handled)))
variable_map <- bind_rows_safe(all_maps)
if (nrow(variable_map)) {
  variable_map$missing_source_variables <- vapply(
    variable_map$canonical,
    function(v) paste(alias_registry[[v]], collapse = ";"),
    character(1)
  )
  write_csv(variable_map, file.path(roots$out_dir, "variable_map.csv"))
}

add_source <- function(df, source_name) {
  if (is.null(df)) return(NULL)
  df$source_file <- source_name
  df
}

nonicd_transfer <- bind_rows_safe(list(
  add_source(transfer_data$NonICD_reduced, "NonICD_reduced"),
  add_source(transfer_data$NonICD_preserved, "NonICD_preserved")
))

filter_non_icd <- function(df) {
  if (is.null(df) || !nrow(df)) return(df)
  if ("ICD_status" %in% names(df)) {
    icd <- to_bin01(df$ICD_status)
    keep <- is.na(icd) | icd == 0L
    return(df[keep, , drop = FALSE])
  }
  df
}

analysis_data <- if (!is.null(df_handled) && nrow(df_handled)) df_handled else nonicd_transfer
nonicd_data <- filter_non_icd(analysis_data)
if (is.null(nonicd_data) || !nrow(nonicd_data)) {
  stop("No usable Non-ICD analysis dataset found.", call. = FALSE)
}

preserved_data <- if (!is.null(transfer_data$NonICD_preserved)) {
  transfer_data$NonICD_preserved
} else if ("LVEF" %in% names(nonicd_data)) {
  nonicd_data[lvef_percent(nonicd_data$LVEF) >= 50, , drop = FALSE]
} else {
  nonicd_data[FALSE, , drop = FALSE]
}

reduced_data <- if (!is.null(transfer_data$NonICD_reduced)) {
  transfer_data$NonICD_reduced
} else if ("LVEF" %in% names(nonicd_data)) {
  nonicd_data[lvef_percent(nonicd_data$LVEF) < 40, , drop = FALSE]
} else {
  nonicd_data[FALSE, , drop = FALSE]
}

global_census_one <- function(df, label) {
  st <- status_num(df)
  tt <- as_num_safely(get_col(df, "Survival_time"))
  py <- derive_person_years(df)
  id <- as.character(get_col(df, "ID"))
  data.frame(
    source = label,
    rows = nrow(df),
    columns = ncol(df),
    unique_ids = if ("ID" %in% names(df)) length(unique(id[not_blank(id)])) else NA_integer_,
    duplicate_ids = if ("ID" %in% names(df)) sum(duplicated(id[not_blank(id)])) else NA_integer_,
    status_0 = sum(st == 0L, na.rm = TRUE),
    status_1 = sum(st == 1L, na.rm = TRUE),
    status_2 = sum(st == 2L, na.rm = TRUE),
    status_other = sum(!is.na(st) & !(st %in% c(0L, 1L, 2L))),
    followup_unit_inferred = infer_time_unit(tt),
    survival_time_median = suppressWarnings(stats::median(tt, na.rm = TRUE)),
    survival_time_q1 = suppressWarnings(quantile_or_na(tt, 0.25)),
    survival_time_q3 = suppressWarnings(quantile_or_na(tt, 0.75)),
    survival_time_max = suppressWarnings(max_or_na(tt)),
    person_years = sum(py[py > 0], na.rm = TRUE),
    stringsAsFactors = FALSE
  )
}

census_items <- c(transfer_data, list(df_handled = df_handled))
census_items <- census_items[!vapply(census_items, is.null, logical(1))]
global_census <- bind_rows_safe(Map(global_census_one, census_items, names(census_items)))
write_csv(global_census, file.path(roots$out_dir, "global_cohort_census.csv"))

status_by_db <- function(df, label) {
  if (!("DB" %in% names(df))) df$DB <- "UNKNOWN_DB"
  st <- status_num(df)
  aggregate(
    data.frame(n = rep(1L, nrow(df))),
    by = list(source = rep(label, nrow(df)), DB = as.character(df$DB), Status = st),
    FUN = sum
  )
}
status_by_db_report <- bind_rows_safe(Map(status_by_db, census_items, names(census_items)))
if (nrow(status_by_db_report)) {
  write_csv(status_by_db_report, file.path(roots$out_dir, "status_by_db.csv"))
}

ids_for <- function(df) {
  if (is.null(df) || !("ID" %in% names(df))) return(character(0))
  unique(as.character(df$ID[not_blank(df$ID)]))
}

overlap_rows <- list()
tf_names <- names(transfer_data)
if (length(tf_names) >= 2) {
  pairs <- utils::combn(tf_names, 2, simplify = FALSE)
  overlap_rows <- lapply(pairs, function(p) {
    id1 <- ids_for(transfer_data[[p[[1]]]])
    id2 <- ids_for(transfer_data[[p[[2]]]])
    data.frame(
      file_a = p[[1]],
      file_b = p[[2]],
      ids_a = length(id1),
      ids_b = length(id2),
      overlap_ids = length(intersect(id1, id2)),
      stringsAsFactors = FALSE
    )
  })
}
patient_overlap_report <- bind_rows_safe(overlap_rows)
write_csv(patient_overlap_report, file.path(roots$out_dir, "patient_overlap_report.csv"))

db_value <- function(df) {
  if ("DB" %in% names(df)) as.character(df$DB) else rep("UNKNOWN_DB", nrow(df))
}

data_contract_report <- function(df) {
  db <- db_value(df)
  tt <- as_num_safely(get_col(df, "Survival_time"))
  st <- status_num(df)
  split_idx <- split(seq_len(nrow(df)), db, drop = TRUE)
  bind_rows_safe(lapply(names(split_idx), function(d) {
    idx <- split_idx[[d]]
    tt_d <- tt[idx]
    st_d <- st[idx]
    data.frame(
      DB = d,
      n = length(idx),
      followup_unit_inferred = infer_time_unit(tt_d),
      survival_time_max = suppressWarnings(max_or_na(tt_d)),
      survival_time_p99 = suppressWarnings(quantile_or_na(tt_d, 0.99)),
      has_status_0 = any(st_d == 0L, na.rm = TRUE),
      has_status_1 = any(st_d == 1L, na.rm = TRUE),
      has_status_2 = any(st_d == 2L, na.rm = TRUE),
      distinct_status_values = paste(sort(unique(st_d[!is.na(st_d)])), collapse = ";"),
      flag_no_competing_event_code_2 = !any(st_d == 2L, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  }))
}

contract <- data_contract_report(nonicd_data)
write_csv(contract, file.path(roots$out_dir, "data_contract_report.csv"))

red_flags <- list()
add_flag <- function(type, detail, n = NA_integer_, DB = NA_character_) {
  data.frame(type = type, DB = DB, n = n, detail = detail, stringsAsFactors = FALSE)
}
tt_all <- as_num_safely(get_col(nonicd_data, "Survival_time"))
red_flags[[length(red_flags) + 1L]] <- add_flag("followup_nonpositive", "Survival_time <= 0", sum(!is.na(tt_all) & tt_all <= 0))
st_all <- status_num(nonicd_data)
red_flags[[length(red_flags) + 1L]] <- add_flag("status_invalid", "Status outside 0/1/2", sum(!is.na(st_all) & !(st_all %in% c(0L, 1L, 2L))))
if ("LVEF" %in% names(nonicd_data)) {
  lv <- as_num_safely(nonicd_data$LVEF)
  red_flags[[length(red_flags) + 1L]] <- add_flag("lvef_0_1_scale", "LVEF values between 0 and 1 detected", sum(!is.na(lv) & lv > 0 & lv <= 1))
  red_flags[[length(red_flags) + 1L]] <- add_flag("lvef_implausible", "LVEF < 0 or > 100 after proportion-to-percent normalization", sum(!is.na(lvef_percent(lv)) & (lvef_percent(lv) < 0 | lvef_percent(lv) > 100)))
}
for (v in c("BMI", "eGFR", "Haemoglobin")) {
  if (v %in% names(nonicd_data)) {
    x <- as_num_safely(nonicd_data[[v]])
    bounds <- switch(
      v,
      BMI = c(10, 80),
      eGFR = c(0, 200),
      Haemoglobin = c(2, 25)
    )
    red_flags[[length(red_flags) + 1L]] <- add_flag(
      paste0(tolower(v), "_implausible"),
      paste0(v, " outside [", bounds[[1]], ", ", bounds[[2]], "]"),
      sum(!is.na(x) & (x < bounds[[1]] | x > bounds[[2]]))
    )
  }
}
for (i in seq_len(nrow(contract))) {
  if (isTRUE(contract$flag_no_competing_event_code_2[[i]])) {
    red_flags[[length(red_flags) + 1L]] <- add_flag(
      "db_no_status_2",
      "DB has no Status == 2 records",
      contract$n[[i]],
      contract$DB[[i]]
    )
  }
}
red_flags_df <- bind_rows_safe(red_flags)
write_csv(red_flags_df, file.path(roots$out_dir, "red_flags.csv"))

group_counts <- function(df, group_var) {
  if (!(group_var %in% names(df))) return(data.frame())
  groups <- as.character(df[[group_var]])
  groups[is.na(groups) | groups == ""] <- "Missing"
  split_idx <- split(seq_len(nrow(df)), groups, drop = TRUE)
  bind_rows_safe(lapply(names(split_idx), function(g) {
    cbind(data.frame(group = g, stringsAsFactors = FALSE), count_events(df[split_idx[[g]], , drop = FALSE]))
  }))
}

idea_summary_rows <- list()
complete_case_rows <- list()
missingness_rows <- list()

idea_A <- data.frame()
if (all(c("eGFR", "Haemoglobin") %in% names(nonicd_data))) {
  a_df <- nonicd_data[stats::complete.cases(nonicd_data[, c("eGFR", "Haemoglobin"), drop = FALSE]), , drop = FALSE]
  eg <- as_num_safely(a_df$eGFR)
  hb <- as_num_safely(a_df$Haemoglobin)
  a_df$egfr_quartile <- make_quartile(eg)
  a_df$hb_quartile <- make_quartile(hb)
  cells <- split(seq_len(nrow(a_df)), interaction(a_df$egfr_quartile, a_df$hb_quartile, drop = TRUE), drop = TRUE)
  idea_A <- bind_rows_safe(lapply(names(cells), function(g) {
    parts <- strsplit(g, "\\.", fixed = FALSE)[[1]]
    cbind(
      data.frame(egfr_quartile = parts[[1]], hb_quartile = parts[[2]], stringsAsFactors = FALSE),
      count_events(a_df[cells[[g]], , drop = FALSE])
    )
  }))
}
write_csv(idea_A, file.path(roots$out_dir, "idea_A_egfr_hb_counts.csv"))
missingness_rows[[length(missingness_rows) + 1L]] <- summarise_missingness(nonicd_data, c("eGFR", "Haemoglobin"), "A_egfr_hb")
complete_case_rows[[length(complete_case_rows) + 1L]] <- complete_case_summary(nonicd_data, c("eGFR", "Haemoglobin"), "A_egfr_hb")
a_events <- count_events(nonicd_data)
a_cc <- complete_case_rows[[length(complete_case_rows)]]
idea_summary_rows[[length(idea_summary_rows) + 1L]] <- data.frame(
  idea = "A_egfr_hb",
  n = a_events$n,
  exposed_n = NA_integer_,
  unexposed_n = NA_integer_,
  scd_events = a_events$scd_events,
  non_scd_deaths = a_events$non_scd_deaths,
  complete_case_retention = a_cc$retention,
  min_cell_n = min_or_na(idea_A$n),
  positivity = NA_real_,
  go_no_go = ifelse(a_cc$n_complete > 0 && a_cc$scd_events_complete > 50 && a_cc$all_deaths_complete > 100, "GO", "CHECK"),
  stringsAsFactors = FALSE
)

idea_B <- data.frame()
if (all(c("LBBB", "RBBB") %in% names(nonicd_data))) {
  b_df <- nonicd_data
  lbbb <- to_bin01(b_df$LBBB)
  rbbb <- to_bin01(b_df$RBBB)
  b_df$conduction_group <- ifelse(lbbb == 1L & rbbb == 1L, "Both",
    ifelse(lbbb == 1L, "LBBB", ifelse(rbbb == 1L, "RBBB",
      ifelse(lbbb == 0L & rbbb == 0L, "Neither", "Missing")
    ))
  )
  idea_B <- group_counts(b_df, "conduction_group")
}
write_csv(idea_B, file.path(roots$out_dir, "idea_B_lbbb_rbbb_counts.csv"))
missingness_rows[[length(missingness_rows) + 1L]] <- summarise_missingness(nonicd_data, c("LBBB", "RBBB"), "B_lbbb_rbbb")
complete_case_rows[[length(complete_case_rows) + 1L]] <- complete_case_summary(nonicd_data, c("LBBB", "RBBB"), "B_lbbb_rbbb")
b_lbbb_events <- if (nrow(idea_B) && any(idea_B$group == "LBBB")) idea_B$scd_events[idea_B$group == "LBBB"][[1]] else NA_integer_
idea_summary_rows[[length(idea_summary_rows) + 1L]] <- data.frame(
  idea = "B_lbbb_rbbb",
  n = nrow(nonicd_data),
  exposed_n = if (nrow(idea_B) && any(idea_B$group == "LBBB")) idea_B$n[idea_B$group == "LBBB"][[1]] else NA_integer_,
  unexposed_n = if (nrow(idea_B) && any(idea_B$group == "Neither")) idea_B$n[idea_B$group == "Neither"][[1]] else NA_integer_,
  scd_events = sum(idea_B$scd_events, na.rm = TRUE),
  non_scd_deaths = sum(idea_B$non_scd_deaths, na.rm = TRUE),
  complete_case_retention = tail(complete_case_rows, 1)[[1]]$retention,
  min_cell_n = min_or_na(idea_B$n),
  positivity = ifelse(nrow(nonicd_data) > 0 && !is.na(b_lbbb_events), sum(to_bin01(nonicd_data$LBBB) == 1L, na.rm = TRUE) / nrow(nonicd_data), NA_real_),
  go_no_go = ifelse(!is.na(b_lbbb_events) && b_lbbb_events >= 50, "GO", "CHECK"),
  stringsAsFactors = FALSE
)

idea_C <- data.frame()
c_df <- preserved_data
if ("LVEF" %in% names(c_df)) {
  c_df <- c_df[is.na(lvef_percent(c_df$LVEF)) | lvef_percent(c_df$LVEF) >= 50, , drop = FALSE]
}
if ("Beta_blockers" %in% names(c_df)) {
  c_df$bb_group <- ifelse(to_bin01(c_df$Beta_blockers) == 1L, "Treated",
    ifelse(to_bin01(c_df$Beta_blockers) == 0L, "Untreated", "Missing")
  )
  idea_C <- group_counts(c_df, "bb_group")
  db <- db_value(c_df)
  bb <- to_bin01(c_df$Beta_blockers)
  db_counts <- aggregate(
    data.frame(n = rep(1L, nrow(c_df)), treated = bb == 1L, untreated = bb == 0L),
    by = list(DB = db),
    FUN = function(x) sum(x, na.rm = TRUE)
  )
  db_counts$treated_share <- ifelse(db_counts$n > 0, db_counts$treated / db_counts$n, NA_real_)
  write_csv(db_counts, file.path(roots$out_dir, "idea_C_beta_blocker_preserved_by_db.csv"))
}
write_csv(idea_C, file.path(roots$out_dir, "idea_C_beta_blocker_preserved_counts.csv"))
c_vars <- c("Beta_blockers", "Age", "Sex", "LVEF", "eGFR", "Diabetes", "Hypertension", "MI_history")
missingness_rows[[length(missingness_rows) + 1L]] <- summarise_missingness(c_df, c_vars, "C_beta_blocker_preserved")
complete_case_rows[[length(complete_case_rows) + 1L]] <- complete_case_summary(c_df, c_vars, "C_beta_blocker_preserved")
c_untreated <- if (nrow(idea_C) && any(idea_C$group == "Untreated")) idea_C$n[idea_C$group == "Untreated"][[1]] else NA_integer_
c_treated <- if (nrow(idea_C) && any(idea_C$group == "Treated")) idea_C$n[idea_C$group == "Treated"][[1]] else NA_integer_
c_pos <- ifelse(sum(c_treated, c_untreated, na.rm = TRUE) > 0, c_untreated / sum(c_treated, c_untreated, na.rm = TRUE), NA_real_)
idea_summary_rows[[length(idea_summary_rows) + 1L]] <- data.frame(
  idea = "C_beta_blocker_preserved",
  n = nrow(c_df),
  exposed_n = c_treated,
  unexposed_n = c_untreated,
  scd_events = sum(idea_C$scd_events, na.rm = TRUE),
  non_scd_deaths = sum(idea_C$non_scd_deaths, na.rm = TRUE),
  complete_case_retention = tail(complete_case_rows, 1)[[1]]$retention,
  min_cell_n = min_or_na(idea_C$n),
  positivity = c_pos,
  go_no_go = ifelse(!is.na(c_pos) && c_pos >= 0.10, "GO", "CHECK"),
  stringsAsFactors = FALSE
)

idea_D <- data.frame()
if ("Digitalis_glycosides" %in% names(nonicd_data)) {
  d_df <- nonicd_data
  d_df$digitalis_group <- ifelse(to_bin01(d_df$Digitalis_glycosides) == 1L, "User",
    ifelse(to_bin01(d_df$Digitalis_glycosides) == 0L, "Non-user", "Missing")
  )
  d_df$calendar_era <- if ("Time_zero_Y" %in% names(d_df)) {
    cut(as_num_safely(d_df$Time_zero_Y), breaks = c(-Inf, 2004, 2009, 2014, Inf), labels = c("<=2004", "2005-2009", "2010-2014", ">=2015"))
  } else {
    factor("Unknown")
  }
  idea_D <- group_counts(d_df, "digitalis_group")
  digitalis_by_era <- aggregate(
    data.frame(n = rep(1L, nrow(d_df)), digitalis = to_bin01(d_df$Digitalis_glycosides) == 1L),
    by = list(DB = db_value(d_df), calendar_era = as.character(d_df$calendar_era)),
    FUN = function(x) sum(x, na.rm = TRUE)
  )
  digitalis_by_era$prevalence <- ifelse(digitalis_by_era$n > 0, digitalis_by_era$digitalis / digitalis_by_era$n, NA_real_)
  write_csv(digitalis_by_era, file.path(roots$out_dir, "idea_D_digitalis_by_db_era.csv"))
  if ("AF_atrial_flutter" %in% names(d_df)) {
    af_tab <- as.data.frame(table(
      digitalis = d_df$digitalis_group,
      af = ifelse(to_bin01(d_df$AF_atrial_flutter) == 1L, "AF", ifelse(to_bin01(d_df$AF_atrial_flutter) == 0L, "No_AF", "Missing")),
      useNA = "ifany"
    ))
    write_csv(af_tab, file.path(roots$out_dir, "idea_D_digitalis_by_af.csv"))
  }
}
write_csv(idea_D, file.path(roots$out_dir, "idea_D_digitalis_counts.csv"))
missingness_rows[[length(missingness_rows) + 1L]] <- summarise_missingness(nonicd_data, c("Digitalis_glycosides", "AF_atrial_flutter"), "D_digitalis")
complete_case_rows[[length(complete_case_rows) + 1L]] <- complete_case_summary(nonicd_data, c("Digitalis_glycosides", "AF_atrial_flutter"), "D_digitalis")
d_user <- if (nrow(idea_D) && any(idea_D$group == "User")) idea_D$n[idea_D$group == "User"][[1]] else NA_integer_
d_nonuser <- if (nrow(idea_D) && any(idea_D$group == "Non-user")) idea_D$n[idea_D$group == "Non-user"][[1]] else NA_integer_
idea_summary_rows[[length(idea_summary_rows) + 1L]] <- data.frame(
  idea = "D_digitalis",
  n = nrow(nonicd_data),
  exposed_n = d_user,
  unexposed_n = d_nonuser,
  scd_events = sum(idea_D$scd_events, na.rm = TRUE),
  non_scd_deaths = sum(idea_D$non_scd_deaths, na.rm = TRUE),
  complete_case_retention = tail(complete_case_rows, 1)[[1]]$retention,
  min_cell_n = min_or_na(idea_D$n),
  positivity = ifelse(sum(d_user, d_nonuser, na.rm = TRUE) > 0, d_user / sum(d_user, d_nonuser, na.rm = TRUE), NA_real_),
  go_no_go = ifelse(!is.na(d_user) && d_user > 0 && !is.na(d_nonuser) && d_nonuser > 0, "GO", "CHECK"),
  stringsAsFactors = FALSE
)

idea_E <- data.frame()
if (nrow(reduced_data)) {
  e_df <- reduced_data
  pci_any <- if ("PCI" %in% names(e_df)) to_bin01(e_df$PCI) == 1L else rep(FALSE, nrow(e_df))
  cabg_any <- if ("CABG" %in% names(e_df)) to_bin01(e_df$CABG) == 1L else rep(FALSE, nrow(e_df))
  e_df$revasc_group <- ifelse(pci_any & cabg_any, "Both",
    ifelse(pci_any, "PCI_only", ifelse(cabg_any, "CABG_only", "None"))
  )
  idea_E <- group_counts(e_df, "revasc_group")
  acute_vars <- intersect(c("PCI_acute", "CABG_acute", "Revascularisation_acute", "Thrombolysis_acute"), names(e_df))
  acute_report <- summarise_missingness(e_df, acute_vars, "E_revascularization_acute_fields")
  write_csv(acute_report, file.path(roots$out_dir, "idea_E_revascularization_acute_field_availability.csv"))
}
write_csv(idea_E, file.path(roots$out_dir, "idea_E_revascularization_counts.csv"))
e_vars <- c("PCI", "CABG", "PCI_acute", "CABG_acute", "Revascularisation_acute", "Thrombolysis_acute")
missingness_rows[[length(missingness_rows) + 1L]] <- summarise_missingness(reduced_data, e_vars, "E_revascularization")
complete_case_rows[[length(complete_case_rows) + 1L]] <- complete_case_summary(reduced_data, e_vars, "E_revascularization")
e_exposed <- if (nrow(idea_E)) sum(idea_E$n[idea_E$group != "None"], na.rm = TRUE) else NA_integer_
e_unexposed <- if (nrow(idea_E) && any(idea_E$group == "None")) idea_E$n[idea_E$group == "None"][[1]] else NA_integer_
idea_summary_rows[[length(idea_summary_rows) + 1L]] <- data.frame(
  idea = "E_revascularization",
  n = nrow(reduced_data),
  exposed_n = e_exposed,
  unexposed_n = e_unexposed,
  scd_events = sum(idea_E$scd_events, na.rm = TRUE),
  non_scd_deaths = sum(idea_E$non_scd_deaths, na.rm = TRUE),
  complete_case_retention = tail(complete_case_rows, 1)[[1]]$retention,
  min_cell_n = min_or_na(idea_E$n),
  positivity = ifelse(sum(e_exposed, e_unexposed, na.rm = TRUE) > 0, e_exposed / sum(e_exposed, e_unexposed, na.rm = TRUE), NA_real_),
  go_no_go = ifelse(nrow(idea_E) && min(idea_E$n) > 0, "GO", "CHECK"),
  stringsAsFactors = FALSE
)

idea_F <- data.frame()
if ("Age" %in% names(nonicd_data)) {
  f_df <- nonicd_data
  age <- as_num_safely(f_df$Age)
  age_groups <- list(age_lt_50 = which(age < 50), age_lt_55 = which(age < 55))
  idea_F <- bind_rows_safe(lapply(names(age_groups), function(g) {
    cbind(data.frame(group = g, stringsAsFactors = FALSE), count_events(f_df[age_groups[[g]], , drop = FALSE]))
  }))
  young <- f_df[age < 55, , drop = FALSE]
  young_avail <- summarise_missingness(young, c("fh_scd", "mi_location_anterior"), "F_young_phenotype")
  write_csv(young_avail, file.path(roots$out_dir, "idea_F_young_variable_availability.csv"))
}
write_csv(idea_F, file.path(roots$out_dir, "idea_F_young_phenotype_counts.csv"))
missingness_rows[[length(missingness_rows) + 1L]] <- summarise_missingness(nonicd_data, c("Age", "fh_scd", "mi_location_anterior"), "F_young_phenotype")
complete_case_rows[[length(complete_case_rows) + 1L]] <- complete_case_summary(nonicd_data, c("Age", "fh_scd", "mi_location_anterior"), "F_young_phenotype")
f_lt55 <- if (nrow(idea_F) && any(idea_F$group == "age_lt_55")) idea_F$n[idea_F$group == "age_lt_55"][[1]] else NA_integer_
idea_summary_rows[[length(idea_summary_rows) + 1L]] <- data.frame(
  idea = "F_young_phenotype",
  n = nrow(nonicd_data),
  exposed_n = f_lt55,
  unexposed_n = ifelse(!is.na(f_lt55), nrow(nonicd_data) - f_lt55, NA_integer_),
  scd_events = sum(idea_F$scd_events, na.rm = TRUE),
  non_scd_deaths = sum(idea_F$non_scd_deaths, na.rm = TRUE),
  complete_case_retention = tail(complete_case_rows, 1)[[1]]$retention,
  min_cell_n = min_or_na(idea_F$n),
  positivity = ifelse(nrow(nonicd_data) > 0 && !is.na(f_lt55), f_lt55 / nrow(nonicd_data), NA_real_),
  go_no_go = ifelse(nrow(idea_F) && any(idea_F$scd_events >= 50), "GO", "CHECK"),
  stringsAsFactors = FALSE
)

complete_case_retention <- bind_rows_safe(complete_case_rows)
write_csv(complete_case_retention, file.path(roots$out_dir, "complete_case_retention_by_idea.csv"))

missingness_by_idea <- bind_rows_safe(missingness_rows)
write_csv(missingness_by_idea, file.path(roots$out_dir, "missingness_by_idea.csv"))

feasibility_summary <- bind_rows_safe(idea_summary_rows)
write_csv(feasibility_summary, file.path(roots$out_dir, "feasibility_summary.csv"))

events_per_db <- bind_rows_safe(lapply(split(seq_len(nrow(nonicd_data)), db_value(nonicd_data), drop = TRUE), function(idx) {
  cbind(data.frame(DB = db_value(nonicd_data)[idx[[1]]], stringsAsFactors = FALSE), count_events(nonicd_data[idx, , drop = FALSE]))
}))
write_csv(events_per_db, file.path(roots$out_dir, "events_per_db.csv"))

if ("Time_zero_Y" %in% names(nonicd_data)) {
  y <- as_num_safely(nonicd_data$Time_zero_Y)
  calendar_coverage <- data.frame(
    DB = names(split(y, db_value(nonicd_data))),
    year_min = vapply(split(y, db_value(nonicd_data)), function(x) suppressWarnings(min_or_na(x)), numeric(1)),
    year_max = vapply(split(y, db_value(nonicd_data)), function(x) suppressWarnings(max_or_na(x)), numeric(1)),
    n = vapply(split(y, db_value(nonicd_data)), length, integer(1)),
    stringsAsFactors = FALSE
  )
  write_csv(calendar_coverage, file.path(roots$out_dir, "calendar_coverage_by_db.csv"))
}

plot_df <- nonicd_data
plot_df$DB_plot <- db_value(plot_df)
if ("Survival_time" %in% names(plot_df)) {
  p <- ggplot2::ggplot(plot_df, ggplot2::aes(x = as_num_safely(Survival_time))) +
    ggplot2::geom_histogram(bins = 40, na.rm = TRUE) +
    ggplot2::facet_wrap(ggplot2::vars(DB_plot), scales = "free_y") +
    ggplot2::labs(x = "Survival_time", y = "N")
  ggplot2::ggsave(file.path(roots$out_dir, "survival_time_distribution_by_db.png"), p, width = 10, height = 7, dpi = 150)
}
if ("LVEF" %in% names(plot_df)) {
  p <- ggplot2::ggplot(plot_df, ggplot2::aes(x = lvef_percent(LVEF))) +
    ggplot2::geom_histogram(bins = 40, na.rm = TRUE) +
    ggplot2::facet_wrap(ggplot2::vars(DB_plot), scales = "free_y") +
    ggplot2::labs(x = "LVEF", y = "N")
  ggplot2::ggsave(file.path(roots$out_dir, "lvef_distribution_by_db.png"), p, width = 10, height = 7, dpi = 150)
}
if (nrow(missingness_by_idea)) {
  p <- ggplot2::ggplot(missingness_by_idea, ggplot2::aes(x = variable, y = idea, fill = missing_pct)) +
    ggplot2::geom_tile() +
    ggplot2::scale_fill_viridis_c(option = "C", na.value = "grey80") +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1)) +
    ggplot2::labs(x = NULL, y = NULL, fill = "Missing")
  ggplot2::ggsave(file.path(roots$out_dir, "missingness_heatmap_by_idea.png"), p, width = 10, height = 5, dpi = 150)
}

input_paths <- c(
  vapply(transfer_data, function(x) attr(x, "input_path"), character(1)),
  if (!is.null(df_handled)) attr(df_handled, "input_path") else character(0)
)
file_hashes <- vapply(input_paths, function(path) {
  if (file.exists(path)) digest::digest(file = path, algo = "sha256") else NA_character_
}, character(1))
row_counts <- vapply(census_items, nrow, integer(1))

json_escape <- function(x) {
  x <- gsub("\\\\", "\\\\\\\\", as.character(x))
  x <- gsub("\"", "\\\\\"", x)
  x <- gsub("\n", "\\\\n", x)
  paste0("\"", x, "\"")
}

named_json_object <- function(x) {
  if (!length(x)) return("{}")
  paste0(
    "{",
    paste(paste0(json_escape(names(x)), ":", json_escape(unname(x))), collapse = ","),
    "}"
  )
}

metadata <- paste0(
  "{\n",
  "  \"timestamp\": ", json_escape(format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")), ",\n",
  "  \"args\": [", paste(json_escape(args), collapse = ","), "],\n",
  "  \"data_root\": ", json_escape(roots$data_root), ",\n",
  "  \"output_root\": ", json_escape(roots$output_root), ",\n",
  "  \"transfer_dir\": ", json_escape(roots$transfer_dir), ",\n",
  "  \"out_dir\": ", json_escape(roots$out_dir), ",\n",
  "  \"input_hashes_sha256\": ", named_json_object(file_hashes), ",\n",
  "  \"row_counts\": ", named_json_object(row_counts), ",\n",
  "  \"r_version\": ", json_escape(R.version.string), ",\n",
  "  \"package_versions\": ", named_json_object(vapply(required_packages, function(pkg) as.character(utils::packageVersion(pkg)), character(1))), "\n",
  "}\n"
)
writeLines(metadata, file.path(roots$out_dir, "run_metadata.json"))

message("Done. Wrote feasibility reports to: ", roots$out_dir)
