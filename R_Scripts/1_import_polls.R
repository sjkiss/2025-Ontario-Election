library(rvest)
library(dplyr)
library(janitor)
library(readr)
library(lubridate)
library(writexl)
library(haven)
library(srvyr)

# URL
url <- "https://en.wikipedia.org/wiki/2025_Ontario_general_election"

# Read page
page <- read_html(url)

# Extract polling table (26th table)
polls <- page %>%
  html_nodes("table") %>%
  .[26] %>%
  html_table(fill = TRUE) %>%
  data.frame()

# Clean column names
polls <- clean_names(polls)

# Remove non-data rows
polls <- polls[-c(1:5), ]
polls <- polls[-c(135:136), ]

# Keep only needed columns
polls <- polls[, c(1, 2, 4, 5, 6, 7)]

# Rename columns
names(polls) <- c(
  "Polling Firm",
  "Last Date of Polling",
  "PC",
  "NDP",
  "Liberal",
  "Green"
)

# Keep only real poll rows (removes event text rows)
polls <- polls %>%
  filter(grepl("^[0-9]", PC))

# Convert to numeric
polls[, 3:6] <- lapply(polls[, 3:6], parse_number)

# Convert dates
polls$`Last Date of Polling` <- mdy(polls$`Last Date of Polling`)

# Export to Excel
write_xlsx(polls, "vote_intention.xlsx")

# View result
glimpse(polls)
head(polls)