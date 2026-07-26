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
INT      := data/interim
PROC     := data/processed
LOGS     := outputs/logs
TAB      := outputs/tables
FIG      := outputs/figures

.PHONY: all deps clean clean-outputs verify help

## all: full pipeline, raw download through provenance freeze
all: docs/PROVENANCE.md

## deps: restore the pinned package library from renv.lock
deps:
> $(R) -e 'renv::restore(prompt = FALSE)'

# --- acquisition and validation -------------------------------------------
# The download gate is a raw .xpt file, NOT data/raw/MANIFEST.csv. MANIFEST.csv
# is committed (it is the provenance record), so using it as the target made
# make consider the download satisfied on a fresh clone and jump straight to
# 02_import.R, which then failed with "No .xpt files in data/raw/". P_DEMO.xpt
# is gitignored, so it is absent exactly when a download is actually needed.
$(RAW)/P_DEMO.xpt: analysis/01_download.R R/utils.R
> $(R) analysis/01_download.R

$(INT)/nhanes_raw_list.rds: analysis/02_import.R docs/variable_specification.csv $(RAW)/P_DEMO.xpt
> $(R) analysis/02_import.R

$(LOGS)/03_qc_report.md: analysis/03_quality_control.R $(INT)/nhanes_raw_list.rds
> $(R) analysis/03_quality_control.R

$(INT)/dag.rds: analysis/00_dag.R R/utils.R
> $(R) analysis/00_dag.R

# --- exposure, outcome, covariates ----------------------------------------
$(TAB)/04_wweia_category_conflicts.csv: analysis/04_wweia_conflicts.R docs/pdi_food_group_mapping.csv docs/wweia_adjudications.csv $(LOGS)/03_qc_report.md
> $(R) analysis/04_wweia_conflicts.R

$(INT)/exposure_pdi.rds: analysis/05_exposure_pdi.R $(TAB)/04_wweia_category_conflicts.csv
> $(R) analysis/05_exposure_pdi.R

$(INT)/outcome_composite.rds: analysis/06_outcome_composite.R $(LOGS)/03_qc_report.md
> $(R) analysis/06_outcome_composite.R

$(INT)/analytic_dataset.rds: analysis/07_covariates.R $(INT)/exposure_pdi.rds $(INT)/outcome_composite.rds
> $(R) analysis/07_covariates.R

$(INT)/imputed_data.rds: analysis/08_missing_data.R $(INT)/analytic_dataset.rds
> $(R) analysis/08_missing_data.R

# --- estimation ------------------------------------------------------------
$(TAB)/09_primary_models.csv: analysis/09_models_primary.R $(INT)/imputed_data.rds $(INT)/dag.rds
> $(R) analysis/09_models_primary.R

$(INT)/calibration.rds: analysis/10_calibration.R $(INT)/imputed_data.rds
> $(R) analysis/10_calibration.R

$(TAB)/11_vif_groups.csv: analysis/11_collinearity_check.R $(INT)/imputed_data.rds $(INT)/exposure_pdi.rds
> $(R) analysis/11_collinearity_check.R

$(INT)/substitution.rds: analysis/12_models_substitution.R $(TAB)/11_vif_groups.csv
> $(R) analysis/12_models_substitution.R

$(INT)/pca.rds: analysis/13_pca.R $(INT)/outcome_composite.rds
> $(R) analysis/13_pca.R

$(TAB)/14_pca_associations.csv: analysis/14_pca_associations.R $(INT)/pca.rds docs/pca_component_names.md
> $(R) analysis/14_pca_associations.R

$(INT)/sensitivity.rds: analysis/15_sensitivity.R $(TAB)/09_primary_models.csv $(INT)/calibration.rds
> $(R) analysis/15_sensitivity.R

$(TAB)/16_mediation_exploratory.csv: analysis/16_mediation_exploratory.R $(INT)/sensitivity.rds
> $(R) analysis/16_mediation_exploratory.R

# --- manuscript outputs and preservation ----------------------------------
$(TAB)/T1_characteristics.csv: analysis/17_tables.R $(INT)/sensitivity.rds $(INT)/substitution.rds $(TAB)/14_pca_associations.csv $(TAB)/16_mediation_exploratory.csv
> $(R) analysis/17_tables.R

# imputed_data.rds is listed because 18_figures.R reads it directly: the
# analytic SEQNs decide which rows the descriptive statistics on F2 and F6 are
# computed over (Amendment 13). It is already upstream via T1, but a direct
# input belongs in the prerequisites.
$(FIG)/F1_sensitivity_forest.png: analysis/18_figures.R $(TAB)/T1_characteristics.csv $(INT)/imputed_data.rds
> $(R) analysis/18_figures.R

# CAPTIONS.md is a prerequisite because 19_freeze_provenance.R validates its
# *Source:* paths against the artefact manifest. Without it, editing a caption
# would not re-run the check that the caption is still true.
docs/PROVENANCE.md: analysis/19_freeze_provenance.R $(FIG)/F1_sensitivity_forest.png docs/manuscript/CAPTIONS.md
> $(R) analysis/19_freeze_provenance.R

## verify: rebuild everything and confirm artefact checksums are unchanged
verify:
> cp docs/artefact_checksums.csv /tmp/baseline_checksums.csv
> $(MAKE) clean-outputs
> $(MAKE) all
> @diff -q /tmp/baseline_checksums.csv docs/artefact_checksums.csv \
>   && echo "REPRODUCIBILITY: PASS -- all artefact checksums identical" \
>   || echo "REPRODUCIBILITY: DIFFERENCES FOUND -- inspect the diff"

## clean-outputs: remove generated outputs but keep downloaded raw data
clean-outputs:
> rm -rf $(INT)/* $(PROC)/* $(FIG)/* $(TAB)/* $(LOGS)/*

## clean: remove everything reproducible, including raw downloads
clean: clean-outputs
> rm -rf $(RAW)/*

## help: list targets
help:
> @grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## //'
