
library(readxl)
library(dplyr)
library(stringr)
library(lubridate)
library(ggplot2)
library(ggrepel)
library(here)

# --- 1. Read cleaned data -------------------------------------------
raw <- read_excel(
  path  = here("data/ontario_leader_approval_polls.xlsx"),
  sheet = "Leader Approval Polls",
  col_types = "text"
)

# --- 2. Clean ---------------------------------------------------------
polls <- raw |>
  filter(
    (Pollster == "Abacus Data" & Metric == "net impression") |
      (Pollster == "Angus Reid Institute" & Metric %in% c("net favourability", "net approval"))
  ) |>
  rename(
    field_end = `Field End`,
    leader    = Leader,
    net       = Net,
    pollster  = Pollster
  ) |>
  mutate(
    date = case_when(
      str_detect(field_end, "^\\d+(\\.\\d+)?$")       ~ as.Date(as.numeric(field_end), origin = "1899-12-30"),
      str_detect(field_end, "^\\d{4}-\\d{2}-\\d{2}$") ~ ymd(field_end),
      str_detect(field_end, "^\\d{4}-\\d{2}$")        ~ ymd(paste0(field_end, "-15")),
      TRUE                                            ~ as.Date(NA)
    ),
    net = as.numeric(net),
    leader = factor(
      leader,
      levels = c("Ford", "Crombie", "Stiles", "Fraser (interim Lib)")
    ),
    pollster = factor(pollster, levels = c("Abacus Data", "Angus Reid Institute"))
  ) |>
  filter(!is.na(date), !is.na(net), date >= as.Date("2024-01-01")) |>
  arrange(leader, pollster, date)

party_cols <- c(
  "Ford"                 = "#1A4782",
  "Crombie"              = "#D71920",
  "Stiles"               = "#F37021",
  "Fraser (interim Lib)" = "#8B0000"
)

election_day <- as.Date("2025-02-27")

# --- Restrict to pre-election period --------------------------------
polls <- polls |> filter(date <= election_day)

# Direct labels: last wave per leader (across either pollster)
labels <- polls |>
  group_by(leader) |>
  slice_max(date, n = 1, with_ties = FALSE) |>
  ungroup() |>
  mutate(
    label = recode(as.character(leader),
                   "Fraser (interim Lib)" = "Fraser (interim Lib)")
  )

y_top    <- max(polls$net) + 6
y_bottom <- min(polls$net) - 3

# --- 4. Plot -------------------------------------------------------
p <- ggplot(polls, aes(x = date, y = net, colour = leader, linetype = pollster,
                       group = interaction(leader, pollster))) +
  geom_hline(yintercept = 0, linewidth = 0.3, colour = "grey55") +
  geom_vline(xintercept = election_day, linetype = "dotted",
             colour = "grey45", linewidth = 0.5) +
  annotate("label", x = election_day, y = y_top,
           label = "Election\nFeb 27, 2025",
           hjust = 1.05, vjust = 1, size = 3.1, colour = "grey25",
           fill = "white", label.size = 0, label.padding = unit(0.15, "lines")) +
  geom_line(linewidth = 0.9, alpha = 0.9) +
  geom_point(size = 2.3) +
  geom_text_repel(
    data = labels,
    aes(label = label),
    hjust = 0, direction = "y", nudge_x = 18, xlim = c(NA, Inf),
    segment.color = "grey70", segment.size = 0.3,
    size = 3.6, fontface = "bold", lineheight = 0.9,
    min.segment.length = 0, box.padding = 0.3,
    show.legend = FALSE
  ) +
  scale_colour_manual(values = party_cols, guide = "none") +
  scale_linetype_manual(values = c("Abacus Data" = "solid", "Angus Reid Institute" = "dashed"),
                        name = "Pollster") +
  guides(linetype = guide_legend(keywidth = unit(1.8, "cm"))) +
  scale_x_date(breaks = seq(as.Date("2024-01-01"), election_day, by = "3 months"),
               date_labels = "%b %Y",
               limits = c(as.Date("2024-01-01"), NA),
               expand = expansion(mult = c(0.02, 0.12))) +
  scale_y_continuous(expand = expansion(mult = c(0.06, 0.10))) +
  coord_cartesian(clip = "off") +
  labs(
    title    = "Net ratings of Ontario party leaders, Jan 2024\u2013Feb 2025",
    subtitle = "Abacus Data (net impression) & Angus Reid Institute (net favourability/approval), by survey wave",
    x = NULL, y = "Net rating (points)",
    caption  = "Typical wave MOE \u00b1\u22483 percentage points."
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title.position = "plot",
    plot.title    = element_text(face = "bold", size = 15, margin = margin(b = 4)),
    plot.subtitle = element_text(colour = "grey35", size = 10.5, margin = margin(b = 12)),
    plot.caption  = element_text(colour = "grey45", size = 8.5, margin = margin(t = 10)),
    axis.text.x   = element_text(angle = 45, hjust = 1),
    axis.title.y  = element_text(size = 10.5, colour = "grey25"),
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_blank(),
    legend.position = "bottom",
    legend.title = element_text(size = 9.5, face = "bold"),
    legend.text  = element_text(size = 9),
    plot.margin  = margin(t = 12, r = 55, b = 8, l = 8)
  )

print(p)

ggsave(here("Plots/ontario_leader_net_impressions.png"), p,
       width = 10, height = 6.2, dpi = 300)
