# PROFID Study 3

This README merges the operational run instructions with the Study 3 codebase
description.

`Study3/` contains an R-based workflow for preparing, harmonising, merging,
describing, and modelling Study 3 event data for PROFID ICD substudies. The
apparent scientific focus is comparison of inappropriate ICD shock outcomes
between single-chamber and dual-chamber ICD recipients, with registry-specific
harmonisation and dataset-stratified survival models.

Only mapping workbooks and scripts are present in this checkout. Raw data are
kept outside the repository. In default/HPC mode they are resolved below the
HPC data root. With `Study3/master_run.R --local`, they are resolved below
`/Users/PROFID_RAW_DATA`.

## Folder Contents

Top-level files in `Study3/` are organised as numbered R scripts:

| File | Purpose |
| --- | --- |
| `01_eucert_initial_cleaning.R` | Cleans EU-CERT event data and writes `eucert_events_clean.rds`. |
| `02_Helios_initial_cleaning.R` | Cleans HELIOS event data from multiple Excel sheets and writes `helios_events_clean.rds`. |
| `03_israel_initial_cleaning.R` | Cleans Israeli event data and writes `israel_events_clean.rds`. |
| `04_prose_inital cleaning.R` | Cleans PROSE event data and writes `prose_events_clean.rds`. |
| `05_LCV_initial_script.R` | Cleans LCV event data and writes `lcv_events_clean.rds`. |
| `06_Dataset_merging.R` | Stacks cleaned event datasets, merges them to baseline ICD data, removes duplicates, and writes the final merged dataset. |
| `06_Dataset_merging_updated.R` | Near-duplicate of `06_Dataset_merging.R`, with one additional event variable, `t_followup_days_israel`, in the final event variable list. |
| `07_Descriptive_Table1_Table2.R` | Builds descriptive Table 1 and Table 2 style outputs, missingness summaries, follow-up summaries, incidence rates, and an analysis cohort. |
| `08_Cox models.R` | Builds the primary Cox proportional hazards models for inappropriate shock. |
| `09_Kaplan Maier and Fine Gray.R` | Builds Kaplan-Meier, log-rank, Fine-Gray competing-risk, and cumulative incidence analyses. |
| `10_secondary analysis.R` | Runs secondary Cox analyses, covariate screening, multivariable models, and subgroup interactions. |
| `11_sensitivty analysis (180 days).R` | Runs a 180-day minimum follow-up sensitivity analysis. |
| `12_MICE.R` | Runs SAP-style multiple imputation sensitivity analysis for covariates with less than 30 percent missingness. |
| `master_run.R` | Canonical sequential runner with default/HPC, local, debugging, and step-selection modes. |
| `run_study3.sh` | Slurm submission wrapper that forwards runner options. |
| `study3_paths.R` | Shared path, debugging, endpoint, and graphics helpers. |
| `README.md` | Combined operational execution and codebase reference. |
| `Changelog_HPC_Adaptations.md` | Execution, path, and HPC adaptation history. |
| `CODEBASE_DESCRIPTION.md` | Original detailed workflow and codebase reference. |
| `01_master_map.xlsx` | Broad variable mapping workbook. |
| `02_small_map.xlsx` | Smaller harmonisation map used by the cleaning scripts. |

## High-Level Workflow

The intended pipeline is:

1. Clean each contributing registry or study dataset:
   - EU-CERT
   - HELIOS
   - Israel
   - PROSE
   - LCV
2. Harmonise source-specific column names to common Study 3 names using the
   small mapping workbook.
3. Derive time-to-event and follow-up variables within each source dataset.
4. Apply Study 3 inclusion and exclusion rules, especially ICD type and adult
   age restrictions.
5. Save source-specific cleaned RDS files.
6. Stack the event datasets and merge them into a baseline stacked ICD dataset.
7. Remove known PROSE-LCV duplicate participants.
8. Generate descriptive summaries and analysis cohorts.
9. Run primary and sensitivity survival analyses for inappropriate shock by
   device group.
10. Run secondary adjusted, subgroup, competing-risk, and imputation analyses.

The core data product of the merge step is:

- `study3_final_merged.rds`
- `study3_final_merged.csv`

The main downstream analysis cohort created by the descriptive script is:

- `study3_analysis_final.rds`

## Execution Modes

`Study3/master_run.R` is the canonical entry point. It runs the numbered Study
3 scripts in their established order without changing their statistical logic.
The runner writes a timestamped master log to:

```text
Study3/outputs/master_run_<timestamp>.txt
```

The runner has two path modes:

| Mode | Selection | Raw inputs | Derived intermediates | Outputs |
| --- | --- | --- | --- | --- |
| Default/HPC | no mode flag | `/sc-projects/sc-proj-dhzc-profid/PROFID_Substudies/data` | `<HPC data root>/derived/Study3` | `Study3/outputs` |
| Local | `--local` | `/Users/PROFID_RAW_DATA` | `/Users/PROFID_RAW_DATA/derived/Study3` | `Study3/outputs` |

`--local` is opt-in and checks that the local raw-data root exists. It sets
`PROFID_DATA_ROOT` for raw-file aliases and sets
`PROFID_STUDY3_DERIVED_ROOT` to
`/Users/PROFID_RAW_DATA/derived/Study3`. Without `--local`, the
default/HPC configuration is unchanged.

The local raw-data root is selected only when `--local` is present. Local mode
reads the registry files from their dataset-specific folders and reads
`ICD.csv` from `Data Transfer to Charite/`. Derived Study 3 datasets are
written to `/Users/PROFID_RAW_DATA/derived/Study3`.

