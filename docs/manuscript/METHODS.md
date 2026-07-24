# Methods

## Study design and population

We conducted a **cross-sectional, observational** analysis of the National
Health and Nutrition Examination Survey (NHANES) 2017–March 2020 pre-pandemic
public-use files. NHANES uses a complex, multistage, stratified probability
design representing the civilian non-institutionalised US population. Because
data collection for the 2019–2020 cycle was suspended in March 2020, the
partial cycle was combined by NCHS with 2017–2018 into a single pre-pandemic
file with its own set of survey weights.

Participants were eligible if they were aged ≥20 years, not pregnant, examined
in the Mobile Examination Center, and included in the fasting subsample. Cycles
were **not** pooled with earlier NHANES waves: auscultatory blood-pressure
measurement ended after 2017–2018, so blood pressure is not comparable with
prior cycles.

All estimates reported are **associations**. No causal effect is estimated, and
no temporal ordering between diet, adiposity and cardiometabolic status is
observed.

## Data sources

Three public sources were used, all fetched programmatically and pinned by
SHA-256 checksum:

1. **NHANES 2017–March 2020 pre-pandemic public-use files** (CDC/NCHS) —
   demographics, dietary recalls, examination, laboratory and questionnaire
   components.
2. **Food Patterns Equivalents Database (FPED) for use with WWEIA, NHANES
   2017–March 2020 Prepandemic** (USDA ARS), at the food-code level.
3. **Food and Nutrient Database for Dietary Studies (FNDDS) 2017–2018 and
   2019–2020, "At A Glance — Foods and Beverages"** (USDA ARS), which carry the
   official mapping from food code to WWEIA food category.

Both FNDDS releases were required: the 2017–2018 release covers 95.2% of the
7,444 food codes in FPED 2017–March 2020 and the 2019–2020 release 75.6%, but
their union covers 100%. Because the pre-pandemic public file omits the
survey-cycle identifier for disclosure control, food codes cannot be assigned
to the FNDDS release contemporaneous with their collection; a single
classification per food code is therefore unavoidable. Where the two releases
disagreed (30 of 5,263 shared codes), the later USDA classification was
adopted as the best available public representation. Two conflicts changed a
plant-based diet index food-group assignment; both were adjudicated
individually and the decisions recorded in a version-controlled lookup table
so that every run reproduces identically.

## Exposure: plant-based diet index

Diet was assessed by two interviewer-administered 24-hour dietary recalls (day
1 in person, day 2 by telephone). Only recalls flagged reliable by NCHS were
used.

We constructed the overall (PDI), healthful (hPDI) and unhealthful (uPDI)
plant-based diet indices following Satija et al. (2016), adapted to 24-hour
recall data under a single governing principle: **every edible gram contributes
to the index exactly once.**

Food items were assigned **hierarchically**. Items falling in the three
WWEIA-exclusive groups — tea and coffee, sugar-sweetened beverages, and sweets
and desserts — were assigned wholly to those groups by gram weight; all
remaining items were then decomposed through FPED into the other groups. This
preserves the mutual exclusivity that is a structural property of the original
food-frequency-questionnaire instrument, while retaining FPED's ability to
decompose composite dishes. A naive hybrid, in which FPED decomposition and
category assignment run in parallel, would count a cookie both as refined
grains and as a sweet.

This yields **17 groups rather than 18**. Satija's *miscellaneous animal-based
foods* group has no FPED analogue and is conceptually redundant under a
decomposition approach: the mixed dishes it was designed to capture are exactly
those FPED resolves into constituent components. Absolute index ranges are
therefore 17–85 rather than 18–90 and are not directly comparable with
published values; relative ranking, which every analysis here uses, is
unaffected.

Two USDA definitions were verified before use. `V_LEGUMES` and `PF_LEGUMES`
are the *same* legumes expressed as vegetables and as protein foods; summing
them would double-count, so `V_LEGUMES` was used alone with soy products added
at the standard equivalence. `V_TOTAL` already excludes legumes and `F_TOTAL`
already includes juice.

