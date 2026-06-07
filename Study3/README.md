# PROFID Study 3

Event-level data preparation, harmonisation, and merging scripts for Study 3.

## Running The Pipeline

Run the complete pipeline from the repository root:

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
