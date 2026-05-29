# Study2 Codebase Description

## Purpose

`Study2/` contains the analysis code for PROFID Study 2: exploring seasonal, temporal, and environmental patterns in sudden cardiac death (SCD) incidence after myocardial infarction (MI). The code is written as procedural R scripts rather than as an R package or reproducible project pipeline. The scripts cover four broad workstreams:

1. Cohort assembly, temporal feature engineering, data quality checks, and clinical/lifestyle harmonisation.
2. Monthly time-series analysis of SCD events.
3. Seasonal survival modelling using Cox proportional hazards models.
4. Environmental/weather exposure integration and survival modelling.

The folder currently functions as an analyst workspace containing production-like scripts, temporary exploratory scripts, metadata files, and prototype model code. It does not yet have a single orchestrating entry point, dependency lockfile, local path configuration, or automated tests.

## Folder Contents

| File | Role | Status |
| --- | --- | --- |
| `01_data_cleaning.R` | Main cohort preparation and feature engineering script. Reads raw cohort extracts, harmonises columns, filters analytic cohort, creates temporal/holiday/lifestyle/clinical variables, and writes `df_cleaned.rds`. | Core script, but includes setup, package installation, exploratory checks, and some run-time issues. |
| `timeseriesTEMP.R` | Time-series analysis of monthly SCD events using classical decomposition, STL, X-13ARIMA-SEATS, and spectral analysis. | Exploratory/prototype script. Contains several undefined objects in later sections. |
| `seasonalSurvTEMP.R` | Earlier temporary version of seasonal Cox survival models. | Prototype/superseded by `02_02_03_survivalseasonal20260221.R`. |
| `02_02_03_survivalseasonal20260221.R` | More polished seasonal Cox survival analysis. Produces hazard ratio tables and plots for season, continuous sine/cosine seasonality, time-varying seasonality, and subgroup analyses. | Main seasonal survival script. |
| `02_02_04_survivalflexibleV2.R` | Flexible survival extensions: piecewise exponential models, penalised spline Cox models, cause-specific Cox for non-SCD death, and Fine-Gray competing risk models. | Main flexible survival script. |
| `environmental_data.R` | Downloads and aggregates daily ERA5 weather data from Open-Meteo for study centres. Builds center-level climate summaries and combined climate RDS files. | Data acquisition/preparation script; interactive and rate-limit sensitive. |
| `environmental_analysis_temp.R` | Links patient data to weather exposure data and fits environmental Cox models for temperature, pressure, daylight, and sunshine. | Exploratory/full pipeline draft with several unresolved object and naming assumptions. |
| `DB_lookup_table_final.csv` | Registry lookup table with registry type, location, coordinates, environmental resolution, and climate strategy. | Metadata input. |
| `research_centres_UPDATED.txt` | Centre metadata with centre IDs, registry codes, cities/countries, and coordinates. | Metadata input. |

## High-Level Data Flow

The intended pipeline is:

1. Run `01_data_cleaning.R`.
   - Input: raw cohort CSV files from `T:/PROFID/data/raw`.
   - Output: cleaned patient-level cohort `df_cleaned.rds`.

2. Run seasonal and temporal analyses on `df_cleaned.rds`.
   - `timeseriesTEMP.R` aggregates monthly SCD event counts and performs decomposition/X-13/spectral analyses.
   - `02_02_03_survivalseasonal20260221.R` fits seasonal Cox survival models.
   - `02_02_04_survivalflexibleV2.R` fits flexible survival and competing risk models.

3. Build environmental exposure data.
   - `environmental_data.R` downloads ERA5 daily climate data by centre through Open-Meteo and writes combined climate RDS files.

4. Link patient data to weather and model environmental associations.
   - `environmental_analysis_temp.R` joins `df_cleaned.rds`, research-centre metadata, CERT centre IDs, and climate data.
   - It fits Cox models for temperature, pressure, daylight, and sunshine, then saves environmental model objects.

Conceptually:

```text
Raw cohort CSVs
  -> 01_data_cleaning.R
  -> df_cleaned.rds
      -> timeseriesTEMP.R
      -> 02_02_03_survivalseasonal20260221.R
      -> 02_02_04_survivalflexibleV2.R
      -> environmental_analysis_temp.R

research_centres_UPDATED.txt
  -> environmental_data.R
  -> climate_all_centers.rds
      -> environmental_analysis_temp.R

DB_lookup_table_final.csv
  -> registry environmental-resolution strategy reference
```

