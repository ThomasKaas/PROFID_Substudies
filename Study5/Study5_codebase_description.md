# Study 5 Codebase Description

This document describes the `Study5/` codebase in the `PROFID_Substudies` workspace. The folder contains a standalone R analysis pipeline for PROFID Study 5, focused on temporal trends and determinants of evidence-based heart failure therapy in post-myocardial infarction patients with HFrEF.

The code is not organised as an R package or an RStudio project. Instead, it is a sequence of script files, stored mostly as `.txt` files containing R code, with hard-coded paths under `T:/Study_5` and some fallback paths under `S:/AG/f-dhzc-profid/...`. The intended execution model is therefore sequential script execution in an R environment where these network drives are mounted and where the required packages and source data are available.

## High-Level Purpose

The Study 5 pipeline:

1. Loads a harmonised Study 4 / Study 5 source dataset.
2. Restricts the analysis cohort to HFrEF patients, defined as `LVEF < 40`.
3. Restricts the calendar window to 2000-2020.
4. Derives medication class indicators for RAAS inhibitor therapy, beta-blockers, and MRA.
5. Defines the main count endpoint `HF_n_classes` as the number of disease-modifying HFrEF medication classes received.
6. Defines the primary binary endpoint `HF_BIN_eq3`, indicating receipt of all 3 classes: RAAS inhibitor, beta-blocker, and MRA.
7. Produces descriptive baseline tables and observed temporal trends.
8. Fits unadjusted and adjusted logistic regression models for temporal trends and determinants.
9. Runs complete-case primary analysis, multiple-imputation sensitivity analysis, stratified analyses, and interaction tests.
10. Evaluates model performance, apparent calibration, AUC, and bootstrap optimism.
11. Runs post-hoc database variation and exploratory machine-learning variable-importance analyses.

## Directory Contents

`Study5/` is a flat directory with nine script files:

| File | Role |
|---|---|
| `Script1_.study.5_.build_cohort_and_end_points_ESC.R.txt` | Builds the HFrEF analysis dataset, derives calendar year and therapy endpoints, and saves `df_study5_hfref.rds`. |
| `Script2_study.5_.descriptives._.and._.trends_.Regression.logistic.model.univariate.R.txt` | Produces baseline descriptives, therapy uptake summaries over time, trend figures, and unadjusted yearly logistic trend models. |
| `Script3_.study5_.multivariable.models_determinants.R.txt` | Fits staged determinant models: complete-case M1/M2 and multiple-imputation M3/M4. |
| `Script4_.GMDT.models_performance.and.internal.validation.R.txt` | Evaluates model performance, calibration, MICE objects, and bootstrap AUC validation. The file contains an earlier version and a later updated version in the same file. |
| `Script5A_primary analysis (+ BH-FDR_ Correction)_Interactions_Stratified_.txt` | Primary complete-case analysis with BH-FDR correction, stratified analyses, predicted trends, interaction tests, and forest plots. |
| `Script5B_Sensitivity analyses` | Multiple-imputation sensitivity analysis corresponding to the primary complete-case model. |
| `Script6_Decision Curve Analysis _ Compare M2 vs M5` | Despite its filename, the script body is another robust multiple-imputation sensitivity workflow, not a decision-curve-analysis implementation. |
| `Script7_.Model.Development_.Steps.1__5.txt` | Model-development workflow: univariate screening, correlation filtering, candidate selection, backward elimination, and VIF checks. |
| `Script8_.PostHoc_.Exploratory.R.txt` | Post-hoc between-database variation, adjusted GEO trend models, and optional RF/XGBoost variable importance. |

## Data Lineage

The core data flow implemented by the scripts is:

```text
T:/Study_5/df_handled.rds
  or T:/Study_5/df_study5.rds
  -> Script 1
  -> T:/Study_5/Results_Study5/Script1_HFrEF_UPDATED/df_study5_hfref.rds
  -> Scripts 2-8
  -> descriptive tables, trend plots, logistic models, MICE objects,
     calibration outputs, validation summaries, stratified analyses,
     interaction tests, forest plots, and exploratory post-hoc outputs
```

Most downstream scripts assume the Script 1 output exists at:

```text
T:/Study_5/Results_Study5/Script1_HFrEF_UPDATED/df_study5_hfref.rds
```

Several scripts defensively re-derive variables such as `HF_BIN_eq3`, `Age_num`, `Age3`, `DB`, and binary covariates if they are missing. This makes the scripts more robust to upstream changes, but it also means the same derivation logic is repeated in multiple places.

## Core Clinical and Analysis Definitions

### Cohort

