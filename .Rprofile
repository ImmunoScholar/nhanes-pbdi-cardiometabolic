# Project profile. Loaded by R when the working directory is the project root,
# which suppresses the user-level ~/.Rprofile -- so the environment is the same
# for every user on every machine.
#
# IMPORTANT: do not run pipeline scripts with `Rscript --vanilla`. That flag
# skips this file, renv never activates, and the scripts silently resolve
# packages from the system library instead of the pinned project library.
# The Makefile uses `Rscript --no-restore --no-save` for exactly this reason.

# Binary package repository for Ubuntu 24.04 (noble). Recorded here rather than
# left to the user's global config so that `renv::restore()` is reproducible and
# does not require compiling every package from source.
options(
  repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/noble/latest"),
  HTTPUserAgent = sprintf(
    "R/%s R (%s)", getRversion(),
    paste(getRversion(), R.version["platform"], R.version["arch"], R.version["os"])
  )
)

source("renv/activate.R")
