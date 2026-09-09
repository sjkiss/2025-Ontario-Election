# ------------------------------------------------------------------
# Ontario leader approval — Abacus net-impression tracker, 2024–2026
# Source: sjkiss/2025-Ontario-Election / ontario_leader_approval_polls (1).xlsx
# Design choices:
#   - Abacus "net impression" only (consistent single-house series)
#   - Waves connected with lines: no smoothing, so every movement
#     shown is an actual movement in the data
#   - Starts Jan 2024, where regular tracking begins (drops the
#     lone Stiles wave from Mar 2023)
#   - Direct labels instead of a legend; election + Crombie
#     resignation annotated
# ------------------------------------------------------------------

library(readxl)
library(dplyr)
library(stringr)
library(lubridate)
library(ggplot2)

# --- 1. Download ---------------------------------------------------
# url <- "https://github.com/sjkiss/2025-Ontario-Election/raw/main/ontario_leader_approval_polls%20(1).xlsx"
# tmp <- tempfile(fileext = ".xlsx")
# download.file(url, tmp, mode = "wb")

# raw <- read_excel(tmp, sheet = "Leader Approval Polls")
library(here)
raw<-read_excel(path=here("Data/ontario_leader_approval_polls.xlsx"))
# --- 2. Clean ------------------------------------------------------
polls <- raw |>
  filter(Pollster == "Abacus Data", Metric == "net impression") |>
  rename(
    field_end = `Field End`,
    leader    = Leader,
    positive  = `Positive %`,
    negative  = `Negative %`,
    net       = Net
  ) |>
  mutate(
    date = case_when(
      str_detect(field_end, "^\\d{4}-\\d{2}-\\d{2}$") ~ ymd(field_end),
      str_detect(field_end, "^\\d{4}-\\d{2}$")        ~ ymd(paste0(field_end, "-15")),
      TRUE                                            ~ as.Date(NA)
    ),
    net = coalesce(net, positive - negative),
    leader = factor(
      leader,
      levels = c("Ford", "Crombie", "Stiles", "Fraser (interim Lib)")
    )
  ) |>
  filter(!is.na(date), !is.na(net), date >= as.Date("2024-01-01")) |>
  arrange(leader, date) |> 
  filter(field_end<"2025-03-01")

# --- 3. Direct labels at the end of each series --------------------
labels <- polls |>
  group_by(leader) |>
  slice_max(date, n = 1) |>
  ungroup() |>
  mutate(
    label   = recode(as.character(leader),
                     "Fraser (interim Lib)" = "Fraser\n(interim Lib)"),
    # manual nudges so Stiles/Fraser labels don't collide at the right edge
    nudge_y = case_when(
      leader == "Stiles"               ~  1.5,
      leader == "Fraser (interim Lib)" ~ -1.5,
      TRUE                             ~  0
    )
  )

party_cols <- c(
  "Ford"                 = "#1A4782",
  "Crombie"              = "#D71920",
  "Stiles"               = "#F37021",
  "Fraser (interim Lib)" = "#8B0000"
)

election_day    <- as.Date("2025-02-27")
resignation_day <- as.Date("2025-09-14")
y_bottom        <- min(polls$net) - 2

# --- 4. Plot -------------------------------------------------------
p <- ggplot(polls, aes(x = date, y = net, colour = leader)) +
  geom_hline(yintercept = 0, linewidth = 0.3, colour = "grey55") +
  # geom_vline(xintercept = election_day, linetype = "dashed",
  #            colour = "grey40", linewidth = 0.4) +
  # geom_vline(xintercept = resignation_day, linetype = "dotted",
  #            colour = "grey40", linewidth = 0.4) +
  # annotate("text", x = election_day, y = y_bottom,
  #          label = "Election\nFeb 27, 2025",
  #          hjust = 1.05, vjust = 0, size = 3, colour = "grey30") +
  # annotate("text", x = resignation_day, y = y_bottom,
  #          label = "Crombie announces\nresignation",
  #          hjust = -0.05, vjust = 0, size = 3, colour = "grey30") +
  geom_line(linewidth = 0.8, alpha = 0.9) +
  geom_point(size = 2.2) +
  geom_text(data = labels,
            aes(label = label, y = net + nudge_y),
            hjust = -0.15, size = 3.4, fontface = "bold",
            lineheight = 0.9, show.legend = FALSE) +
  scale_colour_manual(values = party_cols, guide = "none") +
  scale_x_date(breaks = seq(as.Date("2024-01-01"), as.Date("2025-03-01"),
                            by = "3 months"),
               date_labels = "%b %Y",
               expand = expansion(mult = c(0.02, 0.14))) +
  labs(
    title    = "Net impressions of Ontario party leaders, 2024\u20132026",
    subtitle = "Abacus Data, % positive minus % negative, by survey wave",
    x = NULL, y = "Net impression (points)",
    caption  = paste0(
      "Typical wave MOE \u00b1\u22483 percentage points."
    )
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title.position = "plot",
    axis.text.x = element_text(angle = 45, hjust = 1),
    panel.grid.minor = element_blank()
  )

print(p)

ggsave("ontario_leader_net_impressions.png", p, width = 10, height = 6, dpi = 300)
