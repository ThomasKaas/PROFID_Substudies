# Study7 Codebase Analysis

## Scope

The `Study7/` directory contains four standalone R scripts for descriptive and survival-oriented analyses across three PROFID cohorts:

- ICD cohort: `ICD_filtered_with_coords.csv`
- Non-ICD reduced cohort, LVEF <=35%: `NonICD_reduced_filtered_with_coords.csv`
- Non-ICD preserved cohort, LVEF >35%: `NonICD_preserved_filtered_with_coords.csv`

All scripts are written as direct execution scripts rather than functions or an R package. They read input data from a hard-coded Windows network-drive path and save analysis outputs into the current working directory from which the script is run.

## Directory Contents

| File | Main purpose | Main outputs |
| --- | --- | --- |
| `Table1.R` | Baseline characteristics by cardiovascular risk region for all three cohorts | `table1_ICD.html`, `table1_NR.html`, `table1_NP.html` |
| `SupT1.R` | Reporting completeness of selected binary clinical variables by region and centre | `med_missingness_ICD.html`, `med_missingness_NR.html`, `med_missingness_NP.html` |
| `event_rate_SupT2.R` | SCD and other-death event counts/rates by region, plus outcome missingness by region and centre | `events_ICD.html`, `events_NR.html`, `events_NP.html`, `missing_status_multilevel_ICD.html`, `missing_status_multilevel_NR.html`, `missing_status_multilevel_NP.html` |
| `km.R` | Kaplan-Meier curves for SCD-free survival by cardiovascular risk region | `km_plot_ICD.png`, `km_plot_NR.png`, `km_plot_NP.png` |

## Shared Workflow

Each script follows the same broad pattern:

1. Define a vector of required R packages.
2. Install any missing packages with `install.packages(..., quiet = TRUE)`.
3. Load the packages with `library()`.
4. Read the same three CSV files with `data.table::fread()`.
5. Prepare cohort-specific cardiovascular risk region labels.
6. Run the script-specific summarisation, table generation, or plotting logic.
7. Save outputs into the current working directory.

The common input paths are:

```r
fread("T:/Data Transfer to Charite/raw/ICD_filtered_with_coords.csv")
fread("T:/Data Transfer to Charite/raw/NonICD_reduced_filtered_with_coords.csv")
fread("T:/Data Transfer to Charite/raw/NonICD_preserved_filtered_with_coords.csv")
```

This means reproducibility depends on the user having access to the `T:/Data Transfer to Charite/raw/` drive and running the scripts in an environment where that path is mounted.

## Cohort Definitions and Risk Region Handling

The code uses three cohort objects consistently:

| Object | Cohort | Centre column used in centre-level summaries |
| --- | --- | --- |
| `df_ICD` | ICD cohort | `ctr_name` |
| `df_NR` | Non-ICD reduced cohort, LVEF <=35% | `DB` |
| `df_NP` | Non-ICD preserved cohort, LVEF >35% | `DB` |

Cardiovascular risk region handling differs between ICD and Non-ICD cohorts:

- `df_ICD` excludes `CVD_risk_region == 2`.
- `df_ICD$CVD_risk_region` is converted to a factor with levels `1`, `3`, and `4`, labelled `Low`, `High`, and `Very High`.
- `df_NR$CVD_risk_region` and `df_NP$CVD_risk_region` use levels `1`, `2`, `3`, and `4`, labelled `Low`, `Medium`, `High`, and `Very High`.

The practical implication is that the ICD cohort deliberately has no `Medium` risk group in these outputs, while both Non-ICD cohorts do.

## Package Dependencies

The scripts collectively depend on:

- `dplyr`
- `tidyverse`
- `data.table`
- `gt`
- `gtsummary`
- `survival`
- `survminer`
- `ggplot2`
- `scales`

Several scripts load both `dplyr` and `tidyverse`, which is redundant because `tidyverse` loads `dplyr`. Some loaded packages are not used directly in all scripts; for example, `event_rate_SupT2.R` loads `ggplot2` and `scales` but only creates `gt` tables.

The scripts auto-install packages at runtime. That is convenient for interactive use, but it can make production runs less reproducible because package versions are not pinned.

## Input Data Schema Expected by the Scripts

The scripts assume the following columns exist.

Shared or common columns:

- `CVD_risk_region`
- `Status`
- `Survival_time`
- `Age`
- `Sex`
- `LVEF`

ICD centre column:

- `ctr_name`

Non-ICD centre/database column:

- `DB`

Clinical/binary variables:

- `Hypertension`
- `Diabetes`
- `ACE_inhibitor_ARB`
- `Beta_blockers`
- `Anti_platelet`
- `Lipid_lowering`
- `Anti_diabetic`
- `Anti_coagulant`
- `Diuretics`
- `Smoking`

The binary-variable logic assumes values are encoded as the strings `"Yes"` and `"No"`. Values outside those two strings are treated as incomplete in `SupT1.R`, even if they are non-missing.

## `Table1.R`

### Purpose

