# Study 3 Consolidated Changelog

## Purpose and Scope

This document consolidates:

- substantive preprocessing and statistical-analysis changes identified from
  the Git commit history and current workspace state of the `Study3/` analysis
  scripts; and
- the HPC, local-execution, plotting, diagnostics, and output adaptations
  previously documented in `Changelog_HPC_Adaptations.md`.

Path and file-directory adaptations are documented separately from analytical
changes. They are not classified as changes to the analysis.

The original uploaded Study 3 scripts are used as the analytical baseline.

## Executive Summary

Most changes made while adapting Study 3 for HPC execution concern paths,
runner infrastructure, diagnostics, plot presentation, and output handling.
However, the Git history and current workspace state also contain significant
preprocessing, cohort filtering, endpoint-classification, and
statistical-model changes.

The most consequential analytical changes are:

1. Israel follow-up and mortality information are now supplemented with a
   validated Israel endpoint dataset.
2. Israel date parsing was revised to support additional formats and to remove
   forced conversion of pre-2000 dates to 20xx.
3. Records without valid positive survival follow-up are now excluded more
   consistently from survival analyses.
4. Competing deaths in the primary Fine-Gray analysis are now identified
   case-insensitively.
5. Dataset-adjusted Fine-Gray models were added to the primary and 180-day
   sensitivity analyses.
6. Inappropriate-shock event derivation was centralized and persisted across
   the pipeline.
7. The 180-day sensitivity cohort is now restricted using analyzed endpoint
   time rather than total follow-up, excluding early inappropriate shocks that
   were previously retained.

The earlier statement that no statistical logic, filtering rule, endpoint
classification, or transformation changed applied to the initial HPC port, but
does not describe all later commits. In particular, commit `b790195` introduced
material preprocessing and analysis-inclusion changes.

---

# Part I: Significant Preprocessing and Analysis Changes

## Chronological Overview

| Date | Commit | Category | Significant change | Analytical impact |
|---|---|---|---|---|
| 2026-05-30 | `2a34956` | Endpoint preprocessing | Centralized and persisted inappropriate-shock event derivation | Ensures downstream analyses consistently contain and derive the event variable |
| 2026-05-30 | `e510e56` | Cohort filtering | Added valid survival-input filtering before KM and Fine-Gray analyses | Removes participants without usable follow-up or device group |
| 2026-06-04 | `282cc58` | Statistical model | Added dataset-adjusted Fine-Gray models | Adds dataset-adjusted device-effect estimates |
| 2026-06-07 | `b790195` | Israel preprocessing | Supplemented Israel follow-up and mortality using validated endpoint data | Changes Israel follow-up times, death status, and survival eligibility |
| 2026-06-07 | `b790195` | Date preprocessing | Replaced Israel date-parsing logic | Supports more formats and stops forced conversion of pre-2000 dates |
| 2026-06-07 | `b790195` | Survival analysis | Added positive-follow-up exclusions to secondary Cox analyses and corrected primary Fine-Gray death coding | Changes secondary-model populations and competing-event counts |
| 2026-06-09 | `working tree` | Sensitivity cohort definition | Corrected the 180-day sensitivity restriction to use analyzed endpoint time | Excludes early inappropriate shocks that had total follow-up >= 180 days but event time < 180 days |

## 1. Inappropriate-Shock Event Derivation Centralized and Persisted

**Commit:** `2a34956`  
**Affected files:** `study3_paths.R` and analysis scripts `07` through `12`

The existing inappropriate-shock derivation was moved from
`08_Cox models.R` into the shared helper:

```r
study3_add_inapp_shock_event(dt)
```

The helper:

- creates `inapp_shock_flag_std` using
  `tolower(trimws(as.character(inapp_shock_flag)))`;
- creates `event_inapp_shock`, with `"yes"` coded as `1` and `"no"`,
  `"unknown"`, missing, and unrecognized values coded as `0`; and
- sets `days_to_inapp_shock` equal to `t_followup_days_final` when a recorded
  inappropriate-shock time exceeds final follow-up.

The helper is called before saving `study3_analysis_final.rds` and after that
dataset is loaded by downstream analysis scripts.