The target cohort is HFrEF-only:

```r
LVEF_num < 40
```

The primary analysis window is:

```r
Year_index >= 2000 & Year_index <= 2020
```

Script comments indicate that the final HFrEF dataset is expected to contain approximately:

```text
n = 30,830
p = 122
```

### Therapy Variables

Script 1 maps source variables flexibly using regex-based column discovery:

- `ACEI_ARB`: ACE inhibitor or ARB source field.
- `ARNI`: optional ARNI field, if available.
- `RAAS`: derived as ACEi/ARB or ARNI, depending on availability.
- `BB`: beta-blocker.
- `MRA`: mineralocorticoid receptor antagonist.
- `SGLT2`: audited only; expected absent or sparse in this data extract.
- `Diuretics`: descriptive only; not part of the disease-modifying therapy count.
- `LoopDiuretic_drug_specific`: optional descriptive field derived from drug-specific loop diuretic variables if present.

The main count is:

```r
HF_n_classes = RAAS + BB + MRA
```

It is clamped to the range 0-3.

### Endpoints

The pipeline defines two therapy count categories:

- `HF_GDMT_count4`: four-level count, `"0"`, `"1"`, `"2"`, `"3"`.
- `HF_GDMT_cat`: grouped category, `"0"`, `"1-2"`, `"3+"`.

The primary binary endpoint is:

```r
HF_BIN_eq3 = 1 if HF_n_classes == 3
HF_BIN_eq3 = 0 otherwise
```

This represents receipt of triple disease-modifying HFrEF therapy at baseline: RAAS inhibitor, beta-blocker, and MRA.

Script 4 also creates a sensitivity endpoint:

```r
HF_BIN_geq2 = 1 if HF_count_for_MI >= 2
```

## Script-by-Script Description

### Script 1: Build HFrEF Cohort and Endpoints

File:

```text
Script1_.study.5_.build_cohort_and_end_points_ESC.R.txt
```

Purpose:

- Starts from either `T:/Study_5/df_handled.rds` or `T:/Study_5/df_study5.rds`.
- Builds the Study 5 HFrEF analysis dataset.
- Applies calendar-year restriction to 2000-2020.
- Derives HFrEF restriction from LVEF.
- Creates therapy indicators and therapy-count endpoints.
- Saves audit outputs and the final HFrEF dataset.

Key packages:

- `dplyr`
- `readr`
- `stringr`
- `tibble`

Important helper logic:

- `pick_first_by_regex()` finds likely source columns by regex.
- `safe_get()` safely returns an all-`NA` vector if a mapped column is absent.
- `to_bin01()` converts logical, numeric, and common yes/no encodings to 0/1.
- `derive_year_index()` derives `Year_index` from explicit year fields or year-month fields.
- `make_period_bins()` bins years into:
  - `2000-2004`
  - `2005-2009`
  - `2010-2014`
  - `2015-2020`

Main outputs:

```text
T:/Study_5/Results_Study5/Script1_HFrEF_UPDATED/cohort_flow.csv
T:/Study_5/Results_Study5/Script1_HFrEF_UPDATED/year_audit.csv
T:/Study_5/Results_Study5/Script1_HFrEF_UPDATED/hf_endpoint_audit.csv
T:/Study_5/Results_Study5/Script1_HFrEF_UPDATED/hf_endpoint_distribution.csv
T:/Study_5/Results_Study5/Script1_HFrEF_UPDATED/hf_endpoint_distribution_count4.csv
T:/Study_5/Results_Study5/Script1_HFrEF_UPDATED/df_study5_hfref.rds
```

Notes:

- SGLT2 inhibitor variables are only audited and are not counted in the HFrEF therapy class count.
- Diuretics are reported descriptively and are not part of the disease-modifying class count.
- RAAS therapy is ACEi/ARB, or ACEi/ARB plus ARNI if ARNI exists and is non-missing.

### Script 2: Descriptives and Unadjusted Temporal Trends

File:

```text
Script2_study.5_.descriptives._.and._.trends_.Regression.logistic.model.univariate.R.txt
```

Purpose:

- Loads `df_study5_hfref.rds` from Script 1.
- Performs baseline descriptives overall and by `HF_GDMT_count4`.
- Summarises therapy uptake yearly and by period.
- Generates therapy trend figures.
- Fits unadjusted logistic trend models for each binary therapy outcome.

Key packages:

- `dplyr`
- `tidyr`
- `readr`
- `ggplot2`
- `broom`
- `forcats`
- `stringr`

Required variables:

