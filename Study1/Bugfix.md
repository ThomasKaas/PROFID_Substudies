# Study 1 — Manuscript vs. Codebase Congruence Audit & Bugfix Tracker

Audit date: 2026-07-20
Scope: `Study1/Manusscript/ms_20072026_TK.md` and `suppl_20072026_TK.md` checked against the actual
R source in `Study1/` (all preprocessing scripts and scripts 1–10), not against the reconstructed
`Dataflow.md` / `Study1_codebase_description.md` summaries, which were themselves spot-checked and
found accurate except where noted below.

Raw data is not present in this repository, so none of the reported *numbers* (N=3,084, HR=0.98,
etc.) could be reproduced or checked. Every finding below is a **logical/structural** discrepancy
between what the manuscript describes as the method and what the code actually does — the kind of
mismatch that survives regardless of what the underlying data happen to contain.

Each item states: the manuscript claim, the actual code behaviour (file:line), why it matters, and
a recommended fix direction (fix the code to match the stated intent, or fix the manuscript wording
to match the actually-defensible implementation).

---

## Summary table

| # | Issue | Severity | Fix direction |
|---|---|---|---|
| 1 | CRT exclusion only active for 2 of 4 registries | High | Fix code (or narrow manuscript claim) |
| 2 | "Non-ischaemic cardiomyopathy" exclusion only exists for 1 of 4 registries | High | Fix code / verify source data / narrow claim |
| 3 | ISRAEL has no primary-prevention-indication filter | High | Verify source data / fix code |
| 4 | "≥40 days post-MI" is not an eligibility filter, only nulls 7 covariates | High | Fix manuscript wording |
| 5 | "Duplicate enrolment across datasets" is a warning, not an exclusion | Medium | Fix code (enforce) or fix manuscript wording |
| 6 | Missingness-threshold claim self-contradicts (haemoglobin 74.9% vs stated >80% rule) | Medium | Fix manuscript text |
| 7 | Landmark models are *not* "the same covariate set" as the primary model (NYHA parameterisation, unit rescaling) | Medium-High | Fix manuscript disclosure |
| 8 | Supplementary Table S3 footnote claims LRT; code runs a pooled Wald test | Medium | Fix manuscript footnote |
| 9 | Fine-Gray outcome (`Survival_time`/`Status`, "appropriate ICD therapy"/ATP) is untraceable — never constructed anywhere in this repo | High (reproducibility) | Fix code (add/expose derivation) |
| 10 | Supplementary Table S2 (exposure derivation) omits 3 of 6 real reclassification rules (E1/E2/E6) | High | Fix manuscript table |
| 11 | HELIOS `Time_FIS_days` typo (writes to `Time_FIS` instead) | Confirmed code bug | Fix code |
| 12 | Table/Figure numbering mismatches between script output and manuscript labels | Low / cosmetic | Fix labels |
| 13 | LVEF ≤35% is computed as a QC statistic but never enforced as a filter | Low | Confirm intent |

---

## 1. CRT exclusion is only active for 2 of 4 registries

**Manuscript (Methods, Study population):** "Patients with a cardiac resynchronization therapy
device at baseline ... were excluded."

**Code:**
- `preprocessing_dataset_scripts/eucert_preprocessing.R:79` — `EXCLUDE_CRT <- TRUE` (applied, lines 125-133)
- `preprocessing_dataset_scripts/prose_processing.R:142` — `EXCLUDE_CRT <- TRUE` (applied, lines 144-150)
- `preprocessing_dataset_scripts/helios_processing.R:84` — `EXCLUDE_CRT <- FALSE` (block at 278-284 never runs)
- `preprocessing_dataset_scripts/israel_processing.R:42` — `EXCLUDE_CRT <- FALSE` (block at 88-96 never runs)

Supplementary Table S1's own description of the Israeli registry says it enrols "implantation or
replacement of an implantable cardioverter defibrillator **or CRT defibrillator**" — the
supplement itself documents that CRT patients are present in that cohort, directly contradicting
the Methods sentence quoted above.

