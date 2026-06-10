# run_check.R
# Entry point: fetch all sources, diff, and write a run summary.
# Run locally with:   Rscript R/run_check.R
# Run on CI weekly via .github/workflows/check-sources.yml

source("R/sources.R")
source("R/fetch.R")

message("surveillance-watch run: ", Sys.time())

results <- lapply(SOURCES, fetch_source)
out     <- diff_and_update(results)

message(nrow(out$new_items), " new item(s); ",
        nrow(out$failures), " source failure(s).")

# Write a small run-status file the dashboard reads.
status <- tibble::tibble(
  last_run    = as.character(Sys.time()),
  new_items   = nrow(out$new_items),
  failures    = nrow(out$failures),
  sources_ok  = sum(vapply(results, function(r) r$ok, logical(1))),
  sources_all = length(results)
)
readr::write_csv(status, "data/run_status.csv")

# Non-zero exit only if *everything* failed (lets CI flag total outages
# without failing the run for one flaky agency page).
if (status$sources_ok == 0) quit(status = 1)