- `Year_index`
- `Period_2000_2020`
- `LVEF_num`
- `DB`
- `RAAS`
- `BB`
- `MRA`
- `HF_n_classes`
- `HF_GDMT_cat`
- `HF_GDMT_count4`
- `Diuretics`

Candidate continuous descriptive variables include:

- `Age_num`
- `LVEF_num`
- `eGFR_num`
- `NTProBNP_log1p`
- `Haemoglobin_log1p`
- `Sodium_log1p`
- `Potassium_log1p`
- `Time_index_MI_CHD_num`
- `BMI_log1p`

Candidate categorical descriptive variables include:

- `Sex_BIN_Male`
- `Age_cat`
- `DB`
- `ICD_BIN_Yes`
- `Diabetes_BIN_Yes`
- `Hypertension_BIN_Yes`
- `Smoking_BIN_Yes`
- `AF_atrial_flutter_BIN_Yes`
- `Stroke_TIA_BIN_Yes`
- `PCI_BIN_Yes`
- `CABG_BIN_Yes`
- NYHA binary variables

Therapy outcomes used for trends:

- `RAAS`
- `BB`
- `MRA`
- `HF_BIN_eq3`
- `Diuretics`

Main outputs:

```text
T:/Study_5/Results_Study5/Script2_HFrEF/baseline_cont_overall.csv/.rds
T:/Study_5/Results_Study5/Script2_HFrEF/baseline_cont_by_HFcount4.csv/.rds
T:/Study_5/Results_Study5/Script2_HFrEF/baseline_cat_overall.csv/.rds
T:/Study_5/Results_Study5/Script2_HFrEF/baseline_cat_by_HFcount4.csv/.rds
T:/Study_5/Results_Study5/Script2_HFrEF/yearly_therapy_props.csv/.rds
T:/Study_5/Results_Study5/Script2_HFrEF/period_therapy_props.csv/.rds
T:/Study_5/Results_Study5/Script2_HFrEF/Fig1_therapy_trends_faceted.png
T:/Study_5/Results_Study5/Script2_HFrEF/Fig1_therapy_trends_combined.png
T:/Study_5/Results_Study5/Script2_HFrEF/trend_models_unadjusted.csv/.rds
```

The unadjusted trend models are logistic regressions of each therapy outcome on `Year_index`. The script reports odds ratios per 1-year increase and per 5-year increase.

### Script 3: Multivariable Determinants Models

File:

```text
Script3_.study5_.multivariable.models_determinants.R.txt
```

Purpose:

- Loads the HFrEF dataset from Script 1.
- Enforces the 2000-2020 window.
- Derives `HF_BIN_eq3` if missing.
- Fits staged logistic regression models for determinants of triple HFrEF therapy.

Key packages:

- `dplyr`
- `tibble`
- `readr`
- `broom`
- `purrr`
- `mice`

Model structure:

| Model | Analysis type | Predictors |
|---|---|---|
| `M1_temporal` | Complete case | `Year_index` |
| `M2_temporal_demo` | Complete case | `Year_index`, `Age_num`, `Sex_BIN_Male`, `DB` |
| `M3_temporal_demo_clinical` | Multiple imputation | Temporal + demographics + clinical predictors |
| `M4_full_extended` | Multiple imputation | Temporal + demographics + clinical + labs + procedures |

Clinical predictors:

- `LVEF_num`
- `ICD_BIN_Yes`
- `Baseline_within40d`
- `Time_index_MI_CHD_log1p`
- `Diabetes_BIN_Yes`
- `Hypertension_BIN_Yes`
- `Smoking_BIN_Yes`
- `AF_atrial_flutter_BIN_Yes`
- `Stroke_TIA_BIN_Yes`

Lab predictors:

- `eGFR_log1p`
- `NTProBNP_log1p`
- `Haemoglobin_log1p`
- `Sodium_log1p`
- `Potassium_log1p`

Procedure predictors:

- `PCI_BIN_Yes`
- `CABG_BIN_Yes`
- `Revascularisation_acute_BIN_Yes`

Important handling:

- `Baseline_within40d` is dropped if constant.
- Lab variables with at least 80% missingness are excluded.
- Complete-case models drop factor predictors with fewer than two levels.
- MI uses `mice`, with 20 imputations and 20 iterations.
- Outcome is not imputed.
- `DB` is imputed using `polyreg` when present.

Main outputs:

```text
T:/Study_5/Results_Study5/Script3_Determinants_HFrEF/determinants_CC_models.csv/.rds
T:/Study_5/Results_Study5/Script3_Determinants_HFrEF/mice_traceplots.pdf
T:/Study_5/Results_Study5/Script3_Determinants_HFrEF/determinants_MI_models.csv/.rds
T:/Study_5/Results_Study5/Script3_Determinants_HFrEF/determinants_ALL_models_CC_plus_MI.csv/.rds
```

