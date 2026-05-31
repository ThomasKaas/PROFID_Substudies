# PROFID Dataset Landscape and Whole-Dataset Analysis Opportunities

Generated: 2026-05-31
Updated with direct CSV inventory: 2026-05-31

This document summarizes what can be inferred about the available PROFID data from the repository code, codebase descriptions, metadata workbooks, checked-in output tables, and the direct CSV inventory files listed below. The original study-review layer remains based on static review of `Study1` through `Study9`; the new inventory layer is based on generated column/table metadata, row counts, and missingness summaries rather than individual-level protected raw records. Where the code uses hard-coded external paths or derived objects that are not present in this checkout, the statements below are extrapolated from the variables read, transformed, modeled, and reported by the scripts.

## Executive Summary

The repository points to a large multi-source post-myocardial-infarction data lake, with a core harmonized cohort split into ICD recipients, non-ICD patients with reduced LVEF, and non-ICD patients with preserved LVEF. Across the substudy code, the most reusable whole-dataset structure is:

- Patient-level follow-up with `Survival_time` and `Status`, where `Status == 1` is generally sudden cardiac death (SCD), `Status == 2` is non-SCD death or another competing event, and `Status == 0` is censored.
- Calendar/index timing through `Time_zero_Y`, `Time_zero_Ym`, `Year_index`, period/band variables, and follow-up durations.
- Cohort/source identifiers through `DB`, `dataset`, `Group`, `ICD_status`, and related source labels.
- A broad baseline phenotype: age, sex, LVEF, BMI, renal function, hemoglobin, lipids, cardiovascular history, diabetes, hypertension, smoking, atrial fibrillation/flutter, stroke/TIA, ECG features, NYHA class, medications, and revascularization.
- ICD-specific event data in a subset of registries, especially inappropriate shock/therapy, appropriate shock/therapy, ATP, follow-up time, death, and device type.
- Geographic/environmental metadata in some workflows: cardiovascular risk region, center/city/country, coordinates, ERA5-derived temperature, pressure, daylight, sunshine, and season.
- Treatment variables that support heart failure guideline-directed medical therapy (GDMT) analyses: RAAS inhibitor, beta-blocker, MRA, diuretics, optional ARNI/SGLT2 fields, and derived triple-therapy endpoints.

The direct CSV inventory now quantifies that landscape: 363 table/sheet/object entries were inventoried, including 289 observation-source entries, 14,732 observation-source inventory rows, 8,949 distinct nonblank normalized column labels in the master inventory, and 5,046 normalized variables in the all-source availability roll-up. Broadly reusable variables include `status`, `survival_time`, age, sex, LVEF, BMI, eGFR, diabetes, hypertension, smoking, AF/flutter, beta-blockers, PCI, and CABG; ICD therapy, ATP, detailed device, NYHA, ECG, scar, and biomarker fields are valuable but more source-specific.

The code therefore supports more than isolated substudy analyses. The strongest next whole-dataset opportunities are:

1. A canonical endpoint and variable dictionary with automated availability and unit checks.
2. A full-cohort competing-risk SCD model with absolute risk calibration.
3. LVEF-threshold and continuous-LVEF analyses that test whether current cutoffs remain clinically meaningful.
4. Calendar-era analyses linking SCD risk, ICD proxy events, GDMT uptake, and changing case mix from 2000 to 2020.
5. Transportability and heterogeneity studies across databases, geography, and registry types.
6. A dynamic absolute-risk framework that jointly models SCD and non-SCD death.
7. Whole-cohort phenotyping using multimorbidity, medications, labs, ECG, EF, BMI, and AF status.

## Evidence Sources Reviewed

The following repository components were used as evidence:

- Top-level `README.md` and `Repo-Structure.md`.
- Study descriptions:
  - `Study1/Study1_codebase_description.md`
  - `Study2/STUDY2_CODEBASE_DESCRIPTION.md`
  - `Study3/CODEBASE_DESCRIPTION.md`
  - `Study4/Study4_codebase_description.md`
  - `Study5/Study5_codebase_description.md`
  - `Study6/Study6_codebase_description.md`
  - `Study7/Study7_codebase_analysis.md`
  - `Study8/Study8_codebase_description.md`
  - `Study9/Study9_codebase_description.md`
- R scripts and R-like `.txt` scripts across `Study1` to `Study9`.
- Study 3 mapping workbooks:
  - `Study3/01_master_map.xlsx`
  - `Study3/02_small_map.xlsx`
- Checked-in output CSVs, especially from Study 6 and Study 8.
- Path mappings and dataset lists in `Repo-Structure.md`.
- Direct inventory CSVs supplied for this update:
  - `profid_data_structure_master.csv`
  - `profid_variable_availability_by_dataset.csv`
  - `profid_variable_availability_by_substudy.csv`
  - `profid_outcome_observation_points.csv`
  - `profid_covariate_observation_points.csv`
  - `profid_inventory_read_status_summary.csv`
  - `profid_inventory_reader_package_status.csv`

The direct inventory files provide table/column metadata and missingness summaries, but not individual patient-level raw data values. Raw-data semantics such as endpoint coding, units, and source-specific categorical encodings still require validation against the source documentation and analysis code.

## Direct CSV Inventory Update (2026-05-31)

The seven CSV files in `/Users/thomaskaas/Downloads` add a direct, quantitative inventory layer on top of the code-derived review above. They do not contain individual-level raw records, but they do enumerate source tables, columns, inferred variable roles, source stages, row counts, column counts, nonmissing observation points, and missing observation points. In this section, "observation points" means table cells or column-level row observations inside the inventoried source tables. These counts are not unique patients: original files, processed common-data-model files, transfer tables, visit tables, event tables, measurements, and repeated extracts can all describe overlapping people.

### Inventory Files Read

| CSV file | Rows | Columns | Role in this report |
| --- | --- | --- | --- |
| profid_variable_availability_by_substudy.csv | 7,730 | 16 | Variable availability aggregated by All PROFID sources and Study1 through Study9 source groupings. |
| profid_variable_availability_by_dataset.csv | 6,269 | 17 | Variable availability aggregated by source dataset and stage. |
| profid_outcome_observation_points.csv | 650 | 22 | Outcome-tagged observation points with row counts and missingness. |
| profid_inventory_reader_package_status.csv | 6 | 2 | Reader package availability used by the inventory reader. |
| profid_inventory_read_status_summary.csv | 7 | 2 | Read-status summary for inventory rows. |
| profid_data_structure_master.csv | 15,653 | 22 | Master column-level inventory across transfer, original, processed, dictionaries, maps, and CDM specification sources. |
| profid_covariate_observation_points.csv | 1,999 | 22 | Covariate-tagged observation points with row counts and missingness. |

### Reader Coverage and Read Status

The inventory reader had working support for the main formats used here: `data.table`, `readxl`, `openxlsx`, and `haven` were available. `readODS` and `arrow` were not available, which matters for any `.ods` or Arrow/Parquet-style material that would require those readers.

| Reader package | Available |
| --- | --- |
| data.table | yes |
| readxl | yes |
| openxlsx | yes |
| readODS | no |
| haven | yes |
| arrow | no |

The master inventory contains 15,653 rows across 363 distinct table, sheet, object, or archive-member entries. Most rows were read normally, but a small set of files were only structurally described or not read completely.

| Read status | Rows |
| --- | --- |
| archive_not_scanned | 4 |
| missing_package | 1 |
| no_supported_archive_members | 1 |
| ok | 11,771 |
| ok_structure_only_size_limit | 3,860 |
| read_error | 10 |
| unsupported_text_layout | 6 |

Interpreting this read-status table:

- `ok` covers 11,771 column-level inventory rows and 340 unique table/sheet/object entries.
- `ok_structure_only_size_limit` is concentrated in one very wide source, the Swedish original `.dta` table with 3,860 columns. Its structure was captured, but nonmissing cell counts are not available from a full data read in this inventory run.
- `read_error`, `archive_not_scanned`, `unsupported_text_layout`, `missing_package`, and `no_supported_archive_members` together account for a small number of table-level entries, but they should be reviewed before claiming exhaustive source coverage.
- The processed Swedish common-data-model file was read successfully and contributes the largest patient-record table in the inventory, so the Swedish source is not absent; the limitation mainly affects the original wide file.

### Master Structure by Source Stage, Kind, and File Type

The full inventory combines transfer extracts, original source files, processed common-data-model objects, dictionaries, map files, and CDM specifications. Observation sources are only a subset of this total.

| Source stage | Unique tables/sheets | Inventory rows |
| --- | --- | --- |
| original | 262 | 13,322 |
| scripts_cdm | 40 | 560 |
| dictionary | 27 | 308 |
| processed | 23 | 1,084 |
| maps | 5 | 25 |
| transfer | 4 | 326 |
| cdm_spec | 2 | 28 |

| Source kind | Unique tables/sheets | Inventory rows |
| --- | --- | --- |
| dataset_original | 249 | 13,086 |
| dataset_cdm_spec | 40 | 560 |
| dataset_dictionary | 27 | 308 |
| dataset_processed | 23 | 1,084 |
| dataset_original_archive_member | 13 | 236 |
| dataset_maps | 5 | 25 |
| transfer_table | 4 | 326 |
| global_cdm_spec | 2 | 28 |

| File type | Unique tables/sheets |
| --- | --- |
| csv | 114 |
| sas7bdat | 107 |
| xlsx | 100 |
| rds | 23 |
| txt | 8 |
| rar | 4 |
| xls | 3 |
| sav | 1 |
| zip | 1 |
| ods | 1 |
| dta | 1 |

The 289 observation-source table entries contain 14,732 observation-source inventory rows and 8,949 distinct nonblank normalized column labels in the master table. The availability roll-up collapses this broader raw-column surface to 5,046 normalized analysis variables for `All_PROFID_sources`.

### Observation-Source Scale

Across observation sources, summed table rows total 2,192,920. This is a measure of dataset volume, not a count of unique individuals. The largest component is repeated visit-style data, followed by patient-record tables.

| Count unit | Tables | Variable rows | Unique normalized variables | Summed table rows | Median rows/table | Max rows/table |
| --- | --- | --- | --- | --- | --- | --- |
| visits | 71 | 1,626 | 929 | 1,407,401 | 26,292 | 54,230 |
| patient_records | 61 | 7,518 | 4,916 | 381,348 | 768 | 175,573 |
| measurements | 21 | 900 | 674 | 163,228 | 768 | 64,224 |
| unknown_rows | 81 | 755 | 543 | 151,551 | 768 | 34,231 |
| event_rows | 55 | 3,933 | 2,499 | 89,392 | 760 | 9,256 |

The median observation table has 979 rows and 18 columns. The 90th percentile table has about 28,202 rows and 88 columns. The largest successfully read observation table is the processed Swedish common-data-model object with 175,573 patient records.

### Source Dataset Profile

The observation inventory covers 21 source datasets: Data_Transfer_to_Charite, artemis, aston-rdb, derivate, do-it, eu-cert-icd, eu-trig-treat, french-icd, helios-rdb, isar-rdb, israeli-icd, madit-ii, madit-rit, nancy-rdb, olomouc-rdb, predetermine, prose-icd, prose-lvscd, scd-heft, silesian-rdb, swedish-hr. The table below summarizes each source. `Summed table rows` again counts rows across all tables for that source, so a source with many visit or event tables can exceed its patient count.

