#!/usr/bin/env Rscript

# Master runner for the Study3 analysis pipeline.
#
# Run from any working directory, for example:
#   Rscript Study3/master_run.R
#   ./Study3/run_study3.sh
#   Rscript Study3/master_run.R --stage analysis
#   Rscript Study3/master_run.R --from merge --to descriptive
#   Rscript Study3/master_run.R --dry-run
#   Rscript Study3/master_run.R --local
#   Rscript Study3/master_run.R --local --debugging
#   Rscript Study3/master_run.R --debugging

args <- commandArgs(trailingOnly = TRUE)

usage <- function(status = 0L) {
  cat(
    "Usage:\n",
    "  Rscript Study3/master_run.R [options]\n\n",
    "Options:\n",
    "  --help                    Show this help text.\n",
    "  --dry-run                 Print the selected scripts without running them.\n",
    "  --local                   Use /Users/thomaskaas/PROFID_RAW_DATA for raw inputs.\n",
    "  --debugging               Print detailed cohort, field, and model-input diagnostics.\n",
    "  --stage <name>            Run one stage: all, preprocessing, analysis,\n",
    "                            descriptive, modeling, sensitivity, imputation.\n",
    "                            Default: all.\n",
    "  --from <step_id>          Start at a named step id.\n",
    "  --to <step_id>            Stop at a named step id.\n",
    "  --only <ids>              Comma-separated step ids to run.\n",
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
  if (basename(script_dir) == "Study3") return(dirname(script_dir))
  if (dir.exists(file.path(script_dir, "Study3"))) return(script_dir)

  cwd <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  if (dir.exists(file.path(cwd, "Study3"))) return(cwd)
  if (basename(cwd) == "Study3") return(dirname(cwd))

  stop("Could not locate repository root containing Study3/.", call. = FALSE)
}

pipeline <- data.frame(
  id = c(
    "preprocess_eucert",
    "preprocess_helios",
    "preprocess_israel",
    "preprocess_prose",
    "preprocess_lcv",
    "merge",
    "descriptive",
    "primary_cox",
    "km_fine_gray",
    "secondary",
    "sensitivity_180d",
    "mice"
  ),
  stage = c(
    rep("preprocessing", 6),
    "descriptive",
    rep("modeling", 3),
    "sensitivity",
    "imputation"
  ),
  script = c(
    "Study3/01_eucert_initial_cleaning.R",
    "Study3/02_Helios_initial_cleaning.R",
    "Study3/03_israel_initial_cleaning.R",
    "Study3/04_prose_inital cleaning.R",
    "Study3/05_LCV_initial_script.R",
    "Study3/06_Dataset_merging_updated.R",
    "Study3/07_Descriptive_Table1_Table2.R",
    "Study3/08_Cox models.R",
    "Study3/09_Kaplan Maier and Fine Gray.R",
    "Study3/10_secondary analysis.R",
    "Study3/11_sensitivty analysis (180 days).R",
    "Study3/12_MICE.R"
  ),
  label = c(
    "Clean EU-CERT event data",
    "Clean HELIOS event data",
    "Clean Israel event data",
    "Clean PROSE event data",
    "Clean LCV event data",
    "Merge event data with baseline ICD data",
    "Create descriptive tables and analysis cohort",
    "Run primary Cox models",
    "Run Kaplan-Meier and Fine-Gray analyses",
    "Run secondary analyses",
    "Run 180-day sensitivity analyses",
    "Run MICE sensitivity analysis"
  ),
  stringsAsFactors = FALSE
)

stage <- "all"
from_id <- NULL
to_id <- NULL
only_ids <- NULL
dry_run <- FALSE
local <- FALSE
debugging <- FALSE
continue_on_error <- FALSE

i <- 1L
while (i <= length(args)) {
  arg <- args[[i]]

  if (arg == "--help" || arg == "-h") {
    usage(0L)
  } else if (arg == "--dry-run") {
    dry_run <- TRUE
  } else if (arg == "--local") {
    local <- TRUE
  } else if (arg == "--debugging") {
    debugging <- TRUE
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

known_stages <- c("all", "preprocessing", "analysis", "descriptive",
                  "modeling", "sensitivity", "imputation")
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
  if (stage == "analysis") {
    selected <- selected[selected$stage %in% c("descriptive", "modeling",
                                              "sensitivity", "imputation"), , drop = FALSE]
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

if (nrow(selected) == 0L) {
  stop("No scripts selected. Check --stage, --from, --to, and --only.",
       call. = FALSE)
}

repo_root <- repo_root_from_script()
old_wd <- getwd()
setwd(repo_root)
on.exit(setwd(old_wd), add = TRUE)

local_data_root <- "/Users/thomaskaas/PROFID_RAW_DATA"
local_derived_root <- file.path(local_data_root, "derived", "Study3")
if (local) {
  if (!dir.exists(local_data_root)) {
    stop(sprintf("Local data root does not exist: %s", local_data_root), call. = FALSE)
  }
  Sys.setenv(
    PROFID_DATA_ROOT = local_data_root,
    PROFID_STUDY3_DERIVED_ROOT = local_derived_root
  )
}

Sys.setenv(STUDY3_DEBUGGING = if (debugging) "1" else "0")

run_timestamp <- Sys.getenv("STUDY3_RUN_TIMESTAMP", unset = "")
if (!nzchar(run_timestamp)) {
  run_timestamp <- format(Sys.time(), "%Y-%m-%d_%H-%M-%S")
  Sys.setenv(STUDY3_RUN_TIMESTAMP = run_timestamp)
}

output_dir <- Sys.getenv(
  "PROFID_STUDY3_OUTPUT_ROOT",
  unset = file.path(repo_root, "Study3", "outputs")
)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
log_file <- file.path(output_dir, sprintf("master_run_%s.txt", run_timestamp))
log_con <- file(log_file, open = "wt")
sink(log_con, split = TRUE)
on.exit({
  sink()
  close(log_con)
}, add = TRUE)
cat(sprintf("Master run log: %s\n\n", log_file))

repos <- getOption("repos")
if (is.null(repos) || is.na(repos[["CRAN"]]) || identical(unname(repos[["CRAN"]]), "@CRAN@")) {
  options(repos = c(CRAN = "https://cloud.r-project.org"))
}

r_libs_user <- Sys.getenv("STUDY3_R_LIBS_USER", unset = Sys.getenv("R_LIBS_USER", unset = ""))
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
  if (!length(missing)) {
    cat(sprintf("All requested packages already available: %s\n",
                paste(pkgs, collapse = ", ")))
    return(invisible(NULL))
  }

  cat(sprintf("Installing missing package(s) into %s: %s\n",
              r_libs_user, paste(missing, collapse = ", ")))
  utils::install.packages(missing, lib = r_libs_user, ...)
}

load_study3_package <- function(package, ..., character.only = FALSE) {
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
    cat(sprintf("Skipping optional package '%s'; Study3 scripts do not require it.\n", pkg))
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

cat("Study3 master run\n")
cat(sprintf("Repository root: %s\n", repo_root))
cat(sprintf("R library path: %s\n", r_libs_user))
cat(sprintf("Execution mode: %s\n", if (local) "local" else "default/HPC"))
if (local) {
  cat(sprintf("Local raw-data root: %s\n", local_data_root))
  cat(sprintf("Local derived-data root: %s\n", local_derived_root))
}
cat(sprintf("Debugging output: %s\n", if (debugging) "enabled" else "disabled"))
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
      step_parent <- new.env(parent = globalenv())
      step_parent$install.packages <- install_missing_packages
      step_parent$library <- load_study3_package
      step_env <- new.env(parent = step_parent)
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
  cat(sprintf("Study3 master run completed with %d failure(s) in %.2f minutes.\n",
              length(failures), as.numeric(total_elapsed)))
  for (failure in failures) {
    cat(sprintf("- %s (%s): %s\n", failure$id, failure$script, failure$message))
  }
  quit(save = "no", status = 1L)
}

cat(sprintf("Study3 master run completed successfully in %.2f minutes.\n",
            as.numeric(total_elapsed)))
quit(save = "no", status = 0L)
