# Study 1 Codebase Description

This document describes the `Study1/` codebase as it exists in this repository. The folder contains an R-based workflow for preparing, harmonising, merging, describing, imputing, and modelling Study 1 data for the PROFID ICD substudies.

The scientific focus is the association between first inappropriate ICD shock or therapy (FIS) and all-cause mortality in an ICD cohort assembled from four registries: EU-CERT-ICD, HELIOS, ISRAEL-ICD, and PROSE-ICD. The primary analysis is a time-dependent Cox model with multiple imputation; landmark Cox and Fine-Gray competing-risk analyses serve as sensitivity analyses.

## Folder Contents

Top-level files in `Study1/` are organised as numbered R scripts plus a preprocessing subdirectory:

| File | Purpose |
| --- | --- |
| `preprocessing_dataset_scripts/eucert_preprocessing.R` | Processes EU-CERT-ICD registry data into a CDM-ready dataset. |
| `preprocessing_dataset_scripts/helios_processing.R` | Processes HELIOS data from an 11-sheet Excel workbook into a CDM-ready dataset. |
| `preprocessing_dataset_scripts/israel_processing.R` | Processes ISRAEL-ICD data into a CDM-ready dataset. |
| `preprocessing_dataset_scripts/prose_processing.R` | Processes PROSE-ICD data into a CDM-ready dataset. |
| `preprocessing_dataset_scripts/Final_merge_script.R` | Harmonises endpoint columns and IDs, stacks the four registries, and merges them into the ICD master cohort. |
| `preprocessing_dataset_scripts/Variables_overview.R` | Documentation-only `gt` table of endpoint construction by registry. |
| `1.Preliminary analysis.R` | Standardises the merged cohort: inadmissible-value rules, <=40-day baseline rule, factor and `bin_*` creation. |
| `2.Variable_transformation.R` | Log-transforms right-skewed numeric variables and creates SAP age groups. |
| `3.data_cleaning_incidence_power_calc.R` | Defines the final analytic cohort; produces cohort derivation, incidence, exposure, and power tables. |
| `4.Table 1 and table S3.R` | Builds Table 1 baseline characteristics and the supplementary missing-data table. |
| `5.KM1.R` | Descriptive Kaplan-Meier cumulative incidence of time to first inappropriate shock. |
| `6.KM2.R` | Descriptive Kaplan-Meier overall survival by ever/never inappropriate shock. |
| `7.mice_full_cohort.R` | Runs full-cohort MICE imputation (m = 20) with missingness audits. |
| `8.full_cohort_cox_model_and_development.R` | Develops and fits the primary time-dependent Cox model, diagnostics, interactions, and subgroups. |
| `9.Landmark_analysis.R` | Landmark Cox sensitivity analyses at 6, 12, and 24 months. |
| `10.Fine_gray.R` | Landmark Fine-Gray competing-risk sensitivity analyses at 6, 12, and 24 months. |
| `master_run.R` | Canonical sequential runner with stage and step selection. |
| `run_study1.sh` | Slurm submission wrapper that forwards runner options. |
| `study1_paths.R` | Shared path, graphics-device, and plot-saving helpers. |
| `Dataflow.md` | Reconstructed data-flow note with pipeline diagram. |
| `Study1_codebase_description.md` | This document. |

Raw data are kept outside the repository. Inputs resolve below the data root given by `PROFID_DATA_ROOT` (default `/sc-projects/sc-proj-dhzc-profid/PROFID_Substudies/data`); derived intermediates resolve below `PROFID_STUDY1_DERIVED_ROOT` (default `<data root>/derived/Study1`); tables and figures are written to `PROFID_STUDY1_OUTPUT_ROOT` (default `<repo>/Study1/outputs`).

## High-Level Workflow

The pipeline is:

1. Process each contributing registry into a common-data-model-ready dataset:
   - EU-CERT-ICD (`CERT`)
   - HELIOS (`HELS`)
   - ISRAEL-ICD (`ISRL`)
   - PROSE-ICD (`PRSE`)
2. Construct the harmonised endpoint variables per registry: `Status_death`, `Time_death_days`, `t_followup_days`, `Status_FIS`, `Time_FIS_days`.
3. Apply registry-specific inclusion/exclusion rules (adult age; ischemic-only, CRT-D, overlap-centre, and co-enrolment exclusions where configured).
4. Stack the four registries and merge them into the ICD master cohort `ICD.csv` by normalised ID.
5. Standardise the merged cohort (inadmissible values to NA, <=40-day baseline rule, factors, `bin_*` indicators).
6. Transform skewed numerics (`log1p`) and create SAP age groups.
7. Apply final outcome/exposure cleaning rules to define the master analytic cohort.
8. Generate descriptive tables (Table 1, missingness, incidence, power) and Kaplan-Meier figures.
9. Run full-cohort MICE imputation.
10. Fit the primary time-dependent Cox model for all-cause mortality.
11. Run landmark Cox and Fine-Gray competing-risk sensitivity analyses.

The core data products are:

- `derived/Study1/FINAL_ICD_COHORT/icd_merged1.rds` (merged cohort)
- `derived/Study1/master_clean_dataset1.rds` (final analytic cohort)
- `derived/Study1/Imputed_data/mice_full_object1.rds` (20 imputations)

## Master Runner And Execution Modes