The local layout resolves registry inputs under `datasets/local/...` and
`ICD.csv` under `Data Transfer to Charite/`. The HPC layout uses
`Data_Transfer_to_Charite/` for the transfer directory.

## Running The Pipeline

Run the complete pipeline in default/HPC mode from the repository root:

```bash
Rscript Study3/master_run.R
```

Run through the Slurm wrapper:

```bash
./Study3/run_study3.sh
```

Preview the selected scripts without executing them:

```bash
Rscript Study3/master_run.R --dry-run
```

Run the complete pipeline locally:

```bash
Rscript Study3/master_run.R --local
```

Local mode can be combined with debugging and the normal selection options:

```bash
Rscript Study3/master_run.R --local --debugging
Rscript Study3/master_run.R --local --from preprocess_israel --to km_fine_gray --debugging
```

Without `--local`, the runner retains the default/HPC path configuration.

The Slurm wrapper forwards normal options, for example:

```bash
./Study3/run_study3.sh --debugging
```

## Runner Options

Options can be combined in any order:

| Option | Effect |
| --- | --- |
| `--local` | Use `/Users/PROFID_RAW_DATA` for raw inputs. |
| `--debugging` | Print detailed cohort, field, and model-input diagnostics. |
| `--dry-run` | Print selected scripts without executing them. |
| `--stage <name>` | Run one stage: `all`, `preprocessing`, `analysis`, `descriptive`, `modeling`, `sensitivity`, or `imputation`. |
| `--from <step_id>` | Start at a named pipeline step. |
| `--to <step_id>` | Stop at a named pipeline step. |
| `--only <ids>` | Run comma-separated step IDs in the supplied order. |
| `--continue-on-error` | Continue after a failed script and report failures at the end. |
| `--help` | Print complete runner usage and available step IDs. |

Examples:

```bash
Rscript Study3/master_run.R --local --dry-run
Rscript Study3/master_run.R --local --stage preprocessing
Rscript Study3/master_run.R --local --only merge
Rscript Study3/master_run.R --local --from preprocess_israel --to km_fine_gray --debugging
```

The runner also supports `--dry-run`, `--stage`, `--from`, `--to`, `--only`,
and `--continue-on-error`. Run `Rscript Study3/master_run.R --help` for the
complete option and step-ID list.

## Path Configuration

The runner and numbered scripts use `Study3/study3_paths.R`.

- `--local` sets `PROFID_DATA_ROOT=/Users/PROFID_RAW_DATA`.
- `--local` sets `PROFID_STUDY3_DERIVED_ROOT=/Users/PROFID_RAW_DATA/derived/Study3`.
- `--debugging` sets `STUDY3_DEBUGGING=1`.
- `PROFID_STUDY3_OUTPUT_ROOT` can override the output directory.
- `PROFID_STUDY3_RAW_ROOT`, `PROFID_STUDY3_DERIVED_ROOT`, and
  `PROFID_STUDY3_METADATA_ROOT` remain available for explicit path overrides
  outside local mode.

The short filenames used by the numbered scripts are resolved to the original
registry files under `datasets/local/...`.

Both the HPC transfer directory `Data_Transfer_to_Charite/` and the local
directory `Data Transfer to Charite/` are supported for `ICD.csv`.

By default, `study3_metadata_path()` finds the committed top-level
`Study3/02_small_map.xlsx`. `PROFID_STUDY3_METADATA_ROOT` can explicitly
override the metadata location.

## Detailed Debugging Log

Use `--debugging` when investigating missing follow-up, dataset exclusions, or
differences between the merged cohort and the Cox/Fine-Gray model inputs:

```bash
Rscript Study3/master_run.R --debugging
```

Or through Slurm:

```bash
./Study3/run_study3.sh --debugging
```

The option can be combined with the normal selection options:

```bash
Rscript Study3/master_run.R --from preprocess_israel --to km_fine_gray --debugging
```

Debugging output is written to both the terminal and the timestamped master
log:

```text
Study3/outputs/master_run_<timestamp>.txt
```

`--debugging` sets the shared `STUDY3_DEBUGGING=1` environment flag. Scripts
that source `Study3/study3_paths.R` use the following shared helpers:

- `study3_debugging_enabled()` checks whether debug reporting is active.
- `study3_debug_section()` prints consistently labelled debug headings.
- `study3_debug_print()` prints an object only during a debug run.
- `study3_debug_columns()` summarizes requested columns, including class,
  missingness, nonblank values, positive numeric values, and numeric range.

The master runner uses `sink(..., split = TRUE)`, so diagnostic output produced
with `cat()` and `print()` is copied to both destinations. Warnings and package
messages written to standard error may appear only in the Slurm log.

Debug mode reports the complete Israel-to-model data path:

- raw Israel source dimensions, date-field availability, and representative
  date strings
- Israel fields before and after date parsing and follow-up derivation
- final cleaned Israel follow-up, event, and death counts
- survival-field availability by dataset before and after merging
- comparison of `t_followup_days`, `t_followup_days_israel`, and
  `t_followup_days_final`
- Cox eligibility exclusions and final model input by dataset
- Fine-Gray eligibility exclusions, death coding, event coding, included
  datasets, reference dataset, and design-matrix columns

The detailed reports trace the complete Israel-to-model path:

1. `03_israel_initial_cleaning.R`
   - raw input location and dimensions
   - harmonised date-field availability
   - representative raw date strings
   - parsed and derived follow-up fields
   - final cleaned Israel follow-up, event, and death counts
   - separate labels for the script's first duplicated block and the
     export-producing block
