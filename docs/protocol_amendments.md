# Protocol Amendments

The analysis plan was frozen on 2026-07-24. Every subsequent change to
`docs/variable_specification.csv` or to the analysis plan is recorded here,
with the reason and whether it constitutes a **design change** (alters what
the study estimates) or a **correction** (aligns the specification with the
data without changing the estimand).

Design changes require explicit approval. Corrections do not, but are logged.

---

## Amendment 1 — 2026-07-24 — CORRECTION

**Trigger:** `02_import.R` variable-name validation halted the pipeline.

**Finding:** the specification listed the physical-activity block as
`PAQ605:PAQ680`. `PAQ680` does not exist in `P_PAQ`. The sedentary-time
variable is named **`PAD680`**, and the GPAQ activity block runs
`PAQ605` … `PAD675` (verified by reading the variable labels directly from
`data/raw/P_PAQ.xpt`).

**Change:**
- Range corrected to `PAQ605:PAD675`; status raised `EXPECTED` → `VERIFIED`.
- `PAD680` added as a separate row with `inclusion = exclude_primary`.

**Why `PAD680` is excluded rather than adopted:** sedentary time is a distinct
construct from physical activity and was not part of the frozen covariate set
or the DAG. Adding it would be a design change, not a correction. It is
recorded so that its absence is a documented decision rather than an oversight.

**Estimand affected:** none.

---

## Amendment 2 — 2026-07-24 — CORRECTION (source resolution)

**Trigger:** the WWEIA food-code → category crosswalk was an unresolved
external dependency, required for 3 of the 18 PDI food groups (sugar-sweetened
beverages, tea/coffee, sweets/desserts) because `P_DR1IFF` carries no WWEIA
category variable.

**Finding:** the official crosswalk is distributed inside the USDA FNDDS
*"At A Glance – Foods and Beverages"* workbooks, with columns
`Food code`, `Main food description`, `Additional food description`,
`WWEIA Category number`, `WWEIA Category description`.

**Verified empirically against `FPED_1720.xls` (7,444 food codes):**

| Source | Coverage of FPED_1720 food codes |
|---|---|
| FNDDS 2017-2018 alone | 7,083 / 7,444 (95.2%) |
| FNDDS 2019-2020 alone | 5,624 / 7,444 (75.6%) |
| **Union of both** | **7,444 / 7,444 (100.0%)** |

**Change:** both FNDDS releases are mandatory inputs, added to
`01_download.R`. Using only the 2017-2018 release — the intuitive choice for a
"2017–March 2020" analysis — would have silently dropped 361 food codes.

**Known conflict, carried forward to script 04:** of the 5,263 food codes
present in both releases, **30 (0.57%) are assigned different WWEIA categories**
between them (e.g. code 27500050: 3708 → 3740). Precedence rule, to be
implemented in `04_exposure_pdi.R`: prefer the FNDDS 2017-2018 assignment,
falling back to 2019-2020 only for codes absent from it. The script must
additionally flag as **BLOCKING** any conflict whose categories fall in a
PDI-relevant group, for human adjudication rather than automatic resolution.

**Estimand affected:** none.

---

## Amendment 3 — 2026-07-24 — CORRECTION

**Trigger:** `03_quality_control.R` QC4 halted the pipeline, flagging 3
"impossible" values: one insulin at 512.5 uU/mL and two hs-CRP at 236.36 and
246.86 mg/L.

**Investigation (before any bound was changed):**
- No sentinel codes (7777/9999 etc.) present in either variable.
- Insulin comment codes (`LBDINLC`): 4,618 normal, 7 below detection limit,
  none flagged invalid.
- Both upper tails are smooth and continuous, not spikes:
  insulin 512.5, 485.1, 435.9, 382.5, 379.2, 321.6, …;
  hs-CRP 246.9, 236.4, 182.8, 138.8, 124.3, …

**Conclusion:** the data are correct and the specification was wrong. The
original bounds (insulin <=500; hs-CRP <=200) were clinical-normality limits,
not physiological ceilings. hs-CRP routinely exceeds 200 mg/L in acute
infection, and fasting insulin above 500 uU/mL occurs in severe insulin
resistance.

**Change:** `LBXIN` upper bound 500 -> 1000 uU/mL; `LBXHSCRP` upper bound
200 -> 500 mg/L. The stated purpose of QC4 (detect corruption, not biological
extremes) is unchanged and is now documented in the code.

**Guard against goalpost-moving:** no observation is deleted or altered. All
three values remain in the analytic dataset. They are captured by the frozen
log-transform rule (both variables have |skew| > 1: insulin 10.58, hs-CRP
10.77) and reported advisorily by QC7. Had the tails shown a spike at a round
number, or had comment codes flagged them invalid, the correct response would
have been to exclude them and say so — not to widen the bound.

**Estimand affected:** none.

---

## Amendment 4 — 2026-07-24 — SCORING RULE (approved by PI)

**Trigger:** diagnostics showed that a single 24-hour recall is heavily
zero-inflated, so plain weighted-quintile scoring collapsed most food groups
(fish/seafood to 2 levels; nuts, legumes, fruit juices, SSB to 3) and — the
decisive problem — assigned *different scores to identical behaviour*:
a non-consumer scored 1 for vegetables, 2 for whole grains, 3 for fish, purely
because of how common non-consumption is in that group. For an index that SUMS
group scores this is incoherent.

**Literature verification (requested before changing the rule).** No
established convention exists. Checked the source paper and four NHANES
implementations:

| Study | Scale | Zero-inflation rule |
|---|---|---|
| Satija 2016, PLoS Med (FFQ) | quintiles 1-5 | none stated |
| NHANES 2017-2018, fasting insulin (PMC10623701) | -5 to +5 | none stated |
| Eur J Nutr 2023 NHANES (PMC10468921) | deciles 1-10 | none stated |
| PLOS One gallstones (PMC11198842) | 0-5 | "lowest **or no** consumption received a 0" |
| Subclinical CVD NHANES (PMC12206005) | quintiles 1-5 | explicitly absent |

These disagree on both the number of categories and the scale. The only
near-convention that appears is that non-consumers receive the lowest score.
An FFQ asks about usual frequency over a year, so it never faced this problem;
a single recall does.

**Decision (PI-approved):** PRIMARY scoring rule is non-consumers -> category 1,
consumers -> weighted quartiles 2-5. The plain weighted-quintile rule is
retained as a PRE-SPECIFIED SENSITIVITY ANALYSIS, not discarded.

**Cost, stated plainly:** for groups with few non-consumers this is effectively
quartile rather than quintile scoring, a small loss of resolution.

**Agreement between the two rules (n = 7,630):**

| Score | Pearson | Spearman | Weighted kappa | Same quintile | Moved 1 | Moved >=2 |
|---|---|---|---|---|---|---|
| PDI  | 0.949 | 0.944 | 0.908 | 66.9% | 31.7% | 1.4% |
| hPDI | 0.962 | 0.959 | 0.923 | 71.1% | 28.3% | 0.6% |
| uPDI | 0.957 | 0.954 | 0.916 | 68.0% | 31.3% | 0.7% |

Bland-Altman bias is -5.46 (PDI), +1.34 (hPDI), +1.08 (uPDI) with SD ~1.84.
The level shift is expected and uninformative: the two rules anchor the scale
differently. The meaningful quantities are rank agreement and
cross-classification. Rank agreement is high (kappa > 0.90; moves of >=2
quintiles under 1.5%), but ~30% of participants shift by one quintile, so the
choice is not inconsequential at the individual level even though it is
unlikely to change conclusions.

**Implementation bugs found and fixed while making this change** (both caught
by diagnostics, not by the code failing):
1. `as.integer()` on a factor returns level CODES, not label values, so
   `cut(..., labels = 2:5)` silently produced 1..4 and merged consumers into
   the non-consumer category. Every group reported 4 levels instead of 5.
   Now uses `labels = FALSE` with an explicit offset.
2. Grouping distinct doubles via `factor()` / `tapply()` names round-trips
   through character and either collides distinct values or fails to match.
   Now grouped by integer index into `sort(unique(x))`.

**Estimand affected:** yes — this changes the primary exposure values. Approved
by the PI on 2026-07-24 with the plain-quintile implementation retained as a
pre-specified sensitivity analysis.

---

## Amendment 5 — 2026-07-24 — CORRECTION (NHANES skip patterns)

**Trigger:** the first imputation run reported `lipid_med` 69.1% and `bp_med`
63.9% missing. A medication variable cannot plausibly be two-thirds missing in
an examined adult sample, so the imputation was halted and inspected before
its output was used.

**Finding:** these are NHANES SKIP PATTERNS, not missing data. Verified
directly against the data:

- `BPQ050A` is non-missing for exactly the 3,279 respondents with
  `BPQ040A == 1`, which is itself reached only via `BPQ020 == 1`
  (ever told high blood pressure).
- `BPQ100D` is non-missing for exactly the 2,748 with `BPQ090D == 1`, reached
  via `BPQ080 == 1` (told high cholesterol) OR, for those not told,
  `BPQ060 == 1` (ever had cholesterol checked).

A respondent never told they had high blood pressure is not *missing*
antihypertensive medication status; they are not taking antihypertensive
medication. Coding the blank as `NA` and passing it to `mice` invites the
imputation model to invent medication use for people who were never told they
had the condition -- and, because these variables are predictors in the
imputation model, that error propagates into every other imputed variable.

**Change:** `bp_med` and `lipid_med` are now derived by following the skip path
explicitly (`07_covariates.R`), and `bp_treated` likewise in
`06_outcome_composite.R`. For the additive-constant blood-pressure variant an
unknown treatment status is treated as untreated, which is conservative
because it withholds the upward adjustment.

**Effect:** `bp_med` 63.86% -> 0.17% missing; `lipid_med` 69.12% -> 3.82%.
Complete-case n is unchanged at 2,500, because neither variable is a primary
covariate -- but both are predictors in the imputation model, so the first
imputation run was discarded and re-run from corrected inputs.

**Generalisation for the rest of the project:** any NHANES questionnaire item
showing implausibly high missingness must be checked against its skip pattern
before being treated as missing at random. `tried_lose_wt` (13.85%) was checked
and is NOT a skip artefact -- its missingness is near-constant across age bands
(379 / 432 / 389 / 57), so it is genuine item non-response and is imputed.

**Estimand affected:** none directly (medication variables enter only the
pre-specified sensitivity variants), but the imputation model -- and therefore
every imputed covariate used in the primary analysis -- was contaminated. The
correction is material.

---

## Amendment 6 — 2026-07-24 — PRESENTATION ONLY

**Trigger:** PI requested higher-quality manuscript figures.

