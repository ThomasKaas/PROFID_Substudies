# Study 9 Codebase Description

This document describes the `Study9/` codebase in the `PROFID_Substudies` workspace. The folder contains an R-based analysis workflow for PROFID UmBIZO Study 9, focused on calendar-time trends from 2000 to 2020 in two cohort-specific outcomes:

- Non-ICD cohort: sudden cardiac death, represented by `SCD_bin` / source `SCD_event`.
- ICD cohort: appropriate ICD therapy proxy, represented by `ICD_proxy_bin`, defined as `ICD_bin == 1` and `Status == 1`.

The workflow is not an R package or self-contained project. It consists of three standalone R scripts with hard-coded Windows/network paths. The intended execution environment is an R session on a machine where the `S:/` input drive and `T:/Study_9` output drive are available.

## Directory Contents

`Study9/` contains three top-level script files:

| File | Role |
| --- | --- |
| `Script 01: Final EHJ dataset unchanged + calendar-time QC + minimal dataset` | Builds the analysis-ready Study 9 dataset from `df_handled.csv`, creates QC files, writes the minimal RDS used downstream, and then rebuilds Table 1 with non-ICD patients split by LVEF <35% versus >=35%. |
| `Script 02: Calendar-time temporal summaries (2000-2020)` | Uses the minimal RDS from Script 01 to produce crude annual and calendar-band summaries, publication figures, unadjusted temporal trend models, adjusted temporal trend models, and non-ICD LVEF subgroup analyses. |
| `Script 03: Sensitivity analysis restricted to LVEF <35% (2000-2020)` | Rebuilds an independent LVEF <35% sensitivity dataset directly from `df_handled.csv`, then repeats the crude summaries, figures, and temporal trend models within the restricted population. |

There are no nested source directories, metadata files, project files, or dependency manifests in this checkout.

## High-Level Workflow

The intended data flow is:

```text
S:/AG/f-dhzC-profid/Data Transfer to Charite/df_handled.csv
  -> Script 01 first section
  -> T:/Study_9/Results_Study9/Script01_BuildAnalysisDataset_v2/
       df_study9_analysis_v2.rds
       df_study9_analysis_v2.csv
       QC and variable mapping files
  -> T:/Study_9/Results_Study9/Script01_CalendarTime_QC/
       df_study9_minimal.rds
  -> Script 01B section
       Table 1 with non-ICD LVEF <35% / >=35% split
  -> Script 02
       crude rate tables, figures, formal temporal trend outputs

S:/AG/f-dhzC-profid/Data Transfer to Charite/df_handled.csv
  -> Script 03
  -> restrict to years 2000-2020 and LVEF <35%
  -> crude rate tables, figures, formal trend outputs for sensitivity analysis
```

Script 02 depends on the `df_study9_minimal.rds` file written by Script 01. Script 03 does not depend on Script 01 output; it reads the raw handled CSV directly and rebuilds the restricted LVEF <35% dataset internally.

## Main Scientific/Analysis Scope

The scripts implement a calendar-time analysis with:

- Study window: baseline/index year 2000 through 2020.
- Calendar-time bands:
  - `2000-2004`
  - `2005-2009`
  - `2010-2014`
  - `2015-2020`
- LVEF subgroup threshold: `<35%` versus `>=35%`.
- Rate scale: events per 1,000 person-years.
- Primary descriptive split:
  - Non-ICD patients: SCD rates.
  - ICD patients: ICD proxy event rates.
- Formal temporal trend scale:
  - `year_decade = (Year_index - 2000) / 10`, so model estimates are interpreted per decade.

The code treats the outcome definition as cohort-specific throughout: SCD events are summarized for non-ICD patients, while the ICD cohort uses a proxy derived from ICD status and `Status == 1`.

## R Package Dependencies

The visible scripts use the following R packages:

- `dplyr`
- `readr`
- `tibble`
- `tidyr`
- `stringr`
- `ggplot2`
- `patchwork`
- `MASS`
- `broom`

There is no `renv.lock`, `DESCRIPTION`, or other dependency manifest. Reproducibility therefore depends on the user's installed package versions.