### Impact

The intended endpoint rule was not changed by this commit. The significant
change is that the endpoint derivation is now reusable, persistent, and
consistently available to resumed or separately executed analysis steps.

## 2. Invalid Survival Inputs Explicitly Excluded

### Primary Kaplan-Meier and Fine-Gray Analyses

**Commit:** `e510e56`  
**Affected file:** `09_Kaplan Maier and Fine Gray.R`

Before Kaplan-Meier, log-rank, cumulative-incidence, and Fine-Gray analyses,
records are now excluded when they have:

- missing `t_followup_days_final`;
- non-finite `t_followup_days_final`;
- `t_followup_days_final <= 0`; or
- missing `device_group`.

The script also prints a QC table of excluded records by dataset and reason.

The available June 7 debug run excluded 76 records:

| Dataset | Exclusion reason | Records |
|---|---|---:|
| HELIOS | Non-positive follow-up | 42 |
| HELIOS | Missing follow-up | 27 |
| ISRAEL | Missing follow-up | 7 |

### Secondary Cox Analyses

**Commit:** `b790195`  
**Affected file:** `10_secondary analysis.R`

The requirement `t_followup_days_final > 0` was added to:

- univariable Cox screening;
- the multivariable complete-case Cox analysis; and
- subgroup interaction analyses.

Previously, these analyses required complete cases but did not explicitly
exclude zero or negative follow-up.

### Impact

These are analysis-population changes. They alter model sample sizes and can
alter estimates, confidence intervals, and p values. The excluded records
cannot validly contribute time at risk to the corresponding survival models.

## 3. Dataset-Adjusted Fine-Gray Models Added

**Commit:** `282cc58`  
**Affected files:**

- `09_Kaplan Maier and Fine Gray.R`
- `11_sensitivty analysis (180 days).R`

The original device-only Fine-Gray model remains in place. A second model was
added using:

```r
X_dataset <- model.matrix(~ device_group + dataset, data = ...)[, -1, drop = FALSE]

crr(
  ftime = ...,
  fstatus = ...,
  cov1 = X_dataset,
  cengroup = dataset
)
```

The additional model:

- includes dataset as fixed-effect covariates; and
- estimates dataset-specific censoring distributions through `cengroup`.

It is run for both:

- the primary Fine-Gray analysis; and
- the minimum-180-day follow-up sensitivity analysis.

The following result files are written:

- `finegray_primary_device_results.csv`
- `finegray_sens_min180d_device_results.csv`

Each file contains the original device-only estimate and the dataset-adjusted
estimate for `device_groupSingle`, including event counts, log-sHR, sHR,
95% confidence interval, p value, and included datasets.

### Impact

This is a new statistical model and produces an additional dataset-adjusted
device-effect estimate. It is correctly described as a dataset-adjusted
Fine-Gray model, not as a literal `strata(dataset)` Cox model.

## 4. Israel Follow-Up and Mortality Supplemented from Validated Endpoint Data

**Commit:** `b790195`  
**Affected files:**

- `03_israel_initial_cleaning.R`
- `06_Dataset_merging_updated.R`
- `07_Descriptive_Table1_Table2.R`

Israel follow-up was previously derived from implant, death, and
last-follow-up dates. Because implant dates in the raw Israel extract are
sparse, date subtraction cannot recover usable follow-up for most Study 3
participants.

The preprocessing script now joins the validated Israel endpoint file:

```text
datasets/local/israeli-icd/data/working/03-stage-1-endpoints-and-comp-risks.csv
```

The following fields are used:

- `Alive_last_FU_days`
- `Status_death`

After joining by patient ID, the script:

- creates `t_followup_days_israel`;
- overrides `t_followup_days` when validated positive follow-up is available;
- overrides `death_flag` when validated death status is available; and
- assigns validated follow-up to `days_to_death` for deaths.

The merge step now stops when matched Israel records exist but none have
positive follow-up, preventing silent continuation with an unusable Israel
survival cohort.

### Impact

This is the most substantial preprocessing change. It can change:

- Israel follow-up times;
- Israel mortality status;
- competing-event classification;
- the number of Israel records eligible for survival analyses; and
- all survival estimates that include Israel.

## 5. Final Israel Follow-Up Assignment Now Has a Fallback

**Commit:** `b790195`  
**Affected file:** `07_Descriptive_Table1_Table2.R`

Previously, `t_followup_days_final` was initialized as missing and Israel
records received only `t_followup_days_israel`. Israel records without that
specific field remained missing even when standard `t_followup_days` existed.

The current logic:

1. initializes `t_followup_days_final` from `t_followup_days` for all datasets;
2. overrides it with `t_followup_days_israel` for Israel when the validated
   value is available.

### Impact

This increases the number of Israel participants that can have usable final
follow-up and directly affects survival-analysis eligibility.

## 6. Israel Date Parsing Revised

**Commit:** `b790195`  
**Affected file:** `03_israel_initial_cleaning.R`

The new `parse_israel_date()` helper attempts the following formats:

```text
%b %d, %Y
%d-%b-%y
%d%b%Y
%Y-%m-%d
```

The previous implementation also converted every successfully parsed date
before 2000 into a date after 2000. That forced-century conversion was removed.

### Impact

This can change implant, death, and last-follow-up dates. It supports additional
raw formats and prevents valid pre-2000 dates from automatically becoming 20xx
dates.

## 7. Primary Fine-Gray Competing-Death Coding Corrected

**Commit:** `b790195`  
**Affected file:** `09_Kaplan Maier and Fine Gray.R`

Previously, a competing death was recognized only when:

```r
death_flag == "Yes"
```

The primary Fine-Gray analysis now uses:

```r
tolower(trimws(as.character(death_flag))) == "yes"
```

This recognizes differently capitalized values and values containing
surrounding whitespace.

The available debug output showed why this matters:

- EU-CERT had 329 case-insensitive deaths but zero exact `"Yes"` values.
- Israel had 126 case-insensitive deaths but zero exact `"Yes"` values.

### Impact

This materially changes competing-event classification in the primary
Fine-Gray analysis and can materially change its estimates.

## 8. 180-Day Sensitivity Restriction Corrected To Use Endpoint Time

**Commit:** `working tree`  
**Affected file:** `11_sensitivty analysis (180 days).R`

The minimum-180-day sensitivity cohort was previously defined as:

```r
dt_sens_6mo <- dt_final[t_followup_days_final >= min_fu_days]
```

This used total follow-up to determine eligibility, even though inappropriate
shock cases are timed in the analysis by `t_inapp_shock_or_censor_days`, which
uses actual shock time for events and follow-up time for censoring.

As a result, patients with:

- total follow-up of at least 180 days; but
- an actual inappropriate shock before day 180

were incorrectly retained in the 180-day sensitivity cohort.

The cohort definition is now:

```r
dt_sens_6mo <- dt_final[
  !is.na(t_inapp_shock_or_censor_days) &
    t_inapp_shock_or_censor_days >= min_fu_days
]
```

The QC block in the same script was also expanded to report:

- records below 180 days by total follow-up;
- records below 180 days by analyzed endpoint time;
- shock cases with actual shock time before 180 days;
- shock cases excluded by the corrected rule; and
- shock cases missed by the previous follow-up-based rule.

Local verification against `study3_analysis_final.rds` showed:

- old cohort: 2,853 patients, 73 inappropriate shocks;
- corrected cohort: 2,837 patients, 57 inappropriate shocks; and
- 16 inappropriate-shock cases removed because shock time was before day 180
  despite total follow-up of at least 180 days.

### Impact

This is a substantive cohort-definition correction in the 180-day sensitivity
analysis. It changes the analyzed population and event count so that the
sensitivity restriction now matches the manuscript statement that patients must
have at least 180 days before the analyzed endpoint.

---

# Part II: HPC, Execution, Diagnostics, and Output Adaptations

## Initial HPC Port

**Commit:** `e2d00b8`

Study 3 was adapted to run on the PROFID HPC using:

- central path handling in `study3_paths.R`;
- reusable derived data under `data/derived/Study3`;
- human-facing outputs under `Study3/outputs`;
- a master runner in `master_run.R`; and
- a Slurm wrapper in `run_study3.sh`.

The initial HPC port changed path resolution, execution orchestration, and
output locations. It did not intentionally change cohort definitions,
endpoint definitions, transformations, model formulas, or statistical
methods.

## Raw File Mapping

The original scripts requested short local filenames that do not exist under
those names in the HPC data tree. `study3_paths.R` maps those aliases to the
actual files.

| Study 3 requested file | Path relative to the selected data root |
|---|---|
| `eu-cert-icd.csv` | `datasets/local/eu-cert-icd/data/original/registry_data_eu-cert-icd_selection_161019-Data-sheet.csv` |
| `Helius.xlsx` | `datasets/local/helios-rdb/data/original/Final_delivery.2021-05-20._Ali EDxlsx.xlsx` |
| `israeli.csv` | `datasets/local/israeli-icd/data/original/ICDALL_20170630.csv` |
| `prose.xlsx` | `datasets/local/prose-icd/data/original/FinaltoPROFID_PROSEonlysent_no_password.xlsx` |
| `LCV.xlsx` | `datasets/local/prose-lvscd/data/original/FinaltoPROFID_LVSCDonlySent_no_password.xlsx` |
| `PROSE_LCVcommon participant.csv` | `datasets/local/prose-icd/data/original/FinaltoPROFID_PROSEonlysent_coenrolled.csv` |
| `ICD.csv` | HPC: `Data_Transfer_to_Charite/ICD.csv`; local: `Data Transfer to Charite/ICD.csv` |
| `02_small_map.xlsx` | Repository path: `Study3/02_small_map.xlsx` |

For EU-CERT, Study 3 uses the original registry file. It does not use the
Study 1 derived CDM-ready output because that file has already undergone
Study 1-specific preprocessing.

These mappings are path and input-location adaptations, not analytical
changes.

## Path Validation

From the repository root, validate the default/HPC raw-file mappings with:

```bash
Rscript -e 'source("Study3/study3_paths.R"); files <- c("eu-cert-icd.csv","Helius.xlsx","israeli.csv","prose.xlsx","LCV.xlsx","PROSE_LCVcommon participant.csv"); for (f in files) cat(f, "->", study3_raw_path(f), file.exists(study3_raw_path(f)), "\n")'
```

Validate a local data root with:

```bash
PROFID_DATA_ROOT=/Users/PROFID_RAW_DATA PROFID_STUDY3_DERIVED_ROOT=/Users/PROFID_RAW_DATA/derived/Study3 Rscript -e 'source("Study3/study3_paths.R"); files <- c("eu-cert-icd.csv","Helius.xlsx","israeli.csv","prose.xlsx","LCV.xlsx","PROSE_LCVcommon participant.csv"); for (f in files) cat(f, "->", study3_raw_path(f), file.exists(study3_raw_path(f)), "\n"); cat("ICD.csv ->", profid_transfer_path("ICD.csv"), file.exists(profid_transfer_path("ICD.csv")), "\n"); cat("Derived datasets ->", study3_derived_root(), "\n")'
```

Each required raw file should resolve to an existing file and print `TRUE`.

## Local Execution Mode

`master_run.R` supports an opt-in local mode:

```bash
Rscript Study3/master_run.R --local
```

Local mode selects the configured local raw-data and derived-data roots. It can
be combined with debugging, dry runs, stages, and step selection:

```bash
Rscript Study3/master_run.R --local --debugging
Rscript Study3/master_run.R --local --dry-run
Rscript Study3/master_run.R --local --from preprocess_israel --to km_fine_gray --debugging
```

This changes path configuration only.

## Detailed Debugging Output

**Commit:** `7aa70cb`

The runner accepts:

```bash
Rscript Study3/master_run.R --debugging
```

The Slurm wrapper forwards the same option:

```bash
./Study3/run_study3.sh --debugging
```

Debug mode reports:

- Israel raw and harmonized date fields;
- representative Israel date strings before parsing;
- parsed dates, derived follow-up, events, and deaths;
- source fields before merging and Israel fields after merging;
- transfer into `t_followup_days_final`;
- dataset-specific Cox exclusions and final Cox input; and
- Fine-Gray exclusions, event coding, included datasets, reference level, and
  design-matrix columns.

Debugging changes reporting only. It does not modify input values, endpoint
definitions, cohort rules, filters, model formulas, or statistical methods.

## Headless Plot Saving

**Commit:** `c5cdf79`

The 180-day sensitivity script previously used direct base-R `png()` calls,
which can fail on headless compute nodes.

The direct calls were replaced with `study3_save_grid()`, which:

- writes the same plots and PNG filenames;
- additionally writes PDF copies; and
- attempts headless-safe graphics devices.

This changes only how completed plots are written to disk.

## Figure 1 Kaplan-Meier Output Adaptations

**Relevant commits:** `f9cc956`, `b2e45f2`, `59d9dad`, `6ea34ed`,
`5f7044f`, `f683ae8`, `282cc58`, and `1b771f3`

Figure 1 was revised to:

- display follow-up through 2,200 days and label the x-axis in years;
- use a full 0.00-to-1.00 main y-axis;
- include a substantially enlarged untitled zoom inset;
- display single-lead devices as a blue solid curve and double-lead devices as
  a red dashed curve;
- add semi-transparent 95% confidence-interval ribbons around both Kaplan-Meier
  curves in the main panel and inset;
- add and refine a Study 1-style number-at-risk table as a separate lower
  panel;
- manually draw thinner censoring marks, with separate smaller tick styling in
  the inset;
- move the legend and log-rank annotation into the left side of the inset, with
  the log-rank label placed below the legend and aligned to the legend line
  symbols;
- enlarge and reposition the inset to keep the zoomed curves, confidence
  ribbons, legend, and annotation readable; and
- harmonize spacing, labels, and typography so the main axes, inset axes,
  legend, log-rank annotation, x-axis title, and numbers-at-risk use a
  consistent larger text size;
- save PNG and PDF copies; and
- export the underlying curve and risk-table data to CSV.

A cumulative-incidence Figure 2 was also added.

These are presentation and output changes. They do not change the underlying
Kaplan-Meier fit, log-rank test, cumulative-incidence calculation, Fine-Gray
event coding, or model results.

## Timestamped Logs and Output Directory Changes

**Relevant commits:** `a89ccf3` and `0c14e1b`

The master runner writes timestamped logs and standardizes the output directory
as `Study3/outputs`.

These are execution and file-organization changes only.

---

# Part III: Changes Excluded from the Analytical Change List

The following reviewed changes are not classified as changes to preprocessing
rules, analysis populations, endpoints, or statistical models:

- HPC and local path handling;
- raw-file alias mapping;
- master-runner and Slurm infrastructure;
- timestamped logs;
- output-directory capitalization;
- debug diagnostics and QC printing;
- headless graphics-device handling;
- plot colors, labels, censor marks, insets, risk-table styling, and layout;
- plot-data CSV exports;
- display-only Figure 1 truncation; and
- initial script uploads that establish the baseline.

## Documentation Note

`Changelog_HPC_Adaptations.md` documented the initial HPC adaptations, endpoint
persistence, KM/Fine-Gray filtering, plotting changes, diagnostics, and
dataset-adjusted Fine-Gray models. It did not document the later substantive
changes introduced by commit `b790195`.

Accordingly, this consolidated changelog supersedes the earlier broad statement
that no filtering rule, endpoint classification, transformation, or
statistical-analysis logic changed.

---

# Running Study 3

Default/HPC dry run:

```bash
Rscript Study3/master_run.R --dry-run
```

Default/HPC full run:

```bash
Rscript Study3/master_run.R
```

Slurm wrapper:

```bash
./Study3/run_study3.sh
```

Local dry run:

```bash
Rscript Study3/master_run.R --local --dry-run
```

Local full run:

```bash
Rscript Study3/master_run.R --local
```

Local full run with detailed diagnostics:

```bash
Rscript Study3/master_run.R --local --debugging
```