**Scoring.** Because a single 24-hour recall is heavily zero-inflated for foods
not eaten daily, plain quintile scoring assigns different scores to identical
behaviour — a non-consumer scored 1 for vegetables, 2 for whole grains and 3
for fish — which is incoherent for an index that sums group scores. A review of
the source paper and four NHANES implementations found **no established
convention** for this: published studies disagree on the number of categories
(quintiles versus deciles) and on the scale (1–5, 0–5, −5 to +5), and none
documents a zero-intake rule. We therefore pre-specified that **non-consumers
receive category 1 and consumers are divided into survey-weighted quartiles
2–5**, retaining plain weighted quintiles as a sensitivity analysis. The two
rules correlate 0.95–0.96 (Pearson) with weighted κ 0.91–0.92.

## Outcome

The primary outcome was a **continuous cardiometabolic dysfunction score**: the
equally weighted mean of survey-weighted, sex-standardised z-scores of waist
circumference, log-triglycerides, HDL-cholesterol (sign-reversed), log fasting
glucose, and mean arterial pressure. Higher values indicate worse status for
every component. Blood pressure was the mean of the second and third
oscillometric readings. Standardisation was verified by assertion to produce
weighted mean 0 and SD 1 within sex.

Secondary outcomes were log HOMA-IR, HbA1c, log hs-CRP and log ALT, with
Benjamini–Hochberg control of the false discovery rate.

## Covariates

The adjustment set was **derived from a directed acyclic graph**, not assembled
by convention. The DAG was encoded in `dagitty` and its minimal sufficient
adjustment set computed; the pre-specified covariate list was then checked
against it programmatically, with the pipeline halting on disagreement. The
single minimal sufficient set is: age, sex, race/ethnicity (modelled as a
social variable), education, family income-to-poverty ratio, smoking status,
alcohol intake, physical activity (GPAQ MET-minutes/week), dietary supplement
use, and total energy intake.

Body mass index is **absent from every minimal sufficient adjustment set**: the
DAG places adiposity on the causal path from diet to cardiometabolic status, so
adjusting for it in the primary model would remove part of the association of
interest. Models adjusting for BMI are reported as over-adjusted sensitivity
analyses and in the exploratory pathway analysis only.

Prevalent cardiovascular disease and diabetes are descendants of the outcome
that also influence diet; conditioning on them would open bias, so they are
handled by exclusion in sensitivity analyses rather than by adjustment.

Medication use is a descendant of the outcome that alters the *measured*
biomarker, and no handling is unbiased. Three approaches were pre-specified and
all three are reported: adjustment as a covariate, additive constants for
treated blood pressure (+15/+10 mmHg), and exclusion of treated participants.

## Missing data

Multiple imputation by chained equations (m = 20, 20 iterations) was used, with
predictive mean matching for continuous variables and logistic or multinomial
models for categorical variables. Design information — the log survey weight
and stratum — entered the imputation model directly, and the design was
respected again at analysis, since imputing without design information and
analysing with it would be uncongenial.

We used **multiple imputation then deletion**: all variables including the
outcome were imputed, so that outcome information contributed to imputing
covariates, after which records whose outcome had been imputed were deleted.
Convergence was assessed from trace plots of chain means and standard
deviations.

NHANES skip patterns were distinguished from missing data throughout. Blood
pressure and lipid medication questions are asked only of participants who
reach them; treating the blanks as missing would have made these variables
64% and 69% "missing" and invited the imputation model to invent medication use
for people never told they had the condition. Following the skip paths
explicitly reduced missingness to 0.2% and 3.8%.

## Statistical analysis

All analyses used design-based methods (`survey`), with masked variance
pseudo-strata and pseudo-PSUs and `nest = TRUE`. The **fasting subsample weight**
was used, following the NHANES rule of using the weight of the smallest
subsample contributing to the analysis; this was verified empirically rather
than assumed (fasting n = 3,769 versus day-1 dietary n = 7,630). Design objects
were always constructed on the full frame and subset with `subset()`, never by
filtering rows beforehand.

Estimates from the m completed datasets were combined by Rubin's rules
(`mitools::MIcombine`). The exposure was modelled per standard deviation, with
quintiles as a secondary specification. Exactly one primary test was
pre-specified: hPDI per SD against the cardiometabolic dysfunction score.

## Correction for within-person measurement error

