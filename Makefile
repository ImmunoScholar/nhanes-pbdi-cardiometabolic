# ---------------------------------------------------------------------------
# Reproducible build. `make all` rebuilds every result from public source data.
#
# NOTE: this Makefile sets .RECIPEPREFIX to '>' instead of relying on TAB
# characters. Recipe lines therefore begin with '>'. This is deliberate --
# it makes the file immune to editors and tooling that silently convert
# leading tabs to spaces, which is the single most common way a generated
# Makefile breaks. Requires GNU Make >= 3.82.
# ---------------------------------------------------------------------------
.RECIPEPREFIX = >
.DELETE_ON_ERROR:
SHELL := /bin/bash

# NOT --vanilla: that flag skips .Rprofile, which means renv never activates
# and scripts silently resolve packages from the system library instead of the
# pinned project library. --no-restore --no-save gives a clean session while
# still loading the project profile.
R := Rscript --no-restore --no-save

RAW      := data/raw
INTERIM  := data/interim
LOGS     := outputs/logs
TABLES   := outputs/tables

MANIFEST := $(RAW)/MANIFEST.csv
IMPORTED := $(INTERIM)/nhanes_raw_list.rds
QCREPORT := $(LOGS)/03_qc_report.md
DAG      := $(INTERIM)/dag.rds

.PHONY: all dag download import qc clean clean-outputs deps help

## all: full pipeline through the quality-control gate
all: qc dag

## dag: encode the causal structure and validate the adjustment set
dag: $(DAG)
$(DAG): analysis/00_dag.R R/utils.R
> $(R) analysis/00_dag.R

## deps: restore the pinned package library from renv.lock
deps:
> $(R) -e 'renv::restore(prompt = FALSE)'

## download: fetch public NHANES/USDA data and verify checksums
download: $(MANIFEST)
$(MANIFEST): analysis/01_download.R R/utils.R
> $(R) analysis/01_download.R

## import: read .XPT and validate against the frozen variable specification
import: $(IMPORTED)
$(IMPORTED): analysis/02_import.R docs/variable_specification.csv $(MANIFEST)
> $(R) analysis/02_import.R

## qc: mandatory quality-control gate; halts on any blocking failure
qc: $(QCREPORT)
$(QCREPORT): analysis/03_quality_control.R $(IMPORTED)
> $(R) analysis/03_quality_control.R

## clean-outputs: remove generated outputs but keep downloaded raw data
clean-outputs:
> rm -rf $(INTERIM)/* data/processed/* outputs/figures/* outputs/tables/* $(LOGS)/*

## clean: remove everything reproducible, including raw downloads
clean: clean-outputs
> rm -rf $(RAW)/*

## help: list targets
help:
> @grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## //'
