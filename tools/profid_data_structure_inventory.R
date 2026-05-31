#!/usr/bin/env Rscript

###############################################################################
# PROFID data structure and availability inventory
#
# This script scans source-data and common-data-model tables and writes aggregate
# metadata only. It does not export patient-level values, value examples,
# category frequencies, min/max values, or date ranges.
###############################################################################

DEFAULT_DATA_ROOT <- "/sc-projects/sc-proj-dhzc-profid/PROFID_Substudies/data"

args <- commandArgs(trailingOnly = TRUE)

get_arg <- function(name, default = NULL) {
  flag <- paste0("--", name)
  hit <- which(args == flag)
  if (!length(hit)) return(default)
  if (hit[[1]] == length(args)) return(default)
  args[[hit[[1]] + 1L]]
}

yes_arg <- function(name, default = FALSE) {
  value <- get_arg(name, if (default) "yes" else "no")
  tolower(value) %in% c("yes", "true", "1", "y")
}

print_usage <- function() {
  cat(
    "Usage:\n",
    "  Rscript tools/profid_data_structure_inventory.R \\\n",
    "    --data-root /sc-projects/sc-proj-dhzc-profid/PROFID_Substudies/data \\\n",
    "    --out-dir /sc-projects/sc-proj-dhzc-profid/PROFID_Substudies/data/derived/data_structure \\\n",
    "    --scope source_plus_cdm \\\n",
    "    --include-archives yes \\\n",
    "    --include-availability yes\n",
    sep = ""
  )
}

if ("--help" %in% args || "-h" %in% args) {
  print_usage()
  quit(status = 0)
}

data_root <- get_arg("data-root", Sys.getenv("PROFID_DATA_ROOT", unset = DEFAULT_DATA_ROOT))
repo_root <- get_arg("repo-root", normalizePath(getwd(), winslash = "/", mustWork = FALSE))
out_dir <- get_arg(
  "out-dir",
  file.path(data_root, "derived", "data_structure")
)
scope <- get_arg("scope", "source_plus_cdm")
include_archives <- yes_arg("include-archives", TRUE)
include_availability <- yes_arg("include-availability", TRUE)
substudy_config <- get_arg(
  "substudy-config",
  file.path(repo_root, "config", "profid_substudy_sources.csv")
)

if (!dir.exists(data_root)) {
  stop(
    sprintf(
      "Data root does not exist: %s\nSet --data-root or PROFID_DATA_ROOT to the mounted PROFID data directory.",
      data_root
    ),
    call. = FALSE
  )
}

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

message("PROFID data root: ", normalizePath(data_root, winslash = "/", mustWork = FALSE))
message("Output directory: ", normalizePath(out_dir, winslash = "/", mustWork = FALSE))
message("Scope: ", scope)
message("Include availability counts: ", include_availability)
message("Include ZIP/RAR archives: ", include_archives)

supported_table_ext <- c(
  "csv", "tsv", "txt", "xlsx", "xls", "ods",
  "sas7bdat", "dta", "sav", "rds", "parquet"
)
supported_archive_ext <- c("zip", "rar")

pkg_available <- function(pkg) requireNamespace(pkg, quietly = TRUE)

reader_package_status <- data.frame(
  package = c("data.table", "readxl", "openxlsx", "readODS", "haven", "arrow"),
  available = vapply(
    c("data.table", "readxl", "openxlsx", "readODS", "haven", "arrow"),
    pkg_available,
    logical(1)
  ),
  stringsAsFactors = FALSE
)
message(
  "Optional reader packages: ",
  paste(
    paste0(reader_package_status$package, "=", ifelse(reader_package_status$available, "yes", "no")),
    collapse = ", "
  )
)

rel_path <- function(path, root) {
  root_norm <- normalizePath(root, winslash = "/", mustWork = FALSE)
  path_norm <- normalizePath(path, winslash = "/", mustWork = FALSE)
  prefix <- paste0(root_norm, "/")
  if (startsWith(path_norm, prefix)) {
    substring(path_norm, nchar(prefix) + 1L)
  } else {
    path_norm
  }
}

path_ext <- function(path) {
  ext <- tools::file_ext(path)
  tolower(ext)
}

is_blank <- function(x) {
  if (is.factor(x)) x <- as.character(x)
  if (!is.character(x)) return(rep(FALSE, length(x)))
  !nzchar(trimws(x))
}

nonmissing_count <- function(x) {
  if (is.list(x) && !is.data.frame(x)) {
    return(sum(!vapply(x, is.null, logical(1))))
  }
  sum(!is.na(x) & !is_blank(x))
}

