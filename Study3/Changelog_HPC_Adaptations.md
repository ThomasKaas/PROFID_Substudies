# Changelog: HPC Adaptations for Study 3

## Purpose

Study 3 was adapted to run on the PROFID HPC using the same execution pattern as Study 1:

- central path handling in `study3_paths.R`
- reusable derived data under `data/derived/Study3`
- human-facing outputs under `Study3/outputs`
- a master runner in `master_run.R`
- a Slurm wrapper in `run_study3.sh`

No statistical analysis logic, model formula, filtering rule, endpoint definition, or transformation was intentionally changed.

## Raw Data Path Issue

The original Study 3 scripts used short local filenames such as `eu-cert-icd.csv`, `Helius.xlsx`, and `prose.xlsx`.
These files do not exist under those names in the HPC data tree.

The real source files are stored in dataset-specific folders under:

```text
data/datasets/local/<dataset>/data/original/
```

To keep the Study 3 scripts unchanged, `study3_paths.R` now maps the short Study 3 filenames to the actual HPC files.

## Raw File Mapping

| Study 3 requested file | Actual HPC file now loaded |
|---|---|
| `eu-cert-icd.csv` | `data/datasets/local/eu-cert-icd/data/original/registry_data_eu-cert-icd_selection_161019-Data-sheet.csv` |
| `Helius.xlsx` | `data/datasets/local/helios-rdb/data/original/Final_delivery.2021-05-20._Ali EDxlsx.xlsx` |
| `israeli.csv` | `data/datasets/local/israeli-icd/data/original/ICDALL_20170630.csv` |
| `prose.xlsx` | `data/datasets/local/prose-icd/data/original/FinaltoPROFID_PROSEonlysent_no_password.xlsx` |
| `LCV.xlsx` | `data/datasets/local/prose-lvscd/data/original/FinaltoPROFID_LVSCDonlySent_no_password.xlsx` |
| `PROSE_LCVcommon participant.csv` | `data/datasets/local/prose-icd/data/original/FinaltoPROFID_PROSEonlysent_coenrolled.csv` |
| `ICD.csv` | `data/Data_Transfer_to_Charite/ICD.csv` |
| `02_small_map.xlsx` | `Study3/02_small_map.xlsx` |

## Important Note

For EU-CERT, the correct Study 3 input is the original registry file:

```text
data/datasets/local/eu-cert-icd/data/original/registry_data_eu-cert-icd_selection_161019-Data-sheet.csv
```

Do not use the Study 1 derived output:

```text
data/derived/Study1/EUCID/eu_cert_icd_cdm_ready.csv
```

That file is already processed for Study 1 and is not the raw input expected by the Study 3 cleaning script.

## Event Variable Helper

The HPC run failed in `Study3/09_Kaplan Maier and Fine Gray.R` with:

```text
Error: object 'event_inapp_shock' not found
```

The reason was a pipeline persistence issue, not a statistical issue. The variable `event_inapp_shock` was originally created inside `Study3/08_Cox models.R`, but later scripts reload `study3_analysis_final.rds`. That saved RDS did not contain `event_inapp_shock`, so scripts `09` to `12` could fail when run after `08` or when resumed from an intermediate step.

To fix this without changing the analysis method, the original endpoint derivation from `Study3/08_Cox models.R` was moved unchanged into the shared helper `study3_add_inapp_shock_event()` in `Study3/study3_paths.R`.

Original logic:

```r
dt[, inapp_shock_flag_std :=
     tolower(trimws(as.character(inapp_shock_flag)))]

dt[, event_inapp_shock :=
     fifelse(inapp_shock_flag_std == "yes", 1L, 0L, na = 0L)
]

dt[
  event_inapp_shock == 1 &
    !is.na(days_to_inapp_shock) &
    days_to_inapp_shock > t_followup_days_final,
  days_to_inapp_shock := t_followup_days_final
]
```

Current shared implementation:

```r
study3_add_inapp_shock_event(dt)
```

This helper performs the same three operations:

- creates `inapp_shock_flag_std` as `tolower(trimws(as.character(inapp_shock_flag)))`
- creates `event_inapp_shock` using the same rule: `yes = 1`, `no`, `unknown`, and missing values = `0`
- applies the same event-time guard: if `days_to_inapp_shock` is later than `t_followup_days_final`, it is set to `t_followup_days_final`

The QC line remains in `Study3/08_Cox models.R`:

```r
dt[, .N, by = .(dataset, event_inapp_shock)]
```

The helper is now called before saving `study3_analysis_final.rds` in `Study3/07_Descriptive_Table1_Table2.R`, so the derived dataset contains the endpoint expected by later scripts. It is also called after loading the RDS in scripts `08` to `12`, so resumed HPC runs use the same endpoint definition even if the RDS was generated before this fix.

This does not change any statistical analysis logic, model formula, filtering rule, covariate set, endpoint definition, or transformation. It only makes the pre-existing endpoint derivation reusable and persistent across the pipeline.

## KM/Fine-Gray Follow-Up Check

After the endpoint persistence fix, the HPC run reached `Study3/09_Kaplan Maier and Fine Gray.R` and then failed with:

```text
Error: all(!is.na(dt_final$t_followup_days_final)) is not TRUE
```

This was another data-contract issue. `study3_analysis_final.rds` is also used for descriptive output and can still contain rows where final follow-up time is missing or not usable for time-to-event analysis. Those rows cannot contribute to Kaplan-Meier, log-rank, Fine-Gray, or cumulative-incidence calculations because all of those require a valid positive follow-up time.

`Study3/08_Cox models.R` already applies the same analysis-readiness requirement before Cox modelling:

```r
dt <- dt[t_followup_days_final > 0]
```

The fix in `Study3/09_Kaplan Maier and Fine Gray.R` makes that requirement explicit before the KM/Fine-Gray analyses:

- keep only rows with non-missing, finite, positive `t_followup_days_final`
- keep only rows with non-missing `device_group`
- print a small QC table showing any excluded rows by dataset and reason

In simple words: the script now removes records that have no usable time-at-risk before running survival and competing-risk functions. These records could not be analyzed by these methods anyway. No model formula, event definition, competing-risk definition, statistical method, or cohort rule was changed.

## Headless Plot Saving In 180-Day Sensitivity Script

The next HPC run reached `Study3/11_sensitivty analysis (180 days).R` and failed while saving the Kaplan-Meier sensitivity plot:

```text
Error: unable to start device PNG
```

This was an HPC graphics-device issue. The script used base R `png()` directly, but compute nodes often run without an interactive graphical display. The analysis had already completed up to the plot-saving step.

The fix replaces the two direct `png()` calls in `Study3/11_sensitivty analysis (180 days).R` with the existing helper `study3_save_grid()` from `Study3/study3_paths.R`.

In simple words:

- the same Kaplan-Meier and cumulative-incidence plots are drawn
- the same filenames for PNG outputs are used
- a PDF copy is also written for each plot
- the helper tries headless-safe graphics devices such as Cairo, `ragg`, or Ghostscript-backed bitmap output

No statistical analysis logic was changed. The Cox model, log-rank test, Fine-Gray model, event coding, 180-day filter, plot contents, labels, colors, and line widths remain the same. Only the way the completed plots are written to disk was made compatible with the HPC environment.

## Figure 1 Kaplan-Meier Output Adaptation

`Study3/09_Kaplan Maier and Fine Gray.R` now saves an updated Figure 1 Kaplan-Meier plot for inappropriate shock by device group:

- x-axis display is limited to 2,200 days and labelled in years
- the main y-axis uses absolute scaling from 0.00 to 1.00
- an untitled enlarged zoom inset shows the 0.90-1.00 event-free survival range
- Single Lead Device is drawn as a blue solid curve and Double Lead Device as a red dashed curve
- the log-rank annotation is placed below the legend on the left side of the main panel
- the x-axis title is spaced slightly farther below the year tick labels
- curve line widths are reduced and censoring tick marks are drawn manually as short, thin vertical marks so the KM trend lines remain clearly visible
- a number-at-risk table is drawn below the Kaplan-Meier curves, styled as a separate lower panel in line with the Study 1 Kaplan-Meier figure
- PNG and PDF copies are written to `Study3/outputs`
- the quantitative data behind the plot are also exported to CSV files in `Study3/outputs`, so the figure can be reloaded and replotted independently

