# PROFID Repository and HPC Data Structure

This note describes the path structure implied by the exported directory listing and the hard-coded paths currently used in the substudy scripts. Its purpose is to make it easier to update imports when running the individual studies after separating the analysis repository from the protected data tree on the HPC.

## Recommended root variables

Do not hard-code the old Windows drive letters directly in new script edits. Define the roots once and build all paths with `file.path()`.

```r
repo_root   <- Sys.getenv("PROFID_REPO_ROOT",   unset = "/path/to/PROFID_Substudies")
data_root   <- Sys.getenv("PROFID_DATA_ROOT",   unset = "/path/to/profid-data")
output_root <- Sys.getenv("PROFID_OUTPUT_ROOT", unset = "/path/to/profid-outputs")
```

On the HPC, replace `/path/to/...` with the actual mounted project locations. The examples below use placeholders because the attached directory listing starts at `.` and does not include the absolute HPC mount prefix.

## Current repository layout

The code repository is organized by substudy:

```text
PROFID_Substudies/
  README.md
  Study1/
  Study2/
  Study3/
  Study4/
  Study5/
  Study6/
  Study7/
  Study8/
  Study9/
  assets/
  images/
  index.html
```

The current checked-out repository contains study code, documentation, and some generated figures/tables. It should not be treated as the canonical location for protected raw data.

## Data tree from the attached listing

The attached directory listing includes a data tree that should be considered the canonical data-side structure:

```text
<data_root>/
  Data_Transfer_to_Charite/
    ICD.csv
    ICD_all.csv
    NonICD_preserved.csv
    NonICD_reduced.csv
  datasets/
    cdm/
      profid-common-data-model.csv
      medication-classification-map.csv
    hz-scripts/
      hz-basic-summary-statistics.R
      hz-data-ratification-utils.R
      hz-unusual-data.R
      hz-variable-units-and-transformations.R
    local/
      <dataset-name>/
        data/
          original/
          dictionary/
          processed/
          working/
          maps/             # only present for some datasets
          gran-support/     # only present for predetermine
        scripts/
          cdm/
          hz-scripts/
        logs/
        results/
```

The key convention is:

```text
<data_root>/datasets/local/<dataset-name>/data/<stage>/<file>
```

where `<stage>` is usually one of `original`, `dictionary`, `processed`, or `working`.

## Data structure and availability inventory

The repository contains an HPC-ready inventory workflow that scans the PROFID source-data tree and writes aggregate metadata about which variables are available where. It is designed for planning analyses across studies and substudy groups, not for exporting individual patient data.

Main files:

| File | Purpose |
| --- | --- |
| `tools/profid_data_structure_inventory.R` | Scans supported raw/source/CDM tables, records column-level structure, classifies likely covariates/outcomes, and computes aggregate non-missing/missing counts where possible. |
| `tools/run_profid_data_structure_inventory.sh` | Slurm wrapper for the R script. It loads `R/4.5.0`, sets the HPC data root, writes logs, uses resume mode, and runs the inventory from the repository root. |
| `config/profid_substudy_sources.csv` | Maps source datasets and data stages to substudy labels for substudy-level availability summaries. Edit this file if the substudy grouping changes. |

Recommended HPC command:

```bash
cd /sc-projects/sc-proj-dhzc-profid/PROFID_Substudies
PROFID_REPO_ROOT="$PWD" sbatch tools/run_profid_data_structure_inventory.sh
```

The wrapper defaults to:

```text
PROFID_DATA_ROOT=/sc-projects/sc-proj-dhzc-profid/PROFID_Substudies/data
PROFID_INVENTORY_OUT_DIR=${PROFID_DATA_ROOT}/derived/data_structure
PROFID_INVENTORY_MAX_FULL_READ_MB=4096
PROFID_INVENTORY_CHUNK_ROWS=100000
```

These defaults can be overridden at submission time, for example:

```bash
PROFID_DATA_ROOT=/sc-projects/sc-proj-dhzc-profid/PROFID_Substudies/data \
PROFID_INVENTORY_MAX_FULL_READ_MB=2048 \
sbatch tools/run_profid_data_structure_inventory.sh
```

The output directory is:

```text
/sc-projects/sc-proj-dhzc-profid/PROFID_Substudies/data/derived/data_structure/
```

Expected output files:

| Output file | Contents |
| --- | --- |
| `profid_data_structure_master.csv` | One row per source column, sheet, or object where readable. Includes source dataset, data stage, relative file path, table dimensions, column name, normalized variable name, inferred role, domain guess, and aggregate missingness counts. |
| `profid_covariate_observation_points.csv` | Column-level rows from observation-source tables classified as covariates, including approximate non-missing observation counts. |
| `profid_outcome_observation_points.csv` | Column-level rows from observation-source tables classified as outcomes, including approximate non-missing observation counts. |
| `profid_variable_availability_by_dataset.csv` | Aggregated availability by source dataset, data stage, normalized variable, inferred role, and domain. |
| `profid_variable_availability_by_substudy.csv` | Aggregated availability by substudy group, normalized variable, inferred role, and domain using `config/profid_substudy_sources.csv`. |
| `profid_inventory_read_status_summary.csv` | Counts of read statuses such as successful reads, skipped large files, unsupported file types, or read errors. |
| `profid_inventory_reader_package_status.csv` | Availability of optional R reader packages on the compute node. |

The availability estimates are approximate planning counts. For readable tabular files, `nonmissing_n`, `missing_n`, `nonmissing_pct`, and table row counts are computed by column. For very large files above `PROFID_INVENTORY_MAX_FULL_READ_MB`, the script may record structure only or skip files that cannot be safely inspected without loading the full object, especially large `.rds` objects. The read-status summary should therefore be checked before interpreting the totals.

Privacy boundary:

The inventory outputs contain metadata only: file paths relative to `data_root`, sheet/object names, column names, inferred variable roles/domains, row/column counts, and missingness counts. They do not contain patient-level rows, patient identifiers, raw values, value examples, category frequencies, min/max values, or date ranges. The outputs should still be treated as internal project metadata because variable names and dataset paths can reveal study structure, but they are not individual patient data.

Monitoring commands:

```bash
squeue -j <JOBID>
scontrol show job <JOBID> | egrep 'JobName|Command|WorkDir|StdOut|StdErr|ReqMem|RunTime|Partition'
tail -f profid_inventory_<JOBID>.log
ls -lh /sc-projects/sc-proj-dhzc-profid/PROFID_Substudies/data/derived/data_structure/
```

When the wrapper is run directly with `bash tools/run_profid_data_structure_inventory.sh`, it self-submits to Slurm and places the log under:

```text
/sc-projects/sc-proj-dhzc-profid/PROFID_Substudies/data/derived/data_structure/logs/
```

When it is submitted directly with `sbatch tools/run_profid_data_structure_inventory.sh`, Slurm uses the static `#SBATCH` log pattern and usually writes `profid_inventory_<JOBID>.log` in the submit directory.

Resume behavior:

The Slurm wrapper runs the R script with `--resume yes`. If a job is interrupted or the SSH session drops, resubmitting the same command continues from the existing `profid_data_structure_master.csv` and skips already-inventoried top-level files. If the master CSV schema is incompatible with the current script, the old file is moved to a timestamped backup and a new inventory is started.

Direct R invocation, useful for debugging on an interactive node:

```bash
module load R/4.5.0
Rscript /sc-projects/sc-proj-dhzc-profid/PROFID_Substudies/tools/profid_data_structure_inventory.R \
  --data-root /sc-projects/sc-proj-dhzc-profid/PROFID_Substudies/data \
  --repo-root /sc-projects/sc-proj-dhzc-profid/PROFID_Substudies \
  --out-dir /sc-projects/sc-proj-dhzc-profid/PROFID_Substudies/data/derived/data_structure \
  --scope source_plus_cdm \
  --include-archives yes \
  --include-availability yes \
  --max-full-read-mb 4096 \
  --chunk-rows 100000 \
  --resume yes
```

## Dataset folders

The listing contains these dataset folders under `datasets/local/`:

```text
artemis
aston-rdb
barcelona
derivate
do-it
eu-cert-icd
eu-trig-treat
french-icd
helios-rdb
isar-rdb
israeli-icd
madit-ii
madit-rit
nancy-rdb
olomouc-rdb
predetermine
prose-icd
prose-lvscd
scd-heft
silesian-rdb
swedish-hr
```