**Impact:** CRT-D recipients have a materially different arrhythmic and mortality risk profile than
single/dual-chamber ICD recipients. If HELIOS and ISRAEL patients with CRT devices remain in the
pooled cohort while EU-CERT and PROSE patients do not, the cohort is not the homogeneous population
the manuscript describes, and between-registry heterogeneity is partly a mix of registry effects and
uncontrolled device-type effects (only partially absorbed by `strata(DB)`).

**Recommended fix:** Determine whether HELIOS/ISRAEL raw data even contain a device-type field
(the ISRAEL script's existing `if (EXCLUDE_CRT) { ... stop(...) }` guard at line 94 suggests a
`Device_type`/`ICD_type` column may exist there). If it does, set `EXCLUDE_CRT <- TRUE` for both
and re-run the pipeline. If no such field exists for HELIOS, the manuscript's claim needs to be
narrowed to state which registries this exclusion was actually applied to.

---

## 2. "Non-ischaemic cardiomyopathy" exclusion only exists for 1 of 4 registries

**Manuscript:** "...or with coexisting non-ischaemic cardiomyopathy ... were excluded."

**Code:** Only `eucert_preprocessing.R:116` filters by etiology:
```r
dt <- dt[pat_diag_type == "ischemic"]
```
No equivalent filter exists in `helios_processing.R`, `israel_processing.R`, or
`prose_processing.R` (grepping all three for "ischem" returns nothing).

**Impact:** Same as #1 — if this restriction is not built into the raw source data for HELIOS,
ISRAEL, and PROSE, the pooled cohort includes non-ischaemic patients despite the manuscript stating
otherwise. HELIOS's own Table S1 description ("patients who suffered myocardial infarction and
received ICD implantation for primary prevention") and PROSE-ICD's known study design suggest those
two registries may already be restricted to post-MI/ischaemic patients *at the point of
enrolment* (i.e., no in-code filter is needed because the source population is already ischaemic-only).
ISRAEL is the clear outstanding gap: its Table S1 description states it enrols "all patients" with an
ICD or CRT-D, with no mention of a diagnostic restriction.

**Recommended fix:** Confirm with the ISRAEL data dictionary whether an etiology field exists and,
if so, apply the same ischemic-only filter used in `eucert_preprocessing.R`. For HELIOS/PROSE,
document in the manuscript (or a data note) that the ischaemic restriction is inherited from the
registry's enrolment criteria rather than applied in this pipeline, so the claim is verifiably true
rather than merely assumed.

---

## 3. ISRAEL has no primary-prevention-indication filter

**Manuscript:** Cohort description implies all four registries are restricted to primary-prevention
ICD indications.

**Code:** `israel_processing.R` contains no filter on prevention indication (grep for
"indication"/"primary" returns nothing), and Supplementary Table S1's own text for ISRAEL describes
"all patients with implantation or replacement of an ICD or CRT-D," without a primary/secondary
prevention qualifier — unlike the Table S1 entries for EU-CERT ("primary prophylactic"), HELIOS
("primary prevention of sudden cardiac death"), and PROSE ("primary prevention ICD recipients"),
which each state the restriction explicitly.

**Impact:** Combined with #1 and #2, the ISRAEL-ICD contribution to the pooled cohort is the least
constrained of the four registries against the manuscript's stated eligibility criteria (MI history,
ischaemic-only, non-CRT, primary prevention) — none of the four restrictions are enforced in code
for this registry specifically.

**Recommended fix:** Verify against the raw ISRAEL registry data dictionary whether a prevention
indication field or a secondary-prevention flag exists, and add the corresponding filter if so;
otherwise, qualify the manuscript's population description for this registry.

---

## 4. "≥40 days after the index event" is not an eligibility/exclusion filter

**Manuscript:** "...underwent ICD implantation for primary prevention of SCD at least 40 days after
the index event, consistent with guideline-defined eligibility criteria." This sentence sits in the
same paragraph as the other exclusion criteria, implying patients implanted <40 days post-MI were
excluded from the cohort.

