library(ggplot2)
library(dplyr)
library(here)

# Run the script that imports the polls
source(here("R_Scripts/1_import_polls.R"))

# Ensure data is sorted
polls <- polls %>%
  arrange(`Last Date of Polling`)

# --- Set the campaign start date here ---
campaign_start <- as.Date("2025-01-28")  # adjust to your actual cutoff

# Split into two periods
polls_precampaign <- polls %>%
  filter(`Last Date of Polling` < campaign_start)

polls_campaign <- polls %>%
  filter(`Last Date of Polling` >= campaign_start)

# Shared party colors
party_colors <- c(
  "PC"      = "blue",
  "NDP"     = "orange",
  "Liberal" = "red",
  "Green"   = "green"
)

# Reusable plot function
make_vote_plot <- function(data, title, subtitle) {
  ggplot(data, aes(x = `Last Date of Polling`)) +
    geom_point(aes(y = PC,      color = "PC"),      alpha = 0.5, size = 1) +
    geom_point(aes(y = NDP,     color = "NDP"),     alpha = 0.5, size = 1) +
    geom_point(aes(y = Liberal, color = "Liberal"), alpha = 0.5, size = 1) +
    geom_point(aes(y = Green,   color = "Green"),   alpha = 0.5, size = 1) +
    
    geom_smooth(aes(y = PC,      color = "PC"),      se = FALSE, linewidth = 1) +
    geom_smooth(aes(y = NDP,     color = "NDP"),     se = FALSE, linewidth = 1) +
    geom_smooth(aes(y = Liberal, color = "Liberal"), se = FALSE, linewidth = 1) +
    geom_smooth(aes(y = Green,   color = "Green"),   se = FALSE, linewidth = 1) +
    
    labs(
      title    = title,
      subtitle = subtitle,
      x = "Date",
      y = "Vote Intention (%)",
      color = "Party",
      caption = "Source: Wikipedia polling aggregate"
    ) +
    
    scale_color_manual(values = party_colors) +
    
    theme_minimal(base_size = 13) +
    theme(
      plot.title    = element_text(face = "bold"),
      legend.position = "bottom"
    )
}

# Pre-campaign plot
plot_precampaign <- make_vote_plot(
  polls_precampaign,
  title    = "Ontario Vote Intention — Pre-Campaign Period",
  subtitle = "Polling trends by party (before campaign start)"
)

# Campaign plot
plot_campaign <- make_vote_plot(
  polls_campaign,
  title    = "Ontario Vote Intention — Campaign Period",
  subtitle = "Polling trends by party (campaign period)"
)

# Display both
plot_precampaign
plot_campaign

# Optionally save both
ggsave(here("Plots/vote_intention_precampaign.png"), plot_precampaign, width = 8, height = 5)
ggsave(here("Plots/vote_intention_campaign.png"), plot_campaign, width = 8, height = 5)