Important detail: the first section of Script 01 uses unqualified functions from several packages, including `%>%`, `transmute`, `mutate`, `case_when`, `filter`, `tibble`, `write_csv`, `str_detect`, and `str_to_lower`, before the script explicitly loads libraries in the later Script 01B section. In a clean R session, Script 01 needs the relevant libraries loaded before line 88 even though the library calls appear only later in the file.

## Script 01: Analysis Dataset Build and Table 1

File:

- `Study9/Script 01: Final EHJ dataset unchanged + calendar-time QC + minimal dataset`

Script 01 contains two logical scripts in one physical file:

1. `Script 01 v2`: builds the analysis dataset and writes QC/minimal dataset outputs.
2. `Script 01B`: reads the minimal dataset and rebuilds Table 1 with non-ICD patients split by LVEF subgroup.

### Script 01 v2 Purpose

The first section builds an analysis-ready dataset from:

```text
S:/AG/f-dhzC-profid/Data Transfer to Charite/df_handled.csv
```

It writes primary outputs under:

```text
T:/Study_9/Results_Study9/Script01_BuildAnalysisDataset_v2/
```

and also writes the downstream minimal RDS to:

```text
T:/Study_9/Results_Study9/Script01_CalendarTime_QC/df_study9_minimal.rds
```

### Required Input Columns

The script requires these source columns:

| Derived purpose | Required source column |
| --- | --- |
| ICD status | `ICD_status` |
| SCD event | `SCD_event` |
| Calendar/index year | `Time_zero_Y` |
| ICD proxy source status | `Status` |

If any of these columns are missing, the script stops.

### Auto-Detected Optional Columns

Script 01 attempts to auto-detect:

| Concept | Candidate source names |
| --- | --- |
| Person-years | `py`, `person_years` |
| Follow-up months | `ftime_mo_int`, `followup_mo`, `fu_mo` |
| Age | `Age`, `AGE`, `age`, `Age_years`, `age_yrs` |
| Sex | `Sex`, `sex`, `SEX`, `Gender`, `gender`, `Male` |
| eGFR | `eGFR`, `eGFR_num`, `egfr`, `egfr_num`, `GFR`, `gfr` |
| LVEF | `LVEF_ESC`, `LVEF`, `LVEF_percent`, `LVEF_pct`, `LVEF_baseline`, `EF`, `EjectionFraction` |
| Dataset/database | `DB`, `DBP`, `dataset`, `Database` |

If no LVEF candidate is found, the script additionally searches for names matching LVEF, EF, or ejection-fraction patterns.

### Derived Variables

The main dataset `analysis_df` includes:

| Variable | Meaning |
| --- | --- |
| `Year_index` | Integer calendar/index year from `Time_zero_Y`. |
| `ICD_bin` | Binary ICD indicator created by `to_bin01()`. |
| `SCD_bin` | Binary SCD event indicator created by `to_bin01()`. |
| `Status_num` | Integer version of `Status`. |
| `person_years` | Source person-years if available; otherwise follow-up months divided by 12; otherwise `NA`. |
| `age_num` | Numeric age if detected. |
| `sex_raw` | Raw sex value if detected. |
| `egfr_num` | Numeric eGFR if detected. |
| `lvef_num` | Numeric LVEF if detected. |
| `db_raw` / `db_grp` | Source database/dataset value if detected. |
| `ICD_proxy_bin` | `1` if `ICD_bin == 1` and `Status_num == 1`, otherwise `0`. |
| `cohort` | `"ICD"` if `ICD_bin == 1`, otherwise `"Non-ICD"`. |
| `band_2000_2020` | Calendar-time band covering 2000-2004, 2005-2009, 2010-2014, or 2015-2020. |
| `year_decade` | `(Year_index - 2000) / 10`. |
| `lvef35_grp` | `"<35%"`, `">=35%"`, or missing based on `lvef_num` and cutpoint 35. |
| `sex_bin` | Male `1`, female `0`, missing otherwise. |
| `py_valid` | `TRUE` if person-years are non-missing and positive. |
| `log_py` | Log person-years for valid person-time only. |

