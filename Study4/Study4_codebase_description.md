# Study4 Codebase Description

Generated on 2026-05-29 from a static review of the files under `Study4/`.

## Executive summary

`Study4/` contains an R-based analysis workflow for PROFID Study 4: sudden cardiac death (SCD) after myocardial infarction, with a primary emphasis on age-stratified analyses. The code combines ICD and non-ICD cohorts, performs harmonisation and data-quality filtering, derives age groups and analysis-ready variables, then runs incidence-rate, competing-risk, Cox survival, model-validation, sensitivity, and multiple-imputation analyses.

The intended data flow is:

1. Import and harmonise source cohort CSVs into `dat`.
2. Handle complex variables and derive `df_handled`.
3. Create complete-case datasets such as `df_handled_cc`.
4. Estimate crude and age-standardised SCD incidence.
5. Run competing-risk analyses using cumulative incidence functions and Fine-Gray models.
6. Run cause-specific survival analyses using Kaplan-Meier and Cox models.
7. Validate Fine-Gray and Cox models with discrimination, calibration, and bootstrap optimism checks.
8. Run complete-case sensitivity analyses.
9. Run multiple imputation and compare MI-pooled results with complete-case results.

The scripts are mostly procedural and rely on objects created in earlier scripts remaining in the same R session. They are not structured as a package and do not currently have a single robust driver script.

## File inventory

| File | Lines | Main role |
| --- | ---: | --- |
| `1_Study_Harmonisation.Data_.Quality.Control_Age.Stratification.R` | 1050 | Imports source CSVs, harmonises cohorts, creates `dat`, applies QC rules, creates log transforms and age groups, and includes exploratory table checks. |
| `2_.Handlign.of.complex.variables_df_handled.R.txt` | 114 | Converts `dat` to `df_handled`, handles atrial fibrillation variables, creates Fine-Gray status/time fields, and saves `df_handled.rds`. |
| `3__.Incidence.Rate.calculations.R.txt` | 322 | Calculates crude age-specific SCD incidence per 1,000 person-years and WHO 2000-2025 age-standardised incidence. |
| `4_.Competing.risk.analysis.R.txt` | 420 | Computes univariate CIFs by age, plots SCD and non-SCD competing-risk summaries, and fits a multivariable Fine-Gray model. |
| `5_Survival.analysis.fromwark.R.txt` | 347 | Runs Kaplan-Meier SCD-free survival and Cox proportional-hazards analyses with PH checks and age interaction screening. |
| `6_Risk_factors_identification.R.txt` | 451 | Despite its filename, this is effectively a Fine-Gray model validation script and is almost identical to file 7. |
| `7_Validation.FG.Model.Performance.R.txt` | 453 | Validates Fine-Gray model performance: SHR table, Harrell C, time-dependent AUC, calibration, HL-like checks, and bootstrap optimism. |
| `8_Validation.COX.model.1.performance.R` | 290 | Validates Cox model performance: Harrell C, time-dependent AUC, calibration groups, HL-like checks, and bootstrap optimism. |
| `9_.Sensitivity.analyses_CC.R` | 343 | Runs complete-case Cox sensitivity scenarios: alternative age bands, key-variable complete cases, complete echo subset, ICD-only, and non-ICD. |
| `Multiple.Imputation.strategy.R.txt` | 332 | Builds MICE imputations, exports imputed datasets, pools Cox results, and attempts pooled Fine-Gray summaries. |
| `Incidence Rate Calculations` | 1 | Empty or placeholder file. |

## Main scientific objective represented in code

The code is built around Study 4 of the PROFID/UmBIZO analysis program. The outcome of interest is SCD after MI. The analysis distinguishes SCD from non-SCD death as a competing event and repeatedly stratifies or adjusts by age groups:

| Age group | Interpretation in comments |
| --- | --- |
| `<=50` | young adults |
| `51-65` | middle-aged |
| `66-75` | older adults |
| `>75` | elderly |

The primary status convention is:

| Code | Meaning |
| ---: | --- |
| `0` | censored |
| `1` | SCD event |
| `2` | non-SCD death or competing event |

For Cox models, the event is recoded to `event_scd = 1` for SCD and `0` for censored/non-SCD. For competing-risk methods, the three-level status is retained as `fstatus`.

## Detailed pipeline

