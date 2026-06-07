# PROFID Study 3

Event-level data preparation, harmonisation, and merging scripts for Study 3.

## Execution Modes

`Study3/master_run.R` is the canonical entry point. It runs the numbered Study
3 scripts in their established order without changing their statistical logic.

The runner has two path modes:

| Mode | Command flag | Raw-data root | Derived intermediates | Analysis outputs |
|---|---|---|---|---|
| Default/HPC | none | `/sc-projects/sc-proj-dhzc-profid/PROFID_Substudies/data` | `<HPC data root>/derived/Study3` | `Study3/outputs` |
| Local | `--local` | `/Users/PROFID_RAW_DATA` | `/Users/PROFID_RAW_DATA/derived/Study3` | `Study3/outputs` |

The local raw-data root is selected only when `--local` is present. Local mode
checks that `/Users/PROFID_RAW_DATA` exists before running. It reads
the registry files from their dataset-specific folders and reads `ICD.csv` from
`Data Transfer to Charite/`. Derived Study 3 datasets are written to
`/Users/PROFID_RAW_DATA/derived/Study3`.

## Running The Pipeline

Run the complete pipeline in default/HPC mode from the repository root:

```bash
Rscript Study3/master_run.R
```

Run through the Slurm wrapper:

```bash
./Study3/run_study3.sh
```

Preview the selected scripts without executing them:

```bash
Rscript Study3/master_run.R --dry-run
```

Run the complete pipeline locally:

```bash
Rscript Study3/master_run.R --local
```

Local mode can be combined with debugging and the normal selection options:

```bash
Rscript Study3/master_run.R --local --debugging
Rscript Study3/master_run.R --local --from preprocess_israel --to km_fine_gray --debugging
```

Without `--local`, the runner retains the default/HPC path configuration.

## Runner Options

Options can be combined in any order:

| Option | Effect |
|---|---|
| `--local` | Use `/Users/PROFID_RAW_DATA` for raw inputs. |
| `--debugging` | Print detailed cohort, field, and model-input diagnostics. |
| `--dry-run` | Print selected scripts without executing them. |
| `--stage <name>` | Run one stage: `all`, `preprocessing`, `analysis`, `descriptive`, `modeling`, `sensitivity`, or `imputation`. |
| `--from <step_id>` | Start at a named pipeline step. |
| `--to <step_id>` | Stop at a named pipeline step. |
| `--only <ids>` | Run comma-separated step IDs in the supplied order. |
| `--continue-on-error` | Continue after a failed script and report failures at the end. |
| `--help` | Print complete runner usage and available step IDs. |

Examples:

```bash
Rscript Study3/master_run.R --local --dry-run
Rscript Study3/master_run.R --local --stage preprocessing
Rscript Study3/master_run.R --local --only merge
Rscript Study3/master_run.R --local --from preprocess_israel --to km_fine_gray --debugging
```

## Path Configuration

The runner and numbered scripts use `Study3/study3_paths.R`.

- `--local` sets `PROFID_DATA_ROOT=/Users/PROFID_RAW_DATA`.
- `--local` sets `PROFID_STUDY3_DERIVED_ROOT=/Users/PROFID_RAW_DATA/derived/Study3`.
- `--debugging` sets `STUDY3_DEBUGGING=1`.
- `PROFID_STUDY3_OUTPUT_ROOT` can override the output directory.
- `PROFID_STUDY3_RAW_ROOT`, `PROFID_STUDY3_DERIVED_ROOT`, and
  `PROFID_STUDY3_METADATA_ROOT` remain available for explicit path overrides
  outside local mode.

The short filenames used by the numbered scripts are resolved to the original
registry files under `datasets/local/...`. Both the HPC transfer directory
`Data_Transfer_to_Charite/` and the local directory `Data Transfer to Charite/`
are supported for `ICD.csv`.

## Detailed Debugging Log

Use `--debugging` when investigating missing follow-up, dataset exclusions, or
differences between the merged cohort and the Cox/Fine-Gray model inputs:

```bash
Rscript Study3/master_run.R --debugging
```

Or through Slurm:

```bash
./Study3/run_study3.sh --debugging
```

The option can be combined with the normal selection options:

```bash
Rscript Study3/master_run.R --from preprocess_israel --to km_fine_gray --debugging
```

Debugging output is written to both the terminal and the timestamped master log:

```text
Study3/outputs/master_run_<timestamp>.txt
```

The master runner uses `sink(..., split = TRUE)`, so diagnostic output produced
with `cat()` and `print()` is copied to both destinations. Warnings and package
messages written to standard error may appear only in the Slurm log.

Debug mode reports the complete Israel-to-model data path:

- raw Israel source dimensions, date-field availability, and representative date strings
- Israel fields before and after date parsing and follow-up derivation
- final cleaned Israel follow-up, event, and death counts
- survival-field availability by dataset before and after merging
- comparison of `t_followup_days`, `t_followup_days_israel`, and `t_followup_days_final`
- Cox eligibility exclusions and final model input by dataset
- Fine-Gray eligibility exclusions, death coding, event coding, included datasets,
  reference dataset, and design-matrix columns

Debug sections are labelled with headings such as:

```text
DEBUG: Israel representative date strings before parsing
DEBUG: Israel final cleaned export summary
DEBUG: Israel immediately before merge
DEBUG: Israel immediately after baseline/event merge
DEBUG: First t_followup_days_final assignment comparison
DEBUG: Primary Cox survival-readiness exclusions
DEBUG: Dataset-adjusted Fine-Gray design
```

Debug mode adds reporting only. It does not change cohort definitions, endpoint
definitions, follow-up values, model formulas, or statistical methods.

## Path Verification

Verify the local raw-data paths without running the analysis:

```bash
Rscript Study3/master_run.R --local --dry-run
PROFID_DATA_ROOT=/Users/PROFID_RAW_DATA PROFID_STUDY3_DERIVED_ROOT=/Users/PROFID_RAW_DATA/derived/Study3 Rscript -e 'source("Study3/study3_paths.R"); files <- c("eu-cert-icd.csv","Helius.xlsx","israeli.csv","prose.xlsx","LCV.xlsx","PROSE_LCVcommon participant.csv"); for (f in files) cat(f, "->", study3_raw_path(f), "\n"); cat("ICD.csv ->", profid_transfer_path("ICD.csv"), "\n"); cat("Derived datasets ->", study3_derived_root(), "\n")'
```