The script filters to `Year_index >= 2000` and `Year_index <= 2020`.

### Imputation Variables

Script 01 creates simple single-imputation fields for adjusted model support:

- `age_imp`: missing age replaced by median observed age.
- `egfr_imp`: missing eGFR replaced by median observed eGFR.
- `lvef_imp`: missing LVEF replaced by median observed LVEF.
- `sex_missing`: missingness flag for sex.
- `egfr_missing`: missingness flag for eGFR.
- `lvef_missing`: missingness flag for LVEF.
- `db_imp`: missing database/source value replaced by modal observed source and converted to factor.

The downstream Script 02 adjusted models mostly use raw detected values and complete-case filtering rather than these imputed variables. The imputed variables are still present in the minimal RDS and may be useful for alternate model specifications.

### Script 01 v2 Outputs

Under:

```text
T:/Study_9/Results_Study9/Script01_BuildAnalysisDataset_v2/
```

the script writes:

| Output | Description |
| --- | --- |
| `columns_snapshot.csv` | One-row-per-column snapshot of the input CSV column names. |
| `qc_overall.csv` | Overall counts by cohort and missingness counts for person-years, LVEF, age, sex, and eGFR. |
| `availability_by_year_and_cohort.csv` | Year/cohort counts, summed valid person-years, SCD events, and ICD proxy events. |
| `nonICD_LVEF35_group_counts.csv` | Non-ICD counts by LVEF subgroup. |
| `variable_map.csv` | Mapping from derived variables to source variables. |
| `df_study9_analysis_v2.rds` | Full analysis dataset as RDS. |
| `df_study9_analysis_v2.csv` | Full analysis dataset as CSV. |

Additionally, it writes:

```text
T:/Study_9/Results_Study9/Script01_CalendarTime_QC/df_study9_minimal.rds
```

This is the input consumed by Script 02.

### Script 01B Purpose

The second half of the file rebuilds Table 1 from:

```text
T:/Study_9/Results_Study9/Script01_CalendarTime_QC/df_study9_minimal.rds
```

Outputs go to:

```text
T:/Study_9/Results_Study9/Script01B_Table1_nonICD_LVEF35_split/
```

It builds baseline descriptive columns for:

- Non-ICD, LVEF <35%.
- Non-ICD, LVEF >=35%.
- ICD.
- Overall.

### Script 01B Table Variables

The displayed Table 1 rows include:

- Age, median (Q1, Q3).
- Sex:
  - Female, n (%).
  - Male, n (%).
- Calendar year at baseline, median (Q1, Q3).
- Calendar-time band:
  - 2000-2004.
  - 2005-2009.
  - 2010-2014.
  - 2015-2020.
- LVEF, median (Q1, Q3).
- eGFR, median (Q1, Q3).

### Script 01B Outputs

Under:

```text
T:/Study_9/Results_Study9/Script01B_Table1_nonICD_LVEF35_split/
```

the script writes:

| Output | Description |
| --- | --- |
| `variable_map_table1.csv` | Variable mapping used by the Table 1 section. |
| `group_counts_table1.csv` | Counts for Non-ICD LVEF <35%, Non-ICD LVEF >=35%, ICD, and overall. |
| `Table_1_baseline_nonICD_LVEF35_split.csv` | Excel-safe Table 1 output. |
| `Table_1_baseline_nonICD_LVEF35_split_plain.csv` | Plain CSV version of Table 1. |
| `Table_1_notes.txt` | Text notes and abbreviations for Table 1. |
| `QC_missingness_table1.csv` | Missingness counts for age, sex, eGFR, LVEF, and LVEF subgroup. |

## Script 02: Calendar-Time Summaries and Temporal Trend Models

File:

- `Study9/Script 02: Calendar-time temporal summaries (2000-2020)`

Script 02 reads:

```text
T:/Study_9/Results_Study9/Script01_CalendarTime_QC/df_study9_minimal.rds
```

and writes to:

```text
T:/Study_9/Results_Study9/Script02_TemporalTables_FormalTrend_FINAL/
```

### Input Requirements

The minimal RDS must contain:

- `Year_index`
- `ICD_bin`
- `SCD_bin`
- `ICD_proxy_bin`
- `person_years`
- `lvef35_grp`

Script 02 also tries to detect optional covariates for adjusted models:

- Age: `Age`, `age`, `Age_num`, `age_num`, `age_years`, `Age_years`
- Sex: `Sex`, `sex`, `Sex_BIN_Male`, `sex_male`, `Male`, `male`
- eGFR: `eGFR`, `egfr`, `eGFR_num`, `egfr_num`, `eGFR_log1p`, `egfr_log1p`
- LVEF: `LVEF`, `lvef`, `LVEF_num`, `lvef_num`

Rows are restricted to:

- `Year_index` in 2000-2020.
- Non-missing `ICD_bin`.
- Non-missing, positive `person_years`.

### Helper Logic

Key helpers include:

- `band_from_year()`: maps calendar year to four study bands.
- `rate_ci_poisson()`: calculates crude event rates per 1,000 person-years and exact Poisson confidence intervals using chi-square quantiles.
- `clean_lvef35_labels()`: normalizes LVEF subgroup labels to `LVEF <35%` and `LVEF >=35%`.
- `clean_sex_binary()`: normalizes sex labels to `Male` / `Female`.
- `theme_journal()`: applies a shared classic publication figure theme.
- `plot_band()` and `plot_annual()`: create band-level and annual crude-rate plots.
- `fit_rate_model()`: fits a Poisson log-link model first, calculates Pearson dispersion, and switches to `MASS::glm.nb()` negative-binomial regression if dispersion is finite and greater than 1.5.
- `extract_trend_row()`: extracts exponentiated `year_decade` model results as incidence rate ratios and percent change per decade.
- `extract_interaction_row()`: extracts LVEF subgroup interaction terms.
- `safe_lrt()`: attempts a likelihood-ratio test comparing reduced and full models.
- `derive_subgroup_trends_from_interaction()`: derives LVEF subgroup-specific trend estimates from the interaction model coefficients and variance-covariance matrix.

### Crude Primary Tables

Script 02 creates:

| Object | Cohort | Event definition | Time aggregation |
| --- | --- | --- | --- |
| `nonicd_year` | Non-ICD | `SCD_bin == 1` | Annual, with 2000-2020 grid. |
| `nonicd_band` | Non-ICD | `SCD_bin == 1` | Four calendar bands. |
| `icd_year` | ICD | `ICD_proxy_bin == 1` | Annual, with 2000-2020 grid. |
| `icd_band` | ICD | `ICD_proxy_bin == 1` | Four calendar bands. |

Annual tables are right-joined to a complete year grid, so absent years are retained with `n = 0`, `events = 0`, and `person_years = 0`.

### Non-ICD LVEF Subgroup Tables

For non-ICD patients with valid LVEF subgroup labels, Script 02 creates:

- Counts by LVEF subgroup.
- Band-level SCD rates by `LVEF <35%` versus `LVEF >=35%`.
- Annual SCD rates by LVEF subgroup.

### QC Outputs

The script specifically writes:

- `QC_nonICD_2005_denominator_artifact.csv`, reflecting the special handling/annotation of the unstable 2005 non-ICD estimate.
- `availability_by_year_and_cohort.csv`, with year/cohort counts, person-years, SCD events, and ICD proxy events.

### Script 02 Table Outputs

Under:

```text
T:/Study_9/Results_Study9/Script02_TemporalTables_FormalTrend_FINAL/
```

the script writes:

| Output | Description |
| --- | --- |
| `Table_2a_nonICD_SCD_by_band.csv` | Non-ICD SCD rates by calendar band. |
| `Table_2b_ICD_proxy_by_band.csv` | ICD proxy event rates by calendar band. |
| `Supp_nonICD_SCD_by_year.csv` | Annual non-ICD SCD rates. |
| `Supp_ICD_proxy_by_year.csv` | Annual ICD proxy rates. |
| `nonICD_LVEF35_group_counts.csv` | Non-ICD LVEF subgroup counts. |
| `Table_S_nonICD_SCD_by_band_LVEF35groups.csv` | Band-level non-ICD SCD rates by LVEF subgroup. |
| `Supp_nonICD_SCD_by_year_LVEF35groups.csv` | Annual non-ICD SCD rates by LVEF subgroup. |
| `QC_nonICD_2005_denominator_artifact.csv` | 2005 non-ICD denominator artifact QC. |
| `availability_by_year_and_cohort.csv` | Year/cohort availability and event counts. |