### 1. Harmonisation, quality control, and age stratification

File: `1_Study_Harmonisation.Data_.Quality.Control_Age.Stratification.R`

This is the main upstream preparation script. It expects source CSVs in a Windows/network path:

- `combined_dataset.csv`
- `ICD_all.csv`
- `ICD.csv`
- `NonICD_preserved.csv`
- `NonICD_reduced.csv`

It creates cohort flags:

- `ICD_status`: intended to mark ICD cohort membership.
- `LVEF_category`: `Reduced` for ICD and non-ICD reduced EF, `Preserved` for non-ICD preserved EF.

It aligns the three cohort data frames by:

- forcing selected clinical variables to numeric;
- taking the union of available columns;
- adding missing columns as `NA`;
- row-binding into `dat`;
- moving important identifiers and survival fields to the front.

Important derived variables and transformations:

- `*_log1p` companions are added for right-skewed positive variables.
- The scripted final log-transform list is intended to include `CRP`, `Greyzone_size`, `NTProBNP`, `Troponin_T`, plus SAP-required `BMI` and `eGFR`.
- Binary clinical variables and medication variables are standardised to ordered factor levels `No`, `Yes`.
- `NYHA` is normalised to ordered factor levels `I`, `II`, `III`, `IV`.
- `age_group` and `age_group_desc` are created from numeric `Age`.

Quality-control logic includes:

- inadmissible-value bounds for BMI, BUN, cholesterol, haemoglobin, HbA1c, HDL, LDL, sodium, triglycerides, TSH, HR, PR, QRS, and QTc;
- a rule to set early measurements to missing if they were taken within 40 days after MI;
- a 7x IQR outlier screen for selected variables such as `Total_scar` and `NTProBNP`, intended as reporting rather than deletion.

The file also contains a substantial exploratory section after the main QC/age-stratification work. That section checks ARB tabulations, coronary vessel variables, medication variables, atrial fibrillation/anticoagulation consistency, and ICD therapy-related variable names.

Important implementation notes:

- The file currently does not parse completely; `Rscript` parsing stops near line 792 because an earlier `table(...)` call appears unfinished.
- Some expressions appear to be accidental code rather than comments, for example assignments such as `NonICD_preserved$ICD_status <- 0 >35`.
- Some within-40-day checks use `is.na(y) & y < threshold`, which cannot be true for finite values and likely should be `!is.na(y) & y < threshold`.
- `Time_index_MI_CHD` is described as days but is compared to a threshold expressed in years in one branch.
- `QTc` is written back as `QTC`, creating a new column name rather than updating `QTc`.
- The script calls `install.packages()` inside the analysis script, which makes reproducible execution harder.

### 2. Complex variable handling and `df_handled`

File: `2_.Handlign.of.complex.variables_df_handled.R.txt`

This script expects `dat` from step 1. It creates `df_handled`, the main downstream analysis object.

Main operations:

- normalises `age_group` labels to the four SAP age groups;
- recodes Yes/No style variables;
- searches for atrial fibrillation columns;
- creates `AF_any` from the first available source among `AF_any`, `AF`, and `AF_atrial_flutter`;
- retains `AF_type` only if it has at least two informative non-missing levels;
- applies another time-zero rule to selected baseline variables;
- creates `fstatus` from `Status` when possible;
- creates `ftime_mo_int` from `Survival_time`, rounded to integer months;
- saves `df_handled.rds`.

The comments report a resulting object of about 139,915 rows and 107 columns.

Implementation note:

- The function named `apply_within40_rule()` sets baseline variables to `NA` when `days > boundary_days`. Given the surrounding comments, this appears inverted: a within-40-day rule would normally mark `days <= 40`.

### 3. Incidence-rate calculations

File: `3__.Incidence.Rate.calculations.R.txt`

This script expects `df_handled` with `ftime_mo_int`, `fstatus`, and `age_group`, but it also initially checks for `df` with `age_group`, `Status`, and `Survival_time`. It then sets `df <- df_handled`.

Main analyses:

- creates `SCD_event = Status == 1`;
- converts `Survival_time` from months to person-years;
- drops rows with invalid person-time or missing age group;
- calculates crude age-specific SCD incidence per 1,000 person-years;
- calculates exact Poisson confidence intervals using `poisson.test()`;
- creates an all-ages crude incidence row;
- plots crude age-specific incidence with error bars;
- aggregates WHO 2000-2025 world standard population weights into the four Study 4 age bands;
- calculates direct age-standardised incidence per 1,000 person-years;
- estimates a quasi-Poisson overdispersion factor and inflated CI;
- exports tables:
  - `SCD_incidence_crude_by_age.csv`
  - `WHO2000_2025_weights_4bands.csv`
  - `SCD_incidence_ASR_WHO2000_2025.csv`

Implementation notes:

- The quasi-Poisson call uses `dfa = pl`; the intended argument is almost certainly `data = pl`.
- The code uses both `df$Status` and `df_handled$fstatus`; consistency depends on upstream objects retaining both fields.
- The export path is `T:/study_4`, with fallback to `~/Study4_outputs` in the second export block.

### 4. Competing-risk analysis

File: `4_.Competing.risk.analysis.R.txt`

This script expects `df_handled` with:

- `ftime_mo_int`
- `fstatus`
- `age_group`

It uses `cmprsk::cuminc()` for univariate cumulative incidence functions by age group.

Univariate outputs:

- CIF estimates at 12, 36, and 60 months by age group;
- primary 36-month CIF table;
- Gray's test p-value for between-age-group comparison;
- CIF curve plot by age;
- bar charts at 12, 36, and 60 months;
- grouped bar and line displays for CIF snapshots;
- stacked 36-month SCD vs non-SCD competing-risk bar chart.

Multivariable Fine-Gray model:

- complete-case data are selected from `df_handled`;
- continuous covariates are scaled per 1 SD:
  - `LVEF`
  - `eGFR`
  - `BMI`
  - `Haemoglobin`
- binary covariates:
  - `Diabetes`
  - `Hypertension`
  - `ACE_inhibitor`
  - `ARB`
  - `Anti_coagulant`
- `age_group` is included, with `<=50` as reference by factor ordering;
- model fitting uses `cmprsk::crr()`;
- results are exported as `FG_MULTI_SHR_completecases.csv`;
- a forest plot is produced for adjusted subdistribution hazard ratios.

Output directories:

- tables: `T:/study_4/Results_tables`, falling back to local `Results_tables`;
- figures: `T:/study_4/Results_graph`, falling back to local `Results_graph`.

### 5. Survival analysis framework

File: `5_Survival.analysis.fromwark.R.txt`

This file implements cause-specific survival analysis using Kaplan-Meier and Cox proportional hazards models.

Kaplan-Meier section:

- builds `df_handled_cc` initially from `ftime_mo_int`, `fstatus`, and `age_group`;
- converts months to `time_years`;
- defines `event_scd = fstatus == 1`;
- estimates SCD-free survival by age group;
- exports survival at 1, 3, and 5 years to `KM_survival_at_1_3_5_years_by_age.csv`;
- plots SCD-free survival with a zoomed y-axis.

Cox model section:

- rebuilds `df_handled_cc` as complete cases for:
  - `ftime_mo_int`
  - `fstatus`
  - `age_group`
  - `LVEF`
  - `eGFR`
  - `BMI`
  - `Haemoglobin`
  - `Diabetes`
  - `Hypertension`
  - `ACE_inhibitor`
  - `ARB`
  - `Anti_coagulant`
- scales continuous covariates per 1 SD;
- fits age-only Cox and multivariable Cox models;
- creates hazard-ratio tables manually from coefficients and variance matrices.

Model diagnostics and interactions:

- runs Schoenfeld residual PH tests using `cox.zph()`;
- attempts residual plots;
- screens each covariate for interaction with `age_group` using likelihood-ratio tests;
- if significant interactions exist, fits a final model and exports:
  - `CoxPH_age_interaction_LRT.csv`
  - `CoxPH_final_with_interactions_HR_table.csv`
  - `CoxPH_PH_tests_Schoenfeld_final.csv`
  - per-variable within-age HR tables.

The inline comments report 101,517 complete cases out of 139,915 and significant age interactions for `Diabetes` and `LVEF`.

Implementation notes:

- The script parses, but `write_df()`, `open_dev()`, and `close_dev()` are called without being defined in this file. The file defines similarly intended helpers `write_tab()`, `open_fig()`, and `close_fig()`.
- The header says the dataset is `df_handled_cc`, but the script reconstructs `df_handled_cc` more than once with different column sets.

