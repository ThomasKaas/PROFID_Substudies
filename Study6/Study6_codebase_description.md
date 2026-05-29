# Study6 Codebase Description

Static analysis date: 2026-05-29

This document describes the `Study6/` analysis codebase in the PROFID substudies workspace. The code is primarily an R-based statistical analysis pipeline for studying the association between BMI and sudden cardiac death (SCD) risk, using multiple imputation, descriptive summaries, Kaplan-Meier analyses, cause-specific Cox models, and several sensitivity analyses.

## Executive Summary

`Study6/` contains a complete analysis workflow around BMI and SCD risk:

1. Build an analysis cohort by excluding records with missing BMI, missing event status, or missing survival time.
2. Generate multiply imputed datasets using `mice`, with BMI and outcomes treated as non-imputed variables and lipid variables imputed with predictive mean matching.
3. Produce descriptive tables and Kaplan-Meier curves by BMI category.
4. Fit a baseline cause-specific Cox model with BMI modeled using natural splines.
5. Extend the model with lipids, stroke/TIA, ICD status, and in some older or sensitivity code, cancer and COPD.
6. Evaluate discrimination, AIC, calibration, proportional hazards assumptions, complete-case behavior, alternative BMI functional forms, time-varying coefficient sensitivity, subgroup interactions, and competing-risk Fine-Gray models.

The directory contains 18 R scripts and many generated artifacts:

- 18 `.R` scripts
- 72 `.csv` outputs
- 45 `.pdf` outputs
- 33 `.png` outputs
- 3 `.svg` outputs
- 4 `.RDS` objects currently present under `ExtendedModel/`

The code appears to be research-analysis code rather than a packaged, directly reproducible software project. There is no central `renv.lock`, `DESCRIPTION`, Makefile, or orchestrating script. Most scripts rely on hard-coded Windows/network paths and assume that derived files such as `mice_imputed_data.RDS`, `mice_imputed_data_extended.RDS`, and `combined_BMI_outcomefiltered.csv` are available in the current working directory.

## Directory Layout

```text
Study6/
  baseline_model.R
  BaseModel/
    baseline_model.R
    model output CSV/PDF files
  Imputation/
    MICE.R
    imputation_reporting.R
    imputation diagnostics and missingness outputs
  DescriptiveAnalysis/
    descriptive_analysis.R
    descriptive_categorical.R
    kaplan-meier.R
    descriptive/KM outputs
    ImputedData/
      duplicate imputed descriptive scripts and outputs
  ExtendedModel/
    extended_model.R
    completecase_eval.R
    proportional_hazards.R
    prop_hazards_90days.R
    TVCmodels.R
    FPmodels_sensitivity_analysis.R
    splines_extended_sensitivity_analysis.R
    finegrey_sensitivity.R
    plotfinegrey.R
    subgroup_analysis.R
    extended model outputs and selected RDS objects
```

The root-level `Study6/baseline_model.R` and `Study6/BaseModel/baseline_model.R` are non-identical versions of the baseline-model script. The `BaseModel/` version appears newer for the 90-month horizon workflow because it explicitly creates horizon-censored outcome variables and reads the extended imputation object for model comparison.

`Study6/ExtendedModel/MICE.R` is also a modified copy of `Study6/Imputation/MICE.R`, but it contains a syntax error (`make.predictorMatrix(imp_data)s`) and excludes or comments some variables differently. The `Imputation/MICE.R` version is the cleaner source for the main imputation step.

## External Inputs

The scripts depend on several external files outside the repository:

- `S:/AG/f-dhzc-profid/Data Transfer to Charite/combined_icd.csv`
- `S:/AG/f-dhzc-profid/Data Transfer to Charite/combined_dataset.csv`
- `S:/AG/f-dhzc-profid/Data Transfer to Charite/ICD.csv`
- `S:/AG/f-dhzc-profid/Data Transfer to Charite/NonICD_preserved.csv`
- `S:/AG/f-dhzc-profid/Data Transfer to Charite/NonICD_reduced.csv`

Several scripts set the working directory to:

- `T:/Dokumente/PROFID/Study6`
- `//charite.de/homes/h02/clco10/Dokumente/PROFID/Study6`

This means the scripts will not run unchanged on another machine unless those drives, UNC paths, and derived files exist. The repository currently stores many outputs inside subdirectories, but the R scripts generally write to the root Study6 working directory because of the hard-coded `setwd()`.

## Main R Dependencies

The code uses:

- `survival`: Cox models, `Surv()`, `survfit()`, `cox.zph()`, concordance, base hazards
- `survminer`: Kaplan-Meier plotting and survival summaries
- `dplyr`, `tidyr`, `purrr`: data manipulation
- `mice`: multiple imputation and pooling
- `rms`: restricted cubic spline support and subgroup modeling
- `splines`: natural spline basis for BMI
- `broom`: tidy model outputs
- `ggplot2`, `patchwork`: plotting and diagnostic panels
- `cmprsk`: Fine-Gray competing-risk models
- `gtsummary`: Table 1 generation
- `lubridate`: loaded in descriptive scripts, though not central to the observed workflow

Many scripts include `install.packages()` calls at the top. For reproducible execution, these should usually be removed from analysis scripts and replaced with a documented dependency setup step.

## End-to-End Data Flow

```text
Raw cohort files
  |
  |-- Imputation/MICE.R
  |     -> combined_BMI_outcomefiltered.csv
  |     -> mice_imputed_data.RDS
  |     -> imputed_data_1_for_plots.csv
  |
  |-- Imputation/imputation_reporting.R
  |     -> missingness and observed-vs-imputed diagnostics
  |
  |-- DescriptiveAnalysis/*.R
  |     -> Table 1, continuous/categorical summaries, KM curves
  |
  |-- ExtendedModel/extended_model.R
  |     reads mice_imputed_data.RDS + combined_BMI_outcomefiltered.csv
  |     -> mice_imputed_data_extended.RDS
  |     -> fit_list_cs1_extended.RDS
  |     -> extended Cox outputs
  |
  |-- BaseModel/baseline_model.R
  |     reads mice_imputed_data.RDS and mice_imputed_data_extended.RDS
  |     -> baseline Cox outputs
  |     -> baseline-vs-extended performance comparisons
  |
  |-- ExtendedModel/sensitivity scripts
        -> PH diagnostics, complete-case analysis, FP/spline checks,
           TVC checks, Fine-Gray outputs, subgroup interaction outputs
```

## Cohort and Outcome Definitions

The cohort construction in `Imputation/MICE.R` starts from `combined_icd.csv` and filters out observations with:

- missing or non-numeric `BMI`
- missing or non-numeric `Status`
- missing `Survival_time`

This cleaned dataset is written as `combined_BMI_outcomefiltered.csv`.

The status coding used throughout the modeling code is:

- `Status == 1`: SCD / event of interest
- `Status == 0`: censored / no event
- `Status == 2`: competing or other death, treated as non-event for cause-specific Cox models

Most current model scripts use a 90-month horizon:

```r
Survival_time_h = pmin(Survival_time, 90)
Status_cs1_h = ifelse(Survival_time <= 90 & Status == 1, 1L, 0L)
```

The baseline comparison script also evaluates 60-, 90-, and 120-month horizons.

## BMI Categories

The descriptive and KM scripts use these BMI categories:

- Underweight: `<18.5`
- Normal: `18.5 to <25`
- Overweight: `25 to <30`
- Obese I: `30 to <35`
- Obese II: `35 to <40`
- Obese III: `>=40`

The generated Table 1 reports these observed/imputed-first-dataset category sizes:

- Underweight: 1,560
- Normal: 39,692
- Overweight: 52,099
- Obese I: 20,909
- Obese II: 5,401
- Obese III: 1,820
- Total: 121,481

## Imputation Module

### `Imputation/MICE.R`

This is the main imputation script.

Key behavior:

- Loads `combined_icd.csv`.
- Filters to records with available BMI, status, and survival time.
- Writes `combined_BMI_outcomefiltered.csv`.
- Selects variables for imputation:
  - outcome: `Survival_time`, `Status`
  - exposure: `BMI`
  - base confounders: age, sex, diabetes, hypertension, smoking, MI history, LVEF, eGFR, haemoglobin, medication/revascularisation variables
  - auxiliary/extended variables: cholesterol, LDL, HDL, triglycerides, stroke/TIA, baseline type, CVD risk region, MI type
- Converts categorical variables to factors when present.
- Builds a `mice` predictor matrix.
- Prevents imputation of `Survival_time`, `Status`, and `BMI`, while allowing BMI to be used as a predictor.
- Uses predictive mean matching (`pmm`) for lipid variables.
- Restricts lipid predictors to a clinical base set to avoid unstable lipid cross-prediction.
- Runs `mice(..., m = 20, maxit = 20, pmm.k = 10)`.
- Saves:
  - `mice_imputed_data.RDS`
  - `imputed_data_1_for_plots.csv`

Important implementation detail: the script excludes BMI missingness by filtering before imputation. BMI is therefore an observed exposure, not imputed.

