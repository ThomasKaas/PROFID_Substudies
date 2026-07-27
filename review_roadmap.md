# Review roadmap

## Study 1

### C21 — Test for small-sample bias in the shock estimate

Status: implemented as a standalone optional sensitivity analysis on 2026-07-27.

`Study1/c21_sparse_data_bias_sensitivity.R` refits the time-dependent inappropriate-shock (`FIS_td`) Cox model in each of the existing multiple imputations using only five prespecified core covariates (age, sex, LVEF, NYHA, and eGFR) and retains cohort stratification. It pools the exposure coefficient with Rubin's rules and writes separate C21 outputs. The primary analysis, its code, and its outputs are not modified.

Run with:

```sh
Rscript Study1/c21_sparse_data_bias_sensitivity.R
```

Interpret the resulting hazard ratio and interval alongside the primary estimate. A meaningful difference would indicate sensitivity to the adjustment set; concordance does not eliminate imprecision from the 13 exposed deaths.

### C5 — Same-day inappropriate shock and secondary outcome

Status: completed on 2026-07-27.

- Confirmed and retained Fine-Gray Rule E: `Time_FIS_days >= Survival_time_days` is reclassified as unexposed. A shock recorded on the same day as the secondary endpoint therefore cannot set `FIS_L = 1`.
- Added the aggregate-only output `C5_same_day_FIS_secondary_endpoint_audit.csv`, with the number of same-day, later, and combined at-or-after-endpoint records eligible at each 6-, 12-, and 24-month landmark (imputation 1; exposure and outcome are not imputed).
- Kept the signed-off mortality E5 rule (`Time_FIS_days >= Time_death_days` means unexposed) as the sole recoding rule. The time-dependent Cox model now asserts this invariant before `tmerge()` and stops rather than applying a divergent local recode.
- Corrected the Dataflow description to match the implemented `>=` Rule E and recorded the new C5 audit output.