**Code:** `1.Preliminary analysis.R:306-418` implements a "≤40-day baseline rule" that only nulls
seven specific baseline covariates for flagged rows — it never removes a patient:
```r
vars_40d_all <- c("SBP", "DBP", "CRP", "Troponin_T", "NYHA", "AV_block", "AV_block_II_or_III")
...
if (length(vars_40d) > 0 && any(flag40)) {
  df[flag40, (vars_40d) := NA]   # sets values to NA — does not filter rows
}
```
No `dt <- dt[!flag40]`-style row filter exists anywhere in the codebase tied to this flag.

**Impact:** This is a fairly consequential misstatement: a reader would reasonably conclude that
early-implant patients are outside the analytic cohort, when in fact they remain in it with a subset
of baseline covariates (including **NYHA**, a forced covariate in the primary Cox model) set to
missing and then multiply imputed. This changes how a reader should interpret both the eligibility
criteria and the missing-data mechanism for NYHA specifically.

**Recommended fix:** Rewrite the Methods sentence to describe this accurately as a data-quality rule
("baseline measurements obtained within 40 days of the index MI were treated as unreliable and set
to missing prior to imputation, rather than used to exclude patients") rather than as an eligibility
criterion — unless the intended design truly was to exclude these patients, in which case a new
patient-level filter needs to be added to script 1 (or earlier) and the whole downstream pipeline
re-run.

---

## 5. "Duplicate enrolment across datasets" is a warning, not an exclusion

**Manuscript:** "...or evidence of duplicate enrolment across datasets were excluded."

**Code:** `preprocessing_dataset_scripts/Final_merge_script.R:356-368` only flags and writes
duplicated `ID_f` values to a QC CSV — it never removes them:
```r
dup_ids <- d6[, .N, by = ID_f][N > 1]
if (nrow(dup_ids) > 0) {
  cat("\nWARNING: duplicated ID_f found ...")
  fwrite(dup_ids, file.path(OUT_QC_DIR, "dup_id_f_in_d6.csv"))   # warn only, no drop
}
```
The only *active* cross-file exclusion is PROSE-specific: patients in the PROSE-vs-LVSCD
co-enrolment join file are removed (`prose_processing.R:160`), which addresses a single known
overlap between two PROSE-related studies, not duplicate enrolment across the four pooled
registries in general.

**Impact:** If genuine cross-registry duplicates exist in the data (a patient somehow captured in
two of the four source registries), the current pipeline would silently retain both records rather
than resolving/excluding them, contradicting the stated criterion.

**Recommended fix:** Check the QC output (`dup_id_f_in_d6.csv`) from the last full run: if it is
empty, the manuscript's claim is incidentally true and should be reworded to reflect that dedup was
checked-for rather than actively enforced. If it is non-empty, add an actual exclusion step and
re-run downstream analyses.

---

## 6. Missingness threshold: manuscript claim self-contradicts its own reported statistic

**Manuscript:** "Variables with more than 80% missingness were excluded ... haemoglobin (74.9%
missing) was consequently excluded from multivariable modelling."

**Code:** The missingness threshold is consistently `>80%` / `≥80%`:
- `4.Table 1 and table S3.R:105` — `MISS_THRESHOLD <- 80` (variables ≥80% missing excluded from Table 1)
- `7.mice_full_cohort.R:599` — `drop_80 <- names(which(colMeans(is.na(full_imp_data)) > 0.80))`

74.9% is below 80% by either rule, so haemoglobin is **not** dropped by the missingness rule. It is
in fact explicitly carried into the primary Cox model's `candidate_vars`
(`8.full_cohort_cox_model_and_development.R:101`) and passed through the p<0.05 screening step
(line 435, `P_THRESH <- 0.05`) and possible backward elimination. If haemoglobin is absent from the
final published model, that is a result of failing the *statistical* screen, not the *missingness*
threshold.

**Impact:** As written, the manuscript's own numbers refute its own stated rule — a reader who does
the arithmetic (74.9 < 80) will immediately flag this. It also misattributes why haemoglobin isn't
in Table 2, which matters for anyone trying to reproduce the variable-selection process.

**Recommended fix:** Rewrite the sentence to reflect what actually happened — e.g., "haemoglobin
(74.9% missing) was retained through imputation but did not meet the p<0.05 screening threshold for
inclusion in the multivariable model," or, if a different (lower) ad hoc cutoff was actually applied
somewhere outside the audited scripts, state that cutoff explicitly instead of "80%."

