# Surveillance Watch

**A weekly, automated monitor of the public record on U.S. surveillance
authorities.** Every Monday it checks primary sources (the Federal Register,
the FISA Court's public docket, ODNI press releases, PCLOB oversight reports,
and Congress.gov) plus a small set of analysis feeds, and publishes anything
new as a digest. Raw copies of everything fetched are archived in this
repository, because public documents sometimes disappear.

**Live site:** https://surveillance-watch.github.io/surveillance-watch/
*(adjust if your org/repo slug differs)*

## Why this exists

Most of what the public knows about how U.S. surveillance authorities are
used, including documented abuses, surfaces through a slow drip of
declassified FISA Court opinions, annual transparency reports, and oversight
findings. Those documents are public, but scattered and inconvenient to
watch. Meanwhile, the rules governing authorities like Executive Order 12333
can change with a presidential signature, with the only public marker a
Federal Register entry. This project makes the visible part of the system
actually convenient to see: one page, updated weekly, with the receipts
archived.

## What it watches

| Source | What it tells you |
|---|---|
| Federal Register API | New executive orders and any document citing EO 12333 |
| FISA Court public docket | Declassified opinions and orders, incl. compliance findings |
| ODNI press releases | Annual Statistical Transparency Report, declassifications |
| PCLOB | Independent oversight reports on 702 and 12333 |
| Congress.gov API | FISA/Section 702 bills and FY27 NDAA (incl. Section 224) |
| Lawfare, EFF feeds | Legal analysis, filtered to surveillance topics |

Everything monitored is a public record published by the government or by
established organizations. Methods are visible in this repo; nothing here
requires trusting us: see below for running your own copy.

## Reading the dashboard

- **New this week** - items first seen since the last check.
- **Full record by source** - everything seen so far, newest first.
- **Source health** - fetch failures (agency sites get redesigned; when a
  source appears here, its parser needs a selector update).

## Repository layout

```
.github/workflows/check-sources.yml   weekly cron: fetch → commit → render → deploy
R/sources.R                           registry of monitored sources
R/fetch.R                             fetch + parse + diff + raw archiving
R/run_check.R                         entry point
R/money_ndaa.R                        FEC campaign-finance + committee-roster module
R/analysis_hasc.R                     HASC × money × Section-224-position cross-tab
index.qmd / _quarto.yml / styles.css  the dashboard
data/seen.csv                         every item ever seen (the diff state)
data/failures.csv                     source-failure log
data/raw/<source>/<date>.*            raw archived responses
```

---

## Run your own copy

Don't want to trust this instance? Good instincts - it forks in ~15 minutes and runs
free on GitHub Actions, no server required.

1. **Fork or push this repo** to your account or organization.
2. **Congress.gov API key** (free: https://api.congress.gov/sign-up/) → repo
   Settings → Secrets and variables → Actions → new secret `CONGRESS_API_KEY`.
   (Everything else works without keys; skipping this only disables the
   Congress sources.)
3. **Enable GitHub Pages**: Settings → Pages → Source: **GitHub Actions**.
4. **Run once manually**: Actions tab → `check-sources` → Run workflow.
5. Update the `USER_AGENT` string in `R/fetch.R` and `R/money_ndaa.R` to
   point at *your* fork; also, identifying your bot is good scraping etiquette.

It then runs every Monday 13:00 UTC (edit the cron line to taste).

### Running locally (RStudio)

```r
install.packages(c("httr2","rvest","xml2","jsonlite","dplyr",
                   "purrr","readr","stringr","tibble","tidyr","knitr"))
Sys.setenv(CONGRESS_API_KEY = "your-key")   # optional
source("R/run_check.R")
```

Render the dashboard with `quarto render`.

### Money & NDAA module (Section 224 analysis)

`R/money_ndaa.R` provides functions for the FEC API (PAC direct
contributions via Schedule B, super PAC independent expenditures via
Schedule E), the House Armed Services Committee roster, and FY27 NDAA bill
actions. Free FEC key at https://api.data.gov/signup/ → env var
`FEC_API_KEY` (`DEMO_KEY` works for light testing).

`R/analysis_hasc.R` cross-tabulates HASC members × campaign money ×
hand-coded member positions on NDAA Section 224. Committee markup votes on
provisions are often unrecorded (the June 2026 Khanna strike amendment
failed on a voice vote), so positions are coded manually in
`data/hasc_positions.csv` with an evidence-type column. Read the script's
header comments before interpreting results: selection effects mean money
follows votes as readily as votes follow money, and a near-unanimous vote
leaves funding nothing to explain. Recorded floor votes are the better
dataset when they occur.

### Maintenance

- **Scrapers drift.** When a source appears in "Source health," open its
  archived raw HTML under `data/raw/<source_id>/`, find the new page
  structure, and update the matching `parse_*` function in `R/fetch.R`.
- **Raw archives are part of the value.** Prune old raw HTML if the repo
  grows large, but keep PDFs and JSON.
- **Adding a source** is one entry in `R/sources.R` plus (for scrape types)
  a small parser returning `item_id, title, url, date`.
- **Email digests:** add a `blastula` step in `run_check.R` sending
  `out$new_items`; an SMTP secret in Actions is all it needs.

## License

Code is MIT-licensed (see LICENSE). Archived documents are U.S. government
public records.