### Script 4: Model Performance, Internal Validation, and Calibration

File:

```text
Script4_.GMDT.models_performance.and.internal.validation.R.txt
```

Purpose:

- Evaluates performance of the determinant models.
- Computes apparent discrimination and calibration.
- Runs MICE for MI model performance.
- Performs bootstrap optimism correction for AUC.
- Produces calibration plots.

Key packages:

- `dplyr`
- `tidyr`
- `purrr`
- `tibble`
- `mice`
- `pROC`
- `ggplot2`
- `ResourceSelection`

Important implementation detail:

The file contains two full versions of the workflow. The second starts around the "Study 5 - Script 4 (UPDATED, ENGLISH)" block and adds:

- `HF_count_for_MI`
- `HF_BIN_geq2`
- passive imputation logic for `HF_BIN_geq2`
- updated output list

If this file is sourced top-to-bottom, the first version runs and then the updated version runs again, writing many of the same output names. In practice, the latter version appears to be the intended current implementation.

Performance metrics:

- AUC with confidence interval via `pROC`
- Calibration intercept
- Calibration slope
- Hosmer-Lemeshow p-value
- AIC
- BIC

Validation:

- Bootstrap validation of AUC for M3 and M4.
- Uses `B = 1000`.
- Runs on the first completed imputed dataset.
- Saves checkpoint files every 50 bootstrap samples.

Main outputs:

```text
T:/Study_5/Results_Study5/Script4_Determinants_Performance/imp_study5_mice_script4.rds
T:/Study_5/Results_Study5/Script4_Determinants_Performance/study5_MI_traceplots_script4.pdf
T:/Study_5/Results_Study5/Script4_Determinants_Performance/study5_model_performance_summary.csv/.rds
T:/Study_5/Results_Study5/Script4_Determinants_Performance/study5_bootstrap_auc_validation.csv/.rds
T:/Study_5/Results_Study5/Script4_Determinants_Performance/calibration_M2.png
T:/Study_5/Results_Study5/Script4_Determinants_Performance/calibration_M3.png
T:/Study_5/Results_Study5/Script4_Determinants_Performance/calibration_M4.png
```

### Script 5A: Primary Complete-Case Analysis

File:

```text
Script5A_primary analysis (+ BH-FDR_ Correction)_Interactions_Stratified_.txt
```

Purpose:

- Runs the primary complete-case analysis for `HF_BIN_eq3`.
- Applies BH-FDR correction to main covariates, stratified trend tests, and interaction tests.
- Produces stratified descriptive and adjusted yearly trend estimates.
- Produces predicted temporal trends by age group and database.
- Produces interaction joint tests.
- Produces determinant forest plots.

Key packages:

- `dplyr`
- `tidyr`
- `tibble`
- `readr`
- `stringr`
- `ggplot2`
- `broom`
- optional `brglm2`
- optional `logistf`

Configuration:

```r
YEAR_MIN <- 2000L
YEAR_MAX <- 2020L
OUTCOME <- "HF_BIN_eq3"
TOP_DB_FOR_MODEL <- 8
TOP_DB_FOR_PLOTS <- 6
MIN_N_STRAT <- 200
MIN_EVENTS_STRAT <- 30
DO_INTERACTION_ICD <- FALSE
DO_FDR_MAIN_MODEL <- TRUE
DO_FDR_STRAT <- TRUE
DO_FDR_INT <- TRUE
```

Primary model covariates:

- `Year_index`
- `Age3`
- `Sex_BIN_Male`
- `DB`
- `ICD_BIN_Yes`
- `Time_index_MI_CHD_log1p`
- `Diabetes_BIN_Yes`
- `Hypertension_BIN_Yes`
- `Smoking_BIN_Yes`
- `AF_atrial_flutter_BIN_Yes`
- `Stroke_TIA_BIN_Yes`
- `eGFR_log1p`
- `Haemoglobin_log1p`
- `PCI_BIN_Yes`
- `CABG_BIN_Yes`
- `Revascularisation_acute_BIN_Yes`

Important handling:

- Defensively re-restricts to HFrEF and 2000-2020.
- Derives `HF_BIN_eq3` if missing.
- Collapses `DB` to top databases plus `OTHER`.
- Further collapses sparse DB levels by minimum events for model stability.
- Creates `time_period` from a median split of `Year_index`.
- Creates `Age3` if needed.
- Drops predictors with only one usable level.
- Saves `PRIMARY_CC_fit_and_data.rds` for downstream use.