---

## 7. Landmark models are not "the same covariate set" as the primary model

**Manuscript:** "Multivariable models were fitted using the same covariate set as the primary
analysis."

**Code comparison:**

| | Primary model (`8.full_cohort_cox_model_and_development.R`) | Landmark model (`9.Landmark_analysis.R`) |
|---|---|---|
| NYHA | 4-level factor, dummy-coded (lines 77-95, 179-183); NYHA I is reference — matches Table 2 | Dichotomised to `NYHA_grp` (I-II vs III-IV) via `make_nyha_grp()` (lines 114-124, 141, 175-181) |
| Age | raw years (HR 1.03/year in Table 2) | `Age_10 := Age/10` (line 230) — HR per 10 years |
| LVEF | raw % (HR 0.96/% in Table 2) | `LVEF_5 := LVEF/5` (line 231) — HR per 5% |
| eGFR | raw units (HR 0.99/unit in Table 2) | `eGFR_10 := eGFR/10` (line 232) — HR per 10 units |

The *set of variables* is the same (age, sex, LVEF, eGFR, QRS, diabetes, beta-blockers, stroke/TIA,
AF/flutter, NYHA, strata(DB)), but the *parameterisation* is not — this is a meaningfully different
model, not a re-run of the same specification on a landmark-restricted sample. Additionally,
`QRS_log1p` and `bin_stroke_tia` are hard-coded into the landmark model's covariate list, whereas in
the primary model they are only screening candidates whose survival to the final model is
data-dependent (could not be verified without data).

**Impact:** A reader comparing Table 2's Age HR (1.03) against a landmark-analysis Age HR would be
comparing per-year vs. per-10-year hazard ratios without being told — this can look like a much
larger or smaller effect than it is. It doesn't invalidate the sensitivity analysis, but the "same
covariate set" claim is inaccurate as literally stated.

**Recommended fix:** Add a Methods/Table S5 footnote disclosing the rescaling and NYHA
dichotomisation used in the landmark (and Fine-Gray) models, and soften "same covariate set" to
"same covariates, with NYHA dichotomised and continuous variables rescaled for landmark models" (or
similar).

---

## 8. Supplementary Table S3 footnote claims likelihood-ratio tests; code runs a pooled Wald test

**Manuscript (suppl, Table S3 footnote):** "P-values derived from likelihood ratio tests comparing
models with and without an interaction term between each subgroup variable and inappropriate ICD
therapy..."

**Code:** `8.full_cohort_cox_model_and_development.R:320` — the function is literally named and
commented as a Wald test:
```r
# Pool multiple coefficients (factor variables) using Wald test
pool_multiple_coefs <- function(coef_matrix, vcov_list) {
  ...
  wald_stat <- as.numeric(t(coef_pooled) %*% solve(vcov_total) %*% coef_pooled)
  p_value <- pchisq(wald_stat, df = k, lower.tail = FALSE)
  ...
}
```
and for single-coefficient interactions, `pool_single_coef` (lines 307-318) computes a z-statistic
(`coef_pooled / se_pooled`) and a normal-distribution p-value — again a Wald test, not a likelihood
ratio test. Both are legitimate ways to pool an interaction test across multiply-imputed datasets,
but neither compares nested models' likelihoods (which would require `mice::pool.compare()` or
D3/D4-style pooled LRT/F statistics, none of which appear in this script).

**Impact:** This is a factual error in a specific, checkable methodological claim in the supplement.

**Recommended fix:** Correct the Table S3 footnote to state the actual test used, e.g., "P-values
derived from a Wald test on the interaction coefficient, pooled across imputed datasets using
Rubin's rules."

---

## 9. Fine-Gray outcome ("appropriate ICD therapy" / ATP) is untraceable in this repository

**Manuscript:** "...first appropriate ICD therapy, defined as appropriate shock or, where
anti-tachycardia pacing data were unavailable, appropriate shock alone..."

