# Study 1 Codebase Description

This document describes the `Study1/` codebase in the `PROFID_Substudies` workspace. The codebase is an R-based analysis pipeline for an ICD cohort assembled from four registries: EU-CERT-ICD, HELIOS, ISRAEL-ICD, and PROSE-ICD. The clinical focus is the association between first inappropriate ICD shock or therapy (`FIS`) and all-cause mortality.

The scripts are not packaged as an R project. They are ordered as standalone scripts with hard-coded local/network paths, mainly on `T:/`, `S:/`, and `//Charite.de/...`. The intended workflow is therefore sequential execution in an environment where those data drives and source files are mounted.

## High-Level Purpose

The Study 1 pipeline:

1. Preprocesses each source registry into a PROFID common data model-like structure.
2. Merges the source registries into one ICD cohort.
3. Standardises variables for descriptive and modelling use.
4. Applies transformations to skewed numeric variables and creates SAP-defined age groups.
5. Applies final cohort cleaning rules for mortality follow-up and first inappropriate shock timing.
6. Produces cohort derivation, incidence, power, baseline characteristics, and missingness tables.
7. Generates Kaplan-Meier descriptive figures.
8. Performs multiple imputation by chained equations.
9. Fits the primary time-dependent Cox model for all-cause mortality.
10. Runs landmark Cox sensitivity analyses.
11. Runs Fine-Gray landmark competing-risk sensitivity analyses.

## Directory Contents

`Study1/` contains ten numbered analysis scripts and a preprocessing subdirectory:

| File | Role |
|---|---|
| `1.Preliminary analysis.R` | Loads merged ICD cohort, validates and standardises variables, applies baseline rules, saves standardised data. |
| `2.Variable_transformation.R` | Detects right-skewed numeric variables, creates `*_log1p` transforms, creates SAP age groups. |
| `3.data_cleaning_incidence_power_calc.R` | Applies final analytic cohort rules, saves master clean dataset, creates cohort derivation, incidence, exposure, and power tables. |
| `4.Table 1 and table S3.R` | Builds Table 1 baseline characteristics and supplementary missing data table. |
| `5.KM1.R` | Creates descriptive Kaplan-Meier cumulative incidence curve for time to first inappropriate shock. |
| `6.KM2.R` | Creates descriptive Kaplan-Meier survival curves by ever/never inappropriate shock. |
| `7.mice_full_cohort.R` | Builds and saves full-cohort MICE imputations and missingness audit outputs. |
| `8.full_cohort_cox_model_and_development.R` | Develops and fits the primary time-dependent Cox model, diagnostics, interactions, and subgroup outputs. |
| `9.Landmark_analysis.R` | Runs landmark Cox sensitivity analyses at 6, 12, and 24 months. |
| `10.Fine_gray.R` | Runs landmark Fine-Gray competing-risk sensitivity analyses at 6, 12, and 24 months. |
| `preprocessing_dataset_scripts/` | Source-registry preprocessing, registry merge, and variable construction overview. |

## Data Lineage

The intended data flow is:

```text
Raw registry files
  -> preprocessing_dataset_scripts/*_processing.R
  -> processed registry RDS/CSV files
  -> preprocessing_dataset_scripts/Final_merge_script.R
  -> T:/FINAL ICD COHORT/icd_merged1.csv/.rds
  -> 1.Preliminary analysis.R
  -> T:/FINAL ICD COHORT/standardised_data1.csv/.rds
  -> 2.Variable_transformation.R
  -> T:/FINAL ICD COHORT/Transformed_data1.rds
  -> 3.data_cleaning_incidence_power_calc.R
  -> T:/Study_1/master_clean_dataset1.rds
  -> descriptive tables, KM figures, MICE, Cox, landmark, and Fine-Gray analyses
```

The downstream analysis scripts rely on `T:/Study_1/master_clean_dataset1.rds` and, for imputed modelling, `T:/Study_1/Imputed_data/mice_full_object1.rds`.

## Preprocessing Layer

### `eucert_preprocessing.R`

This script processes EU-CERT-ICD registry data into a CDM-ready dataset.

Main steps:

- Loads a raw patient-level CSV.
- Loads a data dictionary and a common data model CSV.
- Converts dictionary-marked date variables.
- Restricts to ischemic diagnosis where `pat_diag_type` exists.
- Excludes patients younger than 18.
- Optionally excludes CRT-D patients with `EXCLUDE_CRT <- TRUE`.
- Excludes the Karolinska overlap centre if `ctr_name` exists.
- Checks follow-up consistency by comparing date-derived follow-up with `length_fu_mortality`.
- Constructs:
  - `Status_death`: `death == yes` gives 1, `death == no` gives 0.
  - `Time_death`: `length_fu_mortality`.
  - `Status_FIS`: `inap_shock == yes` gives 1, `inap_shock == no` gives 0.
  - `Time_FIS`: `length_fu_inap_shock`.
- Reclassifies heart transplant cases as non-deaths when `heart_transplant == yes`.
- Adds `DB <- "CERT"` and `ID_f <- paste0(DB, "-", ID)`.
- Saves `eu_cert_icd_cdm_ready.rds`, CSV, QC summary, and basic summary statistics.

### `helios_processing.R`

This script processes HELIOS data from a multi-sheet Excel workbook.

Main steps:

- Reads and merges multiple sheets by `PAT_INDEX`.
- Uses the dictionary to rename raw variables once.
- Excludes patients younger than 18.
- Optional CRT exclusion is available but set to `FALSE`.
- Constructs all-cause mortality:
  - `Status_death` from `Status_death_cat`.
  - `Time_death_days` from `DAYS2DEATH.ICD` for deaths and `DAYS2LastFU.ICD` for censored patients.
  - `t_followup_days <- Time_death_days`.
- Constructs exposure:
  - `Status_FIS` from `inappropriate_shock`.
  - `Time_FIS_days` from `DAYS2_inappropriate_shock.ICD` for exposed patients.
- Adds `DB <- "HELS"` and `ID_f <- paste0(DB, "-", ID)`.
- Saves `helios_cdm_ready.rds`, CSV, QC summary, and basic summary statistics.

### `israel_processing.R`

This script processes ISRAEL-ICD data.

Main steps:

- Loads raw CSV and dictionary.
- Renames all variables according to the dictionary.
- Optionally parses date columns based on dictionary data types.
- Excludes age `<18` when `EXCLUDE_AGE_LT18 <- TRUE`.
- Optional CRT exclusion is available but set to `FALSE`.
- Handles deaths after last follow-up by aligning `Alive_last_FU_days` with `Alive_total_days` for deceased patients.
- Constructs:
  - `Status_death`: `Status_last == "DIED"` gives 1, otherwise 0.
  - `Time_death_days` and `t_followup_days`: `Alive_last_FU_days`.
  - `Status_FIS`: `Inapp_shock_1st == "YES"` gives 1, `NO` gives 0.
  - `Time_FIS_days`: `Inapp_shock_days` for exposed and `Alive_last_FU_days` for unexposed.
- Reclassifies FIS events after follow-up as unexposed and censors their FIS time at follow-up.
- Adds `DB <- "ISRL"` and `ID_f <- paste0(DB, "_", ID)`.
- Saves processed RDS/CSV, QC summary, and basic summary statistics.

### `prose_processing.R`

This script processes PROSE-ICD data.

Main steps:

- Loads raw PROSE data, a co-enrollment ID file, a dictionary, and CDM.
- Renames variables using the dictionary.
- Excludes age `<18`.
- Excludes CRT patients by keeping only single- or dual-chamber ICD types.
- Removes co-enrolled patients using the join ID file.
- Defines follow-up as the maximum available time across `Death_days`, `days_to_app_shock`, and `t_inappshock`.
- Constructs:
  - `Status_death`: `Death_status == "Yes"` gives 1, `No` gives 0.
  - `Time_death`: `Death_days`.
  - `Status_FIS`: `inappshock == "Yes"` gives 1, `No` gives 0.
  - Missing shock information with available death follow-up is assumed `No`.
  - `Time_inapp`: `t_inappshock` for exposed and `Death_days` for unexposed.
- Adds `DB <- "PRSE"` and `ID_f <- paste0(DB, "-", ID)`.
- Saves `prose_cdm_ready.rds`, CSV, QC summary, and basic summary statistics.

### `Final_merge_script.R`

This script merges the ICD cohort with the four processed registry datasets.

Main steps:

- Loads the ICD master CSV plus processed EU-CERT, HELIOS, ISRAEL, and PROSE RDS files.
- Normalises IDs for CERT, HELS, and PRSE by trimming and replacing hyphens with underscores.
- Harmonises endpoint/follow-up column names:
  - `Status_death`
  - `Time_death_days`
  - `t_followup_days`
  - `Status_FIS`
  - `Time_FIS_days`
- Applies registry-specific naming fixes:
  - EU-CERT: `fu_days_from_dates -> t_followup_days`, `Time_death -> Time_death_days`, `Time_FIS -> Time_FIS_days`.
  - PROSE: `Time_death -> Time_death_days`, `Time_inapp -> Time_FIS_days`, `PRSE_` ID prefix changed to `PRSI_`.
- Stacks the four processed endpoint datasets.
- Merges stacked endpoint data into the ICD master cohort by `ICD$ID == stacked$ID_f`.
- Keeps only target databases `CERT`, `HELS`, `ISRL`, and `PRSE`.
- Drops rows without matched `Status_death`.
- Writes QC outputs for duplicates, completeness by DB, before/after counts, ID matching, and FIS-after-follow-up flags.
- Saves `icd_merged1.rds` and `icd_merged1.csv`.

### `Variables_overview.R`

This script creates a `gt` HTML table documenting, by source registry, how mortality, exposure, and follow-up variables were constructed. It is documentation/QC output rather than a data-transformation step.

## Numbered Analysis Scripts

### 1. `1.Preliminary analysis.R`

This is the first main analysis-stage script after the merged ICD cohort is available.

Inputs:

- `T:/FINAL ICD COHORT/icd_merged1.csv`

Outputs:

- `T:/FINAL ICD COHORT/standardised_data1.csv`
- `T:/FINAL ICD COHORT/standardised_data1.rds`

Main responsibilities:

- Loads the merged ICD cohort.
- Checks LVEF inclusion logic and duplicate IDs.
- Applies inadmissible value rules by setting implausible measurements to `NA`, without dropping rows. Examples:
  - `BMI < 12` or `BMI > 69`.
  - `BUN > 900`.
  - `Haemoglobin < 2` or `> 110`.
  - `LDL == 0`.
  - `Sodium < 99`.
  - `Triglycerides < 20`.
  - `TSH == 0`.
  - `HR < 25` or `> 140`.
  - `PR <= 50` or `> 1000`.
  - `QRS < 50`.
  - `QTc <= 250` or `> 790`.
- Applies the `<=40 day` baseline rule. If a patient is flagged as being within 40 days by baseline label, year-based timing, or day-based timing, selected variables are set to `NA`: `SBP`, `DBP`, `CRP`, `Troponin_T`, `NYHA`, `AV_block`, and `AV_block_II_or_III`.
- Standardises NYHA as ordered `I < II < III < IV`.
- Standardises binary-like fields to ordered `No < Yes` factors for tables.
- Creates `bin_*` 0/1 variables for Cox modelling.
- Creates `bin_sex_male`.

### 2. `2.Variable_transformation.R`

Inputs:

- `T:/FINAL ICD COHORT/standardised_data1.rds`

Output:

- `T:/FINAL ICD COHORT/Transformed_data1.rds`

Main responsibilities:

- Identifies numeric candidate variables for skewness assessment, excluding IDs, outcomes, exposure variables, time variables, existing binary indicators, and existing `*_log1p` variables.
- Produces exploratory histograms for candidate variables.
- Calculates Bowley skewness.
- Applies `log1p()` transformations where:
  - Bowley skewness is at least 0.2.
  - Values are non-negative.
  - There are at least 10 unique non-missing values.
- Drops a log transform if it over-corrects skewness into negative Bowley skewness.
- Creates before/after boxplot and histogram checks.
- Creates SAP age categories:
  - `<=50`
  - `51-65`
  - `66-75`
  - `>75`
- Creates a descriptive `age_group_desc`.

### 3. `3.data_cleaning_incidence_power_calc.R`

Inputs:

- `T:/FINAL ICD COHORT/Transformed_data1.rds`

Outputs:

- `T:/Study_1/master_clean_dataset1.rds`
- `TableS1_CohortDerivation.html`
- `results_crude_death.csv/.html`
- `inappropriate_therapy_incidence.csv/.html`
- `deaths_by_exposure.csv/.html`
- `exposure_summary.csv/.html`
- `power_posthoc_table.csv/.html`
- `power_mdhr_summary.csv/.html`
- `power_curve_table.csv/.html`