Common processed CDM files identified in the listing:

| Dataset | Processed CDM file |
| --- | --- |
| artemis | `atms-common-data-model.rds` |
| aston-rdb | `astn-common-data-model.rds` |
| derivate | `drvt-icd-common-data-model.rds`, `drvt-non-icd-common-data-model.rds` |
| do-it | `doit-common-data-model.rds` |
| eu-cert-icd | `cert-common-data-model.rds` |
| eu-trig-treat | `trig-common-data-model.rds` |
| french-icd | `fren-common-data-model.rds` |
| helios-rdb | `hels-common-data-model.rds`, `hels-phase-1.xlsx` |
| isar-rdb | `isar-common-data-model.rds` |
| israeli-icd | `isrl-common-data-model.rds` |
| madit-ii | `mdii-icd-common-data-model.rds`, `mdii-non-icd-common-data-model.rds` |
| madit-rit | `mdrt-common-data-model.rds` |
| nancy-rdb | `nanc-common-data-model.rds` |
| olomouc-rdb | `olmc-common-data-model.rds` |
| predetermine | `prdt-common-data-model.rds` |
| prose-icd | `prsi-common-data-model.rds` |
| prose-lvscd | `prsl-common-data-model.rds` |
| scd-heft | `shft-icd-common-data-model.rds`, `shft-non-icd-common-data-model.rds` |
| silesian-rdb | `slsn-common-data-model.rds` |
| swedish-hr | `swhr-common-data-model.rds` |

Example:

```r
helios_cdm <- file.path(
  data_root,
  "datasets", "local", "helios-rdb", "data", "processed",
  "hels-common-data-model.rds"
)
```

## Legacy path mapping

Use this table when replacing old imports and output paths.

| Legacy path root | New pattern |
| --- | --- |
| `S:/AG/f-dhzc-profid/Data Transfer to Charite` | `file.path(data_root, "Data_Transfer_to_Charite")` |
| `//Charite.de/Centren/AG/f-dhzc-profid/Data Transfer to Charite` | `file.path(data_root, "Data_Transfer_to_Charite")` |
| `T:/Data Transfer to Charite` | `file.path(data_root, "Data_Transfer_to_Charite")` |
| `S:/AG/f-dhzc-profid/datasets` | `file.path(data_root, "datasets")` |
| `//Charite.de/Centren/AG/f-dhzc-profid/datasets` | `file.path(data_root, "datasets")` |
| `T:/PROFID/data/raw` | `file.path(data_root, "raw")` or `file.path(data_root, "Data_Transfer_to_Charite")`, depending on the file |
| `T:/PROFID/data/processed` | `file.path(data_root, "processed")` |
| `T:/PROFID/output` | `output_root` |
| `T:/PROFID/Study8` | `file.path(output_root, "Study8")` for generated files; `file.path(repo_root, "Study8")` for scripts |
| `T:/Study_1` | `file.path(output_root, "Study1")` |
| `T:/Study_5` | `file.path(output_root, "Study5")` |
| `T:/Study_9` | `file.path(output_root, "Study9")` |
| `T:/study_4`, `T:/study4`, `T:/studyears_4` | normalize to `file.path(output_root, "Study4")` |
| `T:/Dokumente/PROFID/Study6` | `file.path(output_root, "Study6")` |
| `//charite.de/homes/.../Dokumente/PROFID/Study6` | `file.path(output_root, "Study6")` |
| `T:/FINAL ICD COHORT` | `file.path(data_root, "derived", "Study1", "FINAL_ICD_COHORT")` |
| `T:/EUCID`, `T:/HELIOS`, `T:/ISRAEL`, `T:/PROSE` | `file.path(data_root, "derived", "Study1", "<source>")` |

For output-only paths, prefer `output_root`. For intermediate datasets that are consumed by later studies or later stages of the same study, prefer `data_root/derived/<Study>/...` so they are easy to distinguish from publication tables and plots.

## Study-specific path expectations

