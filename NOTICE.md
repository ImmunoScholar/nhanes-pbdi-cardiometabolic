# Scope of the licences in this repository

This repository contains three kinds of material under three different terms.
Nothing here changes the terms in `LICENSE`; this file records which files each
set of terms applies to.

`LICENSE` holds the MIT licence text alone, with nothing appended, so that
GitHub and other automated tools identify the repository as MIT rather than
falling back to "Other". This file carries the scope statement that used to sit
underneath that text.

## Software — MIT

The MIT licence in `LICENSE` applies to the software in this repository:

- everything under `analysis/` and `R/`
- the `Makefile`
- configuration files (`.Rprofile`, `renv.lock`, `.gitignore`, `CITATION.cff`)

## Manuscript text, tables and figures — CC BY 4.0

Everything under `docs/` and `outputs/` is licensed under Creative Commons
Attribution 4.0 International (CC BY 4.0):
<https://creativecommons.org/licenses/by/4.0/>

This covers the manuscript sections in `docs/manuscript/`, the protocol and its
amendments, and every generated table and figure in `outputs/`.

## Source data — neither licence applies

**Neither licence applies to the source data.** The NHANES, FPED and FNDDS files
this pipeline downloads are public works of the United States federal government
(CDC/NCHS and USDA ARS). They are **not redistributed here**: they are fetched
from their official sources at build time, their provenance is recorded in
`data/raw/MANIFEST.csv`, their integrity is pinned in `docs/checksums.lock`, and
they remain subject to those agencies' own terms of use.
