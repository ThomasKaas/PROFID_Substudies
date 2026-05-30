# Shared path helpers for Study1.
#
# Defaults are set for the PROFID HPC repository layout, with environment
# variables available for local or test runs.

.study1_current_file <- function() {
  frames <- sys.frames()
  files <- vapply(frames, function(frame) {
    if (!is.null(frame$ofile)) frame$ofile else NA_character_
  }, character(1))
  files <- files[!is.na(files)]

  if (length(files) == 0L) return(NA_character_)
  normalizePath(files[[length(files)]], winslash = "/", mustWork = FALSE)
}

study1_repo_root <- function() {
  env_root <- Sys.getenv("PROFID_REPO_ROOT", unset = "")
  if (nzchar(env_root)) {
    return(normalizePath(env_root, winslash = "/", mustWork = FALSE))
  }

  current_file <- .study1_current_file()
  if (!is.na(current_file)) {
    return(dirname(dirname(current_file)))
  }

  cwd <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  if (dir.exists(file.path(cwd, "Study1"))) return(cwd)
  if (basename(cwd) == "Study1") return(dirname(cwd))
  if (basename(dirname(cwd)) == "Study1") return(dirname(dirname(cwd)))

  cwd
}

profid_data_root <- function() {
  Sys.getenv(
    "PROFID_DATA_ROOT",
    unset = "/sc-projects/sc-proj-dhzc-profid/PROFID_Substudies/data"
  )
}

study1_derived_root <- function() {
  Sys.getenv(
    "PROFID_STUDY1_DERIVED_ROOT",
    unset = profid_data_path("derived", "Study1")
  )
}

study1_output_root <- function() {
  Sys.getenv(
    "PROFID_STUDY1_OUTPUT_ROOT",
    unset = file.path(study1_repo_root(), "Study1", "outputs")
  )
}

profid_data_path <- function(...) {
  file.path(profid_data_root(), ...)
}

profid_transfer_path <- function(...) {
  profid_data_path("Data_Transfer_to_Charite", ...)
}

profid_dataset_path <- function(...) {
  profid_data_path("datasets", ...)
}

study1_derived_path <- function(...) {
  file.path(study1_derived_root(), ...)
}

study1_output_path <- function(...) {
  file.path(study1_output_root(), ...)
}