clean_variable_name <- function(x) {
  x <- tolower(trimws(as.character(x)))
  x <- gsub("[^a-z0-9]+", "_", x)
  x <- gsub("_+", "_", x)
  x <- gsub("^_|_$", "", x)
  x
}

classify_role <- function(column_name) {
  n <- clean_variable_name(column_name)
  if (!nzchar(n) || is.na(n)) return("unknown")

  if (n %in% c("variable_name", "original_name", "new_name", "raw_name",
               "cdm_name", "label", "role")) {
    return("unknown")
  }

  identifier_pat <- paste(
    c(
      "^id$", "^id_", "_id$", "_id_",
      "patient_id", "patient", "pat_id", "pat_index", "subject_id",
      "record_id", "linkage",
      "postcode", "postal", "zip", "site_id", "centre_id", "center_id",
      "mrn", "(^|_)name($|_)", "address", "email", "phone"
    ),
    collapse = "|"
  )

  outcome_strong_pat <- paste(
    c(
      "death", "mort", "scd", "sudden", "endpoint", "event", "shock",
      "survival", "followup", "follow_up", "^fu_", "_fu_", "time_to",
      "days_to", "censor", "vital", "arrhythm", "hospitali"
    ),
    collapse = "|"
  )

  covariate_pat <- paste(
    c(
      "age", "sex", "gender", "lvef", "bmi", "egfr", "gfr",
      "diabetes", "hypertension", "smok", "chol", "hdl", "ldl",
      "triglycer", "haemoglobin", "hemoglobin", "creatinine", "nyha",
      "mi_", "_mi", "myocard", "infarct", "pci", "cabg", "revasc",
      "medication", "drug", "beta", "ace", "arb", "statin",
      "device", "icd_type", "crt", "ecg", "qrs", "imaging", "cmr",
      "atrial", "af_", "_af", "stroke", "tia", "renal", "lipid"
    ),
    collapse = "|"
  )

  outcome_weak_pat <- paste(c("therapy", "status", "outcome"), collapse = "|")

  if (grepl(identifier_pat, n, ignore.case = TRUE)) return("identifier")
  if (grepl(outcome_strong_pat, n, ignore.case = TRUE)) return("outcome")
  if (grepl(covariate_pat, n, ignore.case = TRUE)) return("covariate")
  if (grepl(outcome_weak_pat, n, ignore.case = TRUE)) return("outcome")
  "unknown"
}

guess_domain <- function(column_name, role) {
  n <- clean_variable_name(column_name)
  if (role == "identifier") return("identifier")
  if (grepl("death|mort|vital", n)) return("outcome_death")
  if (grepl("scd|sudden", n)) return("outcome_scd")
  if (grepl("shock|therapy|arrhythm", n)) return("outcome_device_therapy")
  if (grepl("survival|follow|fu_|time_to|days_to|censor", n)) return("outcome_followup_time")
  if (grepl("age|sex|gender", n)) return("demographics")
  if (grepl("lvef|ef|nyha|hf|heart_failure", n)) return("cardiac_function")
  if (grepl("egfr|gfr|renal|creatinine", n)) return("renal")
  if (grepl("bmi|chol|hdl|ldl|triglycer|haemoglobin|hemoglobin|lipid", n)) return("labs_or_biomarkers")
  if (grepl("diabetes|hypertension|smok|stroke|tia|af_|atrial|comorb", n)) return("comorbidity")
  if (grepl("medication|drug|beta|ace|arb|statin|lipid_lower", n)) return("medication")
  if (grepl("device|icd|crt", n)) return("device")
  if (grepl("pci|cabg|revasc|procedure", n)) return("procedure")
  if (grepl("ecg|qrs|imaging|cmr|mri", n)) return("ecg_imaging")
  if (grepl("country|region|postcode|zip|site|centre|center", n)) return("geography")
  if (role == "outcome") return("outcome_other")
  if (role == "covariate") return("covariate_other")
  "unknown"
}

infer_count_unit <- function(source_info, sheet_or_object, col_names) {
  text <- clean_variable_name(paste(
    source_info$relative_path,
    source_info$archive_member,
    sheet_or_object,
    source_info$source_stage,
    paste(col_names, collapse = " "),
    sep = " "
  ))

  if (source_info$source_stage == "processed" &&
      grepl("common_data_model|common-data-model", text)) {
    return("patient_records")
  }
  if (source_info$source_dataset == "Data_Transfer_to_Charite") {
    return("patient_records")
  }
  if (grepl("patients|baseline|demo|target_pop|cohort|registry", text)) {
    return("patient_records")
  }
  if (grepl("event|endpoint|death|shock|therapy|interrog|arrhythm", text)) {
    return("event_rows")
  }
  if (grepl("visit|follow|fu_", text)) {
    return("visits")
  }
  if (grepl("lab|ecg|imaging|cmr|mri|measurement|medication|atc", text)) {
    return("measurements")
  }
  "unknown_rows"
}