`Study1/master_run.R` runs the pipeline scripts in a fixed order. Each script is executed via `sys.source()` in its own environment, into which the runner injects shims: `install.packages` is replaced by an installer that targets the user library (with a special case installing `gt` 0.7.0 from the CRAN archive), and `library` is replaced by a loader that installs missing packages on demand, expands `tidyverse` into its core packages, and silently skips the optional `survminer`/`ggsurvplot` packages.

The runner supports:

```bash
Rscript Study1/master_run.R                    # full pipeline
Rscript Study1/master_run.R --dry-run          # print selected scripts only
Rscript Study1/master_run.R --stage analysis   # one stage only
Rscript Study1/master_run.R --from 3_clean --to 8_primary_cox
Rscript Study1/master_run.R --only 7_mice,8_primary_cox
Rscript Study1/master_run.R --skip-optional    # skip QC/descriptive steps
Rscript Study1/master_run.R --continue-on-error
```

Stages are `preprocessing`, `core` (scripts 1-3), `descriptive` (scripts 4-6), `imputation` (script 7), `modeling` (script 8), `sensitivity` (scripts 9-10), and the umbrella stages `analysis` (everything after the merge) and `all`. Step IDs in default order:

```text
preprocess_eucert, preprocess_helios, preprocess_israel, preprocess_prose,
variables_overview (optional), merge,
1_preliminary, 2_transform, 3_clean,
4_table1 (optional), 5_km1 (optional), 6_km2 (optional),
7_mice, 8_primary_cox, 9_landmark, 10_fine_gray
```

The runner stops at the first failing script unless `--continue-on-error` is given, and reports per-step timings and a failure summary at the end. Run `Rscript Study1/master_run.R --help` for the complete option list.

The Slurm wrapper:

```bash
./Study1/run_study1.sh                 # submits via sbatch, forwards all options
./Study1/run_study1.sh --dry-run
```

It self-submits with `sbatch` when run outside a Slurm allocation, loads `R/4.5.0`, writes `Study1/outputs/log_run_<timestamp>.log`, and sends begin/end/fail mail notifications.

## Shared Path And Graphics Helpers

All scripts source `Study1/study1_paths.R` through a fallback chain (`Study1/study1_paths.R` -> `study1_paths.R` -> `../study1_paths.R`), so scripts work from the repository root, `Study1/`, or `Study1/preprocessing_dataset_scripts/`.

The central helpers are:

- `profid_data_root()`, `profid_data_path(...)`, `profid_dataset_path(...)`, `profid_transfer_path(...)` for raw inputs under the data root.
- `study1_derived_path(...)` for derived intermediates (registry RDS files, the merged cohort, the master clean dataset, imputation outputs).
- `study1_output_path(...)` for tables and figures under `Study1/outputs/`.
- `study1_save_plot()` and `study1_save_grid()` for PNG/PDF export with headless device fallbacks (ragg -> cairo -> ghostscript bitmap; cairo_pdf -> pdf), plus headless cairo configuration on Linux.

Notable detail:

- `study1_output_path()` only honours the last path component when it carries a file extension; directory-like components are silently dropped. Arguments such as `study1_output_path("Supplementary_data", "Primary")` therefore resolve to the output root itself, and all table/figure outputs of scripts 3-10 land flat in `Study1/outputs/` rather than in the subfolder structure the arguments suggest.

## R Package Dependencies

Across the codebase, the scripts use:

- `tidyverse` (expanded to core packages by the runner shim)
- `data.table`
- `readxl`
- `openxlsx`
- `survival`
- `mice`
- `naniar`
- `VIM`
- `gt` (pinned to 0.7.0 from the CRAN archive by the runner)
- `ggplot2`, `grid`, `gridExtra`, `patchwork`, `scales`
- `cmprsk`
- `broom`
- `haven`, `stringr`

Many scripts still contain unconditional `install.packages()` calls; when run through `master_run.R` these are intercepted by the runner's shim. There is no project-level dependency lockfile such as `renv.lock`.

## Source-Specific Preprocessing Scripts

Each preprocessing script reads its raw registry data, a registry data dictionary, and a common data model CSV, and writes a CDM-ready RDS/CSV pair plus QC outputs under `derived/Study1/<REGISTRY>/`. All times are days from ICD implantation.

### `eucert_preprocessing.R` (`DB = "CERT"`)

Inputs:

- `datasets/local/eu-cert-icd/data/original/registry_data_eu-cert-icd_selection_161019-Data-sheet.csv`
- `datasets/local/eu-cert-icd/data/dictionary/eu-cert-icd-data-dictionary-raw.xlsx` (used only to identify date columns)
- `datasets/cdm/profid-common-data-model.csv` (shared CDM copy)

Main steps:

1. Reads the registry CSV with `fread()`.
2. Restricts to ischemic diagnoses (`pat_diag_type == "ischemic"`).
3. Excludes patients younger than 18.
4. Excludes CRT-D devices (`EXCLUDE_CRT <- TRUE`).
5. Excludes the Karolinska overlap centre (`ctr_name == "Karolinska Institute Stockholm"`).
6. QC-compares date-derived follow-up (`lastfu_date - icd_implant_date`, kept as `fu_days_from_dates`) against `length_fu_mortality`; discrepancies over 7 days are flagged only.
7. Constructs endpoints:
   - `Status_death`: `death` yes/no; deaths with `heart_transplant == "yes"` are reclassified as censored.
   - `Time_death`: `length_fu_mortality`.
   - `Status_FIS`: `inap_shock` yes/no.
   - `Time_FIS`: `length_fu_inap_shock`.
