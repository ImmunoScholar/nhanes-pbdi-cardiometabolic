# Provenance record

Generated: 2026-07-26 12:57:29 UTC

## Study

Plant-based diet quality and cardiometabolic dysfunction in US adults,
NHANES 2017-March 2020 pre-pandemic. **Observational and cross-sectional.**
All reported estimates are associations; no causal effect is estimated.

## Git

- Commit: `5934d4ad7a88bed7cd6ef4372f6e13f16f489b0a`
- Branch: `main`
- Working tree at freeze: **MODIFIED** (see below)
  - ` M analysis/08_missing_data.R  M docs/artefact_checksums.csv  M outputs/figures/08_mice_convergence.png`

## Analytic dataset

- File: `data/processed/analytic_frozen.rds`
- SHA-256: `303bcbe0da07eb89196068d88b25b3c7a110491e9613ecc253a11e6528648969`
- Analytic n: 3131
- Imputations: m = 20
- Exposure scoring rule: `zero_lowest`

## Source data

All inputs are public and were fetched from CDC and USDA. Integrity is pinned in `docs/checksums.lock` (28 files).

- NHANES 2017-March 2020 pre-pandemic public-use files (CDC/NCHS)
- FPED for use with WWEIA, NHANES 2017-March 2020 Prepandemic (USDA ARS)
- FNDDS 2017-2018 and 2019-2020, At A Glance: Foods and Beverages (USDA ARS)

## Environment

- R: 4.6.1
- Packages pinned in `renv.lock`: 92 (full list in `docs/package_versions.csv`)
- Platform: x86_64-pc-linux-gnu

## Artefact checksums

SHA-256 for all 66 generated tables and figures: `docs/artefact_checksums.csv`.

## sessionInfo()

```
R version 4.6.1 (2026-06-24)
Platform: x86_64-pc-linux-gnu
Running under: Ubuntu 24.04.4 LTS

Matrix products: default
BLAS:   /usr/lib/x86_64-linux-gnu/blas/libblas.so.3.12.0 
LAPACK: /usr/lib/x86_64-linux-gnu/lapack/liblapack.so.3.12.0  LAPACK version 3.12.0

locale:
 [1] LC_CTYPE=C.UTF-8       LC_NUMERIC=C           LC_TIME=C.UTF-8       
 [4] LC_COLLATE=C.UTF-8     LC_MONETARY=C.UTF-8    LC_MESSAGES=C.UTF-8   
 [7] LC_PAPER=C.UTF-8       LC_NAME=C              LC_ADDRESS=C          
[10] LC_TELEPHONE=C         LC_MEASUREMENT=C.UTF-8 LC_IDENTIFICATION=C   

time zone: Etc/UTC
tzcode source: system (glibc)

attached base packages:
[1] stats     graphics  grDevices datasets  utils     methods   base     

other attached packages:
[1] digest_0.6.39 here_1.0.2   

loaded via a namespace (and not attached):
 [1] Matrix_1.7-5     mitml_0.4-5      glmnet_5.0       jsonlite_2.0.0  
 [5] dplyr_1.2.1      compiler_4.6.1   renv_1.2.3       rpart_4.1.27    
 [9] tidyselect_1.2.1 Rcpp_1.1.2       mice_3.19.0      tidyr_1.3.2     
[13] splines_4.6.1    boot_1.3-32      lattice_0.22-9   R6_2.6.1        
[17] generics_0.1.4   shape_1.4.6.1    pan_2.0          rbibutils_2.4.1 
[21] iterators_1.0.14 MASS_7.3-65      backports_1.5.1  tibble_3.3.1    
[25] nloptr_2.2.1     nnet_7.3-20      rprojroot_2.1.1  minqa_1.2.8     
[29] pillar_1.11.1    rlang_1.3.0      broom_1.0.13     cli_3.6.6       
[33] magrittr_2.0.5   Rdpack_2.6.6     jomo_2.7-6       foreach_1.5.2   
[37] grid_4.6.1       lme4_2.0-6       nlme_3.1-169     lifecycle_1.0.5 
[41] reformulas_0.4.4 vctrs_0.7.3      glue_1.8.1       codetools_0.2-20
[45] survival_3.8-6   purrr_1.2.2      tools_4.6.1      pkgconfig_2.0.3 
```
