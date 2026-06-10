# sources.R
# Registry of monitored sources. Each source is a list with:
#   id      - short stable identifier (used in seen-state and raw archive paths)
#   name    - human-readable label for the dashboard
#   type    - "api_json", "scrape", or "rss"
#   url     - endpoint or page to fetch
#   parse   - name of the parser function in fetch.R
#   notes   - what this source tells you
#
# Add or remove sources here; nothing else needs to change.

SOURCES <- list(

  # ---- Structured APIs (reliable) ------------------------------------------

  list(
    id    = "federal_register_eo",
    name  = "Federal Register — Executive orders & presidential documents (intelligence/surveillance)",
    type  = "api_json",
    url   = paste0(
      "https://www.federalregister.gov/api/v1/documents.json",
      "?conditions%5Bterm%5D=intelligence%20surveillance",
      "&conditions%5Btype%5D%5B%5D=PRESDOCU",
      "&order=newest&per_page=20"
    ),
    parse = "parse_federal_register",
    notes = "Catches new EOs or amendments touching surveillance authorities (the 'changed with a signature' problem)."
  ),

  list(
    id    = "federal_register_12333",
    name  = "Federal Register — Documents citing EO 12333",
    type  = "api_json",
    url   = paste0(
      "https://www.federalregister.gov/api/v1/documents.json",
      "?conditions%5Bterm%5D=%22Executive%20Order%2012333%22",
      "&order=newest&per_page=20"
    ),
    parse = "parse_federal_register",
    notes = "Anything published that references EO 12333 directly, including agency procedure changes."
  ),

  list(
    id    = "congress_fisa_bills",
    name  = "Congress.gov — Bills mentioning FISA / Section 702",
    type  = "api_json",
    # Requires CONGRESS_API_KEY in env. Free key: https://api.congress.gov/sign-up/
    url   = "https://api.congress.gov/v3/bill?format=json&limit=20&sort=updateDate+desc",
    parse = "parse_congress",
    notes = "Tracks reauthorization and reform bills. Filtered to FISA-related titles in the parser."
  ),

  # ---- Scrape targets (stable pages, but selectors may need maintenance) ----

  list(
    id    = "fisc_filings",
    name  = "FISA Court — Public filings & opinions",
    type  = "scrape",
    url   = "https://www.fisc.uscourts.gov/public-filings",
    parse = "parse_fisc",
    notes = "Declassified opinions and orders. This is where compliance-violation findings surface."
  ),

  list(
    id    = "odni_press",
    name  = "ODNI — Reports & Publications",
    type  = "scrape",
    url   = "https://www.dni.gov/index.php/newsroom/reports-publications/reports-publications-2026",
    parse = "parse_odni",
    notes = "Annual Statistical Transparency Report lands here each spring, plus declassification announcements."
  ),

  list(
    id    = "pclob_reports",
    name  = "PCLOB — Oversight reports",
    type  = "scrape",
    url   = "https://www.pclob.gov/Oversight",
    parse = "parse_pclob",
    notes = "Privacy and Civil Liberties Oversight Board: deepest independent public reports on 702 and 12333."
  ),

  # ---- RSS (interpretation / analysis) --------------------------------------

  list(
    id    = "congress_ndaa",
    name  = "Congress.gov — FY2027 NDAA and US-Israel defense cooperation bills",
    type  = "api_json",
    url   = "https://api.congress.gov/v3/bill?format=json&limit=20&sort=updateDate+desc",
    parse = "parse_congress_ndaa",
    notes = "Tracks the FY27 NDAA (Section 224, US-Israel Defense Technology Cooperation Initiative) and related bills."
  ),

  list(
    id    = "lawfare_rss",
    name  = "Lawfare — Surveillance coverage",
    type  = "rss",
    url   = "https://www.lawfaremedia.org/feeds/rss",
    parse = "parse_rss",
    notes = "Legal analysis of FISA developments. Filtered to surveillance keywords in the parser."
  ),

  list(
    id    = "eff_rss",
    name  = "EFF — Deeplinks blog",
    type  = "rss",
    url   = "https://www.eff.org/rss/updates.xml",
    parse = "parse_rss",
    notes = "Civil-liberties tracking and action alerts. Filtered to surveillance keywords in the parser."
  )
)

# Keywords used to filter broad feeds down to relevant items.
RELEVANCE_KEYWORDS <- c(
  "fisa", "702", "12333", "surveillance", "warrantless", "fisc",
  "foreign intelligence", "section 215", "executive order", "wiretap",
  "data broker", "fourth amendment"
)