**Change:** eight packages added to the locked environment (ggplot2, scales,
patchwork, ragg, systemfonts, textshaping, ggrepel, svglite) plus the
`fonts-liberation` system font package. `analysis/18_figures.R` rewritten
against a shared visual system in `R/theme_manuscript.R`; each figure is now
emitted as a 600 dpi raster and as a vector file at journal column widths.
A sixth figure was added showing the 17 individual food-group coefficients,
which previously existed only as a CSV.

**Estimand affected: none.** `18_figures.R` reads stored analysis objects and
estimates nothing. No model, dataset, or reported number changes. Verified by
comparing the re-run pipeline outputs against the originals: substitution
estimates (-0.0300 / -0.0060 / -0.0027 / -0.0077 / -0.0234) and calibration
results (-0.0646 / 0.3883 / -0.1665) are identical.

**Process failure to record honestly:** the first `make verify` run was
invalidated because `18_figures.R` was edited while that run was executing it.
Verification must test a frozen pipeline; changing a file mid-run makes the
result meaningless. Scripts 01-17 completed and reproduced identically before
the break, but the run cannot be cited as a passing end-to-end verification.
The pipeline was re-verified afterwards without modification.

**Colour and accessibility note:** the Okabe-Ito palette is used throughout and
no figure encodes information by colour alone -- position, shape, or text
always carries it -- so all figures remain readable in greyscale and under
colour-vision deficiency.

---

## Amendment 7 — 2026-07-24 — REPRODUCIBILITY DEFECTS (found by verification)

**Trigger:** the first untouched `make verify` run rebuilt the entire pipeline
and reported that 2 of 66 artefact checksums differed. The verification did its
job: both differences were real defects in my own code, not noise.

**Defect 1 — unseeded random number generation.** `05_exposure_pdi.R` called
`jitter()` in the Bland-Altman diagnostic without setting a seed. It was the
only unseeded RNG call in the pipeline (audited across all scripts: 08, 10, 13
and 16 all seed correctly). No estimate depends on it -- jitter is applied at
plot time to reduce overplotting -- but it made the script non-deterministic
and its figure unreproducible. `set.seed(20260724)` added.

I initially assumed this difference was an embedded PNG creation timestamp.
Inspecting the PNG chunk structure showed no `tIME` chunk in either the base-R
or the ragg output, which ruled that out and led to the actual cause. The
assumption would have been wrong and the defect would have survived.

**Defect 2 — timestamp inside a content-addressed artefact.**
`19_freeze_provenance.R` stored `frozen_on = Sys.time()` inside
`analytic_frozen.rds`, so the SHA-256 of that file changed on every run
regardless of whether the data changed. A frozen dataset must be
content-addressed: its hash should be a pure function of the data. Two checks
confirmed the mechanism rather than assuming it — `saveRDS` is deterministic
for an identical payload, and altering the timestamp alone was sufficient to
change the hash. The field was removed; the freeze time is recorded in
`docs/PROVENANCE.md`, where a timestamp belongs.

**Estimand affected: none.** All 64 content artefacts — every table and every
manuscript figure — were already bit-identical across two independent full
rebuilds. Both defects were in reproducibility machinery, not in analysis.


---

## Amendment 8 - 2026-07-26 - CROSS-ENVIRONMENT REPRODUCTION (no estimand affected)

**Trigger:** the repository was rebuilt from a clean clone on a different machine
in order to commit the generated figures and tables, which had been gitignored
and so existed only on the machine that produced them. That rebuild doubled as
an independent reproduction attempt and surfaced two defects.

**Defect 1 - `make all` did not download on a clean clone.** The download target
was `data/raw/MANIFEST.csv`, but that file is *committed*, because it is the
provenance record. On a fresh clone it therefore already exists, make judged the
download step already satisfied, and the build jumped straight to `02_import.R`,
which halted with `No .xpt files in data/raw/`. The claim in README and in the
reproducibility checklist that `make all` rebuilds from a clean checkout was
consequently false for anyone who actually tried it. The gate is now
`data/raw/P_DEMO.xpt`, which is gitignored and is therefore absent exactly when
a download is genuinely needed.

**Defect 2 - figure bytes are not reproducible across environments.** Checked
against the *committed* checksums rather than freshly regenerated ones, which
matters: `19_freeze_provenance.R` rewrites `docs/artefact_checksums.csv` as part
of the run, so comparing the run against its own output would have compared the
outputs with themselves and passed vacuously. Against the committed values, 62 of
66 artefacts were byte-identical, comprising **all 55 tables, the frozen analytic
dataset** (SHA-256 `303bcbe0da07eb89...`, unchanged) **and all six manuscript
figures**. The four that differed are exactly the four diagnostics drawn with
base `png()`: `05_bland_altman_hPDI`, `08_mice_convergence`,
`08_observed_vs_imputed` and `13_scree`.

The cause is the graphics device, not the analysis and not the seeding. `png()`
resolves to the system **cairo** stack here (`capabilities("cairo")` is TRUE and
`bitmapType` is `"cairo"`), whose font rasterisation and PNG encoding are
properties of the operating system and are **not** pinned by `renv.lock`. The six
manuscript figures use `ragg::agg_png` with `systemfonts` and `textshaping`, all
of which are pinned, and they reproduced exactly. That contrast is what isolates
the device as the cause: identical data, identical seeds, different rasteriser.

An honest correction to the record: Amendment 7 reported "66/66 artefacts
identical across two full rebuilds". That was true as written, but both rebuilds
ran on the same machine, so it evidenced determinism rather than portability. The
weaker, better-supported claim now stands in the checklist.