8. FIS/death events after last follow-up are flagged, not corrected.
9. Adds `DB = "CERT"` and `ID_f = "CERT-<ID>"` (hyphenated).
10. Saves `EUCID/eu_cert_icd_cdm_ready.rds` and `.csv`, a QC summary, and basic summary statistics.

Notable detail:

- Despite the header comment, no dictionary-driven renaming happens; raw names are kept and intersected with the CDM at the end.

### `helios_processing.R` (`DB = "HELS"`)

Inputs:

- `datasets/local/helios-rdb/data/original/Final_delivery.2021-05-20._Ali EDxlsx.xlsx` — 11 sheets: `target_pop`, `Baseline Characteristics`, `Past Medical History (ICD10)`, `Past Medical History (OPS)`, `Medication (ATC)`, `Lab Data`, `ECG`, `ICD queries`, `Outcome`, `CMR-Scar and GZ`, `Imaging`
- `datasets/local/helios-rdb/data/dictionary/helios-data-dictionary-raw.csv`

Main steps:

1. Reads all 11 sheets and outer-merges them by `PAT_INDEX` (each sheet asserted unique per patient; for multi-row Imaging the first row is kept).
2. Renames once via the dictionary (`original_name` -> `new_name`).
3. Excludes patients younger than 18; CRT exclusion block present but disabled.
4. Constructs endpoints:
   - `Status_death` from `Status_death_cat` yes/no.
   - `Time_death_days`: `DAYS2DEATH.ICD` for deaths, `DAYS2LastFU.ICD` for censored patients.
   - `t_followup_days = Time_death_days`.
   - `Status_FIS` from `inappropriate_shock`.
   - `Time_FIS_days`: `DAYS2_inappropriate_shock.ICD` for exposed patients.
5. Negative times set to NA; event-after-follow-up flagged only.
6. Adds `DB = "HELS"` and `ID_f = "HELS-<ID>"` (hyphenated).
7. Saves `HELIOS/helios_cdm_ready.rds` and `.csv`, a QC summary, and basic summary statistics.

Notable detail:

- The censored-FIS-time assignment writes to a stray `Time_FIS` column instead of `Time_FIS_days`, so censored FIS times stay NA for HELIOS; the master cleaning rules (E1/E6) later backfill them from `Time_death_days`.

### `israel_processing.R` (`DB = "ISRL"`)

Inputs:

- `datasets/local/israeli-icd/data/original/ICDALL_20170630.csv`
- `datasets/local/israeli-icd/data/dictionary/israeli-icd-data-dictionary-raw-v3.xlsx`

Main steps:

1. Reads the CSV with `fread()` (several NA spellings honoured).
2. Strict dictionary rename: requires the data columns to match the dictionary's `original_name` column exactly, in order.
3. Optional dictionary-driven date parsing.
4. Excludes patients younger than 18; CRT exclusion block present but disabled.
5. For deceased patients, aligns `Alive_last_FU_days` to `Alive_total_days` when death occurred after last follow-up (an actual correction, with assertion).
6. Constructs endpoints:
   - `Status_death`: 1 iff `Status_last == "DIED"`, else 0 (never NA).
   - `Time_death_days = t_followup_days = Alive_last_FU_days` (post-correction).
   - `Status_FIS`: `Inapp_shock_1st` YES/NO.
   - `Time_FIS_days`: `Inapp_shock_days` for exposed, follow-up otherwise.
7. Actively reclassifies FIS occurring after follow-up as unexposed and censors FIS time at follow-up.
8. Adds `DB = "ISRL"` and `ID_f = "ISRL_<ID>"` (underscore, unlike the other registries).
9. Saves `ISRAEL/processed-isrl-common-data-model.rds`, `processed-ISRAEL-common-data-model.csv`, a QC CSV, and basic summaries.

### `prose_processing.R` (`DB = "PRSE"`)

Inputs:

- `datasets/local/prose-icd/data/original/FinaltoPROFID_PROSEonlysent_hopkins_prose_study.csv`
- `datasets/local/prose-icd/data/original/FinaltoPROFID_PROSEonlysent_coenrolled.csv` (co-enrolment join file)
- `datasets/local/prose-icd/data/dictionary/prose-only-data-dictionary-raw-v1.xlsx`

Main steps:

1. Reads the raw CSV and renames via the dictionary.
2. Excludes patients younger than 18.
3. Excludes CRT patients (`EXCLUDE_CRT <- TRUE`): keeps only `ICD_type` `SINGLE - Single` and `DUAL - Dual`.
4. Removes co-enrolled LVSCD patients via the join file.
5. Because PROSE has no calendar follow-up date, defines `t_followup_days` as the maximum of `Death_days`, `days_to_app_shock`, and `t_inappshock` (all-missing converted from `-Inf` to NA).
6. Constructs endpoints:
   - `Status_death`: `Death_status` Yes/No.
   - `Time_death`: `Death_days`.
   - `Status_FIS`: `inappshock` Yes/No; missing shock information with available death follow-up is assumed `No`.
   - `Time_inapp`: `t_inappshock` for exposed, `Death_days` for unexposed.