## Dependencies

The scripts use the following main R packages:

| Package | Used for |
| --- | --- |
| `dplyr`, `tidyr`, `tibble`, `tidyverse`, `purrr`, `readr` | Data manipulation and CSV/RDS output. |
| `lubridate`, `timeDate` | Dates, seasons, holidays, survival/event date construction. |
| `survival` | Cox models, `Surv()`, `coxph()`, `survSplit()`. |
| `cmprsk` | Fine-Gray competing risk models and cumulative incidence. |
| `splines` | Natural splines for temperature and seasonal curves. |
| `ggplot2`, `patchwork` | Figures and combined plots. |
| `seasonal` | X-13ARIMA-SEATS seasonal adjustment. |
| `forecast`, `zoo` | Missing-value interpolation and rolling spectral analysis. |
| `naniar`, `VIM` | Missingness summaries and visualisation. |
| `httr`, `jsonlite` | Open-Meteo API calls. |
| `stringr`, `stringi` | String cleanup and accent removal for centre names. |
| `broom` | Tidy model summaries. |

The scripts currently install packages inline using `install.packages()` in `01_data_cleaning.R` and `timeseriesTEMP.R`. That is convenient for a one-off desktop session, but it is not ideal for reproducibility or batch execution. A project-level package manifest, such as `renv.lock`, would make the environment easier to reproduce.

## External Data Dependencies

The code expects data outside `Study2/`. Most paths are hard-coded to `T:/PROFID/...`, for example:

| Expected path or file | Purpose |
| --- | --- |
| `T:/PROFID/data/raw/ICD_all.csv` | Raw ICD-all cohort extract. Loaded but not included in the final `bind_rows()` by default. |
| `T:/PROFID/data/raw/ICD.csv` | Raw ICD cohort extract. |
| `T:/PROFID/data/raw/NonICD_preserved.csv` | Raw non-ICD preserved LVEF cohort extract. |
| `T:/PROFID/data/raw/NonICD_reduced.csv` | Raw non-ICD reduced LVEF cohort extract. |
| `T:/PROFID/data/processed/df_cleaned.rds` | Cleaned patient-level cohort used by survival, flexible survival, and environmental analyses. |
| `T:/PROFID/data/raw/research_centres_UPDATED.txt` | Centre metadata with IDs, registry codes, cities/countries, and coordinates. A copy also exists in `Study2/`. |
| `T:/PROFID/data/raw/centreIDSEUCERT.csv` | Patient-to-centre mapping for CERT patients. Not present in `Study2/`. |
| `T:/PROFID/data/raw/era5_city_raw_until2022/climate_all_centers.rds` | Combined daily ERA5 climate data. |

Because these paths point to a Windows drive, the code will not run unchanged on macOS/Linux unless that drive is mounted equivalently or the paths are parameterised.

## Core Data Model

The patient-level dataset produced by `01_data_cleaning.R` is expected to contain at least:

| Variable | Meaning |
| --- | --- |
| `ID` | Patient identifier. |
| `DB` or `dataset` | Registry/database identifier. |
| `Time_zero_Ym` | Follow-up start date or year-month. Converted to `Date`. |
| `Time_zero_Y` | Follow-up start year. |
| `Survival_time` | Follow-up duration. The main scripts treat this as months. |
| `Status` | Outcome status: `0` censored, `1` SCD, `2` non-SCD death/competing event. |
| `event_date` | Derived event/censoring date as `Time_zero_Ym + round(Survival_time)` months. |
| `Age`, `Sex`, `BMI` | Baseline demographic/clinical covariates. |
| `LVEF`, `MRI_LVEF`, `LVEF_std` | LVEF source values and harmonised LVEF. |
| `season`, `month_num`, `month_lab` | Season/month variables derived from `Time_zero_Ym` or event date. |

The climate dataset is expected to contain:

| Variable | Meaning |
| --- | --- |
| `center_id` | Research centre identifier. |
| `date` | Daily date. |
| `temp_mean`, `temp_min`, `temp_max` | Daily temperature variables. |
| `pressure` | Surface pressure. |
| `sunshine` | Sunshine duration in hours. |
| `daylight` | Daylight duration in hours. |

## Script Details

### `01_data_cleaning.R`

This is the main preparation script. It does the following:

1. Installs and loads R packages.
2. Creates a local project folder skeleton: `data/raw`, `data/processed`, `scripts`, `output/tables`, `output/figures`, and `output/models`.
3. Writes a small `project_metadata.csv`.
4. Sets the working directory to `T:/PROFID/data/raw`.
5. Reads four raw cohort CSVs: `ICD_all.csv`, `ICD.csv`, `NonICD_preserved.csv`, and `NonICD_reduced.csv`.
6. Adds a `dataset` identifier to each raw data frame.
7. Computes common and union column sets across the four extracts.
8. Standardises column sets by adding missing columns as `NA`.
9. Combines `ICD`, `NonICD_preserved`, and `NonICD_reduced`; `ICD_all` is loaded and standardised but commented out of the final bind.
10. Filters the analytic cohort to non-missing `Time_zero_Ym` and positive `Survival_time`.
11. Coerces core survival/time fields.
12. Derives month, season, holiday, Easter, and daylight saving indicators.
13. Performs missingness summaries and visualisations.
14. Applies plausibility filters to clinical/laboratory variables.
15. Creates `event_date` from follow-up start plus rounded survival months.
16. Checks temporal consistency.
17. Creates lifestyle variables for smoking, alcohol, BMI category, and NYHA-based physical activity proxy.
18. Harmonises LVEF, preferring `MRI_LVEF` over echocardiographic `LVEF`.
19. Standardises ECG variables and recodes conduction abnormalities.
20. Recodes medication variables and creates medication count/percentage scores.
21. Saves the cleaned cohort as `df_cleaned.rds`.

Important caveats:

- The comments describe a robust parser for `Time_zero_Ym`, but the current code simply calls `as.Date(df$Time_zero_Ym)`.
- The script references `df$is_christmas_ny` in a sanity check, but the created variable is named `is_christmas`.
- Temporal checks reference `followup_start_date`, but the script uses `Time_zero_Ym`; `followup_start_date` is not created.
- Several variables are forcibly set to `NA` in the plausibility filter section, including `SBP`, `DBP`, `CRP`, `Troponin_T`, `NYHA`, `AV_block`, and related fields. This may be intentional due to unavailable/incompatible columns, but it also removes downstream information needed by some derived variables.
- `scale()` inside `mutate()` returns matrix-like columns unless explicitly converted with `as.numeric()`.
- The script mixes project setup, package installation, cleaning, QC, plotting, and saving in one file.

### `timeseriesTEMP.R`

This script performs temporal aggregation and time-series analysis of SCD events. The intended steps are:

1. Load `df_cleaned.rds`.
2. Aggregate SCD events by month using `date_SCD`.
3. Create a monthly `ts` object with frequency 12.
4. Run classical additive decomposition with `decompose()`.
5. Run STL decomposition with `stl(..., s.window = "periodic")`.
6. Quantify seasonal amplitude by month.
7. Save decomposition plots and seasonal summary outputs.
8. Run X-13ARIMA-SEATS seasonal adjustment using `seasonal::seas()`.
9. Restrict to stable years, especially 2005-2018, to avoid zero-heavy/noisy periods.
10. Compare adjusted series across full, post-2000, and stable windows.
11. Perform spectral/Fourier analysis using `spec.pgram()`.
12. Compare pre-2000 and post-2000 spectral structure.
13. Save output RDS/CSV/PNG artifacts.

Important caveats:

- It reads `df_cleaned.rds` from `T:/PROFID/data/raw`, while other scripts expect it in `T:/PROFID/data/processed`.
- It aggregates on `date_SCD`, but the cleaning script creates `event_date`; `date_SCD` is not created in `01_data_cleaning.R`.
- `ggsave(..., plot = aver_seas)` is used for the monthly event-count figure, so the wrong plot object may be saved.
- The first `ggsave()` uses `plot = p`, but `p` is not defined.
- The script uses `spec_pre` and `spec_post` before they are created.
- The final save section writes `scd_decomp_long` and `top_peaks`, but those objects are not created in the script.
- This should be treated as exploratory code until the undefined objects and input-date conventions are standardised.

### `seasonalSurvTEMP.R`

This is an earlier temporary seasonal survival modelling script. It:

1. Loads `df_cleaned.rds`.
2. Creates `fu_yrs = Survival_time`, although the header says survival time is in months.
3. Creates `status_scd = Status == 1`.
4. Derives month, season, and sine/cosine seasonality terms.
5. Fits a base Cox model with categorical season.
6. Fits a continuous sine/cosine Cox model.
7. Attempts time-varying seasonal effects by follow-up band.
8. Fits subgroup Cox models by LVEF category and age group.
9. Contains narrative interpretation comments at the end.