| Source dataset | Stages | Tables | Summed table rows | Variable columns | Unique variables | Covariate cols | Outcome cols | Unknown cols | Aggregate nonmissing |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| scd-heft | original \| processed | 101 | 1,458,864 | 2,874 | 1,826 | 455 | 42 | 2,373 | 41.9% |
| olomouc-rdb | original \| processed | 14 | 197,980 | 759 | 385 | 125 | 12 | 527 | 31.6% |
| swedish-hr | original \| processed | 3 | 175,573 | 3,924 | 3,921 | 590 | 368 | 2,867 | 82.8% |
| Data_Transfer_to_Charite | transfer | 4 | 147,997 | 326 | 91 | 122 | 16 | 184 | 56.9% |
| madit-ii | original \| processed | 26 | 59,336 | 1,213 | 285 | 43 | 14 | 1,133 | 91.2% |
| madit-rit | original \| processed | 16 | 39,609 | 395 | 169 | 24 | 8 | 350 | 85.3% |
| predetermine | original \| processed | 9 | 29,603 | 701 | 233 | 199 | 63 | 438 | 69.6% |
| helios-rdb | original \| processed | 35 | 22,149 | 775 | 280 | 133 | 63 | 544 | 80.6% |
| french-icd | original \| processed | 4 | 12,751 | 145 | 86 | 26 | 7 | 111 | 67.7% |
| israeli-icd | original \| processed | 2 | 10,009 | 603 | 603 | 39 | 7 | 556 | 37.2% |
| isar-rdb | original \| processed | 2 | 7,644 | 112 | 101 | 48 | 12 | 51 | 92.4% |
| eu-cert-icd | original \| processed | 3 | 7,043 | 90 | 90 | 34 | 21 | 32 | 67.1% |
| aston-rdb | original \| processed | 7 | 4,614 | 267 | 124 | 52 | 78 | 136 | 89.2% |
| derivate | original \| processed | 6 | 3,538 | 436 | 217 | 162 | 42 | 226 | 88.8% |
| silesian-rdb | original \| processed | 16 | 3,441 | 388 | 370 | 106 | 113 | 164 | 90.4% |
| prose-icd | original \| processed | 14 | 3,308 | 307 | 146 | 61 | 39 | 200 | 97.3% |
| prose-lvscd | original \| processed | 14 | 3,069 | 319 | 155 | 65 | 40 | 207 | 96.9% |
| artemis | original \| processed | 2 | 2,916 | 611 | 598 | 106 | 23 | 480 | 94.8% |
| do-it | original \| processed | 3 | 1,448 | 189 | 187 | 65 | 18 | 105 | 89.3% |
| eu-trig-treat | original \| processed | 4 | 1,385 | 151 | 80 | 34 | 17 | 99 | 88.7% |
| nancy-rdb | original \| processed | 4 | 643 | 147 | 144 | 69 | 13 | 61 | 99.9% |

Important interpretation points from this source profile:

- `scd-heft` has the largest table-row volume because many original SAS datasets are visit-structured. It contributes 1,826 unique normalized variables across 101 observation tables, but aggregate nonmissingness is low because the visit/event matrices are sparse.
- `swedish-hr` contributes the largest processed patient-record table: 175,573 rows and 63 columns in `swhr-common-data-model.rds`. Its original `.dta` source is much wider but was structure-only in this run.
- The transfer layer `Data_Transfer_to_Charite` contains the four familiar harmonized cohort files and accounts for 147,997 summed patient-record rows across ICD and non-ICD transfer tables.
- ICD/device-therapy sources such as `eu-cert-icd`, `helios-rdb`, `israeli-icd`, `prose-icd`, `prose-lvscd`, `madit-ii`, `madit-rit`, and `olomouc-rdb` contain many event/device fields, but their variable names and event semantics require manual harmonization before pooled device analyses.
- Several processed source-stage files have much cleaner and denser availability than the corresponding original files; future pooled analyses should usually start from the processed common-data-model files and then selectively return to original files for source-specific endpoints.

### Largest and Widest Observation Tables

Largest observation tables by row count:

| Source | Stage | Count unit | Rows | Columns | Table/file |
| --- | --- | --- | --- | --- | --- |
| swedish-hr | processed | patient_records | 175,573 | 63 | rds_object |
| Data_Transfer_to_Charite | transfer | patient_records | 107,603 | 88 | NonICD_preserved.csv |
| olomouc-rdb | original | measurements | 64,224 | 27 | Elektrody |
| scd-heft | original | visits | 54,230 | 11 | fuicdc2.sas7bdat |
| scd-heft | original | visits | 50,378 | 10 | shsig.sas7bdat |
| olomouc-rdb | original | measurements | 38,113 | 64 | Hospitalizace_2 |
| olomouc-rdb | original | measurements | 38,109 | 155 | Hospitalizace_1 |
| olomouc-rdb | original | unknown_rows | 34,231 | 74 | Pacienti |
| scd-heft | original | visits | 30,723 | 19 | walk.sas7bdat |
| scd-heft | original | visits | 28,813 | 11 | meds7.sas7bdat |
| scd-heft | original | visits | 28,813 | 13 | epstudy.sas7bdat |
| scd-heft | original | visits | 28,813 | 20 | afib2.sas7bdat |

Widest observation tables by column count:

| Source | Stage | Count unit | Rows | Columns | Read status | Table/file |
| --- | --- | --- | --- | --- | --- | --- |
| swedish-hr | original | patient_records |  | 3,860 | ok_structure_only_size_limit | Swedish_cohort.dta |
| israeli-icd | original | event_rows | 9,256 | 560 | ok | ICDALL_20170630.csv |
| artemis | original | event_rows | 1,946 | 550 | ok | ARTEMIS_PROFID-2021-02-05 (3).sav |
| scd-heft | original | visits | 25,681 | 486 | ok | followup.sas7bdat |
| scd-heft | original | measurements | 2,521 | 301 | ok | basecrf.sas7bdat |
| scd-heft | original | event_rows | 612 | 257 | ok | deathrpt.sas7bdat |
| silesian-rdb | original | patient_records | 665 | 255 | ok | Sheet1 |
| madit-ii | original | patient_records | 1,233 | 179 | ok | PATIENTS.csv |
| madit-ii | original | patient_records | 1,233 | 178 | ok | PATIENTS_v3.csv |
| madit-ii | original | patient_records | 1,233 | 178 | ok | PATIENTS.csv |

These tables show why the PROFID data structure is complex: it combines small patient-level registries, very large patient-level extracts, repeated visit tables, event tables, device tables, and extremely wide original-source files.

### Variable Availability by Substudy or Source Group

The substudy availability table confirms two broad inventory regimes. `All_PROFID_sources` is the full variable universe. `Study1` and `Study3` use a much wider ICD/event-registry surface. Studies 2 and 4 through 9 are represented here mainly through the four harmonized transfer tables, with a much smaller and more regular 90-variable profile.

| Substudy/source group | Variables | Covariates | Outcomes | Unknown | Source table mentions | Nonmissing obs points | Missing obs points | Aggregate nonmissing |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| All_PROFID_sources | 5,046 | 682 | 326 | 4,038 | 10,617 | 46,512,451 | 43,783,159 | 51.5% |
| Study1 | 1,027 | 124 | 60 | 843 | 2,355 | 9,890,829 | 9,020,562 | 52.3% |
| Study3 | 1,027 | 124 | 60 | 843 | 2,355 | 9,890,829 | 9,020,562 | 52.3% |
| Study2 | 90 | 36 | 4 | 50 | 322 | 7,147,202 | 5,529,169 | 56.4% |
| Study4 | 90 | 36 | 4 | 50 | 322 | 7,147,202 | 5,529,169 | 56.4% |
| Study5 | 90 | 36 | 4 | 50 | 322 | 7,147,202 | 5,529,169 | 56.4% |
| Study6 | 90 | 36 | 4 | 50 | 322 | 7,147,202 | 5,529,169 | 56.4% |
| Study7 | 90 | 36 | 4 | 50 | 322 | 7,147,202 | 5,529,169 | 56.4% |
| Study8 | 90 | 36 | 4 | 50 | 322 | 7,147,202 | 5,529,169 | 56.4% |
| Study9 | 90 | 36 | 4 | 50 | 322 | 7,147,202 | 5,529,169 | 56.4% |

Quantitatively:

- The all-source roll-up contains 5,046 normalized variables: 682 covariates, 326 outcomes, and 4,038 variables still classified as unknown by the current heuristic.
- Study1 and Study3 each expose 1,027 normalized variables, including 124 covariates and 60 outcome variables. This reflects the richer ICD shock/therapy/death event registry surface.
- Studies 2 and 4 through 9 each show 90 normalized variables in this inventory: 36 covariates, 4 outcomes, and 50 unknown fields, consistent with analyses based on the harmonized transfer files.
- The all-source aggregate nonmissing percentage is 51.5%. This aggregate is strongly affected by sparse wide tables and repeated-event structures, so variable-specific availability is more meaningful than the global percentage.

### Availability by Dataset and Stage

This table is the most useful view for deciding whether to use original files, processed files, or transfer files for a future project. Original files are richer but messier. Processed files are generally smaller and more harmonized. Transfer files are the most immediately reusable for whole-cohort patient-level survival work.

