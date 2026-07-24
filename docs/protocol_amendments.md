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