source_info_for_path <- function(file, data_root, archive_member = NA_character_) {
  rel <- rel_path(file, data_root)
  parts <- strsplit(rel, "/", fixed = TRUE)[[1]]
  ext <- path_ext(if (is.na(archive_member)) file else archive_member)

  source_dataset <- "unknown"
  source_stage <- "unknown"
  source_kind <- "unknown"

  if (length(parts) >= 2L && parts[[1]] == "Data_Transfer_to_Charite") {
    source_dataset <- "Data_Transfer_to_Charite"
    source_stage <- "transfer"
    source_kind <- "transfer_table"
  } else if (length(parts) >= 3L && parts[[1]] == "datasets" && parts[[2]] == "cdm") {
    source_dataset <- "PROFID_CDM"
    source_stage <- "cdm_spec"
    source_kind <- "global_cdm_spec"
  } else if (length(parts) >= 5L &&
             parts[[1]] == "datasets" &&
             parts[[2]] == "local" &&
             parts[[4]] == "data") {
    source_dataset <- parts[[3]]
    source_stage <- parts[[5]]
    source_kind <- paste0("dataset_", source_stage)
  } else if (length(parts) >= 5L &&
             parts[[1]] == "datasets" &&
             parts[[2]] == "local" &&
             parts[[4]] == "scripts" &&
             parts[[5]] == "cdm") {
    source_dataset <- parts[[3]]
    source_stage <- "scripts_cdm"
    source_kind <- "dataset_cdm_spec"
  }

  if (!is.na(archive_member)) {
    source_kind <- paste0(source_kind, "_archive_member")
  }

  list(
    source_dataset = source_dataset,
    source_stage = source_stage,
    source_kind = source_kind,
    relative_path = rel,
    archive_member = archive_member,
    file_type = ext
  )
}

empty_inventory_row <- function(source_info, sheet_or_object, read_status, read_error = NA_character_) {
  is_observation_source <- source_info$source_stage %in% c(
    "transfer", "original", "processed", "working"
  )

  data.frame(
    source_dataset = source_info$source_dataset,
    source_stage = source_info$source_stage,
    source_kind = source_info$source_kind,
    is_observation_source = is_observation_source,
    relative_path = source_info$relative_path,
    archive_member = source_info$archive_member,
    sheet_or_object = sheet_or_object,
    file_type = source_info$file_type,
    column_position = NA_integer_,
    column_name = NA_character_,
    column_name_clean = NA_character_,
    normalized_variable = NA_character_,
    analysis_role = "unknown",
    domain_guess = "unknown",
    count_unit = "unknown_rows",
    table_n_rows = NA_integer_,
    table_n_columns = NA_integer_,
    nonmissing_n = NA_integer_,
    missing_n = NA_integer_,
    nonmissing_pct = NA_real_,
    read_status = read_status,
    read_error = read_error,
    stringsAsFactors = FALSE
  )
}

make_inventory_rows <- function(source_info, sheet_or_object, col_names, table_n_rows,
                                nonmissing, missing, read_status = "ok",
                                read_error = NA_character_) {
  col_names <- as.character(col_names)
  table_n_columns <- length(col_names)

  if (!table_n_columns) {
    return(empty_inventory_row(source_info, sheet_or_object, "no_columns", read_error))
  }

  if (is.null(nonmissing)) nonmissing <- rep(NA_integer_, table_n_columns)
  if (is.null(missing)) missing <- rep(NA_integer_, table_n_columns)

  roles <- vapply(col_names, classify_role, character(1))
  domains <- mapply(guess_domain, col_names, roles, USE.NAMES = FALSE)
  count_unit <- infer_count_unit(source_info, sheet_or_object, col_names)
  is_observation_source <- source_info$source_stage %in% c(
    "transfer", "original", "processed", "working"
  )
  pct <- suppressWarnings(as.numeric(nonmissing) / as.numeric(table_n_rows) * 100)
  pct[!is.finite(pct)] <- NA_real_

  data.frame(
    source_dataset = source_info$source_dataset,
    source_stage = source_info$source_stage,
    source_kind = source_info$source_kind,
    is_observation_source = is_observation_source,
    relative_path = source_info$relative_path,
    archive_member = source_info$archive_member,
    sheet_or_object = sheet_or_object,
    file_type = source_info$file_type,
    column_position = seq_along(col_names),
    column_name = col_names,
    column_name_clean = clean_variable_name(col_names),
    normalized_variable = clean_variable_name(col_names),
    analysis_role = roles,
    domain_guess = domains,
    count_unit = count_unit,
    table_n_rows = as.integer(table_n_rows),
    table_n_columns = as.integer(table_n_columns),
    nonmissing_n = as.integer(nonmissing),
    missing_n = as.integer(missing),
    nonmissing_pct = pct,
    read_status = read_status,
    read_error = read_error,
    stringsAsFactors = FALSE
  )
}