| Source dataset | Stage | Variables | Cov | Out | Unknown | Table mentions | Nonmissing | Missing | Aggregate nonmissing |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Data_Transfer_to_Charite | transfer | 90 | 36 | 4 | 50 | 322 | 7,147,202 | 5,529,169 | 56.4% |
| artemis | original | 549 | 83 | 19 | 447 | 549 | 1,010,119 | 58,235 | 94.5% |
| artemis | processed | 60 | 23 | 4 | 33 | 60 | 57,266 | 934 | 98.4% |
| aston-rdb | original | 107 | 19 | 33 | 55 | 242 | 209,505 | 27,157 | 88.5% |
| aston-rdb | processed | 22 | 11 | 2 | 9 | 22 | 15,390 | 142 | 99.1% |
| derivate | original | 177 | 66 | 17 | 94 | 346 | 260,607 | 35,925 | 87.9% |
| derivate | processed | 41 | 16 | 4 | 21 | 82 | 30,653 | 1,368 | 95.7% |
| do-it | original | 126 | 39 | 13 | 74 | 126 | 97,118 | 13,888 | 87.5% |
| do-it | processed | 61 | 26 | 5 | 30 | 61 | 32,809 | 1,778 | 94.9% |
| eu-cert-icd | original | 60 | 22 | 16 | 22 | 60 | 182,306 | 104,587 | 63.5% |
| eu-cert-icd | processed | 27 | 12 | 5 | 10 | 27 | 42,449 | 11,713 | 78.4% |
| eu-trig-treat | original | 61 | 13 | 6 | 42 | 121 | 68,027 | 8,808 | 88.5% |
| eu-trig-treat | processed | 28 | 8 | 5 | 15 | 28 | 2,991 | 229 | 92.9% |
| french-icd | original | 57 | 7 | 1 | 49 | 114 | 417,572 | 206,978 | 66.9% |
| french-icd | processed | 30 | 11 | 5 | 14 | 30 | 36,666 | 10,734 | 77.4% |
| helios-rdb | original | 224 | 35 | 19 | 170 | 666 | 345,696 | 85,665 | 80.1% |
| helios-rdb | processed | 74 | 28 | 6 | 40 | 74 | 24,523 | 8,703 | 73.8% |
| isar-rdb | original | 68 | 26 | 8 | 34 | 68 | 239,683 | 21,437 | 91.8% |
| isar-rdb | processed | 43 | 22 | 4 | 17 | 43 | 152,417 | 11,155 | 93.2% |
| israeli-icd | original | 560 | 20 | 1 | 539 | 560 | 1,911,980 | 3,271,380 | 36.9% |
| israeli-icd | processed | 42 | 19 | 6 | 17 | 42 | 28,663 | 2,963 | 90.6% |
| madit-ii | original | 239 | 2 | 2 | 235 | 1,097 | 1,451,818 | 150,641 | 90.6% |
| madit-ii | processed | 45 | 18 | 4 | 23 | 90 | 54,201 | 1,194 | 97.8% |
| madit-rit | original | 128 | 2 | 1 | 125 | 340 | 599,145 | 115,005 | 83.9% |
| madit-rit | processed | 38 | 16 | 5 | 17 | 38 | 26,798 | 182 | 99.3% |
| nancy-rdb | original | 106 | 47 | 9 | 50 | 106 | 19,367 | 0 | 100.0% |
| nancy-rdb | processed | 36 | 21 | 4 | 11 | 36 | 3,570 | 30 | 99.2% |
| olomouc-rdb | original | 305 | 54 | 4 | 247 | 614 | 3,792,055 | 8,738,677 | 30.3% |
| olomouc-rdb | processed | 46 | 17 | 5 | 24 | 46 | 33,149 | 4,479 | 88.1% |
| predetermine | original | 172 | 44 | 21 | 107 | 625 | 2,521,509 | 1,200,991 | 67.7% |
| predetermine | processed | 71 | 32 | 5 | 34 | 71 | 353,120 | 57,189 | 86.1% |
| prose-icd | original | 113 | 19 | 19 | 75 | 258 | 92,957 | 2,878 | 97.0% |
| prose-icd | processed | 38 | 15 | 3 | 20 | 38 | 14,804 | 168 | 98.9% |
| prose-lvscd | original | 113 | 19 | 19 | 75 | 258 | 92,957 | 2,878 | 97.0% |
| prose-lvscd | processed | 50 | 19 | 4 | 27 | 50 | 7,292 | 458 | 94.1% |
| scd-heft | original | 1,781 | 151 | 29 | 1,601 | 2,764 | 15,889,978 | 22,170,673 | 41.7% |
| scd-heft | processed | 53 | 20 | 3 | 30 | 106 | 68,435 | 836 | 98.8% |
| silesian-rdb | original | 311 | 71 | 107 | 133 | 320 | 163,766 | 17,204 | 90.5% |
| silesian-rdb | processed | 55 | 32 | 4 | 19 | 55 | 32,536 | 2,554 | 92.7% |
| swedish-hr | processed | 62 | 31 | 2 | 29 | 62 | 8,981,352 | 1,904,174 | 82.5% |

### Outcome Inventory

The outcome observation-point file contains 650 outcome-tagged column rows, 326 unique normalized outcome variables, 21 source datasets, and 100 observation tables. Outcome columns are distributed as follows.

| Domain | Columns | Unique variables | Datasets | Tables | Nonmissing | Missing | Median nonmissing | Aggregate nonmissing |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| outcome_death | 177 | 88 | 18 | 40 | 174,046 | 45,935 | 100.0% | 79.1% |
| outcome_device_therapy | 157 | 61 | 18 | 61 | 146,555 | 302,547 | 98.5% | 32.6% |
| outcome_followup_time | 145 | 107 | 21 | 41 | 421,790 | 13,824 | 100.0% | 96.8% |
| outcome_scd | 83 | 32 | 10 | 30 | 239,460 | 168,283 | 100.0% | 58.7% |
| outcome_other | 74 | 27 | 21 | 43 | 376,873 | 76,623 | 100.0% | 83.1% |
| cardiac_function | 9 | 7 | 3 | 6 | 5,839 | 734 | 99.8% | 88.8% |
| medication | 2 | 1 | 1 | 2 | 806 | 41,363 | 1.1% | 1.9% |
| comorbidity | 1 | 1 | 1 | 1 | 665 | 0 | 100.0% | 100.0% |
| device | 1 | 1 | 1 | 1 | 181 | 0 | 100.0% | 100.0% |
| ecg_imaging | 1 | 1 | 1 | 1 | 645 | 38 | 94.4% | 94.4% |

The strongest whole-cohort outcome fields are `status` and `survival_time`:

- `status` appears in 21 datasets, with 347,883 nonmissing and 871 missing observation points in the dataset-stage roll-up.
- `survival_time` appears in 21 datasets, with 345,476 nonmissing and 957 missing observation points.
- Outcome follow-up time is therefore broadly available, but the unit must still be explicitly standardized before modeling. The inventory reports names and missingness, not semantic units.
- Device therapy outcomes are present but distributed across specialized ICD sources and contain heterogeneous names. They are not a single plug-and-play endpoint across the full data lake.

### Covariate Inventory

The covariate observation-point file contains 1,999 covariate-tagged column rows, 682 unique normalized covariate variables, 21 source datasets, and 200 observation tables.

| Domain | Columns | Unique variables | Datasets | Tables | Nonmissing | Missing | Median nonmissing | Aggregate nonmissing |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| demographics | 412 | 50 | 21 | 155 | 2,374,126 | 2,886,263 | 100.0% | 45.1% |
| medication | 293 | 125 | 20 | 81 | 1,992,611 | 1,156,874 | 99.2% | 63.3% |
| covariate_other | 243 | 94 | 16 | 56 | 1,146,047 | 1,083,456 | 88.3% | 51.4% |
| comorbidity | 238 | 72 | 20 | 65 | 2,097,147 | 654,661 | 99.9% | 76.2% |
| ecg_imaging | 230 | 157 | 18 | 54 | 325,319 | 176,682 | 97.5% | 64.8% |
| labs_or_biomarkers | 193 | 35 | 19 | 62 | 2,084,654 | 701,799 | 97.5% | 74.8% |
| cardiac_function | 151 | 50 | 21 | 71 | 589,756 | 649,761 | 99.7% | 47.6% |
| procedure | 125 | 49 | 15 | 43 | 1,645,972 | 421,557 | 99.7% | 79.6% |
| renal | 72 | 27 | 19 | 52 | 385,031 | 325,927 | 96.4% | 54.2% |
| device | 42 | 23 | 12 | 23 | 116,356 | 194,774 | 91.0% | 37.4% |

Covariate availability is strongest for demographics, core comorbidities, common medications, renal function, BMI, and LVEF-related fields. It is more source-specific for ECG intervals, device details, cardiac imaging/scar variables, NYHA, and specialized biomarkers.

### Key Variable Coverage for Future Analyses

The following table uses `profid_variable_availability_by_dataset.csv`, so it is the best direct input for feasibility screening. `Datasets` counts source datasets with that normalized variable; `Table mentions` counts contributing source tables in the roll-up; nonmissing and missing are summed observation points across those source-dataset/stage entries.

| Variable | Role | Domain | Datasets | Table mentions | Nonmissing | Missing | Aggregate nonmissing | Median table nonmissing |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| status | outcome | outcome_other | 21 | 29 | 347,883 | 871 | 99.8% | 100.0% |
| survival_time | outcome | outcome_followup_time | 21 | 27 | 345,476 | 957 | 99.7% | 100.0% |
| age | covariate | demographics | 21 | 53 | 393,497 | 20 | 100.0% | 100.0% |
| sex | covariate | demographics | 21 | 39 | 417,972 | 2,825 | 99.3% | 100.0% |
| lvef | covariate | cardiac_function | 20 | 38 | 319,864 | 64,118 | 83.3% | 99.5% |
| bmi | covariate | labs_or_biomarkers | 18 | 44 | 332,905 | 51,425 | 86.6% | 97.6% |
| egfr | covariate | renal | 17 | 33 | 325,740 | 21,501 | 93.8% | 97.8% |
| haemoglobin | covariate | labs_or_biomarkers | 10 | 14 | 294,846 | 38,816 | 88.4% | 93.6% |
| diabetes | covariate | comorbidity | 20 | 31 | 344,711 | 6,262 | 98.2% | 100.0% |
| hypertension | covariate | comorbidity | 16 | 25 | 335,438 | 11,068 | 96.8% | 100.0% |
| smoking | covariate | comorbidity | 15 | 25 | 320,553 | 27,714 | 92.0% | 100.0% |
| af_atrial_flutter | covariate | comorbidity | 16 | 21 | 319,908 | 21,943 | 93.6% | 99.8% |
| nyha | covariate | cardiac_function | 19 | 35 | 86,780 | 302,538 | 22.3% | 99.1% |
| qrs | covariate | ecg_imaging | 14 | 25 | 44,897 | 129,001 | 25.8% | 97.8% |
| qtc | unknown | unknown | 11 | 27 | 57,005 | 141,055 | 28.8% | 97.4% |
| lbbb | unknown | unknown | 13 | 22 | 319,309 | 20,500 | 94.0% | 98.5% |
| rbbb | unknown | unknown | 7 | 12 | 310,038 | 24,778 | 92.6% | 98.0% |
| beta_blockers | covariate | medication | 20 | 27 | 342,332 | 3,576 | 99.0% | 100.0% |
| ace_inhibitor | covariate | medication | 12 | 20 | 332,950 | 9,312 | 97.3% | 100.0% |
| ace_inhibitor_arb | covariate | medication | 9 | 13 | 149,893 | 4,207 | 97.3% | 100.0% |
| arb | covariate | medication | 10 | 15 | 320,004 | 15,397 | 95.4% | 100.0% |
| aldosterone_antagonist | unknown | unknown | 11 | 16 | 175,134 | 160,797 | 52.1% | 100.0% |
| diuretics | unknown | unknown | 18 | 27 | 346,861 | 4,213 | 98.8% | 100.0% |
| lipid_lowering_statins | covariate | labs_or_biomarkers | 15 | 18 | 194,286 | 896 | 99.5% | 100.0% |
| pci | covariate | procedure | 13 | 20 | 325,786 | 16,644 | 95.1% | 99.8% |
| cabg | covariate | procedure | 14 | 23 | 331,974 | 14,469 | 95.8% | 100.0% |
| fh_scd | outcome | outcome_scd | 5 | 9 | 16,421 | 139,982 | 10.5% | 86.0% |
| death | outcome | outcome_death | 6 | 14 | 18,106 | 1 | 100.0% | 100.0% |
| appshock | outcome | outcome_device_therapy | 2 | 4 | 2,568 | 0 | 100.0% | 100.0% |
| inappshock | outcome | outcome_device_therapy | 2 | 4 | 2,568 | 0 | 100.0% | 100.0% |
| apptherapy | outcome | outcome_device_therapy | 2 | 4 | 1,386 | 0 | 100.0% | 100.0% |
| appatp1 | unknown | unknown | 1 | 1 | 9,256 | 0 | 100.0% | 100.0% |

