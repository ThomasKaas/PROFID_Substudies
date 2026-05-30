#!/usr/bin/env Rscript

# Master runner for the Study1 analysis pipeline.
#
# Run from any working directory, for example:
#   Rscript Study1/master_run.R
#   ./Study1/run_study1.sh
#   Rscript Study1/master_run.R --stage analysis
#   Rscript Study1/master_run.R --from 3_clean --to 8_primary_cox
#   Rscript Study1/master_run.R --dry-run

args <- commandArgs(trailingOnly = TRUE)

usage <- function(status = 0L) {
  cat(
    "Usage:\n",
    "  Rscript Study1/master_run.R [options]\n\n",
    "Options:\n",
    "  --help                    Show this help text.\n",
    "  --dry-run                 Print the selected scripts without running them.\n",
    "  --stage <name>            Run one stage: all, preprocessing, analysis, core,\n",
    "                            descriptive, imputation, modeling, sensitivity.\n",
    "                            Default: all.\n",
    "  --from <step_id>          Start at a named step id.\n",
    "  --to <step_id>            Stop at a named step id.\n",
    "  --only <ids>              Comma-separated step ids to run.\n",
    "  --skip-optional           Skip optional QC/descriptive scripts.\n",
    "  --continue-on-error       Continue after a failed script and report failures\n",
    "                            at the end. Default is to stop immediately.\n\n",
    "Step ids, in default order:\n",
    sep = ""
  )
  for (i in seq_len(nrow(pipeline))) {
    cat(sprintf("  %-2d %-22s %s\n", i, pipeline$id[[i]], pipeline$label[[i]]))
  }
  quit(save = "no", status = status)
}

script_dir_from_args <- function() {
  cmd <- commandArgs(trailingOnly = FALSE)
  file_arg <- "--file="
  hit <- grep(paste0("^", file_arg), cmd, value = TRUE)
  if (length(hit)) {
    return(dirname(normalizePath(sub(file_arg, "", hit[[1]]), winslash = "/", mustWork = TRUE)))
  }
  normalizePath(getwd(), winslash = "/", mustWork = FALSE)
}

repo_root_from_script <- function() {
  script_dir <- script_dir_from_args()
  if (basename(script_dir) == "Study1") return(dirname(script_dir))
  if (dir.exists(file.path(script_dir, "Study1"))) return(script_dir)

  cwd <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  if (dir.exists(file.path(cwd, "Study1"))) return(cwd)
  if (basename(cwd) == "Study1") return(dirname(cwd))

  stop("Could not locate repository root containing Study1/.", call. = FALSE)
}

pipeline <- data.frame(
  id = c(
    "preprocess_eucert",
    "preprocess_helios",
    "preprocess_israel",
    "preprocess_prose",
    "variables_overview",
    "merge",
    "1_preliminary",
    "2_transform",
    "3_clean",
    "4_table1",
    "5_km1",
    "6_km2",
    "7_mice",
    "8_primary_cox",
    "9_landmark",
    "10_fine_gray"
  ),
  stage = c(
    rep("preprocessing", 4),
    "optional",
    "preprocessing",
    rep("core", 3),
    rep("descriptive", 3),
    "imputation",
    "modeling",
    rep("sensitivity", 2)
  ),
  optional = c(
    rep(FALSE, 4),
    TRUE,
    rep(FALSE, 4),
    rep(TRUE, 3),
    rep(FALSE, 4)
  ),
  script = c(
    "Study1/preprocessing_dataset_scripts/eucert_preprocessing.R",
    "Study1/preprocessing_dataset_scripts/helios_processing.R",
    "Study1/preprocessing_dataset_scripts/israel_processing.R",
    "Study1/preprocessing_dataset_scripts/prose_processing.R",
    "Study1/preprocessing_dataset_scripts/Variables_overview.R",
    "Study1/preprocessing_dataset_scripts/Final_merge_script.R",
    "Study1/1.Preliminary analysis.R",
    "Study1/2.Variable_transformation.R",
    "Study1/3.data_cleaning_incidence_power_calc.R",
    "Study1/4.Table 1 and table S3.R",
    "Study1/5.KM1.R",
    "Study1/6.KM2.R",
    "Study1/7.mice_full_cohort.R",
    "Study1/8.full_cohort_cox_model_and_development.R",
    "Study1/9.Landmark_analysis.R",
    "Study1/10.Fine_gray.R"
  ),
  label = c(
    "Preprocess EU-CERT-ICD",
    "Preprocess HELIOS",
    "Preprocess ISRAEL-ICD",
    "Preprocess PROSE-ICD",
    "Create variable-construction overview",
    "Merge preprocessed registries",
    "Standardise merged cohort",
    "Transform variables",
    "Clean final analysis cohort",
    "Create Table 1 and missingness table",
    "Create KM figure: time to FIS",
    "Create KM figure: survival by shock",
    "Run full-cohort MICE",
    "Run primary Cox model",
    "Run landmark Cox sensitivity",
    "Run Fine-Gray sensitivity"
  ),
  stringsAsFactors = FALSE
)