This script defines the final analytic cohort. Its rules are central to all downstream analyses.

Outcome cleaning rules:

- `O1`: remove patients with missing or zero `Time_death_days`.
- `O2`: if `Status_death` is missing but valid follow-up exists, recode as censored/alive (`0`).

Exposure cleaning rules:

- `E1`: if both `Status_FIS` and `Time_FIS_days` are missing, classify as unexposed and set FIS time to `Time_death_days`.
- `E2`: if FIS time exists but status is missing, classify as exposed.
- `E4`: if marked exposed but FIS timing is unknown, exclude the patient.
- `E5`: if FIS occurs at or after end of follow-up, reclassify as unexposed and set FIS time to `Time_death_days`.
- `E6`: if unexposed with missing FIS time, set FIS time to `Time_death_days`.

Analytical outputs:

- A cohort derivation table grouped by outcome and exposure handling.
- Crude all-cause mortality incidence per 100 person-years with exact Poisson CI.
- Crude first inappropriate ICD shock incidence per 100 person-years with exact Poisson CI.
- Death counts by ever/never inappropriate shock status.
- Exposure distribution summary.
- Post-hoc Cox power and minimum detectable hazard ratio using the Schoenfeld approximation.

### 4. `4.Table 1 and table S3.R`

Inputs:

- `T:/Study_1/master_clean_dataset1.rds`

Outputs:

- `Table1_baseline.html`
- `Table1_baseline.csv`
- `Table1_baseline.rds`
- `Supplementary_Missing_Data.html`
- `Supplementary_Missing_Data.csv`

Main responsibilities:

- Builds Table 1 by `Status_FIS`.
- Uses no p-values by design because the groups are strongly imbalanced and p-values are considered unhelpful for confounding assessment.
- Reports binary variables as `n (%)` using non-missing group denominators.
- Reports continuous variables as mean +/- SD.
- Shows NYHA as a 4-level categorical block.
- Excludes variables with at least 80% missingness from Table 1.
- Creates a supplementary missing data summary for outcome/exposure variables and covariates.

Table sections include:

- Demographic
- Clinical parameters
- Comorbidities
- Arrhythmia / Conduction / ECG
- Medical history
- Medications
- Laboratory

### 5. `5.KM1.R`

Inputs:

- `T:/Study_1/master_clean_dataset1.rds`

Outputs:

- `KM_FigA_time_to_FIS_fullcohort.png`
- `KM_FigA_time_to_FIS_fullcohort.pdf`

Main responsibilities:

- Fits `survfit(Surv(Time_FIS_years, Status_FIS) ~ 1)`.
- Plots cumulative incidence of first inappropriate ICD shock over 0-5 years.
- Computes whether median time to first inappropriate shock is estimable.
- Computes cumulative incidence at 1, 3, and 5 years.
- Builds a risk table panel under the figure.

This curve is explicitly descriptive and does not account for the time-dependent nature of exposure.

### 6. `6.KM2.R`

Inputs:

- `T:/Study_1/master_clean_dataset1.rds`

Outputs:

- `KM_FigB_survival_by_shock_fullcohort.png`
- `KM_FigB_survival_by_shock_fullcohort.pdf`

Main responsibilities:

- Groups patients by ever/never inappropriate shock.
- Fits `survfit(Surv(Time_death_years, Status_death) ~ shock_group)`.
- Produces overall survival curves over 0-5 years.
- Prints deaths by shock group.

This figure is also descriptive only because ever/never exposure grouping does not model the exposure as time-dependent.

### 7. `7.mice_full_cohort.R`

Inputs:

- `T:/Study_1/master_clean_dataset1.rds`

Outputs:

- `T:/Study_1/Imputed_data/mice_full_object1.rds`
- `T:/Study_1/Imputed_data/full_imputed_long1.csv`
- `T:/Study_1/Imputed_data/mice_audit_log_FULL1.csv`
- Missingness figures and logs under `T:/Study_1/Imputed_data/Figures` and `T:/Study_1/Imputed_data/Logs`

Main responsibilities:

- Builds a full-cohort imputation dataset.
- Keeps ID, outcome, exposure, time-zero variables, continuous variables, categorical variables, binary variables, and base variables required for passive log transforms.
- Removes pre-existing `*_log1p` columns from the imputation dataset so they can be passively derived after or during imputation.
- Summarises and plots missingness.
- Drops variables with more than 80% missingness.
- Removes duplicate base variables when a `bin_*` version exists.
- Runs optional missingness diagnostics:
  - Little's MCAR test on numeric variables.
  - A MAR quick screen using missingness indicators regressed against observed predictors.