**Not changed, deliberately.** The four figures were left on `png()` rather than
migrated to `ragg`. Migrating them would alter committed artefacts and their
recorded hashes for presentation reasons alone, and this protocol treats
figure-system changes as amendments needing their own justification (cf.
Amendment 6). The limitation is documented instead, and the migration is recorded
here as a known follow-up rather than performed silently.

**Estimand affected: none.** Every table and every reported estimate is
byte-identical to the original run, computed from independently re-downloaded
source data whose 28 input checksums all verified against `docs/checksums.lock`.

---

## Amendment 9 — 2026-07-26 — PRESENTATION ONLY (device migration)

**Trigger:** Amendment 8 recorded, as a known follow-up rather than a silent
change, that the four diagnostic figures still drawn with base `png()` were the
only artefacts of 66 that failed to reproduce byte-for-byte on a second machine.
This amendment carries out that migration.

**Change.** The four call sites now use `ragg::agg_png` instead of
`grDevices::png`:

| Script | Figure | Former pixels / res | Inches at same res |
|---|---|---|---|
| `05_exposure_pdi.R` | `05_bland_altman_hPDI.png` | 1600 x 1200 @ 200 | 8.000 x 6.000 |
| `08_missing_data.R` | `08_mice_convergence.png` | 2000 x 1400 @ 160 | 12.500 x 8.750 |
| `08_missing_data.R` | `08_observed_vs_imputed.png` | 1800 x 1200 @ 160 | 11.250 x 7.500 |
| `13_pca.R` | `13_scree.png` | 1500 x 1000 @ 160 | 9.375 x 6.250 |

The plotting code is untouched; these remain the same base-graphics and lattice
diagnostics. `png()` takes width and height in **pixels** alongside `res`, while
`agg_png()` here takes **inches**, so the dimensions were converted at the
unchanged resolution. The output pixel dimensions are therefore identical, which
was confirmed by reading them back out of the regenerated files rather than
assumed from the arithmetic.

**The device swap alone was not sufficient, and stopping there would have left
the defect in place under a different name.** With no font family named, `ragg`
resolves the generic sans through **fontconfig**, which on this machine returns
DejaVu Sans from `fonts-dejavu-core` -- a package `renv.lock` does not pin and
the project does not declare anywhere. That is the same class of unpinned
operating-system dependency Amendment 8 identified in cairo, merely relocated
from the rasteriser to font selection. The six manuscript figures were never
exposed to it because `R/theme_manuscript.R` names `Liberation Sans` explicitly.

The family is now pinned to Liberation Sans, which is already a declared system
dependency (`fonts-liberation`, added in Amendment 6) and is the typeface of
every manuscript figure. `agg_png()` accepts no `family` argument, so the pin is
applied per device: `par(family = ...)` for the two base-graphics figures, and
`lattice::trellis.par.set(grid.pars = list(fontfamily = ...))` for the two
lattice figures, trellis settings being per-device.

**Tested, not assumed.** Under a `FONTCONFIG_FILE` that reorders the generic sans
families so the default sans resolves to Ubuntu rather than DejaVu Sans:

| Variant | Stock font environment vs reordered |
|---|---|
| Unpinned, base graphics | bytes **differ** |
| Unpinned, lattice | bytes **differ** |
| Pinned, base graphics | bytes **identical** |
| Pinned, lattice | bytes **identical** |

The two unpinned rows are the negative control and they carry the argument:
without them, "identical" would only have shown that the perturbation did
nothing. They also show that migrating the device without pinning the font would
have produced a figure that still moved with the host's font configuration.

**Verification of the pipeline.** Two independent clean rebuilds
(`make clean-outputs` then `make all`) were run end to end and compared three
ways:

- run 1 versus run 2: **all 66 artefact checksums identical**, including all ten
  PNGs;
- run 2 versus `git show HEAD:docs/artefact_checksums.csv`: **62 of 66
  identical**, the four exceptions being exactly the four migrated figures.
  Comparing against the *committed* checksums rather than the working-tree file
  matters for the reason Amendment 8 gave -- `19_freeze_provenance.R` rewrites
  `docs/artefact_checksums.csv` during the run, so a run-versus-working-tree
  comparison compares the outputs with themselves and passes vacuously;
- the frozen analytic dataset is unchanged at SHA-256 `303bcbe0da07eb89...`, as
  are all 55 tables and all six manuscript figures.

**Consequence for appearance, stated plainly.** The four diagnostics now render
in Liberation Sans rather than DejaVu Sans, so glyph shapes and text metrics
change slightly and their committed PNGs are replaced. All four were inspected
against the previous versions: no data geometry, axis range, plotted point,
annotation value or legend entry moves. The Bland-Altman bias and limits of
agreement still read 1.34 and -2.24 to 4.92, matching Amendment 4, and the scree
eigenvalues are unchanged.

**Residual limitation, not eliminated.** All ten figures now render through
`ragg`, `systemfonts` and `textshaping`, which `renv.lock` pins, with the font
file supplied by a declared system package. Glyph rasterisation still ultimately
runs through the system **FreeType**, and PNG encoding through the system
zlib/libpng, neither of which `renv.lock` pins. This assumption is not new and is
not specific to these four figures -- it applies equally to the six manuscript
figures, which did reproduce byte-identically across two machines in Amendment 8.
What has changed is that the four diagnostics are no longer a special case that
fails where the other six succeed. A second-machine rebuild since this change has
not yet been performed; that remains the confirming test, and the checklist says
so rather than claiming it.

