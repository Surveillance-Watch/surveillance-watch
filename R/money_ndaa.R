# money_ndaa.R
# Module: campaign-finance + committee-roster data for the Section 224 analysis.
#
# Data sources (all official):
#   - FEC API (api.open.fec.gov) — PAC contributions and independent expenditures.
#     Free key at https://api.data.gov/signup/ ; set as env var FEC_API_KEY.
#     DEMO_KEY works for light testing (low rate limit).
#   - Congress.gov API — House Armed Services Committee roster + NDAA bill status.
#     Uses the same CONGRESS_API_KEY as the main project.
#
# Note on OpenSecrets: its public API has had availability changes; this module
# uses the FEC directly, which is the primary source OpenSecrets itself builds on.
# OpenSecrets bulk downloads remain useful for cross-checking if available.

suppressPackageStartupMessages({
  library(httr2)
  library(jsonlite)
  library(dplyr)
  library(purrr)
  library(readr)
  library(stringr)
  library(tibble)
})

USER_AGENT <- "Surveillance Watch (public-records monitor; github.com/surveillance-watch/surveillance-watch)"

FEC_BASE <- "https://api.open.fec.gov/v1"

fec_key <- function() {
  k <- Sys.getenv("FEC_API_KEY")
  if (k == "") "DEMO_KEY" else k
}

fec_get <- function(path, params = list()) {
  params$api_key <- fec_key()
  params$per_page <- params$per_page %||% 100
  req <- request(paste0(FEC_BASE, path)) |>
    req_url_query(!!!params) |>
    req_user_agent(USER_AGENT) |>
    req_retry(max_tries = 3, backoff = ~10) |>
    req_timeout(30)
  resp <- req_perform(req)
  Sys.sleep(1)
  fromJSON(resp_body_string(resp), simplifyVector = TRUE, flatten = TRUE)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# ---- 1. Find the PAC committees by name -------------------------------------
# Don't hardcode FEC committee IDs; look them up and eyeball the results once.
# Expected hits include AIPAC's connected PAC and the United Democracy Project
# super PAC; verify names/IDs in the returned tibble before trusting downstream.

find_committees <- function(query) {
  j <- fec_get("/committees/", list(q = query, sort = "-receipts"))
  as_tibble(j$results) |>
    select(any_of(c("committee_id", "name", "committee_type_full",
                    "designation_full", "party_full")))
}

# ---- 2. Direct contributions from a PAC to candidates (Schedule B) ----------
# Disbursements from the PAC; recipient committees that are candidate committees
# are the direct-contribution channel.

pac_contributions <- function(committee_id, cycle = 2026) {
  results <- list(); page <- 1
  repeat {
    j <- fec_get(paste0("/committee/", committee_id, "/schedules/schedule_b/"),
                 list(two_year_transaction_period = cycle, page = page))
    if (length(j$results) == 0) break
    results[[page]] <- as_tibble(j$results)
    if (page >= (j$pagination$pages %||% 1)) break
    page <- page + 1
    if (page > 50) break  # safety valve; raise if you need full history
  }
  if (length(results) == 0) return(tibble())
  bind_rows(results) |>
    select(any_of(c("recipient_name", "recipient_committee_id",
                    "disbursement_amount", "disbursement_date",
                    "disbursement_description"))) |>
    arrange(desc(disbursement_amount))
}

# ---- 3. Independent expenditures supporting/opposing candidates (Sched. E) --
# This is where super PAC spending (e.g., United Democracy Project) appears.

pac_independent_expenditures <- function(committee_id, cycle = 2026) {
  results <- list(); page <- 1
  repeat {
    j <- fec_get("/schedules/schedule_e/",
                 list(committee_id = committee_id, cycle = cycle, page = page))
    if (length(j$results) == 0) break
    results[[page]] <- as_tibble(j$results)
    if (page >= (j$pagination$pages %||% 1)) break
    page <- page + 1
    if (page > 50) break
  }
  if (length(results) == 0) return(tibble())
  bind_rows(results) |>
    select(any_of(c("candidate_name", "candidate_id", "support_oppose_indicator",
                    "expenditure_amount", "expenditure_date"))) |>
    arrange(desc(expenditure_amount))
}

# ---- 4. House Armed Services Committee roster (Congress.gov) ----------------
# Committee code for House Armed Services is "hsas00".

hasc_roster <- function(congress = 119) {
  key <- Sys.getenv("CONGRESS_API_KEY")
  if (key == "") stop("CONGRESS_API_KEY not set")
  req <- request(sprintf(
      "https://api.congress.gov/v3/committee/%d/house/hsas00?format=json", congress)) |>
    req_headers(`X-Api-Key` = key) |>
    req_user_agent(USER_AGENT) |>
    req_timeout(30)
  j <- fromJSON(resp_body_string(req_perform(req)),
                simplifyVector = TRUE, flatten = TRUE)
  # The committee endpoint returns membership in current shape; normalize to a
  # name/party/state tibble. Field names occasionally shift — inspect j if empty.
  members <- j$committee$members %||% j$committee$membership %||% NULL
  if (is.null(members)) {
    warning("Roster fields not where expected; returning raw object for inspection")
    return(j)
  }
  as_tibble(members)
}

# ---- 5. NDAA FY2027 bill tracking -------------------------------------------
# Once the NDAA bill number is known (check congress.gov for the FY27 NDAA,
# introduced ~May 2026), set it here to pull latest actions into the tracker.

ndaa_status <- function(congress = 119, bill_type = "hr", bill_number) {
  key <- Sys.getenv("CONGRESS_API_KEY")
  if (key == "") stop("CONGRESS_API_KEY not set")
  req <- request(sprintf(
      "https://api.congress.gov/v3/bill/%d/%s/%s/actions?format=json&limit=50",
      congress, bill_type, bill_number)) |>
    req_headers(`X-Api-Key` = key) |>
    req_user_agent(USER_AGENT) |>
    req_timeout(30)
  j <- fromJSON(resp_body_string(req_perform(req)),
                simplifyVector = TRUE, flatten = TRUE)
  as_tibble(j$actions)
}