- Builds a MICE specification:
  - IDs, outcomes, exposures, and time-zero variables are not imputed.
  - Outcome variables can be used as predictors.
  - Exposure variables are not used as predictors.
  - ID and time-zero variables are not used as predictors.
  - Binary/factor variables use logistic or polytomous regression.
  - Numeric variables use predictive mean matching.
  - Passive `*_log1p` transforms are configured where the base variable exists.
- Applies special handling for problematic binary variables:
  - `bin_anti_diabetic` filled from `bin_diabetes`, with remaining missing values set to 0.
  - `bin_anti_diabetic_insulin` forced to logistic imputation or filled as a constant if only one level exists.
  - `bin_av_block_ii_or_iii` filled with 0 due to very high missingness and rare positives.
- Uses a guardrail test imputation to remove rows that remain non-imputable.
- Runs MICE with `m = 20`, `maxit = 10`, seed `123`.
- Saves the `mids` object and an audit log.

### 8. `8.full_cohort_cox_model_and_development.R`

Inputs:

- `T:/Study_1/Imputed_data/mice_full_object1.rds`

Output directory:

- `T:/Study_1/Supplementary_data/Primary`

This is the main primary modelling script.

Primary estimand:

- Outcome: all-cause mortality.
- Exposure: time-dependent inappropriate ICD shock (`FIS_td`).
- Time scale: days from ICD implantation to death or censoring.
- Cohort handling: `strata(DB)` in the primary model.
- Pooling: Rubin-style pooling across 20 MICE imputations.

Core model construction:

- Converts each imputed wide dataset into start-stop long format using `survival::tmerge`.
- Defines death as `event(Time_death_days, Status_death == 1)`.
- Defines time-dependent FIS using `tdc(Time_FIS_days)`.
- Ensures one baseline row per `ID`.

Forced covariates:

- `Age`
- `bin_sex_male`
- `LVEF`
- `NYHA`
- `bin_diabetes`
- `eGFR`
- `bin_beta_blockers`
- `bin_af_atrial_flutter`

Candidate covariates include:

- `bin_hypertension`
- `bin_smoking`
- `Haemoglobin`
- `SBP`
- `BMI`
- `HR`
- `QRS_log1p`
- `bin_hf`
- `bin_stroke_tia`
- `bin_av_block`
- `bin_lbbb`
- `bin_ace_inhibitor`
- `bin_ace_inhibitor_arb`
- `bin_diuretics`
- `bin_anti_arrhythmic_iii`
- `bin_anti_coagulant`
- `bin_anti_platelet`
- `bin_lipid_lowering`
- `bin_anti_diabetic_oral`
- `bin_digitalis_glycosides`
- `bin_pci`
- `HasMRI`

Model development steps:

1. Fit crude `FIS_td` model.
2. Screen each covariate in a model with `FIS_td + covariate`.
3. Keep screened variables with p-value `<0.05`.
4. Combine forced and screened variables.
5. Perform correlation pruning for numeric variables with `|r| > 0.70`, preserving forced variables.
6. Fit a full multivariable model.
7. Apply backward selection to non-forced covariates.
8. Fit the final selected model.
9. Check proportional hazards using `cox.zph` on imputation 1.
10. Check continuous-variable linearity using Martingale residual plots.
11. Fit the primary model with `strata(DB)`.
12. Run exposure feasibility checks, interactions, and subgroups.

Important outputs:

- `00_crude_FIS_model.html`
- `01_screening_summary.html`
- `01_screening_summary_formatted.html`
- `01_screening_factor_details1.csv`
- `02_high_correlations.csv/.html`
- `03_full_model.csv`
- `04_final_model1.csv/.html`
- `04_final_model1_pretty.html`
- `05_ph_test.txt`
- `05_ph_plots.pdf`
- `05_linearity_plots.pdf`
- `07_primary_model_strata_DB.csv/.html`
- `08_interaction_tests.csv/.html`
- `09_subgroup_HR_FIS_td.csv`
- `09_subgroup_table.png/.pdf`
- `14_forest_plot_subgroups.png/.pdf`
- `14_forest_HR_sidetable.png/.pdf`