### `Imputation/imputation_reporting.R`

This script produces imputation diagnostics from `mice_imputed_data.RDS`.

Outputs include:

- `mice_pre_post_continuous_mean_sd.csv`
- `mice_pre_post_categorical_proportions.csv`
- `plot_missingness_numeric.png`
- `plot_pre_post_means.png`
- `plot_pre_post_sds.png`
- `density_pre_post_*.png`
- `prop_pre_post_*.png`
- `Figure_SX_imputation_diagnostics.png`
- `Figure_SX_imputation_diagnostics.pdf`

The generated imputation summaries show the largest missingness among modeled continuous variables in:

- Triglycerides: 29.61%
- LDL: 28.47%
- HDL: 26.56%
- Cholesterol: 24.99%
- Haemoglobin: 10.87%
- eGFR: 5.17%
- LVEF: 0.01%

Post-imputation means and SDs are close to pre-imputation observed summaries for most variables, suggesting the imputation diagnostics were used to check distributional stability.

## Descriptive Analysis Module

### `DescriptiveAnalysis/descriptive_analysis.R`

This script produces continuous summaries and Table 1 style baseline characteristics.

Key behavior:

- Reads `mice_imputed_data.RDS`.
- Uses the first completed imputed dataset (`mice::complete(imp, action = 1)`).
- Reads full/raw datasets for supplementary checks.
- Creates BMI categories.
- Separates continuous and categorical variables.
- Writes:
  - `comorbidity_value_counts.csv`
  - `summary_continuous.csv`
  - `continuous_descriptors_imputed.csv`
  - `Table1_baseline_characteristics.csv`

Generated continuous median/IQR examples from `summary_continuous.csv`:

- Survival time: median 48.32, IQR 60.35
- BMI: median 26.60, IQR 5.53
- Age: median 69, IQR 17
- LVEF: median 55, IQR 15
- eGFR: median 77.98, IQR 30.55
- Haemoglobin: median 14.0, IQR 2.2

The Table 1 output reports SCD in 2,865 of 121,481 participants (2.4%) in the first imputed dataset.

### `DescriptiveAnalysis/descriptive_categorical.R`

This script creates categorical summaries across BMI categories.

Key behavior:

- Reads raw `ICD`, `NonICD_preserved`, `NonICD_reduced`, and `combined_dataset` files.
- Creates BMI categories.
- Moves selected numeric-coded columns into the categorical set.
- Computes counts and percentages by BMI category.
- Runs chi-square tests by variable and adjusts p-values using FDR.
- Writes `final_categorical_summary.csv`.

### `DescriptiveAnalysis/kaplan-meier.R`

This script runs Kaplan-Meier analyses by BMI category for multiple horizons.

Key behavior:

- Reads `combined_dataset.csv`.
- Defines `run_km_at_horizon(df, horizon_months)`.
- Censors follow-up at 60, 90, and 120 months.
- Defines the event as `Status == 1` within the horizon.
- Fits `survfit(Surv(time_h, event_h) ~ BMI_cat)`.
- Generates KM plots and log-rank tests.
- Writes:
  - `KM_Survival_by_BMI_60mo.*`
  - `KM_Survival_by_BMI_90mo.*`
  - `KM_Survival_by_BMI_120mo.*`
  - `KM_Survival_Summary_*mo.csv`
  - `KM_LogRank_Test_*mo.csv`
  - `KM_LogRank_AllHorizons.csv`

Generated log-rank results:

- 60 months: chi-square 81.40, df 5, p approximately 4.44e-16
- 90 months: chi-square 90.98, df 5, p reported as 0 due numeric underflow
- 120 months: chi-square 90.50, df 5, p reported as 0 due numeric underflow

Note: the script calls `ggsave()` with filenames ending in `.pdf` but `device = "svg"` for one output path. That mismatch should be corrected if regenerating outputs.

## Baseline Model Module

### `BaseModel/baseline_model.R`

This is the main baseline cause-specific Cox model script.

Model definition:

- Outcome: `Surv(Survival_time_h, Status_cs1_h)`
- Horizon: 90 months for the main model
- Event: `Status == 1` within 90 months
- BMI functional form: natural spline via `splines::ns()`
- Reference BMI for curves: 25
- Main knot scheme:
  - Boundary knots: observed BMI 5th and 95th percentiles
  - Internal knots: 10th, 35th, 65th, and 90th percentiles
- Sensitivity knot schemes:
  - K3: 10th, 50th, 90th percentiles
  - K5: intended additional sensitivity; implementation uses quantile-derived internal knots