Practical interpretation:

- Very high-feasibility pooled variables: `status`, `survival_time`, `age`, `sex`, `diabetes`, `beta_blockers`, `pci`, `cabg`, and several treatment/procedure fields. These have broad dataset coverage and high median table-level completeness.
- High-feasibility but missingness-sensitive variables: `lvef`, `bmi`, `egfr`, `haemoglobin`, `hypertension`, `smoking`, and `af_atrial_flutter`. These are available in many datasets but still require source-specific missingness handling and clear inclusion rules.
- Clinically important but structurally weaker variables: `nyha`, `qrs`, `qtc`, `fh_scd`, and device-therapy endpoints. They are important for ICD and risk-modeling questions, but their availability is narrower, their coding is more heterogeneous, or the aggregate completeness is lower.
- Medication variable classification needs manual review. For example, `aldosterone_antagonist`, `diuretics`, `anti_platelet`, and some anticoagulant fields are currently classified as `unknown` in the inventory despite being clinically interpretable medication variables. A curated medication map should be created before GDMT analyses.
- No normalized `mra` or `raas` variable is present in the direct availability roll-up. Future analyses should derive these from source variables such as `aldosterone_antagonist`, `spironolactone`, `ace_inhibitor`, `arb`, and `ace_inhibitor_arb`.

### What Is Available for Subsequent Projects

The direct inventory supports the following project-ready data layers.

1. `core_patient_survival`: feasible now from the transfer and processed patient-record sources. Required fields `status`, `survival_time`, `age`, `sex`, `lvef`, `bmi`, `egfr`, `diabetes`, `hypertension`, `smoking`, `af_atrial_flutter`, `beta_blockers`, `pci`, and `cabg` all have broad availability, although LVEF/BMI/eGFR and AF still need source-specific completeness checks.
2. `source_specific_event_registry`: feasible for ICD-event projects, but not as a single universal endpoint. The inventory shows device therapy, shock, ATP, and death fields in several ICD-focused datasets, especially event-row sources. A source-specific endpoint crosswalk is mandatory.
3. `processed_cdm_analysis_layer`: highly recommended as the first pass for pooled analyses. Processed files are present for most sources and usually have fewer variables but much cleaner completeness than raw originals.
4. `raw_source_enrichment_layer`: useful when a project needs variables not included in the processed files, such as detailed visit histories, raw ECG/device fields, repeated measurements, or specialized biomarkers. This layer is high-volume and high-heterogeneity.
5. `data_dictionary_and_maps_layer`: non-observation sources include CDM specifications, dataset dictionaries, and maps. These should be used to resolve unknown variables, units, and source-specific coding before analysis.

### Data-Quality and Harmonization Implications From the CSV Inventory

The inventory changes the data-quality picture in several ways:

- The data lake is larger and more heterogeneous than the substudy scripts alone imply: 363 table/sheet/object entries are represented in the master inventory, including 289 observation-source entries.
- The processed/transfer layers are much better suited to immediate whole-cohort survival analyses than the raw/original layer. Raw sources contain more variables but also more sparse, repeated, and source-specific structures.
- The current role/domain classifier leaves many columns as `unknown`: 10,844 observation-source column rows in the master inventory and 4,038 variables in the all-source availability roll-up. This is expected for a broad raw-data inventory, but it means a curated variable dictionary is not optional.
- Global missingness percentages can be misleading because visit and event tables inflate denominator cells. Feasibility decisions should use variable-by-source tables and patient-level analysis cohorts rather than global cell counts.
- Outcome semantics still need confirmation. `status` and `survival_time` are broadly available, but the inventory cannot prove whether `status == 1` always means SCD, appropriate ICD therapy, death, or another source-specific endpoint.
- Follow-up-time units remain a key unresolved contract. The inventory confirms broad `survival_time` availability, not whether all sources encode it in the same unit.
- The Swedish original source needs a special handling path if its 3,860-column raw table is needed. The processed Swedish CDM is usable, but raw-variable enrichment will require either a size-limit override or a targeted reader strategy.
- Missing reader support for `readODS` and `arrow` should be fixed before calling this an exhaustive inventory, even though the main CSV, XLS/XLSX, SAS, SAV, DTA, RDS, and archive-member surfaces are substantially covered.

### Updated Project Feasibility Ranking Based on the Direct Inventory

Tier A, ready for pooled analysis after endpoint/unit validation:

- Whole-cohort survival/SCD and competing-risk models using `status`, `survival_time`, demographics, LVEF, BMI, eGFR, diabetes, hypertension, smoking, AF/flutter, beta-blockers, ACE/ARB-derived therapy, PCI, and CABG.
- Source/geography/registry heterogeneity analyses using source identifiers, processed CDM files, transfer files, and patient-record count units.
- Treatment-era and baseline-therapy uptake analyses after deriving RAAS/MRA/GDMT variables from component medication fields.

Tier B, feasible but requiring curated source-specific mappings:

- ICD shock/therapy/ATP/death projects.
- NYHA, ECG interval, LBBB/RBBB/QRS/QTc incremental-value models.
- Biomarker and lab-enriched risk models beyond eGFR, hemoglobin, and BMI.
- Raw-source enrichment projects that pull variables not present in processed CDM files.

Tier C, exploratory until the dictionary is curated:

- Automated phenotyping over all 5,046 all-source variables.
- Repeated-visit trajectory models across all visit tables.
- Device-manufacturer or detailed device-programming analyses.
- Projects depending on currently `unknown` variables, unless those variables are manually mapped first.

## Repository-Level Data Assets

### Core Cohort Files

The same small set of cohort files appears repeatedly:

| File or object | Inferred content | Studies using it |
| --- | --- | --- |
| `ICD.csv` | ICD recipient cohort, post-MI, baseline phenotype, event/follow-up status, likely reduced EF enrichment. | Studies 1, 2, 3, 4, 6, 8, and raw input to several workflows. |
| `ICD_all.csv` | Larger or reference ICD extract, sometimes loaded for checks but not always included. | Studies 2 and 4. |
| `NonICD_reduced.csv` | Non-ICD post-MI cohort with reduced LVEF. | Studies 2, 4, 6, 7, 8. |
| `NonICD_preserved.csv` | Non-ICD post-MI cohort with preserved LVEF. | Studies 2, 4, 6, 7, 8. |
| `combined_dataset.csv` | Stacked ICD plus non-ICD cohort used for descriptive and survival analyses. | Study 6 and likely upstream Study 4/5-derived workflows. |
| `combined_icd.csv` | Stacked dataset used for BMI imputation/modeling in Study 6. Despite the name, it appears to include the analysis population for the BMI/SCD work. | Study 6. |
| `df_handled.csv` / `df_handled.rds` | Harmonized, analysis-ready Study 4/5/9-style data with `Status`, `Survival_time`, `ICD_status`, age groups, SCD event fields, and covariates. | Studies 4, 5, 9. |
| `df_cleaned.rds` | Cleaned patient-level cohort with temporal, seasonal, environmental, and clinical variables. | Study 2. |
| `vs_data_complete.csv` | Study 8 model-ready complete-case / imputed dataset for AF/SCD risk modeling. | Study 8. |

### Dataset Folders in the Broader Data Tree

`Repo-Structure.md` documents the broader PROFID data tree under `datasets/local/`. The listed source datasets are:

- `artemis`
- `aston-rdb`
- `barcelona`
- `derivate`
- `do-it`
- `eu-cert-icd`
- `eu-trig-treat`
- `french-icd`
- `helios-rdb`
- `isar-rdb`
- `israeli-icd`
- `madit-ii`
- `madit-rit`
- `nancy-rdb`
- `olomouc-rdb`
- `predetermine`
- `prose-icd`
- `prose-lvscd`
- `scd-heft`
- `silesian-rdb`
- `swedish-hr`

Most have processed common-data-model RDS files such as `cert-common-data-model.rds`, `hels-common-data-model.rds`, `isrl-common-data-model.rds`, `prsi-common-data-model.rds`, and equivalent abbreviations. This suggests the data lake is substantially broader than any one substudy, even if many analyses consume the curated transfer files.

### ICD Event Registry Files

Study 1 and Study 3 indicate richer ICD event data from:

- EU-CERT-ICD
- HELIOS / Heart Center Leipzig
- Israeli National ICD Registry
- PROSE-ICD
- PROSE-LVSCD / LCV

Study 3 maps these into harmonized event variables including inappropriate shock, appropriate shock, ATP, death, device type, and follow-up.

### Geographic and Environmental Files

Study 7 reads geocoded cohort files:

- `ICD_filtered_with_coords.csv`
- `NonICD_reduced_filtered_with_coords.csv`
- `NonICD_preserved_filtered_with_coords.csv`

Study 2 uses:

- `DB_lookup_table_final.csv`
- `research_centres_UPDATED.txt`
- ERA5 climate files such as `climate_all_centers.rds`

The DB lookup table includes registry code, registry name, country/city, coordinate type, latitude/longitude when available, environmental resolution, and climate strategy.

## Cohort Structure Inferred From Code

### Main Cohort Dimensions

The code consistently distinguishes:

| Cohort dimension | Common variable(s) | Inferred levels |
| --- | --- | --- |
| ICD versus non-ICD | `ICD_status`, `ICD_bin`, `Group`, source file | ICD, non-ICD reduced, non-ICD preserved. |
| LVEF status | `LVEF`, `LVEF_num`, `LVEF_category`, `lvef35_grp` | Reduced, preserved, `<35`, `>=35`, `<40`, `<=35`, `36-50`, `>50`, depending on study. |
| Source database | `DB`, `dataset`, `db_raw`, `db_grp` | CERT, HELS, ISRL, PRSE, ASTN, DRVT, DOIT, ATMS, FREN, ISAR, MDII, MDRT, NANC, OLMC, PRDT, SHFT, SLSN, SWHR, and others. |
| Calendar time | `Time_zero_Y`, `Year_index`, `band_2000_2020`, `Period_2000_2020` | Annual year, 2000-2004, 2005-2009, 2010-2014, 2015-2020. |
| Geography | `CVD_risk_region`, `ctr_name`, `center`, `DB`, coordinates | Low, Medium, High, Very High risk regions; center/country/city where available. |
| Device type | `icd_type`, `device_group` | Single-chamber ICD, dual-chamber ICD; CRT exclusions in some ICD-specific workflows. |

### Concrete Cohort Sizes Found in Code/Outputs

Only some sizes are visible in comments or checked-in outputs:

- Study 4 script comments report input dimensions:
  - `ICD`: 7,543 rows and 75 columns.
  - `NonICD_preserved`: 107,603 rows and 88 columns.
  - `NonICD_reduced`: 25,058 rows and 88 columns.
