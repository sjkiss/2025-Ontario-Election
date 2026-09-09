library(ggplot2)
library(dplyr)
library(here)
#Run the script that imports the polls
source(here("R_Scripts/1_import_polls.R"))
# Ensure data is sorted
polls <- polls %>%
  arrange(`Last Date of Polling`)

ggplot(polls, aes(x = `Last Date of Polling`)) +
  # Scatter points for each party
  geom_point(aes(y = PC,      color = "PC"),      alpha = 0.5, size = 1) +
  geom_point(aes(y = NDP,     color = "NDP"),     alpha = 0.5, size = 1) +
  geom_point(aes(y = Liberal, color = "Liberal"), alpha = 0.5, size = 1) +
  geom_point(aes(y = Green,   color = "Green"),   alpha = 0.5, size = 1) +
  
  # Smoothed trend lines for each party
  geom_smooth(aes(y = PC,      color = "PC"),      se = FALSE, linewidth = 1) +
  geom_smooth(aes(y = NDP,     color = "NDP"),     se = FALSE, linewidth = 1) +
  geom_smooth(aes(y = Liberal, color = "Liberal"), se = FALSE, linewidth = 1) +
  geom_smooth(aes(y = Green,   color = "Green"),   se = FALSE, linewidth = 1) +
  
  labs(
    title    = "Ontario Vote Intention Over the Campaign Period",
    subtitle = "Polling trends by party (2022–2025)",
    x = "Date",
    y = "Vote Intention (%)",
    color = "Party",
    caption = "Source: Wikipedia polling aggregate"
  ) +
  
  scale_color_manual(values = c(
    "PC"      = "#6baed6",
    "NDP"     = "#E0A800",
    "Liberal" = "#8B0000",
    "Green"   = "#2a9d8f"
  )) +
  
  theme_minimal(base_size = 13) +
  theme(
    plot.title    = element_text(face = "bold"),
    legend.position = "bottom"
  )