stage <- "all"
from_id <- NULL
to_id <- NULL
only_ids <- NULL
dry_run <- FALSE
skip_optional <- FALSE
continue_on_error <- FALSE

i <- 1L
while (i <= length(args)) {
  arg <- args[[i]]

  if (arg == "--help" || arg == "-h") {
    usage(0L)
  } else if (arg == "--dry-run") {
    dry_run <- TRUE
  } else if (arg == "--skip-optional") {
    skip_optional <- TRUE
  } else if (arg == "--continue-on-error") {
    continue_on_error <- TRUE
  } else if (arg == "--stage") {
    i <- i + 1L
    if (i > length(args)) stop("--stage requires a value.", call. = FALSE)
    stage <- args[[i]]
  } else if (arg == "--from") {
    i <- i + 1L
    if (i > length(args)) stop("--from requires a step id.", call. = FALSE)
    from_id <- args[[i]]
  } else if (arg == "--to") {
    i <- i + 1L
    if (i > length(args)) stop("--to requires a step id.", call. = FALSE)
    to_id <- args[[i]]
  } else if (arg == "--only") {
    i <- i + 1L
    if (i > length(args)) stop("--only requires comma-separated step ids.", call. = FALSE)
    only_ids <- trimws(strsplit(args[[i]], ",", fixed = TRUE)[[1]])
  } else {
    stop(sprintf("Unknown option: %s. Use --help for usage.", arg), call. = FALSE)
  }

  i <- i + 1L
}

known_stages <- c("all", "preprocessing", "analysis", "core", "descriptive",
                  "imputation", "modeling", "sensitivity")
if (!stage %in% known_stages) {
  stop(sprintf("Unknown stage '%s'. Known stages: %s",
               stage, paste(known_stages, collapse = ", ")), call. = FALSE)
}

selected <- pipeline

if (!is.null(only_ids)) {
  missing_ids <- setdiff(only_ids, pipeline$id)
  if (length(missing_ids)) {
    stop(sprintf("Unknown --only step id(s): %s", paste(missing_ids, collapse = ", ")),
         call. = FALSE)
  }
  selected <- pipeline[match(only_ids, pipeline$id), , drop = FALSE]
} else {
  if (stage == "preprocessing") {
    selected <- selected[selected$stage == "preprocessing", , drop = FALSE]
  } else if (stage == "analysis") {
    selected <- selected[selected$stage %in% c("core", "descriptive", "imputation",
                                              "modeling", "sensitivity"), , drop = FALSE]
  } else if (stage != "all") {
    selected <- selected[selected$stage == stage, , drop = FALSE]
  }

  if (!is.null(from_id)) {
    from_idx <- match(from_id, pipeline$id)
    if (is.na(from_idx)) stop(sprintf("Unknown --from step id: %s", from_id), call. = FALSE)
    selected <- selected[match(selected$id, pipeline$id) >= from_idx, , drop = FALSE]
  }

  if (!is.null(to_id)) {
    to_idx <- match(to_id, pipeline$id)
    if (is.na(to_idx)) stop(sprintf("Unknown --to step id: %s", to_id), call. = FALSE)
    selected <- selected[match(selected$id, pipeline$id) <= to_idx, , drop = FALSE]
  }
}