- Study 6 checked-in outputs report:
  - Full BMI/SCD analysis dataset: 121,481 participants.
  - SCD events: 2,865 events, 2.4%.
  - Extended complete-case dataset: 72,195 participants and 1,087 events.
  - Complete-case retention: 59.43% of participants and 37.94% of events.
- Study 6 BMI category table shows approximate category counts:
  - Underweight: 1,560.
  - Normal: 39,692.
  - Overweight: 52,099.
  - Obese I: 20,909.
  - Obese II: 5,401.
  - Obese III: 1,820.

The top-level README states that PROFID is built around approximately 200,000 post-MI patients, but not all scripts operate on all records.

## Outcome and Follow-Up Variables

### Common Full-Cohort SCD Endpoint

The most common endpoint convention is:

| Variable | Meaning inferred from code |
| --- | --- |
| `Status` | Multi-state outcome code. Generally `0 = censored`, `1 = SCD`, `2 = non-SCD death or competing event`. |
| `Survival_time` | Follow-up duration. Most full-cohort scripts treat it as months, but some scripts/comments are inconsistent. This unit must be standardized before new pooled analyses. |
| `Status_cs1` | Cause-specific SCD event indicator, usually `Status == 1` and all else treated as non-event. |
| `Status_cs1_h` | Horizon-censored SCD indicator, often for 90-month analyses. |
| `Survival_time_h` | Horizon-censored follow-up time, often `pmin(Survival_time, 90)`. |
| `event_scd`, `event_SCD`, `status_scd`, `SCD_bin` | Binary SCD event indicator derived from `Status == 1` or from `SCD_event`. |
| `event_COMP`, `status_nonscd` | Competing non-SCD event indicator, usually `Status == 2`. |
| `fstatus` | Fine-Gray/competing-risk outcome code preserving censored/SCD/non-SCD states. |
| `ftime_mo_int` | Follow-up time in integer months for competing-risk models. |
| `person_years`, `py`, `log_py` | Person-time for rate models, sometimes derived from follow-up months divided by 12. |

### ICD-Specific Mortality and Inappropriate Therapy Endpoint

Study 1 is centered on ICD patients and uses a different endpoint/exposure structure:

| Variable | Meaning |
| --- | --- |
| `Status_death` | All-cause mortality indicator. |
| `Time_death_days` | Follow-up time to death or censoring in days. |
| `Status_FIS` | First inappropriate ICD shock or inappropriate ICD therapy indicator. |
| `Time_FIS_days` | Time to first inappropriate shock/therapy, or censoring time, in days. |
| `FIS_td` | Time-dependent inappropriate shock/therapy exposure generated by `survival::tmerge()`. |
| `FIS_L` | Landmark-fixed exposure: inappropriate shock/therapy by the landmark time. |
| `Status_fg` | Fine-Gray status in the landmark competing-risk script. |

Study 1 cleaning rules are clinically important:

- Patients with missing or zero `Time_death_days` are removed.
- Missing `Status_death` with valid follow-up is recoded as censored/alive.
- Missing `Status_FIS` and missing `Time_FIS_days` are treated as unexposed, with FIS time set to follow-up time.
- If `Time_FIS_days >= Time_death_days`, the FIS event is reclassified as unexposed and FIS time is set to follow-up.
- Time-dependent Cox modeling avoids classifying patients as exposed before their shock occurred.

### ICD Device Therapy Endpoint

Study 3 focuses on ICD shock outcomes and device group:

| Variable | Meaning |
| --- | --- |
| `device_group` | Single-chamber versus dual-chamber ICD. |
| `inapp_shock_flag` | Raw/harmonized inappropriate shock flag. |
| `event_inapp_shock` | `1` for standardized inappropriate shock flag equal to yes; no, unknown, and missing are treated as 0. |
| `days_to_inapp_shock` | Time to inappropriate shock; capped at follow-up if beyond follow-up. |
| `app_shock_flag` | Appropriate shock flag. |
| `days_to_app_shock` | Time to appropriate shock. |
| `app_therapy_flag`, `app_atp_flag`, `Inapp_ATP` | Additional ICD therapy/ATP indicators. |
| `total_app_shock`, `total_inapp_shock`, `total_ATP`, `total_inapp_ATP` | Recurrent event burden/count variables. |
| `death_flag`, `days_to_death`, `death_date` | Mortality fields in ICD event sources. |
| `t_followup_days`, `t_followup_days_final` | Follow-up time for device-event survival models. |
| `fg_event` | Competing-risk event code: inappropriate shock versus death before inappropriate shock. |

### ICD Proxy Endpoint in Calendar-Time Analyses

Study 9 uses a cohort-specific event definition:

| Cohort | Endpoint |
| --- | --- |
| Non-ICD | SCD, represented by `SCD_bin` / `SCD_event`. |
| ICD | Appropriate ICD therapy proxy, `ICD_proxy_bin = 1` if `ICD_bin == 1` and `Status_num == 1`. |

This proxy definition should be validated before any manuscript-level interpretation, because `Status == 1` has SCD semantics in non-ICD/full-cohort scripts but proxy-therapy semantics in Study 9's ICD analysis.

### Therapy Uptake Endpoint

Study 5 is not an event-outcome survival study. It models baseline HFrEF therapy uptake:

| Variable | Meaning |
| --- | --- |
| `RAAS` | ACE inhibitor/ARB, optionally including ARNI where present. |
| `BB` | Beta-blocker. |
| `MRA` | Mineralocorticoid receptor antagonist. |
| `HF_n_classes` | Count of disease-modifying HFrEF medication classes: `RAAS + BB + MRA`, clamped 0-3. |
| `HF_GDMT_count4` | Four-level therapy count: 0, 1, 2, 3. |
| `HF_GDMT_cat` | Grouped therapy count: 0, 1-2, 3+. |
| `HF_BIN_eq3` | Primary endpoint: receipt of all three classes. |
| `HF_BIN_geq2` | Sensitivity endpoint in some scripts: at least two classes. |
| `Diuretics` | Descriptive therapy variable, not part of disease-modifying count. |
| `SGLT2` | Audited only, expected absent or sparse in the current extract. |

## Time Variables and Calendar Features

The data contain or derive several time concepts:

| Domain | Variables |
| --- | --- |
| Baseline/index date | `Time_zero_Y`, `Time_zero_Ym`, `time_zero`, `time_zero_ym`, `Year_index`. |
| Follow-up duration | `Survival_time`, `Time_death_days`, `t_followup_days`, `t_followup_days_final`, `ftime_mo_int`, `person_years`, `py`. |
| MI timing | `Time_index_MI_CHD`, `Time_index_MI_CHD_num`, `Time_index_MI_CHD_log1p`, `MI_date`, `first_mi_date`, `mi_history`, `number_of_mi`. |
| Calendar bands | `Period_2000_2020`, `band_2000_2020`, `year_decade`, 2000-2004, 2005-2009, 2010-2014, 2015-2020. |
| Seasonal features | `month_num`, `month_lab`, `season`, `sin_time`, `cos_time`, `day_of_year`, `month_start`, `fu_band`. |
| Holidays/environment | Christmas/New Year indicator, Easter window, daylight saving indicator, daily weather variables. |
| ICD event dates | `icd_implant_date`, `inapp_shock_date`, `app_shock_date`, `death_date`, `last_fu_date`. |

Time-unit consistency is the most important unresolved data-contract issue. `Survival_time` is usually treated as months, while Study 8 comments alternate between days and months, and Study 1 uses explicit days for ICD therapy/mortality timing.

## Covariate Inventory by Domain

### Demographics and Cohort Metadata

| Domain | Variables seen in code |
| --- | --- |
| Patient identifiers | `ID`, `id`, `patient_id`, `patient_id_full`, registry-specific prefixes such as CERT/HELS/ISRL/PRSE. |
| Source information | `DB`, `dataset`, `Group`, `db_raw`, `db_grp`, `Database`, `Registry`. |
| Demographics | `Age`, `Age_num`, `Age_years`, `age_icd`, `Age_group`, `Age3`, `age65`, `Sex`, `Sex_BIN_Male`, `sex_bin`, `Gender`, `Male`. |
| Anthropometrics | `BMI`, `BMI_cat`, `height_cm`, `weight_kg`. |
| Geography | `CVD_risk_region`, `ctr_name`, `center`, `center_id`, city, country, latitude, longitude. |
| Calendar/source | `Year_index`, `Period_2000_2020`, `time_period`, `DB_plot`. |

### Cardiac Phenotype and Severity

| Domain | Variables seen in code |
| --- | --- |
| LVEF | `LVEF`, `LVEF_num`, `LVEF_ESC`, `MRI_LVEF`, `LVEF_percent`, `LVEF_pct`, `LVEF_baseline`, `EF`, `EjectionFraction`, `LVEF_category`, `lvef35_grp`, `LVEF_cat`, `lvef30`. |
| Heart failure | `HF`, `heart_failure`, `NYHA`, `nyha`, `NYHA_bin`, `NYHA_grp`, `Baseline_type`, `Baseline_within40d`. |
| Imaging/scar | `Infarct_size`, `Total_scar`, `Greyzone_size`, `LV_mass`, `LVDD`, `LVEDV`, `LVESV`, `MR`, `MR_severity`. |
| MI history | `MI_history`, `MI_type`, `MI_location_anterior`, `MI_location_posterior`, `number_of_mi`, `first_mi_flag`. |
| Device | `ICD_status`, `ICD_bin`, `ICD_BIN_Yes`, `icd_type`, `device_group`, CRT exclusions in Study 1. |

### Comorbidities and History

| Domain | Variables seen in code |
| --- | --- |
| Metabolic/vascular | `Diabetes`, `Diabetes_BIN_Yes`, `Hypertension`, `Hypertension_BIN_Yes`, `Dyslipidemia`, `Smoking`, `Smoking_BIN_Yes`, `Alcohol`. |
| Arrhythmia | `AF`, `AF_any`, `AF_atrial_flutter`, `AF_atrial_flutter_BIN_Yes`, `af_history`, `NSVT`. |
| Cerebrovascular | `Stroke_TIA`, `Stroke_TIA_BIN_Yes`, `stroke_tia`, `stroke`, `tia`. |
| Pulmonary/renal | `COPD`, `COPD_cat`, `CKD`. |
| Other | `Cancer`, `FH_CAD`, `FH_SCD`, `heart_tx`, `heart_lung_tx_date`, `HCM`, `DCM`, `ICM`, `cardiomyopathy`, `congenital_hd`. |

### Vitals, ECG, and Labs

| Domain | Variables seen in code |
| --- | --- |
| Vitals | `SBP`, `DBP`, `HR`, `heart_rate`, `ecg_hr`. |
| ECG/conduction | `PR`, `QRS`, `QRS_log1p`, `qrs_ms`, `QTc`, `qtc_ms`, `AV_block`, `AV_block_II_or_III`, `LBBB`, `RBBB`, `lbbb`. |
| Renal/metabolic labs | `eGFR`, `eGFR_num`, `eGFR_log1p`, `Creatinine`, `BUN`, `Sodium`, `Sodium_log1p`, `Potassium`, `Potassium_log1p`, `Glucose`, `HbA1c`. |
| Hematology | `Haemoglobin`, `Haemoglobin_log1p`, `Hematocrit`. |
| Lipids | `Cholesterol`, `LDL`, `HDL`, `Triglycerides`, `Lipid_lowering`. |
| Biomarkers | `CRP`, `Troponin_T`, `Troponin_I`, `NTProBNP`, `NTProBNP_log1p`, `CKMB`, `Myoglobin`, `IL6`, `IL10`, `TNF_receptor`, `TSH`. |

