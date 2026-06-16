library(data.table)

repo_root <- "/Users/thomaskaas/PROFID_Substudies"
data_file <- "/Users/PROFID_RAW_DATA/derived/Study3/study3_final_merged.rds"

source(file.path(repo_root, "Study3", "study3_paths.R"))

# 1) Rohdatensatz laden -------------------------------------------------------
dt0 <- as.data.table(readRDS(data_file))

cat("\n===== Schritt 1: Rohdatensatz =====\n")
cat("n =", nrow(dt0), "\n")
print(dt0[, .N, by = dataset][order(dataset)])

# 2) Nur die 4 Analyse-Register behalten -------------------------------------
analysis_datasets <- c("EUCERT", "HELIOS", "ISRAEL", "PROSE")
dt1 <- copy(dt0)[dataset %in% analysis_datasets]

cat("\n===== Schritt 2: Nur Analyse-Register =====\n")
cat("n =", nrow(dt1), "\n")
print(dt1[, .N, by = dataset][order(dataset)])

# 3) device_group wie in Skript 07 ableiten ----------------------------------
dt1[, device_group := NA_character_]

dt1[grepl("\\b(single|vvi|icd_1)\\b", tolower(icd_type)),
    device_group := "Single"]

dt1[grepl("\\b(dual|ddd|icd_2)\\b", tolower(icd_type)),
    device_group := "Dual"]

cat("\n===== Schritt 3: device_group abgeleitet =====\n")
print(dt1[, .(
  rows = .N,
  missing_device_group = sum(is.na(device_group))
), by = dataset][order(dataset)])

dt2 <- dt1[!is.na(device_group)]

cat("n nach device_group-Filter =", nrow(dt2), "\n")

# 4) Follow-up-Feld wie in Skript 07 bauen -----------------------------------
dt2[, t_followup_days_final := suppressWarnings(as.numeric(t_followup_days))]

if ("t_followup_days_israel" %in% names(dt2)) {
  dt2[
    dataset == "ISRAEL" & !is.na(t_followup_days_israel),
    t_followup_days_final := suppressWarnings(as.numeric(t_followup_days_israel))
  ]
}

# 5) Event-/Survival-Zeit erzeugen --------------------------------------------
# Diese Funktion kommt aus study3_paths.R
study3_add_inapp_shock_event(dt2)

# 6) Gültige Survival-Zeit definieren -----------------------------------------
dt2[, valid_survival_input :=
      !is.na(t_inapp_shock_or_censor_days) &
      is.finite(t_inapp_shock_or_censor_days) &
      !is.na(t_followup_days_final) &
      is.finite(t_followup_days_final) &
      t_followup_days_final > 0]

excluded <- copy(dt2[valid_survival_input == FALSE])
kept <- copy(dt2[valid_survival_input == TRUE])

# 7) Ausschlussgrund lesbar machen --------------------------------------------
excluded[, exclusion_reason := fifelse(
  is.na(t_followup_days_final), "missing_followup",
  fifelse(t_followup_days_final <= 0, "nonpositive_followup", "other")
)]

excluded[, followup_problem := fifelse(
  is.na(icd_implant_date) & is.na(last_fu_date),
  "Implant-Datum und Last-FU-Datum fehlen",
  fifelse(
    !is.na(icd_implant_date) & is.na(last_fu_date),
    "Last-FU-Datum fehlt",
    fifelse(
      is.na(icd_implant_date) & !is.na(last_fu_date),
      "Implant-Datum fehlt",
      fifelse(
        !is.na(icd_implant_date) &
          !is.na(last_fu_date) &
          icd_implant_date == last_fu_date,
        "Implant-Datum = Last-FU-Datum",
        "anderes/bitte prüfen"
      )
    )
  )
)]

# 8) Übersicht 3171 -> 3132 -> 3056 ------------------------------------------
step_overview <- data.table(
  step = c(
    "study3_final_merged.rds",
    "nur EUCERT/HELIOS/ISRAEL/PROSE",
    "nach device_group-Ableitung",
    "gültige Zeit-zu-Ereignis-Kohorte"
  ),
  n = c(
    nrow(dt0),
    nrow(dt1),
    nrow(dt2),
    nrow(kept)
  )
)

step_overview[, excluded_from_previous := c(NA_integer_, diff(n) * -1L)]

cat("\n===== Übersicht 3171 -> 3132 -> 3056 =====\n")
print(step_overview)

cat("\n===== Ausschlüsse nach Register und Grund =====\n")
print(excluded[, .N, by = .(dataset, exclusion_reason)][order(dataset, exclusion_reason)])

cat("\n===== Zeilen vs. eindeutige IDs unter den Ausschlüssen =====\n")
print(excluded[, .(
  rows = .N,
  unique_ID = uniqueN(ID)
), by = dataset][order(dataset)])

dup_ids <- excluded[, .N, by = .(dataset, ID)][N > 1]
cat("\n===== Doppelte ausgeschlossene IDs =====\n")
print(dup_ids)

# 9) Tabelle der ausgeschlossenen Patienten ----------------------------------
excluded_table <- excluded[, .(
  dataset,
  ID,
  patient_id,
  exclusion_reason,
  followup_problem,
  icd_implant_date,
  last_fu_date,
  death_date,
  death_flag,
  t_followup_days,
  t_followup_days_israel,
  t_followup_days_final,
  t_inapp_shock_or_censor_days
)][order(dataset, exclusion_reason, ID)]

cat("\n===== Tabelle der ausgeschlossenen Patienten =====\n")
print(excluded_table)

# 10) CSV speichern -----------------------------------------------------------
out_csv <- file.path(repo_root, "Study3", "Outputs", "excluded_patients_3171_3132_3056.csv")
fwrite(excluded_table, out_csv)

cat("\nCSV geschrieben nach:\n", out_csv, "\n", sep = "")