### Script 02 Figure Outputs

Script 02 writes PNG and PDF figures:

| Output | Description |
| --- | --- |
| `Fig1_primary_separate_cohorts_by_band.png/.pdf` | Two-panel band-level figure: non-ICD SCD and ICD proxy outcomes. |
| `FigS_primary_annual_separate_cohorts.png/.pdf` | Annual two-panel figure for ICD proxy and non-ICD SCD rates. |
| `FigS_nonICD_LVEF35groups_by_band.png/.pdf` | Band-level non-ICD SCD rates stratified by LVEF subgroup. |

Display caps are applied to annual plots:

- Non-ICD SCD annual plot cap: 25 events per 1,000 person-years.
- ICD proxy annual plot cap: 200 events per 1,000 person-years.

The non-ICD annual SCD curve is explicitly broken/annotated at 2005 because the script treats that year as unstable due to very low person-time.

### Script 02 Unadjusted Trend Models

The unadjusted model layer uses annual aggregated count data with log person-years as an offset:

```r
events ~ year_decade + offset(log(person_years))
```

Models are fit separately for:

- Non-ICD SCD.
- ICD proxy outcome.
- Non-ICD SCD with LVEF subgroup main effect.
- Non-ICD SCD with `year_decade * lvef35_grp` interaction.

The model family is selected by `fit_rate_model()`:

1. Fit Poisson model.
2. Calculate Pearson dispersion.
3. If dispersion > 1.5, refit as negative binomial.
4. Otherwise retain Poisson.

Unadjusted outputs include:

| Output | Description |
| --- | --- |
| `Formal_temporal_trend_results_main.csv` | Main non-ICD and ICD unadjusted temporal trend results. |
| `Formal_temporal_trend_nonICD_LVEF_main_effect.csv` | Non-ICD LVEF main-effect trend result. |
| `Formal_temporal_trend_nonICD_LVEF_interaction_terms.csv` | LVEF subgroup interaction term(s). |
| `Formal_temporal_trend_nonICD_LVEF_interaction_LRT.csv` | Likelihood-ratio test for interaction. |
| `Formal_temporal_trend_nonICD_LVEF_subgroup_specific.csv` | Derived subgroup-specific trend estimates. |

### Script 02 Adjusted Trend Models

Adjusted models are individual-level rate models with log person-years offsets and complete-case filtering. They are only attempted if age, sex, and eGFR are not entirely missing.

The main adjusted non-ICD model uses:

```r
SCD_bin ~ year_decade + age_num + sex_clean + egfr_num + lvef_num + offset(log(person_years))
```

If continuous LVEF is unavailable, it falls back to:

```r
SCD_bin ~ year_decade + age_num + sex_clean + egfr_num + lvef35_grp + offset(log(person_years))
```

The adjusted ICD model uses:

```r
ICD_proxy_bin ~ year_decade + age_num + sex_clean + egfr_num + offset(log(person_years))
```

The adjusted non-ICD LVEF interaction model uses:

```r
SCD_bin ~ year_decade * lvef35_grp + age_num + sex_clean + egfr_num + offset(log(person_years))
```

Adjusted outputs include:

| Output | Description |
| --- | --- |
| `Adjusted_temporal_trend_results_main.csv` | Main adjusted non-ICD and ICD trend results. |
| `Adjusted_temporal_trend_nonICD_LVEF_main_effect.csv` | Adjusted LVEF main-effect model result. |
| `Adjusted_temporal_trend_nonICD_LVEF_interaction_terms.csv` | Adjusted LVEF interaction term(s). |
| `Adjusted_temporal_trend_nonICD_LVEF_interaction_LRT.csv` | Adjusted interaction LRT. |
| `Adjusted_temporal_trend_nonICD_LVEF_subgroup_specific.csv` | Adjusted subgroup-specific derived trends. |
| `Adjusted_temporal_trend_text_ready_summary.txt` | Text-ready summary of adjusted model findings. |