2. `06_Dataset_merging_updated.R`
   - survival-field availability for every source dataset before merging
   - detailed Israel field availability immediately before merging
   - match and field-retention summaries immediately after merging
3. `07_Descriptive_Table1_Table2.R`
   - source follow-up fields before final-follow-up assignment
   - comparison of `t_followup_days`, `t_followup_days_israel`, and
     `t_followup_days_final`
   - final survival readiness and events lost because follow-up is unavailable
4. `08_Cox models.R`
   - missing/non-positive follow-up and device-group exclusions by dataset
   - events before and after eligibility filtering
   - final Cox input, follow-up range, and dataset strata
5. `09_Kaplan Maier and Fine Gray.R`
   - missing/non-positive follow-up and event losses before filtering
   - case-sensitive versus case-insensitive death counts
   - datasets entering Fine-Gray
   - Fine-Gray event coding by dataset
   - dataset reference level and dataset-adjusted design-matrix columns

Debug sections are labelled with headings such as:

```text
DEBUG: Israel representative date strings before parsing
DEBUG: Israel final cleaned export summary
DEBUG: Israel immediately before merge
DEBUG: Israel immediately after baseline/event merge
DEBUG: First t_followup_days_final assignment comparison
DEBUG: Primary Cox survival-readiness exclusions
DEBUG: Dataset-adjusted Fine-Gray design
```

All added debug reports use `cat()` or `print()`. Because the master runner
uses `sink(log_con, split = TRUE)`, these reports are written to both the
terminal and the master text log. Warnings and package messages written to
standard error may instead appear only in the Slurm log.

Debug mode is reporting-only. It does not alter values, filtering rules,
cohort definitions, endpoints, models, or statistical methods.

## Path Verification

Verify the local raw-data paths without running the analysis:

```bash
Rscript Study3/master_run.R --local --dry-run
PROFID_DATA_ROOT=/Users/PROFID_RAW_DATA PROFID_STUDY3_DERIVED_ROOT=/Users/PROFID_RAW_DATA/derived/Study3 Rscript -e 'source("Study3/study3_paths.R"); files <- c("eu-cert-icd.csv","Helius.xlsx","israeli.csv","prose.xlsx","LCV.xlsx","PROSE_LCVcommon participant.csv"); for (f in files) cat(f, "->", study3_raw_path(f), "\n"); cat("ICD.csv ->", profid_transfer_path("ICD.csv"), "\n"); cat("Derived datasets ->", study3_derived_root(), "\n")'
```

## R Package Dependencies

Across the codebase, the scripts use:

- `data.table`
- `readxl`
- `lubridate`
- `stringr`
- `tableone`
- `psych`
- `stats`
- `survival`
- `cmprsk`
- `mice`

Most scripts include commented `install.packages()` calls, but there is no
project-level dependency file such as `renv.lock`, `DESCRIPTION`, or a
`requirements` equivalent.

## Mapping Workbooks

The mapping files define source-specific variable names and harmonised Study 3
names.

The cleaning scripts resolve the mapping workbook through the shared path
helper:

```r
path_smallmap <- study3_metadata_path("02_small_map.xlsx")
map_small <- as.data.table(read_excel(path_smallmap, sheet = 1))
```

The small map contains columns such as:

- `meaning`
- `ISRAEL`
- `EU-CERT`
- `LCV`
- `PROSE`
- `Helios`
- `harmonised_name`

Examples of harmonised target variables visible from the workbook and scripts
include:

- `patient_id`
- `icd_implant_date`
- `age_icd`
- `icd_type`
- `inapp_shock_flag`
- `Inapp_ATP`
- `days_to_inapp_shock`
- `app_shock_flag`
- `days_to_app_shock`
- `death_date`
- `death_flag`
- `days_to_death`
- `last_fu_date`
- `t_followup_days`
- `sudden_cardiac_death_flag`

The mapping workbook path is resolved by `study3_metadata_path()`, so the
numbered scripts use the committed `Study3/02_small_map.xlsx` regardless of
whether the master runner is started from the repository root or another
working directory.

## Source-Specific Cleaning Scripts

### `01_eucert_initial_cleaning.R`

Inputs:

- `eu-cert-icd.csv`
- `02_small_map.xlsx`, resolved by `study3_metadata_path()`

Main steps:

1. Reads EU-CERT CSV with `fread()`.
2. Uses the small map to rename EU-CERT columns to harmonised names.
3. Parses key dates:
   - `icd_implant_date`
   - `inapp_shock_date`
   - `app_shock_date`
   - `death_date`
   - `last_fu_date`
4. Date parsing supports:
   - ISO dates, `%Y-%m-%d`
   - day/month/year, `%d/%m/%Y`
   - Excel serial dates based on origin `1899-12-30`
5. Derives:
   - `days_to_death`
   - `days_to_app_shock`
   - `last_fu_days`
   - `event_or_censor_date`
   - `t_followup_days`
6. Creates a competing-event-style status:
   - `0` for alive/censored
   - `1` for cardiac, sudden cardiac, non-sudden cardiac, or unknown death
   - `2` for non-cardiac death
7. Excludes device types outside `VVI` and `DDD`.
8. Applies adult age restriction if `pat_implant_age` exists.
9. Keeps event-related variables and saves `eucert_events_clean.rds`.

Notable detail:

- The age filter checks `pat_implant_age`, while the harmonised selected
  variable is usually `age_icd`. This may be intentional if both exist, but it
  should be verified.

### `02_Helios_initial_cleaning.R`

Inputs:

- `Helius.xlsx`
- `02_small_map.xlsx`, resolved by `study3_metadata_path()`