**Code:** `10.Fine_gray.R:109-111` simply declares:
```r
VAR_TIME   <- "Survival_time"   # months (confirmed)
VAR_STATUS <- "Status"          # 0=alive/censored, 1=appropriate shock, 2=death
```
Neither `Survival_time` nor `Status` is constructed anywhere in this codebase — not in any of the
four registry preprocessing scripts, not in `Final_merge_script.R`. They must already exist as
pre-built columns in the externally-sourced `Data_Transfer_to_Charite/ICD.csv` file
(`Final_merge_script.R:58`, `profid_transfer_path("ICD.csv")`), whose construction happens entirely
outside this repository and is invisible to anyone auditing it. Notably, `helios_processing.R`'s own
header comment (line 20) promises "Define exposure variables (Status_FIS/**Status_ATP**...)," but
`Status_ATP` is never actually created anywhere in that script or the rest of the codebase — the
ATP-fallback rule described in the manuscript's Methods has no visible implementation at all.

**Impact:** This is the manuscript's headline secondary/positive finding (sHR 2.5–3.2 for subsequent
appropriate therapy), and its outcome variable's derivation — including the specific ATP-fallback
rule the manuscript claims was applied — cannot be verified, reproduced, or audited from this
repository. This is a significant reproducibility gap for the paper's most clinically emphasized
result.

**Recommended fix:** Either (a) locate and bring into this repository the actual derivation logic
for `Survival_time`/`Status` (wherever `ICD.csv` is built) so it can be documented and QC'd the same
way every other endpoint in this pipeline is, or (b) if that logic genuinely lives in a separate,
frozen master file outside version control, add an explicit data provenance note to the manuscript
and a checked-in copy of its derivation rules, and implement the promised (but currently absent)
`Status_ATP` construction if ATP data really is being incorporated per-registry as claimed.

---

## 10. Supplementary Table S2 (exposure derivation) omits 3 of 6 real reclassification rules

**Manuscript (suppl, Table S2):** Presents exposure classification as: 72 raw exposed → −1
(unknown timing) → −4 (reclassified unexposed, shock at/after follow-up) → 67 final exposed. Implies
these are the only two adjustments made to the raw exposure signal.

**Code (`3.data_cleaning_incidence_power_calc.R:161-212`)** actually applies six rules, in this order:

| Rule | What it does | In manuscript Table S2? |
|---|---|---|
| O1 (163) | Drop missing/zero `Time_death_days` | Yes (−32) |
| O2 (169-170) | Missing `Status_death` + valid time → censored | Yes (0) |
| **E1 (176-178)** | **Both** `Status_FIS` and `Time_FIS_days` missing → reclassified **unexposed**, `Time_FIS_days` set to `Time_death_days` | **No** |
| **E2 (183)** | `Time_FIS_days` present, `Status_FIS` missing → reclassified **exposed** | **No** |
| E4 (191) | Exposed, timing unknown → hard exclusion | Yes (−1) |
| E5 (199-202) | FIS at/after end of follow-up → reclassified unexposed | Yes (−4) |
| **E6 (210)** | Unexposed, FIS time missing → time set to `Time_death_days` | **No** |

Critically, the "72 raw exposed" figure itself is computed **after** E1 and E2 have already mutated
`Status_FIS` in place (`n_raw_exp <- sum(ds_clean$Status_FIS == 1L) + n_e4 + n_e5`, line 244) — so
any patients reclassified as exposed by E2 (a recorded shock *time* with no recorded shock *status*)
are folded into "72" without disclosure, and any patients reclassified as unexposed by E1 (fully
missing exposure data) never appear in the derivation table at all.

**Impact:** E1 and E2 are inference/imputation-like decisions about the primary exposure variable of
the whole study — not simple exclusions. Omitting them from the derivation table understates how
much of the "first inappropriate shock" variable was inferred rather than directly observed, which
is exactly the kind of detail a methods reviewer would want to see for the paper's key exposure.

Separately, the code's own output table is titled "**Table S1**. Cohort derivation and exposure
classification" (`3.data_cleaning_incidence_power_calc.R:306`), while the manuscript's supplement
uses this content as "**Table S2**" (its own Table S1 is the four-registry description table) — a
naming/numbering mismatch between what the code produces and what the manuscript presents.