**Estimand affected: none.** These are diagnostic figures. `05` and `13` write
their estimates to CSV independently of the plot; `08`'s figures are convergence
and distributional checks on the imputation. A graphics device cannot alter an
estimate, and the evidence for that here is direct rather than argued: every
table and the frozen analytic dataset are byte-identical to the committed values
across both rebuilds.

---

## Amendment 10 — 2026-07-26 — DIAGNOSTIC ARTEFACT DEFECT (figure showed 3 of 11 variables)

**Trigger:** reading `08_mice_convergence.png` against the claim its own script
makes. The comment above the figure says "Convergence: chains should mix, with no
trend across iterations", and for most of the imputed variables the artefact could
not support that statement, because most of them were not in it.

**Defect -- a multi-page lattice plot written to a single-page device.**
`plot.mids()` draws two panels per imputed variable, the chain mean and the chain
standard deviation. Eleven variables are imputed here, so it produces 22 panels.
The call passed `layout = c(2, 4)`, which is 8 panels per page and therefore 3
pages. A raster device holds one page: lattice drew each page over the last and
the file retained only the final one. The committed artefact was 6 panels covering
`bp_med`, `lipid_med` and `tried_lose_wt` -- the last 3 of the 11. Convergence for
`cmd_score`, `education3`, `pir`, `smoking3`, `alcohol_dpd`, `met_min_wk`,
`supplement_any` and `diabetes_dx` was never visible.

This is long-standing and **not** a regression from Amendment 9. The pre-migration
`png()` version of the file contains the same 6 panels; the device swap changed the
rasteriser, not the pagination. It is recorded as its own defect because it is one,
and because it sits in the blind spot of the previous amendment: Amendment 9
established that this figure's *bytes* were reproducible, which is orthogonal to
whether the figure shows what it claims. A byte-stable artefact can be byte-stably
wrong, and this one was.

**Change.** The layout is sized to the number of imputed variables so the plot is a
single page -- two columns (chain mean, chain sd), one row per variable:

| | Before | After |
|---|---|---|
| `layout` | `c(2, 4)` | `c(2, length(conv_vars))` = `c(2, 11)` |
| Pages drawn | 3 (2 overwritten) | 1 |
| Panels in the file | 6 of 22 | 22 of 22 |
| Device, inches @ 160 dpi | 12.5 x 8.75 | 12.5 x 24.0625 |
| Output pixels | 2000 x 1400 | 2000 x 3850 |

Width and resolution are unchanged, and the height scales at the former per-row
height (8.75 in / 4 rows = 2.1875 in), so every panel keeps its previous size and
only the page grows. The rendered dimensions were read back out of the PNG header
rather than inferred from the arithmetic: 2000 x 3850.

The variable count is not hard-coded. It is derived with the same rule
`plot.mids()` applies internally -- the rows of `chainMean` carrying no `NaN` or
`NA` -- so the figure stays complete if the missingness pattern changes. Two
consequences are worth recording, because both were mistakes waiting to be made:

- the count must be computed **before** the device is opened. `plot(imp)` resolves
  the lattice theme, which starts the default `pdf` device when none is open, so
  building the trellis object first in order to count its panels deposits an
  `Rplots.pdf` in the repository root on every build. Verified by doing it: the
  file appeared.
- a `stopifnot()` after the object is built re-checks that the panel count is twice
  the variable count and that the layout holds every panel on one page. If mice's
  selection rule ever diverges from the rule used to size the device, the build
  fails instead of silently truncating the figure again. That silent truncation is
  the failure being fixed, and it persisted for the whole life of the project
  without anything complaining.

**Newly visible, and one panel is worth recording.** `diabetes_dx` has a single
imputed cell (0.03% of 3,481 records). Its chain mean therefore alternates between
the two factor codes, and its chain-sd panel is **empty**, because `chainVar` is
`NA` throughout when only one cell is imputed. `plot.mids()` selects variables on
`chainMean` alone, so the variable is plotted while its sd panel has nothing to
draw. This is a property of the data, not of the fix -- it was equally true before,
merely on a discarded page. `education3`, `smoking3` and `supplement_any` are
similarly sparse at 3 imputed cells each. The substantively imputed variables --
`tried_lose_wt` (482 cells), `pir` (427), `alcohol_dpd` (379), `cmd_score` (350),
`lipid_med` (133) -- mix without trend across the 20 iterations, which is the first
time the artefact has actually shown it.

**Verification.** `make all` re-executed scripts 08-19. Scripts 05 and 13 did not
re-run, their inputs being unchanged, so their artefacts are byte-identical by
construction rather than by re-derivation -- stated because it makes this a weaker
check than Amendment 9's two full clean rebuilds, not an equal one.
`docs/artefact_checksums.csv` and `docs/PROVENANCE.md` were regenerated by
`19_freeze_provenance.R`, and the result was compared against
`git show HEAD:docs/artefact_checksums.csv` -- the *committed* values, not the
working-tree file, for the reason Amendments 8 and 9 both give:
`19_freeze_provenance.R` rewrites that file during the run, so comparing a run
against it compares the outputs with themselves and passes vacuously.

