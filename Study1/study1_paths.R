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

study1_hpc_data_root <- function() {
  Sys.getenv(
    "PROFID_DATA_ROOT",
    unset = "/sc-projects/sc-proj-dhzc-profid/PROFID_Substudies/data"
  )
}

study1_local_data_root_candidates <- function() {
  repo_root <- study1_repo_root()
  parent_root <- dirname(repo_root)

  unique(c(
    # The local protected-data checkout is kept outside this analysis
    # repository. Candidates are ordered from most to least project-specific.
    file.path(repo_root, "data"),
    file.path(parent_root, "PROFID_RAW_DATA"),
    file.path(dirname(parent_root), "PROFID_RAW_DATA")
  ))
}

study1_is_local_run <- function() {
  tolower(Sys.getenv("STUDY1_LOCAL", unset = "")) %in% c("1", "true", "yes")
}

profid_data_root <- function() {
  if (!study1_is_local_run()) {
    return(normalizePath(study1_hpc_data_root(), winslash = "/", mustWork = FALSE))
  }

  configured_root <- Sys.getenv("PROFID_LOCAL_DATA_ROOT", unset = "")
  if (nzchar(configured_root)) {
    if (!dir.exists(file.path(configured_root, "datasets"))) {
      stop(
        sprintf("PROFID_LOCAL_DATA_ROOT does not contain datasets/: %s", configured_root),
        call. = FALSE
      )
    }
    return(normalizePath(configured_root, winslash = "/", mustWork = FALSE))
  }

  candidates <- study1_local_data_root_candidates()
  usable <- candidates[dir.exists(file.path(candidates, "datasets"))]

  if (length(usable)) {
    return(normalizePath(usable[[1]], winslash = "/", mustWork = FALSE))
  }

  stop(
    paste(
      "Could not locate a local PROFID data root containing datasets/.",
      "Set PROFID_LOCAL_DATA_ROOT or run without --local on the HPC."
    ),
    call. = FALSE
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
  data_root <- profid_data_root()
  transfer_dirs <- c("Data_Transfer_to_Charite", "Data Transfer to Charite")
  available <- transfer_dirs[dir.exists(file.path(data_root, transfer_dirs))]
  transfer_dir <- if (length(available)) available[[1]] else transfer_dirs[[1]]

  file.path(data_root, transfer_dir, ...)
}

profid_dataset_path <- function(...) {
  profid_data_path("datasets", ...)
}

study1_derived_path <- function(...) {
  file.path(study1_derived_root(), ...)
}

study1_output_path <- function(...) {
  parts <- c(...)
  root <- study1_output_root()

  if (!length(parts)) return(root)

  leaf <- basename(parts[[length(parts)]])
  has_extension <- grepl("\\.[^./\\\\]+$", leaf)

  if (!has_extension) return(root)

  file.path(root, leaf)
}

study1_configure_headless_graphics <- function() {
  if (!identical(.Platform$OS.type, "unix")) return(invisible(FALSE))
  if (!identical(unname(Sys.info()[["sysname"]]), "Linux")) return(invisible(FALSE))

  current_bitmap <- getOption("bitmapType", default = "")
  has_display <- nzchar(Sys.getenv("DISPLAY", unset = ""))

  if (isTRUE(capabilities("cairo")) &&
      (!has_display || identical(current_bitmap, "Xlib"))) {
    options(bitmapType = "cairo")
    return(invisible(TRUE))
  }

  if (!has_display && !isTRUE(capabilities("cairo"))) {
    warning(
      "No graphical DISPLAY is available and this R build has no cairo support; PNG output may fail.",
      call. = FALSE
    )
  }

  invisible(FALSE)
}

study1_configure_headless_graphics()

study1_file_ready <- function(file) {
  if (!file.exists(file)) return(FALSE)
  size <- file.info(file)$size
  is.finite(size) && !is.na(size) && size > 0
}

study1_save_plot <- function(plot, png_file, pdf_file, width, height, dpi = 300) {
  dir.create(dirname(png_file), recursive = TRUE, showWarnings = FALSE)
  dir.create(dirname(pdf_file), recursive = TRUE, showWarnings = FALSE)

  pdf_devices <- list()
  if (capabilities("cairo")) {
    pdf_devices[["grDevices::cairo_pdf"]] <- grDevices::cairo_pdf
  }
  pdf_devices[["grDevices::pdf"]] <- grDevices::pdf

  pdf_errors <- character(0)
  for (device_name in names(pdf_devices)) {
    ok <- tryCatch(
      {
        ggplot2::ggsave(
          filename = pdf_file,
          plot = plot,
          width = width,
          height = height,
          device = pdf_devices[[device_name]]
        )
        if (!study1_file_ready(pdf_file)) {
          stop(sprintf("device completed but did not create a non-empty file: %s", pdf_file),
               call. = FALSE)
        }
        TRUE
      },
      error = function(e) {
        pdf_errors <<- c(pdf_errors, sprintf("%s: %s", device_name, conditionMessage(e)))
        FALSE
      }
    )

    if (ok) break
  }

  if (!study1_file_ready(pdf_file)) {
    warning(
      sprintf(
        "Could not save PDF '%s'. Tried: %s",
        pdf_file,
        if (length(pdf_errors)) paste(pdf_errors, collapse = "; ") else "none"
      ),
      call. = FALSE
    )
  }

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
        if (!study1_file_ready(png_file)) {
          stop(sprintf("device completed but did not create a non-empty file: %s", png_file),
               call. = FALSE)
        }
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

study1_save_grid <- function(draw, png_file, pdf_file, png_width, png_height,
                             png_res = 300, pdf_width, pdf_height) {
  stopifnot(is.function(draw))

  dir.create(dirname(png_file), recursive = TRUE, showWarnings = FALSE)
  dir.create(dirname(pdf_file), recursive = TRUE, showWarnings = FALSE)

  pdf_devices <- list()
  if (capabilities("cairo")) {
    pdf_devices[["grDevices::cairo_pdf"]] <- grDevices::cairo_pdf
  }
  pdf_devices[["grDevices::pdf"]] <- grDevices::pdf

  pdf_errors <- character(0)
  for (device_name in names(pdf_devices)) {
    opened_device <- NA_integer_
    ok <- tryCatch(
      {
        pdf_devices[[device_name]](pdf_file, width = pdf_width, height = pdf_height)
        opened_device <- grDevices::dev.cur()
        tryCatch(
          draw(),
          finally = {
            if (!is.na(opened_device) && opened_device > 1L &&
                grDevices::dev.cur() == opened_device) {
              grDevices::dev.off()
            }
          }
        )
        if (!study1_file_ready(pdf_file)) {
          stop(sprintf("device completed but did not create a non-empty file: %s", pdf_file),
               call. = FALSE)
        }
        TRUE
      },
      error = function(e) {
        if (!is.na(opened_device) && opened_device > 1L &&
            grDevices::dev.cur() == opened_device) {
          grDevices::dev.off()
        }
        pdf_errors <<- c(pdf_errors, sprintf("%s: %s", device_name, conditionMessage(e)))
        FALSE
      }
    )

    if (ok) break
  }

  if (!study1_file_ready(pdf_file)) {
    warning(
      sprintf(
        "Could not save PDF '%s'. Tried: %s",
        pdf_file,
        if (length(pdf_errors)) paste(pdf_errors, collapse = "; ") else "none"
      ),
      call. = FALSE
    )
  }

  png_devices <- list()

  if (requireNamespace("ragg", quietly = TRUE)) {
    png_devices[["ragg::agg_png"]] <- function(filename) {
      ragg::agg_png(
        filename = filename,
        width = png_width,
        height = png_height,
        units = "px",
        res = png_res,
        background = "white"
      )
    }
  }

  if (capabilities("cairo")) {
    png_devices[["grDevices::png(type = 'cairo')"]] <- function(filename) {
      grDevices::png(
        filename = filename,
        width = png_width,
        height = png_height,
        units = "px",
        res = png_res,
        type = "cairo",
        bg = "white"
      )
    }
  }

  if (nzchar(Sys.which("gs"))) {
    png_devices[["grDevices::bitmap(type = 'png16m')"]] <- function(filename) {
      grDevices::bitmap(
        file = filename,
        type = "png16m",
        width = png_width / png_res,
        height = png_height / png_res,
        units = "in",
        res = png_res
      )
    }
  }

  png_errors <- character(0)
  for (device_name in names(png_devices)) {
    opened_device <- NA_integer_
    ok <- tryCatch(
      {
        png_devices[[device_name]](png_file)
        opened_device <- grDevices::dev.cur()
        tryCatch(
          draw(),
          finally = {
            if (!is.na(opened_device) && opened_device > 1L &&
                grDevices::dev.cur() == opened_device) {
              grDevices::dev.off()
            }
          }
        )
        if (!study1_file_ready(png_file)) {
          stop(sprintf("device completed but did not create a non-empty file: %s", png_file),
               call. = FALSE)
        }
        TRUE
      },
      error = function(e) {
        if (!is.na(opened_device) && opened_device > 1L &&
            grDevices::dev.cur() == opened_device) {
          grDevices::dev.off()
        }
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
