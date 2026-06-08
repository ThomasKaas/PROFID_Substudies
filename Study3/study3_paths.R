# Shared path helpers for Study3.
#
# Defaults are set for the PROFID HPC repository layout. The master runner's
# --local mode and explicit environment variables support local or test runs.

.study3_current_file <- function() {
  frames <- sys.frames()
  files <- vapply(frames, function(frame) {
    if (!is.null(frame$ofile)) frame$ofile else NA_character_
  }, character(1))
  files <- files[!is.na(files)]

  if (length(files) == 0L) return(NA_character_)
  normalizePath(files[[length(files)]], winslash = "/", mustWork = FALSE)
}

study3_repo_root <- function() {
  env_root <- Sys.getenv("PROFID_REPO_ROOT", unset = "")
  if (nzchar(env_root)) {
    return(normalizePath(env_root, winslash = "/", mustWork = FALSE))
  }

  current_file <- .study3_current_file()
  if (!is.na(current_file)) {
    return(dirname(dirname(current_file)))
  }

  cwd <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  if (dir.exists(file.path(cwd, "Study3"))) return(cwd)
  if (basename(cwd) == "Study3") return(dirname(cwd))
  if (basename(dirname(cwd)) == "Study3") return(dirname(dirname(cwd)))

  cwd
}

profid_data_root <- function() {
  Sys.getenv(
    "PROFID_DATA_ROOT",
    unset = "/sc-projects/sc-proj-dhzc-profid/PROFID_Substudies/data"
  )
}

study3_raw_root <- function() {
  env_root <- Sys.getenv("PROFID_STUDY3_RAW_ROOT", unset = "")
  if (nzchar(env_root)) {
    return(normalizePath(env_root, winslash = "/", mustWork = FALSE))
  }

  roots <- c(
    profid_data_path("raw", "Study3"),
    file.path(study3_repo_root(), "Study3"),
    study3_repo_root(),
    profid_data_path("Study3"),
    profid_data_path("Data_Transfer_to_Charite", "Study3"),
    profid_data_path("Data_Transfer_to_Charite")
  )

  existing <- roots[dir.exists(roots)]
  if (length(existing)) return(normalizePath(existing[[1]], winslash = "/", mustWork = FALSE))

  roots[[1]]
}

study3_derived_root <- function() {
  Sys.getenv(
    "PROFID_STUDY3_DERIVED_ROOT",
    unset = profid_data_path("derived", "Study3")
  )
}

study3_output_root <- function() {
  Sys.getenv(
    "PROFID_STUDY3_OUTPUT_ROOT",
    unset = file.path(study3_repo_root(), "Study3", "outputs")
  )
}

study3_metadata_root <- function() {
  env_root <- Sys.getenv("PROFID_STUDY3_METADATA_ROOT", unset = "")
  if (nzchar(env_root)) {
    return(normalizePath(env_root, winslash = "/", mustWork = FALSE))
  }

  roots <- c(
    file.path(study3_repo_root(), "Study3"),
    file.path(study3_repo_root(), "Study3", "metadata"),
    file.path(study3_repo_root(), "Study3", "Study3", "metadata")
  )

  existing <- roots[dir.exists(roots)]
  if (length(existing)) return(normalizePath(existing[[1]], winslash = "/", mustWork = FALSE))

  roots[[1]]
}

profid_data_path <- function(...) {
  file.path(profid_data_root(), ...)
}

profid_transfer_path <- function(...) {
  parts <- c(...)
  candidates <- file.path(
    c(
      profid_data_path("Data_Transfer_to_Charite"),
      profid_data_path("Data Transfer to Charite"),
      study3_repo_root(),
      file.path(study3_repo_root(), "Study3"),
      study3_raw_root()
    ),
    do.call(file.path, as.list(parts))
  )

  existing <- candidates[file.exists(candidates)]
  if (length(existing)) return(normalizePath(existing[[1]], winslash = "/", mustWork = FALSE))

  candidates[[1]]
}

profid_dataset_path <- function(...) {
  profid_data_path("datasets", ...)
}