**Exactly one of the 66 artefact hashes changed**, and it is
`figures/08_mice_convergence.png` (957,182 -> 3,748,154 bytes). The other 65 are
byte-identical, including all 55 tables, all six manuscript figures, the other
three migrated diagnostics, and the frozen analytic dataset at SHA-256
`303bcbe0da07eb89...`. Because the imputation itself re-ran, this also re-confirms
that the seeding is deterministic: 20 chains x 20 iterations reproduced
byte-identical downstream estimates.

**Determinism of the new figure was tested, not assumed.** Re-rendering it from the
stored `mids` at the same specification reproduced the artefact's MD5 exactly
(`61bddb5c148ebc1d...`). The device remains `ragg::agg_png` with Liberation Sans
named explicitly and dimensions in inches with `res`, so nothing in Amendment 9's
argument is weakened; the pin is still applied through
`trellis.par.set(grid.pars = ...)` because this is a lattice figure and trellis
settings are per-device.

**Estimand affected: none.** This is a diagnostic figure. `08_missing_data.R`
imputes and diagnoses; it fits no model of scientific interest, and the figure is
read rather than computed from. The evidence is direct rather than argued: every
table and the frozen dataset are byte-identical to the committed values across the
rebuild, and the reported substitution estimates (-0.0300 / -0.0060 / -0.0027 /
-0.0077 / -0.0234) and calibration results (-0.0646 / 0.3883 / -0.1665) are
unchanged.

**Scope, and what is not fixed.** The same reasoning applies to any lattice object
whose panel count can exceed its layout on a one-page device. The sibling call in
this script, `densityplot(imp, ~ pir + alcohol_dpd + met_min_wk)`, was checked
rather than assumed: it names three variables and leaves `layout` unset, lattice
packs all three onto one page, and a re-render at the artefact's own specification
is byte-identical to the committed `08_observed_vs_imputed.png`, whose three panels
are all present. No other script prints a multi-panel lattice object to a raster
device; the manuscript figures in `18_figures.R` are ggplot2 and patchwork, which
do not paginate. One latent inconsistency is noted without being changed:
`cont_missing` is computed from the continuous variables that actually have missing
data, but the `densityplot` formula hard-codes the same three names. They agree
today only because `energy_kcal` is complete.

---

## Amendment 11 — 2026-07-26 — LATENT ARTEFACT DEFECT (figure and table could describe different variables)

**Trigger:** the closing paragraph of Amendment 10, which recorded this
inconsistency and deliberately left it in place.

**Defect, and its status.** `08_missing_data.R` produces two artefacts describing
the observed-versus-imputed comparison, and derived the variables they cover from
two independent places:

| Artefact | Variables came from |
|---|---|
| `tables/08_observed_vs_imputed.csv` | `cont_missing`, computed from the missingness table |
| `figures/08_observed_vs_imputed.png` | `~ pir + alcohol_dpd + met_min_wk`, written out by hand |

`cont_missing` is `intersect(c("pir", "alcohol_dpd", "met_min_wk", "energy_kcal"),`
`pre$variable[pre$pct_missing > 0])`. The two lists agree **only** because
`energy_kcal` is 100% complete in this extract. Had it, or any continuous covariate
added later, acquired missingness, the table would have gained a row and the figure
would have said nothing about it — the reader comparing the two would have no signal
that a variable was missing from one of them.

**This is stated as latent, not active.** Unlike Amendment 10, no committed artefact
was ever wrong. `cont_missing` evaluates to exactly the three hard-coded names today,
and the figure shows all three. The defect is that correctness rested on a coincidence
in the data rather than on anything in the code, and the coincidence was not the one
the reader would assume: it is not that the author kept the two lists in step, it is
that a fourth variable happened never to need imputing.

**Change.** The formula is built from `cont_missing`:

|  | Before | After |
|---|---|---|
| Formula | `~ pir + alcohol_dpd + met_min_wk` | `reformulate(cont_missing)` |
| `layout` | unset | `c(length(cont_missing), 1)` = `c(3, 1)` |
| Device, inches @ 160 dpi | `11.25 x 7.5` | `3.75 * length(cont_missing) x 7.5` = `11.25 x 7.5` |
| Output pixels | 1800 x 1200 | 1800 x 1200 |

The width scales at the former per-panel width (11.25 in / 3 panels = 3.75 in) and
the height is unchanged, so panels keep their size and only the page grows — the
same rule Amendment 10 applied to the convergence figure. A `stopifnot()` after the
object is built re-checks that the panel count matches the count the device was
sized for and that the layout holds every panel on one page, exactly as there.
`length(cont_missing) >= 1L` is asserted before the device is opened, because
`reformulate(character(0))` is an error rather than an empty figure.

**Pagination here is weaker than Amendment 10's case, and saying otherwise would
overstate it.** `plot.mids()` was passed an explicit `layout = c(2, 4)` smaller than
its panel count, which is what produced three pages and a file holding only the last.
`densityplot` was passed no `layout` at all, and lattice's default is
`compute.layout(NULL, n)` → `c(0, n, 1)`: *n* panels, **one page**, for every *n*
(checked at n = 1…12, 20, 22 and 40). This figure was therefore never truncated and
could not have been. What the explicit layout buys is that the single-page property
is now enforced by the `stopifnot()` instead of inherited from a lattice default, and
that the page grows with the variable count instead of packing more panels into a
fixed 11.25 x 7.5 in.

**The filter is load-bearing, which was not obvious and was tested.** Naming a
fully-observed variable in the formula does not draw an empty panel — it fails.
`densityplot.mids` builds a density from the *imputed* values, and with none to draw
`density.default()` stops with "need at least 2 points to select a bandwidth
automatically". So `~ pir + alcohol_dpd + met_min_wk + energy_kcal`, the obvious
hand-written way to keep the figure in step with the table, would have broken the
build today. Deriving the formula from `cont_missing` is the only form that is both
complete and safe.