table_counts <- function(dat) {
  if (is.null(dat)) {
    return(list(n_rows = NA_integer_, nonmissing = NULL, missing = NULL))
  }
  dat <- as.data.frame(dat, stringsAsFactors = FALSE)
  n_rows <- nrow(dat)
  nonmissing <- vapply(dat, nonmissing_count, integer(1))
  missing <- n_rows - nonmissing
  list(n_rows = n_rows, nonmissing = nonmissing, missing = missing)
}

detect_delimiter <- function(file) {
  ext <- path_ext(file)
  if (ext == "tsv") return(list(sep = "\t", count = NA_integer_))
  if (ext == "csv") return(list(sep = ",", count = NA_integer_))

  line <- ""
  con <- file(file, open = "r")
  on.exit(close(con), add = TRUE)
  for (i in seq_len(20L)) {
    x <- readLines(con, n = 1L, warn = FALSE)
    if (!length(x)) break
    if (nzchar(trimws(x))) {
      line <- x
      break
    }
  }
  candidates <- c("," = ",", ";" = ";", "\t" = "\t", "|" = "|")
  counts <- vapply(candidates, function(sep) {
    match_positions <- gregexpr(sep, line, fixed = TRUE)[[1]]
    if (length(match_positions) == 1L && match_positions[[1]] == -1L) {
      0L
    } else {
      length(match_positions)
    }
  }, integer(1))
  best <- which.max(counts)
  list(sep = candidates[[best]], count = counts[[best]])
}

read_delimited_file <- function(file, source_info, include_availability) {
  delimiter <- detect_delimiter(file)
  sep <- delimiter$sep
  if (path_ext(file) == "txt" && isTRUE(delimiter$count == 0L)) {
    return(empty_inventory_row(
      source_info,
      NA_character_,
      "unsupported_text_layout",
      "TXT file has no detected delimiter; skipped to avoid treating text content as column names."
    ))
  }

  dat <- NULL
  err <- NULL

  if (pkg_available("data.table")) {
    dat <- tryCatch(
      data.table::fread(
        file,
        sep = sep,
        na.strings = c("", "NA", "N/A", "NULL", "."),
        data.table = FALSE,
        showProgress = FALSE,
        nrows = if (include_availability) Inf else 0L,
        check.names = FALSE
      ),
      error = function(e) {
        err <<- conditionMessage(e)
        NULL
      }
    )
  }

  if (is.null(dat) && is.null(err)) {
    dat <- tryCatch(
      utils::read.table(
        file,
        header = TRUE,
        sep = sep,
        quote = "\"",
        comment.char = "",
        stringsAsFactors = FALSE,
        check.names = FALSE,
        na.strings = c("", "NA", "N/A", "NULL", "."),
        nrows = if (include_availability) -1L else 0L
      ),
      error = function(e) {
        err <<- conditionMessage(e)
        NULL
      }
    )
  }

  if (is.null(dat)) {
    return(empty_inventory_row(source_info, NA_character_, "read_error", err))
  }

  counts <- if (include_availability) table_counts(dat) else list(
    n_rows = NA_integer_,
    nonmissing = NULL,
    missing = NULL
  )
  make_inventory_rows(source_info, NA_character_, names(dat), counts$n_rows,
                      counts$nonmissing, counts$missing)
}

excel_sheets <- function(file) {
  if (pkg_available("readxl")) return(readxl::excel_sheets(file))
  if (pkg_available("openxlsx")) return(openxlsx::getSheetNames(file))
  stop("Package 'readxl' or 'openxlsx' is required for Excel files.", call. = FALSE)
}

read_excel_sheet <- function(file, sheet, include_availability) {
  if (pkg_available("readxl")) {
    return(as.data.frame(
      readxl::read_excel(
        file,
        sheet = sheet,
        n_max = if (include_availability) Inf else 0L,
        .name_repair = "minimal"
      ),
      stringsAsFactors = FALSE
    ))
  }
  if (pkg_available("openxlsx")) {
    dat <- openxlsx::read.xlsx(file, sheet = sheet, colNames = TRUE)
    dat <- as.data.frame(dat, stringsAsFactors = FALSE)
    if (!include_availability) dat <- dat[0, , drop = FALSE]
    return(dat)
  }
  stop("Package 'readxl' or 'openxlsx' is required for Excel files.", call. = FALSE)
}