### Medications and Procedures

| Domain | Variables seen in code |
| --- | --- |
| HF therapy | `ACE_inhibitor`, `ARB`, `ACE_inhibitor_ARB`, `ACEI_ARB`, `ARNI`, `RAAS`, `Beta_blockers`, `BB`, `Aldosterone_antagonist`, `MRA`, `SGLT2`. |
| Other cardiovascular drugs | `Diuretics`, `LoopDiuretic_drug_specific`, `Anti_anginal`, `Calcium_antagonists`, `Anti_arrhythmic_III`, `antiarrhythmic_class`, `Anti_coagulant`, `anticoagulant_noac`, `Anti_platelet`, `aspirin`, `Statin`, `Lipid_lowering`, `Digitalis_glycosides`, `digoxin`. |
| Diabetes drugs | `Anti_diabetic`, `Anti_diabetic_oral`, `Anti_diabetic_insulin`. |
| Revascularization | `PCI`, `CABG`, `Revascularisation_acute`, `PCI_acute`, `CABG_acute`, `Thromolysis_acute`, `Thrombolysis_acute`, `first_hosp_flag`, `first_hosp_reason`, `total_hosp_count`. |

### Environment and Geography

| Domain | Variables seen in code |
| --- | --- |
| Location | `DB`, `Registry`, `Country_City`, `Coord_Type`, `Latitude`, `Longitude`, `center_id`, `ctr_name_clean`. |
| Exposure resolution | `Environmental_resolution`, `Climate_strategy`: city-level, country-seasonal-average, season-only. |
| Weather | `temp_mean`, `temp_min`, `temp_max`, `pressure`, `sunshine`, `daylight`, annual/winter/summer summaries. |
| Calendar/season | `season`, month, sine/cosine annual terms, holiday indicators, daylight saving. |

## Study-by-Study Data Signal

| Study | Main data used | Main outcome/exposure | Key covariates/methods | What it reveals about available data |
| --- | --- | --- | --- | --- |
| Study 1 | ICD cohort assembled from EU-CERT, HELIOS, Israel, PROSE plus `ICD.csv`. | Exposure: first inappropriate ICD shock/therapy. Outcome: all-cause mortality. | Time-dependent Cox with `FIS_td`, MICE, landmark analysis, Fine-Gray sensitivity. Covariates include age, sex, LVEF, NYHA, eGFR, diabetes, beta-blockers, AF/flutter, hypertension, smoking, hemoglobin, SBP, BMI, HR, QRS, HF, stroke/TIA, AV block, LBBB, medications, PCI, MRI availability. | Rich ICD therapy timing and mortality follow-up are available for selected ICD registries, with event dates/times and device/source information. |
| Study 2 | `ICD.csv`, `NonICD_preserved.csv`, `NonICD_reduced.csv`, center metadata, ERA5 climate files. | SCD seasonality, non-SCD competing death, environmental exposure. | Seasonal Cox, sine/cosine seasonality, piecewise exponential models, penalized spline Cox, cause-specific Cox, Fine-Gray, weather Cox models. | The data include calendar/index dates, event/censoring dates, month/season, center/geography, and enough timing to evaluate seasonal or climate associations. |
| Study 3 | EU-CERT, HELIOS, Israel, PROSE, LCV event data merged with baseline `ICD.csv`. | First inappropriate shock by single versus dual-chamber ICD; appropriate shock and death as secondary/competing fields. | Cox stratified by dataset, KM, Fine-Gray, leave-one-dataset-out sensitivity, MICE. | ICD event-level variables exist: inappropriate shock, appropriate shock, ATP, counts, timing, device type, death/follow-up. |
| Study 4 | `ICD_all`, `ICD`, `NonICD_preserved`, `NonICD_reduced`, and handled full-cohort object. | SCD by age group with non-SCD death as competing event. | Incidence per 1,000 person-years, WHO age-standardization, CIF, Fine-Gray, Cox, validation, MICE, complete-case sensitivity. | Full-cohort SCD and competing-death data support age-stratified incidence and competing-risk modeling. |
| Study 5 | Study 4/5 handled HFrEF dataset restricted to `LVEF < 40`, calendar years 2000-2020. | HFrEF therapy uptake: triple therapy `HF_BIN_eq3`. | Logistic trend and determinant models, complete-case and MICE, FDR-corrected interactions, database variation, optional RF/XGBoost. | Medication fields and calendar time support treatment uptake and implementation-science analyses. |
| Study 6 | `combined_icd.csv`, `combined_dataset.csv`, raw ICD/non-ICD files, MICE objects. | BMI association with SCD, with non-SCD events treated as censoring or competing events in sensitivity analyses. | BMI categories, spline Cox, 90-month horizon, extended lipids/stroke/ICD model, C-index, calibration, PH checks, fractional polynomials, Fine-Gray. | The full cohort supports nonlinear risk modeling with many clinical/lab covariates and imputation diagnostics. |
| Study 7 | Geocoded ICD, non-ICD reduced, and non-ICD preserved files. | Crude SCD and other-death rates by cardiovascular risk region; KM SCD-free survival by region. | Baseline tables, missingness tables, region-specific event summaries, KM plots. | CVD risk region and center/DB-level geography are available for all three major cohorts. |
| Study 8 | `ICD.csv`, `NonICD_preserved.csv`, `NonICD_reduced.csv`, `vs_data_complete.csv`. | SCD risk stratification in AF/post-MI patients; GBM risk score. | Cox, Fine-Gray, survival GBM, RSF, AUC/Brier/C-index, AF-only model, subgroups, sensitivities. Mandatory predictors: LVEF, age, BMI, diabetes, eGFR; optional biomarkers and ECG. | The data can support machine-learning risk prediction, AF-specific modeling, and subgroup validation. |
| Study 9 | `df_handled.csv` and minimal RDS built from it. | Calendar-time trends 2000-2020 in non-ICD SCD and ICD proxy appropriate therapy. | Crude annual/band rates, Poisson/negative-binomial rate models with person-time offset, adjusted models with age/sex/eGFR/LVEF. | The handled dataset supports calendar-time trend models and per-decade incidence rate ratios. |

## Cross-Study Data-Quality and Harmonization Issues

These issues recur across code and should be resolved before new whole-dataset analyses:

1. `Survival_time` units are not globally documented.
   - Study 2, 4, 6, 7, and 9 generally treat it as months.
   - Study 8 comments alternate between days and months.
   - Study 1 uses explicit day variables for ICD-specific analyses.

2. `Status` semantics vary by analysis context.
   - Common full-cohort meaning: 0 censored, 1 SCD, 2 non-SCD death.
   - Study 9 ICD proxy uses `Status == 1` as an appropriate ICD therapy proxy among ICD patients.
   - Study 1 uses separate `Status_death` and `Status_FIS`.

3. Many scripts use hard-coded `T:/`, `S:/`, or UNC paths.
   - A central path/config layer exists for Study 1 and has been adapted for Study 3.
   - Other studies still mix input, output, and working directories.

4. Missingness is domain-specific and often severe.
   - Study 6 missingness outputs show very high missingness for LV volumes, MRI/scar variables, TSH, BUN, CRP, troponin, PR, and alcohol.
   - Core variables such as BMI, survival status, survival time, age, LVEF, eGFR, hemoglobin, medications, and basic comorbidities are much more usable.

5. There are duplicate and divergent scripts.
   - Study 6 has multiple baseline and MICE scripts.
   - Study 8 has duplicated variable-selection/model-development scripts.
   - Study 9 duplicates derivation logic between main and sensitivity scripts.

6. Some scripts use broad formulas such as `~ .`.
   - This can accidentally include helper variables, outcomes, or derived post-outcome indicators as predictors.

7. Several model objects are expected but not produced in this checkout.
   - Examples: external raw data, some RDS intermediate files, final GBM artifacts, MICE objects.

8. Complete-case analyses can be strongly selected.
   - In Study 6, complete-case analyses retained only 59.43% of participants and 37.94% of SCD events, with different LVEF/eGFR profiles.

9. Some logic needs statistical review before reuse.
   - Study 6 subgroup code appears to reuse imputation 1 in a loop.
   - Study 8 factor-to-numeric encoding for GBM may be inconsistent across splits.
   - Study 4 contains parse/logic issues in the first harmonization script.
   - Study 9's ICD proxy endpoint needs semantic confirmation.

## High-Value Whole-Dataset Analysis Projects

The following projects are designed to use the broader dataset rather than repeat one substudy. Each is framed around variables that the code shows are plausibly available.

### 1. Canonical Endpoint and Variable Availability Atlas

Question: What variables, endpoints, time scales, and missingness patterns are truly available across the whole PROFID data lake?

Data:

- All core cohort files and processed CDM files.
- Source identifiers: `DB`, `dataset`, `Group`, `ICD_status`.
- Outcome fields: `Status`, `Survival_time`, `SCD_event`, `Status_death`, `Status_FIS`, therapy fields.
- Covariate domains listed above.

Design:

- Build a variable dictionary with canonical name, aliases, data type, unit, source studies, source datasets, missingness, usable N, and harmonization notes.
- Produce endpoint crosswalks:
  - SCD endpoint.
  - Non-SCD death endpoint.
  - All-cause mortality endpoint.
  - Appropriate ICD therapy proxy.
  - Inappropriate ICD shock/therapy.
  - HFrEF therapy uptake.
- Run automated unit checks for survival time, follow-up days, and person-years.

Outputs:

- `data_dictionary.csv`
- `endpoint_crosswalk.csv`
- `variable_availability_by_DB.csv`
- Heatmaps of missingness by source and cohort.
- A validation report that flags ambiguous or conflicting endpoint definitions.

Why this matters:

Every downstream whole-dataset study depends on a clean data contract. This is the highest-priority project because it turns the current code-derived knowledge into an auditable dataset specification.

### 2. Whole-Cohort Competing-Risk SCD Model With Absolute Risk

Question: Which baseline factors predict SCD when non-SCD death is treated as a competing risk, and what is each patient's absolute SCD risk over clinically relevant horizons?

Data:

- Full combined cohort with `Status` and `Survival_time`.
- Candidate predictors: age, sex, LVEF, BMI, eGFR, hemoglobin, diabetes, hypertension, smoking, AF/flutter, stroke/TIA, MI history/type, medications, revascularization, ICD status, DB, CVD risk region.

Design:

- Primary model: Fine-Gray or cause-specific Cox plus absolute risk conversion at 1, 3, 5, 7.5, and 10 years, depending on follow-up.
- Use MICE for variables below a prespecified missingness threshold.
- Stratify or frailty-adjust by `DB` to account for source heterogeneity.
- Evaluate calibration and C-index by cohort, LVEF band, ICD status, AF status, sex, age group, and calendar period.

