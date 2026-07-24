# Biomarker PCA — component interpretation and naming

**This file is committed BEFORE any diet–component association is estimated.**
That ordering is the pre-specified safeguard against naming components to fit
the exposure results, and it is verifiable in the git history: this commit
precedes the commit that adds `14_pca_associations.R`.

## Extraction summary

- Sample: n = 3,269 with all nine biomarkers observed
- Survey-weighted correlation matrix; design effect 2.81, effective n = 1,162
- Retention: Horn's parallel analysis retained **2** components at the nominal n
  **and** at the effective n. Kaiser (eigenvalue > 1) would have retained 3 —
  as expected, since Kaiser over-retains. The two PA variants agreeing is
  reassuring given that PA itself is only a heuristic here (no survey-weighted
  implementation exists).
- Varimax rotation applied. Cumulative variance explained: 52.5%.

## Rotated loadings (higher = worse)

| Biomarker | PC1 | PC2 |
|---|---|---|
| Waist circumference | **0.742** | 0.229 |
| HDL-C (reversed, log) | **0.702** | 0.113 |
| Triglycerides (log) | **0.657** | 0.189 |
| HOMA-IR (log) | **0.635** | **0.516** |
| hs-CRP (log) | **0.547** | 0.141 |
| ALT (log) | **0.526** | −0.012 |
| Mean arterial pressure | 0.316 | 0.142 |
| Fasting glucose (log) | 0.186 | **0.921** |
| HbA1c (log) | 0.135 | **0.928** |

## Names

**PC1 — Adiposity–lipid–inflammation axis.**
Central adiposity, atherogenic dyslipidaemia (high triglycerides, low HDL-C),
insulin resistance, systemic inflammation and hepatic enzyme elevation load
together. This is the classic insulin-resistant metabolic cluster.

**PC2 — Glycaemic axis.**
Fasting glucose and HbA1c load almost exclusively here, with HOMA-IR
cross-loading. This axis separates chronic glycaemia from the adiposity
cluster.

## Three things to hold against these components

**1. HOMA-IR is algebraically entangled with fasting glucose.**
HOMA-IR = insulin x glucose / 405, so `log_homa_ir` and `log_glucose` share a
term by construction. That inflates the apparent coherence of PC2 and explains
part of HOMA-IR's cross-loading. A sensitivity analysis substituting
log(fasting insulin) for log(HOMA-IR) removes the algebraic overlap and should
be run before these components are given any weight in the manuscript.

**2. Blood pressure belongs to neither axis.**
Mean arterial pressure loads weakly on both (0.316, 0.142). This is not a
defect of the extraction; it reproduces the component-correlation finding from
`06_outcome_composite.R` (MAP correlates 0.02 with reversed HDL-C) and the
published CFA result that systolic blood pressure loads weakly in every
sex/race group. It does mean the equally weighted primary composite gives
blood pressure the same weight as tightly clustered components — a
transparency choice, made knowingly, not a discovery.

**3. HbA1c remains right-skewed after log transformation** (skew 2.24), because
participants with diabetes generate a long tail that no monotone transformation
removes. PC2 is therefore influenced by a minority with substantially elevated
glycaemia.

## Pre-stated interpretation rule

The scientific question fixed in Phase 2 was whether plant-based diet quality
associates with cardiometabolic dysfunction **globally or on a specific axis**.
That question is answered by comparing the hPDI association across PC1 and PC2:

- similar magnitude on both -> global association
- concentrated on PC1 -> adiposity/inflammation-mediated
- concentrated on PC2 -> glycaemia-specific

This rule is recorded here, before the associations are estimated.