Interaction testing:

- Tests interactions between `FIS_td` and selected final-model covariates.
- Uses binary `NYHA_bin` for NYHA interaction testing to avoid collinearity with the 4-level factor.

Subgroups:

- Age group: `<65`, `65-75`, `>75`
- LVEF category: `<30`, `30-35`, `>35`
- Sex
- Atrial fibrillation/flutter
- Diabetes mellitus
- NYHA class: `I-II` vs `III-IV`

### 9. `9.Landmark_analysis.R`

Inputs:

- `T:/Study_1/Imputed_data/mice_full_object1.rds`
- Optional comparison input: `T:/Study_1/Supplementary_data/Primary/07_primary_model_strata_DB.csv`

Output directory:

- `T:/Study_1/Supplementary_data/Sensitivity`

Purpose:

- Sensitivity analysis to the primary time-dependent Cox model.
- Addresses immortal time bias through landmark restriction rather than counting-process start-stop modelling.

Landmarks:

- 6 months: 183 days.
- 12 months: 365 days.
- 24 months: 730 days.

At each landmark:

- Includes only patients alive beyond the landmark.
- Defines `FIS_L` as any inappropriate shock at or before the landmark.
- Starts follow-up clock at the landmark.
- Models all-cause mortality after the landmark.

Model:

```text
Surv(t_landmark, event) ~ FIS_L + Age_10 + LVEF_5 + eGFR_10 +
  QRS_log1p + bin_beta_blockers + bin_diabetes + bin_stroke_tia +
  bin_af_atrial_flutter + bin_sex_male + NYHA_grp + strata(DB)
```

Details:

- `NYHA` is dichotomised as `I-II` vs `III-IV`.
- `Age`, `LVEF`, and `eGFR` are rescaled for interpretability.
- `QRS_log1p` is derived from raw `QRS`.
- Estimates are pooled across imputations using `mice::pool()`.

Outputs:

- Forest plots per landmark.
- HR tables per landmark.
- `SUMMARY_Landmark_fullcohort.csv/.html`
- `LANDMARK_risk_table.csv/.html`
- `COMPARISON_primary_vs_landmark.csv/.html`

### 10. `10.Fine_gray.R`

Inputs:

- `T:/Study_1/Imputed_data/mice_full_object1.rds`

Output directory:

- `T:/Study_1/Supplementary_data/Fine_gray`

Purpose:

- Landmark competing-risk sensitivity analysis using Fine-Gray subdistribution hazard models.

Landmarks:

- 6, 12, and 24 months, converted with `30.4375` days per month.

Competing-risk setup:

- `VAR_TIME <- "Survival_time"` in months, converted to days.
- `VAR_STATUS <- "Status"` where:
  - `0` means censored/alive.
  - `1` means appropriate shock.
  - `2` means death.
- `Status_FIS` and `Time_FIS_days` define inappropriate shock exposure before the landmark.

Important analysis differences:

- `cmprsk::crr()` is used.
- `DB` is not included because `crr()` does not support `strata(DB)`.
- NYHA is binary (`III-IV` vs `I-II`).
- QRS is transformed inside the script as `log1p(QRS)`.
- `Time_FIS_days > Survival_time_days` is reclassified as unexposed.
- Missing or zero `Survival_time` is excluded.
- Missing `Status` is treated as censored.

Outputs:

- Fine-Gray sHR PDF tables per landmark.
- Fine-Gray forest plots per landmark.
- CIF plots per landmark using imputation 1.
- `TableS2_FineGray_CohortDerivation.html`.
- Console QC summaries for at-risk, exposed, and cause-specific event counts.

## Key Variables and Concepts

| Variable | Meaning |
|---|---|
| `ID` | Patient identifier in the merged cohort. |
| `DB` | Source cohort/database code: `CERT`, `HELS`, `ISRL`, `PRSE`. |
| `Status_death` | All-cause mortality indicator for Cox/KM analyses. |
| `Time_death_days` | Follow-up time to death or censoring in days. |
| `Status_FIS` | Indicator for first inappropriate ICD shock/therapy. |
| `Time_FIS_days` | Time to first inappropriate shock/therapy or censoring time, in days. |
| `FIS_td` | Time-dependent exposure created by `tmerge()` for the primary Cox model. |
| `FIS_L` | Landmark-fixed exposure: inappropriate shock by landmark time. |
| `Survival_time` | Used in Fine-Gray script; documented there as months. |
| `Status` | Fine-Gray competing-risk status: censored, appropriate shock, death. |
| `NYHA` | NYHA class, generally handled as 4-level factor in primary Cox. |
| `NYHA_bin` / `NYHA_grp` | Dichotomised NYHA for interactions, subgroups, and landmark analyses. |
| `QRS_log1p` | Log-transformed QRS duration, generally derived from raw `QRS`. |
| `bin_*` | Binary 0/1 variables created from harmonised clinical fields. |

