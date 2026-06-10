# analysis_hasc.R
# The empirical question: does AIPAC-affiliated money predict HASC members'
# positions on NDAA Section 224 (US-Israel Defense Technology Cooperation
# Initiative)? Run interactively in RStudio.
#
# Honest-methods notes, read before interpreting anything:
#   1. Committee markup votes on individual provisions are often voice votes
#      or unrecorded. data/hasc_positions.csv is therefore hand-coded by you
#      from markup records, amendment votes, and public statements. Code the
#      *evidence type* so readers can weigh it (recorded_vote > amendment_vote
#      > public_statement > inferred).
#   2. Correlation here cannot establish causation in either direction:
#      PACs donate to members who already agree with them (selection), so a
#      positive association is consistent with both "money moves votes" and
#      "money follows votes". What the cross-tab CAN do is test whether the
#      simple narrative even survives contact with the data — often it doesn't,
#      e.g., if support for the provision is near-universal regardless of money.
#   3. Name-matching FEC records to members is messy (nicknames, middle
#      initials). Inspect every join; do not trust fuzzy matches blindly.

source("R/money_ndaa.R")
library(tidyr)

# ---- Step 1: identify the committees (run once, eyeball, record IDs) --------
candidates <- find_committees("AIPAC")
print(candidates)
udp <- find_committees("United Democracy Project")
print(udp)

# After inspecting, set the verified IDs:
AIPAC_PAC_ID <- "FILL_ME_IN"   # from `candidates` above
UDP_ID       <- "FILL_ME_IN"   # from `udp` above

# ---- Step 2: pull the money ---------------------------------------------------
direct <- pac_contributions(AIPAC_PAC_ID, cycle = 2026)
indep  <- pac_independent_expenditures(UDP_ID, cycle = 2026)
write_csv(direct, "data/aipac_direct_2026.csv")
write_csv(indep,  "data/udp_independent_2026.csv")

# ---- Step 3: the roster -------------------------------------------------------
roster <- hasc_roster(congress = 119)
write_csv(roster, "data/hasc_roster.csv")

# ---- Step 4: hand-coded positions --------------------------------------------
# Fill in data/hasc_positions.csv (template created by this script if absent):
#   member_name, position (support/oppose/unclear), evidence_type, source_url
if (!file.exists("data/hasc_positions.csv")) {
  write_csv(
    tibble(member_name = roster$name %||% character(),
           position = "", evidence_type = "", source_url = ""),
    "data/hasc_positions.csv")
  message("Template written to data/hasc_positions.csv — code positions, then re-run from here.")
}
positions <- read_csv("data/hasc_positions.csv", col_types = "cccc")

# ---- Step 5: join and tabulate ------------------------------------------------
# Normalize names for matching: "LAST, FIRST" vs "First Last" etc.
norm_name <- function(x) {
  x |> str_to_upper() |> str_replace_all("[^A-Z ]", "") |>
    str_squish() |>
    # crude LAST FIRST -> FIRST LAST flip when comma-form was stripped:
    identity()
}

money_by_member <- direct |>
  mutate(name_key = norm_name(recipient_name)) |>
  group_by(name_key) |>
  summarise(direct_total = sum(disbursement_amount, na.rm = TRUE))

crosstab <- positions |>
  mutate(name_key = norm_name(member_name)) |>
  left_join(money_by_member, by = "name_key") |>
  mutate(direct_total = replace_na(direct_total, 0),
         funded = direct_total > 0)

# IMPORTANT: inspect unmatched names before believing any of this:
message("Members with no FEC name match (verify these aren't matching failures):")
print(filter(crosstab, direct_total == 0)$member_name)

# The actual question:
with(filter(crosstab, position %in% c("support", "oppose")),
     table(funded, position))

# If both funded and unfunded members overwhelmingly support, the money
# variable has no explanatory work to do — that's a finding. If positions
# split and split along funding lines, the next step is controls (party,
# district lean, defense-industry money generally), not a conclusion.