if (skip_optional) {
  selected <- selected[!selected$optional, , drop = FALSE]
}

if (nrow(selected) == 0L) {
  stop("No scripts selected. Check --stage, --from, --to, --only, and --skip-optional.",
       call. = FALSE)
}

repo_root <- repo_root_from_script()
old_wd <- getwd()
setwd(repo_root)
on.exit(setwd(old_wd), add = TRUE)

repos <- getOption("repos")
if (is.null(repos) || is.na(repos[["CRAN"]]) || identical(unname(repos[["CRAN"]]), "@CRAN@")) {
  options(repos = c(CRAN = "https://cloud.r-project.org"))
}

r_libs_user <- Sys.getenv("STUDY1_R_LIBS_USER", unset = Sys.getenv("R_LIBS_USER", unset = ""))
if (!nzchar(r_libs_user)) {
  r_libs_user <- file.path("~", "R", paste0(R.version$platform, "-library"),
                           paste(R.version$major, R.version$minor, sep = "."))
}
r_libs_user <- path.expand(r_libs_user)
dir.create(r_libs_user, recursive = TRUE, showWarnings = FALSE)
.libPaths(unique(c(r_libs_user, .libPaths())))

install_missing_packages <- function(pkgs, ...) {
  package_aliases <- list(
    tidyverse = c("ggplot2", "dplyr", "tidyr", "readr", "purrr", "tibble",
                  "stringr", "forcats"),
    ggsurvplot = character(0),
    survminer = character(0)
  )

  pkgs <- unlist(lapply(unique(as.character(pkgs)), function(pkg) {
    if (pkg %in% names(package_aliases)) package_aliases[[pkg]] else pkg
  }), use.names = FALSE)
  pkgs <- unique(pkgs)
  pkgs <- pkgs[nzchar(pkgs)]

  if (!length(pkgs)) {
    cat("No packages need installation for this request.\n")
    return(invisible(NULL))
  }

  missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]

  if ("gt" %in% missing) {
    gt_deps <- c("base64enc", "bitops", "cli", "commonmark", "dplyr", "fs",
                 "ggplot2", "glue", "htmltools", "magrittr", "rlang", "sass",
                 "scales", "stringr", "tibble", "tidyselect")
    gt_missing_deps <- gt_deps[!vapply(gt_deps, requireNamespace, logical(1), quietly = TRUE)]
    if (length(gt_missing_deps)) {
      cat(sprintf("Installing archived gt dependency package(s) into %s: %s\n",
                  r_libs_user, paste(gt_missing_deps, collapse = ", ")))
      utils::install.packages(gt_missing_deps, lib = r_libs_user, ...)
    }

    gt_archive_url <- "https://cran.r-project.org/src/contrib/Archive/gt/gt_0.7.0.tar.gz"
    cat(sprintf("Installing gt 0.7.0 from CRAN archive into %s\n", r_libs_user))
    utils::install.packages(gt_archive_url, lib = r_libs_user, repos = NULL, type = "source")
    missing <- setdiff(missing, "gt")
  }

  if (!length(missing)) {
    cat(sprintf("All requested packages already available: %s\n",
                paste(pkgs, collapse = ", ")))
    return(invisible(NULL))
  }

  cat(sprintf("Installing missing package(s) into %s: %s\n",
              r_libs_user, paste(missing, collapse = ", ")))
  utils::install.packages(missing, lib = r_libs_user, ...)
}