Important caveats:

- The variable `fu_yrs` is assigned `Survival_time` without converting months to years.
- It calls `ggsave(..., plot = p)`, but `p` is not defined.
- In the time-varying prediction section, `pred_months_tv` creates `month_start`, but the sine/cosine calculation uses `month`, which is not present.
- This file appears superseded by `02_02_03_survivalseasonal20260221.R`.

### `02_02_03_survivalseasonal20260221.R`

This is the main seasonal Cox survival script. It assumes `df_cleaned.rds` already exists in `T:/PROFID/data/processed`.

The script:

1. Loads the cleaned cohort.
2. Defines `fu_mo = Survival_time`.
3. Creates a cause-specific SCD event indicator: `status_scd = 1` for `Status == 1`, otherwise 0.
4. Extracts the month of follow-up start.
5. Enforces season factor levels: Winter, Spring, Summer, Autumn.
6. Creates sine/cosine seasonal terms.
7. Filters out non-positive follow-up.
8. Fits a base Cox model: `Surv(fu_mo, status_scd) ~ season`.
9. Saves season hazard ratios and a forest plot.
10. Fits a continuous seasonal model: `Surv(fu_mo, status_scd) ~ sin_time + cos_time`.
11. Predicts relative hazard by month and saves the predicted curve.
12. Creates follow-up bands: 0-24 months, 24-60 months, and >60 months.
13. Fits a time-varying seasonal model with interactions between sine/cosine terms and follow-up band.
14. Saves model coefficients and predicted monthly hazards by follow-up band.
15. Creates LVEF categories: `<=35%`, `36-50%`, `>50%`.
16. Fits separate sine/cosine Cox models by LVEF category.
17. Creates age categories: `<55`, `55-69`, `>=70`.
18. Fits separate sine/cosine Cox models by age category.
19. Saves subgroup model outputs and figures.

This file is more coherent than `seasonalSurvTEMP.R` and should be treated as the current seasonal survival analysis entry point.

Important caveats:

- The model treats non-SCD death (`Status == 2`) as censoring for cause-specific SCD analysis. That is methodologically valid for cause-specific hazards but should be explicitly described in reporting.
- Some prediction code uses grouped `mutate()` with `cur_data()`, which is now soft-deprecated in newer dplyr versions. It may still work but should be modernised.
- No proportional hazards diagnostics are saved.

### `02_02_04_survivalflexibleV2.R`

This script extends the seasonal survival analysis with more flexible and competing-risk models. It assumes the same cleaned cohort input as the seasonal Cox script.

The script:

1. Loads `df_cleaned.rds`.
2. Creates `fu_mo`, `status_scd`, month, season, sine/cosine terms, day of year, and factorised sex.
3. Filters out non-positive follow-up.
4. Creates age and LVEF categories.
5. Builds piecewise survival intervals using `survSplit()` at 12, 24, and 60 months.
6. Computes person-time and broad calendar periods using tertiles of follow-up start year.
7. Fits a piecewise exponential model using Poisson regression with offset `log(person_time)`.
8. Saves piecewise model coefficients and predicted rates by interval/season.
9. Fits a penalised spline Cox model on month of follow-up start.
10. Saves the smooth seasonal hazard curve.
11. Creates `status_nonscd` for non-SCD death.
12. Fits a cause-specific Cox model for non-SCD death by season.
13. Fits Fine-Gray competing risk models for SCD using season dummy variables.
14. Computes cumulative incidence functions by season.
15. Saves competing-risk tables and plots.

Important caveats:

- `broom::tidy()` and `ggplot()` are used, but `broom` and `ggplot2` are not loaded at the top. The script uses `broom::tidy()` explicitly for some calls, but plain `ggplot()` requires `ggplot2` to be attached.
- The `cal_period` cut points are quantiles of start year; if duplicate quantile breakpoints occur, `cut()` can fail.
- Fine-Gray models use simple season dummies only; adjusted competing-risk models are not implemented.
- The cumulative incidence extraction assumes names returned by `cuminc()` match the `^1 ` pattern.

### `environmental_data.R`

This script acquires climate exposure data. It:

1. Loads centre metadata from `research_centres_UPDATED.txt`.
2. Defines `get_climate()` to call the Open-Meteo ERA5 archive API.
3. Requests daily data from 1994-01-01 to 2022-12-31.
4. Retrieves temperature, pressure, sunshine duration, and daylight duration.
5. Converts sunshine/daylight from seconds to hours.
6. Defines retry logic in `get_climate_safe()`.
7. Loops through selected centres, sleeping between API calls to avoid throttling.
8. Saves centre-specific `climate_center_<id>.rds` files.
9. Binds centre files into `climate_all`.
10. Summarises climate by centre, including annual/winter/summer temperatures, pressure summaries, daylight amplitude, and sunshine summaries.
11. Handles missing centre ID 32 with a redownload attempt.
12. Rebuilds a combined `climate_all_centers.rds` from files in `era5_city_raw_until2022`.

Important caveats:

- The script starts its download loop at row 14, so earlier centres are skipped unless they already exist from prior runs.
- It calls `View(centers)`, which is interactive and unsuitable for non-interactive execution.
- It renames `climate_summary <- climate_summary %>% rename(center_id = ID)`, but `climate_summary` already groups by `center_id` and does not have `ID`; this line is likely wrong.
- In the redownload section, `centers` has already been renamed from `ID` to `center_id`, but later code still uses `centers$ID`.
- API calls use fixed sleeps and no local cache check before requesting.
- The script assumes a Windows `T:/PROFID/...` filesystem.

### `environmental_analysis_temp.R`

This script links the cleaned patient cohort to climate exposure data and fits weather-related survival models.

The intended workflow is:

1. Load `df_cleaned.rds`.
2. Load combined daily climate data from `climate_all_centers.rds`.
3. Load research-centre metadata.
4. Define registry groups:
   - Single-centre: `ASTN`, `ATMS`, `HELS`, `ISAR`, `NANC`, `OLMC`, `SLSN`.
   - Multi-centre: `DOIT`, `FREN`, `ISRL`, `PRDT`, `PRSE`, `SWHR`.
   - Excluded: `MDRT`, `MDII`, `SHFT`, `DRVT`.
5. Attach CERT patient centre information from `centreIDSEUCERT.csv`.
6. Filter patients with non-missing `event_date`, `Time_zero_Ym`, and `Status`.
7. Clean centre names with `stringi`.
8. Join patients to centre metadata.
9. Limit climate data to the observed patient event-date range.
10. Add registry and country metadata to climate data.
11. Create seasonal climate averages for multi-centre national registries.
12. Retain daily city-level climate for single-centre registries.
13. Link single-centre patients by event date and registry.
14. Link multi-centre patients by registry, country, and season.
15. Combine into `final_env`.
16. Fit Cox models for:
    - Nonlinear temperature using `ns(temp_mean, df = 4)`.
    - Scaled pressure.
    - Daylight duration.
    - Sunshine duration.
17. Fit sensitivity analyses for single-centre, multi-centre, and winter-only subsets.
18. Save environmental dataset and model RDS files.
19. Build a 2x2 combined figure for temperature, pressure, daylight, and sunshine.

Important caveats:

- The script joins to an object named `centers`, but it only reads `research_centres`; `centers` is not created in this script.
- The join uses `by = c("ctr_name_clean" = "Center")`, but the local metadata file uses `center` lowercase, not `Center`.
- `CERT` is prepared separately, but it is not included in either `single_regs` or `multi_regs`, so it is likely dropped from final environmental modelling.
- `climate_country_season` uses average climate by season over the full date window, not event-date-specific weather.
- Single-centre joining is by `event_date` and `DB`, not by `center_id`; this works only if each `DB` maps cleanly to one centre in the climate data.
- Later plotting code references `pred_single`, `pred_multi`, `pred_winter`, and `pred_summer`, but those objects are not created.
- Winter/summer models at the end are fit after those undefined plots, so the script will stop before reaching them unless the missing prediction objects already exist in the R session.

## Metadata Files

### `DB_lookup_table_final.csv`

This file describes registry-level environmental resolution and climate strategy. It maps registry codes to:

- Registry name.
- Country/city.
- Coordinate type.
- Latitude/longitude where available.
- Environmental resolution.
- Climate strategy.

The climate strategies are:

| Strategy | Meaning |
| --- | --- |
| `city-level` | Use ERA5 daily weather for one centre/city. |
| `country-seasonal-average` | Use country-level seasonal climate means for national multi-centre registries. |
| `season-only` | No point climate linkage; use season-only adjustment/analysis. |

