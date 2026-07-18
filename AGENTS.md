# Repository Guidelines

## Project Structure & Module Organization

This repository contains R analysis pipelines for PROFID substudies. Each
`Study1/` through `Study9/` directory owns its analysis scripts, study-specific
documentation, and (where applicable) generated tables and figures. Numbered
R scripts generally represent pipeline order; use a study's `master_run.R` as
the normal entry point rather than running downstream scripts in isolation.

Shared operational code lives in `tools/`; source-to-substudy mappings are in
`config/`; repository-wide layout and data-root guidance is in
`Repo-Structure.md`. Images used by the top-level documentation belong in
`assets/` or `images/`. Protected raw data must remain outside this repository.

## Build, Test, and Development Commands

Run commands from the repository root with a compatible R installation.

```bash
Rscript Study1/master_run.R --dry-run       # preview the Study 1 pipeline
Rscript Study3/master_run.R --local --dry-run
Rscript Study3/master_run.R --help          # list stages and step IDs
Rscript tools/test_feasibility_counts_smoke.R
```

Use `./Study1/run_study1.sh` or `./Study3/run_study3.sh` to submit their
respective pipelines through Slurm. For the metadata-only HPC inventory, use
`PROFID_REPO_ROOT="$PWD" sbatch tools/run_profid_data_structure_inventory.sh`.
Set `PROFID_*` environment variables for data and output roots instead of
introducing machine-specific paths.

## Coding Style & Naming Conventions

Write readable base R or tidyverse-style R with two-space indentation, spaces
around operators, and explicit `file.path()` construction. Keep script names
descriptive; retain the existing numbered prefixes when inserting a pipeline
stage (for example, `13_Figure3_forest_plot.R`). Centralize paths in the
study's path helper or runner. Do not commit `.RData`, raw extracts, patient
level outputs, credentials, or local absolute paths.

## Testing Guidelines

There is no repository-wide test framework or coverage target. Before a
change, run the relevant runner with `--dry-run`; after changes to feasibility
logic, run `Rscript tools/test_feasibility_counts_smoke.R`. For analysis
changes, validate the smallest affected stage with non-sensitive test data and
inspect expected CSV/figure outputs and warnings. Describe any data-dependent
checks that could not be run in the pull request.

## Commit & Pull Request Guidelines

Recent commits use short imperative subjects, such as `Fix script 07 endpoint
derivation ordering` or `Add pooled primary Cox model`. Keep each commit scoped
to one logical correction. Pull requests should state the affected study and
pipeline stage, summarize analytical/output changes, list commands run, link
the issue when available, and include before/after figures or tables when a
visual or published result changes.