A single 24-hour recall measures one day, not usual intake. Using the day-2
recall as a replicate (n = 2,739, 87.5% of the analytic sample), we estimated
the reliability ratio λ by method of moments and corrected the naive
coefficient by regression calibration.

Two refinements were necessary. First, the relevant attenuation factor for an
error-prone exposure alongside covariates measured without error is the
reliability of the exposure **residualised on those covariates**, not its
marginal reliability; using the marginal value would under-correct. Second,
41.2% of day-1 recalls fell on a weekend versus 22.2% of day-2 recalls, and the
days differ in mode; left unadjusted, this systematic difference inflates the
within-person variance. Both day and mode were adjusted before estimating
variance components. Confidence intervals came from a Rao–Wu–Yue–Beaumont
replicate bootstrap (500 replicates) recomputing **both** the coefficient and λ
in each replicate, so uncertainty in the correction factor propagates.

This correction is **partial by construction**. Classical regression
calibration assumes additive, non-differential error uncorrelated with true
intake, and our own data contradict that assumption (see Results). The
corrected estimate should be read as a lower bound on the magnitude of
attenuation, not as an unbiased estimate of the usual-intake association.

## Substitution modelling

The study's principal analysis fits one model containing all 17 food groups
simultaneously plus total energy and the covariate set. Holding total energy
constant, replacing one unit of food X with one unit of food Y is the linear
contrast β_Y − β_X, with variance V_YY + V_XX − 2V_XY.

Swaps were restricted to **unit-compatible pairs** (ounce-equivalents with
ounce-equivalents, cup-equivalents with cup-equivalents, grams with grams).
This is a genuine constraint: grams of confectionery and cup-equivalents of
fruit are not exchangeable quantities, so several scientifically interesting
swaps are not estimable and are reported as such rather than approximated.
Gram-unit groups were rescaled to per 100 g.

Collinearity was assessed **before** any contrast was estimated, since a
difference of two unstable coefficients is less stable than either alone.
Five pre-specified swaps (hypothesis H3) were tested; all other unit-compatible
pairs were treated as exploratory with FDR control, each unordered pair tested
once.

## Exploratory analyses

Two analyses are labelled exploratory throughout.

**Biomarker principal component analysis.** To ask whether the association is
global or axis-specific, we performed PCA on the survey-weighted correlation
matrix of nine biomarkers. Retention used Horn's parallel analysis (1000
simulations, 95th percentile) with a cap of three components; because **no
survey-weighted implementation of parallel analysis exists**, it generates its
null at the nominal sample size and will tend to over-retain, so it was treated
as a heuristic supported by the weighted scree plot, by a robustness run at the
effective sample size, and by a priori interpretability. Components were named
and the interpretation rule fixed in a version-controlled document committed
**before** any diet–component association was estimated.

**Adiposity-related pathways.** No causal mediation analysis was performed and
no proportion mediated is reported: exposure, adiposity and outcome are
measured at one examination, so temporal ordering is assumed rather than
observed and the reverse pathway is plausible.

## Sensitivity analyses

Nine pre-specified analyses were run and **all are reported in a single audit
table regardless of result**: alternative survey weight; exclusion of prevalent
cardiovascular disease, diabetes, and both; the three medication-handling
variants; the alternative scoring rule; and exclusion of implausible energy
reporters (reported energy divided by Mifflin–St Jeor basal metabolic rate
outside 0.87–2.75).

Non-linearity was assessed with a single pre-specified knot structure (natural
cubic spline, knots at the 10th, 50th and 90th percentiles); no alternative
structures were examined.

An E-value was computed for the primary estimate. The E-value quantifies the
minimum strength of association, on the risk-ratio scale, that an unmeasured
confounder would need with both exposure and outcome to explain away the
observed association. It does not demonstrate robustness to confounding.

## Software and reproducibility

Analyses used R 4.6.1 with packages pinned by `renv`. The complete pipeline
runs from raw public data to every table and figure with a single command; no
number in this manuscript was transcribed by hand. Source files are verified
against recorded SHA-256 checksums at every run, and all generated artefacts
are hashed. Code, the frozen analytic dataset specification, the protocol
amendment log, and provenance records are available at the repository.