| Study | Main path dependencies to update |
| --- | --- |
| Study1 | Uses `datasets/local/...` raw/dictionary files, `Data_Transfer_to_Charite/ICD.csv`, and derived outputs under `FINAL ICD COHORT`, `Study_1`, `EUCID`, `HELIOS`, `ISRAEL`, and `PROSE`. |
| Study2 | Uses raw cohort extracts, centre metadata, ERA5 climate files, `df_cleaned.rds`, and `T:/PROFID/output`. The code is inconsistent about whether `df_cleaned.rds` is in `data/raw` or `data/processed`; choose one canonical HPC location. |
| Study3 | Mostly uses relative RDS/CSV files in the working directory. Ensure the required intermediate files are staged in the Study3 run directory or update them to `data_root/derived/Study3`. |
| Study4 | Starts from `Data_Transfer_to_Charite` and writes to several inconsistent roots: `study_4`, `study4`, and `studyears_4`. Normalize all to `output_root/Study4`. |
| Study5 | Scripts stored as `.txt` expect `T:/Study_5` and sometimes fall back to `S:/AG/f-dhzc-profid/Data Transfer to Charite`. Normalize to `output_root/Study5` plus `data_root/Data_Transfer_to_Charite`. |
| Study6 | Reads `ICD.csv`, `NonICD_preserved.csv`, `NonICD_reduced.csv`, `combined_dataset.csv`, and `combined_icd.csv` from `Data_Transfer_to_Charite`; writes and rereads model objects under `T:/Dokumente/PROFID/Study6`. |
| Study7 | Reads geocoded files from `T:/Data Transfer to Charite/raw`. Place these under `data_root/Data_Transfer_to_Charite/raw` or update the scripts to the actual geocoded-data location. |
| Study8 | Reads `ICD.csv`, `NonICD_preserved.csv`, and `NonICD_reduced.csv` from `Data_Transfer_to_Charite`; writes model and risk-score artifacts below `T:/PROFID/Study8`. |
| Study9 | Codebase notes indicate hard-coded `T:/Study_9` outputs and `S:/` inputs. Normalize outputs to `output_root/Study9` and inputs to `data_root/Data_Transfer_to_Charite` or another documented data source. |

## Practical replacement pattern

Old code:

```r
file1 <- read.csv("S:/AG/f-dhzc-profid/Data Transfer to Charite/ICD.csv")
OUTDIR <- "T:/PROFID/Study8/Variable Selection & Model Development/Files"
```

Portable code:

```r
transfer_dir <- file.path(data_root, "Data_Transfer_to_Charite")
study8_out <- file.path(output_root, "Study8", "Variable Selection & Model Development", "Files")

file1 <- read.csv(file.path(transfer_dir, "ICD.csv"))
dir.create(study8_out, recursive = TRUE, showWarnings = FALSE)
```

Old CDM path:

```r
IN_DICT_XLSX <- "S:/AG/f-dhzc-profid/datasets/local/israeli-icd/data/dictionary/israeli-icd-data-dictionary-raw-v3.xlsx"
```

Portable CDM path:

```r
IN_DICT_XLSX <- file.path(
  data_root,
  "datasets", "local", "israeli-icd", "data", "dictionary",
  "israeli-icd-data-dictionary-raw-v3.xlsx"
)
```

## Migration checklist

1. Set `PROFID_REPO_ROOT`, `PROFID_DATA_ROOT`, and `PROFID_OUTPUT_ROOT` in the HPC job script.
2. Replace all `setwd("T:/...")` calls with explicit `repo_root`, `data_root`, or `output_root` paths.
3. Replace every `T:/`, `S:/AG/f-dhzc-profid`, and `//Charite.de/...` literal with a `file.path()` expression.
4. Separate inputs from outputs: raw and curated data under `data_root`, generated tables/figures/models under `output_root`, reusable derived datasets under `data_root/derived`.
5. Normalize inconsistent study names: use `Study1`, `Study4`, `Study5`, `Study6`, `Study8`, and `Study9` rather than mixed forms such as `Study_1`, `study_4`, `study4`, or `studyears_4`.
6. Keep paths with spaces only when they already correspond to real data-delivery folders. For new HPC output folders, prefer stable names without spaces if changing downstream references is feasible.