Main steps:

1. Reads multiple HELIOS Excel sheets:
   - `target_pop`
   - `Baseline Characteristics`
   - `Past Medical History (ICD10)`
   - `Past Medical History (OPS)`
   - `Medication (ATC)`
   - `Lab Data`
   - `Imaging`
   - `CMR-Scar and GZ`
   - `ECG`
   - `ICD queries`
   - `Outcome`
2. Merges all sheets by `PAT_INDEX`.
3. Renames variables via the small map's `Helios` column.
4. Treats implant, death, and follow-up values as years:
   - `implant_year`
   - `death_year`
   - `fu_year`
5. Computes `followup_years` and then `t_followup_days = followup_years * 365`.
6. Restricts device type to exact `ICD_1` and `ICD_2`.
7. Applies adult age restriction using `age_icd`, if present.
8. Keeps event-related variables and saves `helios_events_clean.rds`.

Notable detail:

- HELIOS follow-up is year-based, not full date-based.
- The input file is named `Helius.xlsx` in the script, while the study/dataset
  is referred to as HELIOS elsewhere. The spelling should be verified against
  the real raw file.

### `03_israel_initial_cleaning.R`

Inputs:

- `israeli.csv`
- `02_small_map.xlsx`, resolved by `study3_metadata_path()`

Main steps:

1. Reads the Israeli CSV with `fread()`.
2. Renames variables via the small map's `ISRAEL` column.
3. Creates `death_flag` from presence or absence of `death_date`.
4. Parses implant, death, and last follow-up dates with mixed formats:
   - `%b %d, %Y`
   - `%d-%b-%y`
5. Converts two-digit years less than 2000 into 20xx dates.
6. Derives:
   - `days_to_death`
   - `last_fu_days`
   - `t_followup_days`
7. Creates `status`:
   - `0` for alive/censored
   - `1` for sudden cardiac death
   - `2` for non-sudden or non-cardiac death based on
     `sudden_cardiac_death_flag == NO`
8. Selects event variables.
9. Excludes device type records containing `;`.
10. Keeps device types whose lowercase text matches:
   - `single`
   - `dual`
   - `dx`
   - `icd_1`
   - `icd_2`
11. Excludes device types matching:
   - `crt`
   - `biv`
   - `bi-v`
   - `triple`
   - `plug`
   - `3`
12. Applies adult age restriction using `age_icd`, if present.
13. Saves `israel_events_clean.rds`.

Notable detail:

- The script contains a duplicated cleaning block. The first half repeats
  almost exactly before the final export block appears in the second half. This
  does not necessarily change the final output because `rm(list = ls())` is
  called again before the second copy, but it makes the file harder to
  maintain and increases risk of divergent edits.

### `04_prose_inital cleaning.R`

Inputs:

- `prose.xlsx`
- `02_small_map.xlsx`, resolved by `study3_metadata_path()`

Main steps:

1. Reads sheet `Hopkins_PROSEstudy`.
2. Renames variables via the small map's `PROSE` column.
3. Because PROSE has no calendar follow-up date, derives `last_fu_days` as the
   maximum observed event time across:
   - `days_to_death`
   - `days_to_app_shock`
   - `days_to_inapp_shock`
4. Sets `t_followup_days = last_fu_days`.
5. Restricts ICD type to:
   - `SINGLE - Single`
   - `DUAL - Dual`
6. Applies adult age restriction using `age_icd`, if present.
7. Keeps event variables and saves `prose_events_clean.rds`.

Notable detail:

- `pmax(..., na.rm = TRUE)` can return `-Inf` if all contributing values are
  missing. Unlike the LCV script, this script does not explicitly convert
  infinite values to `NA`.

### `05_LCV_initial_script.R`

Inputs:

- `LCV.xlsx`
- `02_small_map.xlsx`, resolved by `study3_metadata_path()`

Main steps:

1. Reads sheet `Hopkins_LVSCDstudy`.
2. Renames variables via the small map's `LCV` column.
3. Derives `death_type` from:
   - `arrhdeath == 1` -> `sudden cardiac death`
   - `hfdeath == 1` -> `non-sudden cardiac death`
   - otherwise `unknown`
4. Defines `status` as `1` for `death_flag == 1`, otherwise `0`.
5. Converts duration fields to numeric.
6. Converts selected year-based duration variables to days using `365.25`:
   - `time_to_app_therapy`
   - `time_to_inap_therapy`
   - `days_to_death`
7. Defines `t_followup_days` as the maximum of:
   - `days_to_death`
   - `time_to_app_therapy`
   - `time_to_inap_therapy`
8. Converts infinite and negative follow-up times to `NA`.
9. Applies adult age restriction using `age_icd`, if present.
10. Keeps event variables and saves `lcv_events_clean.rds`.

Notable detail:

- Unlike the other source datasets, there is no explicit device-type exclusion
  here. LCV is later included in the merged dataset and then LCV duplicates are
  removed, but Table 1 and primary analysis scripts mostly restrict to
  EU-CERT, HELIOS, PROSE, and Israel.

## Merge Scripts

### `06_Dataset_merging.R`

Inputs:

- `helios_events_clean.rds`
- `eucert_events_clean.rds`
- `israel_events_clean.rds`
- `prose_events_clean.rds`
- `lcv_events_clean.rds`
- `ICD.csv`
- `PROSE_LCVcommon participant.csv`

Main steps:

1. Reads all cleaned event datasets.
2. Reads the baseline stacked ICD dataset from `ICD.csv`.
3. Counts baseline ICD records by ID prefix:
   - `HELS_`
   - `CERT_`
   - `ISRL_`
   - `PRSI_`
   - `PRSL_`