This is an output-only plotting adaptation. It does not change the Kaplan-Meier fit, log-rank test, endpoint definition, input cohort, filtering rule, Fine-Gray event coding, Fine-Gray model, cumulative-incidence analysis, or any statistical result.

## Dataset-Adjusted Fine-Gray Result Exports

In response to reviewer feedback about dataset handling in the competing-risk analysis, the Fine-Gray sections in `Study3/09_Kaplan Maier and Fine Gray.R` and `Study3/11_sensitivty analysis (180 days).R` now keep the original `cmprsk::crr()` device-only model and add a second dataset-adjusted `crr()` model:

```r
model.matrix(~ device_group + dataset, data = ...)
crr(..., cov1 = X_dataset, cengroup = dataset)
```

The added model treats dataset as fixed covariates and uses dataset-specific censoring through `cengroup`. This is documented as dataset-adjusted Fine-Gray analysis, not as a literal `strata(dataset)` Cox model.

Two CSV files are now written to `Study3/outputs`:

- `finegray_primary_device_results.csv`
- `finegray_sens_min180d_device_results.csv`

Each CSV contains the original device-only Fine-Gray result and the dataset-adjusted Fine-Gray result for `device_groupSingle`, including event counts, log-sHR, sHR, 95% confidence interval, p value, and datasets included. The original Fine-Gray model, event coding, KM/CIF plots, Cox models, cohort filters, and endpoint definitions remain unchanged.

## How To Check Paths On HPC

From the repository root:

```bash
cd /sc-projects/sc-proj-dhzc-profid/PROFID_Substudies
Rscript -e 'source("Study3/study3_paths.R"); files <- c("eu-cert-icd.csv","Helius.xlsx","israeli.csv","prose.xlsx","LCV.xlsx","PROSE_LCVcommon participant.csv"); for (f in files) cat(f, "->", study3_raw_path(f), file.exists(study3_raw_path(f)), "\n")'
```

Each file should resolve to an existing path and print `TRUE`.

## How To Run

Dry run:

```bash
Rscript Study3/master_run.R --dry-run
```

Full run:

```bash
Rscript Study3/master_run.R
```

Slurm wrapper:

```bash
./Study3/run_study3.sh
```

## Detailed Master-Run Debugging Output

`Study3/master_run.R` now accepts:

```bash
Rscript Study3/master_run.R --debugging
```

The Slurm wrapper forwards the option:

```bash
./Study3/run_study3.sh --debugging
```

The option can be combined with stage or step selection, for example:

```bash
Rscript Study3/master_run.R --from preprocess_israel --to km_fine_gray --debugging
```

The runner sets `STUDY3_DEBUGGING=1`, and shared reporting helpers in
`Study3/study3_paths.R` allow the critical scripts to print detailed
diagnostics only during debug runs. Normal runs remain concise.

The added reports trace:

- Israel raw and harmonised date fields
- representative Israel date strings before parsing
- Israel parsed dates, derived follow-up, events, and deaths
- source-dataset fields before merging and Israel fields after merging
- transfer from `t_followup_days`/`t_followup_days_israel` into
  `t_followup_days_final`
- dataset-specific Cox exclusions and final Cox input
- dataset-specific Fine-Gray exclusions, event coding, included datasets,
  reference level, and design-matrix columns

All added diagnostic output uses `cat()` or `print()` and is therefore copied
to both the terminal and the timestamped master text log through the runner's
`sink(log_con, split = TRUE)` configuration:

```text
Study3/outputs/master_run_<timestamp>.txt
```

Warnings and package messages written to standard error may appear only in the
Slurm log. Debug mode changes reporting only; it does not change any input
value, endpoint, cohort rule, filtering rule, model formula, or statistical
method.