**Verification.** `make all` re-executed scripts 08–19; 05 and 13 did not re-run,
their inputs being unchanged. `docs/artefact_checksums.csv` and `docs/PROVENANCE.md`
were regenerated by `19_freeze_provenance.R` and compared against
`git show HEAD:docs/artefact_checksums.csv` — the committed values, not the
working-tree file, which that script rewrites during the run so a comparison against
it passes vacuously.

**None of the 66 artefact hashes changed.** `figures/08_observed_vs_imputed.png` is
byte-identical at 244,748 bytes, MD5 `dec5a258fa97c213...`, 1800 x 1200 px, as are all
55 tables, all ten figures and the frozen dataset at SHA-256 `303bcbe0da07eb89...`.
`docs/artefact_checksums.csv` is not modified in the working tree at all. That is the
correct result and a stronger one than a changed hash would have been: it is direct
evidence that the refactor is behaviour-preserving on the current data, which a
diff of the script alone could only argue. `19_freeze_provenance.R` re-ran the
imputation, so this again re-confirms the seeding is deterministic.

**Byte-identity on its own proves only that nothing changed, so the fix was tested
where it is supposed to bite.** Three controls, all run rather than reasoned:

- *the guard fires.* Building the object with `layout = c(2, 1)` against 3 panels
  makes the `stopifnot()` fail, so the build stops instead of truncating.
- *the error above is real.* Adding `energy_kcal` to the formula errors in
  `density.default()`, as described.
- *the divergence is real, and is closed.* Under a synthetic pattern in which
  `energy_kcal` has 50 missing values, `cont_missing` has four entries and the table
  gains a fourth row. The old hard-coded formula still draws **3** panels; the new
  one draws **4**, on one page, with the device grown to 2400 x 1200 px and both
  guards passing. This is the failure the amendment exists to prevent, reproduced on
  demand and then shown not to occur.

No `Rplots.pdf` appeared in the repository root during any of this: the trellis
object is built only after `agg_png()` is open, and the panel count that sizes the
device comes from `length(cont_missing)` rather than from the built object, so
nothing resolves a lattice theme with no device active (Amendment 10).

The device remains `ragg::agg_png` with Liberation Sans named explicitly through
`trellis.par.set(grid.pars = ...)` and dimensions in inches with `res`, so nothing in
Amendment 9's argument is touched.

**Estimand affected: none.** This is a diagnostic figure, and on this data it is not
even a changed diagnostic figure. `08_missing_data.R` imputes and diagnoses and fits
no model of scientific interest. Every table and the frozen dataset are byte-identical
to the committed values, and the substitution estimates
(-0.0300 / -0.0060 / -0.0027 / -0.0077 / -0.0234) and calibration results
(-0.0646 / 0.3883 / -0.1665) are unchanged.

**Scope, and what is not fixed.** This closes the inconsistency Amendment 10 recorded.
The general pattern behind Amendments 10 and 11 — an artefact whose contents are
described in one place and generated from another — is not exhausted by them. One
instance is already visible and is left for separate work:
`docs/manuscript/CAPTIONS.md` gives the source of Figure S1 as
`outputs/figures/08_mice_convergence_key.png`, a filename no script writes and
`docs/artefact_checksums.csv` does not list; the file `08_missing_data.R` actually
produces is `08_mice_convergence.png`. Nothing checks that a caption's `*Source:*`
path is an artefact the pipeline produces.

---

## Amendment 12 — 2026-07-26 — DOCUMENTATION DEFECT (caption cited a file that has never existed)

**Trigger:** the closing paragraph of Amendment 11, which recorded this and left it.

**Defect.** `docs/manuscript/CAPTIONS.md` gave the source of Figure S1 as
`outputs/figures/08_mice_convergence_key.png`. No script writes that name, no
build has ever produced it, and `docs/artefact_checksums.csv` does not list it.
The file `08_missing_data.R` produces is `08_mice_convergence.png`. The `_key`
suffix appears nowhere else in the repository, so this is not a rename that was
half-applied; it is a filename that was never real.

This belongs to the family of Amendments 10 and 11 — an artefact described in one
place and generated in another — but sits one level further out. There the artefact
disagreed with its own script; here the manuscript disagrees with the pipeline. The
consequence is worse than a broken link: a reader following the caption finds
nothing, and the file that *does* hold the figure is cited by no caption at all, so
the convergence diagnostic is simultaneously unreachable from the manuscript and
unattributed in the manifest.

**The whole file was audited, not just the reported line.** Every `*Source:*` entry
in `CAPTIONS.md` was resolved against `docs/artefact_checksums.csv` and against the
filesystem: 26 cited paths across 6 tables, 6 figures and 6 supplementary items.

| | Count | Status |
|---|---|---|
| Cited paths resolving to a hashed artefact | 19 | correct |
| Cited `.svg` companions, present but unhashed | 6 | correct, see below |
| Cited non-artefact input (`docs/wweia_adjudications.csv`) | 1 | correct, exists |
| Cited paths that do not exist | **1** | `08_mice_convergence_key.png` |

So the reported defect is the only one. That is the useful result of the audit and
it is stated as a negative finding rather than left implied: the other 25 paths were
checked and are right.