`Table1.R` creates baseline characteristics tables stratified by cardiovascular risk region for the ICD, Non-ICD reduced, and Non-ICD preserved cohorts.

### Main steps

For each cohort, the script:

1. Selects the variables:
   - `CVD_risk_region`
   - `Age`
   - `Sex`
   - `LVEF`
   - `Hypertension`
   - `Diabetes`
   - `ACE_inhibitor_ARB`
   - `Beta_blockers`
   - `Anti_platelet`
   - `Lipid_lowering`
2. Converts selected binary variables to factors with levels `No`, `Yes`.
3. Converts `Sex` to a factor.
4. Uses `gtsummary::tbl_summary()` grouped by `CVD_risk_region`.
5. Reports continuous variables as `mean +/- sd`.
6. Reports categorical variables as `n (%)`.
7. Forces missing-value rows to appear with `missing = "always"` and label `Missing`.
8. Adds per-group sample sizes using `add_n()`.
9. Converts the table to a `gt` object and saves it as HTML.

### Outputs

- `table1_ICD.html`
- `table1_NR.html`
- `table1_NP.html`

### Notes

- The `category` field added via `modify_table_body()` classifies variables into `Demographics`, `Clinical characteristics`, and `Medications`, but the script does not explicitly render those categories as visible group headers in the final `gt` output.
- The table logic is duplicated three times with only cohort object, subtitle, and output filename changing.

## `SupT1.R`

### Purpose

`SupT1.R` creates supplementary reporting-completeness tables for binary clinical variables by cardiovascular risk region and centre.

### Variables checked for completeness

- `ACE_inhibitor_ARB`
- `Beta_blockers`
- `Anti_platelet`
- `Lipid_lowering`
- `Anti_diabetic`
- `Anti_coagulant`
- `Diuretics`
- `Smoking`
- `Hypertension`

### Completeness logic

For each region-centre combination, the script calculates:

```r
N - sum(variable %in% c("Yes", "No"), na.rm = TRUE)
```

This is a count of records that do not contain a valid `"Yes"` or `"No"` response for the variable.

### Grouping

- ICD cohort: grouped by `CVD_risk_region` and `ctr_name`.
- Non-ICD cohorts: grouped by `CVD_risk_region` and `DB`.

### Outputs

- `med_missingness_ICD.html`
- `med_missingness_NR.html`
- `med_missingness_NP.html`

### Notes

- The generated table title says "Reporting Completeness", but the displayed variable values are missing/incomplete counts, not completeness percentages.
- Non-standard encodings such as lowercase `"yes"`, numeric `1/0`, empty strings, or alternative missing codes will be counted as incomplete unless already harmonised upstream.

## `event_rate_SupT2.R`

### Purpose

`event_rate_SupT2.R` produces two families of outputs:

1. Sudden cardiac death and other-death counts/rates by cardiovascular risk region.
2. Outcome reporting completeness by cardiovascular risk region and centre.

### Event-rate logic

For each cohort, the script first removes rows with missing `Status`, then groups by `CVD_risk_region` and calculates:

- `N`: number of patients with non-missing `Status`
- `SCD_events`: count of `Status == 1`
- `Other_deaths`: count of `Status == 2`
- `SCD_rate`: `SCD_events / N * 100`, rounded to one decimal place
- `Other_death_rate`: `Other_deaths / N * 100`, rounded to one decimal place

### Missing-outcome logic

For each region-centre combination, the script calculates:

- `N`: total patients before excluding missing outcomes
- `missing_status`: number of rows where `Status` is missing
- `missing_pct`: missing outcome percentage, rounded to one decimal place

### Outputs

Event summary tables:

- `events_ICD.html`
- `events_NR.html`
- `events_NP.html`

Outcome missingness tables:

- `missing_status_multilevel_ICD.html`
- `missing_status_multilevel_NR.html`
- `missing_status_multilevel_NP.html`

### Notes

- The reported event rates are crude percentages among patients with non-missing `Status`. They are not person-time incidence rates and are not Kaplan-Meier cumulative incidence estimates.
- `Status == 1` is interpreted as sudden cardiac death.
- `Status == 2` is interpreted as other death.
- Any other non-missing `Status` value contributes to `N` but not to either event count.

## `km.R`

### Purpose

`km.R` creates Kaplan-Meier survival plots for SCD-free survival by cardiovascular risk region in the ICD, Non-ICD reduced, and Non-ICD preserved cohorts.

### Survival model logic

For each cohort:

1. Rows with missing `Status` are removed.
2. `Region` is created as a copy of `CVD_risk_region`.
3. A Kaplan-Meier fit is created with:

```r
survfit(Surv(Survival_time, Status == 1) ~ Region, data = ...)
```

This treats `Status == 1` as the event of interest. Other non-missing status values, including `Status == 2`, are treated as censored observations by the logical event expression.

### Plot settings

- `risk.table = TRUE`
- `conf.int = FALSE`
- x-axis label: `Time (months)`
- y-axis label: `SCD-free survival probability`
- theme: `theme_minimal()`
- ICD palette has three colors because ICD risk groups are `Low`, `High`, and `Very High`.
- Non-ICD palettes have four colors because Non-ICD risk groups include `Medium`.