### Script 02 Legend Outputs

The script writes text legend files for the main and supplementary figures:

- `Legend_Fig1_primary_separate_cohorts_by_band.txt`
- `Legend_FigS_nonICD_LVEF35groups_by_band.txt`
- `Legend_FigS_primary_annual_separate_cohorts.txt`

## Script 03: LVEF <35% Sensitivity Analysis

File:

- `Study9/Script 03: Sensitivity analysis restricted to LVEF <35% (2000-2020)`

Script 03 reads directly from:

```text
S:/AG/f-dhzC-profid/Data Transfer to Charite/df_handled.csv
```

and writes to:

```text
T:/Study_9/Results_Study9/Script03_Sensitivity_LVEFlt35_FINAL/
```

### Purpose

Script 03 repeats the broad Script 02 analysis after restricting the source data to:

- `Year_index` between 2000 and 2020.
- Non-missing LVEF.
- `LVEF < 35`.

It produces crude summaries separately for non-ICD and ICD cohorts and formal temporal trend analyses in the restricted population.

### Required and Auto-Detected Columns

Required fixed columns:

| Concept | Source column |
| --- | --- |
| ICD status | `ICD_status` |
| SCD event | `SCD_event` |
| Calendar/index year | `Time_zero_Y` |
| ICD proxy status source | `Status` |

Auto-detected optional columns:

| Concept | Candidate source names |
| --- | --- |
| Person-years | `py`, `person_years` |
| Follow-up months | `ftime_mo_int`, `followup_mo`, `fu_mo` |
| LVEF | `LVEF_ESC`, `LVEF`, `LVEF_percent`, `LVEF_pct`, `LVEF_baseline`, `EF`, `EjectionFraction` |
| Age | `Age`, `Age_num`, `Age_years`, `baseline_age`, `Age_baseline` |
| Sex | `Sex`, `sex`, `Gender`, `gender`, `Sex_BIN_Male`, `Male` |
| eGFR | `eGFR`, `eGFR_num`, `eGFR_baseline`, `eGFR_MDRD`, `egfr` |

The script has fallback pattern matching for LVEF, age, sex, and eGFR if the candidate lists do not find a column. Unlike Script 01, Script 03 stops if no LVEF variable can be detected.

### Derived Dataset

Script 03 derives:

| Variable | Meaning |
| --- | --- |
| `Year_index` | Integer calendar/index year. |
| `ICD_bin` | Binary ICD indicator. |
| `SCD_bin` | Binary SCD event indicator. |
| `Status_num` | Integer status. |
| `LVEF_num` | Numeric LVEF. |
| `age_num` | Numeric age if detected. |
| `male_bin` | Male `1`, female `0`, missing otherwise. |
| `egfr_num` | Numeric eGFR if detected. |
| `person_years` | Person-years from source, or follow-up months divided by 12. |
| `ICD_proxy_bin` | `1` if ICD patient and `Status_num == 1`, otherwise `0`. |
| `cohort` | `"ICD"` or `"Non-ICD"`. |

The restricted dataset is saved only indirectly through summary outputs; there is no RDS export for the full restricted analytic dataset.

### Sensitivity QC Output

The restriction impact table is written as:

```text
restriction_impact_2000_2020_lvef_lt35.csv
```

It contains:

- Total restricted N.
- Non-ICD N.
- ICD N.
- Total SCD events.
- Total ICD proxy events.
- Missing person-years count.
- Non-positive person-years count.

### Sensitivity Crude Summary Outputs

Script 03 creates annual and band-level summaries:

| Output | Description |
| --- | --- |
| `SCD_by_year_nonICD_LVEFlt35_2000_2020.csv` | Annual non-ICD SCD rates in LVEF <35%. |
| `ICD_proxy_by_year_ICD_LVEFlt35_2000_2020.csv` | Annual ICD proxy rates in LVEF <35%. |
| `SCD_by_band_nonICD_LVEFlt35_2000_2020.csv` | Band-level non-ICD SCD rates in LVEF <35%. |
| `ICD_proxy_by_band_ICD_LVEFlt35_2000_2020.csv` | Band-level ICD proxy rates in LVEF <35%. |
| `Table_S2_LVEFlt35_combined.csv` | Word-ready combined table containing both non-ICD SCD and ICD proxy band summaries. |

Annual summaries include additional descriptive means where available:

- `age_mean`
- `male_prop`
- `egfr_mean`
- `lvef_mean`

### Sensitivity Figure Outputs

Script 03 writes:

| Output | Description |
| --- | --- |
| `Fig_S3_two_panels_by_band_LVEFlt35.png/.pdf` | Two-panel band-level crude-rate figure for ICD proxy and non-ICD SCD outcomes in LVEF <35%. |
| `Fig_Supp_annual_two_panels_LVEFlt35.png/.pdf` | Two-panel annual crude-rate figure in LVEF <35%. |

The annual non-ICD SCD curve uses the same 2005 denominator-artifact annotation/break logic as Script 02.

### Sensitivity Temporal Trend Models

Unadjusted models use annual aggregated event counts with log person-years offsets:

```r
events ~ year_decade + offset(log(person_years))
```

This is run separately for:

- Non-ICD SCD.
- ICD proxy outcome.

Adjusted models are also annual aggregated models. The script aggregates covariates by year, then fits:

Non-ICD:

```r
events ~ year_decade + age_mean + male_prop + egfr_mean + lvef_mean + offset(log(person_years))
```

ICD:

```r
events ~ year_decade + age_mean + male_prop + egfr_mean + offset(log(person_years))
```

The adjusted model helper first builds a model frame with complete cases and skips fitting if fewer than eight rows remain. As in Script 02, Poisson models are fit first and replaced by negative-binomial models if Pearson dispersion exceeds 1.5.

Trend outputs:

| Output | Description |
| --- | --- |
| `Formal_temporal_trend_unadjusted_LVEFlt35.csv` | Unadjusted trend results for non-ICD and ICD cohorts. |
| `Formal_temporal_trend_adjusted_LVEFlt35.csv` | Adjusted trend results, if model fitting succeeds. |
| `Formal_temporal_trend_all_LVEFlt35.csv` | Combined unadjusted and adjusted trend results. |
| `Formal_temporal_trend_LVEFlt35_text_ready_summary.txt` | Word-ready textual trend summary. |

Legend outputs:

- `Legend_Fig_S3_LVEFlt35.txt`
- `Legend_Fig_Supp_annual_LVEFlt35.txt`

## Model Interpretation

Across Scripts 02 and 03, the main model term is `year_decade`. Since it is defined as `(Year_index - 2000) / 10`, exponentiated model coefficients are incidence rate ratios per decade. The scripts also calculate:

- `irr`: exponentiated estimate.
- `lcl` / `ucl`: exponentiated confidence interval limits.
- `p_value`: model p-value for the term.
- `pct_change_per_decade`: `(IRR - 1) * 100`.
- `pct_change_lcl` / `pct_change_ucl`: confidence interval on the percent-change scale.

Models include `offset(log(person_years))`, so they are rate models rather than simple event-probability models.

## Important Implementation Details

### Calendar Bands Are Not Fully Label-Consistent

Script 01 initially creates band labels with en dashes, such as `2000-2004` rendered with Unicode dash variants in the source. Script 02 and Script 01B normalize or recreate labels using plain hyphen strings in places. The code handles much of this internally, but downstream manual comparisons should be careful about label variants.

### LVEF Labels Are Normalized Downstream

Script 01 creates factor levels resembling `>=35%` and `<35%` in one place, while Script 02 normalizes to `LVEF >=35%` and `LVEF <35%`. Script 01B also normalizes labels before grouping. This is intentional defensive handling, but it means exact factor labels differ across intermediate objects.

### ICD Proxy Definition Is Central

The ICD cohort event is not read as a direct appropriate-therapy variable. It is derived as:

```r
ICD_proxy_bin = ifelse(ICD_bin == 1L & Status_num == 1L, 1L, 0L)
```