### `research_centres_UPDATED.txt`

This file contains centre-level metadata:

- `ID`
- `center`
- `DB`
- `City`
- `Country`
- `Latitude`
- `Longitude`

It includes standard registry centres and multiple CERT centres. The CERT entries appear to reuse ID `6` and have a different column alignment than the preceding rows, so they need careful validation before automated joins.

## Main Outputs

Expected outputs include:

| Output | Producer | Description |
| --- | --- | --- |
| `df_cleaned.rds` | `01_data_cleaning.R` | Cleaned patient-level cohort. |
| `cox_base_season_hr.csv` | `02_02_03_survivalseasonal20260221.R` | HRs for season vs Winter. |
| `cox_base_season_forest.png` | `02_02_03_survivalseasonal20260221.R` | Forest plot for categorical season model. |
| `cox_sincos_hr.csv` | `02_02_03_survivalseasonal20260221.R` | Sine/cosine model coefficients. |
| `continuous_seasonal_predicted_hazard_by_month.csv` | `02_02_03_survivalseasonal20260221.R` | Predicted monthly relative hazard. |
| `seasonal_continuous.png` | `02_02_03_survivalseasonal20260221.R` | Continuous seasonal hazard plot. |
| `cox_timevarying_season_sincos_by_band.csv` | `02_02_03_survivalseasonal20260221.R` | Time-varying season model coefficients. |
| `timevarying_seasonal_predicted_hazard_by_band.csv` | `02_02_03_survivalseasonal20260221.R` | Predicted monthly hazards by follow-up band. |
| `cox_continuous_season_by_LVEF.csv` | `02_02_03_survivalseasonal20260221.R` | Seasonal coefficients by LVEF group. |
| `cox_continuous_season_by_Agecat.csv` | `02_02_03_survivalseasonal20260221.R` | Seasonal coefficients by age group. |
| `piecewise_exponential_coefficients.csv` | `02_02_04_survivalflexibleV2.R` | Piecewise exponential model coefficients. |
| `pspline_seasonal_curve.csv` | `02_02_04_survivalflexibleV2.R` | Penalised spline seasonal curve. |
| `finegray_season_hr.csv` | `02_02_04_survivalflexibleV2.R` | Fine-Gray season HRs. |
| `fast_finegray_season_hr.csv` | `02_02_04_survivalflexibleV2.R` | Simplified Fine-Gray season HRs. |
| `climate_center_<id>.rds` | `environmental_data.R` | Daily centre-specific climate data. |
| `climate_all_centers.rds` | `environmental_data.R` | Combined daily climate dataset. |
| `final_environmental_dataset.rds` | `environmental_analysis_temp.R` | Patient-level environmental analysis dataset. |
| `model_temperature.rds`, `model_pressure.rds`, `model_daylight.rds`, `model_sunshine.rds` | `environmental_analysis_temp.R` | Environmental survival model objects. |

## Execution Readiness

Static parsing was checked for all R files in `Study2/`. All scripts parse successfully. That means there are no R syntax errors in the current files.

However, parsing is not the same as successful execution. End-to-end execution is currently blocked by:

1. External data not present in the repository.
2. Hard-coded `T:/PROFID/...` paths.
3. Several undefined objects in prototype scripts.
4. Mixed object naming conventions, especially `date_SCD` vs `event_date`, `centers` vs `research_centres`, and `Center` vs `center`.
5. Interactive commands such as `View()`.
6. Inline package installation.

## Notable Technical Issues

The most important issues to resolve before relying on the scripts as a reproducible pipeline are:

1. Path configuration is hard-coded.
   - The code assumes a Windows `T:/PROFID` drive.
   - A project-level `config.R` or environment-variable based path helper would make the scripts portable.

2. The cleaned cohort output location is inconsistent.
   - `01_data_cleaning.R` saves `df_cleaned.rds` in the current working directory after `setwd("T:/PROFID/data/raw")`.
   - Later scripts expect `T:/PROFID/data/processed/df_cleaned.rds`.

3. Date variables are inconsistent.
   - Cleaning creates `event_date`.
   - Time-series code uses `date_SCD`.
   - Temporal checks reference `followup_start_date`.