Baseline covariates:

- `Age`
- `Sex`
- `Diabetes`
- `Hypertension`
- `Smoking`
- `MI_history`
- `LVEF`
- `eGFR`
- `Haemoglobin`
- `ACE_inhibitor_ARB`
- `Beta_blockers`
- `Lipid_lowering`
- `Revascularisation_acute`

Main outputs:

- `cox_RCS_pooled_fit.RDS`
- `cox_RCS_pooled_results.csv`
- `cox_RCS_BMI_curve_cs1.csv`
- `cox_RCS_BMI_curve_cs1.pdf`
- `C_index_per_imputation_cs1.csv`
- `C_index_summary_cs1.csv`
- `fit_list_cs1.RDS`
- `pool_fit_cs1.RDS`
- `pooled_results_cs1.csv`
- `PH_pvalues_per_imputation.csv`
- `PH_violation_rate.csv`
- `AIC_summary_K3_K4_K5.csv`
- `pooled_results_base_simplified.csv`
- `Cindex_comparison_base.csv`
- `AIC_comparison_base.csv`
- `Calibration_*`
- `Model_summary_base_vs_extended_60_90_120.csv`
- `Variable_selection_summary_base.csv`
- `Simplified_base_retained_variables.csv`

Current generated baseline performance:

- Mean C-index: 0.79834
- C-index SD across imputations: 0.00051
- Number of imputations: 20

Knot sensitivity by AIC:

- K3 mean AIC: 60726.20
- K4 mean AIC: 60724.84
- K5 mean AIC: 60729.52

The K4 model has the lowest mean AIC among these baseline spline choices.

The simplified baseline output appears very similar or identical to the full baseline model in some generated outputs. In `Cindex_comparison_base.csv`, both full and simplified models have the same mean C-index and confidence interval. In `Variable_selection_summary_base.csv`, the simplified model has a slightly higher mean C-index but also a higher mean AIC. This suggests the variable-selection code should be reviewed before treating simplified-model conclusions as final.

### Root `Study6/baseline_model.R`

The root-level baseline script is an older or alternate version. Differences from `BaseModel/baseline_model.R` include:

- It initially models `Surv(Survival_time, Status_cs1)` rather than consistently using horizon-censored variables.
- It defines an active `get_calib()` helper that the `BaseModel/` version has commented out.
- It reads `fit_list_cs1_extended.RDS` for extended comparisons.
- It writes calibration outputs such as `Calibration_comparison_all.csv`.

Because it is non-identical and overlaps heavily with the `BaseModel/` script, this file should be treated as a legacy or alternate script unless the analysis owner confirms it is canonical.

## Extended Model Module

### `ExtendedModel/extended_model.R`

This is the central extended-model script.

Key preprocessing:

- Reads `combined_BMI_outcomefiltered.csv`.
- Reads `mice_imputed_data.RDS`.
- Joins extra variables into the imputed long-format data by `ID`:
  - `ICD_status`
  - `Cancer`
  - `COPD_cat`
- Converts back to a `mids` object with `as.mids()`.
- Saves `mice_imputed_data_extended.RDS`.

The current main extended model uses these covariates:

- Baseline covariates from the base model
- `Cholesterol`
- `HDL`
- `LDL`
- `Triglycerides`
- `Stroke_TIA`
- `ICD_status`

Older or comparison code sections also include `Cancer` and `COPD_cat` in extended formulas. This inconsistency should be tracked carefully.

Main model definition:

- Outcome: `Surv(Survival_time_h, Status_cs1_h)`
- Horizon: 90 months
- Event: `Status == 1` within the horizon
- BMI functional form: natural spline with K4 internal knots
- Pooling: `mice::pool()`

Main outputs:

- `mice_imputed_data_extended.RDS`
- `cox_RCS_pooled_fit_extended.RDS`
- `cox_RCS_pooled_results_extended.csv`
- `cox_RCS_BMI_curve_cs1_extended.csv`
- `cox_RCS_BMI_curve_cs1_extended.pdf`
- `C_index_per_imputation_cs1_extended.csv`
- `C_index_summary_cs1_extended.csv`
- `fit_list_cs1_extended.RDS`
- `pool_fit_cs1_extended.RDS`
- `pooled_results_cs1_extended.csv`
- `PH_pvalues_per_imputation_extended.csv`
- `PH_violation_rate_extended.csv`
- `AIC_per_imputation_K3_K4_K5_extended.csv`
- `AIC_summary_K3_K4_K5_extended.csv`
- `BMI_curve_comparison_base_vs_extended_shaded.pdf`
- `BMI_RCS_knot_sensitivity_cs1.pdf`
- `cox_absrisk_90mo_BMI_curve_extended.csv`
- `cox_absrisk_90mo_BMI_curve_extended.pdf`