Stratified analyses:

Stratification variables are drawn from:

- `ICD_BIN_Yes`
- `Age3`
- `time_period`
- `eGFR_cat`
- `DB_plot`

Within each stratum, the yearly effect is fit using:

1. Standard `glm`.
2. `brglm2` if the GLM is unstable.
3. `logistf` if GLM and `brglm2` fail.

Main output folders and files:

```text
T:/Study_5/Results_Study5/Script5A_Primary_CC_2000_2020_ROBUST/QC_alias_map.csv
T:/Study_5/Results_Study5/Script5A_Primary_CC_2000_2020_ROBUST/QC_Covariate_Audit_before_CC.csv
T:/Study_5/Results_Study5/Script5A_Primary_CC_2000_2020_ROBUST/QC_CC_counts.csv
T:/Study_5/Results_Study5/Script5A_Primary_CC_2000_2020_ROBUST/PRIMARY_CC_fit_and_data.rds
T:/Study_5/Results_Study5/Script5A_Primary_CC_2000_2020_ROBUST/Models_CC/PRIMARY_CC_model_HF_BIN_eq3.rds
T:/Study_5/Results_Study5/Script5A_Primary_CC_2000_2020_ROBUST/Models_CC/PRIMARY_CC_OR_HF_BIN_eq3.csv
T:/Study_5/Results_Study5/Script5A_Primary_CC_2000_2020_ROBUST/Models_CC/PRIMARY_CC_OR_HF_BIN_eq3_withFDR.csv
T:/Study_5/Results_Study5/Script5A_Primary_CC_2000_2020_ROBUST/Stratified_CC/*
T:/Study_5/Results_Study5/Script5A_Primary_CC_2000_2020_ROBUST/PredTrends_CC/*
T:/Study_5/Results_Study5/Script5A_Primary_CC_2000_2020_ROBUST/InteractionJointTests_CC/*
T:/Study_5/Results_Study5/Script5A_Primary_CC_2000_2020_ROBUST/ForestPlot_CC/*
```

Code-quality note:

After the main "DONE" log line, the file contains extra exploratory code that reads a placeholder path:

```r
readr::read_csv(".../STRAT_OR_year_ALL_HF_BIN_eq3_ROBUST_withFDR.csv")
```

If the script is sourced as-is, this placeholder will likely fail unless it is manually edited or skipped.

### Script 5B: Multiple-Imputation Sensitivity Analysis

File:

```text
Script5B_Sensitivity analyses
```

Purpose:

- Refit the primary multivariable logistic regression using MICE.
- Report pooled adjusted odds ratios and confidence intervals.
- Run interaction joint tests using `mice::D1`.
- Produce predicted temporal trends by age group using averaged predictions across imputations.

Key packages:

- `dplyr`
- `tidyr`
- `tibble`
- `readr`
- `stringr`
- `ggplot2`
- `broom`
- `mice`

Configuration:

```r
M_IMP <- 20
MAXIT <- 20
SEED <- 20260214
TOP_DB_FOR_MODEL <- 8
MIN_N_DB_KEEP <- 200
MIN_EVENTS_DB_KEEP <- 30
YEAR_PLOT_MIN_N <- 500
```

Model covariates mirror Script 5A:

- `Year_index`
- `Age3`
- `Sex_BIN_Male`
- `DB`
- `ICD_BIN_Yes`
- `Time_index_MI_CHD_log1p`
- `Diabetes_BIN_Yes`
- `Hypertension_BIN_Yes`
- `Smoking_BIN_Yes`
- `AF_atrial_flutter_BIN_Yes`
- `Stroke_TIA_BIN_Yes`
- `eGFR_log1p`
- `Haemoglobin_log1p`
- `PCI_BIN_Yes`
- `CABG_BIN_Yes`
- `Revascularisation_acute_BIN_Yes`

Main outputs:

```text
T:/Study_5/Results_Study5/Script5B_Sensitivity_MI_2000_2020/MI_object_mice.rds
T:/Study_5/Results_Study5/Script5B_Sensitivity_MI_2000_2020/MI_PRIMARY_pooled_OR_HF_BIN_eq3.csv
T:/Study_5/Results_Study5/Script5B_Sensitivity_MI_2000_2020/MI_PRIMARY_pooled_OR_HF_BIN_eq3_withFDR.csv
T:/Study_5/Results_Study5/Script5B_Sensitivity_MI_2000_2020/MI_InteractionJointTests_D1.csv
T:/Study_5/Results_Study5/Script5B_Sensitivity_MI_2000_2020/PredTrends_MI/*
```

