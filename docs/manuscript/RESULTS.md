# Results

All estimates below are **associations** from a cross-sectional survey. Table
and figure numbers refer to files in `outputs/tables/` and `outputs/figures/`,
each generated directly by script.

## Analytic sample

Of 15,560 participants in the NHANES 2017–March 2020 pre-pandemic file, 8,457
were adults aged ≥20 years, not pregnant, and examined in the Mobile
Examination Center. Of these, 3,769 were in the fasting subsample, which was
the binding constraint on sample size. After requiring a reliable day-1 dietary
recall (n = 3,481) and a complete composite outcome, **3,131 participants**
formed the analytic sample; 2,500 had complete covariate data and 631 were
recovered by multiple imputation (Table 1).

The design effect for the primary outcome was 2.74, giving an effective sample
size of 911 for a mean. Covariate missingness was concentrated in
income-to-poverty ratio (12.3%) and alcohol intake (10.9%); all other
covariates were ≥99% complete. Imputation chains mixed without trend
(Figure S1), and the complete-case and imputed covariate means differed
trivially — income-to-poverty ratio by 0.05, alcohol by 0.04 drinks/day, energy
by 30 kcal/day. Imputation therefore recovered sample size rather than
correcting a materially selected sample, and the complete-case and imputed
primary estimates were nearly identical (−0.064 versus −0.065).

## Primary association

Each standard deviation higher hPDI was associated with a **0.065 standard
deviation lower cardiometabolic dysfunction score (95% CI −0.106 to −0.023)**
(Table 2). The fraction of missing information for this coefficient was 0.13%,
so imputation uncertainty contributed negligibly.

Associations for the other indices were consistent in direction: overall PDI
−0.036 (−0.071 to 0.000) and uPDI **+0.050 (0.015 to 0.086)** per SD. Across
quintiles of hPDI the trend was broadly monotone though imprecise, with Q5
versus Q1 −0.171 (−0.311 to −0.030).

Among secondary outcomes, hPDI was associated with lower log hs-CRP
(−0.136, −0.199 to −0.073; FDR = 0.0001) and lower log HOMA-IR (−0.089, −0.142
to −0.036; FDR = 0.002). Associations with HbA1c (−0.010) and log ALT (+0.007)
were null.

## Which foods carry the association

In the all-components substitution model (17 food groups, total energy and
covariates; condition number 6.3, all food-group variance inflation factors
< 2.5), three of five pre-specified substitutions were associated with lower
dysfunction (Table 3, Figure F2):

| Replacing | With | Estimate (95% CI) | FDR |
|---|---|---|---|
| Refined grains | Whole grains (per oz-eq) | −0.030 (−0.050, −0.011) | 0.013 |
| Meat | Nuts (per oz-eq) | −0.023 (−0.040, −0.007) | 0.015 |
| Sugar-sweetened beverages | Tea/coffee (per 100 g) | −0.008 (−0.014, −0.001) | 0.026 |
| Fruit juice | Whole fruit (per cup-eq) | −0.006 (−0.056, 0.044) | 0.93 |
| Potatoes | Legumes (per cup-eq) | −0.003 (−0.059, 0.054) | 0.93 |

The two null swaps are **uninformative rather than negative**: legumes were not
consumed on the recall day by 75.7% of participants and carried the largest
standard error of any group, and both confidence intervals span effects in
either direction of comparable size to those observed elsewhere.

Individually, refined grains (+0.016, 0.005 to 0.027) and meat (+0.014, 0.003
to 0.024) were associated with higher dysfunction and vegetables (−0.040,
−0.069 to −0.010) with lower. Of 35 exploratory unit-compatible swaps, only one
survived FDR control, and it was the reverse of an already pre-specified
contrast. Five intended swaps — including sweets to whole fruit and meat to
legumes — could not be estimated because the groups are measured in
incompatible units.

For scale, exchanging approximately two ounce-equivalents per day of refined
for whole grains corresponds to an estimate of similar magnitude to the whole
index coefficient.

## Correction for within-person measurement error

