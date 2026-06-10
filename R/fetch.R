# fetch.R
# Fetch each source, parse it into a tidy tibble of items, diff against
# previously-seen items, and archive raw responses.
#
# Design principles (learned the hard way with government sources):
#   1. Graceful failure: one broken source must not kill the run. Failures are
#      logged to data/failures.csv and surfaced on the dashboard.
#   2. Keep raw copies: documents occasionally vanish from government sites.
#      Raw responses are archived under data/raw/<source_id>/<date>.{json,html,xml}.
#   3. Be polite: identify yourself with a User-Agent and pause between requests.

suppressPackageStartupMessages({
  library(httr2)
  library(rvest)
  library(xml2)
  library(jsonlite)
  library(dplyr)
  library(purrr)
  library(readr)
  library(stringr)
  library(tibble)
})

USER_AGENT <- "surveillance-watch (public-records monitor; github.com/surveillance-watch/surveillance-watch)"

# ---- HTTP helpers -----------------------------------------------------------

polite_fetch <- function(url, api_key_header = NULL) {
  req <- request(url) |>
    req_user_agent(USER_AGENT) |>
    req_timeout(30) |>
    req_retry(max_tries = 3, backoff = ~10)
  if (!is.null(api_key_header)) {
    req <- req_headers(req, !!!api_key_header)
  }
  resp <- req_perform(req)
  Sys.sleep(2)  # politeness pause between sources
  resp
}

archive_raw <- function(source_id, body_text, ext) {
  dir <- file.path("data", "raw", source_id)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(dir, paste0(Sys.Date(), ".", ext))
  writeLines(body_text, path, useBytes = TRUE)
  invisible(path)
}

# Every parser returns a tibble with exactly these columns:
#   item_id (chr, stable unique key), title (chr), url (chr), date (chr, best effort)
empty_items <- function() {
  tibble(item_id = character(), title = character(),
         url = character(), date = character())
}

# ---- Parsers ----------------------------------------------------------------

parse_federal_register <- function(resp, source) {
  body <- resp_body_string(resp)
  archive_raw(source$id, body, "json")
  j <- fromJSON(body, simplifyVector = FALSE)
  if (length(j$results) == 0) return(empty_items())
  map_dfr(j$results, function(d) {
    tibble(
      item_id = d$document_number %||% d$html_url,
      title   = d$title %||% "(untitled)",
      url     = d$html_url %||% "",
      date    = d$publication_date %||% ""
    )
  })
}

parse_congress <- function(resp, source) {
  body <- resp_body_string(resp)
  archive_raw(source$id, body, "json")
  j <- fromJSON(body, simplifyVector = FALSE)
  if (length(j$bills) == 0) return(empty_items())
  items <- map_dfr(j$bills, function(b) {
    tibble(
      item_id = paste0(b$congress, "-", b$type, "-", b$number),
      title   = b$title %||% "(untitled)",
      url     = sprintf("https://www.congress.gov/bill/%sth-congress/%s/%s",
                        b$congress, tolower(b$type %||% ""), b$number),
      date    = b$latestAction$actionDate %||% ""
    )
  })
  # The bill endpoint is broad; keep only FISA-relevant titles.
  filter(items, str_detect(tolower(title),
    "fisa|surveillance|section 702|foreign intelligence"))
}

parse_congress_ndaa <- function(resp, source) {
  body <- resp_body_string(resp)
  archive_raw(source$id, body, "json")
  j <- fromJSON(body, simplifyVector = FALSE)
  if (length(j$bills) == 0) return(empty_items())
  items <- map_dfr(j$bills, function(b) {
    tibble(
      item_id = paste0(b$congress, "-", b$type, "-", b$number),
      title   = b$title %||% "(untitled)",
      url     = sprintf("https://www.congress.gov/bill/%sth-congress/%s/%s",
                        b$congress, tolower(b$type %||% ""), b$number),
      date    = b$latestAction$actionDate %||% ""
    )
  })
  filter(items, str_detect(tolower(title),
    "national defense authorization|israel.*(defense|security|cooperation)|defense technology cooperation"))
}

parse_fisc <- function(resp, source) {
  body <- resp_body_string(resp)
  archive_raw(source$id, body, "html")
  page <- read_html(body)
  # The FISC public-filings page lists filings in a views table; selectors
  # may need adjustment if the site is reorganized (check data/failures.csv).
  rows <- html_elements(page, "td.views-field-title a, .view-content a")
  if (length(rows) == 0) return(empty_items())
  tibble(
    title = html_text2(rows),
    url   = url_absolute(html_attr(rows, "href"), "https://www.fisc.uscourts.gov"),
    date  = ""
  ) |>
    filter(nchar(title) > 5) |>
    distinct(url, .keep_all = TRUE) |>
    mutate(item_id = url) |>
    select(item_id, title, url, date) |>
    head(25)
}