Current generated extended performance:

- Mean C-index: 0.81543
- C-index SD across imputations: 0.00056
- Number of imputations: 20

Extended-model knot sensitivity by AIC:

- K3 mean AIC: 57370.97
- K4 mean AIC: 57368.65
- K5 mean AIC: 57374.20

The K4 spline again has the lowest mean AIC among the tested K3/K4/K5 spline models.

Generated baseline-vs-extended summary across horizons:

| Horizon | Model | C-index mean | AIC mean |
|---:|---|---:|---:|
| 60 | Baseline | 0.80168 | 50934.15 |
| 60 | Extended | 0.81979 | 50295.77 |
| 90 | Baseline | 0.79834 | 58043.20 |
| 90 | Extended | 0.81576 | 57368.32 |
| 120 | Baseline | 0.79732 | 60543.38 |
| 120 | Extended | 0.81452 | 59855.36 |

Across these generated summaries, the extended model has higher discrimination and lower AIC than the baseline model at all three horizons.

## Complete-Case Evaluation

### `ExtendedModel/completecase_eval.R`

This script compares the imputed extended model with a complete-case extended model.

Key behavior:

- Reads `mice_imputed_data_extended.RDS` for BMI knot definitions.
- Reads `combined_BMI_outcomefiltered.csv` as the raw pre-imputation source.
- Creates 90-month horizon outcome variables.
- Filters complete cases across BMI, outcome variables, and all extended covariates.
- Fits the same extended Cox model on complete cases.
- Exports:
  - `cox_RCS_cs1_extended_CCA.RDS`
  - `cox_RCS_BMI_curve_cs1_extended_CCA.csv`
  - `cindex_cs1_extended_CCA.RDS`
  - `BMI_curve_MICE_vs_CCA_extended.pdf`

Generated complete-case comparison tables report:

- Full dataset: 121,481 participants, 2,865 events
- Complete-case dataset: 72,195 participants, 1,087 events
- Complete-case retention: 59.43% of participants and 37.94% of events
- MICE pooled C-index: 0.814 with 95% CI 0.813-0.815
- Complete-case C-index: 0.771 with 95% CI 0.75-0.79

The generated continuous summary suggests the complete-case subset differs from excluded participants, for example:

- Complete cases are younger on average.
- Complete cases have higher mean LVEF and eGFR.
- Complete cases have different lipid profiles.

This supports treating complete-case analysis as a sensitivity analysis, not the primary analysis.

Implementation issue: `completecase_eval.R` contains a syntax error at `abline(h = 1, lty = 3, col = "grey60")s`. This must be fixed before the plotting section can run cleanly.

## Proportional Hazards Diagnostics

### `ExtendedModel/proportional_hazards.R`

This script evaluates proportional hazards assumptions for the extended model.

Key behavior:

- Reads `mice_imputed_data_extended.RDS`.
- Reads `fit_list_cs1_extended.RDS`.
- Runs `cox.zph()` across imputed model fits.
- Writes per-imputation p-values and violation rates:
  - `PH_pvalues_per_imputation_extended_new.csv`
  - `PH_violation_rate_extended_new.csv`
- Generates Schoenfeld residual plots:
  - `PH_selected_covariates_imp1_extended.pdf`
  - `PH_Schoenfeld_all_covariates_panels_imp1_extended.pdf`
  - `schoenfeld_panels_BMI_Age_LVEF_eGFR.pdf`
- Generates log-minus-log survival plots:
  - `loglog_PH_checks_extended_imputed.pdf`

The script also contains a later section fitting a 90-month cutoff model with time-dependent checks.

### `ExtendedModel/prop_hazards_90days.R`

Despite the filename saying "90days", this script uses `horizon <- 90` in the same units as the rest of the study, which appear to be months. It should likely be renamed to avoid confusion.

Outputs:

- `PH_pvalues_per_imputation_extended_90mo.csv`
- `PH_violation_rate_extended_90mo.csv`
- `PH_selected_covariates_imp1_extended_90mo.pdf`

## Time-Varying Coefficient Sensitivity

### `ExtendedModel/TVCmodels.R`

This script tests whether BMI spline conclusions are stable when allowing selected covariates to vary with time.

Key behavior:

- Reads `mice_imputed_data_extended.RDS`.
- Uses imputation 1.
- Samples a 20,000-row subset for memory/performance.
- Fits:
  - a standard extended Cox model
  - a TVC Cox model with `tt(Age)`, `tt(eGFR)`, and `tt(Haemoglobin)` using interactions with `log(time)`
- Saves:
  - `cox_standard_subsample_extended.RDS`
  - `cox_TVC_subsample_extended.RDS`
  - `BMI_spline_coefficients_standard_vs_TVC_subsample.csv`
  - `BMI_spline_standard_vs_TVC_subsample_dashed.pdf`

Note: comments mention Age, LVEF, and eGFR, but the implemented TVC terms are Age, eGFR, and Haemoglobin. That mismatch should be reconciled.

## Functional-Form Sensitivity

### Spline Sensitivity in `ExtendedModel/extended_model.R`

The extended main script fits K3, K4, and K5 BMI spline versions and compares AIC. The generated output supports K4 as the best of the three by mean AIC.

### `ExtendedModel/FPmodels_sensitivity_analysis.R`

This script evaluates fractional polynomial forms for BMI at the 90-month horizon.

Key behavior:

- Uses `mice_imputed_data_extended.RDS`.
- Tests FP1 and diagonal FP2 specifications using powers:
  - `-2`, `-1`, `-0.5`, `0`, `0.5`, `1`, `2`, `3`
- Fits each specification across all imputations.
- Compares AIC.
- Saves the best overall fit list and BMI curve.

Generated top AIC results:

- Best overall: `FP2_-1_-1`, mean AIC 57377.31
- Next: `FP2_-2_-2`, mean AIC 57377.78
- Next: `FP2_-0.5_-0.5`, mean AIC 57379.45

Compared with the K4 spline mean AIC of approximately 57368.65, the K4 spline remains better by AIC in the generated outputs.

### `ExtendedModel/splines_extended_sensitivity_analysis.R`

Despite the filename, this script is another fractional-polynomial sensitivity script using the original `mice_imputed_data.RDS` plus row-index attachment of ICD, cancer, and COPD from `combined_BMI_outcomefiltered.csv`.

It tests a broader FP2 grid including mixed-power FP2 terms, writes:

- `FP_AIC_summary_extended.csv`
- `FP_AIC_per_imputation_extended.csv`
- `fit_list_cs1_extended_<best>.RDS`

This script uses an older extended covariate set including `COPD_cat` and `Cancer`, so its outputs are not directly comparable to the current updated extended model unless covariate definitions are aligned.

## Fine-Gray Competing-Risk Sensitivity

### `ExtendedModel/finegrey_sensitivity.R`

This script fits Fine-Gray subdistribution hazard models for SCD with non-cardiac death as the competing event.

Key behavior:

- Reads `mice_imputed_data_extended.RDS`.
- Applies a 90-month horizon.
- Uses `Status == 1` as SCD and `Status == 2` as competing event.
- Builds a model matrix with BMI natural splines and updated extended covariates.
- Fits `cmprsk::crr()`.
- Limits fitting to the first 3 imputations (`max_imps <- 3`) for performance.
- Pools coefficients using a Rubin-style manual pooling function.
- Writes:
  - `FineGray_SCD_vs_noncardiac_extended_pooled_results_90mo.csv`
  - `FineGray_SCD_vs_noncardiac_extended_allfits_90mo.RDS`

Because this only fits 3 imputations, it is a reduced sensitivity analysis and not equivalent to the 20-imputation Cox analyses.

### `ExtendedModel/plotfinegrey.R`

This script plots a simpler Fine-Gray BMI curve and can overlay it with a cause-specific Cox curve.

Key behavior:

- Reads `mice_imputed_data_extended.RDS`.
- Uses imputation 1.
- Fits or loads a small Fine-Gray model with BMI spline + Age + Sex.
- Writes:
  - `FineGray_BMI_SCD_curve_data_90mo.csv`
  - `FineGray_BMI_SCD_curve_90mo.pdf`
  - optionally `Cox_vs_FineGray_BMI_overlay_90mo.pdf`

Important mismatch: this script expects `cox_RCS_BMI_curve_cs1_extended_90mo.csv`, but the main extended-model script writes `cox_RCS_BMI_curve_cs1_extended.csv`. The overlay will be skipped unless the expected file exists or the filename is updated.

## Subgroup Interaction Analysis

### `ExtendedModel/subgroup_analysis.R`

This script attempts pooled subgroup interaction tests using likelihood-ratio comparisons and `mice::D2()`.

Tested subgroup variables:

- ICD vs non-ICD
- Diabetes yes/no
- Age `<65` vs `>=65`
- LVEF category: `<30`, `30-39`, `>=40`

The intended model compares:

- Base model: `rcs(BMI, 4)` plus covariates and subgroup main effect
- Interaction model: base model plus linear `BMI:subgroup` interaction

Output:

- `subgroup_interactions_mi_LRT_D2.csv`

Implementation concern: inside `run_subgroup_LRT_linear()`, the base-model fitting loop contains `d <- completed[[1]]`, which overwrites the current imputed dataset and causes the base model to use the first imputation repeatedly. That likely invalidates the pooled D2 comparison as written.

## Generated Output Themes

The generated outputs fall into these groups:

### Imputation

- Missingness summaries
- Pre/post imputation mean and SD comparisons
- Pre/post categorical proportions
- Density and bar plots comparing observed/imputed distributions
- Combined imputation diagnostic panel

### Descriptive

- Table 1 baseline characteristics by BMI category
- Continuous summaries
- Categorical summaries and chi-square/FDR outputs
- Comorbidity value-count checks

### Kaplan-Meier

- Survival curves by BMI category at 60, 90, and 120 months
- Survival summaries
- Log-rank tests

### Baseline Model

- Pooled Cox coefficient tables
- BMI spline HR curves
- C-index and AIC summaries
- PH tests
- Variable-selection summaries
- Calibration comparisons

### Extended Model

- Extended pooled Cox coefficient tables
- Extended BMI spline HR curves
- Absolute 90-month SCD risk curve
- Baseline-vs-extended BMI curve overlays
- K3/K4/K5 knot sensitivity
- Baseline-vs-extended C-index/AIC/calibration summaries

### Sensitivity Analyses

- Complete-case model and MICE-vs-complete-case curve
- PH diagnostics and Schoenfeld plots
- TVC model comparison
- Fractional-polynomial BMI functional-form comparison
- Fine-Gray competing-risk sensitivity
- Subgroup interaction tests

## Current Numerical Takeaways From Stored Outputs

The generated files indicate:

- The analysis dataset represented in Table 1 has 121,481 participants.
- There are 2,865 SCD events in the Table 1 output, corresponding to 2.4%.
- The extended model improves C-index versus the baseline model:
  - 90-month baseline C-index: about 0.798
  - 90-month extended C-index: about 0.816
- The extended model has lower AIC than the baseline model at 60, 90, and 120 months.
- The K4 BMI spline has lower AIC than tested K3/K5 alternatives in both baseline and extended models.
- The best tested fractional polynomial at 90 months (`FP2_-1_-1`) has higher AIC than the K4 spline extended model.
- Complete-case analysis retains only about 59% of participants and 38% of events, and has materially lower C-index than the MICE analysis.

These are descriptions of stored output files, not a fresh rerun.

## Reproducibility and Code Quality Observations

The following issues matter if this codebase must be rerun or handed off.

### Hard-coded paths

Most scripts contain hard-coded `S:/`, `T:/`, or UNC paths. A portable workflow would define `data_dir`, `study_dir`, and `output_dir` once and use relative paths or a config file.

### No execution orchestrator

The pipeline order is implicit. A user has to infer which scripts create which dependencies. A simple driver script, `targets` pipeline, Makefile, or README run order would reduce rerun errors.

### Derived files expected in different locations

The scripts generally write to the root Study6 working directory, while the repository stores outputs under `BaseModel/`, `ExtendedModel/`, `Imputation/`, and `DescriptiveAnalysis/`. This makes it difficult to determine which files are current and whether a script can find its dependencies from its own subdirectory.

### Duplicate and divergent scripts

There are overlapping scripts:

- `Study6/baseline_model.R` vs `Study6/BaseModel/baseline_model.R`
- `Study6/Imputation/MICE.R` vs `Study6/ExtendedModel/MICE.R`
- `DescriptiveAnalysis/` vs `DescriptiveAnalysis/ImputedData/`
- `ExtendedModel/FPmodels_sensitivity_analysis.R` vs `ExtendedModel/splines_extended_sensitivity_analysis.R`

Some duplicates differ in important model definitions or contain syntax errors. The canonical script for each analysis step should be declared.

### Syntax or runtime errors found by static inspection

- `ExtendedModel/MICE.R`: `pred <- make.predictorMatrix(imp_data)s`
- `ExtendedModel/completecase_eval.R`: `abline(h = 1, lty = 3, col = "grey60")s`
- `DescriptiveAnalysis/descriptive_analysis.R`: contains a bare `library` line
- `BaseModel/baseline_model.R`: calls `get_calib()` near the end, but the visible definition is commented out in that file
- `DescriptiveAnalysis/kaplan-meier.R`: saves a `.pdf` filename with `device = "svg"`
- `ExtendedModel/plotfinegrey.R`: expects a Cox curve filename not produced by the main extended-model script