read_excel_file <- function(file, source_info, include_availability) {
  sheets <- tryCatch(excel_sheets(file), error = function(e) {
    return(structure(character(0), error = conditionMessage(e)))
  })
  if (!length(sheets)) {
    err <- attr(sheets, "error")
    return(empty_inventory_row(source_info, NA_character_, "read_error", err))
  }

  rows <- vector("list", length(sheets))
  for (i in seq_along(sheets)) {
    sheet <- sheets[[i]]
    dat <- tryCatch(read_excel_sheet(file, sheet, include_availability), error = function(e) e)
    if (inherits(dat, "error")) {
      rows[[i]] <- empty_inventory_row(source_info, sheet, "read_error", conditionMessage(dat))
      next
    }
    counts <- if (include_availability) table_counts(dat) else list(
      n_rows = NA_integer_,
      nonmissing = NULL,
      missing = NULL
    )
    rows[[i]] <- make_inventory_rows(source_info, sheet, names(dat), counts$n_rows,
                                     counts$nonmissing, counts$missing)
  }
  do.call(rbind, rows)
}

read_ods_file <- function(file, source_info, include_availability) {
  if (!pkg_available("readODS")) {
    return(empty_inventory_row(
      source_info,
      NA_character_,
      "missing_package",
      "Package 'readODS' is required for ODS files."
    ))
  }

  sheets <- tryCatch(readODS::ods_sheets(file), error = function(e) {
    return(structure(character(0), error = conditionMessage(e)))
  })
  if (!length(sheets)) {
    return(empty_inventory_row(source_info, NA_character_, "read_error", attr(sheets, "error")))
  }

  rows <- vector("list", length(sheets))
  for (i in seq_along(sheets)) {
    sheet <- sheets[[i]]
    dat <- tryCatch(
      readODS::read_ods(file, sheet = sheet),
      error = function(e) e
    )
    if (inherits(dat, "error")) {
      rows[[i]] <- empty_inventory_row(source_info, sheet, "read_error", conditionMessage(dat))
      next
    }
    dat <- as.data.frame(dat, stringsAsFactors = FALSE)
    if (!include_availability) dat <- dat[0, , drop = FALSE]
    counts <- if (include_availability) table_counts(dat) else list(
      n_rows = NA_integer_,
      nonmissing = NULL,
      missing = NULL
    )
    rows[[i]] <- make_inventory_rows(source_info, sheet, names(dat), counts$n_rows,
                                     counts$nonmissing, counts$missing)
  }
  do.call(rbind, rows)
}

read_haven_file <- function(file, source_info, include_availability) {
  if (!pkg_available("haven")) {
    return(empty_inventory_row(
      source_info,
      NA_character_,
      "missing_package",
      "Package 'haven' is required for SAS/Stata/SPSS files."
    ))
  }

  ext <- path_ext(file)
  dat <- tryCatch(
    {
      if (ext == "sas7bdat") {
        haven::read_sas(file, n_max = if (include_availability) Inf else 0L)
      } else if (ext == "dta") {
        haven::read_dta(file, n_max = if (include_availability) Inf else 0L)
      } else if (ext == "sav") {
        haven::read_sav(file, n_max = if (include_availability) Inf else 0L)
      } else {
        stop("Unsupported haven file type: ", ext, call. = FALSE)
      }
    },
    error = function(e) e
  )

  if (inherits(dat, "error")) {
    return(empty_inventory_row(source_info, NA_character_, "read_error", conditionMessage(dat)))
  }

  dat <- as.data.frame(dat, stringsAsFactors = FALSE)
  counts <- if (include_availability) table_counts(dat) else list(
    n_rows = NA_integer_,
    nonmissing = NULL,
    missing = NULL
  )
  make_inventory_rows(source_info, NA_character_, names(dat), counts$n_rows,
                      counts$nonmissing, counts$missing)
}

read_parquet_file <- function(file, source_info, include_availability) {
  if (!pkg_available("arrow")) {
    return(empty_inventory_row(
      source_info,
      NA_character_,
      "missing_package",
      "Package 'arrow' is required for Parquet files."
    ))
  }

  dat <- tryCatch(
    as.data.frame(arrow::read_parquet(file)),
    error = function(e) e
  )
  if (inherits(dat, "error")) {
    return(empty_inventory_row(source_info, NA_character_, "read_error", conditionMessage(dat)))
  }
  if (!include_availability) dat <- dat[0, , drop = FALSE]
  counts <- if (include_availability) table_counts(dat) else list(
    n_rows = NA_integer_,
    nonmissing = NULL,
    missing = NULL
  )
  make_inventory_rows(source_info, NA_character_, names(dat), counts$n_rows,
                      counts$nonmissing, counts$missing)
}