### Outputs

- `km_plot_ICD.png`
- `km_plot_NR.png`
- `km_plot_NP.png`

### Notes

- Although `risk.table = TRUE` is passed to `ggsurvplot()`, the script saves only `km_* $plot` with `ggsave()`. That means the PNG files likely contain the main survival curves only, not the risk tables.
- Other deaths are handled as censored observations. That is appropriate for a cause-specific Kaplan-Meier-style display, but it is not a competing-risk cumulative incidence analysis.
- The script does not specify image dimensions, resolution, or output directory, so `ggsave()` uses defaults.

## Outputs Produced by a Full Run

Running all four scripts should produce 15 files:

| Output | Created by |
| --- | --- |
| `table1_ICD.html` | `Table1.R` |
| `table1_NR.html` | `Table1.R` |
| `table1_NP.html` | `Table1.R` |
| `med_missingness_ICD.html` | `SupT1.R` |
| `med_missingness_NR.html` | `SupT1.R` |
| `med_missingness_NP.html` | `SupT1.R` |
| `events_ICD.html` | `event_rate_SupT2.R` |
| `events_NR.html` | `event_rate_SupT2.R` |
| `events_NP.html` | `event_rate_SupT2.R` |
| `missing_status_multilevel_ICD.html` | `event_rate_SupT2.R` |
| `missing_status_multilevel_NR.html` | `event_rate_SupT2.R` |
| `missing_status_multilevel_NP.html` | `event_rate_SupT2.R` |
| `km_plot_ICD.png` | `km.R` |
| `km_plot_NR.png` | `km.R` |
| `km_plot_NP.png` | `km.R` |

Because output paths are relative, these files are written wherever the R session's working directory is set, not necessarily inside `Study7/`.

## Reproducibility and Execution Assumptions

Important assumptions embedded in the current code:

- The CSV files are available at the hard-coded `T:/Data Transfer to Charite/raw/` path.
- Required columns exist and use the expected names.
- Binary variables use exactly `"Yes"` and `"No"` coding.
- `Status == 1` means sudden cardiac death.
- `Status == 2` means other death.
- `Survival_time` is measured in months.
- `CVD_risk_region` uses numeric codes `1`, `2`, `3`, and `4`.
- The ICD cohort should exclude region code `2`.
- The user is comfortable with packages being installed automatically during script execution.

## Main Strengths

- The scripts are short and easy to inspect.
- The three cohort analyses are consistently structured.
- Output filenames are explicit and easy to map back to the analysis scripts.
- `gt` and `gtsummary` are appropriate choices for publication-style HTML tables.
- `survival` and `survminer` are appropriate choices for Kaplan-Meier curve generation.
- Missingness is reported separately for baseline binary variables and outcome status.

## Main Limitations and Risks

- The same input-loading and risk-region preparation code is repeated in all four scripts.
- Hard-coded network-drive paths make the scripts difficult to run on another machine or in a reproducible pipeline.
- Package versions are not pinned.
- Outputs are saved relative to the working directory, which can make results easy to misplace.
- There is no central configuration for input paths, output paths, cohort labels, or risk-region mappings.
- There are no checks that required columns exist before analysis starts.
- There are no checks for unexpected `Status` values.
- There are no checks for unexpected binary encodings.
- `km.R` requests risk tables but saves only the main plot object.
- Event rates are crude percentages, despite the filename suggesting "event rate"; readers could confuse them with person-time rates.
- There is no explicit project-level runner that executes scripts in the intended order.

## Suggested Refactoring Direction

A modest refactor would make the codebase easier to maintain without changing the statistical outputs:

1. Create a shared helper script, for example `Study7/_common.R`.
2. Move package loading, input paths, cohort loading, and risk-region recoding into reusable functions.
3. Define one cohort metadata table containing:
   - cohort key: `ICD`, `NR`, `NP`
   - display label
   - input file
   - centre column
   - risk-region levels
   - output suffix
4. Write outputs to a dedicated directory such as `Study7/outputs/`.
5. Add preflight validation for required columns and allowed values.
6. Save `ggsurvplot()` objects in a way that includes risk tables, or set `risk.table = FALSE` if the risk tables are not intended for exported figures.
7. Consider renaming `event_rate_SupT2.R` outputs or table labels to clarify that the rates are crude percentages among patients with non-missing outcome status.

## Overall Interpretation

`Study7/` is a compact analysis folder designed to generate publication-ready descriptive tables, supplementary missingness tables, crude outcome summaries, and Kaplan-Meier plots for three PROFID cohorts. The code is readable and internally consistent, but it is script-oriented and depends heavily on hard-coded paths and repeated logic. Its main scientific assumptions are that cardiovascular risk region defines the primary stratification, `Status == 1` identifies sudden cardiac death, and other deaths are either counted separately in descriptive summaries or treated as censored in Kaplan-Meier plots.