.study3_raw_alias_paths <- function(file) {
  aliases <- list(
    "eu-cert-icd.csv" = list(
      profid_dataset_path("local", "eu-cert-icd", "data", "original",
                          "registry_data_eu-cert-icd_selection_161019-Data-sheet.csv")
    ),
    "Helius.xlsx" = list(
      profid_dataset_path("local", "helios-rdb", "data", "original",
                          "Final_delivery.2021-05-20._Ali EDxlsx.xlsx"),
      profid_dataset_path("local", "helios-rdb", "data", "processed",
                          "hels-phase-1.xlsx")
    ),
    "israeli.csv" = list(
      profid_dataset_path("local", "israeli-icd", "data", "original",
                          "ICDALL_20170630.csv")
    ),
    "prose.xlsx" = list(
      profid_dataset_path("local", "prose-icd", "data", "original",
                          "FinaltoPROFID_PROSEonlysent_no_password.xlsx"),
      profid_dataset_path("local", "prose-lvscd", "data", "original",
                          "FinaltoPROFID_PROSEonlysent_no_password.xlsx")
    ),
    "LCV.xlsx" = list(
      profid_dataset_path("local", "prose-lvscd", "data", "original",
                          "FinaltoPROFID_LVSCDonlySent_no_password.xlsx"),
      profid_dataset_path("local", "prose-icd", "data", "original",
                          "FinaltoPROFID_LVSCDonlySent_no_password.xlsx")
    ),
    "PROSE_LCVcommon participant.csv" = list(
      profid_dataset_path("local", "prose-icd", "data", "original",
                          "FinaltoPROFID_PROSEonlysent_coenrolled.csv"),
      profid_dataset_path("local", "prose-lvscd", "data", "original",
                          "FinaltoPROFID_PROSEonlysent_coenrolled.csv")
    )
  )

  out <- aliases[[file]]
  if (is.null(out)) character(0) else unlist(out, use.names = FALSE)
}

study3_raw_path <- function(...) {
  parts <- c(...)
  requested <- do.call(file.path, as.list(parts))
  roots <- unique(c(
    Sys.getenv("PROFID_STUDY3_RAW_ROOT", unset = ""),
    profid_data_path("raw", "Study3"),
    file.path(study3_repo_root(), "Study3"),
    study3_repo_root(),
    profid_data_path("Study3"),
    profid_data_path("Data_Transfer_to_Charite", "Study3"),
    profid_data_path("Data_Transfer_to_Charite")
  ))
  roots <- roots[nzchar(roots)]
  candidates <- file.path(roots, do.call(file.path, as.list(parts)))
  if (length(parts) == 1L) {
    candidates <- c(candidates, .study3_raw_alias_paths(parts[[1]]))
  }

  existing <- candidates[file.exists(candidates)]
  if (length(existing)) return(normalizePath(existing[[1]], winslash = "/", mustWork = FALSE))

  stop(
    sprintf(
      paste(
        "Study3 raw input file not found: %s",
        "Checked:",
        "%s",
        "Set PROFID_STUDY3_RAW_ROOT to the directory containing this file if it is stored elsewhere.",
        sep = "\n"
      ),
      requested,
      paste(sprintf("  - %s", candidates), collapse = "\n")
    ),
    call. = FALSE
  )
}

study3_derived_path <- function(...) {
  file.path(study3_derived_root(), ...)
}

study3_output_path <- function(...) {
  parts <- c(...)
  root <- study3_output_root()

  if (!length(parts)) return(root)

  file.path(root, ...)
}

study3_metadata_path <- function(...) {
  parts <- c(...)
  roots <- unique(c(
    Sys.getenv("PROFID_STUDY3_METADATA_ROOT", unset = ""),
    file.path(study3_repo_root(), "Study3"),
    file.path(study3_repo_root(), "Study3", "metadata"),
    file.path(study3_repo_root(), "Study3", "Study3", "metadata")
  ))
  roots <- roots[nzchar(roots)]
  candidates <- file.path(roots, do.call(file.path, as.list(parts)))

  existing <- candidates[file.exists(candidates)]
  if (length(existing)) return(normalizePath(existing[[1]], winslash = "/", mustWork = FALSE))

  candidates[[1]]
}