rectangular_tables_from_rds <- function(obj) {
  out <- list()
  add_table <- function(name, value) {
    if (is.data.frame(value)) {
      out[[name]] <<- as.data.frame(value, stringsAsFactors = FALSE)
    } else if (is.matrix(value) || is.array(value)) {
      dim_value <- dim(value)
      if (length(dim_value) == 2L) {
        out[[name]] <<- as.data.frame(value, stringsAsFactors = FALSE)
      }
    }
  }

  add_table("rds_object", obj)

  if (!length(out) && is.list(obj)) {
    nm <- names(obj)
    for (i in seq_along(obj)) {
      name <- if (!is.null(nm) && nzchar(nm[[i]])) nm[[i]] else paste0("list_", i)
      add_table(name, obj[[i]])
    }
  }

  out
}

read_rds_file <- function(file, source_info, include_availability) {
  obj <- tryCatch(readRDS(file), error = function(e) e)
  if (inherits(obj, "error")) {
    return(empty_inventory_row(source_info, "rds_object", "read_error", conditionMessage(obj)))
  }

  tables <- rectangular_tables_from_rds(obj)
  if (!length(tables)) {
    return(empty_inventory_row(
      source_info,
      paste(class(obj), collapse = "|"),
      "no_rectangular_object",
      "RDS object is not a data.frame, matrix, or top-level list of rectangular objects."
    ))
  }

  rows <- vector("list", length(tables))
  i <- 0L
  for (name in names(tables)) {
    i <- i + 1L
    dat <- tables[[name]]
    if (!include_availability) dat <- dat[0, , drop = FALSE]
    counts <- if (include_availability) table_counts(dat) else list(
      n_rows = NA_integer_,
      nonmissing = NULL,
      missing = NULL
    )
    rows[[i]] <- make_inventory_rows(source_info, name, names(dat), counts$n_rows,
                                     counts$nonmissing, counts$missing)
  }
  do.call(rbind, rows)
}

read_table_file <- function(file, source_info, include_availability) {
  ext <- source_info$file_type
  if (ext %in% c("csv", "tsv", "txt")) {
    read_delimited_file(file, source_info, include_availability)
  } else if (ext %in% c("xlsx", "xls")) {
    read_excel_file(file, source_info, include_availability)
  } else if (ext == "ods") {
    read_ods_file(file, source_info, include_availability)
  } else if (ext %in% c("sas7bdat", "dta", "sav")) {
    read_haven_file(file, source_info, include_availability)
  } else if (ext == "rds") {
    read_rds_file(file, source_info, include_availability)
  } else if (ext == "parquet") {
    read_parquet_file(file, source_info, include_availability)
  } else {
    empty_inventory_row(source_info, NA_character_, "unsupported_file_type",
                        paste0("Unsupported file extension: ", ext))
  }
}

read_zip_archive <- function(file, source_info, data_root, include_availability) {
  listing <- tryCatch(utils::unzip(file, list = TRUE), error = function(e) e)
  if (inherits(listing, "error")) {
    return(empty_inventory_row(source_info, NA_character_, "archive_list_error", conditionMessage(listing)))
  }

  members <- listing$Name
  member_ext <- path_ext(members)
  keep <- member_ext %in% supported_table_ext & !grepl("/$", members)
  members <- members[keep]

  if (!length(members)) {
    return(empty_inventory_row(source_info, NA_character_, "no_supported_archive_members",
                               "Archive contains no supported table files."))
  }

  tmp <- tempfile("profid_inventory_zip_")
  dir.create(tmp, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)

  rows <- vector("list", length(members))
  for (i in seq_along(members)) {
    member <- members[[i]]
    extracted <- tryCatch(
      {
        utils::unzip(file, files = member, exdir = tmp, overwrite = TRUE)
        file.path(tmp, member)
      },
      error = function(e) e
    )

    member_info <- source_info_for_path(file, data_root, archive_member = member)
    member_info$file_type <- path_ext(member)

    if (inherits(extracted, "error") || !file.exists(extracted)) {
      rows[[i]] <- empty_inventory_row(
        member_info,
        NA_character_,
        "archive_extract_error",
        if (inherits(extracted, "error")) conditionMessage(extracted) else "Extracted file was not found."
      )
      next
    }
    rows[[i]] <- read_table_file(extracted, member_info, include_availability)
  }
  do.call(rbind, rows)
}