### 6. Fine-Gray validation and duplicated risk-factor file

Files:

- `6_Risk_factors_identification.R.txt`
- `7_Validation.FG.Model.Performance.R.txt`

These two files are effectively duplicates. A `diff` showed only header/comment differences at the top. Despite the `6_Risk_factors_identification` filename, the content is Fine-Gray validation code, not a distinct risk-factor selection workflow.

The script expects `df_handled_cc` and creates a competing-risk dataset:

- `time_months = ftime_mo_int`
- `Status = fstatus`
- normalised `age_group`

Main analyses:

- fits an age-only Fine-Gray model with `cmprsk::crr()`;
- creates a subdistribution hazard ratio table for age groups;
- computes a linear predictor from the age design matrix;
- calculates Harrell's C using `survival::concordance()`;
- calculates time-dependent AUC at 12, 36, and 60 months using `timeROC`;
- exports `fg_timeROC_AUC.csv` and `fg_Harrell_Cindex.csv`;
- builds calibration summaries and calibration plots;
- fits a `riskRegression::FGR()` object when needed for `predictRisk()`;
- calculates decile calibration tables at 12, 36, and 60 months;
- exports:
  - `fg_calibration_deciles_12m.csv`
  - `fg_calibration_deciles_36m.csv`
  - `fg_calibration_deciles_60m.csv`
  - `fg_calibration_deciles_all.csv`
  - `fg_calibration_HL_like.csv`
- runs bootstrap optimism correction for Harrell C and time-dependent AUC.

Reported AUC comments in the file:

| Horizon | Fine-Gray AUC |
| ---: | ---: |
| 12 months | 0.5824350 |
| 36 months | 0.6103838 |
| 60 months | 0.6457874 |

Implementation notes:

- `library()` is called without an argument around the calibration section, which will error if executed.
- Several CSV exports write to the current working directory rather than the configured `out_dir`.
- The bootstrap default is documented as `n=1000`, but the function default is `B=10`; the caller can override it.
- The model appears age-only, not multivariable, in these validation scripts.

### 7. Cox model validation

File: `8_Validation.COX.model.1.performance.R`

This script expects `df_handled_cc` and a Cox model `cox_multi`, or it refits one if missing.

Main analyses:

- converts follow-up to `time_years`;
- recodes `event_scd = fstatus == 1`;
- scales continuous covariates;
- fits or reuses a multivariable Cox model;
- computes Harrell's C;
- computes time-dependent AUC at 1, 3, and 5 years using `timeROC`;
- creates Cox predicted risks at each horizon using `basehaz()` and linear predictors;
- creates calibration groups, using three groups rather than ten deciles;
- plots predicted vs observed Kaplan-Meier risks;
- calculates a Hosmer-Lemeshow-like chi-square by horizon;
- runs bootstrap optimism correction for Harrell C and AUC.

Reported performance comments in the file:

| Metric | Value |
| --- | ---: |
| Harrell C | 0.2562451 |
| AUC at 1 year | 0.7599869 |
| AUC at 3 years | 0.7669015 |
| AUC at 5 years | 0.7760376 |

Implementation notes:

- The output root is `T:/studyears_4`, which differs from the otherwise common `T:/study_4`.
- `predict(cox_multi, tyearspe = "lp")` appears to intend `type = "lp"`.
- The `coxph()` refit uses `years = TRUE`, which is not a standard `coxph()` argument.
- The AUC plot uses arguments such as `tyearspe`, `yearslab`, and `grid(...)` inside the plot call; these are likely typos for `type`, `ylab`, and a separate `grid()` call.
- Bootstrap code refers to `cox_form`, but this object is not defined in this file when the model is refit as `f_cox`.
- `data.table::fwrite()` writes `cox_calibration_HL_like.csv` to the current working directory rather than `OUT_TAB`.

### 8. Complete-case sensitivity analyses

File: `9_.Sensitivity.analyses_CC.R`

This script expects `df_handled_cc` and runs Cox sensitivity analyses on complete-case data.

Scenarios:

1. Alternative age cutoffs:
   - `ALT_55_64_74`: `<=55`, `56-64`, `65-74`, `>74`
   - `ALT_60_70_75`: `<=60`, `61-70`, `71-75`, `>75`
