# Plant-based diet quality and cardiometabolic dysfunction in US adults

**Which plant foods carry the signal? Isocaloric food-group substitution and
measurement-error–corrected plant-based diet quality in relation to
cardiometabolic dysfunction among US adults (NHANES 2017–March 2020)**

---

## Reproducibility statement

**Every figure, table, and numerical result in this repository can be
regenerated from the official public NHANES and USDA source data using the
workflow provided here.** No manual steps, no undocumented data edits, and no
private or restricted-access inputs are involved. From a clean checkout,
`make all` downloads the raw public files, verifies them against recorded
SHA-256 checksums, and rebuilds the complete analysis end to end. Raw data are
not redistributed in this repository; they are fetched from CDC and USDA at
build time, and their provenance is recorded in `data/raw/MANIFEST.csv`.

## Design

Cross-sectional, nationally representative, survey-weighted analysis of
non-pregnant US adults aged ≥20 years. **This is an observational study.** All
estimates are associations. No causal claim is made, and the substitution
models estimate *statistical* substitutions, not intervention effects.

| | |
|---|---|
| **Data** | NHANES 2017–March 2020 pre-pandemic; USDA FPED 2017–March 2020; USDA WWEIA Food Categories |
| **Exposure** | PDI / hPDI / uPDI (Satija et al. 2016, 18 food groups), as index scores and as servings/day. HEI-2015 computed as a benchmark comparator. |
| **Primary outcome** | Continuous cardiometabolic dysfunction score: equally weighted mean of survey-weighted, sex-standardised z-scores of waist circumference, log-triglycerides, HDL-C (sign-reversed), log fasting glucose, and mean arterial pressure |
| **Primary weight** | `WTSAFPRP` (fasting subsample), per the NHANES least-common-denominator rule; verified empirically in QC |
| **Design** | `SDMVSTRA` / `SDMVPSU`, `nest = TRUE` |

## Contributions, stated honestly

No individual method used here is novel. The association between healthy
plant-based diet quality and cardiometabolic risk is already well established
and is **not** what this project claims to discover. The contribution is an
integrated, fully reproducible framework combining:

1. **Isocaloric food-group substitution within the PDI framework** — the lead
   contribution. Substitution modelling is standard; applying it inside the
   18-group plant-based diet index to identify which specific swaps carry the
   association is, to our knowledge, unexamined.
2. **Regression calibration for within-person 24-hour recall error** — the
   secondary contribution. Measurement-error correction of diet indices is an
   established literature with published NHANES applications; what we did not
   find is its application to the PDI family or to deattenuating a
   plant-based-diet exposure–outcome coefficient.
3. **Transparent survey-weighted analysis and complete computational
   reproducibility.**

Novelty statements in the manuscript are phrased as *"we identified no study
that…"*, naming databases and search dates. Scopus and Embase were not
searchable during protocol development; that gap is documented, not concealed.

## Pipeline

| Script | Purpose |
|---|---|
| `00_dag.R` | Causal DAG; derives the minimal sufficient adjustment set |
| `01_download.R` | Fetch public data; record SHA-256 provenance |
| `02_import.R` | Read `.XPT`; validate against the frozen variable specification |
| `03_quality_control.R` | **Mandatory gate.** Seven check families; halts on any blocking failure |
| `04_exposure_pdi.R` | PDI / hPDI / uPDI and HEI-2015 construction |
| `05_outcome_composite.R` | Cardiometabolic dysfunction score |
| `06_covariates.R` | Covariate harmonisation |
| `07_missing_data.R` | Multiple imputation under the survey design |
| `08_models_primary.R` | Primary survey-weighted models |
| `09_models_substitution.R` | Isocaloric substitution models |
| `10_calibration.R` | Regression calibration; reliability ratio |
| `11_pca.R` | Biomarker PCA (retention criteria pre-specified) |
| `12_sensitivity.R` | Pre-specified sensitivity analyses |
| `13_figures_tables.R` | Publication-quality outputs |

## Frozen protocol

`docs/variable_specification.csv` is the immutable variable contract: NHANES
variable name, units, transformation, derived name, inclusion status, and
justification for every variable, including those **deliberately excluded**
from the primary model and why. It is machine-readable and drives import
validation, so a specification that drifts from the data fails loudly rather
than silently. Amending it requires an explicit, committed protocol amendment.

## Reproducing

```bash
git clone <repo-url> && cd nhanes-pbdi-cardiometabolic
R -e 'renv::restore()'
make all
```

## Data sources

- **NHANES 2017–March 2020 pre-pandemic**, CDC/NCHS — <https://wwwn.cdc.gov/nchs/nhanes/>
- **FPED 2017–March 2020 Prepandemic**, USDA ARS Food Surveys Research Group
- **WWEIA Food Categories 2017–March 2020**, USDA ARS Food Surveys Research Group

All are public and require no application, licence, or credential.

## Licence

Code: MIT. Text and figures: CC-BY-4.0. Neither NHANES nor USDA source data
are redistributed here.