read_archive_file <- function(file, source_info, data_root, include_availability) {
  ext <- path_ext(file)
  if (ext == "zip") {
    return(read_zip_archive(file, source_info, data_root, include_availability))
  }
  empty_inventory_row(
    source_info,
    NA_character_,
    "archive_not_scanned",
    "RAR archive scanning is not enabled by this script; list/extract with unrar first if needed."
  )
}

discover_files <- function(data_root, scope, include_archives) {
  all_files <- list.files(
    data_root,
    recursive = TRUE,
    full.names = TRUE,
    all.files = FALSE,
    no.. = TRUE
  )
  all_files <- all_files[file.exists(all_files) & !dir.exists(all_files)]
  all_files <- all_files[!grepl("(^|/)\\._", all_files)]
  all_files <- all_files[!grepl("(^|/)\\.DS_Store$", all_files)]

  rels <- vapply(all_files, rel_path, character(1), root = data_root)
  exts <- path_ext(all_files)
  supported <- exts %in% supported_table_ext |
    (include_archives & exts %in% supported_archive_ext)
  all_files <- all_files[supported]
  rels <- rels[supported]
  exts <- exts[supported]

  if (scope == "all_stages") {
    keep <- !grepl("(^|/)(results|logs)/", rels)
    return(all_files[keep])
  }

  keep <- rep(FALSE, length(all_files))
  keep <- keep | grepl("^Data_Transfer_to_Charite/", rels)
  keep <- keep | grepl("^datasets/local/[^/]+/data/(original|dictionary|maps|gran-support)/", rels)
  keep <- keep | grepl("^datasets/cdm/", rels)
  keep <- keep | grepl("^datasets/local/[^/]+/scripts/cdm/", rels)
  keep <- keep | grepl("^datasets/local/[^/]+/data/processed/.*common-data-model\\.rds$", rels)

  all_files[keep]
}

collapse_unique <- function(x, max_items = Inf) {
  x <- unique(as.character(x[!is.na(x) & nzchar(as.character(x))]))
  if (!length(x)) return(NA_character_)
  if (is.finite(max_items) && length(x) > max_items) {
    shown <- paste(x[seq_len(max_items)], collapse = " | ")
    return(paste0(shown, " | ... +", length(x) - max_items, " more"))
  }
  paste(x, collapse = " | ")
}

table_id_for_rows <- function(df) {
  archive <- ifelse(is.na(df$archive_member) | !nzchar(df$archive_member),
                    "", paste0("::", df$archive_member))
  sheet <- ifelse(is.na(df$sheet_or_object) | !nzchar(df$sheet_or_object),
                  "", paste0("::", df$sheet_or_object))
  paste0(df$relative_path, archive, sheet)
}

split_indices_by_keys <- function(df, keys) {
  key_df <- df[, keys, drop = FALSE]
  key_df[] <- lapply(key_df, function(x) {
    x <- as.character(x)
    x[is.na(x)] <- ""
    x
  })
  split(seq_len(nrow(df)), do.call(paste, c(key_df, sep = "\r")), drop = TRUE)
}

summarise_availability <- function(df, keys) {
  if (!nrow(df)) return(data.frame())

  df$table_id <- table_id_for_rows(df)
  groups <- split_indices_by_keys(df, keys)
  rows <- vector("list", length(groups))
  i <- 0L

  for (idx in groups) {
    i <- i + 1L
    g <- df[idx, , drop = FALSE]
    base <- g[1L, keys, drop = FALSE]
    rows[[i]] <- data.frame(
      base,
      source_datasets = collapse_unique(g$source_dataset),
      source_stages = collapse_unique(g$source_stage),
      source_kinds = collapse_unique(g$source_kind),
      count_units = collapse_unique(g$count_unit),
      n_source_datasets = length(unique(g$source_dataset)),
      n_source_tables = length(unique(g$table_id)),
      total_nonmissing_observation_points = sum(g$nonmissing_n, na.rm = TRUE),
      total_missing_observation_points = sum(g$missing_n, na.rm = TRUE),
      min_nonmissing_in_single_table = suppressWarnings(min(g$nonmissing_n, na.rm = TRUE)),
      max_nonmissing_in_single_table = suppressWarnings(max(g$nonmissing_n, na.rm = TRUE)),
      mean_nonmissing_pct = mean(g$nonmissing_pct, na.rm = TRUE),
      contributing_sources = collapse_unique(g$table_id, max_items = 12L),
      stringsAsFactors = FALSE
    )
  }

  out <- do.call(rbind, rows)
  out$min_nonmissing_in_single_table[!is.finite(out$min_nonmissing_in_single_table)] <- NA
  out$max_nonmissing_in_single_table[!is.finite(out$max_nonmissing_in_single_table)] <- NA
  out$mean_nonmissing_pct[!is.finite(out$mean_nonmissing_pct)] <- NA
  rownames(out) <- NULL
  out
}