### Script 6: Robust MI Sensitivity Workflow Misnamed as DCA

File:

```text
Script6_Decision Curve Analysis _ Compare M2 vs M5
```

Purpose according to filename:

- Decision curve analysis comparing M2 vs M5.

Actual purpose in script body:

- Robust multiple-imputation sensitivity analysis for `HF_BIN_eq3`.
- QC missingness for MI variables.
- MICE method audit.
- Pooled MI odds-ratio model.
- MI interaction tests.
- Age-group predicted trends.

The script does not call common decision curve packages or functions such as `rmda`, `dcurves`, `decision_curve`, or net-benefit calculations. It appears to be a revised or duplicated version of Script 5B with stronger alias standardisation and safer CSV writing.

Key packages:

- `dplyr`
- `tidyr`
- `tibble`
- `readr`
- `stringr`
- `ggplot2`
- `mice`

Notable implementation details:

- Standardises many variables from aliases using `.standardise_from_alias()`.
- Derives `Age3` if missing.
- Re-derives `HF_BIN_eq3` from medication indicators or count variables if needed.
- Collapses DB to the top 8 levels plus `OTHER`.
- Writes CSV through `safe_write_csv()`, which avoids overwriting locked files by writing a timestamped fallback.
- Uses MICE methods based on variable type: `pmm`, `logreg`, or `polyreg`.
- Runs two versions of MI interaction testing in the same script, with the later block overwriting the earlier output.

Main outputs:

```text
T:/Study_5/Results_Study5/Script5B_Sensitivity_MI_2000_2020_ROBUST/QC_missingness_MIvars.csv
T:/Study_5/Results_Study5/Script5B_Sensitivity_MI_2000_2020_ROBUST/QC_mice_methods.csv
T:/Study_5/Results_Study5/Script5B_Sensitivity_MI_2000_2020_ROBUST/MI_object_mice.rds
T:/Study_5/Results_Study5/Script5B_Sensitivity_MI_2000_2020_ROBUST/MI_pooled_OR_HF_BIN_eq3.csv
T:/Study_5/Results_Study5/Script5B_Sensitivity_MI_2000_2020_ROBUST/MI_pooled_OR_HF_BIN_eq3_withFDR.csv
T:/Study_5/Results_Study5/Script5B_Sensitivity_MI_2000_2020_ROBUST/InteractionJointTests_MI/MI_joint_tests_HF_BIN_eq3.csv
T:/Study_5/Results_Study5/Script5B_Sensitivity_MI_2000_2020_ROBUST/PredTrends_MI/pred_trends_Age3_HF_BIN_eq3_MI.csv
T:/Study_5/Results_Study5/Script5B_Sensitivity_MI_2000_2020_ROBUST/PredTrends_MI/pred_trends_Age3_HF_BIN_eq3_MI.png
T:/Study_5/Results_Study5/Script5B_Sensitivity_MI_2000_2020_ROBUST/PredTrends_MI/pred_trends_Age3_HF_BIN_eq3_MI.pdf
```

Code-quality note:

Near the plotting block, there is debug/fix code inserted inside the `ggplot` chain after `guides(fill = "none") +`. This may make the script syntactically invalid or at least fragile if run as-is. This file should be reviewed before execution.

### Script 7: Model Development Steps 1-5

File:

```text
Script7_.Model.Development_.Steps.1__5.txt
```

Purpose:

- Implements a formal model-development workflow for determinants of `HF_BIN_eq3`.
- Uses univariate screening, correlation filtering, backward elimination, and VIF diagnostics.

Key packages:

- `dplyr`
- `tibble`
- `readr`
- `broom`
- `purrr`
- optional `car`

Workflow:

1. Univariate screening using logistic regression, retaining variables with `p < 0.10`.
2. Forced inclusion of structural variables:
   - `Year_index`
   - `Age_num`
   - `Sex_BIN_Male`
   - `DB`
3. Numeric correlation filtering for candidate predictors with `|r| > 0.70`.
4. For correlated pairs, drop the variable with higher missingness.
5. Backward elimination from the complete-case multivariable model, retaining variables with `p <= 0.05`.
6. Forced variables are never removed.
7. Final model is saved and VIF is computed.

Candidate variable blocks align with Scripts 3 and 4:

- temporal
- demographic
- clinical
- lab
- procedure

Main outputs:

```text
T:/Study_5/Results_Study5/Script7_ModelDevelopment_HFrEF/01_univariate_OR.csv
T:/Study_5/Results_Study5/Script7_ModelDevelopment_HFrEF/02_corr_matrix_numeric.csv
T:/Study_5/Results_Study5/Script7_ModelDevelopment_HFrEF/02_corr_pairs_over_0p70.csv
T:/Study_5/Results_Study5/Script7_ModelDevelopment_HFrEF/03_candidates_after_screening.csv
T:/Study_5/Results_Study5/Script7_ModelDevelopment_HFrEF/03_candidates_after_corr_filter.csv
T:/Study_5/Results_Study5/Script7_ModelDevelopment_HFrEF/04_selection_path.csv
T:/Study_5/Results_Study5/Script7_ModelDevelopment_HFrEF/final_model.rds
T:/Study_5/Results_Study5/Script7_ModelDevelopment_HFrEF/05_final_model_OR.csv
T:/Study_5/Results_Study5/Script7_ModelDevelopment_HFrEF/05_final_model_VIF.csv
```

### Script 8: Post-Hoc Database Variation and GEO Trend Models

File:

```text
Script8_.PostHoc_.Exploratory.R.txt
```

Purpose:

- Examines variation in therapy receipt between databases.
- Fits adjusted trend models with nonlinear calendar-year effects.
- Produces optional machine-learning variable importance.

Key packages:

- `dplyr`
- `tidyr`
- `readr`
- `ggplot2`
- `broom`
- `splines`
- `forcats`
- `tibble`
- optional `ranger`
- optional `xgboost`

Inputs:

The script searches several possible input locations, preferring:

```text
T:/Study_5/Results_Study5/Script1_HFrEF_UPDATED/df_study5_hfref.rds
```

It falls back to:

```text
T:/Study_5/df_study5_hfref.rds
T:/Study_5/df_study5.rds
S:/AG/f-dhzc-profid/Data Transfer to Charite/df_study5.rds
```

Outcomes analysed when present:

- `HF_BIN_eq3`
- `RAAS`
- `BB`
- `MRA`
- `Diuretics`

Observed DB variation:

- Computes per-database event rates.
- Uses Wilson confidence intervals.
- Requires at least 50 rows per DB for observed-rate tables.

GEO trend model:

The model form is:

```r
outcome ~ splines::ns(Year_index, df = 4) + DB + optional covariates
```

Optional covariates:

- `Age_num`
- `Sex_BIN_Male`
- `eGFR_log1p`

Separation control:

- Drops DBs with too few events or nonevents.
- Uses stricter thresholds for `HF_BIN_eq3` and `MRA`.

Machine-learning variable importance:

- Runs random forest permutation importance if `ranger` is installed.
- Runs XGBoost gain importance if `xgboost` is installed.
- The ML workflow is run only for `HF_BIN_eq3`.

Main outputs:

```text
T:/Study_5/Results_Study5/Script8_DB_variation_GEO/AUDIT_basic.csv
T:/Study_5/Results_Study5/Script8_DB_variation_GEO/DB_observed_rates_*.csv
T:/Study_5/Results_Study5/Script8_DB_variation_GEO/DB_observed_rates_*.png
T:/Study_5/Results_Study5/Script8_DB_variation_GEO/GEO_DB_outcome_counts_*.csv
T:/Study_5/Results_Study5/Script8_DB_variation_GEO/GEO_DB_dropped_*.csv
T:/Study_5/Results_Study5/Script8_DB_variation_GEO/GEO_model_OR_*.csv
T:/Study_5/Results_Study5/Script8_DB_variation_GEO/GEO_DB_OR_forest_*.png
T:/Study_5/Results_Study5/Script8_DB_variation_GEO/GEO_pred_trends_overall_*.csv
T:/Study_5/Results_Study5/Script8_DB_variation_GEO/GEO_pred_trends_overall_*.png
T:/Study_5/Results_Study5/Script8_DB_variation_GEO/GEO_model_*.rds
T:/Study_5/Results_Study5/Script8_DB_variation_GEO/ML_RF_varimp_HF_BIN_eq3.csv/.png
T:/Study_5/Results_Study5/Script8_DB_variation_GEO/ML_XGB_gain_HF_BIN_eq3.csv/.png
```

## Package Dependencies

Across the codebase, the main R dependencies are:

- `dplyr`
- `tidyr`
- `readr`
- `stringr`
- `tibble`
- `ggplot2`
- `broom`
- `purrr`
- `forcats`
- `mice`
- `pROC`
- `ResourceSelection`
- `splines`

Optional or conditional dependencies:

- `brglm2`
- `logistf`
- `car`
- `ranger`
- `xgboost`

The scripts do not contain dependency installation logic. The environment must provide the needed packages.

## Output Structure

The scripts write to subdirectories under:

```text
T:/Study_5/Results_Study5/
```

Major output subdirectories:

```text
Script1_HFrEF_UPDATED
Script2_HFrEF
Script3_Determinants_HFrEF
Script4_Determinants_Performance
Script5A_Primary_CC_2000_2020_ROBUST
Script5B_Sensitivity_MI_2000_2020
Script5B_Sensitivity_MI_2000_2020_ROBUST
Script7_ModelDevelopment_HFrEF
Script8_DB_variation_GEO
```

There is no local output folder inside `Study5/` itself. All analysis products are directed to the hard-coded `T:/Study_5/Results_Study5` tree.

## Main Statistical Workflow

The intended inferential workflow is:

1. Use Script 1 to create the HFrEF analysis dataset.
2. Use Script 2 for descriptive statistics and unadjusted trends.
3. Use Script 3 for staged determinant models.
4. Use Script 4 to evaluate model performance and calibration.
5. Use Script 5A as the primary complete-case analysis.
6. Use Script 5B or Script 6 as the multiple-imputation sensitivity analysis.
7. Use Script 7 for model-development documentation and candidate-selection support.
8. Use Script 8 for post-hoc database variation and exploratory analyses.

The primary model in Script 5A is the clearest final-analysis model. Script 3 is more of a staged determinant-model workflow, while Script 7 is model-development support rather than the main final model.

## Key Implementation Observations

### Strengths

- The pipeline has explicit cohort and endpoint audit outputs.
- Script 1 uses flexible source-column matching, making it robust to slightly different input schemas.
- Most downstream scripts defensively re-check the HFrEF and 2000-2020 restrictions.
- The primary endpoint `HF_BIN_eq3` is consistently defined as triple therapy.
- Complete-case and MI analyses are separated.
- Sparse strata and unstable models are handled explicitly in Script 5A.
- BH-FDR correction is applied to main, stratified, and interaction p-values where configured.
- Script 8 includes sensible database-level separation controls before adjusted DB models.

### Risks and Inconsistencies

- All scripts depend on hard-coded Windows/network paths. They are not portable without editing `ROOT_DIR`, `BASE_DIR`, or related path constants.
- Most R scripts are stored as `.txt` files or extensionless files, which can make automated execution and editor tooling less convenient.
- Script 4 contains two complete workflow versions in one file; running the full file will execute both.
- Script 6 is misnamed as decision curve analysis but does not implement decision curve or net-benefit methods.
- Script 6 contains duplicated interaction-test logic and a likely malformed plotting block with debug code inserted inside a `ggplot` expression.
- Script 5A contains post-completion exploratory code with a placeholder path that may fail if the entire script is sourced.
- Several derivations are repeated across scripts, including `HF_BIN_eq3`, `Age3`, binary conversion, DB collapsing, and predictor lists.
- There is no central configuration file for paths, year range, model covariates, imputation settings, or output directories.
- There is no automated test harness or reproducibility wrapper.
- Script execution order is implied by filenames and comments but not enforced programmatically.

## Recommended Cleanups

1. Rename script files to valid `.R` filenames and remove spaces/special characters where possible.
2. Split Script 4 into one current version, archiving the older version separately.
3. Rename Script 6 or replace it with a true DCA script if decision curve analysis is intended.
4. Remove or guard placeholder/debug code in Script 5A and Script 6.
5. Create a shared `config.R` for:
   - root directories
   - year window
   - outcome names
   - covariate lists
   - MICE settings
   - DB collapsing thresholds
6. Create shared helper functions for:
   - binary conversion
   - alias standardisation
   - `Age3` derivation
   - `HF_BIN_eq3` derivation
   - DB collapsing
   - safe CSV writing
7. Add a top-level driver script that executes the pipeline in the intended order.
8. Add lightweight validation checks after each script, especially:
   - row counts
   - year range
   - HFrEF restriction
   - endpoint distribution
   - expected output files
9. Save session/package versions for reproducibility.

## Practical Execution Notes

To run the pipeline, the analyst needs:

- Access to `T:/Study_5`.
- Access to any fallback `S:/...` data paths if primary files are absent.
- Required R packages installed.
- Write access to `T:/Study_5/Results_Study5`.
- Awareness that some scripts may need manual cleanup before fully sourcing:
  - Script 4, because it contains duplicated workflow versions.
  - Script 5A, because of placeholder post-completion code.
  - Script 6, because of likely malformed plotting/debug code and misaligned filename.

The safest practical workflow is to run Script 1 first, confirm `df_study5_hfref.rds`, then run the downstream scripts one by one while checking each output directory.