4. Defines the final event variable list.
5. Uses `extract_events()` to add missing event columns as `NA` and enforce a
   common column order.
6. Adds a `dataset` label to each cleaned event dataset.
7. Stacks all event datasets with `rbindlist(..., fill = TRUE)`.
8. Creates `patient_id_full` to match baseline `ICD.csv` IDs:
   - EU-CERT: `CERT_` + `patient_id`
   - HELIOS: `HELS_` + `patient_id`
   - Israel: `ISRL_` + `patient_id`
   - PROSE: `PRSI_` + `patient_id`
   - LCV: `PRSL_` + `patient_id` + `_MRI`
9. Left-merges events onto baseline ICD data by:
   - `dt_icd$ID`
   - `dt_events_merged$patient_id_full`
10. Calculates `age_diff = age_icd - Age` for QC.
11. Keeps only records with event data from the five expected datasets.
12. Reads `PROSE_LCVcommon participant.csv` and removes LCV duplicate
    participants based on `LCV_ID`.
13. Saves:
    - `study3_final_merged.rds`
    - `study3_final_merged.csv`

### `06_Dataset_merging_updated.R`

This file is almost identical to `06_Dataset_merging.R`, but the final event
variable list also includes:

- `t_followup_days_israel`

That variable is not produced by `03_israel_initial_cleaning.R` as currently
written. It may refer to an earlier or external version of the Israel cleaning
pipeline.

## Descriptive Analysis Script

### `07_Descriptive_Table1_Table2.R`

Input:

- `study3_final_merged.rds`

Main outputs:

- `study3_device_analysis_cohort.rds`
- `supplement_missingness_by_device.csv`
- `followup_summary_by_device.csv`
- `incidence_rates_per_100py_by_device_primary_all_datasets.csv`
- `study3_analysis_final.rds`

Main steps:

1. Loads the merged Study 3 dataset.
2. Creates a descriptive cohort from:
   - EU-CERT
   - HELIOS
   - PROSE
   - Israel
3. LCV is not included in this descriptive cohort.
4. Derives `device_group` from `icd_type`:
   - Single: `single`, `vvi`, `icd_1`
   - Dual: `dual`, `ddd`, `icd_2`
5. Restricts to records classified as Single or Dual.
6. Defines Table 1 variables:
   - Continuous: `age_icd`, `BMI`, `LVEF`, `eGFR`
   - Categorical: `Sex`, `NYHA`, `AF_atrial_flutter`, `Diabetes`,
     `Hypertension`, `COPD`, `Stroke_TIA`, `Smoking`,
     `ACE_inhibitor_ARB`, `Beta_blockers`, `Anti_arrhythmic_III`,
     `Anti_platelet`, `Anti_coagulant`
7. Normalises yes/no fields to `Yes`, `No`, or `NA`.
8. For medication variables, converts patient-level `NA` to `No` only inside
   registries where the variable is available and not entirely missing.
9. Creates Table 1 with `tableone::CreateTableOne()`.
10. Builds `t_followup_days_final`:
    - For Israel: `t_followup_days_israel`, if present.
    - For other datasets: `t_followup_days`.
11. Performs normality checks by device group using Shapiro tests where sample
    size is 3 to 5000.
12. Compares continuous variables using Wilcoxon rank-sum if non-normal,
    otherwise t-test.
13. Compares categorical variables using Fisher exact test when any cell count
    is less than 5, otherwise chi-square.
14. Writes follow-up and missingness summaries.
15. Builds Table 2 style endpoint summaries.
16. Normalises endpoint flags:
    - `inapp_shock_flag`
    - `app_shock_flag`
    - `death_flag`
17. Applies the main rule that missing `inapp_shock_flag` is treated as `No`.
18. Creates incidence rates per 100 person-years by device group using Poisson
    confidence intervals.
19. Performs QC checks on raw endpoint values, follow-up by dataset, shock
    dates with missing flags, and follow-up by inappropriate shock status.
20. Summarises death among patients with inappropriate shock and burden of
    recurrent inappropriate shocks.

Important implementation detail:

- The script creates `new_Status3` in `dt_table2` and then checks whether
  `"Status"` exists in `dt_analysis`. Most earlier scripts use lowercase
  `status`, so this may leave `new_Status3` missing unless a baseline column
  named `Status` exists.
- The script expects `t_followup_days_israel` for Israel-specific follow-up,
  but this variable is not visibly created by the Israel cleaning script.

## Survival Modelling

### `08_Cox models.R`

Input:

- `study3_analysis_final.rds`

Primary endpoint:

- First inappropriate shock, encoded as `event_inapp_shock`

Main exposure:

- `device_group`, comparing Single versus Dual ICDs

Main steps:

1. Loads the analysis cohort from `study3_analysis_final.rds`.
2. Re-harmonises ICD type into `device_group`.
3. Standardises `inapp_shock_flag` by lowercasing and trimming.
4. Defines `event_inapp_shock`:
   - `1` if standardised inappropriate shock flag is `yes`
   - `0` if `no`, `unknown`, or `NA`
5. If an inappropriate shock event time exceeds final follow-up, sets
   `days_to_inapp_shock` to `t_followup_days_final`.
6. Removes records with `t_followup_days_final <= 0`.
7. Defines primary analysis cohort as EU-CERT, HELIOS, PROSE, and Israel with
   non-missing device group and follow-up.
8. Fits primary Cox model:

```r
coxph(
  Surv(t_followup_days_final, event_inapp_shock) ~
    device_group + strata(dataset),
  data = dt_primary
)
```

9. Runs sensitivity models:
   - Excluding Israel
   - Excluding EU-CERT
   - Excluding all records with missing raw inappropriate shock flag
10. Runs a supplementary adjusted Cox model:

```r
Surv(t_followup_days_final, event_inapp_shock) ~
  device_group + age_icd + Sex + strata(dataset)
```

11. Performs QC checks:
    - Required variables present
    - No zero or negative follow-up
    - Binary event coding
    - Event counts by dataset and device
    - Event time not greater than follow-up
    - Events per dataset
    - Proportional hazards via `cox.zph`
12. Runs registry-level Cox models.
13. Runs leave-one-dataset-out sensitivity models.

## Kaplan-Meier and Competing-Risk Analysis

### `09_Kaplan Maier and Fine Gray.R`

Input:

- `study3_analysis_final.rds`

Main steps:

1. Fits Kaplan-Meier curves:

```r
survfit(
  Surv(t_followup_days_final, event_inapp_shock) ~ device_group,
  data = dt_final
)
```

2. Runs a log-rank test with `survdiff()`.
3. Saves Figure 1 as a Kaplan-Meier plot of inappropriate shock event-free
   survival by device group with the x-axis display limited to 2,200 days, the
   x-axis labelled in years, and a Study 1-style number-at-risk table below
   the curves.
4. Uses a presentation-specific Figure 1 design: main y-axis scaled from 0.00
   to 1.00, enlarged untitled zoom inset showing 0.90-1.00 event-free
   survival, Single Lead Device shown as a blue solid curve, Double Lead Device
   shown as a red dashed curve, thinner curve lines, short thin censoring tick
   marks, left-side log-rank annotation below the legend, and slightly
   increased spacing below the year tick labels.
5. Builds a Fine-Gray event indicator:
   - `0` censored
   - `1` inappropriate shock
   - `2` death before inappropriate shock as competing event
6. Uses the original `cmprsk::crr()` model with `device_group` as the only
   covariate.
7. Adds a dataset-adjusted `cmprsk::crr()` model with
   `device_group + dataset` as fixed covariates and dataset-specific censoring
   through `cengroup = dataset`.
8. Extracts the `device_groupSingle` subdistribution hazard ratio, 95 percent
   confidence interval, and p value from both Fine-Gray models by coefficient
   name.
9. Writes both Fine-Gray device-effect results to CSV.
10. Builds cumulative incidence curves with `cuminc()`.

Main outputs:

- `figure_1_km_inapp_shock_by_device_2200d_risk_table.png`
- `figure_1_km_inapp_shock_by_device_2200d_risk_table.pdf`
- `figure_1_km_curve_data_2200d.csv`
- `figure_1_km_number_at_risk_long_2200d.csv`
- `figure_1_km_number_at_risk_wide_2200d.csv`
- `finegray_primary_device_results.csv`

The Figure 1 changes are output-only. The KM CSV exports contain the
Kaplan-Meier curve/censor/event data and the number-at-risk table used for the
plot, so the figure can be reloaded and replotted independently. The
Fine-Gray CSV export contains the original device-only `crr()` result and the
additional dataset-adjusted `crr()` result. The original Fine-Gray model,
endpoint definition, input cohort, filtering rule, and cumulative-incidence
analysis are preserved.

The input is produced by `07_Descriptive_Table1_Table2.R`.

## Secondary Analyses

### `10_secondary analysis.R`

Input:

- `study3_analysis_final.rds`

Main steps:

1. Reports missingness and coding for baseline covariates and outcomes.
2. Sets device group reference level as `Dual`.
3. Relevels `Sex`, where possible, with `Female` as the reference.
4. Creates subgroups:
   - `age65`: age at ICD implantation at least 65 years
   - `lvef30`: LVEF below 30 percent
   - `nyha_bin`: NYHA `I-II` versus `III-IV`
5. Converts AF, diabetes, and stroke/TIA into `No`/`Yes` factors where
   available.
6. Runs univariable Cox screening, stratified by dataset, for:
   - `device_group`
   - `age_icd`
   - `Sex`
   - `LVEF`
   - `Diabetes`
   - `BMI`
   - `eGFR`
   - `AF_atrial_flutter`
   - `nyha_bin`
7. Runs complete-case multivariable Cox model:

```r
Surv(t_followup_days_final, event_inapp_shock) ~
  device_group + age_icd + Sex + LVEF + Diabetes + strata(dataset)
```

8. Runs proportional hazards checks.
9. Reports Harrell's C.
10. Tests device group interactions with:
    - `age65`
    - `lvef30`
    - `AF_atrial_flutter`
11. Performs stroke/TIA event-rate QC for separation.

The input is produced by `07_Descriptive_Table1_Table2.R`.

## 180-Day Sensitivity Analysis

### `11_sensitivty analysis (180 days).R`

Input:

- `study3_analysis_final.rds`

Main outputs:

- `incidence_rates_per_100py_by_device_sens_min180d.csv`
- `figure_km_inapp_shock_by_device_sens_min180d.png`
- `figure_cif_inapp_shock_by_device_sens_min180d.png`
- `study3_analysis_sensitivity_min180d.rds`

Main steps:

1. Applies SAP minimum follow-up threshold:

```r
min_fu_days <- 180
dt_sens_6mo <- dt_final[
  !is.na(t_inapp_shock_or_censor_days) &
    t_inapp_shock_or_censor_days >= min_fu_days
]
```