read_substudy_config <- function(path) {
  if (!file.exists(path)) {
    warning("Substudy config not found: ", path, call. = FALSE)
    return(data.frame(
      substudy = character(0),
      source_dataset = character(0),
      source_stage = character(0),
      include_in_substudy_summary = logical(0),
      stringsAsFactors = FALSE
    ))
  }

  cfg <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  required <- c("substudy", "source_dataset", "source_stage", "include_in_substudy_summary")
  missing <- setdiff(required, names(cfg))
  if (length(missing)) {
    stop("Substudy config is missing columns: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  cfg$include_in_substudy_summary <- tolower(as.character(cfg$include_in_substudy_summary)) %in%
    c("true", "yes", "1", "y")
  cfg[cfg$include_in_substudy_summary, , drop = FALSE]
}

expand_for_substudies <- function(df, cfg) {
  if (!nrow(df)) return(df[0, , drop = FALSE])

  pieces <- vector("list", nrow(df))
  for (i in seq_len(nrow(df))) {
    row <- df[i, , drop = FALSE]
    matches <- cfg$substudy[
      cfg$source_dataset == row$source_dataset &
        (cfg$source_stage %in% c(row$source_stage, "any", "*"))
    ]
    studies <- unique(c("All_PROFID_sources", matches))
    expanded <- row[rep(1L, length(studies)), , drop = FALSE]
    expanded$substudy <- studies
    pieces[[i]] <- expanded
  }

  out <- do.call(rbind, pieces)
  rownames(out) <- NULL
  out
}

write_csv <- function(df, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(df, path, row.names = FALSE, na = "")
  message("Wrote: ", normalizePath(path, winslash = "/", mustWork = FALSE), " [", nrow(df), " rows]")
}

files <- discover_files(data_root, scope, include_archives)
if (!length(files)) {
  stop("No supported source files found under the requested data root and scope.", call. = FALSE)
}

message("Discovered supported files: ", length(files))

inventory_parts <- vector("list", length(files))
for (i in seq_along(files)) {
  file <- files[[i]]
  info <- source_info_for_path(file, data_root)
  message(sprintf("[%d/%d] %s", i, length(files), info$relative_path))
  ext <- path_ext(file)
  inventory_parts[[i]] <- tryCatch(
    {
      if (ext %in% supported_archive_ext) {
        read_archive_file(file, info, data_root, include_availability)
      } else {
        read_table_file(file, info, include_availability)
      }
    },
    error = function(e) empty_inventory_row(info, NA_character_, "read_error", conditionMessage(e))
  )
}

inventory <- do.call(rbind, inventory_parts)
rownames(inventory) <- NULL

structure_path <- file.path(out_dir, "profid_data_structure_master.csv")
write_csv(inventory, structure_path)

availability <- inventory[
  inventory$read_status == "ok" &
    inventory$is_observation_source &
    !is.na(inventory$column_name) &
    nzchar(inventory$column_name) &
    !is.na(inventory$nonmissing_n),
  ,
  drop = FALSE
]

covariates <- availability[availability$analysis_role == "covariate", , drop = FALSE]
outcomes <- availability[availability$analysis_role == "outcome", , drop = FALSE]

write_csv(covariates, file.path(out_dir, "profid_covariate_observation_points.csv"))
write_csv(outcomes, file.path(out_dir, "profid_outcome_observation_points.csv"))

summary_input <- availability[
  availability$analysis_role %in% c("covariate", "outcome", "unknown"),
  ,
  drop = FALSE
]

by_dataset <- summarise_availability(
  summary_input,
  c("source_dataset", "source_stage", "normalized_variable", "analysis_role", "domain_guess")
)
write_csv(by_dataset, file.path(out_dir, "profid_variable_availability_by_dataset.csv"))

cfg <- read_substudy_config(substudy_config)
message("Substudy config: ", normalizePath(substudy_config, winslash = "/", mustWork = FALSE))

substudy_input <- expand_for_substudies(summary_input, cfg)
by_substudy <- summarise_availability(
  substudy_input,
  c("substudy", "normalized_variable", "analysis_role", "domain_guess")
)
write_csv(by_substudy, file.path(out_dir, "profid_variable_availability_by_substudy.csv"))

status_summary <- as.data.frame(table(inventory$read_status), stringsAsFactors = FALSE)
names(status_summary) <- c("read_status", "n_rows")
write_csv(status_summary, file.path(out_dir, "profid_inventory_read_status_summary.csv"))
write_csv(reader_package_status, file.path(out_dir, "profid_inventory_reader_package_status.csv"))

message("Done.")