7. FIS after death is flagged only.
8. Adds `DB = "PRSE"` and `ID_f = "PRSE-<ID>"` (hyphenated; becomes `PRSI_` in the merge script).
9. Saves `PROSE/prose_cdm_ready.rds` and `.csv`, a QC summary, and basic summary statistics.

Notable detail:

- The CDM is read from the `prose-lvscd` dataset folder rather than `prose-icd`.

## Merge Script

### `Final_merge_script.R`

Inputs:

- `Data_Transfer_to_Charite/ICD.csv` (ICD master cohort)
- The four `*_cdm_ready.rds` files

Main steps:

1. Normalises IDs for CERT, HELS, and PRSE (trim, hyphens to underscores); ISRL already uses underscores.
2. Changes the PROSE ID prefix `PRSE_` to `PRSI_` so IDs match the master file (the `DB` value stays `PRSE`).
3. Harmonises endpoint column names to `Status_death`, `Time_death_days`, `t_followup_days`, `Status_FIS`, `Time_FIS_days`:
   - CERT: `fu_days_from_dates` -> `t_followup_days`, `Time_death` -> `Time_death_days`, `Time_FIS` -> `Time_FIS_days`.
   - PROSE: `Time_death` -> `Time_death_days`, `Time_inapp` -> `Time_FIS_days`.
4. Stacks the four registries on the required endpoint columns; checks for duplicate IDs.
5. Left-merges the ICD master cohort onto the stacked endpoints by `ICD$ID == stacked$ID_f`.
6. Keeps only `DB` in `CERT`, `HELS`, `ISRL`, `PRSE`.
7. The analysis cohort is the rows with a matched (non-NA) `Status_death`.
8. Writes QC outputs: duplicates, completeness by DB, before/after counts, ID-match summary, and FIS-after-follow-up rows.
9. Saves `FINAL_ICD_COHORT/icd_merged1.rds` and `icd_merged1.csv`.

### `Variables_overview.R`

Reads no data; builds a static `gt` table documenting, per registry, the raw variables and rules used to construct mortality, FIS, and follow-up endpoints. Output: `Study1/outputs/table_variable_construction_by_dataset.html`.

## Core Cleaning Scripts

### `1.Preliminary analysis.R`

Input:

- `FINAL_ICD_COHORT/icd_merged1.csv`

Main steps:

1. Report-only checks: LVEF inclusion counts, duplicate IDs.
2. Sets inadmissible measurements to NA without dropping rows:
   - `BMI` <12 or >69; `BUN` >900; `Haemoglobin` <2 or >110; `LDL` ==0; `Sodium` <99; `Triglycerides` <20; `TSH` ==0; `HR` <25 or >140; `PR` <=50 or >1000; `QRS` <50; `QTc` <=250 or >790.
3. Applies the <=40-day baseline rule: rows flagged by baseline label text, `Time_zero_Y`/`Time_zero_Ym` <= 40/365.25, or `Time_index_MI_CHD` <= 40 days have `SBP`, `DBP`, `CRP`, `Troponin_T`, `NYHA`, `AV_block`, `AV_block_II_or_III` set to NA.
4. Standardises NYHA to ordered `I < II < III < IV`.
5. Converts 38 binary-like clinical fields to ordered `No < Yes` factors and creates matching `bin_*` 0/1 indicators; creates `bin_sex_male`.
6. Saves `FINAL_ICD_COHORT/standardised_data1.csv` and `standardised_data1.rds`.

### `2.Variable_transformation.R`

Input:

- `FINAL_ICD_COHORT/standardised_data1.rds`

Main steps:

1. Selects numeric candidates, excluding IDs, outcomes, exposure, time variables, `bin_*`, and existing `*_log1p` columns.
2. Computes Bowley skewness per candidate.
3. Creates `<var>_log1p = log1p(var)` where Bowley >= 0.2, values are non-negative, and at least 10 unique non-missing values exist.
4. Drops the transform if it over-corrects to negative Bowley skewness.
5. Creates SAP age groups `age_group` (`<=50`, `51-65`, `66-75`, `>75`) and a descriptive `age_group_desc`.
6. Saves `FINAL_ICD_COHORT/Transformed_data1.rds` (RDS only; exploratory plots print to the Plots pane and are not saved).

### `3.data_cleaning_incidence_power_calc.R`

Input:

- `FINAL_ICD_COHORT/Transformed_data1.rds`

This script defines the final analytic cohort used by everything downstream.

Cleaning rules, applied once in this order:

- `O1`: drop rows with missing or non-positive `Time_death_days`.
- `O2`: missing `Status_death` with valid follow-up -> recoded censored (0).
- `E1`: both `Status_FIS` and `Time_FIS_days` missing -> unexposed, FIS time set to `Time_death_days`.
- `E2`: FIS time present but status missing -> exposed.
- `E4`: exposed with unknown FIS timing -> hard exclusion.
- `E5`: FIS at or after end of follow-up -> reclassified unexposed, FIS time set to `Time_death_days`.
- `E6`: unexposed with missing FIS time -> FIS time set to `Time_death_days`.

After cleaning, no NAs remain in the four endpoint variables (verified by assertion).

Outputs:

- `derived/Study1/master_clean_dataset1.rds`
- `TableS1_CohortDerivation.html`
- Crude all-cause mortality and first-inappropriate-shock incidence per 100 person-years with exact Poisson CIs (`results_crude_death`, `inappropriate_therapy_incidence`)
- `deaths_by_exposure`, `exposure_summary`
- Post-hoc power tables using the Schoenfeld approximation (`power_posthoc_table`, `power_mdhr_summary`, `power_curve_table`)

Notable detail:

- The console footer still references the old unsuffixed name `master_clean_dataset.rds`; the saved file is `master_clean_dataset1.rds`.
- Comments mention a rule E3, but no E3 code block exists.

## Descriptive Scripts

### `4.Table 1 and table S3.R`

Input:

- `master_clean_dataset1.rds`

Main steps:

1. Recodes `Status_FIS` and all `bin_*` variables to strict 0/1; re-standardises NYHA.
2. Excludes variables with >=80% missingness from Table 1.
3. Builds Table 1 by `Status_FIS` (Overall / shock / no shock, plus a Missing column): continuous variables as mean +/- SD, categorical as n (%) of the non-missing group denominator. No p-values by design (severely imbalanced groups; confounding assessment cited instead).
4. Renders NYHA as a 4-level categorical block within the Clinical parameters section.
5. Builds the supplementary missing-data summary (outcome/exposure block plus labelled covariates; >=80% rows highlighted).

Outputs:

- `Table1_baseline.html/.csv/.rds`
- `Supplementary_Missing_Data.html/.csv`

### `5.KM1.R`

Input:

- `master_clean_dataset1.rds`

Main steps:

1. Restricts to positive `Time_FIS_days`; derives `Time_FIS_years = Time_FIS_days / 365.25`.
2. Fits `survfit(Surv(Time_FIS_years, Status_FIS) ~ 1)`.
3. Plots cumulative incidence (1 - KM) of first inappropriate shock over 0-5 years with 95% CI and a risk-table panel; reports cumulative incidence at 1/3/5 years and checks median estimability.

Output:

- `KM_FigA_time_to_FIS_fullcohort.png/.pdf`

### `6.KM2.R`

Input:

- `master_clean_dataset1.rds`

Main steps:

1. Derives `Time_death_years` and `shock_group` (ever vs never inappropriate shock).
2. Fits `survfit(Surv(Time_death_years, Status_death) ~ shock_group)`.
3. Plots overall survival over 0-5 years (no CI bands, no risk table).

Output:

- `KM_FigB_survival_by_shock_fullcohort.png/.pdf`

Both KM figures are explicitly descriptive: they do not model the exposure as time-dependent.

## Multiple Imputation

### `7.mice_full_cohort.R`

Input:

- `master_clean_dataset1.rds`

Main steps:

1. Builds the imputation dataset from ID/DB, outcome, exposure, time-zero, continuous, categorical, and `bin_*` variables; pre-existing `*_log1p` columns are removed so they can be re-derived passively during imputation.
2. Drops variables with >80% missingness and base variables duplicated by a `bin_*` version.
3. Runs missingness diagnostics (lollipop plot, Little's MCAR test, MAR quick screen).
4. Builds the MICE specification: IDs, outcomes, exposures, and time-zero variables are not imputed; outcomes are used as predictors, exposures are not; binary/factor variables use `logreg`/`polyreg`, numerics use `pmm`; `*_log1p` transforms are configured passively as `~I(log1p(base))`.
5. Special handling:
   - `bin_anti_diabetic` (collinear with `bin_diabetes`): filled from `bin_diabetes`, remaining NA set to 0, not imputed.
   - `bin_anti_diabetic_insulin`: forced `logreg` if two levels exist, otherwise constant-filled.
   - `bin_av_block_ii_or_iii` (~75% missing, rare positives): NA filled with 0, not imputed.
6. A guardrail trial imputation removes rows that remain non-imputable.
7. Runs `mice(m = 20, maxit = 10)` with seed 123; asserts no remaining NAs in imputation targets.

Outputs (under `derived/Study1/Imputed_data/`):

- `mice_full_object1.rds` (`mids` object)
- `full_imputed_long1.csv`
- `mice_audit_log_FULL1.csv`
- `Logs/missingness_full1.csv`
- `Figures/missingness_lollipop_top40_FULL.png/.pdf`

Notable detail:

- The console "Saved:" message lists stale train/test filenames that are no longer written; only the full-cohort artifacts above are produced.

## Primary Cox Modelling

### `8.full_cohort_cox_model_and_development.R`

Input:

- `Imputed_data/mice_full_object1.rds` (m = 20)

Primary estimand:

- Outcome: all-cause mortality.
- Exposure: time-dependent first inappropriate shock (`FIS_td`).
- Time scale: days from ICD implantation.
- Cohort handling: `strata(DB)` in the primary model.
- Pooling: Rubin's rules across the 20 imputations.

Main steps:

1. Converts each imputed dataset to start-stop long format with `survival::tmerge`: `death = event(Time_death_days, Status_death == 1)`, `FIS_td = tdc(Time_FIS_days)`; one baseline row per ID; degenerate intervals removed.
2. Forced covariates: `Age`, `bin_sex_male`, `LVEF`, `NYHA` (4-level factor), `bin_diabetes`, `eGFR`, `bin_beta_blockers`, `bin_af_atrial_flutter`.
3. Screens 22 candidate covariates in `FIS_td + X` models; keeps pooled p < 0.05.
4. Correlation pruning: among numeric pairs with |r| > 0.70, keeps the forced variable, else the one with the smaller screening p-value.
5. Backward selection on non-forced covariates (drop highest pooled p while >= 0.05); forced variables never dropped.
6. Diagnostics on imputation 1: `cox.zph` proportional-hazards test and Martingale-residual linearity plots for continuous final covariates.
7. Primary model: `Surv(tstart, tstop, death) ~ FIS_td + <final covariates> + strata(DB)`, pooled across imputations.
8. Interaction tests between `FIS_td` and final-model covariates (NYHA tested as binary `NYHA_bin`).
9. Subgroup HRs for `FIS_td` within: age group (<65 / 65-75 / >75), LVEF (<30 / 30-35 / >35), sex, AF/flutter, diabetes, NYHA I-II vs III-IV; forest plots.

Outputs (all in `Study1/outputs/`):

- `00_crude_FIS_model.html`
- `01_screening_summary.html`, `01_screening_summary_formatted.html`, `01_screening_factor_details1.csv`
- `02_high_correlations.csv/.html`
- `03_full_model.csv`
- `04_final_model1.csv/.html`, `04_final_model1_pretty.html`
- `05_ph_test.txt`, `05_ph_plots.pdf`, `05_linearity_plots.pdf`
- `07_primary_model_strata_DB.csv/.html`
- `08_interaction_tests.csv/.html`
- `09_subgroup_HR_FIS_td.csv`, `09_subgroup_table.png/.pdf`
- `14_forest_plot_subgroups.png/.pdf`, `14_forest_HR_sidetable.png/.pdf`

Notable detail:

- `QRS_log1p` is manually injected into the `mids` object for rows with missing `QRS` before use.
- `09_subgroup_table.png/.pdf` is written twice; the second, re-themed block overwrites the first.

## Landmark Cox Sensitivity Analysis

### `9.Landmark_analysis.R`

Inputs:

- `Imputed_data/mice_full_object1.rds`
- `Study1/outputs/07_primary_model_strata_DB.csv` (for the comparison table)

Main steps:

1. Landmarks at 183, 365, and 730 days (6, 12, 24 months).
2. At each landmark: keeps patients with `Time_death_days > L`; defines `FIS_L = 1` if `Status_FIS == 1` and `Time_FIS_days <= L` (ambiguous exposed-without-time cases dropped); restarts the clock (`t_landmark = Time_death_days - L`).
3. Fits per landmark per imputation:

```r
Surv(t_landmark, event) ~ FIS_L + Age_10 + LVEF_5 + eGFR_10 +
  QRS_log1p + bin_beta_blockers + bin_diabetes + bin_stroke_tia +
  bin_af_atrial_flutter + bin_sex_male + NYHA_grp + strata(DB)
```

   with `Age/10`, `LVEF/5`, `eGFR/10` rescaling, `QRS_log1p = log1p(QRS)` derived in-script, and NYHA dichotomised (`NYHA_grp`, I-II vs III-IV).
4. Pools with `mice::pool()`; counts (N at risk, exposed, deaths) taken from imputation 1.

Outputs:

- Per landmark: `HR_table_<lm>.pdf`, `forest_<lm>.png/.pdf`
- `SUMMARY_Landmark_fullcohort.csv/.html`
- `LANDMARK_risk_table.csv/.html`
- `COMPARISON_primary_vs_landmark.csv/.html`

## Fine-Gray Competing-Risk Sensitivity Analysis

### `10.Fine_gray.R`

Input:

- `Imputed_data/mice_full_object1.rds`

Main steps:

1. Uses `Survival_time` (months, converted with 30.4375 days/month) and `Status` (0 = censored/alive, 1 = appropriate ICD shock = event of interest, 2 = death as competing event).
2. Landmarks at 183, 365, and 731 days.
3. Excludes missing/zero `Survival_time`; treats missing `Status` as censored; reclassifies `Time_FIS_days > time_days` as unexposed (Rule E); applies the same landmark restriction and `FIS_L` derivation as script 9.
4. Fits `cmprsk::crr(..., failcode = 1, cencode = 0)` with the landmark adjustment set, but NYHA binarised and no `strata(DB)` (`crr()` does not support stratification).
5. Pools across imputations with manual Rubin's rules; falls back to imputation 1 if pooling is infeasible.
6. CIF plots with `cuminc()` grouped by `FIS_L` from imputation 1.

Outputs:

- Per landmark: `FULL_sHR_table_<lm>.pdf`, `FULL_forest_<lm>.png/.pdf`, `FULL_CIF_<lm>.png/.pdf`
- `TableS2_FineGray_CohortDerivation.html`

Important distinction:

- The Fine-Gray script uses `Survival_time`/`Status` (appropriate shock vs death), while the Cox/KM analyses use `Time_death_days`/`Status_death` (all-cause mortality). The two endpoint pairs answer different questions and should be documented carefully in any methods write-up.

## Key Derived Variables

### `Status_death` / `Time_death_days`

All-cause mortality indicator and time in days. Constructed per registry (CERT `death` + `length_fu_mortality` with heart-transplant reclassification; HELIOS `Status_death_cat` + `DAYS2DEATH.ICD`/`DAYS2LastFU.ICD`; ISRAEL `Status_last` + `Alive_last_FU_days`; PROSE `Death_status` + `Death_days`), harmonised in the merge script, and finalised by cleaning rules O1/O2.

### `Status_FIS` / `Time_FIS_days`

First inappropriate ICD shock/therapy indicator and time in days. Constructed per registry (CERT `inap_shock` + `length_fu_inap_shock`; HELIOS `inappropriate_shock` + `DAYS2_inappropriate_shock.ICD`; ISRAEL `Inapp_shock_1st` + `Inapp_shock_days`; PROSE `inappshock` + `t_inappshock`), harmonised in the merge script, and finalised by cleaning rules E1/E2/E4/E5/E6. For unexposed patients, `Time_FIS_days` equals `Time_death_days`.

### `FIS_td`

Time-dependent exposure created by `survival::tmerge` in script 8: switches 0 -> 1 at `Time_FIS_days` in start-stop format, so patients are not classified as exposed before their shock.

### `FIS_L`

Landmark-fixed exposure used in scripts 9 and 10: 1 if an inappropriate shock occurred at or before the landmark.

### `Survival_time` / `Status`

Fine-Gray endpoint pair used only in script 10: `Survival_time` in months; `Status` coded 0 = censored, 1 = appropriate shock, 2 = death.

### `bin_*` and `bin_sex_male`

0/1 modelling indicators created in script 1 from the standardised No/Yes clinical fields.

### `*_log1p`

Log transforms of right-skewed numerics created in script 2 (Bowley >= 0.2, non-negative, >=10 unique values, no over-correction); removed before MICE and passively re-derived during imputation.

### `age_group` / `age_group_desc`

SAP age bands (`<=50`, `51-65`, `66-75`, `>75`) created in script 2.

### `NYHA_grp` / `NYHA_bin`

Dichotomised NYHA (I-II vs III-IV) used for interactions, subgroups, and the landmark models; the primary Cox model keeps NYHA as a 4-level factor.

## Primary Analysis Population

The primary survival analysis population includes the four registries:

- EU-CERT-ICD (`CERT`)
- HELIOS (`HELS`)
- ISRAEL-ICD (`ISRL`)
- PROSE-ICD (`PRSE`)

The key inclusion logic is:

- Adult ICD recipients.
- Registry-specific exclusions: ischemic-only, no CRT-D, and no Karolinska overlap centre in EU-CERT; no CRT devices and no LVSCD co-enrolment in PROSE.
- Successful ID match against the ICD master cohort.
- Positive, non-missing mortality follow-up (rule O1); classifiable exposure timing (rule E4).
- `DB` enters the primary model only as a stratification factor.

## Data Products And Expected Outputs

Registry preprocessing outputs (under `derived/Study1/<REGISTRY>/`):

- `eu_cert_icd_cdm_ready.rds/.csv`
- `helios_cdm_ready.rds/.csv`
- `processed-isrl-common-data-model.rds`, `processed-ISRAEL-common-data-model.csv`
- `prose_cdm_ready.rds/.csv`
- per-registry QC summaries and basic summary workbooks

Merge outputs (`derived/Study1/FINAL_ICD_COHORT/`):

- `icd_merged1.rds`, `icd_merged1.csv`
- `standardised_data1.csv`, `standardised_data1.rds`
- `Transformed_data1.rds`
- QC files under `FINAL_ICD_COHORT/qc/`

Master cohort and imputation outputs:

- `derived/Study1/master_clean_dataset1.rds`
- `derived/Study1/Imputed_data/mice_full_object1.rds`
- `derived/Study1/Imputed_data/full_imputed_long1.csv`
- `derived/Study1/Imputed_data/mice_audit_log_FULL1.csv`

Descriptive outputs (`Study1/outputs/`):

- `TableS1_CohortDerivation.html`
- `results_crude_death`, `inappropriate_therapy_incidence`, `deaths_by_exposure`, `exposure_summary`, `power_posthoc_table`, `power_mdhr_summary`, `power_curve_table` (csv + html)
- `Table1_baseline.html/.csv/.rds`
- `Supplementary_Missing_Data.html/.csv`
- `KM_FigA_time_to_FIS_fullcohort.png/.pdf`
- `KM_FigB_survival_by_shock_fullcohort.png/.pdf`
- `table_variable_construction_by_dataset.html`

Primary model outputs (`Study1/outputs/`):

- `00_crude_FIS_model.html`, `01_screening_summary*.html`, `01_screening_factor_details1.csv`
- `02_high_correlations.csv/.html`, `03_full_model.csv`, `04_final_model1.*`
- `05_ph_test.txt`, `05_ph_plots.pdf`, `05_linearity_plots.pdf`
- `07_primary_model_strata_DB.csv/.html`, `08_interaction_tests.csv/.html`
- `09_subgroup_HR_FIS_td.csv`, `09_subgroup_table.png/.pdf`
- `14_forest_plot_subgroups.png/.pdf`, `14_forest_HR_sidetable.png/.pdf`

Sensitivity outputs (`Study1/outputs/`):

- `HR_table_<lm>.pdf`, `forest_<lm>.png/.pdf`, `SUMMARY_Landmark_fullcohort.*`, `LANDMARK_risk_table.*`, `COMPARISON_primary_vs_landmark.*`
- `FULL_sHR_table_<lm>.pdf`, `FULL_forest_<lm>.png/.pdf`, `FULL_CIF_<lm>.png/.pdf`, `TableS2_FineGray_CohortDerivation.html`

## Quality Control Embedded In Scripts

The codebase includes several useful QC checks:

- Follow-up consistency checks in preprocessing (date-derived vs registry-reported follow-up; event-after-follow-up flags in every registry).
- Duplicate-ID checks in preprocessing, merge, and script 1.
- Completeness-by-registry and ID-match summaries in the merge script.
- LVEF inclusion counts and endpoint crosstabs in script 1.
- Missingness summaries, lollipop plot, Little's MCAR test, and a MAR screen in script 7.
- MICE guardrail trial imputation and a post-run assertion that no NAs remain.
- Proportional-hazards (`cox.zph`) and Martingale-residual linearity diagnostics in script 8.
- Exposure feasibility checks (events during exposure) in script 8.
- Risk tables and event counts per landmark in scripts 9 and 10.
- A merged-level FIS-after-follow-up check in the merge script and rule E5 in script 3.

## Reproducibility And Maintenance Issues

The following issues are visible from static code inspection:

1. Raw input data are absent from this repository checkout.
   - Intentional for privacy; the external data root must be available via `PROFID_DATA_ROOT` (or the derived/output roots via their env overrides).

2. `study1_output_path()` silently flattens output subdirectories.
   - Directory-like arguments are discarded, so all script 3-10 outputs land flat in `Study1/outputs/`.
   - Filenames are distinct enough to avoid collisions, but the intended folder structure does not exist on disk.

3. HELIOS censored FIS times are lost at preprocessing.
   - `helios_processing.R` assigns them to a stray `Time_FIS` column instead of `Time_FIS_days`.
   - Downstream rules E1/E6 backfill from `Time_death_days`, so the master cohort is consistent, but registry-level FIS censoring detail is lost.

4. Landmark cutoffs differ slightly between sensitivity scripts.
   - Script 9 uses 183/365/730 days; script 10 uses 183/365/731 days (30.4375-day months).

5. `Survival_time`/`Status` versus `Time_death_days`/`Status_death`.
   - The Fine-Gray script uses a different endpoint pair (appropriate shock as event of interest) than the rest of the pipeline (all-cause mortality); this must be kept distinct in the methods write-up.

6. Stale names and comments.
   - Script 3's console footer references `master_clean_dataset.rds`; script 4's header references "table S3"; script 7's "Saved:" message lists train/test objects that are no longer written; script 3 comments mention a rule E3 with no code.

7. Inline package installation.
   - Many scripts call `install.packages()` unconditionally; harmless through the runner shim, but undesirable when scripts are run standalone. There is no `renv.lock` or equivalent.

8. Duplicated helper code.
   - Binary conversion, NYHA handling, pooling, and table-writing helpers are duplicated across scripts 3-10.

9. The execution harness is sequential rather than dependency-aware.
   - `master_run.R` encodes the order; there is no `targets` pipeline and no run metadata (package versions, input hashes) is recorded.

10. Some diagnostics print interactively rather than being saved.
    - Script 2's before/after transformation plots and several QC tables only appear in the console/Plots pane; in batch runs they are lost unless the log captures them.

## Suggested Execution Order

The canonical execution order is defined in `Study1/master_run.R`:

1. `preprocessing_dataset_scripts/eucert_preprocessing.R`
2. `preprocessing_dataset_scripts/helios_processing.R`
3. `preprocessing_dataset_scripts/israel_processing.R`
4. `preprocessing_dataset_scripts/prose_processing.R`
5. `preprocessing_dataset_scripts/Variables_overview.R` (optional)
6. `preprocessing_dataset_scripts/Final_merge_script.R`
7. `1.Preliminary analysis.R`
8. `2.Variable_transformation.R`
9. `3.data_cleaning_incidence_power_calc.R`
10. `4.Table 1 and table S3.R`
11. `5.KM1.R`
12. `6.KM2.R`
13. `7.mice_full_cohort.R`
14. `8.full_cohort_cox_model_and_development.R`
15. `9.Landmark_analysis.R`
16. `10.Fine_gray.R`

Run the canonical sequence:

```bash
Rscript Study1/master_run.R
```

or through Slurm:

```bash
./Study1/run_study1.sh
```

## Suggested Refactoring Priorities

The codebase would become more reproducible and easier to audit with these changes:

1. Fix `study1_output_path()` so subdirectory arguments are honoured, and move outputs into their intended folder structure.
2. Fix the HELIOS `Time_FIS`/`Time_FIS_days` assignment and re-derive the affected intermediates.
3. Align landmark day cutoffs between scripts 9 and 10.
4. Replace inline `install.packages()` calls with a reproducible environment (`renv.lock`).
5. Split duplicated helper functions (binary conversion, NYHA handling, pooling, table writing) into a shared R file.
6. Record run metadata: package versions, input file hashes, output timestamps.
7. Remove stale train/test and `master_clean_dataset.rds` references, and reconcile table numbering (S2/S3) between scripts and outputs.
8. Save script 2's transformation diagnostic plots to disk instead of the Plots pane.