**Change.** One character sequence in `CAPTIONS.md`:

| | Before | After |
|---|---|---|
| Figure S1 `*Source:*` | `outputs/figures/08_mice_convergence_key.png` | `outputs/figures/08_mice_convergence.png` |

The file's header paragraph was also corrected. It claimed every table and figure
comes from `17_tables.R` and `18_figures.R`, which is true of the manuscript items
and false of the three supplementary diagnostics, which come from `05` and `08` —
the same class of statement, wrong in the same direction, on the same page.

**The check that should have caught it.** `19_freeze_provenance.R` builds the
artefact manifest and now, in a new step 3, reads every `*Source:*` path out of
`CAPTIONS.md` and fails the build unless each one both exists on disk and appears in
that manifest. It is cheap because the manifest is already in memory: it costs one
`readLines()` and no hashing. Two properties of the parser are worth recording,
because both were wrong in a first draft:

- a `*Source:*` entry can wrap onto following lines — Tables 3 and S3 each cite two
  files that way — so the entry is read to the next blank line, not to the end of
  the line. A line-only parser silently checks the first path of each pair and skips
  the second, which is a checker that reports success on half its input.
- the `(and .svg)` convention names a file by extension rather than by path. Those
  are expanded against the preceding path, so Figure 1's caption checks
  `F1_sensitivity_forest.svg` as well as the `.png`.

`docs/manuscript/CAPTIONS.md` was added as a prerequisite of the `docs/PROVENANCE.md`
target. Without it, `make` considers the build satisfied when only a caption has
changed, and the check would not run on precisely the edit most likely to break it.

**One exemption, and it is named rather than derived.** `save_fig()` writes a `.svg`
beside every manuscript `.png`, and `hash_dir()` hashes only `.png`, so those six
files are cited by captions, present on disk, and absent from the manifest. They are
therefore checked for existence alone.

The first implementation derived that exemption from the manifest — exempting any
extension the manifest did not happen to contain — which reads as the more elegant
form and is wrong. It exempts `.log`, `.rds`, `.pdf` and everything else the manifest
does not cover, so it accepts a caption pointing at any file that merely exists. This
was not spotted by reading it. It was spotted because the guard was tested against a
caption citing `outputs/logs/19_freeze.log`, and **the build passed**. A checker whose
own failure mode is the defect it exists to prevent is worth recording: the exemption
is now the literal string `"svg"`, and control 2 below fails as it should.

**Verification.** `make all` re-executed `19_freeze_provenance.R` alone; every other
target was up to date, so nothing was re-derived and this is a weaker check than
Amendments 8 and 9's clean rebuilds, not an equal one. The regenerated
`docs/artefact_checksums.csv` was compared against
`git show HEAD:docs/artefact_checksums.csv` — the committed values, not the
working-tree file, which that script rewrites during the run so a comparison against
it passes vacuously.

**None of the 66 artefact hashes changed**, and none could have: this amendment
changes a Markdown file, a Makefile prerequisite and a validation step that writes
nothing. The frozen dataset is unchanged at SHA-256 `303bcbe0da07eb89...` and n = 3,131.
The build log gained one line: `26 caption sources checked (19 against the artefact
manifest, 7 by existence only)`.

**The guard was tested by breaking the file four ways**, each restored afterwards:

- *the original defect.* Putting `08_mice_convergence_key.png` back fails the build
  with `not on disk` and `not an artefact`. The defect this amendment fixes is now
  unmergeable.
- *real file, not an artefact.* Citing `outputs/logs/19_freeze.log` fails with
  `not an artefact`. This is the control that failed against the first implementation.
- *a `.svg` claim that is not true.* Adding `(and .svg)` to Figure S3, whose script
  writes no vector companion, fails with `not on disk:
  outputs/figures/05_bland_altman_hPDI.svg`. The parenthetical is checked, not trusted.
- *the wrapped second path.* Breaking `12_not_estimable_swaps.csv`, which is the
  continuation line of Table 3's entry, is caught — the multi-line parse is exercised
  rather than assumed.

No `Rplots.pdf` appeared: this step opens no graphics device.

**Estimand affected: none.** Nothing in this amendment touches data, a model, or a
figure. It corrects a filename in a caption and adds a validation step that fails the
build or does nothing. Every table, every figure and the frozen dataset are
byte-identical to the committed values.

**Scope, and what is not fixed.**

- *The six `.svg` files are not hashed.* They are committed, cited by the manuscript
  and outside `docs/artefact_checksums.csv`, so their integrity is not pinned and
  `make verify` cannot detect a change to them. Extending `hash_dir()` to `.svg` is
  one line, and it is deliberately not taken here: `svglite` output depends on
  system font metrics in a way `ragg` output does not, and Amendment 9 established
  cross-environment byte-stability for the raster figures only. Hashing the vectors
  without first demonstrating they reproduce across environments would convert an
  unverified claim into a build that fails on someone else's machine. That
  demonstration is separate work.
- *The check is one-directional.* It proves every citation resolves; it does not prove
  every artefact is cited. The reverse would flag `13_scree.png` and the intermediate
  tables, which are diagnostics and legitimately uncited, so there is no clean rule to
  enforce. The asymmetry is why `08_mice_convergence.png` sat uncited for the whole
  life of the project without complaint.
- *Existence is not correctness.* The check confirms a caption points at a real
  artefact. It cannot confirm the caption describes it — that is what Amendment 10
  had to be read to find, and no cheap check replaces reading the figure.