study3_configure_headless_graphics <- function() {
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

study3_configure_headless_graphics()

study3_file_ready <- function(file) {
  if (!file.exists(file)) return(FALSE)
  size <- file.info(file)$size
  is.finite(size) && !is.na(size) && size > 0
}

study3_debugging_enabled <- function() {
  tolower(trimws(Sys.getenv("STUDY3_DEBUGGING", unset = "0"))) %in%
    c("1", "true", "yes", "on")
}

study3_debug_section <- function(title) {
  if (!study3_debugging_enabled()) return(invisible(FALSE))
  cat("\n", strrep("-", 78), "\n", sep = "")
  cat("DEBUG: ", title, "\n", sep = "")
  cat(strrep("-", 78), "\n", sep = "")
  invisible(TRUE)
}

study3_debug_print <- function(x, title = NULL) {
  if (!study3_debugging_enabled()) return(invisible(FALSE))
  if (!is.null(title)) study3_debug_section(title)
  print(x)
  invisible(TRUE)
}

study3_debug_columns <- function(dt, columns, title) {
  if (!study3_debugging_enabled()) return(invisible(FALSE))
  columns <- intersect(columns, names(dt))
  study3_debug_section(title)
  if (!length(columns)) {
    cat("None of the requested columns are present.\n")
    return(invisible(TRUE))
  }

  result <- data.table::rbindlist(lapply(columns, function(column) {
    x <- dt[[column]]
    nonmissing <- !is.na(x)
    nonblank <- nonmissing
    if (is.character(x) || is.factor(x)) {
      nonblank <- nonmissing & trimws(as.character(x)) != ""
    }
    numeric_x <- suppressWarnings(as.numeric(x))
    data.table::data.table(
      column = column,
      class = paste(class(x), collapse = "/"),
      n = length(x),
      missing = sum(is.na(x)),
      nonblank = sum(nonblank),
      numeric_positive = sum(!is.na(numeric_x) & numeric_x > 0),
      numeric_min = if (any(!is.na(numeric_x))) min(numeric_x, na.rm = TRUE) else NA_real_,
      numeric_median = if (any(!is.na(numeric_x))) stats::median(numeric_x, na.rm = TRUE) else NA_real_,
      numeric_max = if (any(!is.na(numeric_x))) max(numeric_x, na.rm = TRUE) else NA_real_
    )
  }), use.names = TRUE, fill = TRUE)
  print(result)
  invisible(TRUE)
}

study3_add_inapp_shock_event <- function(dt) {
  if (!requireNamespace("data.table", quietly = TRUE)) {
    stop("Package 'data.table' is required to derive event_inapp_shock.", call. = FALSE)
  }
  data.table::setDT(dt)

  required <- c("inapp_shock_flag", "t_followup_days_final")
  missing <- setdiff(required, names(dt))
  if (length(missing)) {
    stop(
      sprintf("Cannot derive event_inapp_shock; missing column(s): %s",
              paste(missing, collapse = ", ")),
      call. = FALSE
    )
  }

  dt[, inapp_shock_flag_std := tolower(trimws(as.character(inapp_shock_flag)))]
  dt[, event_inapp_shock := data.table::fifelse(
    inapp_shock_flag_std == "yes",
    1L,
    0L,
    na = 0L
  )]

  if ("days_to_inapp_shock" %in% names(dt)) {
    dt[
      event_inapp_shock == 1 &
        !is.na(days_to_inapp_shock) &
        days_to_inapp_shock > t_followup_days_final,
      days_to_inapp_shock := t_followup_days_final
    ]
  }

  invisible(dt)
}

study3_save_plot <- function(plot, png_file, pdf_file, width, height, dpi = 300) {
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
        if (!study3_file_ready(pdf_file)) {
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

  if (!study3_file_ready(pdf_file)) {
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
        if (!study3_file_ready(png_file)) {
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

study3_save_grid <- function(draw, png_file, pdf_file, png_width, png_height,
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
    ok <- tryCatch(
      {
        before_device <- grDevices::dev.cur()
        pdf_devices[[device_name]](pdf_file, width = pdf_width, height = pdf_height)
        if (grDevices::dev.cur() == before_device) {
          stop(sprintf("device did not open: %s", device_name), call. = FALSE)
        }
        tryCatch(
          draw(),
          finally = if (grDevices::dev.cur() > before_device) grDevices::dev.off()
        )
        if (!study3_file_ready(pdf_file)) {
          stop(sprintf("device completed but did not create a non-empty file: %s", pdf_file),
               call. = FALSE)
        }
        TRUE
      },
      error = function(e) {
        if (exists("before_device") && grDevices::dev.cur() > before_device) {
          grDevices::dev.off()
        }
        pdf_errors <<- c(pdf_errors, sprintf("%s: %s", device_name, conditionMessage(e)))
        FALSE
      }
    )

    if (ok) break
  }

  if (!study3_file_ready(pdf_file)) {
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
    ok <- tryCatch(
      {
        before_device <- grDevices::dev.cur()
        png_devices[[device_name]](png_file)
        if (grDevices::dev.cur() == before_device) {
          stop(sprintf("device did not open: %s", device_name), call. = FALSE)
        }
        tryCatch(
          draw(),
          finally = if (grDevices::dev.cur() > before_device) grDevices::dev.off()
        )
        if (!study3_file_ready(png_file)) {
          stop(sprintf("device completed but did not create a non-empty file: %s", png_file),
               call. = FALSE)
        }
        TRUE
      },
      error = function(e) {
        if (exists("before_device") && grDevices::dev.cur() > before_device) grDevices::dev.off()
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