4. Temporary scripts contain undefined plot/model objects.
   - `seasonalSurvTEMP.R` uses `p` and `month`.
   - `timeseriesTEMP.R` uses `p`, `scd_decomp_long`, `top_peaks`, and premature `spec_pre`/`spec_post`.
   - `environmental_analysis_temp.R` uses `centers`, `pred_single`, `pred_multi`, `pred_winter`, and `pred_summer`.

5. Metadata column names are inconsistent.
   - `research_centres_UPDATED.txt` uses `center`.
   - `environmental_analysis_temp.R` expects `Center`.
   - `environmental_data.R` renames `ID` to `center_id`, then later refers to `ID` again.

6. Some transformations may accidentally erase useful data.
   - `01_data_cleaning.R` sets some clinical variables to `NA` globally before later deriving lifestyle/clinical features.

7. Model diagnostics are limited.
   - Seasonal Cox models do not save proportional hazards checks.
   - There is no central log of excluded records, model populations, or missingness after each modelling filter.

8. There is no dependency lock or test harness.
   - Package versions and external tools such as X-13 are not pinned.
   - No automated smoke test validates that the pipeline can run on a small fixture dataset.

## Recommended Refactor Plan

Recommended next steps, in priority order:

1. Create a path/config layer.
   - Define `PROFID_ROOT`, `DATA_RAW`, `DATA_PROCESSED`, and `OUTPUT_DIR` once.
   - Remove `setwd()` from analysis scripts.

2. Split setup from analysis.
   - Move package installation out of scripts.
   - Load packages only at script start.

3. Promote the current main scripts and archive prototypes.
   - Keep `01_data_cleaning.R`, `02_02_03_survivalseasonal20260221.R`, `02_02_04_survivalflexibleV2.R`, `environmental_data.R`, and a cleaned version of `environmental_analysis_temp.R`.
   - Move `seasonalSurvTEMP.R` and `timeseriesTEMP.R` to an `archive/` or `exploratory/` folder after extracting valid code.

4. Standardise core variable names.
   - Use `Time_zero_Ym` for follow-up start.
   - Use `event_date` for derived event/censoring date.
   - Use `status_scd` for SCD cause-specific event indicator.
   - Use `fu_mo` for follow-up in months.

5. Fix environmental metadata joins.
   - Decide whether joins should use `center_id`, `DB`, cleaned centre name, or a dedicated lookup table.
   - Validate CERT rows separately because the local centre metadata structure appears inconsistent.

6. Add model population accounting.
   - For each model, save the number of included records, events, non-SCD deaths, censored records, missing exposure values, and registries included.

7. Add diagnostics.
   - Save `cox.zph()` results for Cox models.
   - Save missingness summaries after each major filter.
   - Save session info for each run.

8. Add a lightweight run script.
   - Example order:
     1. `01_data_cleaning.R`
     2. `02_02_03_survivalseasonal20260221.R`
     3. `02_02_04_survivalflexibleV2.R`
     4. `environmental_data.R`
     5. `environmental_analysis.R`

9. Add a small synthetic fixture dataset.
   - This would allow syntax plus execution smoke tests without requiring protected raw data.

## Current Best Entry Points

For the current codebase, the most defensible entry points are:

1. `01_data_cleaning.R` for cohort preparation, after fixing paths and the `df_cleaned.rds` output location.
2. `02_02_03_survivalseasonal20260221.R` for primary seasonal survival models.
3. `02_02_04_survivalflexibleV2.R` for flexible survival and competing-risk sensitivity analyses.
4. `environmental_data.R` for climate acquisition, after fixing metadata handling and making the API download loop resumable.
5. `environmental_analysis_temp.R` as the basis for environmental modelling, after resolving `centers`/metadata joins and undefined plotting objects.

`seasonalSurvTEMP.R` and `timeseriesTEMP.R` are best treated as exploratory drafts unless the unresolved objects and naming inconsistencies are corrected.

## Verification Performed

The codebase was inspected statically on 2026-05-29 from `/Users/thomaskaas/PROFID_Substudies`.

Checks performed:

- Listed all files under `Study2/`.
- Reviewed all seven R scripts.
- Reviewed both metadata input files present in `Study2/`.
- Searched for package usage, file I/O, model entry points, outputs, hard-coded paths, and likely undefined objects.
- Parsed all R scripts with `Rscript -e parse(...)`.

Result:

- All R scripts parse successfully.
- End-to-end execution was not attempted because the required protected/raw data files and Windows `T:/PROFID/...` paths are not available in the local workspace.
