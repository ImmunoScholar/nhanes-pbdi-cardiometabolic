# ---------------------------------------------------------------------------
# utils.R -- shared helpers. Functions only; no side effects on source().
# ---------------------------------------------------------------------------

#' Timestamped console + file logger.
#' Every script writes its own log so a run is auditable after the fact.
log_msg <- function(..., level = "INFO", logfile = NULL) {
  line <- sprintf("[%s] %-5s %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                  level, paste0(...))
  cat(line, "\n", sep = "")
  if (!is.null(logfile)) cat(line, "\n", sep = "", file = logfile, append = TRUE)
  invisible(line)
}

#' SHA-256 of a file on disk.
#' Provenance anchor: lets us prove which byte-for-byte version of a public
#' file produced a given result, and detect silent upstream revisions.
file_sha256 <- function(path) {
  stopifnot(file.exists(path))
  digest::digest(file = path, algo = "sha256")
}

#' Download one file unless a byte-identical copy is already present.
#' Returns a one-row data.frame for the manifest.
download_if_needed <- function(url, dest, logfile = NULL, timeout = 600) {
  if (file.exists(dest)) {
    log_msg("cached: ", basename(dest), logfile = logfile)
    return(data.frame(file = basename(dest), url = url,
                      bytes = file.size(dest), sha256 = file_sha256(dest),
                      status = "cached", stringsAsFactors = FALSE))
  }
  old <- options(timeout = timeout); on.exit(options(old), add = TRUE)
  ok <- tryCatch({
    utils::download.file(url, dest, mode = "wb", quiet = TRUE); TRUE
  }, error = function(e) {
    log_msg("FAILED: ", basename(dest), " -- ", conditionMessage(e),
            level = "ERROR", logfile = logfile)
    FALSE
  })
  if (!ok) {
    if (file.exists(dest)) unlink(dest)   # never leave a truncated file behind
    return(data.frame(file = basename(dest), url = url, bytes = NA_real_,
                      sha256 = NA_character_, status = "failed",
                      stringsAsFactors = FALSE))
  }
  log_msg("downloaded: ", basename(dest), " (",
          format(file.size(dest), big.mark = ","), " bytes)", logfile = logfile)
  data.frame(file = basename(dest), url = url, bytes = file.size(dest),
             sha256 = file_sha256(dest), status = "downloaded",
             stringsAsFactors = FALSE)
}

#' Weighted quantiles (type 1 / inverse-CDF), for design-weighted description.
#' Not a variance estimator -- descriptive only. Design-based SEs come from
#' the `survey` package, never from here.
wtd_quantile <- function(x, w, probs = c(.01, .25, .5, .75, .99)) {
  keep <- is.finite(x) & is.finite(w) & w > 0
  x <- x[keep]; w <- w[keep]
  if (!length(x)) return(setNames(rep(NA_real_, length(probs)), probs))
  o <- order(x); x <- x[o]; w <- w[o]
  cw <- cumsum(w) / sum(w)
  setNames(vapply(probs, function(p) x[which(cw >= p)[1]], numeric(1)), probs)
}

#' Sample skewness (b1). Used only to decide log-transformation per the
#' frozen rule |skew| > 1, so an unweighted estimate is adequate and is
#' declared as such in the protocol.
skewness <- function(x) {
  x <- x[is.finite(x)]; n <- length(x)
  if (n < 3) return(NA_real_)
  m <- mean(x); s <- sqrt(sum((x - m)^2) / n)
  if (s == 0) return(NA_real_)
  sum((x - m)^3) / (n * s^3)
}

#' Append a row to the running QC ledger.
qc_add <- function(ledger, check, result, detail, blocking = FALSE) {
  rbind(ledger, data.frame(check = check, result = result, detail = detail,
                           blocking = blocking, stringsAsFactors = FALSE))
}
