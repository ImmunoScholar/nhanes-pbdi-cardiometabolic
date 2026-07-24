# Methodological note: hierarchical food assignment in the PDI

## The governing principle

> **Every edible gram contributes to the plant-based diet index exactly once.**

Food items are assigned hierarchically. Items belonging to the three
WWEIA-exclusive groups — tea and coffee, sugar-sweetened beverages, and sweets
and desserts — are assigned directly and wholly to those groups. All remaining
items are then decomposed through FPED into the other PDI food groups. No gram
of food enters the index twice, and no gram is discarded.

## Why this is consistent with the original PDI

Satija et al. (2016) built the PDI from food-frequency questionnaire line
items. An FFQ line item *is* a whole food — "cookies", "white bread",
"cola" — and each line item feeds exactly one of the 18 groups. Mutual
exclusivity is not an added constraint in the original framework; it is a
structural property of the instrument. A participant who reports cookies
contributes to *sweets and desserts* and to nothing else.

The hierarchical procedure reproduces that property for 24-hour recall data.
It preserves the two features that give the PDI its meaning:

1. **Each food contributes to one group**, so the 18 group scores partition
   the diet rather than overlapping it.
2. **Group scores remain independently rankable**, since quintile scoring is
   applied within each group separately; units need not be commensurable
   across groups.

## How it differs from a naive FPED decomposition

FPED is a *decomposition* database: it expresses every food, including mixed
dishes, as its constituent pattern equivalents. A cookie is resolved into
refined-grain ounce-equivalents, added sugars, and solid fats. This is exactly
what makes FPED valuable for 24-hour recall data, where a large share of
intake arrives as composite foods that an FFQ would never itemise.

But decomposition and the PDI's group structure conflict at the boundary. Under
a naive hybrid — FPED for the groups it supports, WWEIA categories for the
three it does not — a cookie contributes:

- refined-grain ounce-equivalents to **refined grains** (via FPED), *and*
- its full gram weight to **sweets and desserts** (via WWEIA category 5504).

The same gram is counted in two groups. A participant eating many cookies is
penalised twice, and the resulting index is no longer the published construct.
The distortion is not uniform across participants: it scales with the share of
intake coming from foods that are simultaneously category-assignable and
FPED-decomposable, which differs systematically by dietary pattern.

The hierarchy removes the conflict by ordering the two operations rather than
running them in parallel. Category assignment takes precedence; decomposition
applies to what remains.

## What is retained and what is given up

**Retained.** FPED's decomposition still does the work it is best at. A beef
and vegetable stew is not forced into a single group: its meat, vegetable and
grain components are allocated separately, which an FFQ-based index could not
achieve.

**Given up.** For the three WWEIA-exclusive groups, internal composition is not
decomposed. A cookie's refined-grain content is not credited to *refined
grains*; the cookie is a sweet, entirely. This is a deliberate choice and it is
the same choice the original PDI makes.

## Consequence for the substitution models

Mutual exclusivity is a precondition, not a refinement, for the study's lead
contribution. "Replacing one serving of refined grains with one serving of
whole grains" is only interpretable if the groups do not share food mass.
Under the overlapping implementation the estimand would be undefined; under the
hierarchical implementation it is well posed. Substitutions are further
restricted to unit-compatible group pairs (ounce-equivalents with
ounce-equivalents, cup-equivalents with cup-equivalents, grams with grams).

## Deviation from the published 18-group structure

This implementation yields **17 groups, not 18**. Satija's eighteenth group,
*miscellaneous animal-based foods*, has no FPED analogue — and under a
decomposition-based approach it is conceptually redundant rather than merely
difficult. The foods it was designed to capture (animal-based mixed dishes,
soups, pizza) are precisely the foods FPED resolves into their constituent
meat, dairy, grain and vegetable components. A residual "miscellaneous"
category exists in the FFQ framework because an FFQ cannot decompose composite
foods; once decomposition is available, the category has nothing left to hold.

The consequence is that absolute PDI/hPDI/uPDI score ranges are 17-85 rather
than 18-90 and are not directly comparable with published values. Relative
ranking, which is what every analysis in this study uses, is unaffected.

## Approximations carried forward, and their direction

| Group | Source | Approximation |
|---|---|---|
| Animal fat | `SOLID_FATS` | FPED has no pure animal-fat component. Solid fats include shortening and hydrogenated vegetable fats, so this group is **over-inclusive** and its animal-food signal is diluted. |
| Legumes | `V_LEGUMES` + `PF_SOY`/4 | `V_LEGUMES` and `PF_LEGUMES` are the *same legumes* expressed as vegetables and as protein foods respectively (per USDA variable definitions); summing them would double-count. `V_LEGUMES` (cup-eq) is used alone, with soy products added at the standard 1 cup-eq = 4 oz-eq equivalence. |
| Vegetables | `V_TOTAL` − `V_STARCHY_POTATO` | `V_TOTAL` already excludes legumes per USDA definition, so no further subtraction is required. |
| Whole fruit | `F_TOTAL` − `F_JUICE` | `F_TOTAL` includes juices by definition. |

## Verification

A supplementary analysis computes PDI, hPDI and uPDI under both the
hierarchical (mutually exclusive) and the naive (overlapping) implementations
and reports Pearson and Spearman correlations between them. This is a
transparency check on implementation behaviour, not an alternative primary
analysis. High correlation would indicate the distortion is small in this
population; materially lower correlation for hPDI or uPDI than for PDI would
indicate that the overlap concentrates in the healthy/unhealthy contrast, which
is where it would matter most.