This definition should be checked against the statistical analysis plan and source-data semantics for `Status`.

### Person-Time Handling

Person-years are taken from `py` or `person_years` when available. If unavailable, scripts derive person-years from follow-up months divided by 12. Rows with missing or non-positive person-years are excluded from Script 02 analytic models and rate summaries. Script 01 keeps such rows but flags them with `py_valid`.

### 2005 Non-ICD Denominator Artifact

Scripts 02 and 03 explicitly annotate the 2005 non-ICD annual SCD estimate as unstable due to very low person-time. In annual figures, the curve is broken at 2005 and a dashed line/note is added.

### Poisson vs Negative Binomial Switching

The model helper chooses negative-binomial regression when Poisson Pearson dispersion exceeds 1.5. This is a pragmatic overdispersion rule, but it means model family can differ by outcome or subgroup depending on the data.

### Script 01 Combines Two Workflows

Script 01 is both a dataset-builder and a Table 1 builder. It reloads packages and resets path variables in the second half. This is functional but less modular than separate `01_build_dataset.R` and `01B_table1.R` files would be.

### Script 03 Is Partly Independent of Script 01

Script 03 does not use `df_study9_minimal.rds`. It reconstructs the required fields from the raw handled CSV. This improves independence for sensitivity analysis but creates duplicate derivation logic for binary coding, LVEF detection, person-year derivation, and model helpers.

## Reproducibility and Portability Gaps

The code parses successfully as R code, but several reproducibility issues are visible from static inspection:

1. Hard-coded Windows/network paths are required:
   - `S:/AG/f-dhzC-profid/Data Transfer to Charite`
   - `T:/Study_9`
2. The input data file `df_handled.csv` is not present in this repository.
3. No dependency manifest is included.
4. Script files have no `.R` extension, which may make editor tooling, linting, and batch execution less convenient.
5. Script 01 uses `dplyr`, `readr`, `tibble`, and `stringr` functions before explicitly loading those packages in the visible file.
6. Outputs are written outside the repository, so this checkout does not capture generated tables, figures, logs, or model results.
7. Model fitting is not wrapped in a single pipeline driver; the user must run scripts in the correct order, with Script 01 before Script 02.
8. The same helper logic is duplicated across scripts rather than sourced from a shared helper file.
9. There is no automated verification layer, such as unit tests, snapshot checks, or expected-output checks.
10. There is no code-level provenance capture of package versions, R version, or input file hash.

## Recommended Execution Order

In the intended Windows/R environment:

1. Ensure required packages are installed and loaded.
2. Ensure `S:/AG/f-dhzC-profid/Data Transfer to Charite/df_handled.csv` exists.
3. Run Script 01 to build the analysis dataset and `df_study9_minimal.rds`.
4. Run the Script 01B section, or run the full Script 01 file if package loading/order issues are handled.
5. Run Script 02 for the main 2000-2020 temporal summaries and models.
6. Run Script 03 for the LVEF <35% sensitivity analysis.

## Suggested Refactoring Opportunities

The current code is understandable and mostly organized by analysis step, but it would become more reproducible and maintainable with:

- File extensions changed to `.R`.
- Separate files for Script 01 dataset build and Script 01B Table 1.
- A shared helper script for:
  - Binary conversion.
  - Sex cleaning.
  - LVEF label normalization.
  - Calendar band construction.
  - Poisson confidence intervals.
  - Poisson/negative-binomial model fitting.
  - Trend-result extraction.
- A central path/config file for input root, output root, years, LVEF cutpoint, and display caps.
- Explicit package loading at the top of every script before helper or pipeline code.
- A small run log that records input file path, timestamp, row counts, R version, and package versions.
- A project-level dependency lockfile such as `renv.lock`.
- Optional output validation checks confirming that key CSV/PDF/PNG/RDS files were created and non-empty.

## Static Validation Performed

During this codebase review, all three script files were parsed with `Rscript parse()` and returned `parse_ok`. The scripts were not executed end to end because their required `S:/` and `T:/` data/output drives are environment-specific and the raw input data is not present in this repository.