parse_odni <- function(resp, source) {
  body <- resp_body_string(resp)
  archive_raw(source$id, body, "html")
  page <- read_html(body)
  links <- html_elements(page, "a[href*='press-releases-2']")
  if (length(links) == 0) return(empty_items())
  tibble(
    title = html_text2(links),
    url   = url_absolute(html_attr(links, "href"), "https://www.dni.gov"),
    date  = ""
  ) |>
    filter(nchar(title) > 10) |>
    distinct(url, .keep_all = TRUE) |>
    mutate(item_id = url) |>
    select(item_id, title, url, date) |>
    head(25)
}

parse_pclob <- function(resp, source) {
  body <- resp_body_string(resp)
  archive_raw(source$id, body, "html")
  page <- read_html(body)
  links <- html_elements(page, "a[href$='.pdf'], a[href*='Documents']")
  if (length(links) == 0) return(empty_items())
  tibble(
    title = html_text2(links),
    url   = url_absolute(html_attr(links, "href"), "https://www.pclob.gov"),
    date  = ""
  ) |>
    filter(nchar(title) > 10) |>
    distinct(url, .keep_all = TRUE) |>
    mutate(item_id = url) |>
    select(item_id, title, url, date) |>
    head(25)
}

parse_rss <- function(resp, source) {
  body <- resp_body_string(resp)
  archive_raw(source$id, body, "xml")
  feed <- read_xml(body)
  items <- xml_find_all(feed, "//item | //*[local-name()='entry']")
  if (length(items) == 0) return(empty_items())
  out <- map_dfr(items, function(it) {
    link_node <- xml_find_first(it, "./link | ./*[local-name()='link']")
    link <- xml_text(link_node)
    if (is.na(link) || link == "") link <- xml_attr(link_node, "href")
    tibble(
      title = xml_text(xml_find_first(it, "./title | ./*[local-name()='title']")),
      url   = link %||% "",
      date  = xml_text(xml_find_first(
        it, "./pubDate | ./*[local-name()='updated'] | ./*[local-name()='published']"))
    )
  })
  out |>
    filter(str_detect(tolower(title), paste(RELEVANCE_KEYWORDS, collapse = "|"))) |>
    mutate(item_id = url) |>
    select(item_id, title, url, date)
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || is.na(a[1])) b else a

# ---- Fetch one source with graceful failure ---------------------------------

fetch_source <- function(source) {
  result <- tryCatch({
    headers <- NULL
    if (source$id %in% c("congress_fisa_bills", "congress_ndaa")) {
      key <- Sys.getenv("CONGRESS_API_KEY")
      if (key == "") stop("CONGRESS_API_KEY not set; skipping Congress.gov")
      headers <- list(`X-Api-Key` = key)
    }
    resp <- polite_fetch(source$url, api_key_header = headers)
    parser <- get(source$parse)
    items <- parser(resp, source)
    list(ok = TRUE, items = items, error = NA_character_)
  }, error = function(e) {
    list(ok = FALSE, items = empty_items(), error = conditionMessage(e))
  })
  result$source_id   <- source$id
  result$source_name <- source$name
  result
}

# ---- Diff against seen-state -------------------------------------------------

load_seen <- function(path = "data/seen.csv") {
  if (file.exists(path)) {
    read_csv(path, col_types = "cccccc")
  } else {
    tibble(source_id = character(), item_id = character(), title = character(),
           url = character(), date = character(), first_seen = character())
  }
}

diff_and_update <- function(results, seen_path = "data/seen.csv",
                            failures_path = "data/failures.csv") {
  seen <- load_seen(seen_path)
  today <- as.character(Sys.Date())

  new_items <- map_dfr(results, function(r) {
    if (!r$ok || nrow(r$items) == 0) return(NULL)
    r$items |>
      mutate(source_id = r$source_id) |>
      anti_join(seen, by = c("source_id", "item_id"))
  })

  if (nrow(new_items) > 0) {
    seen <- bind_rows(seen, mutate(new_items, first_seen = today))
    write_csv(seen, seen_path)
  }

  failures <- map_dfr(results, function(r) {
    if (r$ok) return(NULL)
    tibble(date = today, source_id = r$source_id, error = r$error)
  })
  if (nrow(failures) > 0) {
    old <- if (file.exists(failures_path)) read_csv(failures_path, col_types = "ccc") else NULL
    write_csv(bind_rows(old, failures), failures_path)
  }

  list(new_items = new_items, failures = failures, seen = seen)
}
