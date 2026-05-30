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

study1_save_plot <- function(plot, png_file, pdf_file, width, height, dpi = 300) {
  dir.create(dirname(png_file), recursive = TRUE, showWarnings = FALSE)
  dir.create(dirname(pdf_file), recursive = TRUE, showWarnings = FALSE)

  pdf_device <- if (capabilities("cairo")) grDevices::cairo_pdf else grDevices::pdf
  ggplot2::ggsave(
    filename = pdf_file,
    plot = plot,
    width = width,
    height = height,
    device = pdf_device
  )

  png_devices <- list()

  if (requireNamespace("ragg", quietly = TRUE)) {
    png_devices[["ragg::agg_png"]] <- ragg::agg_png
  }

  if (capabilities("cairo")) {
    png_devices[["grDevices::png(type = 'cairo')"]] <- function(filename, width, height, units, res, ...) {
      grDevices::png(
        filename = filename,
        width = width,
        height = height,
        units = units,
        res = res,
        type = "cairo",
        ...
      )
    }
  }

  if (nzchar(Sys.which("gs"))) {
    png_devices[["grDevices::bitmap(type = 'png16m')"]] <- function(filename, width, height, units, res, ...) {
      grDevices::bitmap(
        file = filename,
        type = "png16m",
        width = width,
        height = height,
        units = units,
        res = res,
        ...
      )
    }
  }

  png_errors <- character(0)
  for (device_name in names(png_devices)) {
    ok <- tryCatch(
      {
        ggplot2::ggsave(
          filename = png_file,
          plot = plot,
          width = width,
          height = height,
          dpi = dpi,
          device = png_devices[[device_name]],
          bg = "white"
        )
        TRUE
      },
      error = function(e) {
        png_errors <<- c(png_errors, sprintf("%s: %s", device_name, conditionMessage(e)))
        FALSE
      }
    )

    if (ok) return(invisible(TRUE))
  }

  warning(
    sprintf(
      paste(
        "Saved PDF but could not save PNG '%s'.",
        "No working headless PNG device was available.",
        "Tried: %s"
      ),
      png_file,
      if (length(png_errors)) paste(png_errors, collapse = "; ") else "none"
    ),
    call. = FALSE
  )

  invisible(FALSE)
}