## Statistical Approach

The primary analysis is a Cox proportional hazards model for all-cause mortality with inappropriate ICD shock modelled as a time-dependent exposure. This avoids classifying exposed patients as exposed before their shock occurred.

The model uses multiple imputation for missing covariates and pools estimates across 20 imputed datasets. The primary model includes `strata(DB)` so that baseline hazards may differ by source cohort.

Sensitivity analyses include:

- Landmark Cox models at 6, 12, and 24 months.
- Fine-Gray landmark competing-risk analyses at 6, 12, and 24 months.
- Interaction tests and prespecified subgroup analyses.

## Dependencies

The scripts use common R packages including:

- `tidyverse`
- `dplyr`
- `data.table`
- `survival`
- `mice`
- `naniar`
- `VIM`
- `openxlsx`
- `readxl`
- `gt`
- `ggplot2`
- `grid`
- `gridExtra`
- `patchwork`
- `scales`
- `survminer`
- `cmprsk`
- `timeROC`
- `prodlim`
- `riskRegression`
- `broom`
- `haven`
- `stringr`

Many scripts call `install.packages()` inline. That makes first-run setup convenient but can be undesirable for reproducible or locked-down production environments.

## Output Organization

The code writes to several external folders:

- `T:/FINAL ICD COHORT`
  - merged and standardised datasets.
- `T:/Study_1`
  - master clean dataset.
- `T:/Study_1/Supplementary_data`
  - Table 1, missingness, incidence, power, and KM outputs.
- `T:/Study_1/Imputed_data`
  - MICE objects, long imputed CSV, audit logs, missingness figures.
- `T:/Study_1/Supplementary_data/Primary`
  - primary Cox model outputs.
- `T:/Study_1/Supplementary_data/Sensitivity`
  - landmark Cox sensitivity outputs.
- `T:/Study_1/Supplementary_data/Fine_gray`
  - Fine-Gray sensitivity outputs.

## Implementation Notes and Risks

The codebase is understandable as a sequential analysis record, but it has several maintainability and reproducibility issues:

- Paths are hard-coded to Windows/network drives. The scripts will not run unchanged on another machine.
- Script names and ordering encode the workflow, but there is no formal runner, dependency graph, or project-level configuration.
- Several scripts install packages at runtime.
- There are duplicated helper functions across scripts, especially binary conversion, NYHA handling, pooling, and table writing.
- Some comments and printed messages refer to train/test outputs even though the current MICE script saves only the full-cohort object.
- Some paths appear to miss a slash, for example `T:Study_1/...` instead of `T:/Study_1/...`.
- Some code includes duplicated or stale sections, such as repeated `check_required()` definitions and repeated subgroup-table generation.
- Some labels contain probable typos, for example `QRS_loglp` instead of `QRS_log1p` in presentation recodes.
- The Fine-Gray script uses `Survival_time` and `Status`, while the primary Cox analysis uses `Time_death_days` and `Status_death`; this distinction is important and should be documented carefully in any methods write-up.

## Recommended Refactoring Direction

If this codebase were to be hardened for reuse, the highest-impact changes would be:

1. Move all paths and constants into one configuration file.
2. Replace inline `install.packages()` calls with a reproducible environment file such as `renv.lock`.
3. Split repeated helper functions into shared R files.
4. Add a top-level runner script that records the pipeline order.
5. Save run metadata with package versions, input file hashes, and output timestamps.
6. Add automated QC checks for key assumptions:
   - no missing `Status_death`, `Time_death_days`, `Status_FIS`, or `Time_FIS_days` after cleaning;
   - no FIS time after death/follow-up after final cleaning;
   - consistent source cohort counts through preprocessing and merge;
   - expected MICE variables and methods.
7. Standardise file naming and remove stale train/test references if not used.