Day-1 and day-2 hPDI correlated 0.49 in the replicate subsample (n = 2,739).
Within-person variance (23.4) exceeded between-person variance (14.9),
confirming that a single recall is a poor measure of usual plant-based diet
quality. The covariate-adjusted reliability ratio was **λ = 0.388 (0.319 to
0.434)**; the marginal value was 0.478.

Regression calibration moved the estimate from −0.065 (−0.106 to −0.023) to
**−0.167 (−0.290 to −0.055)**, a deattenuation factor of 2.58 (Table 4, Figure
F4). Hypothesis H2 — that correction would change the estimated association —
was supported. As an internal check, the bootstrap interval for the naive
coefficient (−0.106 to −0.023) matched the independently derived
imputation-pooled interval (−0.106 to −0.023).

## Where the association is located (exploratory)

Parallel analysis retained two components at both the nominal (n = 3,269) and
effective (n = 1,162) sample sizes; Kaiser's criterion would have retained
three. After varimax rotation the components explained 52.5% of variance
(Figure F3):

- **PC1, adiposity–lipid–inflammation axis**: waist 0.74, HDL-C (reversed) 0.70,
  triglycerides 0.66, HOMA-IR 0.64, hs-CRP 0.55, ALT 0.53
- **PC2, glycaemic axis**: HbA1c 0.93, fasting glucose 0.92, HOMA-IR 0.52

Mean arterial pressure loaded weakly on both (0.32, 0.14), reproducing its weak
correlation with the other composite components (r = 0.02 with reversed HDL-C).

Applying the pre-registered interpretation rule, hPDI was associated with PC1
(**−0.119, −0.179 to −0.060**) but not PC2 (−0.011, −0.060 to 0.039); the ratio
of magnitudes was 11.3, indicating an association **concentrated on the
adiposity–lipid–inflammation axis** rather than global or glycaemia-specific
(Table 6). Substituting fasting insulin for HOMA-IR, which removes the
algebraic dependency between HOMA-IR and glucose, left the conclusion unchanged
(PC1 −0.126; PC2 +0.001) and moved insulin to a clean PC1 loading of 0.74.

The PC1 estimate is roughly twice the primary composite estimate, consistent
with the equally weighted composite diluting the signal by giving blood
pressure and glycaemia equal weight with components that do respond.

## Sensitivity analyses

Across all nine pre-specified sensitivity analyses the coefficient ranged from
−0.055 to −0.071 against a primary estimate of −0.065; every confidence
interval overlapped the primary interval and the inference was unchanged in
every case (Table 5, Figure F1). Exclusions costing up to 38% of the sample
did not alter the conclusion.

Excluding participants with prevalent cardiovascular disease or diabetes did
not attenuate the association (−0.059 and −0.071 respectively), which argues
against reverse causation as the explanation, though it cannot exclude it. All
three medication-handling approaches gave materially identical results
(−0.058 to −0.067). The alternative scoring rule gave −0.067.

There was no evidence against linearity (Wald test of the spline against the
linear term, median p = 0.465 across imputations).

Excluding implausible energy reporters (n = 718; 617 under-reporters, 91
over-reporters) gave −0.056. Excluded participants had **higher BMI (32.2
versus 29.3 kg/m²), lower reported energy (1,562 versus 2,278 kcal/day) and
higher apparent diet quality (hPDI 52.8 versus 50.9)**. This is direct evidence
that recall error in these data is **differential with respect to adiposity**,
which is itself a determinant of the outcome — the specific reason the
regression calibration above is a partial correction.

The E-value for the primary estimate was **1.31**, and 1.17 for the confidence
limit closest to the null.

## Adiposity-related pathways (exploratory)

Adjusting for BMI attenuated the hPDI coefficient from −0.065 (−0.106 to
−0.023) to −0.026 (−0.059 to 0.007); the difference was −0.039 (−0.062 to
−0.011) by design-based bootstrap. hPDI was associated with lower BMI (−0.70
kg/m² per SD, −1.16 to −0.25) and BMI with higher dysfunction (+0.055 per
kg/m², 0.052 to 0.058).

No proportion mediated is reported. The cross-sectional data were **compatible
with adiposity-related pathways contributing to the observed association**, but
the same pattern would arise if adiposity influenced diet or if an unmeasured
common cause affected both, and this design cannot distinguish these.