**Recommended fix:** Expand Supplementary Table S2 to show all six rules (or explicitly justify
folding E1/E2/E6 into the other rows, stating how many patients each one affected), and align the
table numbering between the script's output filename/title and the manuscript.

---

## 11. HELIOS `Time_FIS_days` typo (confirmed code bug)

**Code (`preprocessing_dataset_scripts/helios_processing.R:398-400`):**
```r
dt[, Time_FIS_days := NA_real_]
dt[Status_FIS == 0L, Time_FIS := DAYS2LastQuery.ICD]        # <- writes "Time_FIS", not "Time_FIS_days"
dt[Status_FIS == 1L, Time_FIS_days := DAYS2_inappropriate_shock.ICD]
```
For every HELIOS patient with `Status_FIS == 0` (unexposed), the intended censoring time is written
to a column literally named `Time_FIS` — a typo, since the correct/harmonised name used everywhere
else in the pipeline is `Time_FIS_days`. As a result, `Time_FIS_days` stays `NA` for all unexposed
HELIOS patients at the point of registry preprocessing.

**Impact:** Downstream, script 3's rules E1 and E6 backfill these `NA` values with
`Time_death_days`, so the master analytic cohort ends up numerically fine — but the "missing FIS
time" counts reported anywhere upstream of that backfill (e.g., HELIOS's own QC summary) partly
reflect this coding bug rather than genuine source-data missingness, and it is a fragile
coincidence that HELIOS's `t_followup_days` already equals `Time_death_days`, masking what would
otherwise be a real data-loss bug.

**Recommended fix:** Change `Time_FIS` to `Time_FIS_days` on that assignment line and re-run the
HELIOS preprocessing step (and everything downstream of it) to confirm the master cohort numbers are
unaffected (they should be identical, since E1/E6 currently backfill the same value).

---

## 12. Table/Figure numbering mismatches between script output and manuscript labels

- `3.data_cleaning_incidence_power_calc.R:306` outputs "**Table S1**. Cohort derivation..." → manuscript calls this **Table S2** (see #10).
- `5.KM1.R:200-201` labels its console/plot legend "**Figure A**" → manuscript's supplement calls it **Supplementary Figure S1**.
- `6.KM2.R:158-159` labels its legend "**Figure S1**" → manuscript's supplement calls it **Supplementary Figure S2**.

These are cosmetic/leftover draft-labeling inconsistencies (the underlying figure content matches
the manuscript's descriptions of both KM curves), but worth reconciling before submission so
reviewers checking code output against the manuscript aren't confused by mismatched labels.

**Recommended fix:** Align in-script titles/labels with final manuscript numbering as a pre-submission pass.

---

## 13. LVEF ≤35% is computed but never enforced as a filter

**Code (`1.Preliminary analysis.R:128-144`, `check_cohort_icd()`):** computes
`n_include = sum(LVEF <= 35)` / `n_exclude = sum(LVEF > 35)` purely as a printed QC statistic — no
`dt <- dt[LVEF <= 35]` filter is ever applied anywhere in the pipeline.

**Manuscript:** Does not explicitly assert an LVEF ≤35% eligibility criterion in the quoted Methods
paragraph, so this is not a direct contradiction — but LVEF ≤35% is the standard guideline threshold
for primary-prevention ICD eligibility, and its presence as a computed-but-unenforced check suggests
it may have been an intended eligibility filter that was never wired up.

**Recommended fix:** Confirm whether an LVEF-based eligibility restriction was intended. If yes, add
the filter and document it as an inclusion criterion. If no (i.e., all four registries already
restrict enrolment to LVEF-eligible patients at the source), consider removing the unused check or
documenting why it's audit-only.

---

## What to do with this document

This file is meant as a working punch list, not a final verdict — several items (registry-level
eligibility filters, duplicate-ID QC output, whether QRS/stroke-TIA actually survived screening in
the real run) can only be fully resolved by re-running the pipeline against the real data and/or the
raw registry dictionaries, none of which are available in this repository checkout. Items #4, #6,
#7, #8, #10, #12 are primarily manuscript-wording fixes; items #1, #2, #3, #5, #9, #11, #13 require
checking (and possibly changing) the code and/or the raw source data before the manuscript's claims
can be considered verified.