Outputs:

- Whole-cohort SCD risk model.
- Absolute risk curves and calibration plots.
- Source-specific transportability table.
- Net-benefit/decision curve analysis for clinically relevant thresholds.

Why this matters:

The whole PROFID scientific question is about identifying patients at risk for SCD in the contemporary post-MI setting. A calibrated competing-risk model is the natural backbone for that work.

### 3. Reassessment of LVEF Thresholds for SCD Risk

Question: Does LVEF retain a threshold relationship with SCD risk at 35% or 40%, or is risk continuous and modified by age, AF, renal function, BMI, and GDMT?

Data:

- `LVEF`, `LVEF_num`, `MRI_LVEF`, LVEF category variables.
- `Status`, `Survival_time`, competing death.
- Covariates: age, sex, eGFR, diabetes, AF/flutter, BMI, medications, ICD status, DB.

Design:

- Model LVEF using restricted cubic splines and fractional polynomials.
- Compare threshold models: `<30`, `<35`, `<40`, `35-50`, `>50`.
- Test interactions:
  - LVEF by age group.
  - LVEF by AF status.
  - LVEF by sex.
  - LVEF by eGFR.
  - LVEF by GDMT/triple therapy where available.
  - LVEF by ICD status.
- Estimate absolute SCD and non-SCD death risk across the LVEF continuum.

Outputs:

- LVEF risk curves.
- Threshold comparison tables.
- Interaction forest plots.
- Clinical decision threshold simulations.

Why this matters:

Current ICD eligibility heavily depends on EF thresholds. The dataset is well positioned to test whether those thresholds are still aligned with observed SCD risk.

### 4. Contemporary Era Effects: SCD, ICD Proxy Events, and GDMT Uptake From 2000 to 2020

Question: How have SCD rates, ICD proxy therapy events, and GDMT uptake changed over calendar time after adjusting for changing case mix?

Data:

- Study 9 calendar dataset: `Year_index`, `person_years`, `SCD_bin`, `ICD_proxy_bin`.
- Study 5 therapy data: `RAAS`, `BB`, `MRA`, `HF_BIN_eq3`, `Diuretics`, `LVEF < 40`.
- Covariates: age, sex, eGFR, LVEF, DB, ICD status, revascularization, comorbidities.

Design:

- Harmonize year/band definitions across Study 5 and Study 9.
- Fit annual rate models with offsets for person-years.
- Fit therapy uptake models for the same years and cohorts.
- Jointly plot:
  - SCD rate by year.
  - ICD proxy event rate by year.
  - Triple therapy uptake by year.
  - Case-mix shifts by age, EF, renal function, and AF.
- Test whether calendar trends attenuate after adding GDMT variables.

Outputs:

- Era trend report.
- Adjusted incidence rate ratios per decade.
- Joint SCD/GDMT visualization.
- Database-adjusted and database-specific trend estimates.

Why this matters:

This connects risk trends to changes in treatment practice, which is more informative than reporting temporal trends in isolation.

### 5. Source and Geography Transportability Study

Question: Do SCD risk models and event rates transport across databases, countries, registry types, and CVD risk regions?

Data:

- `DB`, `dataset`, registry metadata, `CVD_risk_region`, center/country/city fields.
- `Status`, `Survival_time`, person-years.
- Core predictors and model outputs from Studies 6 and 8.

Design:

- Train a core model on pooled data.
- Validate by leave-one-database-out and leave-one-country/region-out.
- Estimate random intercepts or frailty terms by DB/center.
- Quantify calibration drift by source.
- Compare city-level, country-seasonal, and season-only environmental resolution groups.

Outputs:

- Transportability matrix.
- Leave-one-source-out C-index/calibration.
- Source heterogeneity estimates.
- Recommendations on whether one global model, region-specific recalibration, or source-specific models are needed.

Why this matters:

The data are multi-registry by design. Demonstrating transportability is essential before using any risk model for trial enrichment or clinical decision support.

### 6. Dynamic Post-MI Risk Over Time

Question: How does SCD risk change from early post-MI through chronic follow-up, and do predictors differ by time since MI?

Data:

- `Time_index_MI_CHD`, `Baseline_type`, `Baseline_within40d`, `Time_zero_Ym`, `Survival_time`, `Status`.
- Core covariates and treatments.

Design:

- Define post-MI timing strata: within 40 days, 40 days to 6 months, 6-12 months, >12 months, depending on available timing.
- Fit piecewise cause-specific hazards or flexible parametric survival models.
- Use landmark models at clinically relevant times.
- Test time-varying effects for LVEF, age, eGFR, BMI, and treatment.

Outputs:

- Time-varying absolute risk curves.
- Early versus chronic predictor comparison.
- Landmark risk tables.

Why this matters:

The timing of prophylactic ICD decisions is clinically central. The dataset appears to contain enough timing information to study risk evolution rather than only baseline risk.

### 7. Joint SCD and Non-SCD Death Competing Outcome Framework

Question: Which patients are at high SCD risk but low competing non-SCD death risk, and which are more likely to die from non-SCD causes?

Data:

- `Status == 1` SCD and `Status == 2` non-SCD death.
- Full baseline phenotype.

Design:

- Fit parallel cause-specific models for SCD and non-SCD death.
- Derive a "net SCD-prevention opportunity" phenotype:
  - high predicted SCD risk.
  - low predicted competing mortality.
  - meaningful survival horizon.
- Compare with current ICD eligibility variables.

Outputs:

- Two-risk nomogram or score.
- SCD versus non-SCD risk quadrant plot.
- Clinical enrichment table by LVEF and age.

Why this matters:

Prophylactic ICD benefit depends not just on SCD risk but also on competing mortality. This project directly addresses that clinical tradeoff.

### 8. Multimorbidity Phenotyping and Cluster Analysis

Question: Are there reproducible post-MI phenotypes with distinct SCD and non-SCD death risks?

Data:

- Age, sex, LVEF, BMI, eGFR, hemoglobin, diabetes, hypertension, AF/flutter, stroke/TIA, smoking, HF/NYHA, lipids, medications, ECG, revascularization.

Design:

- Use complete/imputed baseline covariates.
- Apply latent class analysis, hierarchical clustering, or model-based clustering.
- Validate clusters across DBs.
- Estimate SCD and non-SCD cumulative incidence by cluster.
- Compare clusters to simple LVEF strata.

Outputs:

- Phenotype definitions.
- Cluster stability and transportability metrics.
- CIF/KM plots by phenotype.
- Cluster-specific treatment patterns.

Why this matters:

The repository already has many single-axis studies: BMI, age, AF, geography, calendar time. A phenotype analysis can reveal combined-risk profiles that single-variable studies miss.

### 9. Sex-Specific Risk, Treatment, and Outcomes

Question: Are there sex differences in SCD risk, competing mortality, ICD therapy, and GDMT receipt after accounting for baseline phenotype?

Data:

- `Sex`, `Sex_BIN_Male`, SCD outcomes, non-SCD death, ICD therapy variables, GDMT variables.
- Covariates: age, LVEF, eGFR, BMI, AF, diabetes, hypertension, revascularization, medications.

Design:

- Sex-stratified descriptive tables by cohort and LVEF.
- Interaction models: sex by LVEF, sex by age, sex by ICD status, sex by GDMT.
- Compare treatment uptake and outcome rates over calendar time.
- Evaluate calibration of existing risk models by sex.

Outputs:

- Sex-specific event-rate and absolute-risk report.
- Treatment gap analysis.
- Model performance by sex.

Why this matters:

Sex is consistently available and clinically important. This would be a high-feasibility whole-dataset study.

### 10. AF/Flutter Phenotype Across the Full Dataset

Question: How does AF/flutter modify SCD risk, non-SCD death, ICD therapy, and model performance?

Data:

- `AF_atrial_flutter`, `AF_any`, `af_history`, anticoagulant use.
- `Status`, `Survival_time`, `event_COMP`, ICD therapy variables.
- Study 8 GBM/risk-score artifacts where available.

Design:

- Define broad AF and strict AF definitions:
  - broad: AF/flutter yes.
  - strict: AF/flutter yes plus anticoagulant use, as explored in Study 8.
- Compare SCD and non-SCD risks by AF definition.
- Test AF interactions with LVEF, age, sex, and ICD status.
- Assess whether AF-specific models outperform recalibrated general models.

Outputs:

- AF-specific risk model or recalibration.
- AF versus non-AF risk decomposition.
- Anticoagulation/treatment pattern table.

Why this matters:

Study 8 already builds AF-specific workflows, but a whole-dataset AF phenotype could connect prediction, competing risk, and treatment.

### 11. Medication Treatment Patterns and Apparent Risk

Question: How do baseline medications cluster, and how are they associated with SCD, non-SCD death, and ICD therapy after adjustment?

Data:

- ACE inhibitor/ARB/ARNI/RAAS, beta-blocker, MRA/aldosterone antagonist, diuretics, lipid-lowering/statin, antiplatelet, anticoagulant, antiarrhythmic, diabetes drugs, digitalis.
- Outcomes: SCD, non-SCD death, all-cause mortality, ICD therapies where available.

Design:

- Build medication profiles/classes.
- Analyze uptake by year, DB, LVEF, age, sex, and comorbidity.
- Use careful observational methods:
  - propensity score weighting or matching.
  - high-dimensional adjustment.
  - negative control outcomes if plausible.
- Report as association/implementation study, not causal treatment effect unless target-trial assumptions are strong.

Outputs:

- Medication profile clusters.
- Adjusted association models.
- Calendar uptake plots.
- Database variation in treatment patterns.

Why this matters:

Medication data are repeatedly used and are central to contemporary SCD risk. This also bridges Study 5 with the outcome-focused studies.

### 12. ECG and Biomarker Incremental Value Study

Question: How much predictive value do ECG and biomarker variables add beyond age, sex, LVEF, eGFR, BMI, and comorbidities?

Data:

- ECG: HR, PR, QRS, QTc, AV block, LBBB, RBBB, NSVT.
- Biomarkers/labs: NTProBNP, CRP, troponin, hemoglobin, eGFR, sodium, potassium, lipids.
- Outcomes: SCD and non-SCD death.

Design:

- Define core model, core plus ECG, core plus biomarkers, and core plus both.
- Restrict to datasets with sufficient availability, then test transportability.
- Use imputation only where missingness is within acceptable thresholds.
- Compare C-index, calibration, AIC, Brier score, and decision curves.

Outputs:

- Incremental value table.
- Availability and missingness report.
- Predictor importance plots.

Why this matters:

Study 8 and Study 6 already use these variables, but their incremental clinical utility has not been cleanly isolated across the full data.

### 13. BMI, Metabolic Health, and SCD Risk Beyond U-Shaped BMI

Question: Is BMI's association with SCD explained or modified by diabetes, lipids, renal function, sex, age, AF, and LVEF?

Data:

- BMI, diabetes, lipids, eGFR, hemoglobin, LVEF, medications.
- Study 6 MICE and spline modeling infrastructure.

Design:

- Extend Study 6 to metabolic phenotypes:
  - metabolically healthy versus unhealthy overweight/obesity.
  - diabetes/no diabetes.
  - lipid profile strata.
  - renal function strata.
- Test interactions and mediation-style decompositions where appropriate.
- Include non-SCD competing risk.

Outputs:

- Metabolic phenotype risk curves.
- BMI interaction matrix.
- Competing-risk curves by BMI/metabolic phenotype.

Why this matters:

Study 6 establishes BMI as a nonlinear exposure. The next level is understanding what BMI is proxying for.

### 14. Geographic, Climate, and Seasonal Trigger Analysis

Question: Are seasonal and environmental associations with SCD consistent after accounting for geography, baseline risk, and registry type?

Data:

- `Time_zero_Ym`, `event_date`, season/month terms.
- Center metadata, coordinates, country/city, CVD risk region.
- ERA5 temperature, pressure, daylight, sunshine.
- SCD and competing death outcomes.

Design:

- Separate long-term geographic risk from short-term seasonal/weather exposure.
- Use center/DB random effects or stratification.
- Compare city-level versus country-seasonal-average datasets.
- Evaluate effect modification by age, LVEF, ICD status, AF, and beta-blocker use.

Outputs:

- Seasonal hazard curves by subgroup.
- Climate exposure models.
- Geographic heterogeneity plots.

Why this matters:

Study 2 and Study 7 each cover part of the question. A combined approach would be more interpretable and robust.

### 15. ICD Therapy Burden and Mortality Consequences

Question: How do inappropriate therapy, appropriate therapy, ATP, and recurrent shocks relate to subsequent mortality and competing events?

Data:

- ICD event registries from Study 1 and Study 3.
- `Status_FIS`, `Time_FIS_days`, `app_shock_flag`, `days_to_app_shock`, ATP variables, recurrent counts.
- Mortality and follow-up fields.

Design:

- Multi-state model:
  - no therapy.
  - inappropriate therapy.
  - appropriate therapy.
  - death.
- Time-dependent exposures for first therapy.
- Recurrent-event burden models for repeated shocks/ATP where counts are available.
- Stratify by device type and source registry.

Outputs:

- Multi-state transition hazards.
- Therapy burden incidence tables.
- Mortality risk after therapy events.

Why this matters:

The repository contains enough ICD-specific work to move from first-event analyses to a richer therapy-burden framework.

### 16. Current Guideline Eligibility Versus Predicted Risk

Question: How well do guideline-style criteria such as LVEF <=35% identify patients with high absolute SCD risk and low competing mortality?

Data:

- LVEF, NYHA, post-MI timing, ICD status, GDMT variables, age, comorbidities.
- SCD and non-SCD death outcomes.

Design:

- Define guideline-like eligibility categories from available variables.
- Compare observed and predicted SCD risk by eligibility group.
- Identify high-risk patients outside standard LVEF thresholds and low-risk patients inside thresholds.
- Use decision curve analysis for ICD-like intervention thresholds.

Outputs:

- Risk reclassification tables.
- Eligibility versus absolute-risk plots.
- Trial enrichment scenarios.

Why this matters:

This directly aligns with PROFID's stated aim of reassessing prophylactic ICD selection.

### 17. Database-Level Practice Variation and Outcomes

Question: How much do baseline phenotype, medication use, ICD use, and outcomes vary across databases after case-mix adjustment?

Data:

- `DB`, `dataset`, cohort files, medications, ICD status, outcomes.

Design:

- Mixed-effects models for:
  - ICD use.
  - GDMT uptake.
  - SCD rate.
  - non-SCD death rate.
- Estimate observed-to-expected ratios by database.
- Explore whether practice variation explains outcome variation.

Outputs:

- Funnel plots by DB.
- Observed/expected event and treatment rates.
- Case-mix adjusted practice variation report.

Why this matters:

Multi-database variation is a feature, not just a nuisance. It can reveal real-world implementation differences.

### 18. Missingness as a Signal and Bias Audit

Question: Are missing covariates merely nuisance missingness, or do they identify certain datasets, eras, phenotypes, and outcome risks?

Data:

- Missingness summaries from all variables and DBs.
- Outcomes and source identifiers.

Design:

- Model missingness indicators by DB, era, cohort, and baseline phenotype.
- Test whether missingness indicators predict SCD/non-SCD outcomes.
- Compare complete-case, MICE, and missingness-indicator approaches.
- Quantify complete-case selection, similar to Study 6 but across the whole dataset.

Outputs:

- Missingness mechanism report.
- Complete-case selection plots.
- Recommendations for imputation versus exclusion by variable domain.

Why this matters:

Several existing studies rely on MICE or complete-case analyses. A dataset-wide bias audit would strengthen all future manuscripts.

### 19. Revascularization and MI History Risk Study

Question: How do prior MI burden, acute revascularization, PCI/CABG, and MI timing relate to SCD and competing death?

Data:

- `MI_history`, `MI_type`, `number_of_mi`, `Time_index_MI_CHD`, `PCI`, `CABG`, `Revascularisation_acute`, thrombolysis fields.
- Outcomes: SCD, non-SCD death, all-cause mortality.

Design:

- Compare risk by revascularization status and MI history.
- Adjust for LVEF, age, sex, renal function, diabetes, medications, and DB.
- Evaluate interaction with calendar era.

Outputs:

- Revascularization phenotype risk report.
- Era-specific trends in revascularization and risk.

Why this matters:

The data contain enough procedural history to ask whether contemporary revascularization patterns relate to residual SCD risk.

### 20. Preserved-EF SCD Risk Characterization

Question: Among non-ICD preserved-EF patients, what identifies those who still experience SCD?

Data:

- `NonICD_preserved.csv`, `LVEF`, `Status`, `Survival_time`.
- Core clinical, lab, ECG, medication, and geographic variables.

Design:

- Restrict to preserved EF or model preserved EF as a subgroup.
- Compare predictors of SCD in preserved versus reduced EF.
- Use sparse-event methods if event counts are limited.
- Evaluate whether preserved-EF SCD risk clusters in age, renal dysfunction, AF, ECG abnormalities, or geographic/era strata.

Outputs:

- Preserved-EF risk profile.
- Contrast with reduced-EF model.
- Candidate high-risk preserved-EF phenotype list.

Why this matters:

Most ICD guidelines focus on reduced EF, but a large portion of post-MI populations have preserved EF.

## Suggested Prioritization

### Tier 1: Do First

1. Canonical endpoint and variable availability atlas.
2. Whole-cohort competing-risk SCD model.
3. LVEF threshold reassessment.
4. Calendar-era SCD, ICD proxy, and GDMT trend integration.
5. Source/geography transportability study.

These are foundational, high-impact, and reuse variables already touched by multiple studies.

### Tier 2: Do After the Data Contract Is Stable

1. Dynamic post-MI risk over time.
2. Joint SCD and non-SCD death framework.
3. Sex-specific risk and treatment analysis.
4. AF/flutter phenotype analysis.
5. Medication pattern and apparent-risk study.
6. ECG/biomarker incremental value study.

These need stronger harmonization but are feasible with the observed variable surface.

### Tier 3: Exploratory or Higher-Risk

1. Multimorbidity clustering.
2. Environmental/climate trigger analysis.
3. ICD therapy burden multi-state model.
4. Missingness-as-signal analysis.
5. Preserved-EF SCD high-risk phenotype.

These are scientifically valuable but depend more heavily on source-specific availability, endpoint consistency, and missingness handling.

## Recommended Canonical Analysis Datasets

To make new projects efficient, create a small number of canonical derived datasets:

### `core_patient_survival`

One row per patient.

Required fields:

- `patient_id`
- `DB`
- `Group`
- `ICD_status`
- `LVEF`
- `Age`
- `Sex`
- `Survival_time_months`
- `Status_0_1_2`
- `SCD_event`
- `nonSCD_death`
- `person_years`
- `Time_zero_Y`
- `Time_zero_Ym`

Purpose:

- Whole-cohort SCD, competing-risk, calendar, geographic, and risk prediction analyses.

### `core_baseline_covariates`

One row per patient with harmonized covariates.

Domains:

- demographics.
- cardiac phenotype.
- comorbidities.
- labs.
- ECG.
- medications.
- procedures.
- geography.
- missingness indicators.

Purpose:

- Shared modeling input for Studies 4, 6, 8, 9, and future projects.

### `icd_event_long`

One row per ICD event or one row per patient-event type, depending on event availability.

Fields:

- patient ID.
- ICD device type.
- inappropriate shock/therapy date/time.
- appropriate shock/therapy date/time.
- ATP indicators and counts.
- death/follow-up date/time.
- source registry.

Purpose:

- ICD therapy burden, device type, time-dependent therapy, and multi-state analyses.

### `treatment_calendar`

One row per patient with medication fields and calendar time.

Fields:

- `Year_index`
- `LVEF_num`
- `RAAS`
- `BB`
- `MRA`
- `HF_n_classes`
- `HF_BIN_eq3`
- `Diuretics`
- optional `ARNI` and `SGLT2`
- comorbidities and DB.

Purpose:

- GDMT uptake, implementation, treatment-era analyses, and links to outcomes.

### `geo_environment`

One row per patient-date or patient-season, depending on exposure resolution.

Fields:

- patient ID.
- DB/center/country/city.
- latitude/longitude where available.
- CVD risk region.
- season/month.
- temperature, pressure, daylight, sunshine.
- climate strategy.

Purpose:

- Seasonal, geographic, and environmental analyses.

## Minimum Pre-Analysis Validation Checklist

Before running any new whole-dataset analysis:

1. Confirm `Status` coding for each source/cohort.
2. Convert all follow-up fields to explicit units:
   - `Survival_time_months`.
   - `Survival_time_days`, if needed.
   - `person_years`.
3. Confirm that `Status == 1` means SCD in the analysis dataset, unless intentionally using an ICD proxy endpoint.
4. Keep non-SCD death as a separate competing event, not only as censoring.
5. Validate `Time_zero_Y` and `Time_zero_Ym` ranges.
6. Validate `LVEF` units and thresholds.
7. Audit impossible or implausible values:
   - BMI.
   - eGFR.
   - hemoglobin.
   - lipids.
   - ECG intervals.
   - follow-up time.
   - event time after follow-up.
8. Create a DB-by-variable availability table.
9. Decide in advance which variables are:
   - required.
   - imputed.
   - auxiliary only.
   - too sparse for primary models.
10. Preserve source DB and calendar era in all analysis datasets.
11. Avoid formulas using `~ .` after derived outcomes/helper variables are added.
12. Save model input row counts, event counts, missingness, package versions, input file hashes, and output timestamps.

## Practical Next Step

The most useful immediate next project is not a new model. It is a reproducible data inventory script that reads the protected canonical files, applies the endpoint crosswalk, and writes:

- `01_column_inventory_by_file.csv`
- `02_endpoint_coding_audit.csv`
- `03_variable_availability_by_DB.csv`
- `04_core_covariate_missingness.csv`
- `05_followup_unit_checks.csv`
- `06_recommended_analysis_dataset_schema.md`

Once that exists, the whole-dataset analyses above can be run with much less ambiguity and fewer one-off harmonization decisions.