2. Exclude patients missing key variables, especially `LVEF`, `eGFR`, and `Diabetes` when present.
3. Restrict to complete echocardiography variables, falling back to `LVEF` if richer echo variables are absent.
4. Separate analyses in ICD-only and non-ICD subsets.

The analysis engine:

- derives `time_years` and `event_scd`;
- normalises medication and anticoagulant synonyms;
- normalises age groups or creates alternative age bands from numeric `Age`;
- chooses model variables from an existing `results` object, from `final_summary.csv`, or from a default covariate set;
- fits Cox models within each age band;
- skips underpowered strata with fewer than 25 complete cases or fewer than 5 events;
- exports scenario-specific HR and summary CSVs, plus stacked all-scenario files.

Key outputs include:

- `sens_COX_AGE_ALT_ALT_55_64_74.csv`
- `sens_COX_AGE_ALT_ALT_60_70_75.csv`
- `sens_COX_CC_KEYVARS.csv`
- `sens_COX_COMPLETE_ECHO.csv`
- `sens_COX_ICD_ONLY.csv`
- `sens_COX_NO_ICD.csv`
- `sens_COX_ALL.csv`
- `sens_COX_SUM_ALL.csv`

Implementation note:

- If neither a `results` object nor `final_summary.csv` exists, the script falls back to a default global covariate set.

### 9. Multiple-imputation strategy

File: `Multiple.Imputation.strategy.R.txt`

Despite the header saying it uses `df_handled_cc`, this script actually requires `df_handled` and builds an imputation frame from that object.

Main steps:

- normalises survival time variables;
- ensures `time_years`, `ftime_mo_int`, `event_scd`, and `fstatus`;
- defines candidate continuous variables:
  - `LVEF`
  - `eGFR`
  - `BMI`
  - `Haemoglobin`
- defines candidate binary variables:
  - `Diabetes`
  - `Hypertension`
  - `ACE_inhibitor`
  - `ARB`
  - `Anti_coagulant`
  - optional `Beta_blocker`, `Statin`
- includes optional ordered/factor `MR_severity`;
- builds a MICE predictor matrix and method vector;
- prevents imputation of outcome/time variables and age group;
- uses predictive mean matching for continuous variables;
- uses logistic regression for binary variables;
- uses proportional odds logistic regression for ordered `MR_severity`;
- applies post-imputation upper bounds for selected continuous variables;
- runs an initial test imputation with `m = 2`, then the main imputation with `m = 20`;
- exports:
  - `mice_imp_object.rds`
  - `df_imputed_01.csv` through `df_imputed_20.csv`
  - matching RDS files
  - `df_imputed_LONG.csv`
  - `df_imputed_LONG.rds`
  - optional `imputed_csvs.zip`
- fits and pools Cox models across imputations;
- attempts a complete-case comparison;
- attempts Fine-Gray pooling using scalar Rubin pooling for each coefficient.

Implementation notes:

- `cox_form` is used in the complete-case comparison section but is not defined in this file.
- The script contains a check `stopifnot(colSums(pred[, c(...)]) > 0)` that returns a vector; this can fail if any protected outcome/time column is not used as a predictor. The intended check may be more specific.
- `NTproBNP`/`NTPOBNP` post-processing names do not match the earlier common `NTProBNP` spelling.

## Shared objects and dependencies

Important objects passed through the workflow:

| Object | Created in | Used by |
| --- | --- | --- |
| `ICD`, `NonICD_preserved`, `NonICD_reduced` | Script 1 | Script 1 exploratory checks; possible manual follow-up |
| `dat` | Script 1 | Script 2; exploratory code |
| `df_handled` | Script 2 | Scripts 3, 4, 5, Multiple Imputation |
| `df_handled_cc` | Scripts 4/5 and reused later | Scripts 6, 7, 8, 9 |
| `cox_multi` | Script 5 or 8 | Script 8 validation |
| `fit_fg_multi` | Script 4 | Fine-Gray model result table |
| `fgr_fit` | Scripts 6/7 | Fine-Gray calibration and bootstrap validation |
| `imp` | Multiple-imputation script | MI export, Cox pooling, Fine-Gray pooling |

R packages used across scripts:

- `tidyverse`
- `dplyr`
- `janitor`
- `lubridate`
- `stringr`
- `readr`
- `survival`
- `cmprsk`
- `mice`
- `survminer`
- `broom`
- `ggplot2`
- `ggrepel`
- `scales`
- `timeROC`
- `riskRegression`
- `prodlim`
- `pec`
- `data.table`
- `simkid`

## Output structure

The scripts primarily write to Windows-style paths:

- `S:/AG/f-dhzc-profid/Data Transfer to Charite` for input data in script 1.
- `T:/study_4`
- `T:/study_4/Results_tables`
- `T:/study_4/Results_graph`
- `T:/study_4/Results_survival`
- `T:/study_4/Imputed_data`
- `T:/study4/Results_tables`
- `T:/studyears_4/Results_tables`

Several scripts include local fallbacks if `T:/study_4` is unavailable, but path handling is inconsistent. The inconsistency matters because `T:/study_4`, `T:/study4`, and `T:/studyears_4` are treated as different directories.

## Static parse check

A lightweight `Rscript` parse check was run for all files in `Study4/`.

Result:

- All files parse successfully except `1_Study_Harmonisation.Data_.Quality.Control_Age.Stratification.R`.
- Script 1 fails parsing at approximately line 792 because of an unfinished expression before `vars_check`.
- The parse check does not guarantee runtime success. Several other scripts parse but contain undefined objects or likely typographical errors noted above.

## Main runability risks

1. No single orchestrating script defines the full run order, loads intermediate RDS files, and creates all required objects.
2. Several scripts assume an interactive R session where objects from prior scripts remain in memory.
3. Path roots are inconsistent (`T:/study_4`, `T:/study4`, `T:/studyears_4`).
4. Script 1 currently has a parse error and therefore cannot be sourced end to end.
5. Some helper functions are referenced before being defined or are named inconsistently, for example `write_df()`, `open_dev()`, `close_dev()`, and `cox_form`.
6. Scripts 6 and 7 duplicate Fine-Gray validation logic; script 6's filename does not match its content.
7. Several likely typos can change model behavior or stop execution:
   - `tyearspe` instead of `type`;
   - `yearslab` instead of `ylab`;
   - `data` misspelled as `dfa`;
   - `Time_Y` used instead of `Time_zero_Y`;
   - `QTC` created instead of updating `QTc`;
   - `library()` without an argument.
8. The within-40-day rule is implemented inconsistently across scripts and should be reviewed against the SAP.
9. Package installation is embedded in script 1 rather than handled through a reproducible setup step.
10. File extensions are inconsistent: many executable R scripts are saved as `.R.txt`.

## Recommended cleanup path

1. Split script 1 into a sourceable harmonisation script and a separate exploratory QA notebook/script.
2. Fix script 1 parse errors and the obvious variable-name/logic issues before running downstream analyses.
3. Add a top-level driver script, for example `00_run_study4_pipeline.R`, that sources scripts in order and saves/loads stable RDS objects.
4. Standardise all output roots through one variable, for example `STUDY4_OUT_DIR`.
5. Rename `.R.txt` files to `.R` once they are intended for execution.
6. Consolidate duplicated Fine-Gray validation code by keeping script 7 and replacing script 6 with true risk-factor identification or removing it.
7. Define shared helpers in one file, such as `R/helpers.R`, for age normalisation, Yes/No recoding, writable output directories, CSV writing, and model tidying.
8. Add an execution smoke test that sources each script in a clean session using small mock data.
9. Keep a run log with package versions and generated output locations.

## Suggested intended execution order

Assuming the code is cleaned enough to run:

```r
source("Study4/1_Study_Harmonisation.Data_.Quality.Control_Age.Stratification.R")
source("Study4/2_.Handlign.of.complex.variables_df_handled.R.txt")
source("Study4/3__.Incidence.Rate.calculations.R.txt")
source("Study4/4_.Competing.risk.analysis.R.txt")
source("Study4/5_Survival.analysis.fromwark.R.txt")
source("Study4/7_Validation.FG.Model.Performance.R.txt")
source("Study4/8_Validation.COX.model.1.performance.R")
source("Study4/9_.Sensitivity.analyses_CC.R")
source("Study4/Multiple.Imputation.strategy.R.txt")
```

Script 6 is omitted from this suggested order because it duplicates script 7 rather than adding a distinct risk-factor identification step.