2. Reports excluded counts under both the old follow-up-based rule and the
   corrected endpoint-time rule, including early inappropriate shocks that
   would otherwise remain in the cohort.
3. Reports sensitivity cohort size and event counts.
4. Calculates incidence rates per 100 person-years for:
   - inappropriate shock
   - appropriate shock
   - death
5. Fits dataset-stratified Cox model:

```r
Surv(t_followup_days_final, event_inapp_shock) ~
  device_group + strata(dataset)
```

6. Runs proportional hazards checks.
7. Fits Kaplan-Meier and log-rank analyses.
8. Writes Kaplan-Meier plot PNG.
9. Builds Fine-Gray competing-risk event status:
   - `0` censored
   - `1` inappropriate shock
   - `2` death before inappropriate shock
10. Fits the original Fine-Gray model with `cmprsk::crr()`.
11. Adds a dataset-adjusted Fine-Gray model with
    `device_group + dataset` as fixed covariates and dataset-specific
    censoring through `cengroup = dataset`.
12. Writes both Fine-Gray sensitivity device-effect results to CSV.
13. Writes cumulative incidence plot PNG.
14. Saves the sensitivity cohort.

The input is produced by `07_Descriptive_Table1_Table2.R`.

## Multiple Imputation Sensitivity Analysis

### `12_MICE.R`

Input:

- `study3_analysis_final.rds`

Main steps:

1. Loads the analysis dataset.
2. Sets `device_group` as a factor with `Dual` as reference.
3. Sets `dataset` as a factor for stratification.
4. Converts `event_inapp_shock` to integer.
5. Relevels sex to use `Female` as reference if both `Female` and `Male`
   exist.
6. Sets `Diabetes` as `No`/`Yes`.
7. Converts follow-up to numeric.
8. Defines candidate imputation/model variables:
   - `device_group`
   - `age_icd`
   - `Sex`
   - `LVEF`
   - `Diabetes`
   - `dataset`
   - `t_followup_days_final`
   - `event_inapp_shock`
9. Computes missingness.
10. Selects variables with more than 0 and less than 30 percent missingness as
    eligible for imputation.
11. Explicitly excludes `Diabetes` from imputation.
12. Uses predictive mean matching for `LVEF`, if eligible.
13. Does not impute:
    - `t_followup_days_final`
    - `event_inapp_shock`
    - `device_group`
    - `dataset`
    - `age_icd`
    - `Diabetes`
    - `Sex`
14. Runs `mice()` with:
    - `m = 20`
    - `maxit = 20`
    - seed `20260113`
15. Fits Cox model across imputations:

```r
coxph(Surv(t_followup_days_final, event_inapp_shock) ~
  device_group + age_icd + Sex + LVEF + strata(dataset))
```

16. Pools estimates with `pool()` and reports exponentiated estimates.

Important reproducibility issue:

- Although the header says covariates with less than 30 percent missingness are
  imputed, the method assignments only actively impute `LVEF` with predictive
  mean matching in the visible code.

## Key Derived Variables

### `device_group`

The principal exposure variable. Values are:

- `Single`
- `Dual`

Derived from `icd_type` using source-specific or analysis-script-specific
rules.

### `event_inapp_shock`

The main event indicator for survival analysis:

- `1` if `inapp_shock_flag` standardises to `yes`
- `0` if `inapp_shock_flag` is `no`, `unknown`, or missing

This "missing as no event" rule is applied in Table 2 and Cox modelling.

### `t_followup_days`

Source-specific follow-up time, usually defined as time from ICD implant to
death or censoring, depending on available source fields.

### `t_followup_days_final`

Analysis follow-up variable used in descriptive and survival analyses. In
`07_Descriptive_Table1_Table2.R`, it is set to:

- `t_followup_days_israel` for Israel, if that variable exists
- `t_followup_days` for non-Israel datasets

Since `t_followup_days_israel` is not visibly created in the current Israel
script, Israel follow-up may remain missing depending on which merge script and
upstream data version are used.

### `status`

Used differently across sources but broadly represents vital/event status:

- `0`: alive or censored
- `1`: cardiac death, sudden cardiac death, or death event depending on source
- `2`: non-cardiac or non-sudden cardiac death in sources where this
  distinction exists

The interpretation should be checked carefully before pooling.

### `fg_event`

Fine-Gray competing-risk event:

- `0`: censored
- `1`: inappropriate shock
- `2`: death before inappropriate shock

## Primary Analysis Population

The primary survival analysis population appears to include:

- EU-CERT
- HELIOS
- PROSE
- Israel

LCV is cleaned and included in the merge step but is not part of the primary
descriptive and Cox analysis cohorts in `07_Descriptive_Table1_Table2.R` and
`08_Cox models.R`.

The key inclusion logic is:

- Adult ICD recipients, where age is available
- Single-chamber or dual-chamber ICD recipients
- Non-missing `device_group`
- Positive non-missing final follow-up for survival models

## Data Products and Expected Outputs

Source-cleaning outputs:

- `eucert_events_clean.rds`
- `helios_events_clean.rds`
- `israel_events_clean.rds`
- `prose_events_clean.rds`
- `lcv_events_clean.rds`

Merge outputs:

- `study3_final_merged.rds`
- `study3_final_merged.csv`

Descriptive outputs:

- `study3_device_analysis_cohort.rds`
- `supplement_missingness_by_device.csv`
- `followup_summary_by_device.csv`
- `incidence_rates_per_100py_by_device_primary_all_datasets.csv`
- `study3_analysis_final.rds`

Sensitivity outputs:

- `incidence_rates_per_100py_by_device_sens_min180d.csv`
- `finegray_sens_min180d_device_results.csv`
- `figure_km_inapp_shock_by_device_sens_min180d.png`
- `figure_cif_inapp_shock_by_device_sens_min180d.png`
- `study3_analysis_sensitivity_min180d.rds`

Kaplan-Meier / Fine-Gray outputs:

- `figure_1_km_inapp_shock_by_device_2200d_risk_table.png`
- `figure_1_km_inapp_shock_by_device_2200d_risk_table.pdf`
- `figure_1_km_curve_data_2200d.csv`
- `figure_1_km_number_at_risk_long_2200d.csv`
- `figure_1_km_number_at_risk_wide_2200d.csv`
- `finegray_primary_device_results.csv`

## Quality Control Embedded In Scripts

The codebase includes several useful QC checks:

- Dataset row counts after loading and merging
- Baseline ICD ID-prefix counts
- Event dataset merge success
- Patients without event data
- `age_icd - Age` difference after merge
- Follow-up missingness by dataset
- Median follow-up by dataset and device group
- Event counts by dataset and device group
- Raw endpoint coding by dataset
- Shock date present while shock flag is missing
- Death and inappropriate shock time ordering
- Inappropriate shock event time greater than final follow-up
- Zero or negative follow-up before Cox modelling
- Binary event coding assertions
- Proportional hazards checks
- Dataset-level and leave-one-dataset-out Cox sensitivity analyses

## Reproducibility And Maintenance Issues

The following issues are visible from static code inspection:

1. Raw input data are absent from this repository checkout.
   - This may be intentional for privacy, but it means the pipeline cannot be
     rerun from scratch as committed.
   - The external data roots must be available in default/HPC mode or through
     the opt-in `--local` mode.
2. `03_israel_initial_cleaning.R` contains duplicated code.
   - The duplicated block starts over with `rm(list = ls())`.
   - Final output likely comes from the second copy, but maintenance risk is
     high.
3. Israel-specific follow-up variable mismatch.
   - Downstream code checks `t_followup_days_israel`.
   - The visible Israel cleaning script creates `t_followup_days`, not
     `t_followup_days_israel`.
4. `06_Dataset_merging.R` and `06_Dataset_merging_updated.R` are
   near-duplicates.
   - Only the updated file includes `t_followup_days_israel` in `vars_events`.
   - This increases risk of running the wrong version.
5. `Status` versus `status` naming may be inconsistent.
   - Cleaning scripts create lowercase `status`.
   - The descriptive script checks for uppercase `Status` when creating
     `new_Status3`.
6. PROSE follow-up may become infinite if all event times are missing.
   - `pmax(..., na.rm = TRUE)` returns `-Inf` when all values are missing.
   - The LCV script handles this explicitly; the PROSE script does not.
7. Missing inappropriate shock flags are treated as no event.
   - This is implemented deliberately in descriptive and Cox scripts.
   - It is analytically important and should be justified in the SAP or
     manuscript.
8. The project-level execution harness is sequential rather than
   dependency-aware.
   - `Study3/master_run.R` runs the scripts in a fixed documented order and
     `Study3/study3_paths.R` centralises path handling.
   - There is no `targets` pipeline or `renv.lock`.
9. Package availability is not pinned.
   - The code includes commented install commands but no reproducible R
     environment definition.
10. Several scripts print results interactively rather than writing all
    outputs.
    - Main model summaries, QC tables, and secondary results are often only
      printed to console.

## Suggested Execution Order

The canonical execution order is defined in `Study3/master_run.R`:

1. `01_eucert_initial_cleaning.R`
2. `02_Helios_initial_cleaning.R`
3. `03_israel_initial_cleaning.R`
4. `04_prose_inital cleaning.R`
5. `05_LCV_initial_script.R`
6. `06_Dataset_merging_updated.R`
7. `07_Descriptive_Table1_Table2.R`
8. `08_Cox models.R`
9. `09_Kaplan Maier and Fine Gray.R`
10. `10_secondary analysis.R`
11. `11_sensitivty analysis (180 days).R`
12. `12_MICE.R`

Run the canonical sequence in default/HPC mode:

```bash
Rscript Study3/master_run.R
```

Run the same sequence locally:

```bash
Rscript Study3/master_run.R --local
```

## Suggested Refactoring Priorities

The codebase would become more reproducible and easier to audit with these
changes:

1. Replace duplicate merge scripts with one canonical merge script.
2. Remove the duplicated block in the Israel cleaning script.
3. Standardise `status` and `Status`.
4. Write model and QC outputs to CSV or RDS files, not only console output.
5. Add `renv` or another R dependency lockfile.
6. Add explicit assertions after each major step:
   - expected columns exist
   - no unresolved device groups
   - no invalid follow-up
   - expected datasets represented
   - expected ID-prefix merge success
7. Consider converting the sequential scripts into a `targets` pipeline so
   dependencies and outputs are explicit.

## Summary

`Study3/` contains a complete scripted analysis concept for harmonising
multi-registry ICD event data and analysing inappropriate shocks by single-
versus dual-chamber ICD device group. The main design is clear:
source-specific cleaning, common event schema, baseline merge, descriptive
tables, incidence rates, Cox models, competing-risk analysis, 180-day
sensitivity analysis, and MICE sensitivity analysis.

The largest practical risks are not the statistical modelling code itself, but
reproducibility and naming consistency: unavailable external raw inputs,
duplicated scripts, inconsistent `status`/`Status`, and Israel follow-up
variable handling. The master runner and shared path helpers reduce path and
execution-order ambiguity in both default/HPC and local modes.
