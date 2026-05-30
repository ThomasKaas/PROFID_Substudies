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
