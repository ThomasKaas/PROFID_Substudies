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