### Covariate-set drift

The current main extended model excludes `Cancer` and `COPD_cat`, while older sections and some sensitivity scripts include them. This affects comparability across outputs and should be standardized.

### Horizon naming

The file `prop_hazards_90days.R` uses `horizon <- 90` in the same apparent month units as the rest of the study. The filename should likely be changed to `prop_hazards_90mo.R`.

### Complete-case results indicate potential selection

The complete-case subset differs from the full cohort and retains fewer events. Complete-case sensitivity results should be interpreted with that selection in mind.

### Statistical pooling details

Most Cox coefficient pooling uses `mice::pool()`. BMI spline curves are pooled manually using Rubin-style contrast pooling. Fine-Gray pooling is also manual and currently based on only three imputations. These methods should be documented in the statistical analysis plan to avoid ambiguity.

## Suggested Canonical Run Order

If the analysis were cleaned for reproducibility, the run order would likely be:

1. `Imputation/MICE.R`
   - Creates `combined_BMI_outcomefiltered.csv` and `mice_imputed_data.RDS`.
2. `Imputation/imputation_reporting.R`
   - Validates imputation behavior and creates diagnostics.
3. `DescriptiveAnalysis/descriptive_analysis.R`
   - Creates Table 1 and continuous summaries from imputation 1.
4. `DescriptiveAnalysis/descriptive_categorical.R`
   - Creates categorical BMI-category summaries.
5. `DescriptiveAnalysis/kaplan-meier.R`
   - Creates KM plots and log-rank tests.
6. `ExtendedModel/extended_model.R`
   - Creates `mice_imputed_data_extended.RDS`, fits extended Cox model, creates main extended outputs.
7. `BaseModel/baseline_model.R`
   - Fits baseline Cox model and compares baseline vs extended across horizons.
8. `ExtendedModel/completecase_eval.R`
   - Runs complete-case sensitivity.
9. `ExtendedModel/proportional_hazards.R` or `ExtendedModel/prop_hazards_90days.R`
   - Runs PH diagnostics.
10. `ExtendedModel/FPmodels_sensitivity_analysis.R`
    - Runs fractional-polynomial sensitivity for updated extended model.
11. `ExtendedModel/TVCmodels.R`
    - Runs TVC sensitivity.
12. `ExtendedModel/finegrey_sensitivity.R` and `ExtendedModel/plotfinegrey.R`
    - Runs competing-risk sensitivity and plots.
13. `ExtendedModel/subgroup_analysis.R`
    - Runs subgroup interaction tests, after fixing the imputation-loop issue.

## Recommended Cleanup Priorities

1. Add a root `README.md` or analysis manifest that defines the canonical scripts and run order.
2. Replace hard-coded working directories with project-relative paths.
3. Decide whether outputs should live in subdirectories or the root Study6 directory, then update scripts accordingly.
4. Remove `install.packages()` calls from scripts and add an environment setup file.
5. Fix the syntax/runtime issues listed above.
6. Standardize the extended covariate set across the main model and sensitivity analyses.
7. Remove or archive non-canonical duplicate scripts.
8. Save model objects and outputs with horizon-specific names, especially for 90-month analyses.
9. Add a lightweight validation script that checks required inputs, expected columns, number of imputations, event coding, and output freshness.

## High-Level Interpretation of the Codebase

The codebase implements a mature exploratory and inferential survival-analysis workflow rather than a productionized package. The statistical coverage is broad: imputation diagnostics, descriptive summaries, survival curves, baseline and extended Cox models, calibration/discrimination summaries, complete-case sensitivity, PH diagnostics, time-varying coefficient checks, fractional-polynomial checks, Fine-Gray competing-risk checks, and subgroup interactions.

The main scientific analysis appears to center on a 90-month cause-specific Cox model for SCD with BMI modeled nonlinearly using a four-internal-knot spline. The stored results suggest that the extended model improves discrimination and AIC over the baseline model, and that the chosen spline representation performs better by AIC than the tested alternative knot counts and fractional-polynomial alternatives.

The main technical weakness is reproducibility: paths are hard-coded, scripts overlap, outputs are stored separately from where scripts expect to write them, and several scripts contain small syntax or consistency errors. With a modest cleanup pass, the analysis could be made much easier to rerun, review, and hand off.