load_study1_package <- function(package, ..., character.only = FALSE) {
  pkg <- if (character.only) {
    as.character(package)
  } else {
    as.character(substitute(package))
  }

  if (identical(pkg, "tidyverse")) {
    core <- c("ggplot2", "dplyr", "tidyr", "readr", "purrr", "tibble",
              "stringr", "forcats")
    missing <- core[!vapply(core, requireNamespace, logical(1), quietly = TRUE)]
    if (length(missing)) install_missing_packages(missing)

    for (core_pkg in core) {
      base::library(core_pkg, character.only = TRUE, ...)
    }
    return(invisible(TRUE))
  }

  if (pkg %in% c("ggsurvplot", "survminer")) {
    cat(sprintf("Skipping optional package '%s'; Study1 KM scripts do not require it.\n", pkg))
    return(invisible(TRUE))
  }

  if (!requireNamespace(pkg, quietly = TRUE)) {
    install_missing_packages(pkg)
  }
  base::library(pkg, character.only = TRUE, ...)
}

missing_scripts <- selected$script[!file.exists(selected$script)]
if (length(missing_scripts)) {
  stop(sprintf("Missing script(s): %s", paste(missing_scripts, collapse = ", ")),
       call. = FALSE)
}

cat("Study1 master run\n")
cat(sprintf("Repository root: %s\n", repo_root))
cat(sprintf("R library path: %s\n", r_libs_user))
cat(sprintf("Selected scripts: %d\n\n", nrow(selected)))

for (j in seq_len(nrow(selected))) {
  cat(sprintf("%2d. %-22s %s\n", j, selected$id[[j]], selected$script[[j]]))
}
cat("\n")

if (dry_run) {
  cat("Dry run only; no scripts were executed.\n")
  quit(save = "no", status = 0L)
}

failures <- list()
started_at <- Sys.time()

for (j in seq_len(nrow(selected))) {
  step <- selected[j, , drop = FALSE]
  step_start <- Sys.time()

  cat("\n")
  cat(strrep("=", 78), "\n", sep = "")
  cat(sprintf("[%s] Starting %s: %s\n",
              format(step_start, "%Y-%m-%d %H:%M:%S"),
              step$id[[1]],
              step$label[[1]]))
  cat(sprintf("Script: %s\n", step$script[[1]]))
  cat(strrep("=", 78), "\n", sep = "")

  result <- tryCatch(
    {
      step_env <- new.env(parent = globalenv())
      step_env$install.packages <- install_missing_packages
      step_env$library <- load_study1_package
      sys.source(step$script[[1]], envir = step_env, keep.source = FALSE)
      NULL
    },
    error = function(e) e
  )

  elapsed <- difftime(Sys.time(), step_start, units = "mins")

  if (is.null(result)) {
    cat(sprintf("\n[%s] Finished %s in %.2f minutes.\n",
                format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                step$id[[1]],
                as.numeric(elapsed)))
  } else {
    msg <- conditionMessage(result)
    failures[[length(failures) + 1L]] <- list(id = step$id[[1]], script = step$script[[1]],
                                              message = msg)
    cat(sprintf("\n[%s] FAILED %s after %.2f minutes.\n",
                format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                step$id[[1]],
                as.numeric(elapsed)))
    cat(sprintf("Error: %s\n", msg))

    if (!continue_on_error) {
      cat("\nStopping after first failure. Use --continue-on-error to keep going.\n")
      quit(save = "no", status = 1L)
    }
  }
}

total_elapsed <- difftime(Sys.time(), started_at, units = "mins")

cat("\n")
cat(strrep("=", 78), "\n", sep = "")
if (length(failures)) {
  cat(sprintf("Study1 master run completed with %d failure(s) in %.2f minutes.\n",
              length(failures), as.numeric(total_elapsed)))
  for (failure in failures) {
    cat(sprintf("- %s (%s): %s\n", failure$id, failure$script, failure$message))
  }
  quit(save = "no", status = 1L)
}

cat(sprintf("Study1 master run completed successfully in %.2f minutes.\n",
            as.numeric(total_elapsed)))
quit(save = "no", status = 0L)
